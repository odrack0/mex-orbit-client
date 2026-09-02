# Chrome de ventana del sistema N (§4 de 03-sistema-diseno-ui.md).
#
# Es el `.fp` del prototipo llevado a Godot, medida por medida: esquinas en L de
# 13 px, cabecera de 26 px con banda cian de 3 px y degradado, chip de icono,
# botones `–` y `×` de 17 px, arrastre por la cabecera y grip diagonal.
#
# Va aparte de las ventanas concretas a proposito. El chat, el minimapa y los
# ajustes traen hoy tres cabeceras distintas hechas a mano, y esa es justo la
# forma de que el sistema se disperse: cada ventana nueva copia la anterior y el
# spec queda solo en el documento. Aqui el spec ESTA EN UN SITIO, y una ventana
# se construye diciendo que icono y que titulo lleva.
#
# Uso:
#     var v := NWindow.nueva("ajustes", "Ajustes", "res://assets/ui/icons/gear.svg")
#     v.contenido.add_child(lo_que_sea)
class_name NWindow
extends PanelContainer

## UN SOLO boton, `–`. El prototipo traia `–` y `×` heredados del escritorio,
## pero aqui hacen exactamente lo mismo: en un juego donde toda ventana se reabre
## desde la taskbar, "cerrar" y "minimizar" no se distinguen en nada — ni en lo
## que pasa al pulsarlos ni en como se vuelve. Dos botones para una accion solo
## obligan al jugador a preguntarse cual es cual.
signal closed

static var WINDOW_CFG: Dictionary = AssetDefs.config("ui").get("window", {})
static var _HEADER: Dictionary = WINDOW_CFG.get("header", {})
static var _GRADIENT: Dictionary = WINDOW_CFG.get("gradient", {})
static var _HEADER_BUTTON: Dictionary = WINDOW_CFG.get("header_button", {})
static var _CHROME_BUTTON: Dictionary = WINDOW_CFG.get("chrome_button", {})
static var _GRIP: Dictionary = WINDOW_CFG.get("grip", {})

static var HEADER_HEIGHT: int = int(AssetDefs.num(WINDOW_CFG, "header_height", 26))
static var SIDE_L: float = AssetDefs.num(WINDOW_CFG, "l_side", 13.0)              # esquinas en L
static var THICKNESS_L: float = AssetDefs.num(WINDOW_CFG, "l_thickness", 1.5)
static var BAND: float = AssetDefs.num(WINDOW_CFG, "band", 3.0)                # franja cian de la cabecera
static var BAND_GLOW_WIDTH: float = AssetDefs.num(WINDOW_CFG, "band_glow_width", 3.0)
static var BAND_GLOW_ALPHA: float = AssetDefs.num(WINDOW_CFG, "band_glow_alpha", 0.18)
static var STATE_PATH: String = str(WINDOW_CFG.get("state_path", "user://ui_state.cfg"))
static var SHADOW_ALPHA: float = AssetDefs.num(WINDOW_CFG, "shadow_alpha", 0.06)
static var SHADOW_SIZE: int = int(AssetDefs.num(WINDOW_CFG, "shadow_size", 26))

static var HEADER_PAD_LEFT: int = int(AssetDefs.num(_HEADER, "padding_left", 10))
static var HEADER_PAD_RIGHT: int = int(AssetDefs.num(_HEADER, "padding_right", 6))
static var HEADER_SEPARATION: int = int(AssetDefs.num(_HEADER, "separation", 8))
static var CHIP_SIZE: int = int(AssetDefs.num(_HEADER, "chip_size", 14))
static var TITLE_FONT_SIZE: int = int(AssetDefs.num(_HEADER, "title_font_size", 9))
static var TITLE_TRACKING: int = int(AssetDefs.num(_HEADER, "title_tracking", 1))

static var GRADIENT_CYAN_ALPHA: float = AssetDefs.num(_GRADIENT, "cyan_alpha", 0.12)
static var GRADIENT_VIOLET_ALPHA: float = AssetDefs.num(_GRADIENT, "violet_alpha", 0.05)
static var GRADIENT_SPLIT: float = AssetDefs.num(_GRADIENT, "split", 0.55)

static var HEADER_BUTTON_SIZE: int = int(AssetDefs.num(_HEADER_BUTTON, "size", 15))
static var HEADER_BUTTON_FONT_SIZE: int = int(AssetDefs.num(_HEADER_BUTTON, "font_size", 10))
static var HEADER_BUTTON_REST_ALPHA: float = AssetDefs.num(_HEADER_BUTTON, "rest_alpha", 0.06)
static var CHROME_BUTTON_SIZE: int = int(AssetDefs.num(_CHROME_BUTTON, "size", 17))
static var CHROME_BUTTON_FONT_SIZE: int = int(AssetDefs.num(_CHROME_BUTTON, "font_size", 10))

static var GRIP_LINES: int = int(AssetDefs.num(_GRIP, "lines", 3))
static var GRIP_START: float = AssetDefs.num(_GRIP, "start", 3.0)
static var GRIP_STEP: float = AssetDefs.num(_GRIP, "step", 3.5)
static var GRIP_ALPHA: float = AssetDefs.num(_GRIP, "alpha", 0.55)
static var GRIP_INSET: float = AssetDefs.num(_GRIP, "inset", 1)

