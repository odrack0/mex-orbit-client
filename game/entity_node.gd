# Una entidad del mundo. FASE 1 del plan-cliente-3d: el nodo sigue siendo el
# MODELO logico (posicion de juego, interpolacion, reconcile, combate — nada de
# eso cambio), pero su cuerpo visual ya no es un sprite de canvas ni un
# SubViewport aislado: es un Node3D en la ESCENA UNICA (Mundo3D), como el
# original. Con malla GLB si el asset la tiene; sin malla, el cuerpo queda VACIO
# (invisible) hasta tenerla: el PNG tumbado murio con la calidad por niveles
# (1-sep-2026, ver el README: "Calidad grafica").
#
# El HUD (nombre + barras + marcador) vive en la capa 2D del mundo y se
# reposiciona proyectando la posicion 3D a pantalla: tamanio constante, como el
# original. Sus PARTICULARIDADES siguen saliendo del JSON en data/.
class_name EntityNode
extends Node2D

## Giro del cliente 3D original (G§5.2): ease de ~0.2 s por el camino corto,
## CONTINUO — la cuantizacion de 32 pasos era el look del cliente 2D y murio
## con el. Zona muerta para no vibrar persiguiendo el cursor.
const TURN_TIME := 0.2
const DEAD_ZONE := 2.0

## Giro al EMPRENDER VUELO de los bichos: la proa va delante SIEMPRE (ver
## "La proa va delante" en el README).
const TURN_FLIGHT_DEG_PER_SEC := 420.0

## BANKING (G§5.2): el alabeo ES el error angular pendiente del giro. Ahora es
## alabeo REAL del cuerpo 3D — con la camara a 45 grados se ve de verdad.
const BANK_MAX := 20.0
const BANK_EASE := 0.2
const BANK_COMBAT_GAIN := -2.0
const BANK_COMBAT_MAX := 10.0
const BANK_COMBAT_EASE := 0.08

## FLOTACION idle (G§5.3): Lissajous del cuerpo, solo parada, fase propia,
## fundido 0.5 s. En 3D la componente vertical es altura DE VERDAD.
const HOVER_AMP := 5.0
const HOVER_CICLO := 2.0

## Llama al ralenti (G§6.2): jugador parado 0.7, NPC 0, en vuelo 1.
const FLAME_IDLE := 0.7

## El brillo emisivo acompania al casco (G§7.1): suelo a 0% de HP.
const GLOW_HP_MIN := 0.35

# barras de estado (dos: casco y escudo), en PIXELES de pantalla
const BAR_WIDTH := 60.0
const BAR_HEIGHT := 3.0
const BAR_GAP := 5.0

## La capa 2D donde vive el HUD de las entidades (la fija el mundo al arrancar).
static var hud_layer: Node2D

var entity_id := 0
var type_id := ""            # el code del catalogo: "vex", "vexor", "skarn", "phoenix"
var speed := 0.0
var goal := Vector2.ZERO
var is_hero := false
var is_npc := false
var click_radius := 42.0
## Giro: velocidad angular (>0 = bicho, giro continuo a su peso;
## 0 = nave, ease fijo TURN_TIME del original 3D).
var turn_deg_per_sec := 0.0
## Objetivo de ataque: mientras exista GOBIERNA el rumbo (prioridad del
## original: objetivo de ataque > destino de vuelo), incluso con la nave quieta.
var attack_target: EntityNode = null
## Segundos que le quedan al rumbo DEDUCIDO de los disparos (0 = no caduca).
var _attack_ttl := 0.0
## Correccion de `reconcile()` pendiente de absorber (ver _process_correccion):
## el eco del server llega en un mensaje de red, fuera del ritmo de fotogramas,
## y aplicar el ajuste de golpe ahi mismo era un salto real en un solo frame
## disfrazado de "lerp suave". Se guarda el vector completo y se reparte en el
## tiempo, frame a frame, como el giro y el banking.
var _correction := Vector2.ZERO
## Donde cree el SERVER que esta este bicho (extrapolacion lineal). La posicion
## visual la persigue; ver el comentario grande en _process.
var _shadow := Vector2.ZERO
## A este atraso de la sombra, el gas extra llega a +100%; girando, el deficit
## se estabiliza aqui. Bajo el snap de 220 de reconcile a proposito.
const CATCHUP_DIST := 150.0
## Tope del acelerador persiguiendo la sombra, en multiplos de la velocidad.
const CATCHUP_MAX := 1.4

## La definicion del JSON se guarda: al cambiar la calidad hay que rehacer la
## parte visual sin volver a pedirle nada al server.
var _def := {}

# ---- cuerpo 3D (vive en Mundo3D, no bajo este nodo) ----
var _body: Node3D              # raiz: lleva la POSICION en el mundo
var _spin3d: Node3D              # hija: lleva rumbo + banking + hover
var _model: Node3D              # la malla GLB, o null mientras llega por el hilo
var _mats_3d: Array[BaseMaterial3D] = []
var _lava_3d: Array[ShaderMaterial] = []
var _bones_3d := {}
var _body_scale := 1.0        # unidades de mundo por unidad de modelo/pixel

# ---- HUD 2D (vive en capa_hud, proyectado cada frame) ----
var _hud: Node2D
## La proyeccion que produjo el ultimo snap del HUD (ver sincronizar_hud).
var _hud_sp := Vector2.INF
var _entry_name: Label
var _hp: ColorRect
var _shield: ColorRect
var _hp_pct := 1.0
var _shield_pct := 0.0
var _selected := false
var _sel_k := 1.0                # cierre del marcador de seleccion (1.5 -> 1)
var max_hp_abs := 0
var max_shield_abs := 0

var _visual_angle := 0.0          # grados de pantalla de la proa
var _idle_timer := 0.0
var _visual_target := 0.0         # a donde va el giro en curso (fuente del banking)
## Velocidad angular EFECTIVA del giro en curso: 0 = naves, ease a TURN_TIME
## sin importar la magnitud; >0 = velocidad angular constante (bichos).
var _turn_vel := 0.0
var _roll := 0.0
var _hover_phase := 0.0
var _hover_gain := 0.0
var _frozen := false           # engancha el autotest: cuerpo inmovil al medir
## GLB pidiendose en un hilo (carga asincrona); "" = nada pendiente.
var _glb_pending := ""
static var _glb_cache := {}
static var _glb_requested := {}
## Cache de SpriteFrames de los FX de impacto (inmutables, se comparten).
static var _sheets := {}

