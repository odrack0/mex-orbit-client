# Killscreen del sistema N: la nave fue destruida y hay que elegir cómo volver.
# Las opciones NO se inventan aquí — llegan en RespawnOptions, con su etiqueta,
# su coste y si están disponibles. El cliente solo las pinta.
class_name RespawnPanel
extends Control

signal option_chosen(option_id: int)

## Etiquetas por label_key. El contrato manda claves, no texto: así el server
## no decide el idioma (la lección de los menús con texto del legado).
const ETIQUETAS := {
	"respawn.base": "VOLVER A LA BASE",
	"respawn.spot": "REPARAR AQUÍ",
}

var _panel: PanelContainer
var _titulo: Label
var _causa: Label
var _botones: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	# velo rojo sobre todo el mundo: no se puede seguir jugando debajo
	var velo := ColorRect.new()
	velo.color = Color(NTheme.HOSTILE, 0.10)
	velo.set_anchors_preset(Control.PRESET_FULL_RECT)
	velo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(velo)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", NTheme.glass_panel())
	_panel.custom_minimum_size = Vector2(340, 0)
	add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_panel.add_child(col)

	_titulo = NTheme.label("NAVE DESTRUIDA", NTheme.michroma(), 13, NTheme.HOSTILE)
	_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_titulo)

	_causa = NTheme.label("", NTheme.exo2(), 12, NTheme.MUTED)
	_causa.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_causa.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_causa.custom_minimum_size = Vector2(300, 0)
	col.add_child(_causa)

	_botones = VBoxContainer.new()
	_botones.add_theme_constant_override("separation", 6)
	col.add_child(_botones)


func mostrar(msg) -> void:      # msg: MexProtocol.RespawnOptions
	for b in _botones.get_children():
		b.queue_free()
	_causa.text = "Te destruyó %s. Tu bodega quedó flotando en el punto donde caíste." % msg.killer_name
	for op in msg.options:
		_botones.add_child(_boton(op))
	visible = true
	_centrar.call_deferred()


func _boton(op) -> Button:      # op: MexProtocol.RespawnOption
	var b := Button.new()
	var texto: String = ETIQUETAS.get(op.label_key, op.label_key)
	if op.cost_credits > 0:
		texto += "  ·  %d C" % op.cost_credits
	b.text = texto
	b.disabled = not op.available
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_override("font", NTheme.michroma())
	b.add_theme_font_size_override("font_size", 9)
	b.add_theme_color_override("font_color", NTheme.CYAN)
	b.add_theme_color_override("font_disabled_color", NTheme.FAINT)
	var caja := StyleBoxFlat.new()
	caja.bg_color = NTheme.GLASS_2
	caja.border_color = NTheme.EDGE
	caja.set_border_width_all(1)
	b.add_theme_stylebox_override("normal", caja)
	var hover := caja.duplicate()
	hover.bg_color = Color(NTheme.CYAN, 0.16)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(func():
		visible = false
		option_chosen.emit(op.option_id))
	return b


func _centrar() -> void:
	await get_tree().process_frame
	_panel.position = (get_viewport_rect().size - _panel.size) * 0.5
