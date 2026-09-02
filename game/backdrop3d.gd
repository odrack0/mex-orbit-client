# El FONDO del mundo (F3 del plan-cliente-3d, G§10): profundidad DE VERDAD.
# Ya no hay formula de paralaje — cada capa vive a su cota y la camara en
# perspectiva hace el resto, que es exactamente como lo hacia el original:
#
#   cielo      -> Sky del Environment (shaders/sky.gdshader): estrellas con
#                 twinkle, infinito, recentrado gratis
#   telon      -> el arte del mapa a y=-4200, la capa mas profunda
#   nebulosas  -> mosaicos de quads a y = -3500 + capa*550, CADA tile con su
#                 propio jitter vertical (-500..-200): el paralaje entre tiles
#                 lo produce la camara (la joya del tilemap del original)
#   planetas   -> a cota segun su p_factor (heredado del JSON del mapa)
#   sol        -> quad aditivo girando + cadena de flares proyectada al HUD
#   polvo      -> GPUParticles3D anclado al MUNDO que se recentra a saltos de
#                 rejilla siguiendo a la camara: la capa que vende el vuelo
#
# Todo sale del MISMO data/maps/<code>.json de siempre (via MapBgConfig): los
# p_factor del 2D se reinterpretan como profundidad. Determinista por mapa:
# mismas semillas, mismo cielo.
class_name Backdrop3D
extends Node3D

## Diales del fondo: data/config/backdrop.json (nada calibrable vive en el codigo).
static var CFG: Dictionary = AssetDefs.config("backdrop")
static var _LAYERS: Dictionary = CFG.get("layers", {})
static var _TILES: Dictionary = CFG.get("tiles", {})
static var _PROPS: Dictionary = CFG.get("props", {})
static var _DUST: Dictionary = CFG.get("dust", {})
static var _FLARES: Dictionary = CFG.get("flares", {})

## Cotas del original: capas de nebulosa desde -3500 subiendo 550 por capa,
## jitter por tile entre -500 y -200 (G§10.2).
static var LAYER_BASE: float = AssetDefs.num(_LAYERS, "layer_base", -3500.0)
static var LAYER_STEP: float = AssetDefs.num(_LAYERS, "layer_step", 550.0)
static var JITTER_MIN: float = AssetDefs.num(_LAYERS, "jitter_min", -500.0)
static var JITTER_MAX: float = AssetDefs.num(_LAYERS, "jitter_max", -200.0)
static var BACKDROP_Y: float = AssetDefs.num(_LAYERS, "backdrop_y", -4200.0)
## Alto del telon = alto del mapa x este factor (el ancho sigue el aspecto).
static var BACKDROP_HEIGHT_FACTOR: float = AssetDefs.num(_LAYERS, "backdrop_height_factor", 1.8)
## Profundidad de planetas y sol = p_factor x esto; sus posiciones vienen en el
## espacio del fondo (2048x1280) y se pasan a mundo con POSITION_SCALE.
static var DEPTH_PER_P_FACTOR: float = AssetDefs.num(_LAYERS, "depth_per_p_factor", 250.0)
static var POSITION_SCALE: float = AssetDefs.num(_LAYERS, "position_scale", 10.0)
## Tamanio del tile en mundo = ancho_textura * scale * este factor (el original
## usaba 5 sobre tiles de ~256; nuestro arte es de 1024).
static var TILE_FACTOR: float = AssetDefs.num(_TILES, "tile_factor", 1.5)
## Fraccion de celdas VACIAS del mosaico (rompe la repeticion, como la mascara
## de agujeros del original).
static var TILE_GAPS: float = AssetDefs.num(_TILES, "tile_gaps", 0.25)
## Cuanto cubre el mosaico mas alla del mapa.
static var MARGIN: float = AssetDefs.num(_TILES, "margin", 1.5)
## Cada tile sortea su alfa entre esta fraccion y 1.0 del alfa de la capa.
static var TILE_ALPHA_JITTER_MIN: float = AssetDefs.num(_TILES, "alpha_jitter_min", 0.7)

## Props de fondo: rugosidad de las mallas, lado por defecto de un plano y
## cota por defecto.
static var PROP_MESH_ROUGHNESS: float = AssetDefs.num(_PROPS, "mesh_roughness", 0.8)
static var PROP_PLANE_SIDE: float = AssetDefs.num(_PROPS, "plane_side", 1000.0)
static var PROP_Y: float = AssetDefs.num(_PROPS, "y", -2000.0)

