# Una entidad del mundo. FASE 1 del plan-cliente-3d: el nodo sigue siendo el
# MODELO logico (posicion de juego, interpolacion, reconcile, combate — nada de
# eso cambio), pero su cuerpo visual ya no es un sprite de canvas ni un
# SubViewport aislado: es un Node3D en la ESCENA UNICA (Mundo3D), como el
# original. Con malla GLB si el asset la tiene; con su PNG/atlas tumbado en el
# plano si no — el placeholder del cliente 3D original (G§5.5).
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
const BANK_COMBATE_GANANCIA := -2.0
const BANK_COMBATE_MAX := 10.0
const BANK_COMBATE_EASE := 0.08

## FLOTACION idle (G§5.3): Lissajous del cuerpo, solo parada, fase propia,
## fundido 0.5 s. En 3D la componente vertical es altura DE VERDAD.
const HOVER_AMP := 5.0
const HOVER_CICLO := 2.0

## Llama al ralenti (G§6.2): jugador parado 0.7, NPC 0, en vuelo 1.
const LLAMA_IDLE := 0.7

## El brillo emisivo acompania al casco (G§7.1): suelo a 0% de HP.
const GLOW_HP_MIN := 0.35

# barras de estado (dos: casco y escudo), en PIXELES de pantalla
const BARRA_ANCHO := 60.0
const BARRA_ALTO := 3.0
const BARRA_SEPARACION := 5.0

## La capa 2D donde vive el HUD de las entidades (la fija el mundo al arrancar).
static var capa_hud: Node2D

var entity_id := 0
var type_id := ""            # el code del catalogo: "vex", "vexor", "skarn", "phoenix"
var speed := 0.0
var objetivo := Vector2.ZERO
var es_heroe := false
var es_npc := false
var click_radius := 42.0
## Giro: velocidad angular (>0 = bicho, giro continuo a su peso;
## 0 = nave, ease fijo TURN_TIME del original 3D).
var turn_deg_per_sec := 0.0
## Objetivo de ataque: mientras exista GOBIERNA el rumbo (prioridad del
## original: objetivo de ataque > destino de vuelo), incluso con la nave quieta.
var attack_target: EntityNode = null
## Segundos que le quedan al rumbo DEDUCIDO de los disparos (0 = no caduca).
var _attack_ttl := 0.0
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
var _cuerpo: Node3D              # raiz: lleva la POSICION en el mundo
var _giro3d: Node3D              # hija: lleva rumbo + banking + hover
var _modelo: Node3D              # la malla GLB, o null si el cuerpo es un quad
var _sprite3d: Sprite3D          # el quad tumbado (PNG o atlas), o null
var _emissive3d: Sprite3D        # capa emisiva del quad, pulsando
var _mats_3d: Array[BaseMaterial3D] = []
var _lava_3d: Array[ShaderMaterial] = []
var _huesos_3d := {}
var _escala_cuerpo := 1.0        # unidades de mundo por unidad de modelo/pixel

# ---- HUD 2D (vive en capa_hud, proyectado cada frame) ----
var _hud: Node2D
var _nombre: Label
var _hp: ColorRect
var _escudo: ColorRect
var _hp_pct := 1.0
var _shield_pct := 0.0
var _seleccionada := false
var _sel_k := 1.0                # cierre del marcador de seleccion (1.5 -> 1)
var max_hp_abs := 0
var max_shield_abs := 0

var _visual_angle := 0.0          # grados de pantalla de la proa
var _turn_tween: Tween
var _idle_timer := 0.0
var _visual_target := 0.0         # a donde va el giro en curso (fuente del banking)
var _roll := 0.0
var _hover_fase := 0.0
var _hover_gain := 0.0
var _congelado := false           # engancha el autotest: cuerpo inmovil al medir
## GLB pidiendose en un hilo (carga asincrona); "" = nada pendiente.
var _glb_pendiente := ""
static var _glb_cache := {}
static var _glb_solicitados := {}
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
static var _pm_llamas := {}          # ParticleProcessMaterial por color de trail
static var _malla_llama_cache: QuadMesh

## Diales del cuerpo articulado (alas/cola/cuernos/brazos), POR ESPECIE via
## JSON; los defaults se midieron con el Vexor. Sin cambios respecto a la era
## de viewports: el esqueleto es el mismo, solo cambio DONDE vive la malla.
var _alas_grados := 34.0
var _alas_ciclo := 2.17
var _alas_eje := 1
var _cola_grados := 9.0
var _cola_ciclo := 1.50
var _cola_desfase := 0.22
var _cola_eje := 2
var _brazos_n := 0
var _brazos_grados := 0.0
var _brazos_ciclo := 2.4
var _brazos_desfase := 0.125
var _brazos_eje := 2
var _cuernos_min := 0.0
var _cuernos_max := 0.0
var _cuernos_eje := 1

