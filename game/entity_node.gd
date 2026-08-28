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
var _cuernos_min := 0.0          # rango de las pinzas de la proa, en grados
var _cuernos_max := 0.0          # (iguales = no se animan)
var _cuernos_eje := 1
## Nodo 2D que SI gira con el rumbo. En 2D las llamas y las bocas de canion
## cuelgan del sprite y giran con el; en 3D el sprite ya no gira —gira el modelo
## dentro del viewport— asi que se quedarian clavadas en pantalla mientras la nave
## da la vuelta. Este nodo hace ese papel, y con eso el resto del codigo de llamas
## y disparos sigue siendo el mismo.
var _anclas: Node2D
## Ancho maximo del ciclo de empuje (`0.55 + 0.15 * _thrust` a tope de gas). La
## base se calcula contra el para que la llama mida su tobera cuando va a fondo.
const LLAMA_ANCHO_MAX := 0.70
## Cuanto del ancho de su textura ocupa el penacho de verdad, medido cerca de la
## boca: `engine-flame.png` es de 64 px y el chorro va de la columna 10 a la 54,
## o sea 45 px. Sin corregirlo, escalar la TEXTURA al ancho de la tobera deja el
## chorro visible en un 70% de esa medida y no la cubre.
const LLAMA_RELLENO := 0.70
var _mats_3d: Array[BaseMaterial3D] = []   # copia por entidad, para pulsar la emision