## El polvo estelar (G§10.4): volumen alrededor del foco, anclado al mundo.
static var DUST_COUNT: int = int(AssetDefs.num(_DUST, "count", 1500.0))
static var DUST_BOX: Vector3 = AssetDefs.vec3(_DUST.get("box"), Vector3(4200.0, 300.0, 4200.0))
static var DUST_Y: float = AssetDefs.num(_DUST, "y", -160.0)
static var DUST_LIFE: float = AssetDefs.num(_DUST, "life", 25.0)
static var DUST_SPREAD: float = AssetDefs.num(_DUST, "spread", 180.0)
static var DUST_SPEED_MIN: float = AssetDefs.num(_DUST, "speed_min", 2.0)
static var DUST_SPEED_MAX: float = AssetDefs.num(_DUST, "speed_max", 6.0)
static var DUST_SCALE_MIN: float = AssetDefs.num(_DUST, "scale_min", 0.5)
static var DUST_SCALE_MAX: float = AssetDefs.num(_DUST, "scale_max", 1.0)
static var DUST_COLOR_DARK: Color = _rgba(_DUST.get("color_dark"), Color(0.28, 0.28, 0.28))
static var DUST_COLOR_LIGHT: Color = _rgba(_DUST.get("color_light"), Color(0.52, 0.52, 0.52))
static var DUST_TINT_DARKEN: float = AssetDefs.num(_DUST, "tint_darken", 0.4)
static var DUST_MOTE_SIZE: float = AssetDefs.num(_DUST, "mote_size", 2.4)
static var DUST_MOTE_TEX_PX: int = int(AssetDefs.num(_DUST, "mote_tex_px", 16.0))

## Los flares: textura del sol y de sus fantasmas, margen de pantalla en el que
## siguen visibles, y el lensFlare del original (patron de las lentes, cuantas
## y cuanto se extiende la cadena mas alla del centro).
static var SUN_TEXTURE: String = str(_FLARES.get("sun_texture", "res://assets/world/layers/sun.png"))
static var GHOST_TEXTURE: String = str(_FLARES.get("ghost_texture", "res://assets/world/layers/flare-ghost.png"))
static var GHOST_SCREEN_MARGIN_PX: float = AssetDefs.num(_FLARES, "ghost_screen_margin_px", 100.0)
static var DO_LENS_PATTERN: String = str(_FLARES.get("do_lens_pattern", "res://assets/do-ref/flare/lens%d.png"))
static var DO_LENS_COUNT: int = int(AssetDefs.num(_FLARES, "do_lens_count", 11.0))
static var DO_FLARE_SPREAD: float = AssetDefs.num(_FLARES, "do_spread", 3.0)

var _bounds := Vector2.ONE
var _dust: GPUParticles3D
var _sun: MeshInstance3D
var _sun_spin: float = MapBgConfig.SUN_SPIN
var _sun_pos := Vector2.ZERO
var _ghosts: Array[Sprite2D] = []

## fantasmas de la cadena de lentes: fraccion del eje sol->centro, escala y tinte
## ({axis_fraction, scale, color}, del JSON)
static var GHOSTS: Array = _ghosts_from(_FLARES.get("ghosts", [
	{"axis_fraction": 0.35, "scale": 0.30, "color": [0.5, 0.9, 1.0, 0.35]},
	{"axis_fraction": 0.65, "scale": 0.18, "color": [1.0, 0.85, 0.5, 0.30]},
	{"axis_fraction": 1.15, "scale": 0.42, "color": [0.7, 0.6, 1.0, 0.25]},
	{"axis_fraction": 1.55, "scale": 0.24, "color": [0.5, 1.0, 0.9, 0.22]},
]))


## Un color desde un JSON `[r, g, b, a]` en float (los hex pierden precision).
static func _rgba(v: Variant, fallback: Color) -> Color:
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 3:
		var a: Array = v
		return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() >= 4 else 1.0)
	return fallback


static func _ghosts_from(items: Array) -> Array:
	var out := []
	for g: Dictionary in items:
		out.append({
			"axis_fraction": AssetDefs.num(g, "axis_fraction", 0.0),
			"scale": AssetDefs.num(g, "scale", 1.0),
			"color": _rgba(g.get("color"), Color.WHITE),
		})
	return out


