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

static var CFG: Dictionary = AssetDefs.config("ui").get("taskbar", {})
static var _CAP: Dictionary = CFG.get("cap", {})
static var _DOT: Dictionary = CFG.get("dot", {})
static var _SEPARATOR: Dictionary = CFG.get("separator", {})
static var _BUTTON: Dictionary = CFG.get("button", {})

static var SIDE: int = int(AssetDefs.num(CFG, "side", 44))
static var ICON: int = int(AssetDefs.num(CFG, "icon", 21))
static var MARGIN: int = NTheme.BAR_MARGIN
static var HEIGHT_L: float = AssetDefs.num(CFG, "l_side", 12.0)              # esquinas en L, un pelin mas cortas que las de ventana
static var THICKNESS_L: float = NWindow.THICKNESS_L
static var SHADOW_ALPHA: float = AssetDefs.num(CFG, "shadow_alpha", 0.08)
static var SHADOW_SIZE: int = int(AssetDefs.num(CFG, "shadow_size", 24))
static var CAP_WIDTH: int = int(AssetDefs.num(_CAP, "width", 20))
static var CAP_FONT_SIZE: int = int(AssetDefs.num(_CAP, "font_size", 7))
static var CAP_LINE_SPACING: int = int(AssetDefs.num(_CAP, "line_spacing", 2))
static var GLYPH_REST: Color = AssetDefs.color(CFG.get("glyph_rest"), Color("A9B6CC"))
static var DOT_SIZE: int = int(AssetDefs.num(_DOT, "size", 4))
static var DOT_BOTTOM: int = int(AssetDefs.num(_DOT, "bottom", 4))
static var SEPARATOR_WIDTH: int = int(AssetDefs.num(_SEPARATOR, "width", 1))
static var SEPARATOR_VERTICAL_INSET: int = int(AssetDefs.num(_SEPARATOR, "vertical_inset", 18))
static var SEPARATOR_SLOT_WIDTH: int = int(AssetDefs.num(_SEPARATOR, "slot_width", 7))
static var BUTTON_BORDER_TOP: int = int(AssetDefs.num(_BUTTON, "border_top", 2))
static var BUTTON_OPEN_ALPHA: float = AssetDefs.num(_BUTTON, "open_alpha", 0.08)
static var BUTTON_HOVER_ALPHA: float = AssetDefs.num(_BUTTON, "hover_alpha", 0.07)

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
	box.set_border_width_all(NTheme.BORDER_WIDTH)
	box.shadow_color = Color(NTheme.CYAN, SHADOW_ALPHA)
	box.shadow_size = SHADOW_SIZE
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
	cap.add_theme_font_size_override("font_size", CAP_FONT_SIZE)
	cap.add_theme_color_override("font_color", NTheme.CYAN)
	cap.add_theme_constant_override("line_spacing", CAP_LINE_SPACING)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cap.custom_minimum_size = Vector2(CAP_WIDTH, SIDE)
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
	glyph.modulate = GLYPH_REST          # el reposo del §5, mas claro que --muted
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
	point.offset_left = -DOT_SIZE * 0.5
	point.offset_right = DOT_SIZE * 0.5
	point.offset_top = -(DOT_BOTTOM + DOT_SIZE)
	point.offset_bottom = -DOT_BOTTOM
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
	s.custom_minimum_size = Vector2(SEPARATOR_WIDTH, SIDE - SEPARATOR_VERTICAL_INSET)
	var box := StyleBoxFlat.new()
	box.bg_color = NTheme.EDGE_SOFT
	s.add_theme_stylebox_override("panel", box)
	var wrapper := CenterContainer.new()
	wrapper.custom_minimum_size = Vector2(SEPARATOR_SLOT_WIDTH, SIDE)
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
	box.border_width_top = BUTTON_BORDER_TOP
	if d["abierta"]:
		box.bg_color = Color(NTheme.WARN, BUTTON_OPEN_ALPHA)
		box.border_color = NTheme.WARN
		d["glifo"].modulate = NTheme.WARN
	else:
		box.bg_color = Color(NTheme.CYAN, BUTTON_HOVER_ALPHA) if hover else Color(0, 0, 0, 0)
		box.border_color = Color(0, 0, 0, 0)
		d["glifo"].modulate = Color(1, 1, 1) if hover else GLYPH_REST
	b.add_theme_stylebox_override("normal", box)
	b.add_theme_stylebox_override("hover", box)
	b.add_theme_stylebox_override("pressed", box)


func _paint() -> void:
	var s := size
	_deco.draw_rect(Rect2(0, 0, HEIGHT_L, THICKNESS_L), NTheme.CYAN)
	_deco.draw_rect(Rect2(0, 0, THICKNESS_L, HEIGHT_L), NTheme.CYAN)
	_deco.draw_rect(Rect2(s.x - HEIGHT_L, s.y - THICKNESS_L, HEIGHT_L, THICKNESS_L), NTheme.CYAN)
	_deco.draw_rect(Rect2(s.x - THICKNESS_L, s.y - HEIGHT_L, THICKNESS_L, HEIGHT_L), NTheme.CYAN)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _deco != null:
		_deco.queue_redraw()
