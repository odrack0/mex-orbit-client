# Catalogo de definiciones en JSON: naves, NPCs y mapas.
# Heredero del maps-config.xml + la tabla de anclajes de llamas del cliente
# original: nada de particularidades por asset hardcodeadas en el codigo.
# Los JSON viven en data/ y se cargan una vez (cache en memoria).
class_name AssetDefs

const RUTA_NAVES := "res://data/ships/%s.json"
const RUTA_NPCS := "res://data/npcs/%s.json"
const RUTA_MAPAS := "res://data/maps/%s.json"

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