# atlas animado (cuerpo quad): mismos diales que siempre
var _anim_total := 0
var _anim_vaiven := false
var _anim_fps := 12.0
var _anim_t := 0.0

# pulso emisivo (capa del quad o materiales del GLB)
var _pulse_min := 0.2
var _pulse_max := 2.4
var _pulse_speed := 2.6
var _pulse_sharp := 2.8

# bocas de canion (espacio LOCAL del cuerpo, unidades de mundo) y a cual toca
var _canones: Array[Vector2] = []
var _canon_actual := 0
var _impactos_casco := 0        # tope del original: 5 simultaneos
var _impactos_escudo := 0       # tope del original: 9


func setup(spawn, heroe: bool) -> void:   # spawn: MexProtocol.EntitySpawn
	entity_id = spawn.entity_id
	es_heroe = heroe
	es_npc = spawn.kind == MexProtocol.EntityKind.NPC
	type_id = spawn.type_id
	speed = float(spawn.speed)
	position = Vector2(spawn.x, spawn.y)
	_shadow = position
	objetivo = position
	_idle_timer = 2.0 + randf() * 5.0
	_hover_fase = randf() * TAU
	_hp_pct = spawn.hp_pct

	var d := AssetDefs.entidad(spawn.type_id)
	click_radius = float(d.get("click_radius", 42))
	turn_deg_per_sec = float(d.get("turn", {}).get("deg_per_sec", 0.0))

	_def = d
	_construir_visual()
	_montar_canones_json()
	_construir_hud(d, heroe, spawn)


## Todo lo que depende de la CALIDAD vive aqui, para poder rehacerlo en caliente.
## Construye el cuerpo 3D en la escena unica: malla GLB en alta si el asset la
## tiene; si no (o mientras el GLB llega por el hilo), su PNG/atlas tumbado.
func _construir_visual() -> void:
	var d := _def
	_cuerpo = Node3D.new()
	_giro3d = Node3D.new()
	_cuerpo.add_child(_giro3d)
	Mundo3D.instancia.add_child(_cuerpo)
	_cuerpo.position = Vector3(position.x, 0.0, position.y)

	if Quality.nivel("npc") >= 2 and str(d.get("modelo", "")) != "":
		if _construir_malla_3d(d):
			return
	_construir_quad(d)


## El cuerpo como QUAD tumbado: el arte cenital de siempre sobre el plano del
## juego. Es el placeholder del original y el camino de media/baja y de las
## especies que aun no tienen malla.
func _construir_quad(d: Dictionary) -> void:
	var anim: Dictionary = d.get("frames", {}) if Quality.nivel("npc") >= 2 else {}
	var tex: Texture2D
	if anim.is_empty():
		tex = _textura(d.get("texture", ""), "res://assets/npcs/vex-base.png")
	else:
		tex = _textura(anim.get("atlas", ""), "res://assets/npcs/vex-base.png")
	var tam := float(d.get("screen_size", 141))   # ahora: unidades de MUNDO
	_sprite3d = Mundo3D.sprite_plano(tex, tam, int(anim.get("vframes", 1)))
	if not anim.is_empty():
		_sprite3d.hframes = int(anim.get("hframes", 1))
		_sprite3d.vframes = int(anim.get("vframes", 1))
		_anim_total = int(anim.get("count", _sprite3d.hframes * _sprite3d.vframes))
		_anim_vaiven = bool(anim.get("pingpong", false))
		_anim_fps = float(anim.get("fps", 12.0))
		var periodo_ := (_anim_total * 2 - 2) if _anim_vaiven else _anim_total
		_anim_t = randf() * float(periodo_) / maxf(_anim_fps, 1.0)
	_giro3d.add_child(_sprite3d)
	_escala_cuerpo = _sprite3d.pixel_size

	# capa emisiva pulsante (solo el camino PNG: el atlas trae la luz cocida)
	var tex_emisiva := _textura(d.get("emissive", ""), "") \
		if _anim_total == 0 and Quality.nivel("emissive") >= 1 else null
	if tex_emisiva != null:
		_emissive3d = Mundo3D.sprite_plano(tex_emisiva, tam)
		_emissive3d.position.y = 2.0       # sobre el casco, sin z-fighting
		_giro3d.add_child(_emissive3d)
		var p: Dictionary = d.get("pulse", {})
		_pulse_min = float(p.get("min_intensity", 0.2))
		_pulse_max = float(p.get("max_intensity", 2.4))
		_pulse_speed = float(p.get("speed", 2.6))
		_pulse_sharp = float(p.get("sharpness", 2.8))

	# motores del JSON (pixeles de textura = unidades de mundo, misma escala 1:1
	# que tenia el mundo 2D). Nivel 0 = sin llamas.
	if Quality.nivel("engine") >= 1:
		var trail: Dictionary = d.get("engine_trail", {})
		for motor in d.get("engines", []):
			_crear_llama_en(Vector3(float(motor.get("x", 0)), 1.0, float(motor.get("y", 0))),
				trail, float(motor.get("scale", 1.0)))