# motores: el thruster de PARTICULAS del original (thruster.awp: 40 bolas
# aditivas billboard a popa, vel 5-6 / accel 15-20 en unidades de su bola de
# 8, encogiendo 1->0.2 en 1 s) tenido con el AZUL del trail de cada nave.
# Es la solucion del DO 3D y la unica que sobrevive el zoom a la popa: se
# probaron quad fijo (plano), cruz (triangulos), hoja axial (linea de
# refilon), discos y un cono con shader (donas blancas visto desde atras) —
# toda geometria orientada fracasa visto a lo largo del chorro; las bolas
# billboard llenan la campana desde cualquier angulo.
var _flames: Array[GPUParticles3D] = []
var _thrust := 0.0
static var _pm_flames := {}          # ParticleProcessMaterial por color de trail
static var _flame_mesh_cache: QuadMesh

## Diales del cuerpo articulado (alas/cola/cuernos/brazos), POR ESPECIE via
## JSON; los defaults se midieron con el Vexor. Sin cambios respecto a la era
## de viewports: el esqueleto es el mismo, solo cambio DONDE vive la malla.
var _wings_deg := 34.0
var _wings_cycle := 2.17
var _wings_axis := 1
var _tail_deg := 9.0
var _tail_cycle := 1.50
var _tail_phase := 0.22
var _tail_axis := 2
var _arms_count := 0
var _arms_deg := 0.0
var _arms_cycle := 2.4
var _arms_phase := 0.125
var _arms_axis := 2
var _horns_min := 0.0
var _horns_max := 0.0
var _horns_axis := 1

# pulso emisivo (materiales del GLB)
var _pulse_min := 0.2
var _pulse_max := 2.4
var _pulse_speed := 2.6
var _pulse_sharp := 2.8

# bocas de canion (espacio LOCAL del cuerpo, unidades de mundo) y a cual toca
var _cannons: Array[Vector2] = []
var _current_cannon := 0
var _hull_impacts := 0        # tope del original: 5 simultaneos
var _shield_impacts := 0       # tope del original: 9


func setup(spawn, hero: bool) -> void:   # spawn: MexProtocol.EntitySpawn
	# Las entidades son HIJAS de World (world.gd add_child), y Godot procesa
	# el _process del PADRE antes que el de los hijos por defecto — asi que
	# world.gd leia `_hero.position` para la camara ANTES de que el heroe
	# actualizara su propia posicion ESTE fotograma: la camara siempre iba un
	# fotograma detras del heroe, y con la camara inclinada 45 grados ese
	# rezago se proyecta sobre todo en el eje VERTICAL de pantalla — el
	# nombre y las barras (fijos a `position`, iguales para todos) se veian
	# "moverse segun el movimiento de la nave" (reportado 1-sep). Prioridad
	# negativa: las entidades procesan ANTES que World, la camara siempre ve
	# la posicion YA fresca de este fotograma.
	process_priority = -10
	entity_id = spawn.entity_id
	is_hero = hero
	is_npc = spawn.kind == MexProtocol.EntityKind.NPC
	type_id = spawn.type_id
	speed = float(spawn.speed)
	position = Vector2(spawn.x, spawn.y)
	_shadow = position
	goal = position
	_idle_timer = 2.0 + randf() * 5.0
	_hover_phase = randf() * TAU
	_hp_pct = spawn.hp_pct

	var d := AssetDefs.entity(spawn.type_id)
	click_radius = float(d.get("click_radius", 42))
	turn_deg_per_sec = float(d.get("turn", {}).get("deg_per_sec", 0.0))

	_def = d
	_build_visual()
	_mount_cannons_json()
	_build_hud(d, hero, spawn)


## Todo lo que depende de la CALIDAD vive aqui, para poder rehacerlo en caliente.
## Construye el cuerpo 3D en la escena unica: la malla GLB, en TODOS los niveles
## — la calidad ya no cambia que es una nave, solo cuanto cuesta (luces, llamas,
## emision). Sin `modelo` en el JSON, o mientras el GLB llega por el hilo, el
## cuerpo queda vacio: la entidad existe (HUD, click, combate) pero no se ve.
## Decision del 1-sep: el PNG tumbado se retiro entero en vez de dejarlo de
## respaldo — un respaldo que nadie mira es la forma de que seis especies se
## queden sin malla para siempre.
func _build_visual() -> void:
	var d := _def
	_body = Node3D.new()
	_spin3d = Node3D.new()
	_body.add_child(_spin3d)
	Stage3D.instance.add_child(_body)
	_body.position = Vector3(position.x, 0.0, position.y)
	if str(d.get("modelo", "")) != "":
		_build_mesh_3d(d)


