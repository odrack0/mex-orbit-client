# Catalogo de definiciones en JSON: naves, NPCs y mapas.
# Heredero del maps-config.xml + la tabla de anclajes de llamas del cliente
# original: nada de particularidades por asset hardcodeadas en el codigo.
# Los JSON viven en data/ y se cargan una vez (cache en memoria).
class_name AssetDefs

const RUTA_NAVES := "res://data/ships/%s.json"
const RUTA_NPCS := "res://data/npcs/%s.json"
const RUTA_MAPAS := "res://data/maps/%s.json"
const RUTA_PROPS := "res://data/props/%s.json"
const RUTA_AMMO := "res://data/ammo/%s.json"

## De donde viene la luz del mundo, en grados de pantalla (0 = derecha, 90 =
## abajo). UNA sola para todo lo que se ilumine, o el mundo se rompe: dos objetos
## con su propia luz se leen como dos recortes pegados, no como dos cosas en el
## mismo sitio. Es la razon de que viva aqui y no en el JSON de cada asset — un
## dial por asset invitaria justo a eso.
##
## 315 grados = arriba y a la izquierda. Es la convencion de toda la vida en arte
## 2D, y no por capricho: el ojo humano da por supuesta la luz de arriba, y el
## sesgo a la izquierda desambigua bulto de hueco.
const LUZ_MUNDO_GRADOS := 315.0

## Elevacion y energia de esa misma luz, para el camino 3D. Viven AQUI y no en
## entity_node por el motivo de arriba: son del MUNDO, no del asset. Estaban
## sueltas en el codigo del viewport, separadas del azimut que si estaba aqui, y
## eso invita a que alguien las toque por bicho sin darse cuenta de que rompe la
## unidad de la escena.
##
## La energia es 1.0 y no el 2.6 del banco: Blender hornea el sprite de media con
## un sol de 3,2, que cae cerca de 1.0 aqui, y con 2.6 el bicho salia lavado y no
## se parecia a su propio horneado.
const LUZ_MUNDO_ELEVACION := -48.0
const LUZ_MUNDO_ENERGIA := 1.0

## La luz de FONDO del mundo 3D y el tonemap, hermanas de las de arriba y con el
## mismo contrato: son del MUNDO, no del asset. Estaban copiadas a mano en OCHO
## sitios (entity_node, mundo_3d y seis escenas de pruebas — el banco ademas con
## 0.35 propio), asi que subir el ambiente exigia acertar ocho ediciones o la
## homologacion mentia segun que escena midiera.
##
## 0.65 y FILMIC contra el 0.28 lineal original: el mundo entero se percibia mas
## muerto que los modelos en el visor — un visor es un estudio con luz por todas
## partes, y con 0.28 una roca oscura no recibia casi nada. El ambiente sigue
## frio (azul grisaceo) para que el espacio se lea como espacio.
## OJO: cambiar esto descalibra el HORNO_AMBIENTE de cada bicho horneado — media
## se rehornea y se rehomologa con medir_emision, no se deja a ojo.
const LUZ_MUNDO_AMBIENTE_COLOR := Color(0.35, 0.40, 0.55)
const LUZ_MUNDO_AMBIENTE := 0.65


## El vector de la luz del mundo, listo para el shader de relieve.
static func luz_mundo() -> Vector2:
	return Vector2.RIGHT.rotated(deg_to_rad(LUZ_MUNDO_GRADOS))


## La luz de fondo y el tonemap del mundo, aplicados a un Environment. UN solo
## sitio para los NUEVE sitios que montan un mundo 3D: cambiar el ambiente aqui
## cambia el juego, las pruebas y la homologacion a la vez, que es la unica
## manera de que sigan midiendo lo mismo.
static func ambiente_mundo(ent: Environment) -> void:
	ent.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	ent.ambient_light_color = LUZ_MUNDO_AMBIENTE_COLOR
	ent.ambient_light_energy = LUZ_MUNDO_AMBIENTE
	# FILMIC y no lineal: el lineal recorta el hombro y aplana los medios — es
	# la otra mitad de "se ve mas muerto que en el visor", que tonemapea filmico.
	ent.tonemap_mode = Environment.TONE_MAPPER_FILMIC


## El material de relieve para una textura de normales, o null si no hay mapa.
## Vive aqui porque lo montan CUATRO sitios —naves y bichos, estacion, portal y
## caja— y una copia por sitio es una copia que se queda atras el dia que cambie
## la luz. Es la leccion del recorte del croma, que vivio copiado en dos scripts
## hasta que uno se quedo con el despill viejo.
static func material_relieve(ruta: String) -> ShaderMaterial:
	if ruta == "" or not ResourceLoader.exists(ruta):
		return null
	var mat := ShaderMaterial.new()
	mat.shader = load("res://game/shaders/relieve.gdshader")
	mat.set_shader_parameter("normal_map", load(ruta))
	mat.set_shader_parameter("luz_dir", luz_mundo())
	return mat


