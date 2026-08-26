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

## `–` y `×` hacen hoy lo mismo: ocultar. Se mantienen los dos porque el
## prototipo los tiene y porque el dia que una ventana guarde estado que valga la
## pena conservar (una pestania abierta, un scroll), minimizar dejara de ser
## cerrar sin tocar el chrome.
signal cerrada

const ALTO_CABECERA := 26
const LADO_L := 13.0              # esquinas en L
const GROSOR_L := 1.5
const BANDA := 3.0                # franja cian de la cabecera
const RUTA_ESTADO := "user://ui_state.cfg"

var contenido: VBoxContainer      # donde cuelga lo que trae cada ventana
var clave := ""                   # para persistir la posicion

var _deco: Control
var _cabecera: PanelContainer
var _fila_cabecera: HBoxContainer
var _titulo: Label
var _arrastrando := false


static func nueva(clave_: String, titulo: String, icono: String) -> NWindow:
	var v := NWindow.new()
	v.clave = clave_
	v._construir(titulo, icono)
	return v


func _construir(titulo: String, icono: String) -> void:
	var caja := StyleBoxFlat.new()
	caja.bg_color = NTheme.GLASS
	caja.border_color = NTheme.EDGE_SOFT
	caja.set_border_width_all(1)
	# la sombra del §4: 0 0 26px rgba(0,229,255,.06) — el halo cian que separa la
	# ventana del espacio sin dibujarle un marco mas
	caja.shadow_color = Color(NTheme.CYAN, 0.06)
	caja.shadow_size = 26
	add_theme_stylebox_override("panel", caja)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	add_child(col)
	col.add_child(_construir_cabecera(titulo, icono))

	# .fb del prototipo: padding 8px 10px 10px
	var cuerpo := MarginContainer.new()
	cuerpo.add_theme_constant_override("margin_left", 10)
	cuerpo.add_theme_constant_override("margin_right", 10)
	cuerpo.add_theme_constant_override("margin_top", 8)
	cuerpo.add_theme_constant_override("margin_bottom", 10)
	col.add_child(cuerpo)
	contenido = VBoxContainer.new()
	contenido.add_theme_constant_override("separation", 6)
	cuerpo.add_child(contenido)

	# la decoracion va ENCIMA de todo y no come clicks: son adornos, no controles
	_deco = Control.new()
	_deco.set_anchors_preset(Control.PRESET_FULL_RECT)
	_deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deco.draw.connect(_pintar_deco)
	add_child(_deco)