## Monta el fondo del mapa. `config` es el de MapBgConfig.para().
func build(config: Dictionary, bounds: Vector2, rng_seed: int) -> void:
	_bounds = bounds
	var level := Quality.level("background")
	var tint: Color = config.get("starfield_tint", MapBgConfig.STARFIELD_TINT)
	Stage3D.instance.set_sky(tint)
	if level < 1:
		return                    # baja: solo el cielo

	# el telon: el arte del mapa como la capa mas profunda
	if config.has("main"):
		var tex: Texture2D = config.main
		var backdrop_plane := MeshInstance3D.new()
		var q := QuadMesh.new()
		var hgt := bounds.y * BACKDROP_HEIGHT_FACTOR
		q.size = Vector2(hgt * float(tex.get_width()) / float(tex.get_height()), hgt)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = tex
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		q.material = mat
		backdrop_plane.mesh = q
		backdrop_plane.rotation.x = -PI / 2
		backdrop_plane.position = Vector3(bounds.x * 0.5, BACKDROP_Y, bounds.y * 0.5)
		add_child(backdrop_plane)

	# planetas y sol, a la cota que dicta su p_factor (mas factor = mas hondo)
	for p: Dictionary in config.get("planets", []):
		if p.tex == null:
			continue
		var depth: float = float(p.p_factor) * DEPTH_PER_P_FACTOR
		var pos: Vector2 = (p.pos as Vector2) * POSITION_SCALE
		# a mas hondo, mas grande, para que EN PANTALLA mida como su arte pedia
		var apparent := (Stage3D.DIST + depth) / Stage3D.DIST
		var s := Stage3D.flat_sprite(p.tex,
			float((p.tex as Texture2D).get_height()) * float(p.get("scale", 1.0)) * apparent)
		s.position = Vector3(pos.x, -depth, pos.y)
		add_child(s)
	if config.has("sun"):
		var sun_tex: Texture2D = load(SUN_TEXTURE)
		var sun_depth: float = float(config.sun.get("p_factor", MapBgConfig.SUN_P_FACTOR)) * DEPTH_PER_P_FACTOR
		var sun_pos: Vector2 = (config.sun.pos as Vector2) * POSITION_SCALE
		_sun_pos = sun_pos
		var apparent_sun := (Stage3D.DIST + sun_depth) / Stage3D.DIST
		_sun = Stage3D.additive_quad(sun_tex,
			float(sun_tex.get_width()) * float(config.sun.get("scale", MapBgConfig.SUN_SCALE)) * apparent_sun, false)
		_sun.position = Vector3(sun_pos.x, -sun_depth, sun_pos.y)
		add_child(_sun)
		_sun_spin = float(config.sun.get("spin", MapBgConfig.SUN_SPIN))
		_mount_flares()

	# PROPS de fondo (F3+): las mallas y planos que habitan el mapa — lunas,
	# estaciones mineras, satelites — a su cota, con giro lento. Es la pieza que
	# el descriptor display3D del original monta por mapa; los transforms vienen
	# del JSON del mapa tal cual.
	for prop: Dictionary in config.get("props", []):
		if prop.has("lensflare"):
			_mount_flare_do(Vector3(float(prop.get("x", 0)), float(prop.get("y", 0)),
				float(prop.get("z", 0))))
		else:
			_mount_prop(prop)

	# el polvo estelar que vende el vuelo
	_mount_dust(tint, float(config.get("starfield_tint_ratio", MapBgConfig.STARFIELD_TINT_RATIO)))

	if level < 2:
		return                    # media: sin mosaicos de nebulosa

	# los mosaicos de profundidad: far abajo, near arriba (orden = su lista)
	var layer_list: Array = []
	for t in config.get("tiles_far", []):
		layer_list.append(t)
	for t in config.get("tiles_near", []):
		layer_list.append(t)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for i in layer_list.size():
		# `y` (cota absoluta) viene del tilemap del display3D original:
		# y = -3500 + layer*550 lo trae ya calculado el JSON del mapa
		_mount_tilemap(layer_list[i], float(layer_list[i].get("y", LAYER_BASE + float(i) * LAYER_STEP)), rng)