## El cuerpo como MALLA en la escena unica. Ya no hay SubViewport ni camara por
## bicho: la luz, el encuadre y la perspectiva los pone la camara del mundo.
## Devuelve false si el GLB aun no esta (se pide en hilo y se monta el quad).
func _construir_malla_3d(d: Dictionary) -> bool:
	var ruta := str(d["modelo"])
	var escena: PackedScene = _glb_cache.get(ruta)
	if escena == null:
		if not _glb_solicitados.has(ruta):
			if ResourceLoader.load_threaded_request(ruta) != OK:
				push_warning("EntityNode: no se pudo pedir %s; se queda el quad" % ruta)
				return false
			_glb_solicitados[ruta] = true
		_glb_pendiente = ruta
		return false

	_modelo = escena.instantiate()
	_giro3d.add_child(_modelo)
	# El modelo mide sus unidades; el mundo pide `screen_size` UNIDADES DE JUEGO
	# (la escala 1:1 heredada: 141 px del sprite = 141 u del mundo).
	var ext := AssetDefs.extension_3d(_modelo)
	_escala_cuerpo = float(d.get("screen_size", 141)) / ext
	_modelo.scale = Vector3.ONE * _escala_cuerpo

	_huesos_3d = _mapear_huesos(_modelo)
	_mats_3d = AssetDefs.materiales_3d(_modelo)
	# LAVA QUE VIAJA (`lava` en el JSON): pase aditivo como next_pass, igual que
	# en la era de viewports — el material es el mismo.
	var lv: Dictionary = d.get("lava", {})
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
	var pul: Dictionary = d.get("pulse", {})
	_pulse_min = float(pul.get("min_intensity", 0.25))
	_pulse_max = float(pul.get("max_intensity", 2.6))
	_pulse_sharp = float(pul.get("sharpness", 2.4))
	var cg: Array = d.get("cuernos_grados", [])
	if cg.size() == 2:
		_cuernos_min = float(cg[0])
		_cuernos_max = float(cg[1])
	_cuernos_eje = int(d.get("cuernos_eje", 1))
	_brazos_n = 0
	while _huesos_3d.has("brazo_%d" % (_brazos_n + 1)):
		_brazos_n += 1
	var br: Dictionary = d.get("brazos", {})
	_brazos_grados = float(br.get("grados", 0.0))
	_brazos_ciclo = float(br.get("ciclo", _brazos_ciclo))
	_brazos_desfase = float(br.get("desfase", 1.0 / maxf(float(_brazos_n), 1.0)))
	_brazos_eje = int(br.get("eje", _brazos_eje))
	var al: Dictionary = d.get("alas", {})
	_alas_grados = float(al.get("grados", _alas_grados))
	_alas_ciclo = float(al.get("ciclo", _alas_ciclo))
	_alas_eje = int(al.get("eje", _alas_eje))
	var co_: Dictionary = d.get("cola", {})
	_cola_grados = float(co_.get("grados", _cola_grados))
	_cola_ciclo = float(co_.get("ciclo", _cola_ciclo))
	_cola_desfase = float(co_.get("desfase", _cola_desfase))
	_cola_eje = int(co_.get("eje", _cola_eje))

	# LUZ DEL HEROE (G§7.2): en la escena unica por fin DERRAMA sobre los
	# vecinos, como el original — radio 450 unidades de mundo, tal cual.
	# Solo con luces dinamicas encendidas (clave `luces` de la calidad, F2).
	if es_heroe and Quality.nivel("luces") >= 1:
		var heroe_luz := OmniLight3D.new()
		heroe_luz.light_color = AssetDefs.LUZ_HEROE_COLOR
		heroe_luz.light_energy = AssetDefs.LUZ_HEROE_ENERGIA
		heroe_luz.position = Vector3(0.0, 40.0, 0.0)
		heroe_luz.omni_range = 450.0
		heroe_luz.shadow_enabled = false
		_cuerpo.add_child(heroe_luz)

	# anclajes tobera_*/canon_* del GLB, ahora en el espacio REAL del cuerpo
	_montar_anclajes(d)
	return true


