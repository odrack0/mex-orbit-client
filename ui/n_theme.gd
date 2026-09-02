# Tokens del sistema de diseño N (mex-orbit-docs/05-arte/03-sistema-diseno-ui.md).
# No inventar colores: todo sale de aquí.
class_name NTheme

## Los tokens viven en data/config/ui.json ("theme"); aqui solo se leen una vez.
## Un color del JSON es hex "RRGGBB" o, si lleva alpha, {"rgb": "RRGGBB", "alpha": a}.
static var CFG: Dictionary = AssetDefs.config("ui").get("theme", {})
static var PALETTE: Dictionary = CFG.get("palette", {})
static var FONTS: Dictionary = CFG.get("fonts", {})
static var FONT_SIZES: Dictionary = CFG.get("font_sizes", {})
static var PANEL_PADDING: Dictionary = CFG.get("panel_padding", {})
static var GAPS: Dictionary = CFG.get("gaps", {})
static var SEGMENT: Dictionary = CFG.get("segment", {})

static var BG: Color = _tone("bg", Color("07070F"))
static var GLASS: Color = _tone("glass", Color(0.051, 0.067, 0.114, 0.74))
static var GLASS_2: Color = _tone("glass_2", Color(0.051, 0.067, 0.114, 0.55))
static var EDGE: Color = _tone("edge", Color(0.0, 0.898, 1.0, 0.35))
static var EDGE_SOFT: Color = _tone("edge_soft", Color(0.47, 0.55, 0.71, 0.22))
static var CYAN: Color = _tone("cyan", Color("00E5FF"))
static var VIOLET: Color = _tone("violet", Color("A78BFA"))
static var WARN: Color = _tone("warn", Color("FFC85C"))
static var HOSTILE: Color = _tone("hostile", Color("FF3D6E"))
static var HP: Color = _tone("hp", Color("3DF58C"))
static var SHIELD: Color = _tone("shield", Color("4DA6FF"))
static var TXT: Color = _tone("txt", Color("E8F0FF"))
static var MUTED: Color = _tone("muted", Color("8A97B8"))
static var FAINT: Color = _tone("faint", Color("5A6784"))

static var MICHROMA_PATH: String = str(FONTS.get("michroma", "res://assets/fonts/Michroma-Regular.ttf"))
static var EXO2_PATH: String = str(FONTS.get("exo2", "res://assets/fonts/Exo2.ttf"))
static var MONO_PATH: String = str(FONTS.get("mono", "res://assets/fonts/JetBrainsMono.ttf"))

## Cuerpos que se repiten con el mismo papel en varias ventanas.
static var BODY_FONT_SIZE: int = int(AssetDefs.num(FONT_SIZES, "body", 12))
static var ROW_LABEL_FONT_SIZE: int = int(AssetDefs.num(FONT_SIZES, "row_label", 11))
static var ROW_VALUE_FONT_SIZE: int = int(AssetDefs.num(FONT_SIZES, "row_value", 10))

static var BORDER_WIDTH: int = int(AssetDefs.num(CFG, "border_width", 1))
static var HAIRLINE: float = AssetDefs.num(CFG, "hairline", 1.0)
static var SCREEN_MARGIN: int = int(AssetDefs.num(CFG, "screen_margin", 12))
static var BAR_MARGIN: int = int(AssetDefs.num(CFG, "bar_margin", 8))
static var PANEL_PAD_LEFT: int = int(AssetDefs.num(PANEL_PADDING, "left", 10))
static var PANEL_PAD_RIGHT: int = int(AssetDefs.num(PANEL_PADDING, "right", 10))
static var PANEL_PAD_TOP: int = int(AssetDefs.num(PANEL_PADDING, "top", 8))
static var PANEL_PAD_BOTTOM: int = int(AssetDefs.num(PANEL_PADDING, "bottom", 10))
static var ROW_GAP: int = int(AssetDefs.num(GAPS, "row", 7))
static var STACK_GAP: int = int(AssetDefs.num(GAPS, "stack", 6))
static var HOVER_ALPHA: float = AssetDefs.num(CFG, "hover_alpha", 0.16)
static var DISABLED_ALPHA: float = AssetDefs.num(CFG, "disabled_alpha", 0.45)