## Un mosaico de quads con el MISMO arte, roto con las armas del original:
## celdas vacias, giros de 90 y el jitter vertical POR TILE que convierte la
## capa en profundidad de verdad.
func _mount_tilemap(t: Dictionary, y_base: float, rng: RandomNumberGenerator) -> void:
	var tex: Texture2D = t.tex
	if tex == null:
		return
	# ATLAS DE VARIANTES (el arma del original contra la repeticion): si el JSON
	# declara `celdas`, la textura es una rejilla `grid`x`grid` de nubes y cada
	# tile del mosaico sortea la suya — como la seleccion de tiles del original.
	var cells := int(t.get("cells", 1))
	var grid := int(t.get("grid", 1 if cells <= 1 else MapBgConfig.TILE_GRID))
	var side_px := float(tex.get_width()) / float(grid)
	# `lado` explicito = tamano del tile en unidades de mundo (el tilemap del
	# original: tileWidth * tileScale); si no, se deriva del arte
	var side := float(t.get("side", side_px * float(t.get("scale", 1.0)) * TILE_FACTOR))
	var alpha := float(t.get("alpha", 1.0))
	var margin := float(t.get("margin", MARGIN))
	var span := _bounds * margin
	var origin := -_bounds * (margin - 1.0) * 0.5
	var nx := maxi(int(ceil(span.x / side)), 1)
	var ny := maxi(int(ceil(span.y / side)), 1)
	# la MASCARA de agujeros del original (blanco = nube, negro/alfa 0 = vacio),
	# estirada sobre el span entero; sin mascara, huecos aleatorios
	var mask_tex: Image = null
	if t.has("mask"):
		mask_tex = (t.mask as Texture2D).get_image()
	for cx in nx:
		for cy in ny:
			if mask_tex != null:
				var mp := mask_tex.get_pixel(
					clampi(int((float(cx) + 0.5) / float(nx) * mask_tex.get_width()), 0, mask_tex.get_width() - 1),
					clampi(int((float(cy) + 0.5) / float(ny) * mask_tex.get_height()), 0, mask_tex.get_height() - 1))
				if mp.r < 0.5 or mp.a < 0.5:
					continue
			elif rng.randf() < TILE_GAPS:
				continue
			var s := Stage3D.flat_sprite(tex, side, grid)
			if cells > 1:
				s.hframes = grid
				s.vframes = grid
				s.frame = rng.randi_range(0, cells - 1)
			s.position = Vector3(origin.x + (float(cx) + 0.5) * side,
				y_base + rng.randf_range(JITTER_MIN, JITTER_MAX),
				origin.y + (float(cy) + 0.5) * side)
			s.rotation.y = float(rng.randi_range(0, 3)) * PI * 0.5
			s.modulate.a = alpha * rng.randf_range(TILE_ALPHA_JITTER_MIN, 1.0)
			add_child(s)


var _turning: Array = []          # [{nodo, spin (grados/s por eje)}]


