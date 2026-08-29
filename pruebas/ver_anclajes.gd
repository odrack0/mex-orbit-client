extends Node2D

## Dibuja los marcadores ENCIMA del render, con el mismo montaje que usa el juego,
## y guarda la imagen. Sirve para ver si una tobera esta donde el cliente cree, en
## vez de discutirlo mirando la nave en movimiento.
##
##   godot --path . res://pruebas/ver_anclajes.tscn -- --modelo=ships/phoenix.glb

const LADO := 512
var _ruta := "res://assets/ships/phoenix.glb"
var _vp: SubViewport
var _modelo: Node3D
var _escala := 1.0
var _esperas := 0

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--modelo="):
			_ruta = "res://assets/%s" % arg.trim_prefix("--modelo=")

	_modelo = (load(_ruta) as PackedScene).instantiate()
	var caja := AABB()
	var primera := true
	for m in _modelo.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = (m as MeshInstance3D).transform * (m as MeshInstance3D).get_aabb()
		caja = a if primera else caja.merge(a)
		primera = false
	var ext: float = maxf(caja.size.x, caja.size.z)
	# Mismo contrato que el juego: el lado mayor ocupa el ancho util del render.
	_escala = float(LADO) / (ext * 1.15)

	_vp = SubViewport.new()
	_vp.size = Vector2i(LADO, LADO)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_vp.add_child(_modelo)
	var ent := Environment.new()
	ent.background_mode = Environment.BG_CLEAR_COLOR
	AssetDefs.ambiente_mundo(ent)
	var we := WorldEnvironment.new(); we.environment = ent
	_vp.add_child(we)
	_vp.add_child(AssetDefs.sol_mundo())
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = ext * 1.15
	_vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 8.0, 0.0), Vector3.ZERO, Vector3.FORWARD)
	cam.current = true

func _process(_delta: float) -> void:
	_esperas += 1
	if _esperas < 4:
		return
	var img := _vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var centro := Vector2(LADO, LADO) * 0.5
	for n in _modelo.find_children("*", "Node3D", true, false):
		var nom := str(n.name)
		if not (nom.begins_with("tobera") or nom.begins_with("canon")):
			continue
		var p: Vector3 = (n as Node3D).position
		var q := centro + Vector2(p.x, p.z) * _escala
		var ancho: float = (n as Node3D).scale.x * _escala
		var col := Color(0, 1, 1) if nom.begins_with("tobera") else Color(1, 0.4, 0)
		# cruz en el punto y una barra del ANCHO declarado, para ver si cubre la boca
		for k in range(-6, 7):
			_pinta(img, q + Vector2(k, 0), col)
			_pinta(img, q + Vector2(0, k), col)
		for k in range(int(-ancho * 0.5), int(ancho * 0.5) + 1):
			_pinta(img, q + Vector2(k, 8), Color(1, 1, 0))
		print("%-10s en (%.0f, %.0f)  ancho %.1f px" % [nom, q.x, q.y, ancho])
	_medir_bocas(img)
	img.save_png("C:/Tools/anclajes.png")
	print("guardado C:/Tools/anclajes.png")
	get_tree().quit()

func _pinta(img: Image, q: Vector2, c: Color) -> void:
	var x := int(q.x)
	var y := int(q.y)
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


## Mide las bocas EN EL RENDER, que es lo que ve el ojo, y no en la malla. Cuando
## el histograma de vertices y la imagen no coinciden, manda la imagen: la malla
## trae anillos, soportes y tuberia entre toberas que el reparto por densidad no
## sabe distinguir, y el render ya los ha resuelto con oclusion y perspectiva.
func _medir_bocas(img: Image) -> void:
	# Banda de las ultimas filas con silueta: ahi solo quedan las campanas.
	var ultima := -1
	for y in range(img.get_height() - 1, -1, -1):
		var hay := false
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.3:
				hay = true
				break
		if hay:
			ultima = y
			break
	if ultima < 0:
		return
	# Se sube por las filas hasta encontrar una donde las bocas esten SEPARADAS: al
	# ras del todo las campanas se tocan de dos en dos —que es exactamente lo que se
	# veia en el juego— y ahi no se pueden contar.
	for retroceso in range(0, 60, 2):
		if _bocas_en(img, ultima - retroceso) >= 4:
			ultima -= retroceso
			break
	var alto := 6
	var col := PackedInt32Array()
	col.resize(img.get_width())
	for x in img.get_width():
		var n := 0
		for y in range(maxi(0, ultima - alto), ultima + 1):
			if img.get_pixel(x, y).a > 0.3:
				n += 1
		col[x] = n

	print("BOCAS medidas en el render (fila %d):" % ultima)
	var centro := img.get_width() * 0.5
	var ini := -1
	for x in img.get_width() + 1:
		var lleno: bool = x < img.get_width() and col[x] > 0
		if lleno and ini < 0:
			ini = x
		elif not lleno and ini >= 0:
			if x - ini >= 4:
				var c := 0.5 * float(ini + x - 1)
				print("  centro %.1f px -> modelo %+.4f   ancho %d px -> %.4f"
					% [c, (c - centro) / _escala, x - ini, float(x - ini) / _escala])
			ini = -1


## Cuantas bocas separadas hay en una fila.
func _bocas_en(img: Image, y: int) -> int:
	if y < 0 or y >= img.get_height():
		return 0
	var n := 0
	var dentro := false
	var ancho := 0
	for x in img.get_width():
		var lleno := img.get_pixel(x, y).a > 0.3
		if lleno:
			ancho += 1
			dentro = true
		elif dentro:
			if ancho >= 4:
				n += 1
			ancho = 0
			dentro = false
	if dentro and ancho >= 4:
		n += 1
	return n
