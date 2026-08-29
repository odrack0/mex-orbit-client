# Minimapa — ventana del sistema N (doc canonico §8) con el comportamiento del
# prototipo: zoom por pasos, titulo con coordenadas vivas, clic = autopiloto.
# Dibuja: rejilla tenue, hostiles con anillo pulsante, jugadores, cajas ambar,
# el heroe cian con anillo respirando y la linea punteada del autopiloto con X.
#
# El chrome sale de `NWindow`; los pasos de zoom van a la CABECERA como `.zbtn`,
# que es donde el §8 los quiere — no son contenido, son control de la ventana.
class_name MinimapWindow
extends NWindow

signal fly_to(world_pos: Vector2)

const ICONO := "res://assets/ui/icons/map.svg"
const WIDTHS := [180, 238, 300, 380, 460]

var _world: Node          # el mundo: entidades, cajas, heroe, limites
var _wi := 2              # indice del paso de zoom
var _canvas: Control
var _lado := Vector2.ZERO      # el tamanio REAL del mapa dibujado, sin deformar
var _t := 0.0


func setup(world: Node, map_code: String) -> void:
	_world = world
	clave = "minimapa"
	_construir("Sector %s" % map_code, ICONO)
	_titulo = titulo_label()
	boton_cabecera("−", func(): _zoom(-1))
	boton_cabecera("+", func(): _zoom(1))

	_canvas = Control.new()
	_canvas.draw.connect(_dibujar)
	_canvas.gui_input.connect(_click_canvas)
	# SHRINK: sin esto el contenedor lo estira al ancho de la ventana y el mapa se
	# dibuja con un ancho y un alto que no se corresponden — deformado, que es
	# justo lo que el §8 prohibe
	_canvas.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	contenido.add_child(_canvas)
	_aplicar_zoom()
	_reposicionar()


## Al saltar de sector el minimapa NO se rehace: solo cambia de nombre. Volver a
## llamar a `setup` le montaba un segundo chrome y un segundo lienzo encima del
## primero, y el lienzo viejo seguia intentando dibujarse fuera de su `_draw`.
func renombrar(map_code: String) -> void:
	if _titulo != null:
		_titulo.text = "SECTOR %s" % map_code


func _zoom(delta: int) -> void:
	_wi = clampi(_wi + delta, 0, WIDTHS.size() - 1)
	_aplicar_zoom()


## §8: el alto sale del ancho y del ratio del mapa. NUNCA se deforma.
##
## El zoom cambiaba solo el canvas, y una ventana en Godot **no encoge sola**
## cuando su contenido encoge: el aro se quedaba con el ancho anterior, el
## contenedor estiraba el canvas para llenarlo y el mapa acababa con el ancho
## viejo y el alto nuevo. En la captura del bug medía 640x260 —ratio 2,46—
## cuando el mapa es 20800x12800 —ratio 1,625—. Hay que pedirle a la ventana que
## se reajuste, y ahi los dos escalan juntos.
func _aplicar_zoom() -> void:
	var w: float = WIDTHS[_wi]
	var limites: Vector2 = _world.limites()
	_lado = Vector2(w, w * limites.y / limites.x)
	_canvas.custom_minimum_size = _lado
	_reajustar.call_deferred()


## Para que el autotest pueda AFIRMAR el §8. La deformacion no se veia en las
## capturas —un mapa estirado sigue pareciendo un mapa— y por eso llego hasta el
## usuario: hace falta comparar el ratio con un numero, no mirarlo.
func deformacion() -> float:
	if _lado.y <= 0.0:
		return 999.0
	var limites: Vector2 = _world.limites()
	return absf(_lado.x / _lado.y - limites.x / limites.y)


## Y que el canvas mida de verdad lo que dice medir: si el contenedor lo estira,
## el dibujo y los clicks dejan de coincidir con lo que se ve.
func canvas_cuadra() -> bool:
	return _canvas != null and _canvas.size.distance_to(_lado) < 2.0


func pasos_zoom() -> int:
	return WIDTHS.size()


func zoom_a(i: int) -> void:
	_wi = clampi(i, 0, WIDTHS.size() - 1)
	_aplicar_zoom()


func _reajustar() -> void:
	await get_tree().process_frame
	reset_size()
	_reposicionar()


func _reposicionar() -> void:
	# anclada abajo-derecha con margen del sistema N (el drag la libera despues)
	await get_tree().process_frame
	if cargar_posicion():
		return
	position = get_viewport_rect().size - size - Vector2(12, 12)


func _process(delta: float) -> void:
	_t += delta
	if _world != null and _world.heroe() != null:
		var p: Vector2 = _world.heroe().position
		_titulo.text = "Sector %s · (%d, %d)" % [_world.map_code(), p.x, p.y]
	_canvas.queue_redraw()


func _a_mapa(world_pos: Vector2) -> Vector2:
	var limites: Vector2 = _world.limites()
	return world_pos / limites * _lado