## Un prop del fondo: malla OBJ con su textura (iluminada por el sol del mundo)
## o un plano gigante. Campos del JSON: malla|plano, tex, x/y/z (unidades de
## mundo; y negativo = hondo), escala, rot_x/rot_y/rot_z (grados) y spin
## {x,y,z} en grados/segundo — el "append" del background_animation original.
func _mount_prop(p: Dictionary) -> void:
	var node: Node3D = null
	var tex: Texture2D = null
	var tex_path := str(p.get("tex", ""))
	if tex_path != "" and ResourceLoader.exists(tex_path):
		tex = load(tex_path)
	# `modulate` atenua (o tine) el prop: en un plano aditivo es LA palanca de
	# intensidad — un techo de nebulosa a plena potencia lava el cielo entero.
	var mod := AssetDefs.color(p.get("modulate", "FFFFFF"))
	if p.has("mesh"):
		var path := str(p.mesh)
		if not ResourceLoader.exists(path):
			push_warning("fondo: falta la malla %s" % path)
			return
		var mi := MeshInstance3D.new()
		mi.mesh = load(path)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.albedo_color = mod
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = PROP_MESH_ROUGHNESS
		mi.material_override = mat
		node = mi
	elif p.has("plane"):
		var side := float(p.get("scale", PROP_PLANE_SIDE))
		if bool(p.get("additive", false)):
			var mi := Stage3D.additive_quad(tex, side, false)
			(mi.material_override as StandardMaterial3D).albedo_color = mod
			(mi.material_override as StandardMaterial3D).render_priority = int(p.get("priority", 0))
			mi.rotation.x = 0.0          # el JSON manda la orientacion completa
			node = mi
		else:
			var mi := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(side, side)
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_texture = tex
			mat.albedo_color = mod
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			# `prioridad`: orden explicito entre transparentes casi co-planares
			# (el techo de nebulosa va DETRAS del planeta: R 50010 vs 50000)
			mat.render_priority = int(p.get("priority", 0))
			q.material = mat
			mi.mesh = q
			node = mi
	else:
		return
	node.position = Vector3(float(p.get("x", 0)), float(p.get("y", PROP_Y)), float(p.get("z", 0)))
	if p.has("mesh"):
		node.scale = Vector3.ONE * float(p.get("scale", 1.0))
	node.rotation_degrees = Vector3(float(p.get("rot_x", 0)), float(p.get("rot_y", 0)),
		float(p.get("rot_z", 0)))
	add_child(node)
	var spin: Dictionary = p.get("spin", {})
	if not spin.is_empty():
		_turning.append({"node": node, "spin": Vector3(float(spin.get("x", 0)),
			float(spin.get("y", 0)), float(spin.get("z", 0)))})


## El polvo (G§10.4): particulas en un volumen alrededor del foco, SUELTAS AL
## MUNDO (local_coords off) con deriva lenta; el emisor SIGUE al foco cada
## frame y las particulas viejas se quedan donde nacieron.
func _mount_dust(tint: Color, tint_ratio: float) -> void:
	_dust = GPUParticles3D.new()
	_dust.amount = DUST_COUNT
	_dust.lifetime = DUST_LIFE
	_dust.preprocess = DUST_LIFE
	_dust.local_coords = false
	_dust.explosiveness = 0.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = DUST_BOX * 0.5
	pm.direction = Vector3(1, 0, 0)
	pm.spread = DUST_SPREAD
	pm.initial_velocity_min = DUST_SPEED_MIN
	pm.initial_velocity_max = DUST_SPEED_MAX
	pm.gravity = Vector3.ZERO
	pm.scale_min = DUST_SCALE_MIN
	pm.scale_max = DUST_SCALE_MAX
	# la variedad de color del original: grises con una fraccion tenida del mapa.
	# TENUES a proposito: a casi blanco las motas parecian "estrellas pegadas al
	# mapa" en vez de polvo — deben leerse solo en movimiento, no quietas.
	var g := Gradient.new()
	g.set_color(0, DUST_COLOR_DARK)
	g.add_point(1.0 - tint_ratio, DUST_COLOR_LIGHT)
	g.set_color(1, tint.darkened(DUST_TINT_DARKEN))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_initial_ramp = gt
	_dust.process_material = pm

	var q := QuadMesh.new()
	q.size = Vector2(DUST_MOTE_SIZE, DUST_MOTE_SIZE)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = _mote_tex()
	q.material = mat
	_dust.draw_pass_1 = q
	add_child(_dust)


static var _mote_tex_cache: GradientTexture2D


static func _mote_tex() -> GradientTexture2D:
	if _mote_tex_cache == null:
		var g := Gradient.new()
		g.set_color(0, Color.WHITE)
		g.set_color(1, Color(1, 1, 1, 0))
		_mote_tex_cache = GradientTexture2D.new()
		_mote_tex_cache.gradient = g
		_mote_tex_cache.width = DUST_MOTE_TEX_PX
		_mote_tex_cache.height = DUST_MOTE_TEX_PX
		_mote_tex_cache.fill = GradientTexture2D.FILL_RADIAL
		_mote_tex_cache.fill_from = Vector2(0.5, 0.5)
		_mote_tex_cache.fill_to = Vector2(0.5, 0.0)
	return _mote_tex_cache


