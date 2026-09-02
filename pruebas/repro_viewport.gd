extends Node2D

## Repro AISLADO del montaje 3D-en-SubViewport de entity_node, sin servidor ni
## cuenta. Reproduce las DOS cosas que el repro simple no tenia y el juego si:
##   · varias entidades a la vez, cada una con su viewport;
##   · el montaje se hace con el nodo FUERA del arbol, como en setup().
## Si el fan de copias sale aqui, esta en una de esas dos.

## Diales de data/config/tests.json (`repro_viewport` + `common`).
static var CFG: Dictionary = AssetDefs.config("tests").get("repro_viewport", {})
static var CFG_COMMON: Dictionary = AssetDefs.config("tests").get("common", {})
static var CAMERA_HEIGHT: float = AssetDefs.num(CFG_COMMON, "camera_height", 8.0)
static var OUTPUT_DIR: String = str(CFG_COMMON.get("output_dir", "C:/Tools"))
static var MODEL: String = str(CFG.get("model", "res://assets/npcs/vexor.glb"))
static var COUNT: int = int(AssetDefs.num(CFG, "count", 6))
static var GRID_ORIGIN: Vector2 = AssetDefs.vec2(CFG.get("grid_origin"), Vector2(150, 150))
static var GRID_STEP: float = AssetDefs.num(CFG, "grid_step", 260)
static var GRID_COLUMNS: int = int(AssetDefs.num(CFG, "grid_columns", 3))
static var RENDER_SIZE: int = int(AssetDefs.num(CFG, "render_size", 410))
static var CAMERA_SIZE: float = AssetDefs.num(CFG, "camera_size", 2.198)
static var SPRITE_SCALE: float = AssetDefs.num(CFG, "sprite_scale", 0.5)
static var SPIN_BASE: float = AssetDefs.num(CFG, "spin_base", 0.4)
static var SPIN_STEP: float = AssetDefs.num(CFG, "spin_step", 0.25)

var _vps: Array[SubViewport] = []
var _models: Array[Node3D] = []
var _t := 0.0
var _next := 0
static var INSTANTS: Array = CFG.get("snapshot_times_s", [0.5, 9.0])

func _ready() -> void:
	for i in COUNT:
		var ent2d := Node2D.new()
		# TODO el montaje ocurre antes del add_child, igual que en setup()
		var vp := _mount(ent2d, i)
		add_child(ent2d)
		ent2d.position = GRID_ORIGIN + Vector2((i % GRID_COLUMNS) * GRID_STEP, (i / GRID_COLUMNS) * GRID_STEP)
		_vps.append(vp)

func _mount(parent_node: Node2D, i: int) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(RENDER_SIZE, RENDER_SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	parent_node.add_child(vp)

	var model := (load(MODEL) as PackedScene).instantiate()
	vp.add_child(model)
	_models.append(model)

	var ent := Environment.new()
	ent.background_mode = Environment.BG_CLEAR_COLOR
	AssetDefs.world_ambient(ent)
	var we := WorldEnvironment.new()
	we.environment = ent
	vp.add_child(we)

	vp.add_child(AssetDefs.world_sun())

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = CAMERA_SIZE
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, CAMERA_HEIGHT, 0.0), Vector3.ZERO, Vector3.FORWARD)
	cam.current = true

	var s := Sprite2D.new()
	s.texture = vp.get_texture()
	s.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	parent_node.add_child(s)
	return vp

func _process(delta: float) -> void:
	_t += delta
	for i in _models.size():
		_models[i].rotation.y = _t * (SPIN_BASE + SPIN_STEP * i)
	if _next < INSTANTS.size() and _t > INSTANTS[_next]:
		_vps[0].get_texture().get_image().save_png("%s/multi_%.1fs.png" % [OUTPUT_DIR, INSTANTS[_next]])
		print("volcado t=%.1f  mallas_en_vp0=%d" % [INSTANTS[_next],
			_vps[0].find_children("*", "MeshInstance3D", true, false).size()])
		_next += 1
		if _next == INSTANTS.size():
			get_tree().quit()
