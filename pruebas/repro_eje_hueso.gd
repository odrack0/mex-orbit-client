extends Node2D

## Averigua SOBRE QUE EJE hay que rotar un hueso para conseguir el gesto que
## quieres. Renderiza el modelo con ese hueso girado en X, en Y y en Z, y guarda
## las tres imagenes: se elige mirando, no razonando sobre la permutacion de ejes
## de glTF. Deducirlo ya salio mal con la orientacion del bicho entero.
##
##   godot --path . res://pruebas/repro_eje_hueso.tscn -- --hueso=cuerno_izq --grados=30

var _bone := "cuerno_izq"
var _path := "res://assets/npcs/vexor.glb"
var _degrees := 30.0
var _vp: SubViewport
var _sk: Skeleton3D
var _axis := -1
var _only := -1        # si se fija, solo ese eje
var _both := false    # posa el par izq/der en espejo, como en el juego
var _waits := 0

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hueso="):
			_bone = arg.trim_prefix("--hueso=")
		elif arg.begins_with("--grados="):
			_degrees = float(arg.trim_prefix("--grados="))
		elif arg.begins_with("--modelo="):
			# Acepta "vorax.glb" y tambien "npcs/vorax.glb". Antes prefijaba
			# `npcs/` siempre, asi que la segunda forma —la que documenta
			# ver_anclajes— daba `assets/npcs/npcs/vorax.glb`, el modelo NO
			# cargaba y la escena guardaba cuatro PNG negros diciendo "guardado".
			var m := arg.trim_prefix("--modelo=")
			_path = "res://assets/%s" % m if m.contains("/") else "res://assets/npcs/%s" % m
		elif arg.begins_with("--solo-eje="):
			_only = int(arg.trim_prefix("--solo-eje="))
		elif arg == "--ambos":
			_both = true

	_vp = SubViewport.new()
	_vp.size = Vector2i(512, 512)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	# Se comprueba que EXISTE antes de cargarlo. Un `load` fallido devuelve null,
	# `instantiate()` revienta, y la escena seguia adelante guardando negros: un
	# render vacio que se anuncia como bueno es peor que un error, porque se
	# analiza como si fuera un resultado.
	if not ResourceLoader.exists(_path):
		push_error("no existe %s" % _path)
		get_tree().quit(1)
		return
	var scene := load(_path) as PackedScene
	if scene == null:
		push_error("%s no es una escena cargable" % _path)
		get_tree().quit(1)
		return
	var model := scene.instantiate()
	_vp.add_child(model)
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		push_error("el modelo %s no trae esqueleto" % _path)
		get_tree().quit(1)
		return
	_sk = skeletons[0]
	# Sin comprension de lista: GDScript no las tiene, y escribirla es un error de
	# PARSEO que tumba el script entero — misma familia que la asignacion multiple.
	var bone_list: Array[String] = []
	for i in _sk.get_bone_count():
		bone_list.append(_sk.get_bone_name(i))
	print("huesos: %s" % str(bone_list))
	# La extension se MIDE del modelo. Antes era una constante (2.198) heredada
	# de otro bicho, y con un modelo mas ancho el render salia negro sin decir por
	# que: la camara encuadraba fuera de la malla. Es el mismo criterio que ya
	# sigue el cliente, y por el mismo motivo.
	var box := AABB()
	var first := true
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m
		var a := mi.global_transform * mi.get_aabb()
		box = a if first else box.merge(a)
		first = false
	print("caja del modelo: pos %s tam %s" % [str(box.position), str(box.size)])

	var ent := Environment.new()
	ent.background_mode = Environment.BG_CLEAR_COLOR
	AssetDefs.world_ambient(ent)
	var we := WorldEnvironment.new(); we.environment = ent
	_vp.add_child(we)
	_vp.add_child(AssetDefs.world_sun())
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(maxf(box.size.x, box.size.z), 0.1) * 1.15
	_vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 8.0, 0.0), Vector3.ZERO, Vector3.FORWARD)
	cam.current = true

	var names: Array[String] = []
	for i in _sk.get_bone_count():
		names.append(_sk.get_bone_name(i))
	print("ESQUELETO %s" % str(names))
	if _sk.find_bone(_bone) < 0:
		push_error("no existe el hueso %s" % _bone)
		get_tree().quit()

func _process(_delta: float) -> void:
	_waits += 1
	if _waits < 3:
		return
	_waits = 0
	# El REPOSO tambien se guarda: tres poses sin la de partida no se pueden
	# comparar, que fue el primer intento.
	_vp.get_texture().get_image().save_png(
		"C:/Tools/eje_%s_%s_%s.png" % [_path.get_file().get_basename(), _bone, "reposo" if _axis < 0 else ("g%d" % int(_degrees) if _only >= 0 else str(_axis))])
	print("  %s guardado" % ("reposo" if _axis < 0 else "eje %d" % _axis))
	_axis += 1
	if _axis > 2:
		get_tree().quit()
		return
	# COMPONER sobre el reposo: set_bone_pose_rotation fija la pose entera.
	var axis := _only if _only >= 0 else _axis
	var v := Vector3.RIGHT
	if axis == 1:
		v = Vector3.UP
	elif axis == 2:
		v = Vector3.BACK
	var pairs := [[_bone, 1.0]]
	if _both:
		# el par en espejo, que es como lo mueve el juego: un cuerno solo no deja
		# juzgar el gesto
		var other := _bone.replace("izq", "der") if "izq" in _bone else _bone.replace("der", "izq")
		pairs = [[_bone, -1.0], [other, 1.0]]
	for par in pairs:
		var i: int = _sk.find_bone(par[0])
		if i < 0:
			continue
		var rest := _sk.get_bone_rest(i).basis.get_rotation_quaternion()
		_sk.set_bone_pose_rotation(i, rest * Quaternion(v, deg_to_rad(_degrees) * float(par[1])))