## Marcadores del GLB -> llamas y bocas en unidades de MUNDO, en el espacio
## local del cuerpo que gira. Los disparos salen de los caniones reales incluso
## con banking, porque el marcador vive EN el modelo (G§6.1).
func _montar_anclajes(d: Dictionary) -> void:
	var ancho_boca := 0.0
	var toberas: Array[Vector3] = []
	var canones: Array[Vector2] = []
	for n in _modelo.find_children("*", "Node3D", true, false):
		var nombre := str(n.name)
		if not (nombre.begins_with("tobera") or nombre.begins_with("canon")):
			continue
		var p := _posicion_en_modelo(n as Node3D) * _escala_cuerpo
		if nombre.begins_with("tobera"):
			toberas.append(Vector3(p.x, p.y + 1.0, p.z))
			ancho_boca = maxf(ancho_boca, (n as Node3D).scale.x * _escala_cuerpo)
		else:
			canones.append(Vector2(p.x, p.z))
	if not canones.is_empty():
		canones.sort_custom(func(a, b): return a.x < b.x)
		_canones = canones
	if Quality.nivel("engine") >= 1 and not toberas.is_empty():
		toberas.sort_custom(func(a, b): return a.x < b.x)
		var escala := ancho_boca / 20.0 if ancho_boca > 0.0 else 1.0
		var trail: Dictionary = d.get("engine_trail", {})
		for punto in toberas:
			# el marcador esta en el FILO de salida y el disco de emision va
			# exactamente ahi: el medio ancho hacia proa era del quad viejo y
			# hacia nacer las particulas DENTRO de la campana, "de arriba"
			_crear_llama_en(punto, trail, escala)


func _posicion_en_modelo(n: Node3D) -> Vector3:
	var t := Vector3.ZERO
	var actual: Node = n
	while actual != null and actual != _modelo:
		if actual is Node3D:
			t += (actual as Node3D).position
		actual = actual.get_parent()
	return t


func _mapear_huesos(nodo: Node) -> Dictionary:
	var esqs := nodo.find_children("*", "Skeleton3D", true, false)
	if esqs.is_empty():
		return {}
	var sk: Skeleton3D = esqs[0]
	# Se mapea lo que el ESQUELETO trae, no una lista fija (leccion del Vorax).
	var mapa := {"sk": sk}
	for idx in sk.get_bone_count():
		mapa[sk.get_bone_name(idx)] = {"i": idx,
			"rest": sk.get_bone_rest(idx).basis.get_rotation_quaternion()}
	return mapa


func _poner_hueso(nombre: String, eje: int, ang: float) -> void:
	if not _huesos_3d.has(nombre):
		return
	var h: Dictionary = _huesos_3d[nombre]
	var v := Vector3.UP if eje == 1 else (Vector3.BACK if eje == 2 else Vector3.RIGHT)
	_huesos_3d["sk"].set_bone_pose_rotation(h["i"],
		(h["rest"] as Quaternion) * Quaternion(v, ang))


## Bocas de canion del JSON (pixeles de textura = unidades de mundo). Solo si
## el camino 3D no las puso ya del modelo, que es la fuente.
func _montar_canones_json() -> void:
	if not _canones.is_empty():
		return
	for canon in _def.get("cannons", []):
		_canones.append(Vector2(float(canon.get("x", 0)), float(canon.get("y", 0))))