## La ruta del mapa de normales que toca segun el camino: con atlas manda el del
## atlas. Mezclarlos es peor que no tener ninguno — un mapa que no casa con la
## silueta que ilumina inventa bultos donde no hay nada.
static func ruta_normal(d: Dictionary, animado: bool) -> String:
	return d.get("frames", {}).get("normal", "") if animado else d.get("normal", "")

static var _cache := {}


static func nave(code: String) -> Dictionary:
	return _cargar(RUTA_NAVES % code)


static func npc(code: String) -> Dictionary:
	return _cargar(RUTA_NPCS % code)


## Definicion de una entidad por su type_id, sea nave o alien (vacia si no existe).
static func entidad(type_id: String) -> Dictionary:
	var d := nave(type_id)
	return d if not d.is_empty() else npc(type_id)


static func mapa(code: String) -> Dictionary:
	return _cargar(RUTA_MAPAS % code)


## Props del mundo (estacion, portal, caja...).
static func prop(code: String) -> Dictionary:
	return _cargar(RUTA_PROPS % code)


## Municion por loot_id ("ammo_cel_1") o por code ("cel-1").
static func ammo(id: String) -> Dictionary:
	var code := id.trim_prefix("ammo_").replace("_", "-")
	return _cargar(RUTA_AMMO % code)


static func _cargar(ruta: String) -> Dictionary:
	if _cache.has(ruta):
		return _cache[ruta]
	if not FileAccess.file_exists(ruta):
		_cache[ruta] = {}
		return {}
	var texto := FileAccess.get_file_as_string(ruta)
	var datos = JSON.parse_string(texto)
	if typeof(datos) != TYPE_DICTIONARY:
		push_error("JSON invalido: " + ruta)
		datos = {}
	_cache[ruta] = datos
	return datos


## Convierte "00E5FF" (o "#00E5FF") a Color; blanco si falta.
static func color(hex: Variant, defecto := Color.WHITE) -> Color:
	if typeof(hex) != TYPE_STRING or (hex as String).is_empty():
		return defecto
	return Color.html(hex as String)


## El MUNDO 3D de un asset: viewport propio, entorno, la luz del mundo y una
## camara ortografica. Devuelve {vp, modelo, cam}.
##
## Vive aqui porque ya son DOS los sitios que lo montan —los bichos y naves en
## `EntityNode`, y la estacion en `world.gd`— y esta receta tiene demasiadas
## trampas para tenerla escrita dos veces. Cada linea de aqui abajo esta puesta
## por un fallo concreto que ya ocurrio, y una copia que se quede atras los
## repite todos.
##
## `lado` es el tamanio del destino en pixeles y `extension` el lado mayor del
## modelo en unidades del mundo 3D. `elevacion` en grados: 90 es cenital.
static func mundo_3d(escena: PackedScene, lado: int, extension: float,
		elevacion: float, con_glow: bool, glow: Dictionary = {}) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = Vector2i(lado, lado)
	# Fondo transparente: el asset se compone sobre el mundo 2D, no lo tapa.
	vp.transparent_bg = true
	# MUNDO PROPIO, obligatorio. Sin esto los viewports comparten el World3D del
	# padre: todos los modelos viven en el mismo mundo y en el mismo origen, y
	# cada camara los ve TODOS — una bola de copias que crece segun entran mas.
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# BORRAR SIEMPRE, explicito. Sin esto el destino acumula y cada fotograma deja
	# su copia encima del anterior.
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS

	var modelo := escena.instantiate()
	vp.add_child(modelo)

	var ent := Environment.new()
	ent.background_mode = Environment.BG_CLEAR_COLOR
	ambiente_mundo(ent)
	# GLOW: sin el, la emision se RECORTA a 1.0 y lo encendido se lee como
	# "claro" en vez de como "encendido".
	# Los valores por defecto se calibraron con las VETAS de un bicho: lineas
	# finas donde el problema era que no se leyeran como encendidas. Un asset con
	# una zona emisiva grande —el reactor de la estacion— con esos mismos numeros
	# revienta en un halo que se sale de la geometria. Por eso son ajustables por
	# asset y no una constante.
	if con_glow:
		ent.glow_enabled = true
		ent.glow_intensity = float(glow.get("intensity", 1.0))
		ent.glow_bloom = float(glow.get("bloom", 0.25))
		ent.glow_hdr_threshold = float(glow.get("threshold", 0.9))
	var we := WorldEnvironment.new()
	we.environment = ent
	vp.add_child(we)

	# La MISMA luz del mundo que usa el relieve en 2D: si cada asset se ilumina
	# por su cuenta, dos vecinos se leen como dos recortes pegados.
	var sol := DirectionalLight3D.new()
	sol.light_energy = LUZ_MUNDO_ENERGIA
	sol.rotation = Vector3(deg_to_rad(LUZ_MUNDO_ELEVACION), deg_to_rad(LUZ_MUNDO_GRADOS), 0.0)
	sol.shadow_enabled = false
	vp.add_child(sol)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	# El encuadre se MIDE del modelo, nunca una constante: con una a ojo el asset
	# desborda su propio hueco.
	cam.size = extension
	vp.add_child(cam)
	var el := deg_to_rad(elevacion)
	# `look_at_from_position` y no `look_at`: esto corre antes de estar en el
	# arbol. Y el "arriba" es -Z, no Y: a 90 grados la camara mira justo por Y y
	# el vector de arriba seria paralelo a su eje de vista.
	cam.look_at_from_position(Vector3(0.0, 8.0 * sin(el), 8.0 * cos(el)),
		Vector3.ZERO, Vector3.FORWARD)
	cam.current = true
	return {"vp": vp, "modelo": modelo, "cam": cam}


