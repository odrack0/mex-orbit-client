extends Node2D

## Mide hacia donde mira el modelo en pantalla para cada giro sobre Y, que es lo
## unico que hace falta para casar el 3D con la convencion 2D (arte mirando
## ARRIBA, `_visual_angle = atan2(dy,dx) + 90`). Adivinarlo ya salio mal una vez.

## Diales de data/config/tests.json (`repro_orientation` + `common`).
static var CFG: Dictionary = AssetDefs.config("tests").get("repro_orientation", {})
static var CFG_COMMON: Dictionary = AssetDefs.config("tests").get("common", {})
static var CAMERA_HEIGHT: float = AssetDefs.num(CFG_COMMON, "camera_height", 8.0)
static var OUTPUT_DIR: String = str(CFG_COMMON.get("output_dir", "C:/Tools"))
static var ANGLES: Array[int] = _ints(CFG.get("angles_deg"), [0, 90, 180, 270])
static var DEFAULT_MODEL: String = str(CFG.get("default_model", "res://assets/npcs/vexor.glb"))
static var RENDER_SIZE: int = int(AssetDefs.num(CFG, "render_size", 410))
static var CAMERA_SIZE: float = AssetDefs.num(CFG, "camera_size", 2.198)
static var SETTLE_FRAMES: int = int(AssetDefs.num(CFG, "settle_frames", 3))

var _vp: SubViewport
var _model: Node3D
var _path := DEFAULT_MODEL
var _i := 0
var _waits := 0


## Los numeros del JSON llegan como float; los giros se quieren enteros (van al
## nombre del PNG con %03d).
static func _ints(v: Variant, fallback: Array[int]) -> Array[int]:
	if typeof(v) != TYPE_ARRAY:
		return fallback
	var output: Array[int] = []
	for x in (v as Array):
		output.append(int(x))
	return output

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--model="):
			var m := arg.trim_prefix("--model=")
			# con barra, la ruta es dentro de assets/ (naves, props...); sin ella, npcs
			_path = "res://assets/%s" % m if "/" in m else "res://assets/npcs/%s" % m
	_vp = SubViewport.new()
	_vp.size = Vector2i(RENDER_SIZE, RENDER_SIZE)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_model = (load(_path) as PackedScene).instantiate()
	_vp.add_child(_model)

	var ent := Environment.new()
	ent.background_mode = Environment.BG_CLEAR_COLOR
	AssetDefs.world_ambient(ent)
	var we := WorldEnvironment.new(); we.environment = ent
	_vp.add_child(we)
	_vp.add_child(AssetDefs.world_sun())
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = CAMERA_SIZE
	_vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, CAMERA_HEIGHT, 0.0), Vector3.ZERO, Vector3.FORWARD)
	cam.current = true

func _process(_delta: float) -> void:
	if _i >= ANGLES.size():
		get_tree().quit()
		return
	_model.rotation.y = deg_to_rad(float(ANGLES[_i]))
	_waits += 1
	if _waits < SETTLE_FRAMES:
		return
	_waits = 0
	_vp.get_texture().get_image().save_png("%s/ori_%s_%03d.png" % [OUTPUT_DIR, _path.get_file().get_basename(), ANGLES[_i]])
	print("giro Y=%d guardado" % ANGLES[_i])
	_i += 1
