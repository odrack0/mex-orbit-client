# Una entidad en pantalla: sprite orientado a su rumbo + nombre + barra de vida.
# Sus PARTICULARIDADES (textura, tamaÃ±o, anclajes de toberas, capa emisiva)
# salen de su JSON en data/ â€” nada hardcodeado por asset.
# Se mueve por interpolacion local y se reconcilia contra los ecos del server.
class_name EntityNode
extends Node2D

# Giro heredado del prototipo: tween de 0.1 s por el camino corto, orientacion
# cuantizada a 32 pasos de 11.25 grados (el look de los 32 frames del original)
# y zona muerta para no vibrar persiguiendo el cursor.
const TURN_TIME := 0.1
const TURN_STEPS := 32
const DEAD_ZONE := 2.0

## Giro al EMPRENDER VUELO. Los bichos tienen su propio ritmo (el peso de su
## especie) para el giro perezoso en reposo, pero para encarar un destino todos
## son briosos: si no, arrancan a toda velocidad mientras siguen girando y se
## desplazan de lado, como un cangrejo. La proa va delante SIEMPRE.
const TURN_FLIGHT_DEG_PER_SEC := 420.0

# barras de estado (dos: casco y escudo)
const BARRA_ANCHO := 60.0
const BARRA_ALTO := 3.0
const BARRA_SEPARACION := 5.0

var entity_id := 0
var type_id := ""            # el code del catalogo: "vex", "vexor", "skarn", "phoenix"
var speed := 0.0
var objetivo := Vector2.ZERO
var es_heroe := false
var es_npc := false
var click_radius := 42.0
## Giro: pasos de cuantizacion (0 = continuo) y velocidad angular
## (0 = duracion fija TURN_TIME, el modelo de nave del prototipo).
var turn_steps := TURN_STEPS
var turn_deg_per_sec := 0.0
## Objetivo de ataque: mientras exista GOBIERNA el rumbo (prioridad del
## prototipo: objetivo de ataque > destino de vuelo), incluso con la nave quieta.
var attack_target: EntityNode = null

var _sprite: Sprite2D
## La definicion del JSON se guarda: al cambiar la calidad hay que rehacer la
## parte visual sin volver a pedirle nada al server.
var _def := {}
var _nombre: Label
# dos barras y solo dos: casco y escudo. v1 NO tiene nano-casco (la tercera
# barra amarilla del prototipo): se decidiÃ³ dejarlo fuera del juego.
var _hp: ColorRect
var _escudo: ColorRect
var _hp_pct := 1.0
var _shield_pct := 0.0
var _seleccionada := false
var max_hp_abs := 0
var max_shield_abs := 0

var _visual_angle := 0.0          # grados de pantalla de la proa
var _turn_tween: Tween
var _idle_timer := 0.0

# motores: una LLAMA por tobera, anclada a la nave y creciendo con el empuje.
#
# Hubo ademas una estela de CHISPAS soltadas al mundo (`local_coords = false`) y
# se quito: con 0,38 s de vida la nave las adelantaba, asi que el rastro no se
# leia por detras sino como motas encima del casco. Una estela que se ve como
# suciedad no cuenta como estela.
var _flames: Array[Sprite2D] = []
var _relieve: ShaderMaterial     # shader de relieve, si esta nave lo tiene

## ---- malla 3D (calidad ALTA de los bichos que traen `modelo`) ----
## Supermuestreo del viewport respecto al tamanio en pantalla. A 1 el bicho se
## rinde justo a sus 178 px y al acercar el zoom se ve blando; a 2 aguanta el
## acercamiento sin costar cuatro veces, porque el area sigue siendo pequenia.
const VIEWPORT_FACTOR := 2
## Aire alrededor del modelo para que el aleteo no se salga del encuadre. Es
## tambien el pixelaje de mas que se pide al viewport, para que ese aire NO le
## robe tamanio al bicho: el lado mayor sigue midiendo `screen_size`.
const MARGEN := 1.15
## Elevacion de la camara. 90 es el cenital de siempre; por debajo empieza el
## escorzo, que es la decision de Q1 y todavia no esta tomada.
const ELEVACION := 90.0

var _vp: SubViewport             # el mundo 3D de este bicho, o null
var _modelo: Node3D              # la instancia del GLB dentro del viewport
var _huesos_3d := {}             # nombre -> {i, rest}, o vacio si no hay esqueleto
var _cuernos_grados := 0.0       # amplitud de las pinzas de la proa, del JSON
var _mats_3d: Array[BaseMaterial3D] = []   # copia por entidad, para pulsar la emision

## Diales del aleteo, medidos en el banco (pruebas/banco_3d.gd). Cambiarlos aqui
## cambia el bicho en el juego; el banco es donde se comparan, no donde se fijan.
const CICLO_ALAS := 2.17      # 26 fotogramas a 12 fps: el mismo ritmo que el atlas
const ALAS_GRADOS := 34.0
const EJE_ALAS := 1           # Y en Godot. glTF permuta ejes: la Y de Blender sale Z
const COLA_CICLO := 1.50      # reloj propio, como en el sprite
const COLA_GRADOS := 9.0
const COLA_DESFASE := 0.22    # por segmento, para que la onda recorra la cola
const EJE_COLA := 2
## Los cuernos van al MISMO reloj que las alas. El eje se midio con
## repro_eje_hueso.tscn: el 1 es el unico que gira DENTRO del plano —dy≈0 y el
## area crece—, que es abrir de verdad; el 2 mueve mas pixeles pero tumba el
## cuerno hacia la camara (dy +5, area −15%), que se lee como que se cae.
const EJE_CUERNOS := 1
var _thrust := 0.0

# bocas de caÃ±Ã³n (espacio de la textura) y a cuÃ¡l toca disparar
var _canones: Array[Vector2] = []
var _canon_actual := 0
var _impactos_casco := 0        # tope del prototipo: 5 simultÃ¡neos
var _impactos_escudo := 0       # tope del prototipo: 9

# ondulacion (solo los bichos que la definen en su JSON): el cuerpo serpentea
# y la capa emisiva serpentea CON el, o las visceras se quedarian rectas
var _ondas: Array[ShaderMaterial] = []
var _onda_gain := 0.0
var _onda_idle := 0.35

