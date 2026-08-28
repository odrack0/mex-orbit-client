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


## El vector de la luz del mundo, listo para el shader de relieve.
static func luz_mundo() -> Vector2:
	return Vector2.RIGHT.rotated(deg_to_rad(LUZ_MUNDO_GRADOS))


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