## El cuerpo como MALLA en la escena unica. Ya no hay SubViewport ni camara por
## bicho: la luz, el encuadre y la perspectiva los pone la camara del mundo.
## Devuelve false si el GLB aun no esta (se pide en hilo; el cuerpo espera vacio).
func _build_mesh_3d(d: Dictionary) -> bool:
	var path := str(d["modelo"])
	var scene: PackedScene = _glb_cache.get(path)
	if scene == null:
		if not _glb_requested.has(path):
			if ResourceLoader.load_threaded_request(path) != OK:
				push_warning("EntityNode: no se pudo pedir %s; el cuerpo se queda vacio" % path)
				return false
			_glb_requested[path] = true
		_glb_pending = path
		return false

	_model = scene.instantiate()
	_spin3d.add_child(_model)
	# El modelo mide sus unidades; el mundo pide `screen_size` UNIDADES DE JUEGO
	# (la escala 1:1 heredada: 141 px del sprite = 141 u del mundo).
	var ext := AssetDefs.extent_3d(_model)
	_body_scale = float(d.get("screen_size", 141)) / ext
	_model.scale = Vector3.ONE * _body_scale

	_bones_3d = _map_bones(_model)
	_mats_3d = AssetDefs.materials_3d(_model)
	# LAVA QUE VIAJA (`lava` en el JSON): pase aditivo como next_pass, igual que
	# en la era de viewports — el material es el mismo.
	# `emissive` 0 = emision FIJA: ni lava que viaja ni pulso (el pulso se
	# anula dejando min = max; el bucle de _process sigue, pero escribe 1.0)
	var lv: Dictionary = d.get("lava", {}) if Quality.level("emissive") >= 1 else {}
	if not lv.is_empty():
		for mat in _mats_3d:
			if mat.emission_texture == null:
				continue
			var sm := ShaderMaterial.new()
			sm.shader = load("res://game/shaders/lava_flujo.gdshader")
			sm.set_shader_parameter("emisiva", mat.emission_texture)
			sm.set_shader_parameter("cantidad", float(lv.get("amount", 1.5)))
			sm.set_shader_parameter("escala", float(lv.get("scale", 4.0)))
			sm.set_shader_parameter("velocidad", float(lv.get("speed", 0.25)))
			mat.next_pass = sm
			_lava_3d.append(sm)
	var pulse_def: Dictionary = d.get("pulse", {})
	_pulse_min = float(pulse_def.get("min_intensity", 0.25))
	_pulse_max = float(pulse_def.get("max_intensity", 2.6))
	_pulse_sharp = float(pulse_def.get("sharpness", 2.4))
	if Quality.level("emissive") == 0:
		_pulse_min = 1.0
		_pulse_max = 1.0
	var cg: Array = d.get("cuernos_grados", [])
	if cg.size() == 2:
		_horns_min = float(cg[0])
		_horns_max = float(cg[1])
	_horns_axis = int(d.get("cuernos_eje", 1))
	_arms_count = 0
	while _bones_3d.has("brazo_%d" % (_arms_count + 1)):
		_arms_count += 1
	var br: Dictionary = d.get("brazos", {})
	_arms_deg = float(br.get("grados", 0.0))
	_arms_cycle = float(br.get("ciclo", _arms_cycle))
	_arms_phase = float(br.get("desfase", 1.0 / maxf(float(_arms_count), 1.0)))
	_arms_axis = int(br.get("eje", _arms_axis))
	var wings_def: Dictionary = d.get("alas", {})
	_wings_deg = float(wings_def.get("grados", _wings_deg))
	_wings_cycle = float(wings_def.get("ciclo", _wings_cycle))
	_wings_axis = int(wings_def.get("eje", _wings_axis))
	var co_: Dictionary = d.get("cola", {})
	_tail_deg = float(co_.get("grados", _tail_deg))
	_tail_cycle = float(co_.get("ciclo", _tail_cycle))
	_tail_phase = float(co_.get("desfase", _tail_phase))
	_tail_axis = int(co_.get("eje", _tail_axis))

	# LUZ DEL HEROE (G§7.2): en la escena unica por fin DERRAMA sobre los
	# vecinos, como el original — radio 450 unidades de mundo, tal cual.
	# Solo con luces dinamicas encendidas (clave `luces` de la calidad, F2).
	if is_hero and Quality.level("luces") >= 1:
		var hero_light := OmniLight3D.new()
		hero_light.light_color = AssetDefs.HERO_LIGHT_COLOR
		hero_light.light_energy = AssetDefs.HERO_LIGHT_ENERGY
		hero_light.position = Vector3(0.0, 40.0, 0.0)
		hero_light.omni_range = 450.0
		hero_light.shadow_enabled = false
		_body.add_child(hero_light)

	# anclajes tobera_*/canon_* del GLB, ahora en el espacio REAL del cuerpo
	_mount_anchors(d)
	return true


## Marcadores del GLB -> llamas y bocas en unidades de MUNDO, en el espacio
## local del cuerpo que gira. Los disparos salen de los caniones reales incluso
## con banking, porque el marcador vive EN el modelo (G§6.1).
func _mount_anchors(d: Dictionary) -> void:
	var muzzle_width := 0.0
	var nozzles: Array[Vector3] = []
	var cannons: Array[Vector2] = []
	for n in _model.find_children("*", "Node3D", true, false):
		var entry_name := str(n.name)
		if not (entry_name.begins_with("tobera") or entry_name.begins_with("canon")):
			continue
		var p := _position_in_model(n as Node3D) * _body_scale
		if entry_name.begins_with("tobera"):
			nozzles.append(Vector3(p.x, p.y + 1.0, p.z))
			muzzle_width = maxf(muzzle_width, (n as Node3D).scale.x * _body_scale)
		else:
			cannons.append(Vector2(p.x, p.z))
	if not cannons.is_empty():
		cannons.sort_custom(func(a, b): return a.x < b.x)
		_cannons = cannons
	# `engine` 0 = solo el heroe: un emisor por NPC es lo unico que escala
	# con 54 bichos (el original tambien lo reservaba a HIGH)
	if not nozzles.is_empty() and (is_hero or Quality.level("engine") >= 1):
		nozzles.sort_custom(func(a, b): return a.x < b.x)
		var scale_factor := muzzle_width / 20.0 if muzzle_width > 0.0 else 1.0
		var trail: Dictionary = d.get("engine_trail", {})
		for point in nozzles:
			# el marcador esta en el FILO de salida y el disco de emision va
			# exactamente ahi: el medio ancho hacia proa era del quad viejo y
			# hacia nacer las particulas DENTRO de la campana, "de arriba"
			_create_flame_at(point, trail, scale_factor)


func _position_in_model(n: Node3D) -> Vector3:
	var t := Vector3.ZERO
	var cur: Node = n
	while cur != null and cur != _model:
		if cur is Node3D:
			t += (cur as Node3D).position
		cur = cur.get_parent()
	return t


func _map_bones(node: Node) -> Dictionary:
	var skels := node.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return {}
	var sk: Skeleton3D = skels[0]
	# Se mapea lo que el ESQUELETO trae, no una lista fija (leccion del Vorax).
	var map_data := {"sk": sk}
	for idx in sk.get_bone_count():
		map_data[sk.get_bone_name(idx)] = {"i": idx,
			"rest": sk.get_bone_rest(idx).basis.get_rotation_quaternion()}
	return map_data