static var SEGMENT_HEIGHT: int = int(AssetDefs.num(SEGMENT, "height", 22))
static var SEGMENT_FONT_SIZE: int = int(AssetDefs.num(SEGMENT, "font_size", 7))
static var SEGMENT_PADDING_X: int = int(AssetDefs.num(SEGMENT, "padding_x", 10))
static var SEGMENT_GAP: int = int(AssetDefs.num(SEGMENT, "gap", 3))
static var SEGMENT_ACTIVE_ALPHA: float = AssetDefs.num(SEGMENT, "active_alpha", 0.12)
static var SEGMENT_IDLE_ALPHA: float = AssetDefs.num(SEGMENT, "idle_alpha", 0.04)

static var _michroma: FontFile
static var _exo2: FontFile
static var _mono: FontFile


## Un token de color de la paleta: hex suelto o {rgb, alpha}.
static func _tone(key: String, fallback: Color) -> Color:
	var v: Variant = PALETTE.get(key)
	if typeof(v) == TYPE_DICTIONARY:
		var d: Dictionary = v
		return Color(AssetDefs.color(d.get("rgb"), fallback), AssetDefs.num(d, "alpha", fallback.a))
	return AssetDefs.color(v, fallback)


static func michroma() -> FontFile:
	if _michroma == null:
		_michroma = load(MICHROMA_PATH)
	return _michroma


static func exo2() -> FontFile:
	if _exo2 == null:
		_exo2 = load(EXO2_PATH)
	return _exo2


static func mono() -> FontFile:
	if _mono == null:
		_mono = load(MONO_PATH)
	return _mono


## Michroma con ESPACIADO DE GLIFO — el `letter-spacing` del §3, que en Godot no
## existe en Label pero si en FontVariation. El primer intento lo falseaba
## metiendo espacios entre las letras, y eso solo aguanta un titulo corto y fijo:
## sobre "Sector 1-1 · (2330, 2060)" queda ilegible. Es la diferencia entre
## imitar el spec y cumplirlo.
static var _michroma_track := {}


static func michroma_track(px: int) -> FontVariation:
	if not _michroma_track.has(px):
		var f := FontVariation.new()
		f.base_font = michroma()
		f.spacing_glyph = px
		_michroma_track[px] = f
	return _michroma_track[px]


## Panel de cristal con las esquinas en L del sistema N.
static func glass_panel() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = GLASS
	sb.border_color = EDGE_SOFT
	sb.set_border_width_all(BORDER_WIDTH)
	sb.content_margin_left = PANEL_PAD_LEFT
	sb.content_margin_right = PANEL_PAD_RIGHT
	sb.content_margin_top = PANEL_PAD_TOP
	sb.content_margin_bottom = PANEL_PAD_BOTTOM
	return sb


static func label(txt: String, font: Font, size_px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	return l


## Un segmento del SELECTOR SEGMENTADO del §7: Michroma 7px uppercase, para
## elegir entre dos y cuatro opciones excluyentes.
##
## Vive aqui y no en la ventana de Ajustes porque ya son dos los sitios que lo
## usan —la calidad grafica y el modo de la pantalla de entrada— y una copia por
## sitio es una copia que se queda atras. Misma leccion que el recorte del croma.
static func segment(txt: String) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(0, SEGMENT_HEIGHT)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", michroma())
	b.add_theme_font_size_override("font_size", SEGMENT_FONT_SIZE)
	return b


## El elegido va en CIAN, no en ambar. El ambar del §1.3 significa "esta ventana
## esta abierta" y ese codigo no se comparte: un segmento elegido es una pestania
## activa. Mezclarlos deja al jugador sin saber que le dice el color.
static func mark_segment(b: Button, is_active: bool) -> void:
	b.add_theme_color_override("font_color", CYAN if is_active else MUTED)
	b.add_theme_color_override("font_hover_color", CYAN)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(CYAN, SEGMENT_ACTIVE_ALPHA if is_active else SEGMENT_IDLE_ALPHA)
	box.border_color = EDGE if is_active else EDGE_SOFT
	box.set_border_width_all(BORDER_WIDTH)
	box.content_margin_left = SEGMENT_PADDING_X
	box.content_margin_right = SEGMENT_PADDING_X
	b.add_theme_stylebox_override("normal", box)
	var hover := box.duplicate()
	hover.bg_color = Color(CYAN, HOVER_ALPHA)
	b.add_theme_stylebox_override("hover", hover)