var content: VBoxContainer      # donde cuelga lo que trae cada ventana
var key := ""                   # para persistir la posicion

var _deco: Control
var _header: PanelContainer
var _header_row: HBoxContainer
var _title_label: Label
var _dragging := false


static func updated(key_: String, title_text: String, icon: String) -> NWindow:
	var v := NWindow.new()
	v.key = key_
	v._build(title_text, icon)
	return v


func _build(title_text: String, icon: String) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = NTheme.GLASS
	box.border_color = NTheme.EDGE_SOFT
	box.set_border_width_all(NTheme.BORDER_WIDTH)
	# la sombra del §4: 0 0 26px rgba(0,229,255,.06) — el halo cian que separa la
	# ventana del espacio sin dibujarle un marco mas
	box.shadow_color = Color(NTheme.CYAN, SHADOW_ALPHA)
	box.shadow_size = SHADOW_SIZE
	add_theme_stylebox_override("panel", box)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	add_child(col)
	col.add_child(_build_header(title_text, icon))

	# .fb del prototipo: padding 8px 10px 10px
	var body_box := MarginContainer.new()
	body_box.add_theme_constant_override("margin_left", NTheme.PANEL_PAD_LEFT)
	body_box.add_theme_constant_override("margin_right", NTheme.PANEL_PAD_RIGHT)
	body_box.add_theme_constant_override("margin_top", NTheme.PANEL_PAD_TOP)
	body_box.add_theme_constant_override("margin_bottom", NTheme.PANEL_PAD_BOTTOM)
	col.add_child(body_box)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", NTheme.STACK_GAP)
	body_box.add_child(content)

	# la decoracion va ENCIMA de todo y no come clicks: son adornos, no controles
	_deco = Control.new()
	_deco.set_anchors_preset(Control.PRESET_FULL_RECT)
	_deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deco.draw.connect(_paint_deco)
	add_child(_deco)