## La llama de una tobera: GPUParticles3D con los valores del thruster.awp,
## la rampa en el color del trail de la nave (nucleo casi blanco, cola del
## color). Material por color y malla compartidos; el tamano por nave va en
## la escala del nodo (k = boca/5), que con local_coords escala bola y
## velocidades a la vez.
func _crear_llama_en(punto: Vector3, trail: Dictionary, escala: float) -> void:
	var c := AssetDefs.color(trail.get("color", "00E5FF"))
	var clave := c.to_html(false)
	if not _pm_llamas.has(clave):
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
		var curva := Curve.new()             # escala 1 -> 0.2 sobre la vida
		curva.add_point(Vector2(0.0, 1.0))
		curva.add_point(Vector2(1.0, 0.2))
		var ct := CurveTexture.new()
		ct.curve = curva
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
		_pm_llamas[clave] = pm
	if _malla_llama_cache == null:
		_malla_llama_cache = QuadMesh.new()
		_malla_llama_cache.size = Vector2(8.0, 8.0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.vertex_color_use_as_albedo = true
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.albedo_texture = load("res://assets/fx/simple-gradient.png")
		_malla_llama_cache.material = mat
	var llama := GPUParticles3D.new()
	llama.amount = 40
	llama.lifetime = 1.0
	llama.preprocess = 1.0        # el penacho existe desde el primer frame
	llama.local_coords = true     # sigue a la nave, como el follow del original
	llama.process_material = _pm_llamas[clave]
	llama.draw_pass_1 = _malla_llama_cache
	llama.position = punto
	# k por nave: la bola de 8 del original sale de una boca de ~5 (la
	# cobertura de la boca la pone el emission_shape, no el tamano de bola)
	llama.set_meta("k", escala * 20.0 / 5.0)
	_giro3d.add_child(llama)
	_flames.append(llama)


## Rehace la parte visual con la calidad actual. El HUD, el rumbo y el estado
## no dependen del nivel y se quedan como estan.
func reconstruir() -> void:
	if _cuerpo != null:
		_cuerpo.queue_free()
	_cuerpo = null
	_giro3d = null
	_modelo = null
	_sprite3d = null
	_emissive3d = null
	_mats_3d.clear()
	_lava_3d.clear()
	_huesos_3d.clear()
	_flames.clear()
	_canones.clear()
	_anim_total = 0
	_anim_vaiven = false
	_construir_visual()
	_montar_canones_json()
	_set_visual_angle(_visual_angle)


func _exit_tree() -> void:
	# el cuerpo vive en Mundo3D y el HUD en su capa: se van con la entidad
	if _cuerpo != null:
		_cuerpo.queue_free()
	if _hud != null:
		_hud.queue_free()


## El HUD 2D: nombre y barras en PIXELES de pantalla, sobre la capa del mundo,
## reposicionado cada frame proyectando la posicion 3D (G§11). Tamanio
## constante a cualquier zoom, como el original.
func _construir_hud(d: Dictionary, heroe: bool, spawn) -> void:
	_hud = Node2D.new()
	_hud.draw.connect(_dibujar_marcador)
	if capa_hud != null:
		capa_hud.add_child(_hud)
	else:
		add_child(_hud)
	var color := NTheme.CYAN if heroe else (NTheme.TXT if not es_npc else NTheme.HOSTILE)
	_nombre = NTheme.label(spawn.name, NTheme.exo2(), 12, color)
	_nombre.position = Vector2(-70, 44)
	_nombre.custom_minimum_size = Vector2(140, 0)
	_nombre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nombre.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_nombre.add_theme_constant_override("outline_size", 4)
	_hud.add_child(_nombre)
	_shield_pct = clampf(spawn.shield_pct, 0.0, 1.0)
	var barra_y := -52.0
	_escudo = _crear_barra(barra_y - BARRA_SEPARACION, NTheme.SHIELD, _shield_pct)
	_hp = _crear_barra(barra_y, NTheme.HP if not es_npc else NTheme.HOSTILE, _hp_pct)


static func _textura(ruta: Variant, respaldo: String) -> Texture2D:
	var r := str(ruta)
	if not r.is_empty() and ResourceLoader.exists(r):
		return load(r)
	if not r.is_empty():
		push_warning("textura ausente en el JSON: " + r)
	if respaldo.is_empty():
		return null
	return load(respaldo)


func _crear_barra(y: float, color: Color, pct: float) -> ColorRect:
	var pista := ColorRect.new()
	pista.color = Color(0, 0, 0, 0.55)
	pista.position = Vector2(-BARRA_ANCHO * 0.5 - 1, y - 1)
	pista.size = Vector2(BARRA_ANCHO + 2, BARRA_ALTO + 2)
	_hud.add_child(pista)
	var barra := ColorRect.new()
	barra.color = color
	barra.position = Vector2(-BARRA_ANCHO * 0.5, y)
	barra.size = Vector2(BARRA_ANCHO * pct, BARRA_ALTO)
	_hud.add_child(barra)
	return barra


func _process(delta: float) -> void:
	# el GLB pedido en hilo: al llegar, el cuerpo se sube a malla
	if _glb_pendiente != "":
		_atender_glb()
	if _cuerpo == null:
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

	var en_vuelo := position.distance_to(objetivo) > 0.5

	# acelerador: el empuje sube en vuelo y cae al frenar; parada, la nave de
	# jugador queda al RALENTI y el NPC apaga (G§6.2)
	if not _flames.is_empty():
		var empuje_objetivo := 1.0 if en_vuelo else (0.0 if es_npc else LLAMA_IDLE)
		if _thrust < empuje_objetivo:
			_thrust = minf(_thrust + 3.0 * delta, empuje_objetivo)
		else:
			_thrust = maxf(_thrust - 4.0 * delta, empuje_objetivo)
		# el original escala el thruster entero 0/0.7/1 (lerp por frame): con
		# local_coords la escala del nodo encoge bola Y velocidades a la vez
		for llama in _flames:
			llama.visible = _thrust > 0.02
			llama.emitting = llama.visible
			var k: float = llama.get_meta("k", 1.0)
			llama.scale = Vector3.ONE * maxf(_thrust, 0.01) * k

	# atlas del quad: mismos fotogramas, mismo vaiven
	if _anim_total > 0 and _sprite3d != null:
		_anim_t += delta
		var i := int(_anim_t * _anim_fps)
		if _anim_vaiven:
			var periodo := _anim_total * 2 - 2
			i = i % maxi(periodo, 1)
			if i >= _anim_total:
				i = periodo - i
		else:
			i = i % _anim_total
		_sprite3d.frame = i

	# pulso emisivo del quad (fase por entidad; el brillo acompania al casco)
	if _emissive3d != null:
		var onda := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * _pulse_speed + entity_id * 1.7)
		onda = pow(onda, _pulse_sharp)
		var k: float = _pulse_min + (_pulse_max - _pulse_min) * onda
		k *= lerpf(GLOW_HP_MIN, 1.0, _hp_pct)
		_emissive3d.modulate = Color(k, k, k, 1.0)

	# ---- el cuerpo articulado (malla): aleteo, cola, brazos, destello ----
	if not _huesos_3d.is_empty():
		var reloj := Time.get_ticks_msec() * 0.001
		var fase := fposmod(entity_id * 0.618034, 1.0)
		var t := fposmod(reloj / _alas_ciclo + fase, 1.0)
		var bat := deg_to_rad(_alas_grados) * sin(TAU * t)
		_poner_hueso("ala_izq", _alas_eje, -bat)
		_poner_hueso("ala_der", _alas_eje, bat)
		if _cuernos_max != _cuernos_min:
			var kq := 0.5 - 0.5 * cos(TAU * t)
			var pinza := deg_to_rad(_cuernos_min + (_cuernos_max - _cuernos_min) * kq)
			_poner_hueso("cuerno_izq", _cuernos_eje, -pinza)
			_poner_hueso("cuerno_der", _cuernos_eje, pinza)
		if _brazos_grados > 0.0 and _brazos_n > 0:
			var tb := reloj / _brazos_ciclo + fase
			for k in _brazos_n:
				_poner_hueso("brazo_%d" % (k + 1), _brazos_eje,
					deg_to_rad(_brazos_grados) * sin(TAU * (tb - k * _brazos_desfase)))
		var tc := reloj / _cola_ciclo + fase
		for k in 3:
			_poner_hueso("cola_%d" % (k + 1), _cola_eje,
				deg_to_rad(_cola_grados) * sin(TAU * (tc - k * _cola_desfase)))
		if not _mats_3d.is_empty():
			var onda3 := pow(0.5 - 0.5 * cos(TAU * t), _pulse_sharp)
			var e: float = _pulse_min + (_pulse_max - _pulse_min) * onda3
			e *= lerpf(GLOW_HP_MIN, 1.0, _hp_pct)
			for mat in _mats_3d:
				mat.emission_energy_multiplier = e
			for sm in _lava_3d:
				sm.set_shader_parameter("intensidad", e)

	# ---- movimiento (modelo, sin cambios) ----
	if en_vuelo:
		if turn_deg_per_sec > 0.0:
			# LA SOMBRA AUTORITATIVA (ver README): el server vuela lineal a
			# velocidad plena; el freno de proa es presentacion y el deficit
			# empuja el gas para que la divergencia no se cobre de golpe.
			_shadow = _shadow.move_toward(objetivo, speed * delta)
			var factor := maxf(cos(deg_to_rad(_error_de_proa(objetivo))), 0.0)
			var deficit := position.distance_to(_shadow)
			var vel := speed * clampf(factor + deficit / CATCHUP_DIST, 0.0, CATCHUP_MAX)
			position = position.move_toward(_shadow, vel * delta)
		else:
			position = position.move_toward(objetivo, speed * delta)

	if attack_target != null and not is_instance_valid(attack_target):
		attack_target = null
	if attack_target != null and _attack_ttl > 0.0:
		_attack_ttl -= delta
		if _attack_ttl <= 0.0:
			attack_target = null
	if attack_target != null:
		_encarar(attack_target.position)
	elif not en_vuelo and es_npc:
		# NPCs parados: giro perezoso aleatorio cada 2-7 s (vida del original)
		_idle_timer -= delta
		if _idle_timer <= 0.0:
			_idle_timer = 2.0 + randf() * 5.0
			_girar_a(_visual_angle + (randf() - 0.5) * 360.0)

	# ---- sincronia del cuerpo 3D y del HUD ----
	_cuerpo.position = Vector3(position.x, 0.0, position.y)
	if turn_deg_per_sec == 0.0 and not _congelado:
		_process_banking(delta, en_vuelo)
		_process_hover(delta, en_vuelo)
	if _hud != null and Mundo3D.instancia != null:
		_hud.position = Mundo3D.instancia.a_pantalla(position).floor()


