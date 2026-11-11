# El RELIEVE del mapa — PRUEBA DE CONCEPTO (10-nov-2026).
#
# La pregunta que responde: ¿se sostiene un mundo con VOLUMEN bajo la camara de
# siempre? La nave sigue volando en su plano (el servidor no se entera de nada);
# lo que cambia es que hay terreno que sube por encima de ella y baja por debajo:
# paredes de canion, una estructura que se cruza por arriba, rocas hondas.
#
# Vive aparte del Backdrop3D a proposito. El fondo esta LEJOS y es decorado; el
# relieve esta A LA COTA DEL JUEGO y es lugar — manana lleva huella de colision,
# linea de vision y marca en el minimapa, y nada de eso es del fondo.
#
# Solo visual. Lo que NO hace todavia: bloquear el paso, bloquear el disparo,
# salir en el minimapa, recortar para ver a OTRAS entidades tapadas (solo el heroe).
#
# Diales en data/config/relief.json; el trazado de cada mapa en
# data/relief/<code>.json.
class_name Relief3D
extends Node3D

static var CFG: Dictionary = AssetDefs.config("relief")
static var _PIECES: Dictionary = CFG.get("pieces", {})
static var _MAT: Dictionary = CFG.get("material", {})
static var _CUT: Dictionary = CFG.get("cutaway", {})
static var _CANYON: Dictionary = CFG.get("canyon_defaults", {})

const LAYOUT_PATH := "res://data/relief/%s.json"
const SHADER_PATH := "res://game/shaders/relief_cutaway.gdshader"
const TERRAIN_SHADER_PATH := "res://game/shaders/relief_terrain.gdshader"

## Las dos lecturas del mismo trazado, para compararlas volando:
##   rocks  = dos filas de rocas sueltas (la primera prueba: se lee como rocas
##            gigantes flotando, no como canion)
##   trench = una superficie continua con la zanja excavada (mapa de alturas)
const VARIANT_ROCKS := "rocks"
const VARIANT_TRENCH := "trench"
var variant := VARIANT_ROCKS
var _rocks: Node3D                 # las rocas de pared de la variante `rocks`
var _terrain: MeshInstance3D       # la superficie de la variante `trench`
var _parent: Node3D                # donde cuelga _place() lo que monta
var _t := {}                       # parametros de la superficie (para height_at)
var _grid := {}                    # la rejilla de alturas ya calculada (para el minimapa)
## Un UNIVERSO son varios mundos: cada planeta es una superficie con su propia
## funcion de altura, su rejilla, su rectangulo y su material.
var _worlds: Array = []            # [{t, grid, rect, name}]
var _terrains: Array[MeshInstance3D] = []
var _universe := Rect2()           # el rectangulo del mapa entero (`bounds` del trazado)

var _info := {}                    # pieza -> {mesh, center, extent, mat}
var _mats: Array[ShaderMaterial] = []
## Cuantas piezas y triangulos se montaron (para el log y la escena de prueba).
var piece_count := 0
var tri_count := 0
var terrain_tris := 0


static func exists_for(map_code: String) -> bool:
	return FileAccess.file_exists(LAYOUT_PATH % map_code)


static func layout(map_code: String) -> Dictionary:
	var path := LAYOUT_PATH % map_code
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("JSON invalido: " + path)
		return {}
	return data


## `terrain_profile`: nombre de un juego de valores de `terrain_profiles` del
## trazado que pisa los de `terrain` (el banco lo usa para la camara de
## persecucion, que pide paredes mas altas que la cenital).
func build(map_code: String, terrain_profile := "") -> bool:
	var d := layout(map_code)
	if d.is_empty():
		return false
	if terrain_profile != "" and d.has("terrain"):
		var over: Dictionary = (d.get("terrain_profiles", {}) as Dictionary).get(terrain_profile, {})
		var merged: Dictionary = (d.terrain as Dictionary).duplicate(true)
		for k in over:
			if typeof(over[k]) == TYPE_DICTIONARY and typeof(merged.get(k)) == TYPE_DICTIONARY:
				(merged[k] as Dictionary).merge(over[k], true)
			else:
				merged[k] = over[k]
		d = d.duplicate()
		d["terrain"] = merged
	_rocks = Node3D.new()
	add_child(_rocks)
	_parent = _rocks
	var canyons: Array = d.get("canyons", [])
	for c: Dictionary in canyons:
		_build_canyon(c)
	_parent = self
	var bounds: Array = d.get("bounds", [])
	if bounds.size() == 2:
		_universe = Rect2(Vector2.ZERO, Vector2(float(bounds[0]), float(bounds[1])))
	var area: Array = d.get("area", [])
	if area.size() == 4:
		_universe = Rect2(float(area[0]), float(area[1]),
			float(area[2]) - float(area[0]), float(area[3]) - float(area[1]))
	for wd: Dictionary in d.get("worlds", []):
		_build_world(wd)
	for body: Dictionary in d.get("sky", []):
		_sky_body(body)
	if d.has("world"):
		_build_world(d.world)
	elif d.has("terrain") and not canyons.is_empty():
		_build_terrain(d.terrain, canyons[0])
	set_variant(str(d.get("variant", VARIANT_TRENCH if not _worlds.is_empty() else VARIANT_ROCKS)))
	for sc: Dictionary in d.get("scatter", []):
		_scatter(sc)
	for md: Dictionary in d.get("models", []):
		_model(md)
	for p: Dictionary in d.get("pieces", []):
		_place(str(p.get("piece", "")),
			Vector3(float(p.get("x", 0)), float(p.get("y", 0)), float(p.get("z", 0))),
			float(p.get("size", 500)),
			Vector3(float(p.get("rot_x", 0)), float(p.get("rot_y", 0)), float(p.get("rot_z", 0))))
	print("Relieve %s: %d piezas, %d triangulos" % [map_code, piece_count, tri_count])
	return piece_count > 0


