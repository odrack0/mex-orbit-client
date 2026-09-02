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
	sb.set_border_width_all(1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
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
	b.custom_minimum_size = Vector2(0, 22)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", michroma())
	b.add_theme_font_size_override("font_size", 7)
	return b


## El elegido va en CIAN, no en ambar. El ambar del §1.3 significa "esta ventana
## esta abierta" y ese codigo no se comparte: un segmento elegido es una pestania
## activa. Mezclarlos deja al jugador sin saber que le dice el color.
static func mark_segment(b: Button, is_active: bool) -> void:
	b.add_theme_color_override("font_color", CYAN if is_active else MUTED)
	b.add_theme_color_override("font_hover_color", CYAN)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(CYAN, 0.12 if is_active else 0.04)
	box.border_color = EDGE if is_active else EDGE_SOFT
	box.set_border_width_all(1)
	box.content_margin_left = 10
	box.content_margin_right = 10
	b.add_theme_stylebox_override("normal", box)
	var hover := box.duplicate()
	hover.bg_color = Color(CYAN, 0.16)
	b.add_theme_stylebox_override("hover", hover)