func _build_header(title_text: String, icon: String) -> Control:
	_header = PanelContainer.new()
	_header.custom_minimum_size = Vector2(0, HEADER_HEIGHT)
	var backdrop := StyleBoxFlat.new()
	backdrop.bg_color = Color(0, 0, 0, 0)
	backdrop.border_color = NTheme.EDGE_SOFT
	backdrop.border_width_bottom = NTheme.BORDER_WIDTH
	backdrop.content_margin_left = HEADER_PAD_LEFT
	backdrop.content_margin_right = HEADER_PAD_RIGHT
	_header.add_theme_stylebox_override("panel", backdrop)
	_header.mouse_filter = Control.MOUSE_FILTER_STOP
	_header.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_header.gui_input.connect(_drag)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", HEADER_SEPARATION)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_header.add_child(row)

	var chip := TextureRect.new()
	chip.texture = load(icon)
	chip.custom_minimum_size = Vector2(CHIP_SIZE, CHIP_SIZE)
	chip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chip.modulate = NTheme.CYAN
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(chip)

	# Michroma 9px con .16em de tracking (~1,4 px a ese cuerpo)
	var t := NTheme.label(title_text.to_upper(), NTheme.michroma_track(TITLE_TRACKING),
		TITLE_FONT_SIZE, NTheme.TXT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label = t
	row.add_child(t)

	_header_row = row
	row.add_child(_chrome_button("–"))
	return _header


## Boton extra en la cabecera, a la izquierda de `–` y `×` — el `.zbtn` del
## prototipo. Lo pide el minimapa para sus pasos de zoom: el §8 los quiere ahi
## arriba y no dentro del cuerpo, porque no son contenido sino control de la
## ventana.
func header_button(glyph: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = glyph
	b.custom_minimum_size = Vector2(HEADER_BUTTON_SIZE, HEADER_BUTTON_SIZE)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", NTheme.mono())
	b.add_theme_font_size_override("font_size", HEADER_BUTTON_FONT_SIZE)
	b.add_theme_color_override("font_color", NTheme.CYAN)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(NTheme.CYAN, HEADER_BUTTON_REST_ALPHA)
	box.border_color = NTheme.EDGE_SOFT
	box.set_border_width_all(NTheme.BORDER_WIDTH)
	b.add_theme_stylebox_override("normal", box)
	var hover := box.duplicate()
	hover.bg_color = Color(NTheme.CYAN, NTheme.HOVER_ALPHA)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(on_press)
	_header_row.add_child(b)
	_header_row.move_child(b, _header_row.get_child_count() - 2)
	return b


## El titulo, para las ventanas que lo actualizan en vivo — el minimapa le cuelga
## las coordenadas del heroe (§8).
func title_label() -> Label:
	return _title_label


func _chrome_button(glyph: String) -> Button:
	var b := Button.new()
	b.text = glyph
	b.custom_minimum_size = Vector2(CHROME_BUTTON_SIZE, CHROME_BUTTON_SIZE)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", NTheme.mono())
	b.add_theme_font_size_override("font_size", CHROME_BUTTON_FONT_SIZE)
	b.add_theme_color_override("font_color", NTheme.MUTED)
	b.add_theme_color_override("font_hover_color", NTheme.CYAN)
	var rest := StyleBoxFlat.new()
	rest.bg_color = Color(0, 0, 0, 0)
	rest.border_color = NTheme.EDGE_SOFT
	rest.set_border_width_all(NTheme.BORDER_WIDTH)
	b.add_theme_stylebox_override("normal", rest)
	var hover := rest.duplicate()
	hover.border_color = NTheme.EDGE
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(func():
		hide()
		closed.emit())
	return b


## Esquinas en L, banda de la cabecera y grip. Todo esto es `::before`/`::after`
## en el prototipo; en Godot es una capa que se pinta y ya.
func _paint_deco() -> void:
	var s := size
	# Degradado de la cabecera: cian .12 -> violeta .05 al 55% -> transparente.
	# Con `draw_polygon` y un color por vertice, que interpola solo. La primera
	# version usaba un GradientTexture2D y salia una BANDA BLANCA OPACA que tapaba
	# el titulo y los botones: el degradado no llegaba a la textura y quedaba el
	# negro->blanco por defecto. Dos triangulos con color por vertice no tienen
	# ese intermediario que puede fallar en silencio.
	var split := s.x * GRADIENT_SPLIT
	var violet := Color(NTheme.VIOLET, GRADIENT_VIOLET_ALPHA)
	_stripe(0.0, split, Color(NTheme.CYAN, GRADIENT_CYAN_ALPHA), violet)
	_stripe(split, s.x, violet, Color(NTheme.CYAN, 0.0))
	# franja cian de 3 px a la izquierda de la cabecera, con su glow
	_deco.draw_rect(Rect2(0, 0, BAND, HEADER_HEIGHT), NTheme.CYAN)
	_deco.draw_rect(Rect2(BAND, 0, BAND_GLOW_WIDTH, HEADER_HEIGHT), Color(NTheme.CYAN, BAND_GLOW_ALPHA))
	# esquinas en L: superior izquierda e inferior derecha
	_deco.draw_rect(Rect2(0, 0, SIDE_L, THICKNESS_L), NTheme.CYAN)
	_deco.draw_rect(Rect2(0, 0, THICKNESS_L, SIDE_L), NTheme.CYAN)
	_deco.draw_rect(Rect2(s.x - SIDE_L, s.y - THICKNESS_L, SIDE_L, THICKNESS_L), NTheme.CYAN)
	_deco.draw_rect(Rect2(s.x - THICKNESS_L, s.y - SIDE_L, THICKNESS_L, SIDE_L), NTheme.CYAN)
	# grip: rayas a 135 grados en el triangulo inferior derecho
	var edge := Vector2(s.x - GRIP_INSET, s.y - GRIP_INSET)
	for i in GRIP_LINES:
		var d := GRIP_START + i * GRIP_STEP
		_deco.draw_line(Vector2(edge.x - d, edge.y), Vector2(edge.x, edge.y - d),
			Color(NTheme.EDGE, GRIP_ALPHA), NTheme.HAIRLINE)


func _stripe(x0: float, x1: float, lft: Color, rgt: Color) -> void:
	if x1 <= x0:
		return
	_deco.draw_polygon(
		PackedVector2Array([Vector2(x0, 0), Vector2(x1, 0),
			Vector2(x1, HEADER_HEIGHT), Vector2(x0, HEADER_HEIGHT)]),
		PackedColorArray([lft, rgt, rgt, lft]))


func _drag(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if not event.pressed:
			_save_position()
	elif event is InputEventMouseMotion and _dragging:
		position = _inside(position + event.relative)


## §1.6: la posicion se clampa al viewport. Sin esto una ventana arrastrada al
## borde se pierde y no hay forma de recuperarla salvo borrar el .cfg.
func _inside(p: Vector2) -> Vector2:
	var v := get_viewport_rect().size
	return Vector2(clampf(p.x, 0.0, maxf(v.x - size.x, 0.0)),
		clampf(p.y, 0.0, maxf(v.y - size.y, 0.0)))


func _save_position() -> void:
	if key == "":
		return
	var cfg := ConfigFile.new()
	cfg.load(STATE_PATH)
	cfg.set_value(str(Session.account_id), key, position)
	cfg.save(STATE_PATH)


## Devuelve true si habia posicion guardada. Quien llama decide donde va si no.
func load_position() -> bool:
	if key == "":
		return false
	var cfg := ConfigFile.new()
	if cfg.load(STATE_PATH) != OK:
		return false
	# `get_value` con null por defecto no devuelve null: ERRORA si la clave no
	# existe. Hay que preguntar antes.
	if not cfg.has_section_key(str(Session.account_id), key):
		return false
	var saved: Variant = cfg.get_value(str(Session.account_id), key)
	position = _inside(saved)
	return true


func center_on() -> void:
	await get_tree().process_frame
	position = _inside((get_viewport_rect().size - size) * 0.5)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _deco != null:
		_deco.queue_redraw()
