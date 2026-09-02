extends Node2D

## Dibuja los marcadores ENCIMA del render, con el mismo montaje que usa el juego,
## y guarda la imagen. Sirve para ver si una tobera esta donde el cliente cree, en
## vez de discutirlo mirando la nave en movimiento.
##
##   godot --path . res://tests/view_anchors.tscn -- --model=ships/phoenix.glb

## Diales de data/config/tests.json (`view_anchors` + `common`).
static var CFG: Dictionary = AssetDefs.config("tests").get("view_anchors", {})
static var CFG_COMMON: Dictionary = AssetDefs.config("tests").get("common", {})
static var FRAME_MARGIN: float = AssetDefs.num(CFG_COMMON, "frame_margin", 1.15)
static var CAMERA_HEIGHT: float = AssetDefs.num(CFG_COMMON, "camera_height", 8.0)
static var OUTPUT_DIR: String = str(CFG_COMMON.get("output_dir", "C:/Tools"))
static var SIDE: int = int(AssetDefs.num(CFG, "render_size", 512))
static var DEFAULT_MODEL: String = str(CFG.get("default_model", "res://assets/ships/phoenix.glb"))
static var SETTLE_FRAMES: int = int(AssetDefs.num(CFG, "settle_frames", 4))
## Marcadores pintados sobre el render.
static var CROSS_RADIUS_PX: int = int(AssetDefs.num(CFG, "cross_radius_px", 6))
static var WIDTH_BAR_OFFSET_PX: int = int(AssetDefs.num(CFG, "width_bar_offset_px", 8))
static var THRUSTER_COLOR: Color = AssetDefs.color(CFG.get("thruster_color"), Color("00ffff"))
static var CANNON_COLOR: Color = AssetDefs.color(CFG.get("cannon_color"), Color("ff6600"))
static var WIDTH_BAR_COLOR: Color = AssetDefs.color(CFG.get("width_bar_color"), Color("ffff00"))
## Medida de las bocas en la imagen.
static var ALPHA_THRESHOLD: float = AssetDefs.num(CFG, "alpha_threshold", 0.3)
static var RECOIL_MAX_PX: int = int(AssetDefs.num(CFG, "recoil_max_px", 60))
static var RECOIL_STEP_PX: int = int(AssetDefs.num(CFG, "recoil_step_px", 2))
static var MIN_MUZZLES: int = int(AssetDefs.num(CFG, "min_muzzles", 4))
static var MIN_MUZZLE_WIDTH_PX: int = int(AssetDefs.num(CFG, "min_muzzle_width_px", 4))
static var BAND_HEIGHT_PX: int = int(AssetDefs.num(CFG, "band_height_px", 6))

var _path := DEFAULT_MODEL
var _vp: SubViewport
var _model: Node3D
var _scale_factor := 1.0
var _waits := 0

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--model="):
			_path = "res://assets/%s" % arg.trim_prefix("--model=")

	_model = (load(_path) as PackedScene).instantiate()
	var box := AABB()
	var first := true
	for m in _model.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = (m as MeshInstance3D).transform * (m as MeshInstance3D).get_aabb()
		box = a if first else box.merge(a)
		first = false
	var ext: float = maxf(box.size.x, box.size.z)
	# Mismo contrato que el juego: el lado mayor ocupa el ancho util del render.
	_scale_factor = float(SIDE) / (ext * FRAME_MARGIN)

	_vp = SubViewport.new()
	_vp.size = Vector2i(SIDE, SIDE)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_vp.add_child(_model)
	var ent := Environment.new()
	ent.background_mode = Environment.BG_CLEAR_COLOR
	AssetDefs.world_ambient(ent)
	var we := WorldEnvironment.new(); we.environment = ent
	_vp.add_child(we)
	_vp.add_child(AssetDefs.world_sun())
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = ext * FRAME_MARGIN
	_vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, CAMERA_HEIGHT, 0.0), Vector3.ZERO, Vector3.FORWARD)
	cam.current = true

