# Fondo del mapa: las MISMAS capas del prototipo, montadas a mano en un
# CanvasLayer por debajo del mundo. Cada capa se recoloca con la formula
# del cliente Flash:
#     posicion_pantalla = -centro_camara / pFactor * zoom + centro_pantalla + offset * zoom
# El fondo principal (2048 px para un mundo de ~20800) usa pFactor 10: recorrer
# el mapa entero recorre justo la imagen entera.
class_name MapBackground
extends CanvasLayer

var _layers: Array = []        # {node, p_factor, offset}
var _starfield: Starfield2D
var _main: Sprite2D            # el skybox
var _world := Vector2.ONE
var _sun: Sprite2D
var _ghosts: Array[Sprite2D] = []

# fantasmas de la cadena de lentes: fraccion del eje sol->centro, escala y tinte
const GHOSTS := [
	[0.35, 0.30, Color(0.5, 0.9, 1.0, 0.35)],
	[0.65, 0.18, Color(1.0, 0.85, 0.5, 0.30)],
	[1.15, 0.42, Color(0.7, 0.6, 1.0, 0.25)],
	[1.55, 0.24, Color(0.5, 1.0, 0.9, 0.22)],
]


func _init() -> void:
	layer = -10


## Monta el stack del mapa. `config` (ver map_bg_config.gd):
## { main, tiles: [{tex, p_factor, scale, alpha}], planets: [{tex, pos, p_factor, scale}],
##   sun: {pos, p_factor}, world: Vector2 }
func build(config: Dictionary) -> void:
	# capa 0: mosaicos profundos primero (z por orden de insercion)
	for t: Dictionary in config.get("tiles_far", []):
		_add_tile(t, config.world)
	# capa 1: el fondo principal como SKYBOX — siempre cubre el viewport (el
	# cielo no se encoge con el zoom) y deriva proporcional al recorrido del
	# mapa. Evita el corte del fondo en las orillas y con zoom-out.
	if config.has("main"):
		_main = Sprite2D.new()
		_main.texture = config.main
		_main.centered = false
		add_child(_main)
		_world = config.world
	# planetas (los renders llegan por prompts; sin textura se omiten)
	for p: Dictionary in config.get("planets", []):
		if p.tex == null:
			continue
		var planeta := Sprite2D.new()
		planeta.texture = p.tex
		planeta.scale = Vector2.ONE * p.get("scale", 1.0)
		add_child(planeta)
		_layers.append({"node": planeta, "p_factor": p.p_factor, "offset": p.pos})
	# mosaicos medio y cercano encima
	for t: Dictionary in config.get("tiles_near", []):
		_add_tile(t, config.world)
	# el sol vive DENTRO del skybox (posicion en el espacio del fondo): se
	# mueve y escala con el, como una estrella pintada en el cielo
	if config.has("sun") and _main != null:
		_sun = Sprite2D.new()
		_sun.texture = load("res://assets/world/layers/sun.png")
		_sun.scale = Vector2.ONE * 0.9
		_sun.position = config.sun.pos
		_main.add_child(_sun)
		var ghost_tex: Texture2D = load("res://assets/world/layers/flare-ghost.png")
		for g: Array in GHOSTS:
			var ghost := Sprite2D.new()
			ghost.texture = ghost_tex
			ghost.scale = Vector2.ONE * g[1]
			ghost.modulate = g[2]
			ghost.material = _material_add()
			add_child(ghost)
			_ghosts.append(ghost)
	# el polvo estelar SIEMPRE, encima de todo el fondo
	_starfield = Starfield2D.new()
	add_child(_starfield)


func _add_tile(t: Dictionary, world: Vector2) -> void:
	var tile := Sprite2D.new()
	tile.texture = t.tex
	tile.centered = false
	tile.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	tile.region_enabled = true
	# el mosaico cubre el recorrido completo de su paralaje + margen de pantalla
	# margen amplio: con zoom-out el mosaico se encoge en pantalla y aun asi
	# debe cubrir el viewport en las orillas del mapa
	var escala: float = t.get("scale", 1.0)
	var span_x: float = world.x / float(t.p_factor) * escala + 8192.0
	var span_y: float = world.y / float(t.p_factor) * escala + 8192.0
	tile.region_rect = Rect2(0, 0, span_x, span_y)
	tile.self_modulate.a = t.get("alpha", 1.0)
	add_child(tile)
	_layers.append({"node": tile, "p_factor": t.p_factor, "offset": Vector2(-4096, -4096)})


## La formula del Flash para las capas + skybox para el fondo principal.
func update_parallax(center: Vector2, zoom: Vector2, viewport: Vector2) -> void:
	_starfield.resize(viewport)
	_starfield.advance(center, _starfield.get_process_delta_time())
	var screen_center := viewport * 0.5

	# skybox: cubre el viewport siempre; deriva del recorrido completo del mapa
	if _main != null:
		var tex := _main.texture.get_size()
		var s := maxf(viewport.x / tex.x, viewport.y / tex.y)
		_main.scale = Vector2.ONE * s
		var recorrido := tex * s - viewport          # cuanto puede derivar
		var t := (center / _world).clamp(Vector2.ZERO, Vector2.ONE)
		_main.position = -t * recorrido

	for entry: Dictionary in _layers:
		var node: Node2D = entry.node
		if not entry.has("base_scale"):
			entry["base_scale"] = node.scale
		node.position = -center / float(entry.p_factor) * zoom + screen_center \
			+ (entry.offset as Vector2) * zoom
		node.scale = (entry.base_scale as Vector2) * zoom

	# cadena de lentes: sobre el eje sol -> centro, solo con el sol en pantalla
	if _sun != null:
		var pos := _sun.get_global_transform_with_canvas().origin
		var visible_sol := pos.x >= -100 and pos.y >= -100 \
			and pos.x <= viewport.x + 100 and pos.y <= viewport.y + 100
		var eje := screen_center - pos
		for i in _ghosts.size():
			var ghost := _ghosts[i]
			ghost.visible = visible_sol
			ghost.position = pos + eje * (GHOSTS[i][0] as float)


static func _material_add() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m