# ATLAS ANIMADO (segundo tipo de asset): en vez de un PNG con shaders encima,
# una rejilla de fotogramas sacada de un video en bucle. La luz va COCIDA en
# ellos, asi que estos bichos no llevan capa emisiva ni shaders â€” su vida ya
# esta en el asset. Es lo que hacia el original con sus aliens (`loopPlay`),
# salvo que los suyos por eso no rotaban y los nuestros si.
var _anim_total := 0
var _anim_vaiven := false
var _anim_fps := 12.0
var _anim_t := 0.0

# capa emisiva pulsante (nucleo y venas del Vex)
var _emissive: Sprite2D
var _pulse_min := 0.2          # intensidad del blend aditivo (>1 sobreexpone)
var _pulse_max := 2.4
var _pulse_speed := 2.6
var _pulse_sharp := 2.8        # 1 = seno suave; 3+ = destello marcado con valles largos


func setup(spawn, heroe: bool) -> void:   # spawn: MexProtocol.EntitySpawn
	entity_id = spawn.entity_id
	es_heroe = heroe
	es_npc = spawn.kind == MexProtocol.EntityKind.NPC
	type_id = spawn.type_id
	speed = float(spawn.speed)
	position = Vector2(spawn.x, spawn.y)
	objetivo = position
	_idle_timer = 2.0 + randf() * 5.0
	_hp_pct = spawn.hp_pct

	var d := AssetDefs.entidad(spawn.type_id)
	click_radius = float(d.get("click_radius", 42))
	var giro: Dictionary = d.get("turn", {})
	turn_steps = int(giro.get("steps", TURN_STEPS))
	turn_deg_per_sec = float(giro.get("deg_per_sec", 0.0))

	_def = d
	_construir_visual()

	# bocas de caÃ±Ã³n del JSON (espacio de la textura; se alternan al disparar)
	for canon in d.get("cannons", []):
		_canones.append(Vector2(float(canon.get("x", 0)), float(canon.get("y", 0))))
	_construir_etiquetas(d, heroe, spawn)


## Todo lo que depende de la CALIDAD vive aqui, para poder rehacerlo en caliente.
func _construir_visual() -> void:
	var d := _def
	_sprite = Sprite2D.new()

	# ---- ALTA con MALLA 3D ----
	# Si el bicho trae `modelo`, la calidad alta deja de ser un atlas de video y
	# pasa a ser una malla con esqueleto. Entra por DEBAJO, no por encima: el 3D
	# vive en un SubViewport y su textura alimenta a este mismo Sprite2D, asi que
	# la posicion, el z-index, el radio de click, las barras y los FX siguen
	# siendo exactamente los de 2D. Cero cambios en world.gd.
	#
	# El precio es un viewport por entidad. Se mide, no se supone.
	if Quality.nivel("npc") >= 2 and str(d.get("modelo", "")) != "":
		if _construir_malla_3d(d):
			add_child(_sprite)
			return
	# ALTA monta el atlas del video; MEDIA y BAJA caen al PNG fijo, que por eso
	# nunca se borro al convertir un bicho a atlas.
	var anim: Dictionary = d.get("frames", {}) if Quality.nivel("npc") >= 2 else {}
	if anim.is_empty():
		_sprite.texture = _textura(d.get("texture", ""), "res://assets/npcs/vex-base.png")
	else:
		_sprite.texture = _textura(anim.get("atlas", ""), "res://assets/npcs/vex-base.png")
		_sprite.hframes = int(anim.get("hframes", 1))
		_sprite.vframes = int(anim.get("vframes", 1))
		_anim_total = int(anim.get("count", _sprite.hframes * _sprite.vframes))
		_anim_vaiven = bool(anim.get("pingpong", false))
		_anim_fps = float(anim.get("fps", 12.0))
		# desfase por entidad: tres Gravon animando al unisono cantan igual que
		# cantaban los gusanos ondulando en fase. Con vaiven el periodo es casi el
		# DOBLE, y repartir sobre `count` dejaria a todos los Vex en la misma mitad
		# de la onda â€” abriendo el ala a la vez, que es justo lo que se evita.
		var periodo_ := (_anim_total * 2 - 2) if _anim_vaiven else _anim_total
		_anim_t = randf() * float(periodo_) / maxf(_anim_fps, 1.0)
	# tamaÃ±o en pantalla constante segun el JSON, sea cual sea la resolucion del
	# export. Con atlas manda el alto del FOTOGRAMA, no el de la textura entera.
	# MIPMAPS, y solo cuando NO es atlas.
	#
	# La nave se dibuja a 141 px desde una textura de 512, y el zoom baja hasta
	# 0,1: ahi son treinta pixeles de una textura de quinientos. Sin mipmaps la
	# GPU muestrea la textura entera con un filtro de 2x2 texeles, asi que el
	# detalle fino no se promedia, se ALIASA â€” hierve al moverse y se lee como
	# ruido. Es la mitad tecnica de "de lejos no se ve bien"; la otra mitad es
	# cuanto detalle trae el render.
	#
	# Con ATLAS no: los mipmaps promedian a ciegas y en los niveles bajos mezclan
	# celdas vecinas, o sea un fotograma con el siguiente. Esa distincion ya
	# estaba calculada aqui arriba, que es la razon de ponerlo en este punto.
	_sprite.texture_filter = (CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if anim.is_empty()
		else CanvasItem.TEXTURE_FILTER_LINEAR)
	var alto_tex := float(_sprite.texture.get_height()) / maxf(float(_sprite.vframes), 1.0)
	var factor: float = float(d.get("screen_size", 141)) / alto_tex
	_sprite.scale = Vector2.ONE * factor
	add_child(_sprite)

	# capa emisiva (si la define su JSON y su PNG existe de verdad). Un bicho de
	# atlas no la lleva: su luz ya viene cocida en los fotogramas.
	var tex_emisiva := _textura(d.get("emissive", ""), "") \
		if _anim_total == 0 and Quality.nivel("emissive") >= 1 else null
	if tex_emisiva != null:
		_emissive = Sprite2D.new()
		_emissive.texture = tex_emisiva
		_emissive.material = _material_add()
		_sprite.add_child(_emissive)
		var p: Dictionary = d.get("pulse", {})
		_pulse_min = float(p.get("min_intensity", 0.2))
		_pulse_max = float(p.get("max_intensity", 2.4))
		_pulse_speed = float(p.get("speed", 2.6))
		_pulse_sharp = float(p.get("sharpness", 2.8))

	_montar_ondulacion(d)
	_montar_relieve(d)

	# motores en los anclajes del JSON. Nivel 0 = sin llamas; 1 = llamas.
	var trail: Dictionary = d.get("engine_trail", {})
	if Quality.nivel("engine") >= 1:
		for motor in d.get("engines", []):
			_flames.append(_crear_llama(motor, trail))