## Por frame: el recorte sigue a la nave. `hero` en coordenadas de la escena
## (x, altura, y de juego); `active` = hay heroe que proteger.
func update(hero: Vector3, active: bool) -> void:
	for mat in _mats:
		mat.set_shader_parameter("hero_pos", hero)
		mat.set_shader_parameter("cut_on", 1.0 if active else 0.0)


## Dos paredes de rocas a lo largo de una polilinea. Determinista por `seed`: el
## mismo trazado monta el mismo canion en cada visita (y en cada cliente).
func _build_canyon(c: Dictionary) -> void:
	var pts: Array[Vector2] = []
	for p in c.get("path", []):
		pts.append(Vector2(float(p[0]), float(p[1])))
	if pts.size() < 2:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c.get("seed", 1))
	var names: Array = c.get("pieces", _PIECES.keys())
	var half_width := float(c.get("half_width", AssetDefs.num(_CANYON, "half_width", 300.0)))
	var size_range := AssetDefs.vec2(c.get("size", _CANYON.get("size")), Vector2(520, 900))
	var y_range := AssetDefs.vec2(c.get("y", _CANYON.get("y")), Vector2(-260, 40))
	var spacing := float(c.get("spacing", AssetDefs.num(_CANYON, "spacing", 0.5)))
	var edge := float(c.get("edge_factor", AssetDefs.num(_CANYON, "edge_factor", 0.4)))
	var jitter := float(c.get("jitter", AssetDefs.num(_CANYON, "jitter", 70.0)))
	var back: Dictionary = c.get("back_row", {})
	var back_size := AssetDefs.vec2(back.get("size"), Vector2(900, 1500))
	var back_y := AssetDefs.vec2(back.get("y"), Vector2(-750, -250))

	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	var step := maxf((size_range.x + size_range.y) * 0.5 * spacing, 50.0)
	var dist := 0.0
	while dist <= total:
		var s := _sample(pts, dist)
		var point: Vector2 = s[0]
		var dir: Vector2 = s[1]
		var normal := Vector2(-dir.y, dir.x)
		for side: float in [-1.0, 1.0]:
			var size := rng.randf_range(size_range.x, size_range.y)
			var off := half_width + size * edge + rng.randf_range(0.0, jitter)
			var p := point + normal * side * off
			_place(str(names[rng.randi_range(0, names.size() - 1)]),
				Vector3(p.x, rng.randf_range(y_range.x, y_range.y), p.y), size, _any_rotation(rng))
			if not back.is_empty() and rng.randf() < float(back.get("chance", 0.5)):
				var bsize := rng.randf_range(back_size.x, back_size.y)
				var bp := point + normal * side * (half_width + float(back.get("offset", 560.0))
					+ bsize * edge + rng.randf_range(0.0, jitter * 2.0))
				_place(str(names[rng.randi_range(0, names.size() - 1)]),
					Vector3(bp.x, rng.randf_range(back_y.x, back_y.y), bp.y), bsize, _any_rotation(rng))
		dist += step


static func _any_rotation(rng: RandomNumberGenerator) -> Vector3:
	return Vector3(rng.randf_range(0.0, 360.0), rng.randf_range(0.0, 360.0), rng.randf_range(0.0, 360.0))


## Punto y direccion de la polilinea a `dist` unidades de su inicio.
static func _sample(pts: Array[Vector2], dist: float) -> Array:
	var left := dist
	for i in pts.size() - 1:
		var seg := pts[i + 1] - pts[i]
		var length := seg.length()
		if left <= length or i == pts.size() - 2:
			var dir := seg / maxf(length, 0.001)
			return [pts[i] + dir * minf(left, length), dir]
		left -= length
	return [pts[0], Vector2.RIGHT]


## Una pieza del catalogo, centrada en su caja y escalada para que su lado mayor
## mida `size`. `rot` en grados.
func _place(piece: String, pos: Vector3, size: float, rot: Vector3) -> void:
	var info := _piece(piece)
	if info.is_empty():
		return
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation_degrees = rot
	holder.scale = Vector3.ONE * (size / float(info.extent))
	var mi := MeshInstance3D.new()
	mi.mesh = info.mesh
	mi.position = -(info.center as Vector3)
	mi.material_override = info.mat
	holder.add_child(mi)
	_parent.add_child(holder)
	piece_count += 1
	tri_count += int(info.tris)