func _atender_glb() -> void:
	if _glb_cache.has(_glb_pendiente):
		_glb_pendiente = ""
		reconstruir()
		return
	var st := ResourceLoader.load_threaded_get_status(_glb_pendiente)
	if st == ResourceLoader.THREAD_LOAD_LOADED:
		_glb_cache[_glb_pendiente] = ResourceLoader.load_threaded_get(_glb_pendiente)
		_glb_pendiente = ""
		reconstruir()
	elif st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		push_warning("EntityNode: fallo la carga en hilo de %s; se queda el quad"
			% _glb_pendiente)
		_glb_pendiente = ""


## BANKING real (G§5.2): el alabeo persigue al error angular pendiente con el
## ease incremental del original. Se aplica al cuerpo entero — malla o quad —
## alrededor de su eje longitudinal, y con la camara a 45 grados SE VE.
func _process_banking(delta: float, en_vuelo: bool) -> void:
	var error := fposmod(_visual_target - _visual_angle + 180.0, 360.0) - 180.0
	var objetivo_roll: float
	var d: float
	if en_vuelo and attack_target != null:
		objetivo_roll = clampf(error * BANK_COMBATE_GANANCIA,
			-BANK_COMBATE_MAX, BANK_COMBATE_MAX)
		d = BANK_COMBATE_EASE
	else:
		objetivo_roll = clampf(error, -BANK_MAX, BANK_MAX)
		d = BANK_EASE
	var k := minf(1.0, (delta / d) * (2.0 - delta / d))
	_roll += (objetivo_roll - _roll) * k
	_aplicar_orientacion()


