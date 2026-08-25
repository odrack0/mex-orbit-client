# Minimapa — ventana del sistema N (doc canonico §8) con el comportamiento del
# prototipo: zoom por pasos, titulo con coordenadas vivas, clic = autopiloto.
# Dibuja: rejilla tenue, hostiles con anillo pulsante, jugadores, cajas ambar,
# el heroe cian con anillo respirando y la linea punteada del autopiloto con X.
class_name MinimapWindow
extends Control

signal fly_to(world_pos: Vector2)

const WIDTHS := [180, 238, 300, 380, 460]

var _world: Node          # el mundo: entidades, cajas, heroe, limites
var _wi := 2              # indice del paso de zoom
var _titulo: Label
var _canvas: Control
var _t := 0.0


func setup(world: Node, map_code: String) -> void:
	_world = world
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # solo el panel interactua

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", NTheme.glass_panel())
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	panel.add_child(col)

	# header: titulo con coordenadas + zoom - / + (arrastre por el titulo)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 5)
	col.add_child(header)
	_titulo = NTheme.label("Sector %s" % map_code, NTheme.michroma(), 8, NTheme.TXT)
	_titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_titulo.mouse_filter = Control.MOUSE_FILTER_STOP
	_titulo.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_titulo.gui_input.connect(_drag)
	header.add_child(_titulo)
	header.add_child(_zoom_btn("−", -1))
	header.add_child(_zoom_btn("+", 1))

	_canvas = Control.new()
	_canvas.draw.connect(_dibujar)
	_canvas.gui_input.connect(_click_canvas)
	col.add_child(_canvas)
	_aplicar_zoom()
	_reposicionar()


func _zoom_btn(texto: String, delta: int) -> Button:
	var b := Button.new()
	b.text = texto
	b.custom_minimum_size = Vector2(18, 18)
	b.add_theme_font_override("font", NTheme.mono())
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", NTheme.CYAN)
	b.pressed.connect(func():
		_wi = clampi(_wi + delta, 0, WIDTHS.size() - 1)
		_aplicar_zoom())
	return b


func _aplicar_zoom() -> void:
	var w: float = WIDTHS[_wi]
	var limites: Vector2 = _world.limites()
	_canvas.custom_minimum_size = Vector2(w, w * limites.y / limites.x)
	_reposicionar.call_deferred()


func _reposicionar() -> void:
	# anclada abajo-derecha con margen del sistema N (el drag la libera despues)
	await get_tree().process_frame
	var panel: Control = get_child(0)
	panel.position = get_viewport_rect().size - panel.size - Vector2(12, 12)


func _drag(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		var panel: Control = get_child(0)
		panel.position += event.relative


func _process(delta: float) -> void:
	_t += delta
	if _world != null and _world.heroe() != null:
		var p: Vector2 = _world.heroe().position
		_titulo.text = "Sector %s · (%d, %d)" % [_world.map_code(), p.x, p.y]
	_canvas.queue_redraw()


func _a_mapa(world_pos: Vector2) -> Vector2:
	var limites: Vector2 = _world.limites()
	return world_pos / limites * _canvas.size


func _click_canvas(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var limites: Vector2 = _world.limites()
		fly_to.emit(event.position / _canvas.size * limites)


func _dibujar() -> void:
	var s := _canvas.size
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

	# cajas: puntos ambar
	for caja in _world.cajas().values():
		_canvas.draw_circle(_a_mapa(caja.position), 2.0, NTheme.WARN)

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
