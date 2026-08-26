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

const ICONO := "res://assets/ui/icons/ship.svg"
const ANCHO := 232

var _rejilla: GridContainer
var _barras := {}
var _valores := {}


static func crear() -> ShipWindow:
	var v := ShipWindow.new()
	v.clave = "nave"
	v._construir("Nave", ICONO)
	v._cuerpo()
	return v


func _ready() -> void:
	custom_minimum_size = Vector2(ANCHO, 0)


## Las filas van en una REJILLA de tres columnas, no en HBox sueltos.
##
## Con una fila por stat, cada una se reparte el ancho por su cuenta: la etiqueta
## se estira y la barra queda pegada al valor, asi que la barra de Bodega —cuyo
## valor "0 / 300" es mas corto que "4.000 / 4.000"— aparecia desplazada a la
## derecha respecto a las de Vida y Escudo. En una rejilla las tres columnas
## miden lo mismo en todas las filas y las barras quedan a plomo.
func _cuerpo() -> void:
	var rejilla := GridContainer.new()
	rejilla.columns = 3
	rejilla.add_theme_constant_override("h_separation", 7)
	rejilla.add_theme_constant_override("v_separation", 6)
	contenido.add_child(rejilla)
	_rejilla = rejilla

	_fila_barra("vida", "Vida", NTheme.HP)
	_fila_barra("escudo", "Escudo", NTheme.SHIELD)
	_fila_barra("bodega", "Bodega", NTheme.WARN)
	_fila_texto("creditos", "Créditos")
	_fila_texto("posicion", "Posición")


func _etiqueta(texto: String) -> Label:
	var k := NTheme.label(texto, NTheme.exo2(), 11, NTheme.MUTED)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return k


## El valor a la DERECHA de su columna: asi las cifras quedan alineadas entre si
## y se pueden comparar de un vistazo, que es para lo que sirve `tabular-nums`.
func _valor(clave: String) -> Label:
	var v := NTheme.label("—", NTheme.mono(), 10, NTheme.WARN)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_valores[clave] = v
	return v


func _fila_barra(clave: String, etiqueta: String, color: Color) -> void:
	_rejilla.add_child(_etiqueta(etiqueta))
	var barra := BarraSegmentada.new()
	barra.color = color
	_barras[clave] = barra
	_rejilla.add_child(barra)
	_rejilla.add_child(_valor(clave))


func _fila_texto(clave: String, etiqueta: String) -> void:
	_rejilla.add_child(_etiqueta(etiqueta))
	# hueco en la columna de la barra: mantiene la rejilla cuadrada
	var hueco := Control.new()
	hueco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rejilla.add_child(hueco)
	_rejilla.add_child(_valor(clave))


## Cada stat se lee contra SU PROPIO maximo (§7). Nunca se suman casco y escudo
## en una barra: esconderia cual de los dos se esta gastando.
func poner(clave: String, valor: int, maximo: int) -> void:
	if _barras.has(clave):
		_barras[clave].fraccion = 0.0 if maximo <= 0 else clampf(float(valor) / float(maximo), 0.0, 1.0)
	if _valores.has(clave):
		_valores[clave].text = "%s / %s" % [_miles(valor), _miles(maximo)]


func poner_texto(clave: String, texto: String) -> void:
	if _valores.has(clave):
		_valores[clave].text = texto


## Separador de miles con PUNTO (§3), heredado del cliente original.
static func _miles(n: int) -> String:
	var s := str(absi(n))
	var fuera := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		fuera = s[i] + fuera
		c += 1
		if c % 3 == 0 and i > 0:
			fuera = "." + fuera
	return ("-" if n < 0 else "") + fuera


## La barra del §7: 96x11, relleno a rayas VERTICALES de 4 px sobre negro. Las
## rayas no son adorno — impiden leer la barra como una regla continua y la
## emparentan con los medidores del HUD original.
class BarraSegmentada extends Control:
	const ANCHO_B := 96.0
	const ALTO_B := 11.0
	const RAYA := 4.0
	const HUECO := 2.0

	var color := Color(1, 1, 1)
	var fraccion := 0.0:
		set(v):
			fraccion = v
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(ANCHO_B, ALTO_B)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(0, 0, ANCHO_B, ALTO_B), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(0, 0, ANCHO_B, ALTO_B), NTheme.EDGE_SOFT, false, 1.0)
		var util := ANCHO_B - 2.0
		var lleno := util * fraccion
		var x := 1.0
		while x < 1.0 + lleno:
			var w: float = minf(RAYA, 1.0 + lleno - x)
			draw_rect(Rect2(x, 1, w, ALTO_B - 2), color)
			x += RAYA + HUECO
