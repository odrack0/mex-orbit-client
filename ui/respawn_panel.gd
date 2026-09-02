# Killscreen del sistema N: la nave fue destruida y hay que elegir cómo volver.
# Las opciones NO se inventan aquí — llegan en RespawnOptions, con su etiqueta,
# su coste y si están disponibles. El cliente solo las pinta.
class_name RespawnPanel
extends Control

signal option_chosen(option_id: int)

## Etiquetas por label_key. El contrato manda claves, no texto: así el server
## no decide el idioma (la lección de los menús con texto del legado).
const LABELS := {
	"respawn.base": "VOLVER A LA BASE",
	"respawn.spot": "REPARAR AQUÍ",
}

static var CFG: Dictionary = AssetDefs.config("ui").get("respawn", {})
static var VEIL_ALPHA: float = AssetDefs.num(CFG, "veil_alpha", 0.10)
static var PANEL_WIDTH: int = int(AssetDefs.num(CFG, "panel_width", 340))
static var SEPARATION: int = int(AssetDefs.num(CFG, "separation", 10))
static var TITLE_FONT_SIZE: int = int(AssetDefs.num(CFG, "title_font_size", 13))
static var CAUSE_WIDTH: int = int(AssetDefs.num(CFG, "cause_width", 300))
static var BUTTON_HEIGHT: int = int(AssetDefs.num(CFG, "button_height", 34))
static var BUTTON_FONT_SIZE: int = int(AssetDefs.num(CFG, "button_font_size", 9))

var _panel: PanelContainer
var _title_label: Label
var _cause: Label
var _buttons: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	# velo rojo sobre todo el mundo: no se puede seguir jugando debajo
	var veil := ColorRect.new()
	veil.color = Color(NTheme.HOSTILE, VEIL_ALPHA)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", NTheme.glass_panel())
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", SEPARATION)
	_panel.add_child(col)

	_title_label = NTheme.label("NAVE DESTRUIDA", NTheme.michroma(), TITLE_FONT_SIZE, NTheme.HOSTILE)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title_label)

	_cause = NTheme.label("", NTheme.exo2(), NTheme.BODY_FONT_SIZE, NTheme.MUTED)
	_cause.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cause.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cause.custom_minimum_size = Vector2(CAUSE_WIDTH, 0)
	col.add_child(_cause)

	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", NTheme.STACK_GAP)
	col.add_child(_buttons)


func display(msg) -> void:      # msg: MexProtocol.RespawnOptions
	for b in _buttons.get_children():
		b.queue_free()
	_cause.text = "Te destruyó %s. Tu bodega quedó flotando en el punto donde caíste." % msg.killer_name
	for op in msg.options:
		_buttons.add_child(_button(op))
	visible = true
	_center.call_deferred()


func _button(op) -> Button:      # op: MexProtocol.RespawnOption
	var b := Button.new()
	var txt: String = LABELS.get(op.label_key, op.label_key)
	if op.cost_credits > 0:
		txt += "  ·  %d C" % op.cost_credits
	b.text = txt
	b.disabled = not op.available
	b.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	b.add_theme_font_override("font", NTheme.michroma())
	b.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	b.add_theme_color_override("font_color", NTheme.CYAN)
	b.add_theme_color_override("font_disabled_color", NTheme.FAINT)
	var box := StyleBoxFlat.new()
	box.bg_color = NTheme.GLASS_2
	box.border_color = NTheme.EDGE
	box.set_border_width_all(NTheme.BORDER_WIDTH)
	b.add_theme_stylebox_override("normal", box)
	var hover := box.duplicate()
	hover.bg_color = Color(NTheme.CYAN, NTheme.HOVER_ALPHA)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(func():
		visible = false
		option_chosen.emit(op.option_id))
	return b


func _center() -> void:
	await get_tree().process_frame
	_panel.position = (get_viewport_rect().size - _panel.size) * 0.5
