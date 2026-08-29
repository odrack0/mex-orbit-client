extends Node2D

## Repro AISLADO del montaje 3D-en-SubViewport de entity_node, sin servidor ni
## cuenta. Reproduce las DOS cosas que el repro simple no tenia y el juego si:
##   · varias entidades a la vez, cada una con su viewport;
##   · el montaje se hace con el nodo FUERA del arbol, como en setup().
## Si el fan de copias sale aqui, esta en una de esas dos.

const CUANTOS := 6
var _vps: Array[SubViewport] = []
var _modelos: Array[Node3D] = []
var _t := 0.0
var _siguiente := 0
const INSTANTES := [0.5, 9.0]

func _ready() -> void:
	for i in CUANTOS:
		var ent2d := Node2D.new()
		# TODO el montaje ocurre antes del add_child, igual que en setup()
		var vp := _montar(ent2d, i)
		add_child(ent2d)
		ent2d.position = Vector2(150 + (i % 3) * 260, 150 + (i / 3) * 260)
		_vps.append(vp)

func _montar(padre: Node2D, i: int) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(410, 410)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	padre.add_child(vp)

	var modelo := (load("res://assets/npcs/vexor.glb") as PackedScene).instantiate()
	vp.add_child(modelo)
	_modelos.append(modelo)

	var ent := Environment.new()
	ent.background_mode = Environment.BG_CLEAR_COLOR
	AssetDefs.ambiente_mundo(ent)
	var we := WorldEnvironment.new()
	we.environment = ent
	vp.add_child(we)

	var sol := DirectionalLight3D.new()
	sol.light_energy = 1.0
	sol.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(315.0), 0.0)
	sol.shadow_enabled = false
	vp.add_child(sol)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.198
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 8.0, 0.0), Vector3.ZERO, Vector3.FORWARD)
	cam.current = true

	var s := Sprite2D.new()
	s.texture = vp.get_texture()
	s.scale = Vector2(0.5, 0.5)
	padre.add_child(s)
	return vp

func _process(delta: float) -> void:
	_t += delta
	for i in _modelos.size():
		_modelos[i].rotation.y = _t * (0.4 + 0.25 * i)
	if _siguiente < INSTANTES.size() and _t > INSTANTES[_siguiente]:
		_vps[0].get_texture().get_image().save_png("C:/Tools/multi_%.1fs.png" % INSTANTES[_siguiente])
		print("volcado t=%.1f  mallas_en_vp0=%d" % [INSTANTES[_siguiente],
			_vps[0].find_children("*", "MeshInstance3D", true, false).size()])
		_siguiente += 1
		if _siguiente == INSTANTES.size():
			get_tree().quit()
