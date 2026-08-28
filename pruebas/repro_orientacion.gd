extends Node2D

## Mide hacia donde mira el modelo en pantalla para cada giro sobre Y, que es lo
## unico que hace falta para casar el 3D con la convencion 2D (arte mirando
## ARRIBA, `_visual_angle = atan2(dy,dx) + 90`). Adivinarlo ya salio mal una vez.

const ANGULOS := [0, 90, 180, 270]
var _vp: SubViewport
var _modelo: Node3D
var _ruta := "res://assets/npcs/vexor.glb"
var _i := 0
var _esperas := 0

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--modelo="):
			var m := arg.trim_prefix("--modelo=")
			# con barra, la ruta es dentro de assets/ (naves, props...); sin ella, npcs
			_ruta = "res://assets/%s" % m if "/" in m else "res://assets/npcs/%s" % m
	_vp = SubViewport.new()
	_vp.size = Vector2i(410, 410)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_modelo = (load(_ruta) as PackedScene).instantiate()
	_vp.add_child(_modelo)

	var ent := Environment.new()
	ent.background_mode = Environment.BG_CLEAR_COLOR
	ent.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	ent.ambient_light_color = Color(0.35, 0.40, 0.55)
	ent.ambient_light_energy = 0.28
	var we := WorldEnvironment.new(); we.environment = ent
	_vp.add_child(we)
	var sol := DirectionalLight3D.new()
	sol.light_energy = 1.0
	sol.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(315.0), 0.0)
	_vp.add_child(sol)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.198
	_vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 8.0, 0.0), Vector3.ZERO, Vector3.FORWARD)
	cam.current = true

func _process(_delta: float) -> void:
	if _i >= ANGULOS.size():
		get_tree().quit()
		return
	_modelo.rotation.y = deg_to_rad(float(ANGULOS[_i]))
	_esperas += 1
	if _esperas < 3:
		return
	_esperas = 0
	_vp.get_texture().get_image().save_png("C:/Tools/ori_%s_%03d.png" % [_ruta.get_file().get_basename(), ANGULOS[_i]])
	print("giro Y=%d guardado" % ANGULOS[_i])
	_i += 1
