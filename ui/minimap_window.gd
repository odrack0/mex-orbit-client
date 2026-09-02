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

const ICON := "res://assets/ui/icons/map.svg"
const WIDTHS := [180, 238, 300, 380, 460]

var _world: Node          # el mundo: entidades, cajas, heroe, limites
var _wi := 2              # indice del paso de zoom
var _canvas: Control
var _side := Vector2.ZERO      # el tamanio REAL del mapa dibujado, sin deformar
var _t := 0.0


func setup(world: Node, map_code: String) -> void:
	_world = world
	key = "minimapa"
	_build("Sector %s" % map_code, ICON)
	_title_label = title_label()
	header_button("−", func(): _zoom(-1))
	header_button("+", func(): _zoom(1))

	_canvas = Control.new()
	_canvas.draw.connect(_redraw)
	_canvas.gui_input.connect(_canvas_click)
	# SHRINK: sin esto el contenedor lo estira al ancho de la ventana y el mapa se
	# dibuja con un ancho y un alto que no se corresponden — deformado, que es
	# justo lo que el §8 prohibe
	_canvas.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(_canvas)
	_apply_zoom()
	_reposition()


## Al saltar de sector el minimapa NO se rehace: solo cambia de nombre. Volver a
## llamar a `setup` le montaba un segundo chrome y un segundo lienzo encima del
## primero, y el lienzo viejo seguia intentando dibujarse fuera de su `_draw`.
func rename_to(map_code: String) -> void:
	if _title_label != null:
		_title_label.text = "SECTOR %s" % map_code


func _zoom(delta: int) -> void:
	_wi = clampi(_wi + delta, 0, WIDTHS.size() - 1)
	_apply_zoom()


## §8: el alto sale del ancho y del ratio del mapa. NUNCA se deforma.
##
## El zoom cambiaba solo el canvas, y una ventana en Godot **no encoge sola**
## cuando su contenido encoge: el aro se quedaba con el ancho anterior, el
## contenedor estiraba el canvas para llenarlo y el mapa acababa con el ancho
## viejo y el alto nuevo. En la captura del bug medía 640x260 —ratio 2,46—
## cuando el mapa es 20800x12800 —ratio 1,625—. Hay que pedirle a la ventana que
## se reajuste, y ahi los dos escalan juntos.
func _apply_zoom() -> void:
	var w: float = WIDTHS[_wi]
	var bounds: Vector2 = _world.bounds()
	_side = Vector2(w, w * bounds.y / bounds.x)
	_canvas.custom_minimum_size = _side
	_readjust.call_deferred()


## Para que el autotest pueda AFIRMAR el §8. La deformacion no se veia en las
## capturas —un mapa estirado sigue pareciendo un mapa— y por eso llego hasta el
## usuario: hace falta comparar el ratio con un numero, no mirarlo.
func deformation() -> float:
	if _side.y <= 0.0:
		return 999.0
	var bounds: Vector2 = _world.bounds()
	return absf(_side.x / _side.y - bounds.x / bounds.y)


## Y que el canvas mida de verdad lo que dice medir: si el contenedor lo estira,
## el dibujo y los clicks dejan de coincidir con lo que se ve.
func canvas_fits() -> bool:
	return _canvas != null and _canvas.size.distance_to(_side) < 2.0


func zoom_steps() -> int:
	return WIDTHS.size()


func zoom_to(i: int) -> void:
	_wi = clampi(i, 0, WIDTHS.size() - 1)
	_apply_zoom()


func _readjust() -> void:
	await get_tree().process_frame
	reset_size()
	_reposition()


func _reposition() -> void:
	# anclada abajo-derecha con margen del sistema N (el drag la libera despues)
	await get_tree().process_frame
	if load_position():
		return
	position = get_viewport_rect().size - size - Vector2(12, 12)


func _process(delta: float) -> void:
	_t += delta
	if _world != null and _world.hero() != null:
		var p: Vector2 = _world.hero().position
		_title_label.text = "Sector %s · (%d, %d)" % [_world.map_code(), p.x, p.y]
	_canvas.queue_redraw()


func _to_map(world_pos: Vector2) -> Vector2:
	var bounds: Vector2 = _world.bounds()
	return world_pos / bounds * _side


func _canvas_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var bounds: Vector2 = _world.bounds()
		fly_to.emit(event.position / _side * bounds)


