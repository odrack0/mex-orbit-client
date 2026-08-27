# Banco de pruebas: cuantos bichos VIVOS aguanta el cliente.
#
# No es el juego: es la pregunta que decide si el pipeline de modelo unico entra
# o no. Monta N modelos girando bajo una camara ortografica en la elevacion que
# se le pida, con UNA luz direccional clavada en el mundo —la misma idea que
# AssetDefs.LUZ_MUNDO_GRADOS—, mide los fps sostenidos y se va.
#
# Uso:
#   Godot --path . pruebas/banco_3d.tscn -- --n=15 --elev=70 --shot=C:/ruta.png
extends Node3D

const RUTA := "res://pruebas/vexor.glb"
const LUZ_MUNDO_GRADOS := 315.0

var _n := 15
var _elev := 70.0
var _shot := ""
var _segundos := 6.0

var _bichos: Array[Node3D] = []
var _label: Label
var _t := 0.0
var _fps_min := 9999.0
var _fps_suma := 0.0
var _fps_muestras := 0

## Todos los tiempos de fotograma, para poder sacar percentiles. El MINIMO
## ABSOLUTO no es una estadistica: es "lo peor que he visto", y solo puede
## empeorar cuanto mas tiempo miras. En pasadas de 6 s daba 70 fps y dejando la
## ventana abierta unos minutos bajaba a 38 — sin que el juego fuera a peor, solo
## por haber visto veinte veces mas fotogramas. Lo que se compara entre pasadas
## es el 1% PEOR, que si converge.
var _dts := PackedFloat32Array()
var _p1 := 0.0
var _proximo_recalculo := 0.0

## Un tiron visible: por debajo de 30 fps en un solo fotograma.
const TIRON_MS := 33.3
## Frontera para separar "esto se compilo tarde" de "esto pasa siempre". El
## driver de OpenGL compila shaders la primera vez que los usa y bloquea; si
## todos los tirones caen antes de esta marca, no son del juego.
const PRONTO_S := 10.0

var _calentamiento := 2.0
var _t_peor := 0.0
var _tirones_pronto := 0
var _tirones_tarde := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--n="):
			_n = int(arg.trim_prefix("--n="))
		elif arg.begins_with("--elev="):
			_elev = float(arg.trim_prefix("--elev="))
		elif arg.begins_with("--shot="):
			_shot = arg.trim_prefix("--shot=")
		elif arg.begins_with("--calentamiento="):
			_calentamiento = float(arg.trim_prefix("--calentamiento="))
		elif arg.begins_with("--segundos="):
			# 0 = no se cierra solo. Para mirarlo en vez de medirlo: la medida
			# sigue actualizandose en pantalla y se cierra a mano.
			_segundos = float(arg.trim_prefix("--segundos="))

	var escena: PackedScene = load(RUTA)
	if escena == null:
		push_error("BANCO: no se pudo cargar " + RUTA)
		get_tree().quit(1)
		return

	# rejilla lo mas cuadrada posible, separacion algo mayor que el bicho (1,9)
	var lado := int(ceil(sqrt(float(_n))))
	var sep := 2.4
	for i in _n:
		var m := escena.instantiate()
		var fila := i / lado
		var col := i % lado
		m.position = Vector3((col - (lado - 1) * 0.5) * sep, 0.0,
			(fila - (lado - 1) * 0.5) * sep)
		# cada uno con su fase, para que no giren todos igual y el ojo lo note
		m.rotation.y = TAU * float(i) / float(_n)
		add_child(m)
		_bichos.append(m)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.043, 0.051, 0.071)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.40, 0.55)
	e.ambient_light_energy = 0.35
	e.glow_enabled = true
	env.environment = e
	add_child(env)

	# La luz NO gira con los bichos: es lo unico que distingue un objeto de una
	# calcomania, y es la misma regla que ya vive en AssetDefs.
	var sol := DirectionalLight3D.new()
	sol.light_energy = 2.6
	sol.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(LUZ_MUNDO_GRADOS), 0.0)
	sol.shadow_enabled = false
	add_child(sol)

	var extension := float(lado) * sep
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = extension * 1.15
	var el := deg_to_rad(_elev)
	var d := extension * 3.0
	add_child(cam)
	# look_at exige estar YA en el arbol; llamarlo antes de add_child solo
	# imprime un error y deja la camara mirando a donde estaba.
	cam.position = Vector3(0.0, d * sin(el), d * cos(el))
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.current = true

	# Sin esto la medida no vale nada: con vsync el contador se queda pegado a la
	# frecuencia del monitor y "60 fps" solo significa "no bajo de 60".
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var capa := CanvasLayer.new()
	add_child(capa)
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.85, 0.90, 1.0))
	capa.add_child(_label)

	print("BANCO n=%d elev=%.0f tris=%d" % [_n, _elev, _n * 15000])


