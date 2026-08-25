# Comms — ventana del sistema N: pestañas de canal, historial y entrada.
# El chat viaja TIPADO por el mismo socket del juego (el legado tenía un socket
# aparte y una gramática de texto con separadores sin escapar).
class_name ChatWindow
extends Control

signal send_message(channel: int, text: String)

const MAX_LINEAS := 120

var _panel: PanelContainer
var _log: RichTextLabel
var _entrada: LineEdit
var _canal := 0                 # 0 GLOBAL · 1 FACCION
var _tabs: Array[Button] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", NTheme.glass_panel())
	_panel.custom_minimum_size = Vector2(400, 0)
	add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	_panel.add_child(col)

	var cabecera := HBoxContainer.new()
	cabecera.add_theme_constant_override("separation", 4)
	col.add_child(cabecera)
	var titulo := NTheme.label("COMMS", NTheme.michroma(), 8, NTheme.CYAN)
	titulo.mouse_filter = Control.MOUSE_FILTER_STOP
	titulo.mouse_default_cursor_shape = Control.CURSOR_MOVE
	titulo.gui_input.connect(_drag)
	titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cabecera.add_child(titulo)
	cabecera.add_child(_tab("GLOBAL", 0))
	cabecera.add_child(_tab("FACCIÓN", 1))

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.custom_minimum_size = Vector2(0, 110)
	_log.add_theme_font_override("normal_font", NTheme.exo2())
	_log.add_theme_font_size_override("normal_font_size", 12)
	col.add_child(_log)

	_entrada = LineEdit.new()
	_entrada.placeholder_text = "Escribe y pulsa Enter…"
	_entrada.add_theme_font_override("font", NTheme.exo2())
	_entrada.add_theme_font_size_override("font_size", 12)
	_entrada.max_length = 256
	_entrada.add_theme_color_override("font_color", NTheme.TXT)
	_entrada.add_theme_color_override("font_placeholder_color", NTheme.FAINT)
	_entrada.add_theme_color_override("caret_color", NTheme.CYAN)
	var caja := StyleBoxFlat.new()
	caja.bg_color = NTheme.GLASS_2
	caja.border_color = NTheme.EDGE_SOFT
	caja.set_border_width_all(1)
	caja.content_margin_left = 8
	caja.content_margin_right = 8
	caja.content_margin_top = 5
	caja.content_margin_bottom = 5
	_entrada.add_theme_stylebox_override("normal", caja)
	var caja_foco := caja.duplicate()
	caja_foco.border_color = NTheme.EDGE
	_entrada.add_theme_stylebox_override("focus", caja_foco)
	_entrada.text_submitted.connect(_enviar)
	col.add_child(_entrada)

	_refrescar_tabs()
	_reposicionar.call_deferred()


func _tab(texto: String, canal: int) -> Button:
	var b := Button.new()
	b.text = texto
	b.add_theme_font_override("font", NTheme.michroma())
	b.add_theme_font_size_override("font_size", 8)
	b.custom_minimum_size = Vector2(78, 20)
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func():
		_canal = canal
		_refrescar_tabs()
		_entrada.grab_focus())
	_tabs.append(b)
	return b


func _refrescar_tabs() -> void:
	for i in _tabs.size():
		_tabs[i].add_theme_color_override("font_color",
			NTheme.CYAN if i == _canal else NTheme.MUTED)


func _drag(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_panel.position += event.relative


func _reposicionar() -> void:
	await get_tree().process_frame
	_panel.position = Vector2(12, get_viewport_rect().size.y - _panel.size.y - 12)


func _enviar(texto: String) -> void:
	var t := texto.strip_edges()
	_entrada.clear()
	if t.is_empty():
		return
	send_message.emit(_canal, t)


## Un mensaje recibido: [canal] Nombre: texto
func add_message(canal: int, quien: String, texto: String) -> void:
	var etiqueta := "Global" if canal == 0 else "Facción"
	var color_canal := NTheme.MUTED if canal == 0 else NTheme.VIOLET
	_log.append_text("[color=#%s][%s][/color] [color=#%s]%s:[/color] %s\n" % [
		color_canal.to_html(false), etiqueta,
		NTheme.WARN.to_html(false), quien, texto.replace("[", "[lb]")])
	_recortar()


## Aviso del sistema (conexiones, reconexión…).
func add_system(texto: String, color := NTheme.CYAN) -> void:
	_log.append_text("[color=#%s]◆ %s[/color]\n" % [color.to_html(false), texto])
	_recortar()


func _recortar() -> void:
	while _log.get_paragraph_count() > MAX_LINEAS:
		_log.remove_paragraph(0)


func tiene_foco() -> bool:
	return _entrada.has_focus()


func enfocar() -> void:
	_entrada.grab_focus()
