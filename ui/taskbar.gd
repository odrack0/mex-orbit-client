# TASKBAR — §5 y el `#taskbar` del prototipo N.
#
# El menú de TODAS las ventanas del juego, arriba a la izquierda. Es la otra
# mitad del §1: "todo es ventana" solo funciona si hay un sitio del que
# reabrirlas, y ese sitio es este. Sin taskbar, cerrar una ventana la pierde.
#
# Medidas del prototipo: cap vertical de 20 px, botones de 44x44, icono de 21,
# separadores de 1 px entre grupos.
#
# La sysbar es su gemela pero NO la misma cosa: aquella son acciones del sistema
# (ajustes, salir), esta son ventanas del juego. Comparten el codigo de color del
# §1.3 y nada mas — por eso son dos clases y no una con un modo.
class_name Taskbar
extends PanelContainer

const SIDE := 44
const ICON := 21
const MARGIN := 8
const HEIGHT_L := 12.0              # esquinas en L, un pelin mas cortas que las de ventana

var _row: HBoxContainer
var _buttons := {}
var _deco: Control


func _ready() -> void:
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	offset_left = MARGIN
	offset_top = MARGIN
	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_END

	var box := StyleBoxFlat.new()
	box.bg_color = NTheme.GLASS_2
	box.border_color = NTheme.EDGE
	box.set_border_width_all(1)
	box.shadow_color = Color(NTheme.CYAN, 0.08)
	box.shadow_size = 24
	add_theme_stylebox_override("panel", box)

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 0)
	add_child(_row)

	# el cap "MENÚ" en vertical, a la IZQUIERDA. En el prototipo va a la derecha
	# porque la barra crece hacia alla; aqui da igual el lado, lo que importa es
	# que la barra se lea como un menu y no como una fila de botones sueltos.
	var cap := Label.new()
	cap.text = "M\nE\nN\nÚ"
	cap.add_theme_font_override("font", NTheme.michroma())
	cap.add_theme_font_size_override("font_size", 7)
	cap.add_theme_color_override("font_color", NTheme.CYAN)
	cap.add_theme_constant_override("line_spacing", 2)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cap.custom_minimum_size = Vector2(20, SIDE)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(cap)

	_deco = Control.new()
	_deco.set_anchors_preset(Control.PRESET_FULL_RECT)
	_deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deco.draw.connect(_paint)
	add_child(_deco)


## `tooltip` es la UNICA cadena localizable: §1.4 prohibe texto fijo en barras de
## iconos, para que un idioma largo no pueda romper el ancho de la barra.
func add_entry(key: String, icon: String, tooltip: String, on_press: Callable) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(SIDE, SIDE)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tooltip
	b.pressed.connect(on_press)

	var glyph := TextureRect.new()
	glyph.texture = load(icon)
	glyph.custom_minimum_size = Vector2(ICON, ICON)
	glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glyph.modulate = Color("A9B6CC")          # el reposo del §5, mas claro que --muted
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(glyph)

	# el punto de "abierta" del §5: 4 px ambar abajo y centrado
	var point := ColorRect.new()
	point.color = NTheme.WARN
	point.visible = false
	point.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# anclas Y offsets, los dos. Poniendo solo `position` sobre unas anclas
	# centradas el punto se iba del boton y acababa pintado sobre la ventana Nave.
	point.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	point.offset_left = -2
	point.offset_right = 2
	point.offset_top = -8
	point.offset_bottom = -4
	b.add_child(point)

	b.mouse_entered.connect(func(): _paint_button(key, true))
	b.mouse_exited.connect(func(): _paint_button(key, false))
	_buttons[key] = {"boton": b, "glifo": glyph, "punto": point, "abierta": false}
	_row.add_child(b)
	_paint_button(key, false)


## Separador vertical entre grupos (§5: estado del piloto · economía · social ·
## información). Con cuatro ventanas todavia no hace falta agrupar, pero la
## barra tiene que saber hacerlo antes de que hagan falta veinte.
func separator() -> void:
	var s := PanelContainer.new()
	s.custom_minimum_size = Vector2(1, SIDE - 18)
	var box := StyleBoxFlat.new()
	box.bg_color = NTheme.EDGE_SOFT
	s.add_theme_stylebox_override("panel", box)
	var wrapper := CenterContainer.new()
	wrapper.custom_minimum_size = Vector2(7, SIDE)
	wrapper.add_child(s)
	_row.add_child(wrapper)


## §1.3: ambar = su ventana esta abierta. Es el MISMO codigo que la sysbar y el
## unico que hay; el cian queda para hover y seleccion.
func mark(key: String, opened: bool) -> void:
	if not _buttons.has(key):
		return
	_buttons[key]["abierta"] = opened
	_buttons[key]["punto"].visible = opened
	_paint_button(key, false)


func is_marked(key: String) -> bool:
	return _buttons.has(key) and _buttons[key]["abierta"]


func _paint_button(key: String, hover: bool) -> void:
	var d: Dictionary = _buttons[key]
	var b: Button = d["boton"]
	var box := StyleBoxFlat.new()
	box.border_width_top = 2
	if d["abierta"]:
		box.bg_color = Color(NTheme.WARN, 0.08)
		box.border_color = NTheme.WARN
		d["glifo"].modulate = NTheme.WARN
	else:
		box.bg_color = Color(NTheme.CYAN, 0.07) if hover else Color(0, 0, 0, 0)
		box.border_color = Color(0, 0, 0, 0)
		d["glifo"].modulate = Color(1, 1, 1) if hover else Color("A9B6CC")
	b.add_theme_stylebox_override("normal", box)
	b.add_theme_stylebox_override("hover", box)
	b.add_theme_stylebox_override("pressed", box)


func _paint() -> void:
	var s := size
	_deco.draw_rect(Rect2(0, 0, HEIGHT_L, 1.5), NTheme.CYAN)
	_deco.draw_rect(Rect2(0, 0, 1.5, HEIGHT_L), NTheme.CYAN)
	_deco.draw_rect(Rect2(s.x - HEIGHT_L, s.y - 1.5, HEIGHT_L, 1.5), NTheme.CYAN)
	_deco.draw_rect(Rect2(s.x - 1.5, s.y - HEIGHT_L, 1.5, HEIGHT_L), NTheme.CYAN)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _deco != null:
		_deco.queue_redraw()