func _process(delta: float) -> void:
	for i in _bichos.size():
		_bichos[i].rotation.y += deg_to_rad(100.0) * delta * (0.6 + 0.4 * float(i % 3))

	_t += delta
	# Se mide el TIEMPO DE FOTOGRAMA, no el contador de Godot: el contador es una
	# media movil y esconde justo lo que interesa, que es el peor fotograma.
	var fps := 1.0 / maxf(delta, 0.000001)
	# los dos primeros segundos no cuentan: shaders y texturas se estan calentando
	if _t > _calentamiento:
		_fps_suma += fps
		_fps_muestras += 1
		if fps < _fps_min:
			_fps_min = fps
			_t_peor = _t          # CUANDO fue el peor dice mas que cuanto fue
		_dts.append(delta)
		if delta * 1000.0 > TIRON_MS:
			if _t < PRONTO_S:
				_tirones_pronto += 1
			else:
				_tirones_tarde += 1

	# El percentil se recalcula cada medio segundo, no por fotograma: ordenar
	# miles de muestras a 100 fps seria medir el coste de medir.
	if _t > _proximo_recalculo and _dts.size() > 100:
		_proximo_recalculo = _t + 0.5
		_p1 = _percentil_bajo(1.0)

	var media := _fps_suma / maxf(1.0, float(_fps_muestras))
	_label.text = ("%d bichos vivos · %d tris · elev %.0f°\n%d fps  (media %.0f · 1%% peor %.0f · minimo %.0f en t=%.1fs)"
		+ "\ntirones >%.0f ms:  %d en los primeros %ds  ·  %d despues") % [
		_n, _n * 15000, _elev, int(fps), media, _p1, _fps_min, _t_peor,
		TIRON_MS, _tirones_pronto, int(PRONTO_S), _tirones_tarde]

	# En web no se cierra: no hay a quien devolverle el codigo de salida y la
	# medida se lee de la pantalla, asi que sigue girando y actualizando.
	# Con --segundos=0 tampoco, que es el modo "mirarlo" en vez de "medirlo".
	if _segundos > 0.0 and _t >= _segundos and not OS.has_feature("web"):
		set_process(false)
		_terminar(media)


## Media del PEOR `pct`% de fotogramas, en fps. Es la cifra que se compara entre
## pasadas: el minimo absoluto lo decide un hipo suelto —otro proceso, el reloj
## de la GPU— y no dice nada de como va el juego.
func _percentil_bajo(pct: float) -> float:
	var ordenados := _dts.duplicate()
	ordenados.sort()
	var cuantos := maxi(1, int(float(ordenados.size()) * pct / 100.0))
	var suma := 0.0
	for i in cuantos:
		suma += ordenados[ordenados.size() - 1 - i]   # los mas LARGOS = los peores
	return float(cuantos) / suma


func _terminar(media: float) -> void:
	await RenderingServer.frame_post_draw
	if _shot != "":
		get_viewport().get_texture().get_image().save_png(_shot)
	print("RESULTADO n=%d elev=%.0f media=%.1f  1%%peor=%.1f  minimo=%.1f (t=%.1fs)  tirones=%d/%d pronto/tarde"
		% [_n, _elev, media, _percentil_bajo(1.0), _fps_min, _t_peor,
		_tirones_pronto, _tirones_tarde])
	get_tree().quit(0)
