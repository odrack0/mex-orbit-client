# AJUSTES — ventana del sistema N. Por ahora solo calidad grafica.
#
# Tres preajustes, no un slider de cuatro como el prototipo: el usuario pidio
# alta/media/baja. Por debajo siguen siendo NIVELES POR SUBSISTEMA, asi que
# anadir un modo "personalizado" luego es abrir esta ventana, no rehacer nada.
class_name SettingsWindow
extends Control

signal preset_elegido(nombre: String)

const ORDEN := ["alta", "media", "baja"]
const DETALLE := {
	"alta": "Aliens y cajas con animación completa · fondo con todas sus capas",
	"media": "Arte fijo con sus efectos · libera ~58 MB de memoria de vídeo",
	"baja": "Sin efectos ni capas emisivas · lo mínimo para volar",
}

var _panel: PanelContainer
var _botones := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", NTheme.glass_panel())
	_panel.custom_minimum_size = Vector2(420, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_panel.add_child(col)

	var titulo := NTheme.label("AJUSTES", NTheme.michroma(), 10, NTheme.CYAN)
	titulo.mouse_filter = Control.MOUSE_FILTER_STOP
	titulo.mouse_default_cursor_shape = Control.CURSOR_MOVE
	titulo.gui_input.connect(_drag)
	col.add_child(titulo)

	col.add_child(NTheme.label("CALIDAD GRÁFICA", NTheme.michroma(), 7, NTheme.MUTED))

	for nombre in ORDEN:
		var fila := VBoxContainer.new()
		fila.add_theme_constant_override("separation", 2)
		var b := _boton(nombre)
		_botones[nombre] = b
		fila.add_child(b)
		var d := NTheme.label(DETALLE[nombre], NTheme.exo2(), 11, NTheme.FAINT)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(390, 0)
		fila.add_child(d)
		col.add_child(fila)

	col.add_child(NTheme.label("El cambio se aplica al instante · F1 cierra",
		NTheme.exo2(), 11, NTheme.MUTED))
	_refrescar()
	_centrar.call_deferred()


func _boton(nombre: String) -> Button:
	var b := Button.new()
	b.text = Quality.ETIQUETAS[nombre]
	b.custom_minimum_size = Vector2(0, 30)
	b.add_theme_font_override("font", NTheme.michroma())
	b.add_theme_font_size_override("font_size", 9)
	b.pressed.connect(func():
		preset_elegido.emit(nombre)
		_refrescar())
	return b


## El preajuste activo va en ámbar, que es el estado "abierto/activo" del
## sistema N; los demás en cian de reposo.
func _refrescar() -> void:
	for nombre in _botones:
		var activo: bool = Quality.preset == nombre
		var b: Button = _botones[nombre]
		b.add_theme_color_override("font_color", NTheme.WARN if activo else NTheme.CYAN)
		var caja := StyleBoxFlat.new()
		caja.bg_color = Color(NTheme.WARN, 0.14) if activo else NTheme.GLASS_2
		caja.border_color = NTheme.WARN if activo else NTheme.EDGE_SOFT
		caja.set_border_width_all(1)
		b.add_theme_stylebox_override("normal", caja)
		var hover := caja.duplicate()
		hover.bg_color = Color(NTheme.CYAN, 0.16)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", hover)


func alternar() -> void:
	visible = not visible
	if visible:
		_centrar()


func _drag(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_panel.position += event.relative


func _centrar() -> void:
	await get_tree().process_frame
	_panel.position = (get_viewport_rect().size - _panel.size) * 0.5