func _construir_cabecera(titulo: String, icono: String) -> Control:
	_cabecera = PanelContainer.new()
	_cabecera.custom_minimum_size = Vector2(0, ALTO_CABECERA)
	var fondo := StyleBoxFlat.new()
	fondo.bg_color = Color(0, 0, 0, 0)
	fondo.border_color = NTheme.EDGE_SOFT
	fondo.border_width_bottom = 1
	fondo.content_margin_left = 10
	fondo.content_margin_right = 6
	_cabecera.add_theme_stylebox_override("panel", fondo)
	_cabecera.mouse_filter = Control.MOUSE_FILTER_STOP
	_cabecera.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_cabecera.gui_input.connect(_arrastre)

	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 8)
	fila.alignment = BoxContainer.ALIGNMENT_CENTER
	_cabecera.add_child(fila)

	var chip := TextureRect.new()
	chip.texture = load(icono)
	chip.custom_minimum_size = Vector2(14, 14)
	chip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chip.modulate = NTheme.CYAN
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fila.add_child(chip)

	# Michroma 9px con .16em de tracking (~1,4 px a ese cuerpo)
	var t := NTheme.label(titulo.to_upper(), NTheme.michroma_track(1), 9, NTheme.TXT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_titulo = t
	fila.add_child(t)

	_fila_cabecera = fila
	fila.add_child(_boton_chrome("–"))
	fila.add_child(_boton_chrome("×"))
	return _cabecera


## Boton extra en la cabecera, a la izquierda de `–` y `×` — el `.zbtn` del
## prototipo. Lo pide el minimapa para sus pasos de zoom: el §8 los quiere ahi
## arriba y no dentro del cuerpo, porque no son contenido sino control de la
## ventana.
func boton_cabecera(glifo: String, al_pulsar: Callable) -> Button:
	var b := Button.new()
	b.text = glifo
	b.custom_minimum_size = Vector2(15, 15)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", NTheme.mono())
	b.add_theme_font_size_override("font_size", 10)
	b.add_theme_color_override("font_color", NTheme.CYAN)
	var caja := StyleBoxFlat.new()
	caja.bg_color = Color(NTheme.CYAN, 0.06)
	caja.border_color = NTheme.EDGE_SOFT
	caja.set_border_width_all(1)
	b.add_theme_stylebox_override("normal", caja)
	var hover := caja.duplicate()
	hover.bg_color = Color(NTheme.CYAN, 0.16)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(al_pulsar)
	_fila_cabecera.add_child(b)
	_fila_cabecera.move_child(b, _fila_cabecera.get_child_count() - 3)
	return b


## El titulo, para las ventanas que lo actualizan en vivo — el minimapa le cuelga
## las coordenadas del heroe (§8).
func titulo_label() -> Label:
	return _titulo


func _boton_chrome(glifo: String) -> Button:
	var b := Button.new()
	b.text = glifo
	b.custom_minimum_size = Vector2(17, 17)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", NTheme.mono())
	b.add_theme_font_size_override("font_size", 10)
	b.add_theme_color_override("font_color", NTheme.MUTED)
	b.add_theme_color_override("font_hover_color", NTheme.CYAN)
	var reposo := StyleBoxFlat.new()
	reposo.bg_color = Color(0, 0, 0, 0)
	reposo.border_color = NTheme.EDGE_SOFT
	reposo.set_border_width_all(1)
	b.add_theme_stylebox_override("normal", reposo)
	var hover := reposo.duplicate()
	hover.border_color = NTheme.EDGE
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(func():
		hide()
		cerrada.emit())
	return b


## Esquinas en L, banda de la cabecera y grip. Todo esto es `::before`/`::after`
## en el prototipo; en Godot es una capa que se pinta y ya.
func _pintar_deco() -> void:
	var s := size
	# Degradado de la cabecera: cian .12 -> violeta .05 al 55% -> transparente.
	# Con `draw_polygon` y un color por vertice, que interpola solo. La primera
	# version usaba un GradientTexture2D y salia una BANDA BLANCA OPACA que tapaba
	# el titulo y los botones: el degradado no llegaba a la textura y quedaba el
	# negro->blanco por defecto. Dos triangulos con color por vertice no tienen
	# ese intermediario que puede fallar en silencio.
	_franja(0.0, s.x * 0.55, Color(NTheme.CYAN, 0.12), Color(NTheme.VIOLET, 0.05))
	_franja(s.x * 0.55, s.x, Color(NTheme.VIOLET, 0.05), Color(NTheme.CYAN, 0.0))
	# franja cian de 3 px a la izquierda de la cabecera, con su glow
	_deco.draw_rect(Rect2(0, 0, BANDA, ALTO_CABECERA), NTheme.CYAN)
	_deco.draw_rect(Rect2(BANDA, 0, 3.0, ALTO_CABECERA), Color(NTheme.CYAN, 0.18))
	# esquinas en L: superior izquierda e inferior derecha
	_deco.draw_rect(Rect2(0, 0, LADO_L, GROSOR_L), NTheme.CYAN)
	_deco.draw_rect(Rect2(0, 0, GROSOR_L, LADO_L), NTheme.CYAN)
	_deco.draw_rect(Rect2(s.x - LADO_L, s.y - GROSOR_L, LADO_L, GROSOR_L), NTheme.CYAN)
	_deco.draw_rect(Rect2(s.x - GROSOR_L, s.y - LADO_L, GROSOR_L, LADO_L), NTheme.CYAN)
	# grip: rayas a 135 grados en el triangulo inferior derecho
	for i in 3:
		var d := 3.0 + i * 3.5
		_deco.draw_line(Vector2(s.x - 1 - d, s.y - 1), Vector2(s.x - 1, s.y - 1 - d),
			Color(NTheme.EDGE, 0.55), 1.0)


func _franja(x0: float, x1: float, izq: Color, der: Color) -> void:
	if x1 <= x0:
		return
	_deco.draw_polygon(
		PackedVector2Array([Vector2(x0, 0), Vector2(x1, 0),
			Vector2(x1, ALTO_CABECERA), Vector2(x0, ALTO_CABECERA)]),
		PackedColorArray([izq, der, der, izq]))


func _arrastre(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_arrastrando = event.pressed
		if not event.pressed:
			_guardar_posicion()
	elif event is InputEventMouseMotion and _arrastrando:
		position = _dentro(position + event.relative)


## §1.6: la posicion se clampa al viewport. Sin esto una ventana arrastrada al
## borde se pierde y no hay forma de recuperarla salvo borrar el .cfg.
func _dentro(p: Vector2) -> Vector2:
	var v := get_viewport_rect().size
	return Vector2(clampf(p.x, 0.0, maxf(v.x - size.x, 0.0)),
		clampf(p.y, 0.0, maxf(v.y - size.y, 0.0)))


func _guardar_posicion() -> void:
	if clave == "":
		return
	var cfg := ConfigFile.new()
	cfg.load(RUTA_ESTADO)
	cfg.set_value(str(Session.account_id), clave, position)
	cfg.save(RUTA_ESTADO)


## Devuelve true si habia posicion guardada. Quien llama decide donde va si no.
func cargar_posicion() -> bool:
	if clave == "":
		return false
	var cfg := ConfigFile.new()
	if cfg.load(RUTA_ESTADO) != OK:
		return false
	var guardado: Variant = cfg.get_value(str(Session.account_id), clave, null)
	if guardado == null:
		return false
	position = _dentro(guardado)
	return true


func centrar() -> void:
	await get_tree().process_frame
	position = _dentro((get_viewport_rect().size - size) * 0.5)


func _notification(que: int) -> void:
	if que == NOTIFICATION_RESIZED and _deco != null:
		_deco.queue_redraw()
