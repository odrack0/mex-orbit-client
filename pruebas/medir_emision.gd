extends Node2D

## Compara el rojo de MEDIA contra el de ALTA para saber cuanta ganancia le falta
## al 3D, en vez de subirla a ojo.
##
## Media no es una imagen: es el PNG base MAS la capa emisiva en blend ADITIVO con
## la intensidad del pulso. Aqui se compone a mano igual que lo hace entity_node.
## Se RECORTA a 1.0 en los dos lados, porque la pantalla tampoco pasa de 1 y medir
## media sin recortar la haria parecer mas brillante de lo que se ve.

const K := 2.6        # pico del pulso segun data/npcs/vexor.json
const GANANCIAS := [0.0, 2.6, 5.0, 9.0, 16.0]
## Con glow la emision por encima de 1 se DERRAMA a los pixeles vecinos en vez de
## recortarse, que es lo que el ojo lee como "brilla". Cuesta un post-proceso por
## viewport, asi que hay que saber cuanto compra antes de ponerlo.
const CON_GLOW := [2.6, 5.0, 9.0]

var _vp: SubViewport
var _mats: Array[BaseMaterial3D] = []
var _env: Environment
var _bicho := "vexor"

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bicho="):
			_bicho = arg.trim_prefix("--bicho=")
	_vp = SubViewport.new()
	_vp.size = Vector2i(512, 512)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var modelo := (load("res://assets/npcs/%s.glb" % _bicho) as PackedScene).instantiate()
	_vp.add_child(modelo)
	for m in modelo.find_children("*", "MeshInstance3D", true, false):
		var malla: MeshInstance3D = m
		var copia: BaseMaterial3D = (malla.get_active_material(0) as BaseMaterial3D).duplicate()
		malla.set_surface_override_material(0, copia)
		_mats.append(copia)

	var ent := Environment.new()
	ent.background_mode = Environment.BG_CLEAR_COLOR
	ent.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	ent.ambient_light_color = Color(0.35, 0.40, 0.55)
	ent.ambient_light_energy = 0.28
	_env = ent
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
	_medir.call_deferred()

## Rojo medio sobre lo que NO es fondo, y cuanto del bicho pasa de 0.8 de rojo.
func _stats(img: Image, etiqueta: String) -> void:
	var n := 0; var suma := 0.0; var fuertes := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			n += 1
			var r := minf(c.r, 1.0)
			suma += r
			if r > 0.8:
				fuertes += 1
	print("%-11s rojo medio=%.3f  pixeles>0.8=%5.1f%%  (%d px)"
		% [etiqueta, suma / maxi(n, 1), 100.0 * fuertes / maxi(n, 1), n])

func _medir() -> void:
	var base := (load("res://assets/npcs/%s-base.png" % _bicho) as Texture2D).get_image()
	var emi := (load("res://assets/npcs/%s-emissive.png" % _bicho) as Texture2D).get_image()
	base.decompress(); emi.decompress()
	var media := Image.create_empty(base.get_width(), base.get_height(), false, Image.FORMAT_RGBAF)
	for y in base.get_height():
		for x in base.get_width():
			var b := base.get_pixel(x, y)
			var e := emi.get_pixel(x, y)
			media.set_pixel(x, y, Color(b.r + e.r * e.a * K, b.g + e.g * e.a * K,
				b.b + e.b * e.a * K, maxf(b.a, e.a)))
	media.save_png("C:/Tools/media_%s.png" % _bicho)
	_stats(media, "MEDIA")

	for g in GANANCIAS:
		for m in _mats:
			m.emission_energy_multiplier = g
		# tres pasadas completas: el material se sube a la GPU en la siguiente, y
		# leer antes devuelve el fotograma anterior. Es lo que estropeo la primera
		# medicion, que dio la misma cifra para todas las ganancias.
		for i in 3:
			await RenderingServer.frame_post_draw
		var img := _vp.get_texture().get_image()
		img.save_png("C:/Tools/em_%02d.png" % int(g * 10))
		_stats(img, "ALTA x%.1f" % g)

	_env.glow_enabled = true
	_env.glow_intensity = 1.0
	_env.glow_bloom = 0.25
	_env.glow_hdr_threshold = 0.9
	for g in CON_GLOW:
		for m in _mats:
			m.emission_energy_multiplier = g
		for i in 3:
			await RenderingServer.frame_post_draw
		var img := _vp.get_texture().get_image()
		img.save_png("C:/Tools/em_glow_%02d.png" % int(g * 10))
		_stats(img, "GLOW x%.1f" % g)
	get_tree().quit()