func _process(_delta: float) -> void:
	_waits += 1
	if _waits < SETTLE_FRAMES:
		return
	var img := _vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var center := Vector2(SIDE, SIDE) * 0.5
	for n in _model.find_children("*", "Node3D", true, false):
		var nm := str(n.name)
		if not (nm.begins_with("tobera") or nm.begins_with("canon")):
			continue
		var p: Vector3 = (n as Node3D).position
		var q := center + Vector2(p.x, p.z) * _scale_factor
		var wdt: float = (n as Node3D).scale.x * _scale_factor
		var col := THRUSTER_COLOR if nm.begins_with("tobera") else CANNON_COLOR
		# cruz en el punto y una barra del ANCHO declarado, para ver si cubre la boca
		for k in range(-CROSS_RADIUS_PX, CROSS_RADIUS_PX + 1):
			_paints(img, q + Vector2(k, 0), col)
			_paints(img, q + Vector2(0, k), col)
		for k in range(int(-wdt * 0.5), int(wdt * 0.5) + 1):
			_paints(img, q + Vector2(k, WIDTH_BAR_OFFSET_PX), WIDTH_BAR_COLOR)
		print("%-10s en (%.0f, %.0f)  ancho %.1f px" % [nm, q.x, q.y, wdt])
	_measure_muzzles(img)
	var out_path := "%s/anclajes.png" % OUTPUT_DIR
	img.save_png(out_path)
	print("guardado %s" % out_path)
	get_tree().quit()

func _paints(img: Image, q: Vector2, c: Color) -> void:
	var x := int(q.x)
	var y := int(q.y)
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


## Mide las bocas EN EL RENDER, que es lo que ve el ojo, y no en la malla. Cuando
## el histograma de vertices y la imagen no coinciden, manda la imagen: la malla
## trae anillos, soportes y tuberia entre toberas que el reparto por densidad no
## sabe distinguir, y el render ya los ha resuelto con oclusion y perspectiva.
func _measure_muzzles(img: Image) -> void:
	# Banda de las ultimas filas con silueta: ahi solo quedan las campanas.
	var latest := -1
	for y in range(img.get_height() - 1, -1, -1):
		var found := false
		for x in img.get_width():
			if img.get_pixel(x, y).a > ALPHA_THRESHOLD:
				found = true
				break
		if found:
			latest = y
			break
	if latest < 0:
		return
	# Se sube por las filas hasta encontrar una donde las bocas esten SEPARADAS: al
	# ras del todo las campanas se tocan de dos en dos —que es exactamente lo que se
	# veia en el juego— y ahi no se pueden contar.
	for recoil in range(0, RECOIL_MAX_PX, RECOIL_STEP_PX):
		if _muzzles_at(img, latest - recoil) >= MIN_MUZZLES:
			latest -= recoil
			break
	var hgt := BAND_HEIGHT_PX
	var col := PackedInt32Array()
	col.resize(img.get_width())
	for x in img.get_width():
		var n := 0
		for y in range(maxi(0, latest - hgt), latest + 1):
			if img.get_pixel(x, y).a > ALPHA_THRESHOLD:
				n += 1
		col[x] = n

	print("BOCAS medidas en el render (fila %d):" % latest)
	var center := img.get_width() * 0.5
	var start := -1
	for x in img.get_width() + 1:
		var full: bool = x < img.get_width() and col[x] > 0
		if full and start < 0:
			start = x
		elif not full and start >= 0:
			if x - start >= MIN_MUZZLE_WIDTH_PX:
				var c := 0.5 * float(start + x - 1)
				print("  centro %.1f px -> modelo %+.4f   ancho %d px -> %.4f"
					% [c, (c - center) / _scale_factor, x - start, float(x - start) / _scale_factor])
			start = -1


## Cuantas bocas separadas hay en una fila.
func _muzzles_at(img: Image, y: int) -> int:
	if y < 0 or y >= img.get_height():
		return 0
	var n := 0
	var inside := false
	var wdt := 0
	for x in img.get_width():
		var full := img.get_pixel(x, y).a > ALPHA_THRESHOLD
		if full:
			wdt += 1
			inside = true
		elif inside:
			if wdt >= MIN_MUZZLE_WIDTH_PX:
				n += 1
			wdt = 0
			inside = false
	if inside and wdt >= MIN_MUZZLE_WIDTH_PX:
		n += 1
	return n