func _click_canvas(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var limites: Vector2 = _world.limites()
		fly_to.emit(event.position / _lado * limites)


func _dibujar() -> void:
	var s := _lado
	# fondo y borde del canvas (tokens N)
	_canvas.draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.03, 0.055, 0.9))
	# rejilla tenue 5x4
	for i in range(1, 5):
		_canvas.draw_line(Vector2(s.x * i / 5.0, 0), Vector2(s.x * i / 5.0, s.y), NTheme.EDGE_SOFT, 1)
	for i in range(1, 4):
		_canvas.draw_line(Vector2(0, s.y * i / 4.0), Vector2(s.x, s.y * i / 4.0), NTheme.EDGE_SOFT, 1)
	_canvas.draw_rect(Rect2(Vector2.ZERO, s), NTheme.EDGE, false, 1.0)

	if _world == null:
		return

	# mobiliario del mapa primero, para que las entidades queden encima:
	# la estacion (rombo cian) y los portales (rombo violeta con anillo)
	var base := _a_mapa(_world.estacion_pos())
	_rombo(base, 4.0, NTheme.CYAN)
	var dp: Dictionary = AssetDefs.prop("portal").get("minimap", {})
	var rp: float = float(dp.get("radius", 3.0)) + 1.0
	for p in _world.portales().values():
		var c := AssetDefs.color(dp.get("color", "A78BFA"), NTheme.VIOLET)
		if not p.is_working:
			c = NTheme.MUTED
		var pp := _a_mapa(p.position)
		_rombo(pp, rp, c)
		_canvas.draw_arc(pp, 6.0, 0, TAU, 20, Color(c, 0.45), 1.0)

	# cajas: puntos ambar (su color sale del JSON de la caja)
	var dc: Dictionary = AssetDefs.prop("cargo-box").get("minimap", {})
	var cc := AssetDefs.color(dc.get("color", "FFC85C"), NTheme.WARN)
	var rc := float(dc.get("radius", 2.0))
	for caja in _world.cajas().values():
		_canvas.draw_circle(_a_mapa(caja.position), rc, cc)

	# entidades: hostiles con anillo pulsante, jugadores en texto claro
	var heroe: Node2D = _world.heroe()
	for e in _world.entidades().values():
		if e == heroe:
			continue
		var p := _a_mapa(e.position)
		if e.es_npc:
			_canvas.draw_circle(p, 2.0, NTheme.HOSTILE)
			var pulso := 0.3 + 0.25 * sin(_t * 2.4 + e.entity_id)
			_canvas.draw_arc(p, 4.5, 0, TAU, 20, Color(NTheme.HOSTILE, pulso), 1.0)
		else:
			_canvas.draw_circle(p, 2.0, NTheme.TXT)

	# el heroe: cian con anillo respirando, y su autopiloto si esta activo
	if heroe != null:
		var hp := _a_mapa(heroe.position)
		var auto: Vector2 = _world.autopiloto()
		if auto != Vector2.INF:
			var ap := _a_mapa(auto)
			_linea_punteada(hp, ap, Color(NTheme.WARN, 0.9))
			_canvas.draw_line(ap + Vector2(-4, -4), ap + Vector2(4, 4), NTheme.WARN, 1.4)
			_canvas.draw_line(ap + Vector2(4, -4), ap + Vector2(-4, 4), NTheme.WARN, 1.4)
		_canvas.draw_circle(hp, 3.0, NTheme.CYAN)
		_canvas.draw_arc(hp, 5.5 + sin(_t * 3.0) * 1.2, 0, TAU, 24, Color(NTheme.CYAN, 0.5), 1.0)

	# EL ENCUADRE de la camara (§8): las cuatro esquinas del viewport llevadas al
	# plano del juego, dibujando solo el 12.5% de cada lado desde cada esquina —
	# el gesto del original. Con la camara en perspectiva inclinada el encuadre
	# es un TRAPECIO, la firma visual del cliente 3D.
	var mundo: Array[Vector2] = _world.esquinas_encuadre()
	if mundo.size() == 4:
		var esquinas: Array[Vector2] = []
		for m in mundo:
			esquinas.append(_a_mapa(m).clamp(Vector2.ZERO, s))
		var ce := Color(NTheme.TXT, 0.45)
		for i in 4:
			var e := esquinas[i]
			for vecino in [esquinas[(i + 1) % 4], esquinas[(i + 3) % 4]]:
				_canvas.draw_line(e, e + (vecino - e) * 0.125, ce, 1.0)


## Rombo: la forma del mobiliario fijo, para no confundirlo con naves ni cajas.
func _rombo(centro: Vector2, r: float, color: Color) -> void:
	_canvas.draw_colored_polygon(PackedVector2Array([
		centro + Vector2(0, -r), centro + Vector2(r, 0),
		centro + Vector2(0, r), centro + Vector2(-r, 0)]), color)


func _linea_punteada(desde: Vector2, hasta: Vector2, color: Color) -> void:
	var dir := hasta - desde
	var largo := dir.length()
	if largo < 1.0:
		return
	dir /= largo
	var paso := 8.0
	var offset := fmod(_t * 14.0, paso)
	var d := offset
	while d < largo:
		var fin := minf(d + 4.0, largo)
		_canvas.draw_line(desde + dir * d, desde + dir * fin, color, 1.5)
		d += paso