## Monta la malla 3D en un SubViewport y la cuelga del Sprite2D. Devuelve false
## si el modelo no carga, para que se caiga al camino de siempre.
func _construir_malla_3d(d: Dictionary) -> bool:
	var escena: PackedScene = load(str(d["modelo"]))
	if escena == null:
		push_warning("EntityNode: no se pudo cargar %s; se cae al sprite" % d["modelo"])
		return false

	var lado := int(round(float(d.get("screen_size", 141)) * MARGEN)) * VIEWPORT_FACTOR
	_vp = SubViewport.new()
	_vp.size = Vector2i(lado, lado)
	# Fondo transparente: el bicho se compone sobre el mundo 2D, no lo tapa.
	_vp.transparent_bg = true
	# MUNDO 3D PROPIO. Sin esto el SubViewport COMPARTE el World3D del padre: los
	# modelos de todos los bichos viven en el mismo mundo y en el mismo origen, y
	# cada camara los ve TODOS. Se veia como una bola de copias del bicho que crecia
	# segun entraban mas, cada una en el angulo en que iba su dueno.
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# BORRAR SIEMPRE, explicito. Sin esto el destino acumula: el bicho gira y cada
	# fotograma deja su copia encima del anterior, asi que en unos segundos hay un
	# abanico de vexores en circulo y el apilado de bordes lo empasta a blanco.
	# Se veia como "muchos encimados", que es literalmente lo que era.
	_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	# Sin sombras ni reflejos: es un recorte de un bicho, no una escena.
	add_child(_vp)

	_modelo = escena.instantiate()
	_vp.add_child(_modelo)

	var ent := Environment.new()
	ent.background_mode = Environment.BG_CLEAR_COLOR
	ent.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	ent.ambient_light_color = Color(0.35, 0.40, 0.55)
	ent.ambient_light_energy = 0.28   # la misma fuerza de fondo que usa el horneado

	# GLOW: sin el, la emision se RECORTA a 1.0 y las venas se leen como "claras",
	# no como "encendidas". Media si brilla porque alli la capa emisiva va en blend
	# aditivo ENCIMA del cuerpo, y eso satura de sobra.
	# Medido sobre el mismo bicho (rojo medio del pixel, recortado a 1 en ambos, que
	# es lo que la pantalla puede dar):
	#     media                 0.370      alta sin glow, x2.6   0.291
	#     alta con glow, x2.6   0.377      alta sin glow, x16    0.365
	# Es decir: con glow se iguala a media SIN tocar la ganancia del pulso. Subirla
	# a 16 llega a una cifra parecida pero lavando las venas a rosa —satura el rojo
	# hasta blanco— asi que la cifra empataba y la imagen no.
	# Cuesta un post-proceso por viewport, y hay uno por bicho. Va atado al nivel
	# `emissive`, el mismo interruptor que apaga la capa emisiva en 2D.
	if Quality.nivel("emissive") >= 1:
		ent.glow_enabled = true
		ent.glow_intensity = 1.0
		ent.glow_bloom = 0.25
		ent.glow_hdr_threshold = 0.9
	var we := WorldEnvironment.new()
	we.environment = ent
	_vp.add_child(we)

	# La MISMA luz del mundo que usa el relieve en 2D. No es cosmetico: si cada
	# bicho se ilumina por su cuenta, dos vecinos se leen como dos recortes
	# pegados en vez de dos cosas en el mismo sitio.
	var sol := DirectionalLight3D.new()
	# 1.0, NO el 2.6 del banco. Blender hornea el sprite de media con un sol de 3.2,
	# que por como normaliza equivale a ~1.0 aqui; con 2.6 el bicho salia lavado a
	# blanco y no se parecia a su propio horneado. El horneado es la referencia:
	# alta y media tienen que ser el mismo bicho, uno articulado y otro no.
	sol.light_energy = 1.0
	sol.rotation = Vector3(deg_to_rad(-48.0),
		deg_to_rad(AssetDefs.LUZ_MUNDO_GRADOS), 0.0)
	sol.shadow_enabled = false
	_vp.add_child(sol)

	# Camara ortografica en la elevacion del contrato. A 90 grados es el cenital
	# de siempre y el cambio no se nota; por debajo empieza el escorzo.
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	# El encuadre se MIDE del modelo. Con una constante a ojo el bicho salia
	# desbordando su propia barra de vida: el contrato es que su lado mayor ocupe
	# `screen_size` pixeles, igual que el recorte del PNG en 2D.
	cam.size = _extension(_modelo) * MARGEN
	_vp.add_child(cam)
	var el := deg_to_rad(ELEVACION)
	# `look_at_from_position`, no `look_at`: `setup()` corre ANTES de que la entidad
	# entre en el arbol y `look_at` exige estar dentro. Hacen lo mismo.
	# Y el "arriba" es -Z, no Y: a 90 grados la camara mira justo por Y y el vector
	# de arriba seria paralelo a su eje de vista, que no define una orientacion.
	cam.look_at_from_position(Vector3(0.0, 8.0 * sin(el), 8.0 * cos(el)),
		Vector3.ZERO, Vector3.FORWARD)
	cam.current = true

	_huesos_3d = _mapear_huesos(_modelo)
	_mats_3d = _copiar_materiales(_modelo)
	# Los mismos diales del JSON que usa la capa emisiva de 2D. No son dos ajustes:
	# es el mismo latido, aplicado a la emision del material en vez de al alfa.
	var pul: Dictionary = d.get("pulse", {})
	_pulse_min = float(pul.get("min_intensity", 0.25))
	_pulse_max = float(pul.get("max_intensity", 2.6))
	_pulse_sharp = float(pul.get("sharpness", 2.4))
	_cuernos_grados = float(d.get("cuernos_grados", 0.0))


	_sprite.texture = _vp.get_texture()
	# El viewport ya se rindio al tamanio de pantalla que pide el JSON, asi que
	# aqui no hay que reescalar por `screen_size` como con un PNG: basta deshacer
	# el factor de supermuestreo.
	_sprite.scale = Vector2.ONE / float(VIEWPORT_FACTOR)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	return true