## La cadena de lentes del sol, proyectada al HUD: N sprites sobre la recta
## sol->centro extendida al lado opuesto (la formula x3 del original). Sin
## oclusion todavia — F4, con el raycast.
func _mount_flares() -> void:
	var tex: Texture2D = load(GHOST_TEXTURE)
	if tex == null or EntityNode.hud_layer == null:
		return
	for g: Dictionary in GHOSTS:
		var ghost := Sprite2D.new()
		ghost.texture = tex
		ghost.scale = Vector2.ONE * float(g.scale)
		ghost.modulate = g.color
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		ghost.material = m
		ghost.z_index = -1        # bajo las barras y nombres
		EntityNode.hud_layer.add_child(ghost)
		_ghosts.append(ghost)


var _flare_do: Array[Sprite2D] = []
var _flare_do_pos := Vector3.ZERO


## El lensFlare del display3D original (typeID 6): 11 lentes reales, lente i en
## sol_px + i * (-(sol_px - centro) * 3 / N) — la cadena cruza el centro y se
## extiende x3 al lado opuesto. Se oculta entero si el sol proyecta fuera del
## viewport (la regla del original; oclusion por HUD pendiente F4).
func _mount_flare_do(pos: Vector3) -> void:
	if EntityNode.hud_layer == null:
		return
	_flare_do_pos = pos
	for i in DO_LENS_COUNT:
		var path := DO_LENS_PATTERN % i
		if not ResourceLoader.exists(path):
			continue
		var lens := Sprite2D.new()
		lens.texture = load(path)
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		lens.material = m
		lens.z_index = -1
		lens.visible = false
		EntityNode.hud_layer.add_child(lens)
		_flare_do.append(lens)


func _exit_tree() -> void:
	for ghost in _ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()
	_ghosts.clear()
	for lens in _flare_do:
		if is_instance_valid(lens):
			lens.queue_free()
	_flare_do.clear()


## Por frame: el sol gira, el polvo se recentra a saltos y los flares siguen la
## proyeccion del sol.
func update(focus: Vector2, delta: float) -> void:
	if _sun != null:
		_sun.rotation.y += deg_to_rad(_sun_spin) * delta
	# el giro perezoso de los props (el "append" del original)
	for g: Dictionary in _turning:
		(g.node as Node3D).rotation_degrees += (g.spin as Vector3) * delta
	if _dust != null:
		# ANTES saltaba a la rejilla mas cercana solo al alejarse 1000 unidades:
		# el reposicionamiento en un salto de golpe (no gradual) se sentia como
		# un atoron/parpadeo del polvo (y del juego en general) cada pocos
		# segundos de vuelo sostenido — reportado 31-ago, junto al arreglo del
		# foco de camara (mismo tipo de bug: algo que se snapea en bloques
		# grandes en vez de seguir continuo). Las particulas YA emitidas no
		# les afecta mover el emisor (local_coords=false, quedan donde nacieron
		# en espacio de mundo); seguir el foco cada frame no cambia el
		# comportamiento del rastro, solo quita el salto.
		_dust.position = Vector3(focus.x, DUST_Y, focus.y)
	if not _ghosts.is_empty():
		var px := Stage3D.instance.to_screen(_sun_pos, _sun.position.y)
		var viewport := get_viewport().get_visible_rect().size
		var inside: bool = px.x > -GHOST_SCREEN_MARGIN_PX and px.y > -GHOST_SCREEN_MARGIN_PX \
			and px.x < viewport.x + GHOST_SCREEN_MARGIN_PX and px.y < viewport.y + GHOST_SCREEN_MARGIN_PX
		var axis := viewport * 0.5 - px
		for i in _ghosts.size():
			_ghosts[i].visible = inside
			_ghosts[i].position = px + axis * float(GHOSTS[i].axis_fraction)
	if not _flare_do.is_empty():
		var cam := Stage3D.instance.cam_node
		var vp := get_viewport().get_visible_rect().size
		var after: bool = cam.is_position_behind(_flare_do_pos)
		var sun_px := Vector2.ZERO if after \
			else Stage3D.instance.to_screen(Vector2(_flare_do_pos.x, _flare_do_pos.z),
				_flare_do_pos.y)
		var sun_visible: bool = (not after) and sun_px.x >= 0.0 and sun_px.y >= 0.0 \
			and sun_px.x <= vp.x and sun_px.y <= vp.y
		var step := -(sun_px - vp * 0.5) * DO_FLARE_SPREAD / float(_flare_do.size())
		for i in _flare_do.size():
			_flare_do[i].visible = sun_visible
			_flare_do[i].position = sun_px + step * float(i)
