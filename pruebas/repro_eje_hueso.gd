extends Node2D

## Averigua SOBRE QUE EJE hay que rotar un hueso para conseguir el gesto que
## quieres. Renderiza el modelo con ese hueso girado en X, en Y y en Z, y guarda
## las tres imagenes: se elige mirando, no razonando sobre la permutacion de ejes
## de glTF. Deducirlo ya salio mal con la orientacion del bicho entero.
##
##   godot --path . res://pruebas/repro_eje_hueso.tscn -- --hueso=cuerno_izq --grados=30

var _hueso := "cuerno_izq"
var _ruta := "res://assets/npcs/vexor.glb"
var _grados := 30.0
var _vp: SubViewport
var _sk: Skeleton3D
var _eje := -1
var _esperas := 0

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hueso="):
			_hueso = arg.trim_prefix("--hueso=")
		elif arg.begins_with("--grados="):
			_grados = float(arg.trim_prefix("--grados="))
		elif arg.begins_with("--modelo="):
			_ruta = "res://assets/npcs/%s" % arg.trim_prefix("--modelo=")

	_vp = SubViewport.new()
	_vp.size = Vector2i(512, 512)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var modelo := (load(_ruta) as PackedScene).instantiate()
	_vp.add_child(modelo)
	_sk = modelo.find_children("*", "Skeleton3D", true, false)[0]

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

	var nombres: Array[String] = []
	for i in _sk.get_bone_count():
		nombres.append(_sk.get_bone_name(i))
	print("ESQUELETO %s" % str(nombres))
	if _sk.find_bone(_hueso) < 0:
		push_error("no existe el hueso %s" % _hueso)
		get_tree().quit()

func _process(_delta: float) -> void:
	_esperas += 1
	if _esperas < 3:
		return
	_esperas = 0
	# El REPOSO tambien se guarda: tres poses sin la de partida no se pueden
	# comparar, que fue el primer intento.
	_vp.get_texture().get_image().save_png(
		"C:/Tools/eje_%s_%s_%s.png" % [_ruta.get_file().get_basename(), _hueso, "reposo" if _eje < 0 else str(_eje)])
	print("  %s guardado" % ("reposo" if _eje < 0 else "eje %d" % _eje))
	_eje += 1
	if _eje > 2:
		get_tree().quit()
		return
	# COMPONER sobre el reposo: set_bone_pose_rotation fija la pose entera.
	var i := _sk.find_bone(_hueso)
	var rest := _sk.get_bone_rest(i).basis.get_rotation_quaternion()
	var v := Vector3.RIGHT
	if _eje == 1:
		v = Vector3.UP
	elif _eje == 2:
		v = Vector3.BACK
	_sk.set_bone_pose_rotation(i, rest * Quaternion(v, deg_to_rad(_grados)))
