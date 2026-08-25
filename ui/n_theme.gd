# Tokens del sistema de diseño N (mex-orbit-docs/05-arte/03-sistema-diseno-ui.md).
# No inventar colores: todo sale de aquí.
class_name NTheme

const BG := Color("07070F")
const GLASS := Color(0.051, 0.067, 0.114, 0.74)
const GLASS_2 := Color(0.051, 0.067, 0.114, 0.55)
const EDGE := Color(0.0, 0.898, 1.0, 0.35)
const EDGE_SOFT := Color(0.47, 0.55, 0.71, 0.22)
const CYAN := Color("00E5FF")
const VIOLET := Color("A78BFA")
const WARN := Color("FFC85C")
const HOSTILE := Color("FF3D6E")
const HP := Color("3DF58C")
const SHIELD := Color("4DA6FF")
const TXT := Color("E8F0FF")
const MUTED := Color("8A97B8")
const FAINT := Color("5A6784")

static var _michroma: FontFile
static var _exo2: FontFile
static var _mono: FontFile


static func michroma() -> FontFile:
	if _michroma == null:
		_michroma = load("res://assets/fonts/Michroma-Regular.ttf")
	return _michroma


static func exo2() -> FontFile:
	if _exo2 == null:
		_exo2 = load("res://assets/fonts/Exo2.ttf")
	return _exo2


static func mono() -> FontFile:
	if _mono == null:
		_mono = load("res://assets/fonts/JetBrainsMono.ttf")
	return _mono


## Panel de cristal con las esquinas en L del sistema N.
static func glass_panel() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = GLASS
	sb.border_color = EDGE_SOFT
	sb.set_border_width_all(1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	return sb


static func label(texto: String, fuente: FontFile, tam: int, color: Color) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_override("font", fuente)
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	return l