## Lado mayor del modelo en el plano de la camara, en unidades de mundo. Se suman
## las AABB de las mallas: es el mismo dato que el validador imprime como CAJA.
func _extension(nodo: Node) -> float:
	var caja := AABB()
	var primera := true
	for m in nodo.find_children("*", "MeshInstance3D", true, false):
		var malla: MeshInstance3D = m
		# La transformacion se acumula A MANO hasta la raiz del modelo: `transform`
		# es solo la local, y `global_transform` no vale porque esto corre en
		# `setup()`, antes de que la entidad entre en el arbol.
		var tr := Transform3D()
		var n: Node = malla
		while n != null and n != nodo:
			if n is Node3D:
				tr = (n as Node3D).transform * tr
			n = n.get_parent()
		var a := tr * malla.get_aabb()
		caja = a if primera else caja.merge(a)
		primera = false
	if primera:
		return 2.0
	return maxf(maxf(caja.size.x, caja.size.z), 0.001)


## Duplica los materiales para que el destello sea de ESTE bicho y no de todos.
## Rompe el batching entre entidades; el banco lo midio con esa copia puesta, asi
## que la cifra que hay en pruebas/README.md ya la incluye.
func _copiar_materiales(nodo: Node) -> Array[BaseMaterial3D]:
	var salida: Array[BaseMaterial3D] = []
	for m in nodo.find_children("*", "MeshInstance3D", true, false):
		var malla: MeshInstance3D = m
		var mat = malla.get_active_material(0)
		if mat is BaseMaterial3D:
			var copia: BaseMaterial3D = mat.duplicate()
			# A DOS CARAS: la malla de Meshy trae el giro de las caras inconsistente
			# y con descarte trasero salen huecos donde Blender enseniaba solido.
			copia.cull_mode = BaseMaterial3D.CULL_DISABLED
			malla.set_surface_override_material(0, copia)
			salida.append(copia)
	return salida


## Los huesos que el cliente mueve, por nombre. Vacio si el modelo no trae
## esqueleto — un bicho puede ser malla quieta y seguir siendo valido.
func _mapear_huesos(nodo: Node) -> Dictionary:
	var esqs := nodo.find_children("*", "Skeleton3D", true, false)
	if esqs.is_empty():
		return {}
	var sk: Skeleton3D = esqs[0]
	var mapa := {"sk": sk}
	for nombre in ["ala_izq", "ala_der", "cuerno_izq", "cuerno_der",
			"cola_1", "cola_2", "cola_3"]:
		var idx := sk.find_bone(nombre)
		if idx >= 0:
			# La rotacion de REPOSO se guarda porque `set_bone_pose_rotation` fija
			# la pose ENTERA, no un incremento: escribir un cuaternion a secas
			# machaca el reposo del hueso y la malla sale aplastada sin haber
			# rotado nada.
			mapa[nombre] = {"i": idx,
				"rest": sk.get_bone_rest(idx).basis.get_rotation_quaternion()}
	return mapa


## Rota un hueso COMPONIENDO sobre su reposo. `set_bone_pose_rotation` fija la
## pose ENTERA: escribir el giro a secas machaca el reposo y la malla sale
## aplastada — los huesos de la cola apuntan hacia atras y ese giro va en su reposo.
func _poner_hueso(nombre: String, eje: int, ang: float) -> void:
	if not _huesos_3d.has(nombre):
		return
	var h: Dictionary = _huesos_3d[nombre]
	var v := Vector3.UP if eje == 1 else (Vector3.BACK if eje == 2 else Vector3.RIGHT)
	_huesos_3d["sk"].set_bone_pose_rotation(h["i"],
		(h["rest"] as Quaternion) * Quaternion(v, ang))


## Rehace la parte visual con la calidad actual. Lo demas â€”nombre, barras,
## caÃ±ones, rumboâ€” no depende del nivel y se queda como esta.
func reconstruir() -> void:
	for n in [_sprite, _vp]:
		if n != null:
			n.queue_free()
	_sprite = null
	_vp = null
	_modelo = null
	_huesos_3d.clear()
	_mats_3d.clear()
	_emissive = null
	_relieve = null      # su material moria con el sprite: dejarlo apuntando ahi
	_flames.clear()      # eran hijos del sprite: se van con el
	_ondas.clear()
	_anim_total = 0
	_anim_vaiven = false
	_construir_visual()
	# el sprite vuelve al fondo: si no, se dibujaria sobre las barras y el nombre
	move_child(_sprite, 0)
	_set_visual_angle(_visual_angle)


func _construir_etiquetas(d: Dictionary, heroe: bool, spawn) -> void:
	# nombre y barra DEBAJO de la nave, como el prototipo (con contorno negro
	# para que se lean sobre el fondo estelar). El offset sale del tamaÃ±o real.
	var mitad: float = float(d.get("screen_size", 141)) * 0.5
	var color := NTheme.CYAN if heroe else (NTheme.TXT if not es_npc else NTheme.HOSTILE)
	_nombre = NTheme.label(spawn.name, NTheme.exo2(), 12, color)
	_nombre.position = Vector2(-70, mitad + 6)
	_nombre.custom_minimum_size = Vector2(140, 0)
	_nombre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nombre.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_nombre.add_theme_constant_override("outline_size", 4)
	add_child(_nombre)

	# las barras van ENCIMA de la nave (el nombre abajo): escudo arriba, casco
	# abajo. Son DOS: el nano-casco del prototipo no existe en v1.
	_shield_pct = clampf(spawn.shield_pct, 0.0, 1.0)
	var barra_y := -mitad - 14.0
	_escudo = _crear_barra(barra_y - BARRA_SEPARACION, NTheme.SHIELD, _shield_pct)
	_hp = _crear_barra(barra_y, NTheme.HP if not es_npc else NTheme.HOSTILE, _hp_pct)


