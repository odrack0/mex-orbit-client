extends Node2D

## Mide hacia donde mira el modelo en pantalla para cada giro sobre Y, que es lo
## unico que hace falta para casar el 3D con la convencion 2D (arte mirando
## ARRIBA, `_visual_angle = atan2(dy,dx) + 90`). Adivinarlo ya salio mal una vez.

const ANGLES := [0, 90, 180, 270]
var _vp: SubViewport
var _model: Node3D
var _path := "res://assets/npcs/vexor.glb"
var _i := 0
var _waits := 0

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--modelo="):
			var m := arg.trim_prefix("--modelo=")
			# con barra, la ruta es dentro de assets/ (naves, props...); sin ella, npcs
			_path = "res://assets/%s" % m if "/" in m else "res://assets/npcs/%s" % m
	_vp = SubViewport.new()
	_vp.size = Vector2i(410, 410)
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
	cam.size = 2.198
	_vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 8.0, 0.0), Vector3.ZERO, Vector3.FORWARD)
	cam.current = true

func _process(_delta: float) -> void:
	if _i >= ANGLES.size():
		get_tree().quit()
		return
	_model.rotation.y = deg_to_rad(float(ANGLES[_i]))
	_waits += 1
	if _waits < 3:
		return
	_waits = 0
	_vp.get_texture().get_image().save_png("C:/Tools/ori_%s_%03d.png" % [_path.get_file().get_basename(), ANGLES[_i]])
	print("giro Y=%d guardado" % ANGLES[_i])
	_i += 1
