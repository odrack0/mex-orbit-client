# Comms — pestañas de canal, historial y entrada.
# El chat viaja TIPADO por el mismo socket del juego (el legado tenía un socket
# aparte y una gramática de texto con separadores sin escapar).
#
# El chrome sale de `NWindow`. Antes tenia cabecera propia —titulo, arrastre y
# las pestanias, todo en la misma fila— y de paso migrarlo se corrige algo que
# estaba mal: en el prototipo las PESTANIAS van en el cuerpo (`.fb`), no en la
# cabecera. La cabecera es del chrome; el canal es contenido.
class_name ChatWindow
extends NWindow

signal send_message(channel: int, text: String)

static var CFG: Dictionary = AssetDefs.config("ui").get("chat", {})
static var ICON: String = str(CFG.get("icon", "res://assets/ui/icons/chat.svg"))
static var MAX_LINES: int = int(AssetDefs.num(CFG, "max_lines", 120))
static var WIDTH: int = int(AssetDefs.num(CFG, "width", 400))
static var CONTENT_SEPARATION: int = int(AssetDefs.num(CFG, "content_separation", 5))
static var LOG_HEIGHT: int = int(AssetDefs.num(CFG, "log_height", 110))
static var INPUT_MAX_LENGTH: int = int(AssetDefs.num(CFG, "input_max_length", 256))
static var INPUT_PADDING_X: int = int(AssetDefs.num(CFG, "input_padding_x", 8))
static var INPUT_PADDING_Y: int = int(AssetDefs.num(CFG, "input_padding_y", 5))
static var TAB_FONT_SIZE: int = int(AssetDefs.num(CFG, "tab_font_size", 8))
static var TAB_HEIGHT: int = int(AssetDefs.num(CFG, "tab_height", 20))

var _log: RichTextLabel
var _input_field: LineEdit
var _channel := 0                 # 0 GLOBAL · 1 FACCION
var _tabs: Array[Button] = []


static func create() -> ChatWindow:
	var v := ChatWindow.new()
	v.key = "chat"
	v._build("Comms", ICON)
	v._body()
	return v


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)


func _body() -> void:
	var col := content
	col.add_theme_constant_override("separation", CONTENT_SEPARATION)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", NTheme.SEGMENT_GAP)
	tabs.add_child(_tab("GLOBAL", 0))
	tabs.add_child(_tab("FACCIÓN", 1))
	col.add_child(tabs)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.custom_minimum_size = Vector2(0, LOG_HEIGHT)
	_log.add_theme_font_override("normal_font", NTheme.exo2())
	_log.add_theme_font_size_override("normal_font_size", NTheme.BODY_FONT_SIZE)
	col.add_child(_log)

	_input_field = LineEdit.new()
	_input_field.placeholder_text = "Escribe y pulsa Enter…"
	_input_field.add_theme_font_override("font", NTheme.exo2())
	_input_field.add_theme_font_size_override("font_size", NTheme.BODY_FONT_SIZE)
	_input_field.max_length = INPUT_MAX_LENGTH
	_input_field.add_theme_color_override("font_color", NTheme.TXT)
	_input_field.add_theme_color_override("font_placeholder_color", NTheme.FAINT)
	_input_field.add_theme_color_override("caret_color", NTheme.CYAN)
	var box := StyleBoxFlat.new()
	box.bg_color = NTheme.GLASS_2
	box.border_color = NTheme.EDGE_SOFT
	box.set_border_width_all(NTheme.BORDER_WIDTH)
	box.content_margin_left = INPUT_PADDING_X
	box.content_margin_right = INPUT_PADDING_X
	box.content_margin_top = INPUT_PADDING_Y
	box.content_margin_bottom = INPUT_PADDING_Y
	_input_field.add_theme_stylebox_override("normal", box)
	var focus_box := box.duplicate()
	focus_box.border_color = NTheme.EDGE
	_input_field.add_theme_stylebox_override("focus", focus_box)
	_input_field.text_submitted.connect(_send)
	col.add_child(_input_field)

	_refresh_tabs()
	_place.call_deferred()


func _tab(txt: String, chan: int) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_override("font", NTheme.michroma())
	b.add_theme_font_size_override("font_size", TAB_FONT_SIZE)
	b.custom_minimum_size = Vector2(0, TAB_HEIGHT)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func():
		_channel = chan
		_refresh_tabs()
		_input_field.grab_focus())
	_tabs.append(b)
	return b


## Estilo `.ltab` del prototipo, el mismo que el selector de Ajustes: el canal
## activo en CIAN sobre fondo cian tenue. El ambar no entra aqui — significa
## "esta ventana esta abierta" y no se comparte con nada mas.
func _refresh_tabs() -> void:
	for i in _tabs.size():
		var is_active := i == _channel
		var b: Button = _tabs[i]
		b.add_theme_color_override("font_color", NTheme.CYAN if is_active else NTheme.MUTED)
		b.add_theme_color_override("font_hover_color", NTheme.CYAN)
		var box := StyleBoxFlat.new()
		box.bg_color = Color(NTheme.CYAN,
			NTheme.SEGMENT_ACTIVE_ALPHA if is_active else NTheme.SEGMENT_IDLE_ALPHA)
		box.border_color = NTheme.EDGE if is_active else NTheme.EDGE_SOFT
		box.set_border_width_all(NTheme.BORDER_WIDTH)
		box.content_margin_left = NTheme.SEGMENT_PADDING_X
		box.content_margin_right = NTheme.SEGMENT_PADDING_X
		b.add_theme_stylebox_override("normal", box)
		var hover := box.duplicate()
		hover.bg_color = Color(NTheme.CYAN, NTheme.HOVER_ALPHA)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", hover)


func _place() -> void:
	if load_position():
		return
	await get_tree().process_frame
	position = Vector2(NTheme.SCREEN_MARGIN,
		get_viewport_rect().size.y - size.y - NTheme.SCREEN_MARGIN)


func _send(txt: String) -> void:
	var t := txt.strip_edges()
	_input_field.clear()
	if t.is_empty():
		return
	send_message.emit(_channel, t)


## Un mensaje recibido: [canal] Nombre: texto
func add_message(chan: int, who: String, txt: String) -> void:
	var tag := "Global" if chan == 0 else "Facción"
	var channel_color := NTheme.MUTED if chan == 0 else NTheme.VIOLET
	_log.append_text("[color=#%s][%s][/color] [color=#%s]%s:[/color] %s\n" % [
		channel_color.to_html(false), tag,
		NTheme.WARN.to_html(false), who, txt.replace("[", "[lb]")])
	_crop()


## Aviso del sistema (conexiones, reconexión…).
func add_system(txt: String, color := NTheme.CYAN) -> void:
	_log.append_text("[color=#%s]◆ %s[/color]\n" % [color.to_html(false), txt])
	_crop()


func _crop() -> void:
	while _log.get_paragraph_count() > MAX_LINES:
		_log.remove_paragraph(0)


func is_focused() -> bool:
	return _input_field.has_focus()


func focus_on() -> void:
	_input_field.grab_focus()
