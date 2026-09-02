# NAVE — la ventana de estado del piloto (§7).
#
# Era un panel suelto con cinco etiquetas de texto: "HP 4.000 / 4.000". Ahora es
# una ventana de verdad y las stats van en BARRAS SEGMENTADAS, que es lo que el
# §7 pide y lo que sirve: un numero dice cuanto queda, una barra dice cuanto
# queda *de lo que habia*, y eso se lee sin leer.
#
# Dos barras y solo dos para la integridad —casco y escudo—, porque v1 no tiene
# nano-casco. La tercera barra es la BODEGA, que no es integridad sino espacio, y
# por eso va en ambar y no en un color de stat.
class_name ShipWindow
extends NWindow

const ICON := "res://assets/ui/icons/ship.svg"
const WIDTH := 232

var _grid: GridContainer
var _bars := {}
var _values := {}


static func create() -> ShipWindow:
	var v := ShipWindow.new()
	v.key = "nave"
	v._build("Nave", ICON)
	v._body()
	return v


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)


## Las filas van en una REJILLA de tres columnas, no en HBox sueltos.
##
## Con una fila por stat, cada una se reparte el ancho por su cuenta: la etiqueta
## se estira y la barra queda pegada al valor, asi que la barra de Bodega —cuyo
## valor "0 / 300" es mas corto que "4.000 / 4.000"— aparecia desplazada a la
## derecha respecto a las de Vida y Escudo. En una rejilla las tres columnas
## miden lo mismo en todas las filas y las barras quedan a plomo.
func _body() -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 7)
	grid.add_theme_constant_override("v_separation", 6)
	content.add_child(grid)
	_grid = grid

	_bar_row("vida", "Vida", NTheme.HP)
	_bar_row("escudo", "Escudo", NTheme.SHIELD)
	_bar_row("bodega", "Bodega", NTheme.WARN)
	_text_row("creditos", "Créditos")
	_text_row("posicion", "Posición")


func _tag(txt: String) -> Label:
	var k := NTheme.label(txt, NTheme.exo2(), 11, NTheme.MUTED)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return k


## El valor a la DERECHA de su columna: asi las cifras quedan alineadas entre si
## y se pueden comparar de un vistazo, que es para lo que sirve `tabular-nums`.
func _value(key: String) -> Label:
	var v := NTheme.label("—", NTheme.mono(), 10, NTheme.WARN)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_values[key] = v
	return v


func _bar_row(key: String, tag: String, color: Color) -> void:
	_grid.add_child(_tag(tag))
	var bar := BarraSegmentada.new()
	bar.color = color
	_bars[key] = bar
	_grid.add_child(bar)
	_grid.add_child(_value(key))


func _text_row(key: String, tag: String) -> void:
	_grid.add_child(_tag(tag))
	# hueco en la columna de la barra: mantiene la rejilla cuadrada
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.add_child(gap)
	_grid.add_child(_value(key))


## Cada stat se lee contra SU PROPIO maximo (§7). Nunca se suman casco y escudo
## en una barra: esconderia cual de los dos se esta gastando.
func put(key: String, value: int, maximum: int) -> void:
	if _bars.has(key):
		_bars[key].fraction = 0.0 if maximum <= 0 else clampf(float(value) / float(maximum), 0.0, 1.0)
	if _values.has(key):
		_values[key].text = "%s / %s" % [_thousands(value), _thousands(maximum)]


func set_text(key: String, txt: String) -> void:
	if _values.has(key):
		_values[key].text = txt


## Separador de miles con PUNTO (§3), heredado del cliente original.
static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var outside := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		outside = s[i] + outside
		c += 1
		if c % 3 == 0 and i > 0:
			outside = "." + outside
	return ("-" if n < 0 else "") + outside


## La barra del §7: 96x11, relleno a rayas VERTICALES de 4 px sobre negro. Las
## rayas no son adorno — impiden leer la barra como una regla continua y la
## emparentan con los medidores del HUD original.
class BarraSegmentada extends Control:
	const WIDTH_B := 96.0
	const HEIGHT_B := 11.0
	const DASH := 4.0
	const GAP := 2.0

	var color := Color(1, 1, 1)
	var fraction := 0.0:
		set(v):
			fraction = v
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(WIDTH_B, HEIGHT_B)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(0, 0, WIDTH_B, HEIGHT_B), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(0, 0, WIDTH_B, HEIGHT_B), NTheme.EDGE_SOFT, false, 1.0)
		var util := WIDTH_B - 2.0
		var full := util * fraction
		var x := 1.0
		while x < 1.0 + full:
			var w: float = minf(DASH, 1.0 + full - x)
			draw_rect(Rect2(x, 1, w, HEIGHT_B - 2), color)
			x += DASH + GAP
