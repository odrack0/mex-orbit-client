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

const ICONO := "res://assets/ui/icons/chat.svg"
const MAX_LINEAS := 120
const ANCHO := 400

var _log: RichTextLabel
var _entrada: LineEdit
var _canal := 0                 # 0 GLOBAL · 1 FACCION
var _tabs: Array[Button] = []


static func crear() -> ChatWindow:
	var v := ChatWindow.new()
	v.clave = "chat"
	v._construir("Comms", ICONO)
	v._cuerpo()
	return v


func _ready() -> void:
	custom_minimum_size = Vector2(ANCHO, 0)


func _cuerpo() -> void:
	var col := contenido
	col.add_theme_constant_override("separation", 5)

	var pestanias := HBoxContainer.new()
	pestanias.add_theme_constant_override("separation", 3)
	pestanias.add_child(_tab("GLOBAL", 0))
	pestanias.add_child(_tab("FACCIÓN", 1))
	col.add_child(pestanias)

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
	_colocar.call_deferred()


func _tab(texto: String, canal: int) -> Button:
	var b := Button.new()
	b.text = texto
	b.add_theme_font_override("font", NTheme.michroma())
	b.add_theme_font_size_override("font_size", 8)
	b.custom_minimum_size = Vector2(0, 20)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func():
		_canal = canal
		_refrescar_tabs()
		_entrada.grab_focus())
	_tabs.append(b)
	return b


## Estilo `.ltab` del prototipo, el mismo que el selector de Ajustes: el canal
## activo en CIAN sobre fondo cian tenue. El ambar no entra aqui — significa
## "esta ventana esta abierta" y no se comparte con nada mas.
func _refrescar_tabs() -> void:
	for i in _tabs.size():
		var activo := i == _canal
		var b: Button = _tabs[i]
		b.add_theme_color_override("font_color", NTheme.CYAN if activo else NTheme.MUTED)
		b.add_theme_color_override("font_hover_color", NTheme.CYAN)
		var caja := StyleBoxFlat.new()
		caja.bg_color = Color(NTheme.CYAN, 0.12 if activo else 0.04)
		caja.border_color = NTheme.EDGE if activo else NTheme.EDGE_SOFT
		caja.set_border_width_all(1)
		caja.content_margin_left = 10
		caja.content_margin_right = 10
		b.add_theme_stylebox_override("normal", caja)
		var hover := caja.duplicate()
		hover.bg_color = Color(NTheme.CYAN, 0.16)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", hover)


func _colocar() -> void:
	if cargar_posicion():
		return
	await get_tree().process_frame
	position = Vector2(12, get_viewport_rect().size.y - size.y - 12)


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
