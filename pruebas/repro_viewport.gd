extends Node2D

## Repro AISLADO del montaje 3D-en-SubViewport de entity_node, sin servidor ni
## cuenta. Reproduce las DOS cosas que el repro simple no tenia y el juego si:
##   · varias entidades a la vez, cada una con su viewport;
##   · el montaje se hace con el nodo FUERA del arbol, como en setup().
## Si el fan de copias sale aqui, esta en una de esas dos.

const COUNT := 6
var _vps: Array[SubViewport] = []
var _models: Array[Node3D] = []
var _t := 0.0
var _next := 0
const INSTANTS := [0.5, 9.0]

func _ready() -> void:
	for i in COUNT:
		var ent2d := Node2D.new()
		# TODO el montaje ocurre antes del add_child, igual que en setup()
		var vp := _mount(ent2d, i)
		add_child(ent2d)
		ent2d.position = Vector2(150 + (i % 3) * 260, 150 + (i / 3) * 260)
		_vps.append(vp)

func _mount(parent_node: Node2D, i: int) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(410, 410)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	parent_node.add_child(vp)

	var model := (load("res://assets/npcs/vexor.glb") as PackedScene).instantiate()
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
	cam.size = 2.198
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 8.0, 0.0), Vector3.ZERO, Vector3.FORWARD)
	cam.current = true

	var s := Sprite2D.new()
	s.texture = vp.get_texture()
	s.scale = Vector2(0.5, 0.5)
	parent_node.add_child(s)
	return vp

func _process(delta: float) -> void:
	_t += delta
	for i in _models.size():
		_models[i].rotation.y = _t * (0.4 + 0.25 * i)
	if _next < INSTANTS.size() and _t > INSTANTS[_next]:
		_vps[0].get_texture().get_image().save_png("C:/Tools/multi_%.1fs.png" % INSTANTS[_next])
		print("volcado t=%.1f  mallas_en_vp0=%d" % [INSTANTS[_next],
			_vps[0].find_children("*", "MeshInstance3D", true, false).size()])
		_next += 1
		if _next == INSTANTS.size():
			get_tree().quit()