func _redraw() -> void:
	var s := _side
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
	var base := _to_map(_world.station_pos())
	_diamond(base, 4.0, NTheme.CYAN)
	var dp: Dictionary = AssetDefs.prop("portal").get("minimap", {})
	var rp: float = float(dp.get("radius", 3.0)) + 1.0
	for p in _world.portal_list().values():
		var c := AssetDefs.color(dp.get("color", "A78BFA"), NTheme.VIOLET)
		if not p.is_working:
			c = NTheme.MUTED
		var pp := _to_map(p.position)
		_diamond(pp, rp, c)
		_canvas.draw_arc(pp, 6.0, 0, TAU, 20, Color(c, 0.45), 1.0)

	# cajas: puntos ambar (su color sale del JSON de la caja)
	var dc: Dictionary = AssetDefs.prop("cargo-box").get("minimap", {})
	var cc := AssetDefs.color(dc.get("color", "FFC85C"), NTheme.WARN)
	var rc := float(dc.get("radius", 2.0))
	for box in _world.boxes().values():
		_canvas.draw_circle(_to_map(box.position), rc, cc)

	# entidades: hostiles con anillo pulsante, jugadores en texto claro
	var hero: Node2D = _world.hero()
	for e in _world.entities().values():
		if e == hero:
			continue
		var p := _to_map(e.position)
		if e.is_npc:
			_canvas.draw_circle(p, 2.0, NTheme.HOSTILE)
			var pulse := 0.3 + 0.25 * sin(_t * 2.4 + e.entity_id)
			_canvas.draw_arc(p, 4.5, 0, TAU, 20, Color(NTheme.HOSTILE, pulse), 1.0)
		else:
			_canvas.draw_circle(p, 2.0, NTheme.TXT)

	# el heroe: cian con anillo respirando, y su autopiloto si esta activo
	if hero != null:
		var hp := _to_map(hero.position)
		var auto: Vector2 = _world.autopilot_on()
		if auto != Vector2.INF:
			var ap := _to_map(auto)
			_dotted_line(hp, ap, Color(NTheme.WARN, 0.9))
			_canvas.draw_line(ap + Vector2(-4, -4), ap + Vector2(4, 4), NTheme.WARN, 1.4)
			_canvas.draw_line(ap + Vector2(4, -4), ap + Vector2(-4, 4), NTheme.WARN, 1.4)
		_canvas.draw_circle(hp, 3.0, NTheme.CYAN)
		_canvas.draw_arc(hp, 5.5 + sin(_t * 3.0) * 1.2, 0, TAU, 24, Color(NTheme.CYAN, 0.5), 1.0)

	# EL ENCUADRE de la camara (§8): las cuatro esquinas del viewport llevadas al
	# plano del juego, dibujando solo el 12.5% de cada lado desde cada esquina —
	# el gesto del original. Con la camara en perspectiva inclinada el encuadre
	# es un TRAPECIO, la firma visual del cliente 3D.
	var stage: Array[Vector2] = _world.framing_corners()
	if stage.size() == 4:
		var corners: Array[Vector2] = []
		for m in stage:
			corners.append(_to_map(m).clamp(Vector2.ZERO, s))
		var ce := Color(NTheme.TXT, 0.45)
		for i in 4:
			var e := corners[i]
			for neighbor in [corners[(i + 1) % 4], corners[(i + 3) % 4]]:
				_canvas.draw_line(e, e + (neighbor - e) * 0.125, ce, 1.0)


## Rombo: la forma del mobiliario fijo, para no confundirlo con naves ni cajas.
func _diamond(center: Vector2, r: float, color: Color) -> void:
	_canvas.draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -r), center + Vector2(r, 0),
		center + Vector2(0, r), center + Vector2(-r, 0)]), color)


func _dotted_line(start_at: Vector2, until: Vector2, color: Color) -> void:
	var dir := until - start_at
	var span_len := dir.length()
	if span_len < 1.0:
		return
	dir /= span_len
	var step := 8.0
	var offset := fmod(_t * 14.0, step)
	var d := offset
	while d < span_len:
		var end_at := minf(d + 4.0, span_len)
		_canvas.draw_line(start_at + dir * d, start_at + dir * end_at, color, 1.5)
		d += step