## Shaders vivos de la criatura. Dos efectos INDEPENDIENTES, ambos del JSON:
##
## - `undulate`: el cuerpo serpentea. Va en el sprite Y en su capa emisiva (una
##   con blend aditivo), o el brillo interior se quedaria recto sobre una carne
##   que se dobla.
## - `peristalsis`: una onda de luz recorriendo el interior. Solo en la emisiva.
## - `rings`: anillos concentricos girando. Solo tiene sentido en los bichos de
##   metal, donde la pieza ES concentrica.
## - `flicker`: ruido que hace temblar el brillo. El magma no late limpio como
##   un reactor; arde desigual.
##
## Se piden por separado a proposito: un Skarnox podria tener magma corriendo
## por sus grietas sin que la roca se menee un milimetro.
## RELIEVE: reiluminar el sprite contra la luz del mundo usando un mapa de
## normales. Es la "ruta C" â€” no da volumen ni escorzo, pero al virar el reflejo
## barre el casco, que es lo que separa un objeto de una calcomania.
##
## Cede ante la ONDULACION, que ya ocupa el material del sprite. No es una
## limitacion tecnica sino de sentido: la ondulacion es movimiento estructural
## â€”el bicho se doblaâ€” y el relieve es acabado. Si algun dia un bicho quiere las
## dos, se fusionan en un shader, no se pelean por el slot.
func _montar_relieve(d: Dictionary) -> void:
	if Quality.nivel("shader") < 1:
		return          # calidad baja: ni el material ni el mapa en VRAM
	if _sprite.material != null:
		return          # la ondulacion llego antes y manda
	_relieve = AssetDefs.material_relieve(AssetDefs.ruta_normal(d, _anim_total > 0))
	if _relieve == null:
		return
	_sprite.material = _relieve
	# el giro de partida: sin esto la nave nace iluminada como si mirase al este
	_relieve.set_shader_parameter("giro", _sprite.rotation)


func _montar_ondulacion(d: Dictionary) -> void:
	var o: Dictionary = d.get("undulate", {})
	var peri: Dictionary = d.get("peristalsis", {})
	var anillos: Dictionary = d.get("rings", {})
	var titileo: Dictionary = d.get("flicker", {})
	if Quality.nivel("shader") < 1:
		return          # calidad baja: ni se crea el material
	if _anim_total > 0:
		# El atlas YA trae el movimiento cocido en sus fotogramas. Montarle encima
		# un shader de cuerpo lo contaria dos veces: al Gravit se le abren los aros
		# en el video Y se los giraria el shader. La animacion manda sobre el truco.
		return
	if o.is_empty() and peri.is_empty() and anillos.is_empty() and titileo.is_empty():
		return
	_onda_idle = float(o.get("idle", 0.35))
	_onda_gain = _onda_idle
	var fase := float(entity_id % 628) * 0.01
	var objetivos := [[_sprite, "res://game/shaders/undulate.gdshader"]]
	if _emissive != null:
		objetivos.append([_emissive, "res://game/shaders/undulate_add.gdshader"])
	for par in objetivos:
		var mat := ShaderMaterial.new()
		mat.shader = load(par[1])
		# sin bloque `undulate` la amplitud es CERO, no el defecto del shader:
		# pedir solo peristalsis no puede poner a bailar al bicho de propina
		mat.set_shader_parameter("amplitude", float(o.get("amplitude", 0.0)))
		mat.set_shader_parameter("frequency", float(o.get("frequency", 2.0)))
		mat.set_shader_parameter("speed", float(o.get("speed", 3.0)))
		mat.set_shader_parameter("from_y", float(o.get("from", 0.25)))
		# fase por entidad: un banco de gusanos al unisono canta a bucle
		mat.set_shader_parameter("phase", fase)
		mat.set_shader_parameter("gain", _onda_gain)
		mat.set_shader_parameter("peri_amount", float(peri.get("amount", 0.0)))
		mat.set_shader_parameter("peri_frequency", float(peri.get("frequency", 2.0)))
		mat.set_shader_parameter("peri_speed", float(peri.get("speed", 2.5)))
		mat.set_shader_parameter("peri_sharpness", float(peri.get("sharpness", 3.0)))
		# radial = la onda sale del centro en vez de recorrer el cuerpo: es como
		# irradia un nucleo fundido, y es lo que separa una roca de un gusano
		mat.set_shader_parameter("peri_radial", 1.0 if peri.get("radial", false) else 0.0)
		mat.set_shader_parameter("flicker_amount", float(titileo.get("amount", 0.0)))
		mat.set_shader_parameter("flicker_scale", float(titileo.get("scale", 6.0)))
		mat.set_shader_parameter("flicker_speed", float(titileo.get("speed", 1.0)))
		mat.set_shader_parameter("ring_speed", float(anillos.get("speed", 0.0)))
		mat.set_shader_parameter("ring_bands", float(anillos.get("bands", 3.0)))
		mat.set_shader_parameter("ring_inner", float(anillos.get("inner", 0.05)))
		mat.set_shader_parameter("ring_outer", float(anillos.get("outer", 0.40)))
		mat.set_shader_parameter("ring_falloff", float(anillos.get("falloff", 0.5)))
		par[0].material = mat
		if not o.is_empty():
			_ondas.append(mat)   # solo la ondulacion se modula por frame


## Carga una textura del JSON. Un asset que todavia no existe (arte en camino,
## ruta mal escrita) NO puede tirar el cliente: cae al respaldo, o a null si no
## lo hay, y se avisa por consola.
static func _textura(ruta: Variant, respaldo: String) -> Texture2D:
	var r := str(ruta)
	if not r.is_empty() and ResourceLoader.exists(r):
		return load(r)
	if not r.is_empty():
		push_warning("textura ausente en el JSON: " + r)
	if respaldo.is_empty():
		return null
	return load(respaldo)


## Una barra sobre su pista negra, del ancho del prototipo.
func _crear_barra(y: float, color: Color, pct: float) -> ColorRect:
	var pista := ColorRect.new()
	pista.color = Color(0, 0, 0, 0.55)
	pista.position = Vector2(-BARRA_ANCHO * 0.5 - 1, y - 1)
	pista.size = Vector2(BARRA_ANCHO + 2, BARRA_ALTO + 2)
	add_child(pista)
	var barra := ColorRect.new()
	barra.color = color
	barra.position = Vector2(-BARRA_ANCHO * 0.5, y)
	barra.size = Vector2(BARRA_ANCHO * pct, BARRA_ALTO)
	add_child(barra)
	return barra


## La llama de una tobera: pluma anclada a la nave que rota con ella y crece
## con el empuje. Su boquilla queda EN la tobera y se afila hacia la popa.
func _crear_llama(motor: Dictionary, trail: Dictionary) -> Sprite2D:
	var llama := Sprite2D.new()
	llama.texture = load("res://assets/fx/engine-flame.png")
	llama.position = Vector2(float(motor.get("x", 0)), float(motor.get("y", 0)))
	# el arte de la llama apunta hacia ABAJO (+Y), que es la popa: sin rotar.
	# el pivote va en la boquilla para que crezca hacia atras, no hacia los lados
	llama.offset = Vector2(0, llama.texture.get_height() * 0.5)
	llama.modulate = AssetDefs.color(trail.get("color", "00E5FF"))
	llama.material = _material_add()
	llama.z_index = -1                   # detras del casco
	_sprite.add_child(llama)
	return llama