func _piece(piece: String) -> Dictionary:
	if _info.has(piece):
		return _info[piece]
	var def: Dictionary = _PIECES.get(piece, {})
	var mesh_path := str(def.get("mesh", ""))
	if mesh_path == "" or not ResourceLoader.exists(mesh_path):
		push_warning("relieve: falta la pieza '%s' (%s)" % [piece, mesh_path])
		_info[piece] = {}
		return {}
	var mesh: Mesh = load(mesh_path)
	var box := mesh.get_aabb()
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	var tex_path := str(def.get("tex", ""))
	if tex_path != "" and ResourceLoader.exists(tex_path):
		mat.set_shader_parameter("albedo_tex", load(tex_path))
	mat.set_shader_parameter("tint", AssetDefs.color(def.get("tint", "FFFFFF")))
	mat.set_shader_parameter("roughness", AssetDefs.num(_MAT, "roughness", 0.9))
	mat.set_shader_parameter("interior", AssetDefs.num(_MAT, "interior", 0.25))
	mat.set_shader_parameter("cut_radius", AssetDefs.num(_CUT, "radius", 170.0))
	mat.set_shader_parameter("cut_feather", AssetDefs.num(_CUT, "feather", 70.0))
	mat.set_shader_parameter("cut_margin", AssetDefs.num(_CUT, "margin", 40.0))
	_mats.append(mat)
	var tris := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var idx = arrays[Mesh.ARRAY_INDEX]
		tris += (idx.size() if idx != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	_info[piece] = {
		"mesh": mesh,
		"center": box.get_center(),
		"extent": maxf(maxf(box.size.x, box.size.y), maxf(box.size.z, 0.001)),
		"mat": mat,
		"tris": tris,
	}
	return _info[piece]


## Cambia de lectura en caliente. Sin superficie generada solo existe `rocks`.
func set_variant(v: String) -> void:
	variant = VARIANT_TRENCH if (v == VARIANT_TRENCH and _terrain != null) else VARIANT_ROCKS
	_rocks.visible = variant == VARIANT_ROCKS
	for surface in _terrains:
		surface.visible = variant == VARIANT_TRENCH


# ---- la trinchera: una superficie continua desde un mapa de alturas ----

## Distancia de `p` a la polilinea y el punto mas cercano: [dist, punto].
static func _nearest(pts: Array[Vector2], p: Vector2) -> Array:
	var best := INF
	var best_q := pts[0]
	for i in pts.size() - 1:
		var a := pts[i]
		var ab := pts[i + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var q := a + ab * t
		var dd := p.distance_to(q)
		if dd < best:
			best = dd
			best_q = q
	return [best, best_q]


## La altura del terreno en un punto del mapa. Es LA funcion de la variante: de
## aqui sale la malla, y de aqui saldria la huella del servidor (donde la altura
## supera el plano de vuelo, no se pasa) y el dibujo del minimapa.
##
##   - cerca del eje: el suelo de la zanja (`floor_y`)
##   - a `half_width` del eje la pared cruza el plano de vuelo y sigue hasta el borde
##   - mas alla: meseta rugosa. El borde del lado de la camara (y de juego
##     creciente) es mas BAJO (`rim_near`): con la vista a 45 grados esa pared se
##     ve por detras y taparia el pasillo.
##   - a `outer` del eje el macizo se desploma (`deep_y`): es una isla, no un piso
##     infinito.
## El eje se PROLONGA por los dos extremos para la zanja (no para el macizo): asi
## las bocas quedan abiertas en vez de cerrarse en un fondo de saco.
func _height(p: Vector2, t: Dictionary) -> float:
	if t.has("kind"):
		return _world_height(p, t)
	var edge_n: float = (t.noise_edge as FastNoiseLite).get_noise_2d(p.x, p.y)
	var near: Array = _nearest(t.long_pts, p)
	var dc: float = float(near[0]) + edge_n * float(t.edge_amp)
	var di: float = float(_nearest(t.pts, p)[0]) + edge_n * float(t.edge_amp) * 2.0
	var side: Vector2 = p - (near[1] as Vector2)
	var near_k := smoothstep(-0.25, 0.25, side.y / maxf(side.length(), 1.0))
	var a: float = float(t.half_width) - float(t.wall_width) * 0.6
	var wall := smoothstep(a, a + float(t.wall_width), dc)
	var rim: float = lerpf(float(t.rim_far), float(t.rim_near), near_k) \
		+ (t.noise_plateau as FastNoiseLite).get_noise_2d(p.x, p.y) * float(t.plateau_amp)
	var floor_h: float = float(t.floor_y) \
		+ (t.noise_edge as FastNoiseLite).get_noise_2d(p.y, p.x) * float(t.floor_amp)
	# la ONDA larga del suelo (`floor_wave`): sube y baja a lo largo del pasillo —
	# lo que la nave sigue cuando sigue el terreno
	floor_h += (t.noise_edge as FastNoiseLite).get_noise_2d(p.x * float(t.floor_wave_scale) + 900.0,
		p.y * float(t.floor_wave_scale)) * float(t.floor_wave)
	var outer: float = float(t.outer)
	var fall_end: float = outer + float(t.outer_fall)
	var fall := smoothstep(outer, fall_end, di)
	# la BOCA: con `mouth_ramp` el suelo baja suave hasta `mouth_y` antes de que
	# el macizo se desplome, para que se pueda entrar volando (sin el, el suelo
	# cae con las paredes y la boca es un escalon)
	var mouth_on: bool = float(t.mouth_ramp) > 0.0
	if mouth_on:
		floor_h = lerpf(floor_h, float(t.mouth_y), smoothstep(outer - float(t.mouth_ramp), fall_end, di))
	var h := lerpf(floor_h, rim, wall)
	# RAMPAS: un corredor de pendiente constante del suelo de la zanja al borde,
	# excavado en la pared. Es lo unico por donde se sube a la meseta.
	for r: Dictionary in t.ramps:
		var a2: Vector2 = r.from
		var ab: Vector2 = (r.to as Vector2) - a2
		var k := clampf((p - a2).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var rd := p.distance_to(a2 + ab * k)
		var hw: float = r.half_width
		var inside := 1.0 - smoothstep(hw * 0.55, hw, rd)
		if inside > 0.0:
			# sin ruido: la rampa es de pendiente CONSTANTE, del suelo base al borde base
			h = lerpf(h, lerpf(float(t.floor_y), lerpf(float(t.rim_far), float(t.rim_near), near_k), k), inside)
	h = lerpf(h, float(t.deep_y), fall)
	if mouth_on:
		var lip := lerpf(floor_h, float(t.deep_y), smoothstep(fall_end, fall_end + 300.0, di))
		h = maxf(h, lerpf(float(t.deep_y), lip, 1.0 - wall))
	return h


## Altura del terreno en un punto del mapa (coordenadas de juego). NAN si ahi no
## hay superficie (espacio abierto) o la variante activa no la usa: quien pregunta
## vuela en el plano de siempre.
func height_at(p: Vector2) -> float:
	if variant != VARIANT_TRENCH:
		return NAN
	if not _worlds.is_empty():
		var w := world_at(p)
		return NAN if w.is_empty() else _world_height(p, w.t)
	if _terrain == null or _t.is_empty():
		return NAN
	return _height(p, _t)


## El mundo (planeta) que hay bajo un punto, o {} en espacio abierto.
func world_at(p: Vector2) -> Dictionary:
	for w: Dictionary in _worlds:
		if (w.rect as Rect2).has_point(p) \
				and _world_height(p, w.t) > float((w.t as Dictionary).deep_y) + 1.0:
			return w
	return {}


func planet_at(p: Vector2) -> String:
	var w := world_at(p)
	return "" if w.is_empty() else str(w.name)


## Danio por segundo de lo que hay bajo un punto (lava): 0 si nada quema. Devuelve
## [dps, nombre].
func hazard_at(p: Vector2) -> Array:
	var w := world_at(p)
	if w.is_empty():
		return [0.0, ""]
	var t: Dictionary = w.t
	if float(t.sea_dps) > 0.0 and _world_height(p, t) <= float(t.sea_y) + 0.5:
		return [float(t.sea_dps), str(t.sea_name)]
	return [0.0, ""]


func _build_terrain(def: Dictionary, canyon: Dictionary) -> void:
	var pts: Array[Vector2] = []
	for p in canyon.get("path", []):
		pts.append(Vector2(float(p[0]), float(p[1])))
	if pts.size() < 2:
		return
	var mouth := float(def.get("mouth_extend", 3000.0))
	var long_pts: Array[Vector2] = pts.duplicate()
	long_pts[0] = pts[0] - (pts[1] - pts[0]).normalized() * mouth
	long_pts[-1] = pts[-1] + (pts[-1] - pts[-2]).normalized() * mouth
	var noise_def: Dictionary = def.get("noise", {})
	var noise_edge := FastNoiseLite.new()
	noise_edge.seed = int(canyon.get("seed", 1))
	noise_edge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_edge.frequency = float(noise_def.get("edge_freq", 0.0035))
	var noise_plateau := FastNoiseLite.new()
	noise_plateau.seed = int(canyon.get("seed", 1)) + 7
	noise_plateau.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	# crestas afiladas (ridged) para mirar; lisa para VOLAR encima: una cresta es
	# una pendiente de mas de 45 grados cada pocas unidades y la meseta no se cruza
	if bool(noise_def.get("plateau_ridged", true)):
		noise_plateau.fractal_type = FastNoiseLite.FRACTAL_RIDGED
		noise_plateau.fractal_octaves = 3
	else:
		noise_plateau.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise_plateau.frequency = float(noise_def.get("plateau_freq", 0.0016))
	var t := {
		"pts": pts, "long_pts": long_pts,
		"noise_edge": noise_edge, "noise_plateau": noise_plateau,
		"half_width": float(def.get("half_width", canyon.get("half_width",
			AssetDefs.num(_CANYON, "half_width", 300.0)))),
		"wall_width": float(def.get("wall_width", 190.0)),
		"floor_y": float(def.get("floor_y", -420.0)),
		"rim_far": float(def.get("rim_far", 280.0)),
		"rim_near": float(def.get("rim_near", 120.0)),
		"outer": float(def.get("outer", 1250.0)),
		"outer_fall": float(def.get("outer_fall", 500.0)),
		"deep_y": float(def.get("deep_y", -1600.0)),
		"edge_amp": float(noise_def.get("edge_amp", 70.0)),
		"plateau_amp": float(noise_def.get("plateau_amp", 130.0)),
		"floor_amp": float(noise_def.get("floor_amp", 40.0)),
		"floor_wave": float(noise_def.get("floor_wave", 0.0)),
		"floor_wave_scale": float(noise_def.get("floor_wave_scale", 0.3)),
		"mouth_ramp": float(def.get("mouth_ramp", 0.0)),
		"mouth_y": float(def.get("mouth_y", -150.0)),
		"ramps": [],
	}
	for r: Dictionary in def.get("ramps", []):
		(t.ramps as Array).append({
			"from": AssetDefs.vec2(r.get("from")), "to": AssetDefs.vec2(r.get("to")),
			"half_width": float(r.get("half_width", 240.0)),
		})
	_t = t

	# la rejilla cubre la caja del trazado mas el macizo entero
	var reach: float = float(t.outer) + float(t.outer_fall) + float(t.edge_amp) * 2.0
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	lo -= Vector2.ONE * reach
	hi += Vector2.ONE * reach
	_surface(def, lo, hi)


## La roca de la trinchera, PROCEDURAL: ruido enlosable pasado por una rampa de
## tres tonos. Las texturas de assets/do-ref no sirven aqui — son atlas UV de sus
## mallas (islas de roca dibujadas), y proyectadas en triplanar se ven como fotos
## de asteroides pegadas al suelo.
static func _rock_texture(def: Dictionary) -> NoiseTexture2D:
	var colors: Array = def.get("colors", ["2e1a13", "7a4630", "b89478"])
	var ramp := Gradient.new()
	ramp.set_color(0, AssetDefs.color(colors[0]))
	ramp.set_color(1, AssetDefs.color(colors[colors.size() - 1]))
	if colors.size() >= 3:
		ramp.add_point(0.5, AssetDefs.color(colors[1]))
	var noise := FastNoiseLite.new()
	noise.seed = 3
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	noise.frequency = 0.012
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.noise = noise
	tex.color_ramp = ramp
	return tex


## La malla de la superficie: una rejilla sobre el rectangulo [lo, hi] con la
## altura de `_height()` en cada vertice. La usan la trinchera (un solo trazado)
## y el mundo (`world`).
func _surface(def: Dictionary, lo: Vector2, hi: Vector2) -> void:
	var t := _t
	var cell := maxf(float(def.get("cell", 55.0)), 10.0)
	var nx := int(ceil((hi.x - lo.x) / cell)) + 1
	var nz := int(ceil((hi.y - lo.y) / cell)) + 1

	# alturas con un anillo de guarda para las normales por diferencias centrales
	var gw := nx + 2
	var heights := PackedFloat32Array()
	heights.resize(gw * (nz + 2))
	for iz in nz + 2:
		for ix in gw:
			heights[iz * gw + ix] = _height(lo + Vector2(float(ix - 1), float(iz - 1)) * cell, t)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.resize(nx * nz)
	normals.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			var g := (iz + 1) * gw + (ix + 1)
			verts[iz * nx + ix] = Vector3(lo.x + float(ix) * cell, heights[g], lo.y + float(iz) * cell)
			normals[iz * nx + ix] = Vector3(heights[g - 1] - heights[g + 1], 2.0 * cell,
				heights[g - gw] - heights[g + gw]).normalized()
	# sin los cuadros que ya cayeron al fondo del macizo: la isla tiene borde
	var cut_y: float = float(t.deep_y) + 1.0
	var indices := PackedInt32Array()
	for iz in nz - 1:
		for ix in nx - 1:
			var i0 := iz * nx + ix
			var i1 := i0 + 1
			var i2 := i0 + nx
			var i3 := i2 + 1
			if verts[i0].y <= cut_y and verts[i1].y <= cut_y and verts[i2].y <= cut_y and verts[i3].y <= cut_y:
				continue
			indices.append_array(PackedInt32Array([i0, i1, i2, i1, i3, i2]))
	if indices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := ShaderMaterial.new()
	mat.shader = load(TERRAIN_SHADER_PATH)
	var tex_path := str(def.get("tex", ""))
	if tex_path != "" and ResourceLoader.exists(tex_path):
		mat.set_shader_parameter("albedo_tex", load(tex_path))
	else:
		mat.set_shader_parameter("albedo_tex", _rock_texture(def))
	mat.set_shader_parameter("tint", AssetDefs.color(def.get("tint", "FFFFFF")))
	mat.set_shader_parameter("tex_scale", float(def.get("tex_scale", 700.0)))
	mat.set_shader_parameter("top_fill", float(def.get("top_fill", 0.35)))
	mat.set_shader_parameter("wall_tint", AssetDefs.color(def.get("wall_tint", "9E7A70")))
	if def.has("sea"):
		var sea: Dictionary = def.sea
		mat.set_shader_parameter("sea_y", float(sea.get("y", -60.0)))
		mat.set_shader_parameter("sea_color", AssetDefs.color(sea.get("color", "1d5fa8")))
		mat.set_shader_parameter("sea_emission", float(sea.get("emission", 0.0)))
	if def.has("snow"):
		var snow: Dictionary = def.snow
		mat.set_shader_parameter("snow_y", float(snow.get("y", 500.0)))
		mat.set_shader_parameter("snow_color", AssetDefs.color(snow.get("color", "f2f4f7")))
	mat.set_shader_parameter("roughness", AssetDefs.num(_MAT, "roughness", 0.9))
	mat.set_shader_parameter("dark_y", float(t.floor_y))
	mat.set_shader_parameter("light_y", float(def.get("light_y", 200.0)))
	mat.set_shader_parameter("dark", float(def.get("dark", 0.22)))
	mat.set_shader_parameter("strata", float(def.get("strata", 0.18)))
	mat.set_shader_parameter("strata_period", float(def.get("strata_period", 46.0)))
	mat.set_shader_parameter("cut_radius", AssetDefs.num(_CUT, "radius", 170.0))
	mat.set_shader_parameter("cut_feather", AssetDefs.num(_CUT, "feather", 70.0))
	mat.set_shader_parameter("cut_margin", AssetDefs.num(_CUT, "margin", 40.0))
	_mats.append(mat)
	_terrain = MeshInstance3D.new()
	_terrain.mesh = mesh
	_terrain.material_override = mat
	add_child(_terrain)
	_terrains.append(_terrain)
	terrain_tris = indices.size() / 3
	print("Relieve: superficie de %d x %d celdas, %d triangulos" % [nx - 1, nz - 1, terrain_tris])
	_grid = {"heights": heights, "gw": gw, "nx": nx, "nz": nz, "lo": lo, "cell": cell}


# ---- el MUNDO: una tierra entera compuesta de accidentes ----
#
# La trinchera sale de UN trazado. Un mundo abierto necesita mas vocabulario, y
# este es: PLACAS (la tierra: un cuerpo enorme sobre el que se vuela, con borde de
# acantilado al espacio), COLINAS y CRATERES (suelo que sube y baja, todo
# pisable), MESETAS (se levantan con pared; solo se sube por sus RAMPAS),
# CORDILLERAS (un muro a lo largo de un trazado, con PASOS) y CANIONES (cortan lo
# levantado hasta el suelo, asi que sus bocas quedan abiertas solas).
#
# Regla de oro, heredada de la trinchera: lo que se pisa va bajo la pendiente
# maxima (1,0); lo que debe cerrar el paso, muy por encima.

func _build_world(def: Dictionary) -> void:
	var seed_n := int(def.get("seed", 7))
	var noise_edge := FastNoiseLite.new()
	noise_edge.seed = seed_n
	noise_edge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_edge.frequency = float(def.get("edge_freq", 0.0022))
	var noise_fine := FastNoiseLite.new()
	noise_fine.seed = seed_n + 3
	noise_fine.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_fine.frequency = float(def.get("fine_freq", 0.0035))
	var noise_wave := FastNoiseLite.new()
	noise_wave.seed = seed_n + 11
	noise_wave.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_wave.frequency = float(def.get("wave_freq", 0.00035))
	var w := {
		"kind": "world",
		"noise_edge": noise_edge, "noise_fine": noise_fine, "noise_wave": noise_wave,
		"base_y": float(def.get("base_y", 20.0)),
		"deep_y": float(def.get("deep_y", -1500.0)),
		"floor_y": float(def.get("dark_y", -400.0)),
		"fine_amp": float(def.get("fine_amp", 10.0)),
		"wave_amp": float(def.get("wave_amp", 55.0)),
		"name": str(def.get("name", "")),
		"sea_on": def.has("sea"),
		"sea_y": float((def.get("sea", {}) as Dictionary).get("y", -60.0)),
		"sea_dps": float((def.get("sea", {}) as Dictionary).get("damage_per_sec", 0.0)),
		"sea_name": str((def.get("sea", {}) as Dictionary).get("name", "")),
		"sea_color": AssetDefs.color((def.get("sea", {}) as Dictionary).get("color", "1d5fa8")),
		"low_color": AssetDefs.color((def.get("colors", ["6b3d2b"]) as Array)[0]).lightened(0.25),
		"high_color": AssetDefs.color((def.get("colors", ["6b3d2b", "f0d4b4"]) as Array)[-1]).lightened(0.2),
		"shore_y": float(def.get("shore_y", -12.0)),
		"shore_width": float(def.get("shore_width", 520.0)),
		"plates": [], "hills": [], "craters": [], "mesas": [], "ridges": [], "canyons": [],
	}
	for d: Dictionary in def.get("plates", []):
		(w.plates as Array).append({
			"c": AssetDefs.vec2(d.get("at")), "r": AssetDefs.vec2(d.get("radii"), Vector2(3000, 2000)),
			"edge": float(d.get("edge", 320.0)), "edge_noise": float(d.get("edge_noise", 260.0)),
		})
	for d: Dictionary in def.get("hills", []):
		(w.hills as Array).append({"c": AssetDefs.vec2(d.get("at")),
			"amp": float(d.get("height", 200.0)), "sigma": float(d.get("spread", 600.0))})
	for d: Dictionary in def.get("craters", []):
		(w.craters as Array).append({"c": AssetDefs.vec2(d.get("at")), "r": float(d.get("radius", 1000.0)),
			"depth": float(d.get("depth", 350.0)), "rim": float(d.get("rim", 80.0)),
			"rim_width": float(d.get("rim_width", 170.0))})
	for d: Dictionary in def.get("mesas", []):
		var ramps := []
		for r: Dictionary in d.get("ramps", []):
			ramps.append({"angle": deg_to_rad(float(r.get("toward_deg", 0.0))),
				"half": deg_to_rad(float(r.get("half_deg", 9.0))), "length": float(r.get("length", 1000.0))})
		(w.mesas as Array).append({"c": AssetDefs.vec2(d.get("at")), "r": float(d.get("radius", 1000.0)),
			"top": float(d.get("height", 600.0)), "edge": float(d.get("edge", 220.0)),
			"edge_noise": float(d.get("edge_noise", 40.0)), "ramps": ramps})
	for d: Dictionary in def.get("ridges", []):
		var gaps := []
		for g: Dictionary in d.get("passes", []):
			gaps.append({"c": AssetDefs.vec2(g.get("at")), "r": float(g.get("radius", 320.0))})
		(w.ridges as Array).append({"pts": _points(d.get("path", [])), "top": float(d.get("height", 500.0)),
			"core": float(d.get("core", 60.0)), "width": float(d.get("width", 260.0)), "gaps": gaps})
	for d: Dictionary in def.get("canyons", []):
		(w.canyons as Array).append({"pts": _points(d.get("path", [])),
			"half": float(d.get("half_width", 300.0)), "wall": float(d.get("wall_width", 220.0)),
			"depth": float(d.get("depth", 0.0)), "edge_noise": float(d.get("edge_noise", 30.0))})
	_t = w
	var rect: Array = def.get("rect", [0, 0, 12000, 9000])
	var lo := Vector2(float(rect[0]), float(rect[1]))
	var hi := Vector2(float(rect[2]), float(rect[3]))
	_surface(def, lo, hi)
	_worlds.append({"t": w, "grid": _grid, "rect": Rect2(lo, hi - lo), "name": str(w.name)})


static func _points(raw: Array) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for q in raw:
		pts.append(Vector2(float(q[0]), float(q[1])))
	return pts


func _world_height(p: Vector2, w: Dictionary) -> float:
	var deep: float = w.deep_y
	var edge_n: float = (w.noise_edge as FastNoiseLite).get_noise_2d(p.x, p.y)
	# 1. ¿hay tierra? union de placas (elipses de borde rugoso)
	var land := 0.0
	var shore := 0.0               # 0 en la costa, 1 tierra adentro
	for pl: Dictionary in w.plates:
		var r: Vector2 = pl.r
		var q: Vector2 = (p - (pl.c as Vector2)) / r
		var d: float = (q.length() - 1.0) * minf(r.x, r.y) + edge_n * float(pl.edge_noise)
		land = maxf(land, 1.0 - smoothstep(-float(pl.edge), 0.0, d))
		shore = maxf(shore, smoothstep(float(pl.edge), float(pl.edge) + float(w.shore_width), -d))
	if land <= 0.0:
		return deep
	# 2. el suelo: todo pisable
	var ground: float = float(w.base_y) \
		+ (w.noise_wave as FastNoiseLite).get_noise_2d(p.x, p.y) * float(w.wave_amp) \
		+ (w.noise_fine as FastNoiseLite).get_noise_2d(p.x, p.y) * float(w.fine_amp)
	for hl: Dictionary in w.hills:
		var dh := p.distance_to(hl.c)
		var sg: float = hl.sigma
		ground += float(hl.amp) * exp(-dh * dh / (2.0 * sg * sg))
	for cr: Dictionary in w.craters:
		var dc := p.distance_to(cr.c)
		var cr_r: float = cr.r
		ground -= float(cr.depth) * (1.0 - smoothstep(0.0, cr_r, dc))
		var off: float = (dc - cr_r) / float(cr.rim_width)
		ground += float(cr.rim) * exp(-off * off)
	# LA COSTA: hacia el borde el suelo baja hasta quedar justo BAJO el plano de
	# vuelo, y solo entonces viene el acantilado. Asi la nave entra a la tierra a
	# su altura de siempre por cualquier punto y sube tierra adentro por una
	# pendiente suave. Sin esto el suelo llegaba alto al borde y la costa entera
	# era una pared: desde el espacio no habia por donde subir.
	ground = lerpf(minf(ground, float(w.shore_y)), ground, shore)
	# 3. lo que se levanta: mesetas (pared salvo en las rampas) y cordilleras (muro con pasos)
	var raised := ground
	for m: Dictionary in w.mesas:
		var v: Vector2 = p - (m.c as Vector2)
		var e: float = v.length() - float(m.r) + edge_n * float(m.edge_noise)
		var k := 1.0
		if e > 0.0:
			k = 1.0 - smoothstep(0.0, float(m.edge), e)
			for rp: Dictionary in m.ramps:
				var half: float = rp.half
				var inside := 1.0 - smoothstep(half * 0.6, half, absf(angle_difference(v.angle(), float(rp.angle))))
				if inside > 0.0:
					# pendiente CONSTANTE: altura / largo
					k = lerpf(k, maxf(k, 1.0 - clampf(e / float(rp.length), 0.0, 1.0)), inside)
		raised += float(m.top) * k
	for rg: Dictionary in w.ridges:
		var dr: float = _nearest(rg.pts, p)[0]
		var kr := 1.0 - smoothstep(float(rg.core), float(rg.width), dr)
		if kr > 0.0:
			for g: Dictionary in rg.gaps:
				var gr: float = g.r
				kr *= smoothstep(gr * 0.45, gr, p.distance_to(g.c))
			raised += float(rg.top) * kr
	# 4. caniones: cortan lo levantado hasta el suelo (por eso sus bocas quedan abiertas)
	var h := raised
	for cn: Dictionary in w.canyons:
		var dn: float = float(_nearest(cn.pts, p)[0]) + edge_n * float(cn.edge_noise)
		var a: float = float(cn.half) - float(cn.wall) * 0.6
		h = lerpf(ground - float(cn.depth), h, smoothstep(a, a + float(cn.wall), dn))
	# 5. el mar (o la lava): lo hundido se llena hasta su cota y queda plano
	if bool(w.sea_on):
		h = maxf(h, float(w.sea_y))
	# 6. el borde de la tierra: acantilado al espacio
	return lerpf(deep, h, land)


# ---- piezas sueltas en cantidad, y modelos ----

## Un campo de rocas: `count` piezas sorteadas dentro de un circulo. Solo visual.
func _scatter(d: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d.get("seed", 3))
	var center := AssetDefs.vec2(d.get("at"))
	var radius := float(d.get("radius", 1000.0))
	var names: Array = d.get("pieces", _PIECES.keys())
	var size_range := AssetDefs.vec2(d.get("size"), Vector2(200, 700))
	var y_range := AssetDefs.vec2(d.get("y"), Vector2(-500, 500))
	for i in int(d.get("count", 20)):
		var at := center + Vector2.RIGHT.rotated(rng.randf() * TAU) * sqrt(rng.randf()) * radius
		_place(str(names[rng.randi_range(0, names.size() - 1)]),
			Vector3(at.x, rng.randf_range(y_range.x, y_range.y), at.y),
			rng.randf_range(size_range.x, size_range.y), _any_rotation(rng))


## Un modelo del juego (GLB) plantado en el mundo: `prop` (ficha de data/props) o
## `model` (ruta). `y` es altura sobre el terreno si lo hay debajo.
func _model(d: Dictionary) -> void:
	var path := str(d.get("model", ""))
	if d.has("prop"):
		path = str(AssetDefs.prop(str(d.prop)).get("model", ""))
	if path == "" or not ResourceLoader.exists(path):
		push_warning("relieve: falta el modelo %s" % path)
		return
	var node: Node3D = (load(path) as PackedScene).instantiate()
	node.scale = Vector3.ONE * (float(d.get("size", 800.0)) / AssetDefs.extent_3d(node))
	var at := Vector2(float(d.get("x", 0)), float(d.get("z", 0)))
	var ground := height_at(at)
	node.position = Vector3(at.x, float(d.get("y", 0.0)) + (0.0 if is_nan(ground) else ground), at.y)
	node.rotation_degrees.y = float(d.get("rot_y", 0.0))
	add_child(node)


## Un planeta vecino pintado en el cielo: una esfera enorme y lejana en su
## direccion, con la paleta de ese planeta. No se llega a ella — se va por
## portal —, pero se VE a donde lleva. Con algo de emision para que la cara en
## sombra no sea un disco negro contra el espacio.
func _sky_body(d: Dictionary) -> void:
	var center := _universe.get_center()
	var toward := Vector2.from_angle(deg_to_rad(float(d.get("toward_deg", 0.0))))
	var radius := float(d.get("radius", 6000.0))
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 48
	mesh.rings = 24
	var tex := _rock_texture({"colors": d.get("colors", ["5a2a1c", "b5553a", "e0a078"])})
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3(3.0, 1.5, 1.0)
	mat.roughness = 1.0
	mat.emission_enabled = true
	mat.emission_texture = tex
	mat.emission_energy_multiplier = float(d.get("glow", 0.45))
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var at := center + toward * float(d.get("distance", 46000.0))
	mi.position = Vector3(at.x, float(d.get("height", 9000.0)), at.y)
	mi.rotation_degrees = Vector3(18.0, 40.0, 0.0)
	add_child(mi)


# ---- el minimapa sale del mismo dato ----

## El rectangulo del mapa: el del universo si el trazado lo declara, si no el de
## la superficie.
func world_rect() -> Rect2:
	if _universe.size.x > 0.0:
		return _universe
	if _grid.is_empty():
		return Rect2()
	var lo: Vector2 = _grid.lo
	return Rect2(lo, Vector2(float(_grid.nx - 1), float(_grid.nz - 1)) * float(_grid.cell))


## Una imagen cenital de todo el mapa: cada mundo pintado con su paleta, tono por
## altura, mas oscuro donde es empinado (las paredes se leen como lineas), su mar
## de su color y transparente donde no hay tierra.
func minimap_image(width := 420) -> Image:
	var rect := world_rect()
	if rect.size.x <= 0.0:
		return null
	var layers: Array = _worlds if not _worlds.is_empty() else [{"t": _t, "grid": _grid}]
	var scale := float(width) / rect.size.x
	var out := Image.create(width, maxi(int(rect.size.y * scale), 1), false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for w: Dictionary in layers:
		var g: Dictionary = w.grid
		if g.is_empty():
			continue
		var piece := _grid_image(w.t, g)
		var span := Vector2(float(g.nx - 1), float(g.nz - 1)) * float(g.cell) * scale
		piece.resize(maxi(int(span.x), 1), maxi(int(span.y), 1), Image.INTERPOLATE_BILINEAR)
		var at := ((g.lo as Vector2) - rect.position) * scale
		out.blend_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()), Vector2i(int(at.x), int(at.y)))
	return out


static func _grid_image(t: Dictionary, g: Dictionary) -> Image:
	var nx: int = g.nx
	var nz: int = g.nz
	var gw: int = g.gw
	var cell: float = g.cell
	var heights: PackedFloat32Array = g.heights
	var cut: float = float(t.deep_y) + 60.0
	var low: Color = t.get("low_color", Color("6b3d2b"))
	var high: Color = t.get("high_color", Color("f0d4b4"))
	var sea_on := bool(t.get("sea_on", false))
	var sea_y := float(t.get("sea_y", -100000.0))
	var img := Image.create(nx, nz, false, Image.FORMAT_RGBA8)
	for iz in nz:
		for ix in nx:
			var k := (iz + 1) * gw + (ix + 1)
			var h := heights[k]
			var slope := Vector2(heights[k + 1] - heights[k - 1], heights[k + gw] - heights[k - gw]).length() / (2.0 * cell)
			if h <= cut:
				img.set_pixel(ix, iz, Color(0, 0, 0, 0))
			elif sea_on and h <= sea_y + 0.5 and slope < 0.2:
				# solo lo PLANO a la cota del mar es mar: el acantilado de la costa
				# tambien pasa por esa cota y salia pintado como un anillo de agua
				img.set_pixel(ix, iz, t.sea_color)
			else:
				img.set_pixel(ix, iz, low.lerp(high, clampf((h + 400.0) / 1300.0, 0.0, 1.0)) \
					.darkened(clampf(slope * 0.45, 0.0, 0.75)))
	return img