func _set_bone(entry_name: String, axis: int, ang: float) -> void:
	if not _bones_3d.has(entry_name):
		return
	var h: Dictionary = _bones_3d[entry_name]
	var v := Vector3.UP if axis == 1 else (Vector3.BACK if axis == 2 else Vector3.RIGHT)
	_bones_3d["sk"].set_bone_pose_rotation(h["i"],
		(h["rest"] as Quaternion) * Quaternion(v, ang))


## Bocas de canion del JSON (pixeles de textura = unidades de mundo). Solo si
## el camino 3D no las puso ya del modelo, que es la fuente.
func _mount_cannons_json() -> void:
	if not _cannons.is_empty():
		return
	for cannon in _def.get("cannons", []):
		_cannons.append(Vector2(float(cannon.get("x", 0)), float(cannon.get("y", 0))))


## La llama de una tobera: GPUParticles3D con los valores del thruster.awp,
## la rampa en el color del trail de la nave (nucleo casi blanco, cola del
## color). Material por color y malla compartidos; el tamano por nave va en
## la escala del nodo (k = boca/5), que con local_coords escala bola y
## velocidades a la vez.
func _create_flame_at(point: Vector3, trail: Dictionary, scale_factor: float) -> void:
	var c := AssetDefs.color(trail.get("color", "00E5FF"))
	var key := c.to_html(false)
	if not _pm_flames.has(key):
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 0, 1)      # a popa (+Z del modelo)
		pm.spread = 4.0                      # el jitter x/y +-1 del awp
		# nacen repartidas por el DISCO plano de la boca (anillo de radio
		# interior 0), no en un punto ni en una esfera: con k = boca/5 el
		# radio de la boca en unidades del emisor es 2.5, y el disco delgado
		# en el plano del filo hace que el chorro arranque JUSTO en el aro
		# encendido, no desde dentro de la campana
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3(0, 0, 1)
		pm.emission_ring_radius = 2.5
		pm.emission_ring_inner_radius = 0.0
		pm.emission_ring_height = 0.4
		pm.initial_velocity_min = 5.0
		pm.initial_velocity_max = 6.0
		pm.linear_accel_min = 15.0
		pm.linear_accel_max = 20.0
		pm.gravity = Vector3.ZERO
		var curve_val := Curve.new()             # escala 1 -> 0.2 sobre la vida
		curve_val.add_point(Vector2(0.0, 1.0))
		curve_val.add_point(Vector2(1.0, 0.2))
		var ct := CurveTexture.new()
		ct.curve = curve_val
		pm.scale_curve = ct
		# la rampa del awp con el color de la nave: negro -> color -> nucleo
		# casi blanco -> color -> negro (aditivo: negro = invisible)
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0))
		g.add_point(0.2, c * 0.8)
		g.add_point(0.4, c.lerp(Color.WHITE, 0.75))
		g.add_point(0.6, c.lerp(Color.WHITE, 0.75))
		g.add_point(0.8, c * 0.8)
		g.set_color(1, Color(0, 0, 0))
		var gt := GradientTexture1D.new()
		gt.gradient = g
		pm.color_ramp = gt
		_pm_flames[key] = pm
	if _flame_mesh_cache == null:
		_flame_mesh_cache = QuadMesh.new()
		_flame_mesh_cache.size = Vector2(8.0, 8.0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.vertex_color_use_as_albedo = true
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.albedo_texture = load("res://assets/fx/simple-gradient.png")
		_flame_mesh_cache.material = mat
	var flame := GPUParticles3D.new()
	flame.amount = 40
	# `engine` < 2: la mitad de las bolas, mismo penacho (amount_ratio no reinicia)
	flame.amount_ratio = 1.0 if Quality.level("engine") >= 2 else 0.5
	flame.lifetime = 1.0
	flame.preprocess = 1.0        # el penacho existe desde el primer frame
	flame.local_coords = true     # sigue a la nave, como el follow del original
	flame.process_material = _pm_flames[key]
	flame.draw_pass_1 = _flame_mesh_cache
	flame.position = point
	# k por nave: la bola de 8 del original sale de una boca de ~5 (la
	# cobertura de la boca la pone el emission_shape, no el tamano de bola)
	flame.set_meta("k", scale_factor * 20.0 / 5.0)
	_spin3d.add_child(flame)
	_flames.append(flame)


## Rehace la parte visual con la calidad actual. El HUD, el rumbo y el estado
## no dependen del nivel y se quedan como estan.
func rebuild() -> void:
	if _body != null:
		_body.queue_free()
	_body = null
	_spin3d = null
	_model = null
	_mats_3d.clear()
	_lava_3d.clear()
	_bones_3d.clear()
	_flames.clear()
	_cannons.clear()
	_build_visual()
	_mount_cannons_json()
	_set_visual_angle(_visual_angle)


func _exit_tree() -> void:
	# el cuerpo vive en Mundo3D y el HUD en su capa: se van con la entidad
	if _body != null:
		_body.queue_free()
	if _hud != null:
		_hud.queue_free()


## El HUD 2D: nombre y barras en PIXELES de pantalla, sobre la capa del mundo,
## reposicionado cada frame proyectando la posicion 3D (G§11). Tamanio
## constante a cualquier zoom, como el original.
func _build_hud(d: Dictionary, hero: bool, spawn) -> void:
	_hud = Node2D.new()
	_hud.draw.connect(_draw_marker)
	if hud_layer != null:
		hud_layer.add_child(_hud)
	else:
		add_child(_hud)
	var color := NTheme.CYAN if hero else (NTheme.TXT if not is_npc else NTheme.HOSTILE)
	# El offset era una constante fija (-52/+44), calibrada de ojo contra ALGUNA
	# especie: para la Phoenix (screen_size 141, medio-cuerpo ~70) la barra
	# caia DENTRO de la silueta del casco, casi tocandolo — reportado 31-ago
	# como "las barras brincan", que en realidad era la MISMA nave (el ligero
	# vaiven del banking, el borde del modelo) leyendose contra un vecino
	# demasiado pegado. Proporcional al medio-cuerpo real de CADA nave/bicho
	# mas un margen fijo de aire: nunca vuelve a caer dentro de la silueta,
	# sea cual sea la especie.
	const CLEARANCE := 14.0
	var half_body := float(d.get("screen_size", 141)) * 0.5
	_entry_name = NTheme.label(spawn.name, NTheme.exo2(), 12, color)
	_entry_name.position = Vector2(-70, half_body + CLEARANCE)
	_entry_name.custom_minimum_size = Vector2(140, 0)
	_entry_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_entry_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_entry_name.add_theme_constant_override("outline_size", 4)
	_hud.add_child(_entry_name)
	_shield_pct = clampf(spawn.shield_pct, 0.0, 1.0)
	var bar_y := -(half_body + CLEARANCE)
	_shield = _create_bar(bar_y - BAR_GAP, NTheme.SHIELD, _shield_pct)
	_hp = _create_bar(bar_y, NTheme.HP if not is_npc else NTheme.HOSTILE, _hp_pct)


func _create_bar(y: float, color: Color, pct: float) -> ColorRect:
	var hint := ColorRect.new()
	hint.color = Color(0, 0, 0, 0.55)
	hint.position = Vector2(-BAR_WIDTH * 0.5 - 1, y - 1)
	hint.size = Vector2(BAR_WIDTH + 2, BAR_HEIGHT + 2)
	_hud.add_child(hint)
	var bar := ColorRect.new()
	bar.color = color
	bar.position = Vector2(-BAR_WIDTH * 0.5, y)
	bar.size = Vector2(BAR_WIDTH * pct, BAR_HEIGHT)
	_hud.add_child(bar)
	return bar


func _process(delta: float) -> void:
	# el GLB pedido en hilo: al llegar, el cuerpo se sube a malla
	if _glb_pending != "":
		_serve_glb()
	if _body == null:
		return

	# recorte de delta: un frame trabado (una malla pesada, una pausa del SO)
	# no debe traducirse en un SALTO de posicion. move_toward()/_shadow usan
	# `vel * delta` sin tope, asi que un delta disparado hace que la sombra
	# autoritativa avance de golpe y la posicion la persiga en un solo frame
	# — se ve como un brinco, y como el HUD proyecta la MISMA `position`
	# (linea 672), las barras brincan con el cuerpo. El recorte a 1/15 s
	# (66 ms, tres frames a 45 fps) deja el movimiento en pausa esa fraccion
	# de segundo en vez de teletransportarlo.
	delta = minf(delta, 1.0 / 15.0)

	var in_flight := position.distance_to(goal) > 0.5

	# acelerador: el empuje sube en vuelo y cae al frenar; parada, la nave de
	# jugador queda al RALENTI y el NPC apaga (G§6.2)
	if not _flames.is_empty():
		var thrust_goal := 1.0 if in_flight else (0.0 if is_npc else FLAME_IDLE)
		if _thrust < thrust_goal:
			_thrust = minf(_thrust + 3.0 * delta, thrust_goal)
		else:
			_thrust = maxf(_thrust - 4.0 * delta, thrust_goal)
		# el original escala el thruster entero 0/0.7/1 (lerp por frame): con
		# local_coords la escala del nodo encoge bola Y velocidades a la vez
		for flame in _flames:
			flame.visible = _thrust > 0.02
			flame.emitting = flame.visible
			var k: float = flame.get_meta("k", 1.0)
			flame.scale = Vector3.ONE * maxf(_thrust, 0.01) * k

	# ---- el cuerpo articulado (malla): aleteo, cola, brazos, destello ----
	if not _bones_3d.is_empty():
		var clock := Time.get_ticks_msec() * 0.001
		var phase := fposmod(entity_id * 0.618034, 1.0)
		var t := fposmod(clock / _wings_cycle + phase, 1.0)
		var bat := deg_to_rad(_wings_deg) * sin(TAU * t)
		_set_bone("ala_izq", _wings_axis, -bat)
		_set_bone("ala_der", _wings_axis, bat)
		if _horns_max != _horns_min:
			var kq := 0.5 - 0.5 * cos(TAU * t)
			var pinch := deg_to_rad(_horns_min + (_horns_max - _horns_min) * kq)
			_set_bone("cuerno_izq", _horns_axis, -pinch)
			_set_bone("cuerno_der", _horns_axis, pinch)
		if _arms_deg > 0.0 and _arms_count > 0:
			var tb := clock / _arms_cycle + phase
			for k in _arms_count:
				_set_bone("brazo_%d" % (k + 1), _arms_axis,
					deg_to_rad(_arms_deg) * sin(TAU * (tb - k * _arms_phase)))
		var tc := clock / _tail_cycle + phase
		for k in 3:
			_set_bone("cola_%d" % (k + 1), _tail_axis,
				deg_to_rad(_tail_deg) * sin(TAU * (tc - k * _tail_phase)))
		if not _mats_3d.is_empty():
			var wave3 := pow(0.5 - 0.5 * cos(TAU * t), _pulse_sharp)
			var e: float = _pulse_min + (_pulse_max - _pulse_min) * wave3
			e *= lerpf(GLOW_HP_MIN, 1.0, _hp_pct)
			for mat in _mats_3d:
				mat.emission_energy_multiplier = e
			for sm in _lava_3d:
				sm.set_shader_parameter("intensidad", e)

	# ---- movimiento (modelo, sin cambios) ----
	if in_flight:
		if turn_deg_per_sec > 0.0:
			# LA SOMBRA AUTORITATIVA (ver README): el server vuela lineal a
			# velocidad plena; el freno de proa es presentacion y el deficit
			# empuja el gas para que la divergencia no se cobre de golpe.
			_shadow = _shadow.move_toward(goal, speed * delta)
			var factor := maxf(cos(deg_to_rad(_bow_error(goal))), 0.0)
			var deficit := position.distance_to(_shadow)
			var vel := speed * clampf(factor + deficit / CATCHUP_DIST, 0.0, CATCHUP_MAX)
			position = position.move_toward(_shadow, vel * delta)
		else:
			position = position.move_toward(goal, speed * delta)
	_process_correction(delta)

	if attack_target != null and not is_instance_valid(attack_target):
		attack_target = null
	if attack_target != null and _attack_ttl > 0.0:
		_attack_ttl -= delta
		if _attack_ttl <= 0.0:
			attack_target = null
	if attack_target != null:
		_face_towards(attack_target.position)
	elif not in_flight and is_npc:
		# NPCs parados: giro perezoso aleatorio cada 2-7 s (vida del original)
		_idle_timer -= delta
		if _idle_timer <= 0.0:
			_idle_timer = 2.0 + randf() * 5.0
			_turn_to(_visual_angle + (randf() - 0.5) * 360.0)

	# ---- sincronia del cuerpo 3D (el HUD se proyecta aparte, ver abajo) ----
	_body.position = Vector3(position.x, 0.0, position.y)
	if not _frozen:
		_process_turn(delta)
	if turn_deg_per_sec == 0.0 and not _frozen:
		_process_banking(delta, in_flight)
		_process_hover(delta, in_flight)


## Proyecta el HUD (nombre/barras) a pantalla. NO va dentro de `_process`: el
## render 3D usa lo que quede al FINAL del fotograma (siempre consistente,
## por eso la nave dejo de brincar con la prioridad -10), pero `a_pantalla`
## lee la camara AL MOMENTO de llamarse — y `Mundo3D.actualizar()` corre en
## World, un nodo aparte. Cualquier orden fijo entre nodos deja a uno de los
## dos lados (posicion o camara) leyendo el valor de ANTES de actualizarse
## este fotograma. La unica manera de que ambos esten frescos A LA VEZ es que
## World llame esto EXPLICITAMENTE, justo despues de mover la camara —
## reportado 1-sep: la nave dejo de brincar con la prioridad, pero el nombre
## y las barras seguian, porque quedaron del lado que ahora leia viejo.
func sync_hud() -> void:
	if _hud != null and Stage3D.instance != null:
		var sp := Stage3D.instance.to_screen(position)
		# HISTERESIS del snap (1-sep): el heroe cae SIEMPRE en el mismo punto
		# de pantalla —el centro, un entero exacto— y la matriz de proyeccion
		# lo devuelve con ruido de ~1e-6 distinto en cada frame en que la camara
		# se recalcula (moverse, zoom). `floor()` a secas alternaba 684/685 y
		# 359/360: un temblor de 1 px de nombre y barras que solo tenia el heroe
		# (los NPC nunca se quedan en una frontera) y que aparecia incluso
		# parado, con la rueda del zoom. Solo se re-snapea si la proyeccion se
		# movio DE VERDAD; el ruido ya no cruza la frontera.
		if _hud_sp == Vector2.INF or sp.distance_to(_hud_sp) > 0.05:
			_hud_sp = sp
			_hud.position = sp.floor()


func _serve_glb() -> void:
	if _glb_cache.has(_glb_pending):
		_glb_pending = ""
		rebuild()
		return
	var st := ResourceLoader.load_threaded_get_status(_glb_pending)
	if st == ResourceLoader.THREAD_LOAD_LOADED:
		_glb_cache[_glb_pending] = ResourceLoader.load_threaded_get(_glb_pending)
		_glb_pending = ""
		rebuild()
	elif st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		push_warning("EntityNode: fallo la carga en hilo de %s; el cuerpo se queda vacio"
			% _glb_pending)
		_glb_pending = ""


## BANKING real (G§5.2): el alabeo persigue al error angular pendiente con el
## ease incremental del original. Se aplica al cuerpo entero (la malla)
## alrededor de su eje longitudinal, y con la camara a 45 grados SE VE.
func _process_banking(delta: float, in_flight: bool) -> void:
	var error := fposmod(_visual_target - _visual_angle + 180.0, 360.0) - 180.0
	var roll_goal: float
	var d: float
	if in_flight and attack_target != null:
		roll_goal = clampf(error * BANK_COMBAT_GAIN,
			-BANK_COMBAT_MAX, BANK_COMBAT_MAX)
		d = BANK_COMBAT_EASE
	else:
		roll_goal = clampf(error, -BANK_MAX, BANK_MAX)
		d = BANK_EASE
	var k := minf(1.0, (delta / d) * (2.0 - delta / d))
	_roll += (roll_goal - _roll) * k
	_apply_orientation()


## FLOTACION idle: en 3D la componente vertical es altura de verdad (el
## original flotaba 0..5 unidades hacia arriba, G§5.3).
func _process_hover(delta: float, in_flight: bool) -> void:
	_hover_gain = move_toward(_hover_gain, 0.0 if in_flight else 1.0, 2.0 * delta)
	if _spin3d == null:
		return
	if _hover_gain <= 0.0:
		_spin3d.position = Vector3.ZERO
		return
	_hover_phase += delta / HOVER_CICLO
	var a := _hover_phase
	_spin3d.position = Vector3(sin(a) * cos(a), pow(sin(a), 2.0),
		sin(a * 1.13) * cos(a * 0.87)) * (HOVER_AMP * _hover_gain)


## Rumbo + alabeo compuestos sobre el cuerpo: primero la guiniada, luego el
## roll alrededor del eje longitudinal (la proa mira a -Z a giro 0).
func _apply_orientation() -> void:
	if _spin3d == null:
		return
	_spin3d.basis = Basis(Vector3.UP, -deg_to_rad(_visual_angle)) \
		* Basis(Vector3.BACK, deg_to_rad(_roll))


func set_attack_target(attack_goal: EntityNode, seconds := 0.0) -> void:
	attack_target = attack_goal
	_attack_ttl = seconds
	if attack_target != null and is_instance_valid(attack_target):
		_face_towards(attack_target.position)


## El vector punto-position es la DIRECCION que se convierte en rumbo — y la
## direccion de un vector casi nulo es numericamente inestable: cualquier
## ruido minusculo en el clic (o en la posicion propia) lo hace girar al
## azar, no un poco. El guardia viejo (> 1.0) es trivial de cruzar con un
## clic normal SOBRE la nave — y ahi es exactamente donde el usuario reporto
## que el "brinco" se intensifica (31-ago). `click_radius` ya es "que tan
## cerca cuenta como clicar la nave"; reusarlo aqui es el mismo criterio:
## dentro de ese circulo, la direccion no es confiable y no vale la pena
## recalcular el rumbo.
func _face_towards(point: Vector2) -> void:
	var heading := point - position
	if heading.length() > click_radius:
		_turn_to(_visual_angle_towards(point),
			TURN_FLIGHT_DEG_PER_SEC if turn_deg_per_sec > 0.0 else 0.0)


func _visual_angle_towards(point: Vector2) -> float:
	return rad_to_deg((point - position).angle()) + 90.0


func _bow_error(point: Vector2) -> float:
	return absf(fposmod(_visual_angle_towards(point) - _visual_angle + 180.0, 360.0) - 180.0)


func set_goal(dest: Vector2) -> void:
	var in_flight := position.distance_to(goal) > 0.5
	if in_flight and absf(dest.x - position.x) <= DEAD_ZONE \
			and absf(dest.y - position.y) <= DEAD_ZONE:
		goal = dest
		return
	goal = dest
	if attack_target != null and is_instance_valid(attack_target):
		return
	_face_towards(dest)


## Giro. Dos modelos, como siempre — lo que cambio con la Fase 1 es la NAVE:
## - NAVES (turn_deg_per_sec = 0): ease de TURN_TIME (0.2 s) por el camino
##   corto, CONTINUO — el giro del cliente 3D original. La cuantizacion de 32
##   pasos era el look del sheet 2D y murio con el mundo de sprites.
## - BICHOS (turn_deg_per_sec > 0): velocidad angular constante, su peso.
##
## Solo fija el OBJETIVO — no anima nada aqui. `_process_giro` (por frame,
## como el banking) hace la integracion. Antes esto mataba y recreaba un
## Tween en cada llamada: con "mantener presionado para volar" reenviando el
## rumbo cada 0.25 s (world.gd HOLD_RESEND_SEC), cada pequenio ajuste del
## cursor reiniciaba el EASE_OUT desde cero — la nave nunca llegaba a la cola
## suave de la curva, solo veia el arranque brusco una y otra vez, y eso se
## leia como una VIBRACION continua de proa (reportada 31-ago). El banking ya
## resolvia esto mismo con una integracion incremental por frame, robusta a
## un objetivo que se mueve; el giro pasa al mismo patron.
## Zona muerta angular: el error de proa amplifica cualquier temblor de
## posicion del objetivo en un giro de rumbo mucho mayor cuanto mas cerca
## esta — 5 unidades laterales a 1000 de distancia son 0.3 grados, mismas
## 5 unidades a 50 de distancia son 5.7 grados, 20x mas sensible. `_encarar`
## llama a `_girar_a` TODO fotograma mientras hay attack_target, asi que en
## combate cuerpo a cuerpo ese ruido se recalcula 60 veces por segundo.
## Reportado 31-ago: "brinco" solo en clics/combate cerca de la nave, nunca
## lejos. Si el rumbo nuevo esta a menos de esto del YA comandado, se ignora.
const HEADING_NOISE_DEG := 1.5

func _turn_to(degrees: float, dps := 0.0) -> void:
	var dest_angle := fposmod(degrees, 360.0)
	var vs_commanded := fposmod(dest_angle - _visual_target + 180.0, 360.0) - 180.0
	if absf(vs_commanded) < HEADING_NOISE_DEG:
		return
	var delta := fposmod(dest_angle - _visual_angle + 180.0, 360.0) - 180.0
	_visual_target = fposmod(_visual_angle + delta, 360.0)
	_turn_vel = dps if dps > 0.0 else turn_deg_per_sec


## Un frame de giro: NAVES easean con la misma formula del banking (siempre
## converge, nunca "reinicia" — un _visual_target nuevo a medio camino solo
## redirige la curva); BICHOS avanzan a velocidad angular constante.
func _process_turn(delta: float) -> void:
	var error := fposmod(_visual_target - _visual_angle + 180.0, 360.0) - 180.0
	if is_zero_approx(error):
		return
	if _turn_vel > 0.0:
		var step := _turn_vel * delta
		_set_visual_angle(_visual_angle + clampf(error, -step, step))
	else:
		var k := minf(1.0, (delta / TURN_TIME) * (2.0 - delta / TURN_TIME))
		_set_visual_angle(_visual_angle + error * k)


## Fija el rumbo VISUAL en el acto (enganche del autotest).
func visual_heading(degrees: float) -> void:
	_visual_target = fposmod(degrees, 360.0)
	_turn_vel = 0.0
	_set_visual_angle(degrees)


func _set_visual_angle(degrees: float) -> void:
	_visual_angle = fposmod(degrees, 360.0)
	_apply_orientation()


## En la escena unica TODO cuerpo es 3D.
func is_3d() -> bool:
	return true


## El relieve murio con los sprites: la luz fija sobre un cuerpo que gira es
## gratis por construccion en la escena unica.
func has_relief() -> bool:
	return false


func visual_angle() -> float:
	return _visual_angle


## Enganche del autotest: cuerpo inmovil y a neutro mientras se mide.
func hull_only(is_active: bool) -> void:
	_frozen = is_active
	if is_active and _spin3d != null:
		_spin3d.position = Vector3.ZERO
		_roll = 0.0
		_apply_orientation()
	if _hud != null:
		_hud.visible = not is_active
	for flame in _flames:
		flame.visible = not is_active and _thrust > 0.02


## Eco autoritativo del server: correccion suave si la deriva es chica, snap si es grande.
##
## El SNAP se queda instantaneo a proposito — es la deriva grande, se ve
## igual sea de golpe o repartida, y encima quitarlo tapa un teleport real. La
## deriva CHICA es la que cambio: antes `position.lerp(server_pos, 0.35)` se
## aplicaba aqui mismo, en el mensaje de red, FUERA del ritmo de fotogramas —
## un salto real del 35% del error en un solo frame, disfrazado de "suave"
## por el nombre del metodo. Con reconcile() disparando en cada Move del
## server (cada clic corto genera varios, muy seguidos) eso se leia como
## brinco constante — reportado 31-ago junto al de la camara. Ahora solo se
## GUARDA el vector completo; `_process_correccion` lo reparte de verdad, en
## el tiempo, frame a frame.
func reconcile(x: float, y: float, tx: float, ty: float, new_vel: float, teleport: bool) -> void:
	speed = new_vel
	var server_pos := Vector2(x, y)
	if turn_deg_per_sec > 0.0:
		_shadow = server_pos
		if teleport or position.distance_to(server_pos) > 500.0:
			position = server_pos
			_correction = Vector2.ZERO
	elif teleport or position.distance_to(server_pos) > 220.0:
		position = server_pos
		_correction = Vector2.ZERO
	else:
		# El eco del server SIEMPRE llega mostrando donde estabas hace un
		# instante (round-trip), no donde estas ya — un drift de latencia
		# normal, no un error. Reportado 31-ago: durante hold-drag el reenvio
		# cada 0.25 s (world.gd HOLD_RESEND_SEC) genera un RECONCILE casi tan
		# seguido, con drift real (medido: 0.5-20 unidades, sin patron) —
		# _correccion nunca terminaba de asentarse antes del siguiente, y eso
		# SI se sentia como brinco constante, a diferencia de un vuelo largo
		# con pocos reenvios. Mientras la nave sigue volando de verdad
		# (en_vuelo, persiguiendo un objetivo que YA se refresca solo), el
		# drift es irrelevante — el proximo objetivo lo absorbe gratis. Solo
		# importa aplicarlo cuando la nave esta quieta o a punto de estarlo:
		# ahi si hay que llegar EXACTO a donde dice el server.
		if position.distance_to(goal) <= 0.5:
			_correction += server_pos - position
	set_goal(Vector2(tx, ty))


## Un frame de correccion: absorbe `_correccion` con la misma ease incremental
## del giro y el banking — nunca de golpe, y un reconcile nuevo a medio
## camino solo suma al vector pendiente en vez de reiniciar nada.
const CORRECTION_TIME := 0.3
func _process_correction(delta: float) -> void:
	if _correction.is_zero_approx():
		return
	var k := minf(1.0, (delta / CORRECTION_TIME) * (2.0 - delta / CORRECTION_TIME))
	var step := _correction * k
	position += step
	_correction -= step


func set_hp_pct(pct: float) -> void:
	_hp_pct = clampf(pct, 0.0, 1.0)
	_hp.size.x = BAR_WIDTH * _hp_pct


func set_shield_pct(pct: float) -> void:
	_shield_pct = clampf(pct, 0.0, 1.0)
	_shield.size.x = BAR_WIDTH * _shield_pct


func set_state_abs(hp: int, shield: int) -> void:
	if max_hp_abs > 0:
		set_hp_pct(float(hp) / max_hp_abs)
	if max_shield_abs > 0:
		set_shield_pct(float(shield) / max_shield_abs)


## Boca de canion del proximo disparo, en el espacio LOCAL del cuerpo (unidades
## de mundo). El haz la rota por el rumbo VIVO cada frame — con banking y todo.
func next_local_cannon() -> Vector2:
	if _cannons.is_empty():
		return Vector2.ZERO
	var local := _cannons[_current_cannon]
	_current_cannon = (_current_cannon + 1) % _cannons.size()
	return local


## Chispazo en el casco: billboard suelto en el mundo, punto aleatorio del
## disco de click (la receta del original, intacta).
func hull_impact() -> void:
	if _hull_impacts >= 5:
		return
	_hull_impacts += 1
	var rnd := randf()
	var offset := Vector2.from_angle(rnd * TAU) * (click_radius * 0.5 * rnd)
	var anim := _sheet_anim3d("res://assets/fx/hull-impact.png", 96, 8, 0.45)
	var p := position + offset
	anim.position = Vector3(p.x, 12.0, p.y)
	Stage3D.instance.add_child(anim)
	anim.tree_exited.connect(func(): _hull_impacts -= 1)


## Onda en el escudo: sobre la circunferencia, del lado del atacante; sigue a
## la nave (hija del cuerpo).
func shield_impact(start_at: Vector2) -> void:
	if _shield_impacts >= 9:
		return
	_shield_impacts += 1
	var dir := (start_at - position).normalized()
	var anim := _sheet_anim3d("res://assets/fx/shield-impact.png", 128, 8, 0.3)
	anim.position = Vector3(dir.x * click_radius, 12.0, dir.y * click_radius)
	anim.modulate = NTheme.SHIELD
	_body.add_child(anim)
	anim.tree_exited.connect(func(): _shield_impacts -= 1)


## Un FX de hoja de fotogramas como billboard 3D. El SpriteFrames se cachea por
## hoja (inmutable, se comparte).
static func _sheet_anim3d(path: String, side: int, frames: int, duration: float) -> AnimatedSprite3D:
	var sf: SpriteFrames = _sheets.get(path)
	if sf == null:
		sf = SpriteFrames.new()
		sf.add_animation("x")
		sf.set_animation_loop("x", false)
		sf.set_animation_speed("x", frames / duration)
		var sheet: Texture2D = load(path)
		for i in frames:
			var f := AtlasTexture.new()
			f.atlas = sheet
			f.region = Rect2(i * side, 0, side, side)
			sf.add_frame("x", f)
		_sheets[path] = sf
	var anim := AnimatedSprite3D.new()
	anim.sprite_frames = sf
	anim.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	anim.shaded = false
	anim.pixel_size = 1.0
	anim.play("x")
	anim.animation_finished.connect(anim.queue_free)
	return anim


## Seleccion local: esquinas de mira en el HUD (pixeles de pantalla, tamanio
## constante). El marcador ENTRA cerrando sobre el blanco: 1.5x -> 1x en 0.3 s.
func set_selected(sel: bool) -> void:
	_selected = sel
	if sel:
		_sel_k = 1.5
		var tw := create_tween()
		tw.tween_method(_sel_step, 1.5, 1.0, 0.3) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _hud != null:
		_hud.queue_redraw()


func _sel_step(k: float) -> void:
	_sel_k = k
	if _hud != null:
		_hud.queue_redraw()


func _draw_marker() -> void:
	if not _selected or _hud == null:
		return
	var r := 44.0 * _sel_k
	var l := 14.0
	var c := NTheme.HOSTILE if not is_hero else NTheme.CYAN
	for corner in [Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)]:
		var dx := -l if corner.x > 0 else l
		var dy := -l if corner.y > 0 else l
		_hud.draw_line(corner, corner + Vector2(dx, 0), c, 2.0)
		_hud.draw_line(corner, corner + Vector2(0, dy), c, 2.0)