static func _material_add() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


func _process(delta: float) -> void:
	var en_vuelo := position.distance_to(objetivo) > 0.5

	# acelerador: el empuje sube en vuelo y cae al frenar (modelo del prototipo)
	if not _flames.is_empty():
		_thrust = clampf(_thrust + (3.0 if en_vuelo else -4.0) * delta, 0.0, 1.0)
		# la llama crece a lo largo con el empuje y respira; el ancho apenas cambia
		var respiro := 1.0 + 0.10 * sin(Time.get_ticks_msec() * 0.02 + entity_id)
		for llama in _flames:
			llama.visible = _thrust > 0.02
			llama.scale = Vector2(0.55 + 0.15 * _thrust, _thrust * respiro)
			llama.self_modulate.a = 0.35 + 0.65 * _thrust

	if _anim_total > 0:
		_anim_t += delta
		var i := int(_anim_t * _anim_fps)
		if _anim_vaiven:
			# VAIVEN: ida y vuelta. El bucle cierra POR CONSTRUCCION â€”dos
			# fotogramas seguidos son siempre vecinosâ€” asi que no hay costura que
			# medir ni que arreglar, y sale gratis: el atlas es el mismo.
			#
			# Se descarto para el Gravon y ahi estaba bien descartado: sus aros
			# tienen rotacion NETA, y al reves se mecerian en vez de girar. Un ala
			# que se abre no tiene ese problema â€” cerrarse ES su vuelta. La tecnica
			# no era mala, era el bicho equivocado.
			var periodo := _anim_total * 2 - 2
			i = i % maxi(periodo, 1)
			if i >= _anim_total:
				i = periodo - i
		else:
			i = i % _anim_total
		_sprite.frame = i

	# la ondulacion sube al nadar y baja al quedarse quieto (nunca a cero: un
	# bicho vivo respira aunque no avance)
	if not _ondas.is_empty():
		var objetivo := 1.0 if en_vuelo else _onda_idle
		_onda_gain = move_toward(_onda_gain, objetivo, 1.5 * delta)
		for mat in _ondas:
			mat.set_shader_parameter("gain", _onda_gain)

	# el latido de la capa emisiva (fase por entidad: no laten al unisono).
	# Se modula la INTENSIDAD del blend aditivo, no solo el alfa: por encima de
	# 1 sobreexpone y el nucleo se pone blanco, que es lo que hace visible el pulso.
	if _emissive != null:
		var onda := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * _pulse_speed + entity_id * 1.7)
		onda = pow(onda, _pulse_sharp)
		var k: float = _pulse_min + (_pulse_max - _pulse_min) * onda
		_emissive.self_modulate = Color(k, k, k, 1.0)

	# ---- el bicho 3D: aleteo, cola y destello, del MISMO reloj ----
	# La fase es una sola por entidad y la comparten las alas y la emision, asi que
	# el destello cae en el golpe de bajada por construccion. Dos relojes separados
	# es justo lo que se arreglo en el banco: se veian desincronizados.
	if not _huesos_3d.is_empty():
		var reloj := Time.get_ticks_msec() * 0.001
		# desfase por entidad (razon aurea): 30 vexors no aletean al unisono
		var fase := fposmod(entity_id * 0.618034, 1.0)
		var t := fposmod(reloj / CICLO_ALAS + fase, 1.0)

		# Un SENO, no un 0->1->0: el aleteo oscila alrededor del reposo, arriba y
		# abajo. Con la otra curva el ala solo baja y vuelve, y se lee como que se
		# dobla en vez de batir.
		var bat := deg_to_rad(ALAS_GRADOS) * sin(TAU * t)
		_poner_hueso("ala_izq", EJE_ALAS, -bat)
		_poner_hueso("ala_der", EJE_ALAS, bat)

		# Las pinzas de la proa, del mismo `t` que las alas. La amplitud es POR
		# ESPECIE y por defecto 0: depende de la anatomia y hay que medirla.
		#   Vexor  14 grados — la zona son 17 px en pantalla pero cambia la silueta
		#   Vex     0 grados — sus cuernos son mas verticales y a 141 px el gesto
		#                      no se distingue del reposo. Medido, no supuesto.
		# Pasarse convierte el gesto en un aspaviento; animar lo que no se ve es
		# gastar por nada.
		if _cuernos_grados > 0.0:
			var pinza := deg_to_rad(_cuernos_grados) * sin(TAU * t)
			_poner_hueso("cuerno_izq", EJE_CUERNOS, -pinza)
			_poner_hueso("cuerno_der", EJE_CUERNOS, pinza)

		var tc := reloj / COLA_CICLO + fase
		for k in 3:
			_poner_hueso("cola_%d" % (k + 1), EJE_COLA,
				deg_to_rad(COLA_GRADOS) * sin(TAU * (tc - k * COLA_DESFASE)))

		# Misma fase que el ala, un cuarto de vuelta despues: el pico del destello
		# cae en el punto mas bajo del batido.
		if not _mats_3d.is_empty():
			var onda := pow(0.5 - 0.5 * cos(TAU * t), _pulse_sharp)
			var e: float = _pulse_min + (_pulse_max - _pulse_min) * onda
			for mat in _mats_3d:
				mat.emission_energy_multiplier = e

	if en_vuelo:
		# la punta va delante: mientras la proa no mire al destino apenas avanza,
		# y acelera segun se alinea (coseno del error). Sin esto, un Skarnox
		# arrancaba a 190 u/s de costado durante todo su giro.
		var factor := 1.0
		if turn_deg_per_sec > 0.0:
			factor = maxf(cos(deg_to_rad(_error_de_proa(objetivo))), 0.0)
		position = position.move_toward(objetivo, speed * factor * delta)

	# atacando: el rumbo sigue al objetivo aunque se muevan los dos (o ninguno)
	if attack_target != null:
		if is_instance_valid(attack_target):
			_encarar(attack_target.position)
		else:
			attack_target = null
	elif not en_vuelo and es_npc:
		# NPCs parados: giro perezoso aleatorio cada 2-7 s (vida del original)
		_idle_timer -= delta
		if _idle_timer <= 0.0:
			_idle_timer = 2.0 + randf() * 5.0
			_girar_a(_visual_angle + (randf() - 0.5) * 360.0)