## FLOTACION idle: en 3D la componente vertical es altura de verdad (el
## original flotaba 0..5 unidades hacia arriba, G§5.3).
func _process_hover(delta: float, en_vuelo: bool) -> void:
	_hover_gain = move_toward(_hover_gain, 0.0 if en_vuelo else 1.0, 2.0 * delta)
	if _giro3d == null:
		return
	if _hover_gain <= 0.0:
		_giro3d.position = Vector3.ZERO
		return
	_hover_fase += delta / HOVER_CICLO
	var a := _hover_fase
	_giro3d.position = Vector3(sin(a) * cos(a), pow(sin(a), 2.0),
		sin(a * 1.13) * cos(a * 0.87)) * (HOVER_AMP * _hover_gain)


## Rumbo + alabeo compuestos sobre el cuerpo: primero la guiniada, luego el
## roll alrededor del eje longitudinal (la proa mira a -Z a giro 0).
func _aplicar_orientacion() -> void:
	if _giro3d == null:
		return
	_giro3d.basis = Basis(Vector3.UP, -deg_to_rad(_visual_angle)) \
		* Basis(Vector3.BACK, deg_to_rad(_roll))


func set_attack_target(objetivo_ataque: EntityNode, segundos := 0.0) -> void:
	attack_target = objetivo_ataque
	_attack_ttl = segundos
	if attack_target != null and is_instance_valid(attack_target):
		_encarar(attack_target.position)


func _encarar(punto: Vector2) -> void:
	var rumbo := punto - position
	if rumbo.length() > 1.0:
		_girar_a(_angulo_visual_hacia(punto),
			TURN_FLIGHT_DEG_PER_SEC if turn_deg_per_sec > 0.0 else 0.0)


func _angulo_visual_hacia(punto: Vector2) -> float:
	return rad_to_deg((punto - position).angle()) + 90.0


func _error_de_proa(punto: Vector2) -> float:
	return absf(fposmod(_angulo_visual_hacia(punto) - _visual_angle + 180.0, 360.0) - 180.0)


func set_objetivo(destino: Vector2) -> void:
	var en_vuelo := position.distance_to(objetivo) > 0.5
	if en_vuelo and absf(destino.x - position.x) <= DEAD_ZONE \
			and absf(destino.y - position.y) <= DEAD_ZONE:
		objetivo = destino
		return
	objetivo = destino
	if attack_target != null and is_instance_valid(attack_target):
		return
	_encarar(destino)


## Giro. Dos modelos, como siempre — lo que cambio con la Fase 1 es la NAVE:
## - NAVES (turn_deg_per_sec = 0): ease de TURN_TIME (0.2 s) por el camino
##   corto, CONTINUO — el giro del cliente 3D original. La cuantizacion de 32
##   pasos era el look del sheet 2D y murio con el mundo de sprites.
## - BICHOS (turn_deg_per_sec > 0): velocidad angular constante, su peso.
func _girar_a(grados: float, dps := 0.0) -> void:
	var destino_ang := fposmod(grados, 360.0)
	var delta := fposmod(destino_ang - _visual_angle + 180.0, 360.0) - 180.0
	if is_zero_approx(delta):
		return
	_visual_target = fposmod(_visual_angle + delta, 360.0)
	var duracion := TURN_TIME
	var vel := dps if dps > 0.0 else turn_deg_per_sec
	if vel > 0.0:
		duracion = clampf(absf(delta) / vel, 0.06, 8.0)
	if _turn_tween != null:
		_turn_tween.kill()
	_turn_tween = create_tween()
	_turn_tween.tween_method(_set_visual_angle, _visual_angle, _visual_angle + delta, duracion) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Fija el rumbo VISUAL en el acto (enganche del autotest).
func rumbo_visual(grados: float) -> void:
	if _turn_tween != null and _turn_tween.is_valid():
		_turn_tween.kill()
	_visual_target = fposmod(grados, 360.0)
	_set_visual_angle(grados)


func _set_visual_angle(grados: float) -> void:
	_visual_angle = fposmod(grados, 360.0)
	_aplicar_orientacion()


## En la escena unica TODO cuerpo es 3D.
func es_3d() -> bool:
	return true


## El relieve murio con los sprites: la luz fija sobre un cuerpo que gira es
## gratis por construccion en la escena unica.
func tiene_relieve() -> bool:
	return false


func angulo_visual() -> float:
	return _visual_angle