## La HUELLA del modelo —su lado mayor en el plano XZ— en unidades de su mundo.
## Se usa para encuadrar la camara cenital.
##
## No entra la altura (Y) a proposito: con una camara desde arriba lo que tiene
## que caber es la planta. Metiendo el alto, una torre como la estacion —1,92 de
## alto contra 1,05 de planta— obligaria a alejar la camara casi al doble y la
## estacion saldria diminuta dentro de su propio hueco.
##
## Y la transformacion se acumula A MANO hasta la raiz: `transform` es solo la
## local y `global_transform` NO vale, porque esto corre antes de que el modelo
## entre en el arbol. Usarlo devuelve la identidad y suelta un error por consola
## que no detiene nada — el encuadre sale mal y el juego sigue.
static func extension_3d(nodo: Node) -> float:
	var caja := AABB()
	var primera := true
	for m in nodo.find_children("*", "MeshInstance3D", true, false):
		var malla: MeshInstance3D = m
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


## Lo que el modelo OCUPA EN PANTALLA con la camara a esa elevacion, en unidades
## de mundo. Es lo que hay que encuadrar cuando la camara no es cenital.
##
## `extension_3d` mide la HUELLA (X y Z) y a 90 grados eso es exactamente lo que
## se ve. En cuanto la camara baja deja de serlo: una torre de 1,92 de alto sobre
## una planta de 1,05 se sale por arriba, porque su altura pasa a proyectarse
## sobre la pantalla. Se proyectan las ocho esquinas de la caja al espacio de la
## camara y se toma el lado mayor — exacto y sin casos especiales.
static func extension_vista(nodo: Node, elevacion: float) -> float:
	var caja := AABB()
	var primera := true
	for m in nodo.find_children("*", "MeshInstance3D", true, false):
		var malla: MeshInstance3D = m
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
	# La misma camara que monta `mundo_3d`, para medir lo que ella va a ver.
	var el := deg_to_rad(elevacion)
	var ojo := Vector3(0.0, 8.0 * sin(el), 8.0 * cos(el))
	var vista := Transform3D().looking_at(-ojo, Vector3.FORWARD)
	vista.origin = ojo
	var inv := vista.affine_inverse()
	var ancho := 0.0
	var alto := 0.0
	for i in 8:
		var e := caja.get_endpoint(i)
		var v := inv * e
		ancho = maxf(ancho, absf(v.x) * 2.0)
		alto = maxf(alto, absf(v.y) * 2.0)
	return maxf(maxf(ancho, alto), 0.001)


## Los materiales del modelo, DUPLICADOS por instancia, para poder pulsar la
## emision de cada asset sin tocar a los demas: un material de Godot se comparte
## entre todas las instancias que lo usan.
static func materiales_3d(nodo: Node) -> Array[BaseMaterial3D]:
	var salida: Array[BaseMaterial3D] = []
	for m in nodo.find_children("*", "MeshInstance3D", true, false):
		var malla: MeshInstance3D = m
		var mat = malla.get_active_material(0)
		if mat is BaseMaterial3D:
			var copia: BaseMaterial3D = mat.duplicate()
			# A DOS CARAS: la malla de Meshy trae el giro de las caras
			# inconsistente y con descarte trasero salen huecos donde Blender
			# enseniaba solido.
			copia.cull_mode = BaseMaterial3D.CULL_DISABLED
			malla.set_surface_override_material(0, copia)
			salida.append(copia)
	return salida