## Fija (o limpia con null) el objetivo que gobierna el rumbo.
func set_attack_target(objetivo_ataque: EntityNode) -> void:
	attack_target = objetivo_ataque
	if attack_target != null and is_instance_valid(attack_target):
		_encarar(attack_target.position)


## Orienta la proa hacia un punto del mundo (sin tocar el destino de vuelo).
func _encarar(punto: Vector2) -> void:
	var rumbo := punto - position
	if rumbo.length() > 1.0:
		_girar_a(_angulo_visual_hacia(punto),
			TURN_FLIGHT_DEG_PER_SEC if turn_deg_per_sec > 0.0 else 0.0)


## El angulo visual (proa arriba en el arte -> +90) que mira a un punto.
func _angulo_visual_hacia(punto: Vector2) -> float:
	return rad_to_deg((punto - position).angle()) + 90.0


## Cuanto se desvia la proa del rumbo, en grados (0 = mirando al frente).
func _error_de_proa(punto: Vector2) -> float:
	return absf(fposmod(_angulo_visual_hacia(punto) - _visual_angle + 180.0, 360.0) - 180.0)


## Fija el destino y orienta la proa UNA vez (no cada frame, como el prototipo).
func set_objetivo(destino: Vector2) -> void:
	# zona muerta del prototipo: un destino encima de la nave en pleno vuelo
	# no re-orienta (evita el trompo al clickear sobre ti mismo)
	var en_vuelo := position.distance_to(objetivo) > 0.5
	if en_vuelo and absf(destino.x - position.x) <= DEAD_ZONE \
			and absf(destino.y - position.y) <= DEAD_ZONE:
		objetivo = destino
		return
	objetivo = destino
	# atacando, el objetivo manda sobre el destino de vuelo (prioridad del prototipo)
	if attack_target != null and is_instance_valid(attack_target):
		return
	# proa hacia arriba en el arte -> +90 grados de pantalla
	_encarar(destino)


## Giro. Dos modelos, y la diferencia importa:
##
## - NAVES (turn_deg_per_sec = 0): duracion FIJA de TURN_TIME por el camino
##   corto, cuantizada a 32 pasos. Es el giro del prototipo, calibrado y
##   validado: da igual que el angulo sea de 11 o de 180 grados, siempre tarda
##   lo mismo. En una nave que persigue al cursor eso se siente responsivo.
##
## - BICHOS (turn_deg_per_sec > 0): velocidad ANGULAR constante y giro continuo.
##   Con el modelo de la nave, un alien se daba media vuelta en 0,1 s y parecia
##   un trompo. En el original esto no pasaba porque sus aliens eran animaciones
##   en bucle y NO rotaban nunca (`rotatable=false`); los nuestros son renders
##   con proa, asi que giran, pero a su ritmo: un Skarnox pesa y se nota.
func _girar_a(grados: float, dps := 0.0) -> void:
	var destino_ang := fposmod(grados, 360.0)
	if turn_steps > 0:
		var paso := 360.0 / turn_steps
		destino_ang = fposmod(roundf(grados / paso) * paso, 360.0)
	var delta := fposmod(destino_ang - _visual_angle + 180.0, 360.0) - 180.0
	if is_zero_approx(delta):
		return
	var duracion := TURN_TIME
	var vel := dps if dps > 0.0 else turn_deg_per_sec
	if vel > 0.0:
		duracion = clampf(absf(delta) / vel, 0.06, 8.0)
	if _turn_tween != null:
		_turn_tween.kill()
	_turn_tween = create_tween()
	_turn_tween.tween_method(_set_visual_angle, _visual_angle, _visual_angle + delta, duracion)


## Fija el rumbo VISUAL en el acto. Enganche para el autotest, como
## `encendido_completo()` en el portal: la prueba del relieve necesita el mismo
## bicho en tres rumbos distintos, y esperar a que termine un giro suave
## convertiria la prueba en una carrera. Mata el tween antes: si no, el giro en
## curso pisaria el rumbo que se acaba de fijar.
## Deja a la vista SOLO el casco. Enganche del autotest: la prueba del relieve
## mide hacia donde cae el lado claro de la nave, y las barras de vida y el
## nombre son brillantes, fijos en pantalla y NO giran — arrastran el centroide
## a un sitio estable pase lo que pase, o sea que la prueba pasaba con el
## relieve roto. Las llamas tampoco valen: son aditivas y si giran, asi que
## falsean en la otra direccion.
func solo_casco(activo: bool) -> void:
	for hijo in get_children():
		if hijo != _sprite and hijo is CanvasItem:
			hijo.visible = not activo
	for llama in _flames:
		llama.visible = not activo and _thrust > 0.02


## Sube el contraste del relieve durante la prueba y desactiva la proteccion de
## emisivos. No es hacer trampa, es subir el volumen para oir si el altavoz
## suena — con los valores de juego, la diferencia entre "la luz sigue a la nave"
## y "la luz se queda quieta" era de 0,217 contra 0,316 sobre un umbral de 0,30,
## o sea una moneda al aire. Exagerado, el caso roto no se mueve (con `giro` fijo
## el dibujo es una rotacion exacta pase lo que pase con la luz) y el bueno se
## dispara, que es justo la separacion que hace falta.
func relieve_exagerado(activo: bool) -> void:
	if _relieve == null:
		return
	_relieve.set_shader_parameter("contraste", 1.90 if activo else 0.90)
	# El emisivo tambien se destapa: si no, la prueba mediria menos justo en los
	# pixeles que mas brillan, que son los que mejor delatan un cambio de luz.
	#
	# Se mueven los DOS bordes y en orden. Subir solo el minimo dejaba
	# `smoothstep(2.0, 0.85, x)` con los bordes invertidos, que en GLSL no es
	# "protecciondesactivada" sino comportamiento indefinido: devolvia 1, o sea
	# textura cruda sin iluminar, y la prueba midio cero. La cazo ella misma.
	_relieve.set_shader_parameter("emisivo_min", 2.0 if activo else 0.55)
	_relieve.set_shader_parameter("emisivo_max", 3.0 if activo else 0.85)


## El `giro` que tiene ahora mismo el shader, en radianes. La prueba lo lee para
## comprobar la FONTANERIA —que girar la nave mueve el uniform— sin mirar un solo
## pixel, que es exacto y no depende de como interpole nadie.
func giro_shader() -> float:
	return float(_relieve.get_shader_parameter("giro")) if _relieve != null else 0.0