## Enganche del autotest: cuerpo inmovil y a neutro mientras se mide.
func solo_casco(activo: bool) -> void:
	_congelado = activo
	if activo and _giro3d != null:
		_giro3d.position = Vector3.ZERO
		_roll = 0.0
		_aplicar_orientacion()
	if _hud != null:
		_hud.visible = not activo
	for llama in _flames:
		llama.visible = not activo and _thrust > 0.02


## Eco autoritativo del server: correccion suave si la deriva es chica, snap si es grande.
func reconcile(x: float, y: float, tx: float, ty: float, nueva_vel: float, teleport: bool) -> void:
	speed = nueva_vel
	var server_pos := Vector2(x, y)
	if turn_deg_per_sec > 0.0:
		_shadow = server_pos
		if teleport or position.distance_to(server_pos) > 500.0:
			position = server_pos
	elif teleport or position.distance_to(server_pos) > 220.0:
		position = server_pos
	else:
		position = position.lerp(server_pos, 0.35)
	set_objetivo(Vector2(tx, ty))


func set_hp_pct(pct: float) -> void:
	_hp_pct = clampf(pct, 0.0, 1.0)
	_hp.size.x = BARRA_ANCHO * _hp_pct


func set_shield_pct(pct: float) -> void:
	_shield_pct = clampf(pct, 0.0, 1.0)
	_escudo.size.x = BARRA_ANCHO * _shield_pct


func set_estado_abs(hp: int, escudo: int) -> void:
	if max_hp_abs > 0:
		set_hp_pct(float(hp) / max_hp_abs)
	if max_shield_abs > 0:
		set_shield_pct(float(escudo) / max_shield_abs)


## Boca de canion del proximo disparo, en el espacio LOCAL del cuerpo (unidades
## de mundo). El haz la rota por el rumbo VIVO cada frame — con banking y todo.
func siguiente_canon_local() -> Vector2:
	if _canones.is_empty():
		return Vector2.ZERO
	var local := _canones[_canon_actual]
	_canon_actual = (_canon_actual + 1) % _canones.size()
	return local


## Chispazo en el casco: billboard suelto en el mundo, punto aleatorio del
## disco de click (la receta del original, intacta).
func impacto_casco() -> void:
	if _impactos_casco >= 5:
		return
	_impactos_casco += 1
	var rnd := randf()
	var offset := Vector2.from_angle(rnd * TAU) * (click_radius * 0.5 * rnd)
	var anim := _sheet_anim3d("res://assets/fx/hull-impact.png", 96, 8, 0.45)
	var p := position + offset
	anim.position = Vector3(p.x, 12.0, p.y)
	Mundo3D.instancia.add_child(anim)
	anim.tree_exited.connect(func(): _impactos_casco -= 1)


## Onda en el escudo: sobre la circunferencia, del lado del atacante; sigue a
## la nave (hija del cuerpo).
func impacto_escudo(desde: Vector2) -> void:
	if _impactos_escudo >= 9:
		return
	_impactos_escudo += 1
	var dir := (desde - position).normalized()
	var anim := _sheet_anim3d("res://assets/fx/shield-impact.png", 128, 8, 0.3)
	anim.position = Vector3(dir.x * click_radius, 12.0, dir.y * click_radius)
	anim.modulate = NTheme.SHIELD
	_cuerpo.add_child(anim)
	anim.tree_exited.connect(func(): _impactos_escudo -= 1)


## Un FX de hoja de fotogramas como billboard 3D. El SpriteFrames se cachea por
## hoja (inmutable, se comparte).
static func _sheet_anim3d(ruta: String, lado: int, frames: int, duracion: float) -> AnimatedSprite3D:
	var sf: SpriteFrames = _sheets.get(ruta)
	if sf == null:
		sf = SpriteFrames.new()
		sf.add_animation("x")
		sf.set_animation_loop("x", false)
		sf.set_animation_speed("x", frames / duracion)
		var hoja: Texture2D = load(ruta)
		for i in frames:
			var f := AtlasTexture.new()
			f.atlas = hoja
			f.region = Rect2(i * lado, 0, lado, lado)
			sf.add_frame("x", f)
		_sheets[ruta] = sf
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
	_seleccionada = sel
	if sel:
		_sel_k = 1.5
		var tw := create_tween()
		tw.tween_method(_sel_paso, 1.5, 1.0, 0.3) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _hud != null:
		_hud.queue_redraw()


func _sel_paso(k: float) -> void:
	_sel_k = k
	if _hud != null:
		_hud.queue_redraw()


func _dibujar_marcador() -> void:
	if not _seleccionada or _hud == null:
		return
	var r := 44.0 * _sel_k
	var l := 14.0
	var c := NTheme.HOSTILE if not es_heroe else NTheme.CYAN
	for esquina in [Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)]:
		var dx := -l if esquina.x > 0 else l
		var dy := -l if esquina.y > 0 else l
		_hud.draw_line(esquina, esquina + Vector2(dx, 0), c, 2.0)
		_hud.draw_line(esquina, esquina + Vector2(0, dy), c, 2.0)