## Diales del aleteo, medidos en el banco (pruebas/banco_3d.gd). Cambiarlos aqui
## cambia el bicho en el juego; el banco es donde se comparan, no donde se fijan.
## Aleteo y cola: POR ESPECIE, como los cuernos. Los valores por defecto son los
## que se midieron con el Vexor; cualquier bicho con otra anatomia se calibra en su
## JSON. Estaban como constantes y eso hacia que el Vex aleteara con los grados y
## el ritmo de otro bicho — el mismo fallo que ya costo una ronda con los cuernos.
## El defecto del ciclo, 2,17 s, son 26 fotogramas a 12 fps: el ritmo del atlas 2D.
var _alas_grados := 34.0
var _alas_ciclo := 2.17
var _alas_eje := 1            # Y en Godot. glTF permuta ejes: la Y de Blender sale Z
var _cola_grados := 9.0
var _cola_ciclo := 1.50       # reloj propio, como en el sprite
var _cola_desfase := 0.22     # por segmento, para que la onda recorra la cola
var _cola_eje := 2
## BRAZOS RADIALES (el Vorax). No es la cola con otro nombre: la cola es una
## cadena —cada hueso cuelga del anterior y la onda viaja a lo largo— y esto es un
## ANILLO de huesos hermanos, todos colgados de la raiz. El desfase va por indice
## de brazo, asi que la onda recorre el bicho girando alrededor del centro.
##
## Mover los ocho a la vez se leeria como que respira, no como que se mueve.
var _brazos_n := 0            # cuantos hay: se cuenta del esqueleto, no del JSON
var _brazos_grados := 0.0     # 0 = el bicho no tiene brazos
var _brazos_ciclo := 2.4
var _brazos_desfase := 0.125  # 1/8: con ocho brazos, la onda da una vuelta entera
var _brazos_eje := 2
## Los cuernos van al MISMO reloj que las alas, pero el EJE y el RANGO son de cada
## especie y se miden con repro_eje_hueso.tscn (`--solo-eje` y `--ambos`).
## No hay eje universal: depende de como esten plantados los cuernos.
##   Vexor  eje 1, [-14, +14]  — pinzas abiertas: el 1 gira dentro del plano
##   Vex    eje 2, [-20,   0]  — cuernos casi juntos en reposo: el 1 no los mueve
##                               (0,5 px a 35 grados) y en el 2 el positivo los
##                               CRUZA, asi que el recorrido solo va hacia abrir.
## El rango se escribe entero, con sus dos extremos, en vez de una amplitud: el
## limite seguro es justo lo que hay que dejar dicho.
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
	_shadow = position
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

	_montar_canones_json()
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
	sol.light_energy = AssetDefs.LUZ_MUNDO_ENERGIA
	sol.rotation = Vector3(deg_to_rad(AssetDefs.LUZ_MUNDO_ELEVACION),
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
	cam.size = AssetDefs.extension_3d(_modelo) * MARGEN
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
	_mats_3d = AssetDefs.materiales_3d(_modelo)
	# Los mismos diales del JSON que usa la capa emisiva de 2D. No son dos ajustes:
	# es el mismo latido, aplicado a la emision del material en vez de al alfa.
	var pul: Dictionary = d.get("pulse", {})
	_pulse_min = float(pul.get("min_intensity", 0.25))
	_pulse_max = float(pul.get("max_intensity", 2.6))
	_pulse_sharp = float(pul.get("sharpness", 2.4))
	var cg: Array = d.get("cuernos_grados", [])
	if cg.size() == 2:
		# Una asignacion por linea: GDScript NO tiene asignacion multiple. Escrito
		# como en Python, `a, b = x, y` es un error de PARSEO, no de ejecucion: se
		# cayo entity_node entero, con el world.gd que depende de su clase, y el
		# juego se quedaba en negro justo despues del login.
		_cuernos_min = float(cg[0])
		_cuernos_max = float(cg[1])
	_cuernos_eje = int(d.get("cuernos_eje", 1))
	# Los brazos se CUENTAN del esqueleto: el JSON dice como se mueven, no cuantos
	# son. Si el modelo se rehace con otro numero de tentaculos, el cliente se
	# entera solo en vez de quedarse moviendo los ocho primeros.
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


	_montar_anclajes(d)

	_sprite.texture = _vp.get_texture()
	# El viewport ya se rindio al tamanio de pantalla que pide el JSON, asi que
	# aqui no hay que reescalar por `screen_size` como con un PNG: basta deshacer
	# el factor de supermuestreo.
	_sprite.scale = Vector2.ONE / float(VIEWPORT_FACTOR)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	return true


## Lee los marcadores `tobera_*` y `canon_*` del modelo y monta con ellos las
## llamas de motor y las bocas de canion. Vienen en unidades del MODELO, que es lo
## unico que sobrevive a un cambio de encuadre: los anclajes del JSON estan en
## pixeles de la textura 2D vieja, que tiene otra escala y no valen aqui.
func _montar_anclajes(d: Dictionary) -> void:
	_anclas = Node2D.new()
	add_child(_anclas)

	# Pixeles de pantalla por unidad de mundo. Sale del mismo contrato que el
	# encuadre: el lado mayor del modelo ocupa `screen_size`.
	var escala := float(d.get("screen_size", 141)) / AssetDefs.extension_3d(_modelo)

	var ancho_boca := 0.0
	var toberas: Array[Vector2] = []
	var canones: Array[Vector2] = []
	for n in _modelo.find_children("*", "Node3D", true, false):
		var nombre := str(n.name)
		if not (nombre.begins_with("tobera") or nombre.begins_with("canon")):
			continue
		var p := _posicion_en_modelo(n as Node3D)
		# El plano de la camara es cenital: la X y la Z del modelo son la X y la Y
		# de pantalla. La Y del modelo es la altura y aqui no se ve.
		var punto := Vector2(p.x, p.z) * escala
		if nombre.begins_with("tobera"):
			toberas.append(punto)
			# El ancho de la boca viaja en la ESCALA del marcador (`marcar-anclajes`
			# lo mide y lo guarda ahi, que es un sitio estandar de glTF).
			ancho_boca = maxf(ancho_boca, (n as Node3D).scale.x * escala)
		else:
			canones.append(punto)

	if not canones.is_empty():
		# Se ordenan por X para que el alternado izquierda-derecha sea estable: el
		# orden en que vengan los nodos del GLB no es de fiar.
		canones.sort_custom(func(a, b): return a.x < b.x)
		_canones = canones

	var trail: Dictionary = d.get("engine_trail", {})
	if Quality.nivel("engine") >= 1 and not toberas.is_empty():
		toberas.sort_custom(func(a, b): return a.x < b.x)
		# CADA LLAMA MIDE LO QUE LE TOCA. `_anclas` no lleva escala —sus hijos van
		# en pixeles de pantalla ya calculados— asi que la llama se escala sola, y
		# el arte viene a 64 px de ancho, pensado para una nave dibujada a 512.
		# Sin escalar salia 3,6 veces mas grande de la cuenta y las cuatro se
		# fundian de dos en dos: se veian DOS motores en una nave con cuatro bocas.
		# Y con la escala de 2D (0,275 -> 17,6 px) tampoco llegaban: la separacion
		# entre toberas del Phoenix es de 10 px y seguirian solapando.
		# La llama mide lo que mide SU TOBERA, no lo que hay entre toberas. Con la
		# separacion salian mas gruesas que las bocas de las que salen: en el
		# Phoenix, 12,8 px de llama para una boca de 8,7. El ancho viene medido en
		# el marcador; si falta, se cae a la separacion.
		var ancho_llama := 64.0
		var tex_llama := load("res://assets/fx/engine-flame.png") as Texture2D
		if tex_llama != null:
			ancho_llama = maxf(1.0, float(tex_llama.get_width()))
		var tope := float(d.get("screen_size", 141)) / 512.0
		var ancho := ancho_boca
		if ancho <= 0.0:
			ancho = tope * ancho_llama
			if toberas.size() > 1:
				ancho = (toberas[-1].x - toberas[0].x) / float(toberas.size() - 1)
		var escala_llama: float = minf(ancho / ancho_llama, tope)
		# Se guarda como BASE, no se aplica al crear: `_process` pisa `scale` cada
		# fotograma con el ciclo de empuje. Fijarla aqui no servia de nada —la
		# escala buena duraba un frame— y por eso las llamas seguian saliendo de
		# 35-45 px por mucho que se midiera la boca.
		var base := Vector2.ONE * (escala_llama / (LLAMA_ANCHO_MAX * LLAMA_RELLENO))
		for punto in toberas:
			# Medio ancho de boca hacia PROA, para que el chorro salga de dentro de
			# la campana y no arranque justo en su filo. El marcador esta en el
			# vertice mas trasero de la tobera, que es su borde, no su garganta.
			_flames.append(_crear_llama_en(punto - Vector2(0.0, ancho * 0.5), trail, _anclas, base))


## Posicion de un nodo dentro del modelo, sumando la cadena de padres A MANO:
## esto corre en `setup()`, antes de que la entidad entre en el arbol, y ahi
## `global_position` no esta evaluada.
func _posicion_en_modelo(n: Node3D) -> Vector3:
	var t := Vector3.ZERO
	var actual: Node = n
	while actual != null and actual != _modelo:
		if actual is Node3D:
			t += (actual as Node3D).position
		actual = actual.get_parent()
	return t


## Lado mayor del modelo en el plano de la camara, en unidades de mundo. Se suman
## las AABB de las mallas: es el mismo dato que el validador imprime como CAJA.

## Duplica los materiales para que el destello sea de ESTE bicho y no de todos.
## Rompe el batching entre entidades; el banco lo midio con esa copia puesta, asi
## que la cifra que hay en pruebas/README.md ya la incluye.
## Los huesos que el cliente mueve, por nombre. Vacio si el modelo no trae
## esqueleto — un bicho puede ser malla quieta y seguir siendo valido.
func _mapear_huesos(nodo: Node) -> Dictionary:
	var esqs := nodo.find_children("*", "Skeleton3D", true, false)
	if esqs.is_empty():
		return {}
	var sk: Skeleton3D = esqs[0]
	# Se mapea lo que el ESQUELETO trae, no una lista escrita aqui. La lista fija
	# —alas, cuernos y cola_1..3— dejo fuera a los `brazo_*` del Vorax sin decir
	# nada: `_poner_hueso` salia por la puerta de atras en cada fotograma y los
	# tentaculos no se movian. El unico sintoma era un bicho quieto, que es lo
	# mismo que se ve cuando la animacion esta bien y la amplitud es pequenia.
	#
	# Recorrer el esqueleto ademas hace que un hueso nuevo funcione sin tocar el
	# cliente, que es como ya se cuentan los brazos.
	var mapa := {"sk": sk}
	# La rotacion de REPOSO se guarda porque `set_bone_pose_rotation` fija la pose
	# ENTERA, no un incremento: escribir un cuaternion a secas machaca el reposo
	# del hueso y la malla sale aplastada sin haber rotado nada.
	for idx in sk.get_bone_count():
		mapa[sk.get_bone_name(idx)] = {"i": idx,
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


## Bocas de canion del JSON, en espacio de la TEXTURA. Solo si el camino 3D no las
## ha puesto ya: ahi salen medidas del modelo, que es la fuente.
##
## Se llama en CADA reconstruccion, no solo en `setup()`. Antes solo en setup, y al
## cambiar de calidad `_canones` se quedaba con las del 3D —que estan en pixeles de
## pantalla, no de textura— asi que media disparaba desde donde no debia.
func _montar_canones_json() -> void:
	if not _canones.is_empty():
		return
	for canon in _def.get("cannons", []):
		_canones.append(Vector2(float(canon.get("x", 0)), float(canon.get("y", 0))))


## Rehace la parte visual con la calidad actual. Lo demas â€”nombre, barras,
## caÃ±ones, rumboâ€” no depende del nivel y se queda como esta.
func reconstruir() -> void:
	for n in [_sprite, _vp, _anclas]:
		if n != null:
			n.queue_free()
	_sprite = null
	_vp = null
	_anclas = null
	_modelo = null
	_huesos_3d.clear()
	_mats_3d.clear()
	_emissive = null
	_relieve = null      # su material moria con el sprite: dejarlo apuntando ahi
	_flames.clear()      # eran hijos del sprite: se van con el
	_canones.clear()     # se rehacen: en 3D salen del modelo y en 2D del JSON
	_ondas.clear()
	_anim_total = 0
	_anim_vaiven = false
	_construir_visual()
	_montar_canones_json()
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
	# `scale` por motor: lo escribe el horno para que la llama de MEDIA mida lo
	# mismo que la de alta. Estaba en el JSON desde siempre y no se leia.
	return _crear_llama_en(Vector2(float(motor.get("x", 0)), float(motor.get("y", 0))),
		trail, _sprite, Vector2.ONE * float(motor.get("scale", 1.0)))


## La misma llama, pero en un punto ya calculado y colgando de quien se le diga.
## En 2D cuelga del sprite (que gira) y en 3D de `_anclas` (que gira en su lugar).
func _crear_llama_en(punto: Vector2, trail: Dictionary, padre: Node2D,
		base := Vector2.ONE) -> Sprite2D:
	var llama := Sprite2D.new()
	llama.texture = load("res://assets/fx/engine-flame.png")
	llama.position = punto
	# La escala base viaja EN LA LLAMA, no en una variable de la entidad. Estaba
	# en la entidad y `reconstruir()` no la resetea: al pasar de alta a media, la
	# llama heredaba el factor del 3D y ademas lo multiplicaba por la escala del
	# sprite, quedandose en 3,9 px de ancho. Lo que no se resetea, no debe vivir
	# fuera del nodo que se rehace.
	llama.set_meta("base", base)
	# el arte de la llama apunta hacia ABAJO (+Y), que es la popa: sin rotar.
	# el pivote va en la boquilla para que crezca hacia atras, no hacia los lados
	llama.offset = Vector2(0, llama.texture.get_height() * 0.5)
	llama.modulate = AssetDefs.color(trail.get("color", "00E5FF"))
	llama.material = _material_add()
	llama.z_index = -1                   # detras del casco
	padre.add_child(llama)
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
			var base: Vector2 = llama.get_meta("base", Vector2.ONE)
			llama.scale = Vector2(0.55 + 0.15 * _thrust, _thrust * respiro) * base
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
		var t := fposmod(reloj / _alas_ciclo + fase, 1.0)

		# Un SENO, no un 0->1->0: el aleteo oscila alrededor del reposo, arriba y
		# abajo. Con la otra curva el ala solo baja y vuelve, y se lee como que se
		# dobla en vez de batir.
		var bat := deg_to_rad(_alas_grados) * sin(TAU * t)
		_poner_hueso("ala_izq", _alas_eje, -bat)
		_poner_hueso("ala_der", _alas_eje, bat)

		# Las pinzas de la proa, del mismo `t` que las alas. Recorre el rango de la
		# especie de extremo a extremo; con rango vacio no se toca el hueso.
		if _cuernos_max != _cuernos_min:
			var k := 0.5 - 0.5 * cos(TAU * t)      # 0..1, la fase del destello
			var pinza := deg_to_rad(_cuernos_min + (_cuernos_max - _cuernos_min) * k)
			_poner_hueso("cuerno_izq", _cuernos_eje, -pinza)
			_poner_hueso("cuerno_der", _cuernos_eje, pinza)

		# Los brazos: la misma onda recorriendo el ANILLO. Desfase por indice, no
		# por distancia al centro — todos nacen a la misma distancia.
		if _brazos_grados > 0.0 and _brazos_n > 0:
			var tb := reloj / _brazos_ciclo + fase
			for k in _brazos_n:
				_poner_hueso("brazo_%d" % (k + 1), _brazos_eje,
					deg_to_rad(_brazos_grados) * sin(TAU * (tb - k * _brazos_desfase)))

		var tc := reloj / _cola_ciclo + fase
		for k in 3:
			_poner_hueso("cola_%d" % (k + 1), _cola_eje,
				deg_to_rad(_cola_grados) * sin(TAU * (tc - k * _cola_desfase)))

		# Misma fase que el ala, un cuarto de vuelta despues: el pico del destello
		# cae en el punto mas bajo del batido.
		if not _mats_3d.is_empty():
			var onda := pow(0.5 - 0.5 * cos(TAU * t), _pulse_sharp)
			var e: float = _pulse_min + (_pulse_max - _pulse_min) * onda
			for mat in _mats_3d:
				mat.emission_energy_multiplier = e

	if en_vuelo:
		if turn_deg_per_sec > 0.0:
			# LA SOMBRA AUTORITATIVA. El server vuela LINEAL a velocidad plena
			# desde el instante en que el bicho elige rumbo (el original tambien:
			# su MoveCommand interpolaba lineal por tiempo). El freno de proa de
			# aqui abajo es pura presentacion, y si solo existiera el, cada giro
			# grande acumulaba un deficit que no se recuperaba nunca: un Vex a
			# 150 grados/s tarda 1,2 s en girar 180 y el server le saca ~320
			# unidades en ese rato. La divergencia se cobraba de golpe en el
			# siguiente EntityMove —a veces medio minuto despues— como un lerp
			# brusco o, pasadas 220 unidades, el snap que se veia como
			# teletransporte. Bichos brincando por todo el sector.
			#
			# La sombra reproduce al server tal cual; la posicion visual la
			# persigue. El freno de proa sigue mandando en el arranque (la punta
			# va delante, el Skarnox no despega de costado) pero el deficit
			# empuja: a mas atraso, mas gas, con tope. Girando, el atraso se
			# estabiliza en ~CATCHUP_DIST; alineado, se recupera en un par de
			# segundos acelerando suave — nunca de un salto.
			_shadow = _shadow.move_toward(objetivo, speed * delta)
			var factor := maxf(cos(deg_to_rad(_error_de_proa(objetivo))), 0.0)
			var deficit := position.distance_to(_shadow)
			var vel := speed * clampf(factor + deficit / CATCHUP_DIST, 0.0, CATCHUP_MAX)
			position = position.move_toward(_shadow, vel * delta)
		else:
			# naves: sin freno de proa (turn 0 = factor 1), lineal puro como el
			# server — no divergen y no necesitan sombra
			position = position.move_toward(objetivo, speed * delta)

	if attack_target != null and not is_instance_valid(attack_target):
		attack_target = null
	if attack_target != null and _attack_ttl > 0.0:
		_attack_ttl -= delta
		if _attack_ttl <= 0.0:
			attack_target = null

	# atacando: el rumbo sigue al objetivo aunque se muevan los dos (o ninguno)
	if attack_target != null:
		_encarar(attack_target.position)
	elif not en_vuelo and es_npc:
		# NPCs parados: giro perezoso aleatorio cada 2-7 s (vida del original)
		_idle_timer -= delta
		if _idle_timer <= 0.0:
			_idle_timer = 2.0 + randf() * 5.0
			_girar_a(_visual_angle + (randf() - 0.5) * 360.0)


## Fija (o limpia con null) el objetivo que gobierna el rumbo.
##
## `segundos` > 0 lo deja CADUCAR, y es para el rumbo que se DEDUCE de los
## disparos: un bicho encara a quien le esta pegando. Sin caducidad se quedaria
## mirando a su verdugo mucho despues de dejar de pelear con el. La tecla de
## disparo del heroe lo fija sin caducidad, porque ahi hay quien lo apague.
func set_attack_target(objetivo_ataque: EntityNode, segundos := 0.0) -> void:
	attack_target = objetivo_ataque
	_attack_ttl = segundos
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


## Si esta entidad se dibuja con MALLA 3D en vez de sprite.
func es_3d() -> bool:
	return _vp != null


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
	if _anclas != null:
		_anclas.rotation = deg_to_rad(_visual_angle)
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
	if turn_deg_per_sec > 0.0:
		# bichos: la verdad del server entra DURA en la sombra —es exactamente lo
		# que la sombra representa— y la posicion visual no se toca: ya la esta
		# persiguiendo cada frame, con gas extra si viene atrasada. El unico snap
		# que queda es el teleport de verdad (o una sombra rota por completo).
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
	# En 3D el sprite no gira: quien lleva la rotacion es `_anclas`.
	return (_anclas if _anclas != null else _sprite).to_global(local)


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
