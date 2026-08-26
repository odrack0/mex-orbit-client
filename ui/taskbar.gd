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

const LADO := 44
const ICONO := 21
const MARGEN := 8
const ALTO_L := 12.0              # esquinas en L, un pelin mas cortas que las de ventana

var _fila: HBoxContainer
var _botones := {}
var _deco: Control


func _ready() -> void:
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	offset_left = MARGEN
	offset_top = MARGEN
	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_END

	var caja := StyleBoxFlat.new()
	caja.bg_color = NTheme.GLASS_2
	caja.border_color = NTheme.EDGE
	caja.set_border_width_all(1)
	caja.shadow_color = Color(NTheme.CYAN, 0.08)
	caja.shadow_size = 24
	add_theme_stylebox_override("panel", caja)

	_fila = HBoxContainer.new()
	_fila.add_theme_constant_override("separation", 0)
	add_child(_fila)

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
	cap.custom_minimum_size = Vector2(20, LADO)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fila.add_child(cap)

	_deco = Control.new()
	_deco.set_anchors_preset(Control.PRESET_FULL_RECT)
	_deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deco.draw.connect(_pintar)
	add_child(_deco)


## `tooltip` es la UNICA cadena localizable: §1.4 prohibe texto fijo en barras de
## iconos, para que un idioma largo no pueda romper el ancho de la barra.
func agregar(clave: String, icono: String, tooltip: String, al_pulsar: Callable) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(LADO, LADO)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tooltip
	b.pressed.connect(al_pulsar)

	var glifo := TextureRect.new()
	glifo.texture = load(icono)
	glifo.custom_minimum_size = Vector2(ICONO, ICONO)
	glifo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glifo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glifo.modulate = Color("A9B6CC")          # el reposo del §5, mas claro que --muted
	glifo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glifo.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(glifo)

	# el punto de "abierta" del §5: 4 px ambar abajo y centrado
	var punto := ColorRect.new()
	punto.color = NTheme.WARN
	punto.visible = false
	punto.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# anclas Y offsets, los dos. Poniendo solo `position` sobre unas anclas
	# centradas el punto se iba del boton y acababa pintado sobre la ventana Nave.
	punto.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	punto.offset_left = -2
	punto.offset_right = 2
	punto.offset_top = -8
	punto.offset_bottom = -4
	b.add_child(punto)

	b.mouse_entered.connect(func(): _pintar_boton(clave, true))
	b.mouse_exited.connect(func(): _pintar_boton(clave, false))
	_botones[clave] = {"boton": b, "glifo": glifo, "punto": punto, "abierta": false}
	_fila.add_child(b)
	_pintar_boton(clave, false)


## Separador vertical entre grupos (§5: estado del piloto · economía · social ·
## información). Con cuatro ventanas todavia no hace falta agrupar, pero la
## barra tiene que saber hacerlo antes de que hagan falta veinte.
func separador() -> void:
	var s := PanelContainer.new()
	s.custom_minimum_size = Vector2(1, LADO - 18)
	var caja := StyleBoxFlat.new()
	caja.bg_color = NTheme.EDGE_SOFT
	s.add_theme_stylebox_override("panel", caja)
	var envoltorio := CenterContainer.new()
	envoltorio.custom_minimum_size = Vector2(7, LADO)
	envoltorio.add_child(s)
	_fila.add_child(envoltorio)


## §1.3: ambar = su ventana esta abierta. Es el MISMO codigo que la sysbar y el
## unico que hay; el cian queda para hover y seleccion.
func marcar(clave: String, abierta: bool) -> void:
	if not _botones.has(clave):
		return
	_botones[clave]["abierta"] = abierta
	_botones[clave]["punto"].visible = abierta
	_pintar_boton(clave, false)


func esta_marcado(clave: String) -> bool:
	return _botones.has(clave) and _botones[clave]["abierta"]


func _pintar_boton(clave: String, hover: bool) -> void:
	var d: Dictionary = _botones[clave]
	var b: Button = d["boton"]
	var caja := StyleBoxFlat.new()
	caja.border_width_top = 2
	if d["abierta"]:
		caja.bg_color = Color(NTheme.WARN, 0.08)
		caja.border_color = NTheme.WARN
		d["glifo"].modulate = NTheme.WARN
	else:
		caja.bg_color = Color(NTheme.CYAN, 0.07) if hover else Color(0, 0, 0, 0)
		caja.border_color = Color(0, 0, 0, 0)
		d["glifo"].modulate = Color(1, 1, 1) if hover else Color("A9B6CC")
	b.add_theme_stylebox_override("normal", caja)
	b.add_theme_stylebox_override("hover", caja)
	b.add_theme_stylebox_override("pressed", caja)


func _pintar() -> void:
	var s := size
	_deco.draw_rect(Rect2(0, 0, ALTO_L, 1.5), NTheme.CYAN)
	_deco.draw_rect(Rect2(0, 0, 1.5, ALTO_L), NTheme.CYAN)
	_deco.draw_rect(Rect2(s.x - ALTO_L, s.y - 1.5, ALTO_L, 1.5), NTheme.CYAN)
	_deco.draw_rect(Rect2(s.x - 1.5, s.y - ALTO_L, 1.5, ALTO_L), NTheme.CYAN)


func _notification(que: int) -> void:
	if que == NOTIFICATION_RESIZED and _deco != null:
		_deco.queue_redraw()