## Miente el `giro` a proposito. La prueba lo usa para comprobar el EFECTO: con la
## nave quieta en el mismo sitio, cambiar solo este numero tiene que cambiar los
## pixeles. Si el shader lo ignora, las dos fotos salen identicas al bit.
func forzar_giro(radianes: float) -> void:
	if _relieve != null:
		_relieve.set_shader_parameter("giro", radianes)


## Si esta nave lleva el shader de relieve montado. La prueba lo exige en vez de
## saltarselo: "no hay relieve" y "el relieve funciona" no pueden dar el mismo OK.
func tiene_relieve() -> bool:
	return _relieve != null


func angulo_visual() -> float:
	return _visual_angle


func rumbo_visual(grados: float) -> void:
	if _turn_tween != null and _turn_tween.is_valid():
		_turn_tween.kill()
	_set_visual_angle(grados)


func _set_visual_angle(grados: float) -> void:
	_visual_angle = fposmod(grados, 360.0)

	# Con malla 3D el que gira es el MODELO, no el sprite. Rotar el sprite giraria
	# la imagen ya rendida —y con ella la luz, que es justo lo que el 3D viene a
	# arreglar: la nave gira y el reflejo se queda donde estaba.
	if _modelo != null:
		# Solo el signo, SIN cuarto de vuelta. Medido con repro_orientacion.tscn: a
		# giro 0 el modelo ya mira ARRIBA en pantalla, que es la misma proa que el
		# arte 2D (`_angulo_visual_hacia` suma +90 justo por eso), y a giro 90 apunta
		# a la izquierda. Con la vuelta de mas el bicho perseguia de costado.
		_modelo.rotation.y = -deg_to_rad(_visual_angle)
		return
	if turn_steps <= 0:
		# giro continuo: un bicho girando despacio a 32 pasos se ve a tirones,
		# porque cada paso dura una eternidad
		_sprite.rotation_degrees = _visual_angle
		_avisar_giro()
		return
	# el giro SALTA de posicion en posicion durante el tween, como el flip de
	# frames del sheet original: es el look que distingue al prototipo
	var paso := 360.0 / turn_steps
	_sprite.rotation_degrees = roundf(_visual_angle / paso) * paso
	_avisar_giro()


## El shader de relieve necesita saber cuanto ha girado el sprite para
## contrarrotar la normal al espacio del mundo. Se avisa AQUI y no en _process
## porque aqui es exactamente cuando el rumbo cambia: un uniform por giro en vez
## de uno por fotograma.
func _avisar_giro() -> void:
	if _relieve != null:
		_relieve.set_shader_parameter("giro", _sprite.rotation)


## Eco autoritativo del server: correccion suave si la deriva es chica, snap si es grande.
func reconcile(x: float, y: float, tx: float, ty: float, nueva_vel: float, teleport: bool) -> void:
	speed = nueva_vel
	var server_pos := Vector2(x, y)
	if teleport or position.distance_to(server_pos) > 220.0:
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


## Casco y escudo absolutos del server; cada uno contra su propio mÃ¡ximo.
## Sin mÃ¡ximo conocido (entidad que nunca fue objetivo) la barra conserva lo
## que trajo su spawn: convertir absolutos sin denominador la harÃ­a mentir.
func set_estado_abs(hp: int, escudo: int) -> void:
	if max_hp_abs > 0:
		set_hp_pct(float(hp) / max_hp_abs)
	if max_shield_abs > 0:
		set_shield_pct(float(escudo) / max_shield_abs)


## Boca de caÃ±Ã³n desde la que sale el prÃ³ximo disparo, en coordenadas de MUNDO
## (respeta la rotaciÃ³n y escala del sprite). Sin caÃ±ones definidos, el centro.
func siguiente_canon() -> Vector2:
	if _canones.is_empty():
		return position
	var local := _canones[_canon_actual]
	_canon_actual = (_canon_actual + 1) % _canones.size()
	return _sprite.to_global(local)


## Chispazo en el casco: punto aleatorio del disco de click, suelto en el mundo.
func impacto_casco() -> void:
	if _impactos_casco >= 5:      # el tope del prototipo
		return
	_impactos_casco += 1
	var rnd := randf()
	var offset := Vector2.from_angle(rnd * TAU) * (click_radius * 0.5 * rnd)
	var anim := _sheet_anim("res://assets/fx/hull-impact.png", 96, 8, 0.45)
	anim.position = position + offset
	anim.rotation = randf() * TAU
	get_parent().add_child(anim)
	anim.tree_exited.connect(func(): _impactos_casco -= 1)


## Onda hexagonal en el escudo: sobre la circunferencia, del lado del atacante.
func impacto_escudo(desde: Vector2) -> void:
	if _impactos_escudo >= 9:     # el tope del prototipo
		return
	_impactos_escudo += 1
	var dir := (desde - position).normalized()
	var anim := _sheet_anim("res://assets/fx/shield-impact.png", 128, 8, 0.3)
	anim.position = dir * click_radius
	anim.rotation = dir.angle()
	anim.modulate = NTheme.SHIELD
	add_child(anim)               # hijo: sigue a la nave
	anim.tree_exited.connect(func(): _impactos_escudo -= 1)


static func _sheet_anim(ruta: String, lado: int, frames: int, duracion: float) -> AnimatedSprite2D:
	var sf := SpriteFrames.new()
	sf.add_animation("x")
	sf.set_animation_loop("x", false)
	sf.set_animation_speed("x", frames / duracion)
	var hoja: Texture2D = load(ruta)
	for i in frames:
		var f := AtlasTexture.new()
		f.atlas = hoja
		f.region = Rect2(i * lado, 0, lado, lado)
		sf.add_frame("x", f)
	var anim := AnimatedSprite2D.new()
	anim.sprite_frames = sf
	anim.z_index = 3
	anim.play("x")
	anim.animation_finished.connect(anim.queue_free)
	return anim


## Seleccion local: esquinas de mira alrededor de la entidad (estilo N).
func set_selected(sel: bool) -> void:
	_seleccionada = sel
	queue_redraw()


func _draw() -> void:
	if not _seleccionada:
		return
	var r := 58.0
	var l := 16.0
	var c := NTheme.HOSTILE if not es_heroe else NTheme.CYAN
	for esquina in [Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)]:
		var dx := -l if esquina.x > 0 else l
		var dy := -l if esquina.y > 0 else l
		draw_line(esquina, esquina + Vector2(dx, 0), c, 2.0)
		draw_line(esquina, esquina + Vector2(0, dy), c, 2.0)
