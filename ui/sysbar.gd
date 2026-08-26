# SYSBAR — §1.9 y el `#sysbar` del prototipo N.
#
# Arriba a la derecha y FUERA del menu de ventanas: son acciones del sistema, no
# ventanas del juego. Medidas del prototipo: 8 px de margen, botones de 36x36,
# hueco de 5, icono de 16.
#
# El documento le pone cuatro botones (ajustes, ayuda, pantalla completa, salir).
# Aqui vive solo el que tiene algo detras. Un boton que no hace nada es peor que
# un boton que falta: el que falta se nota, el muerto se aprende y se deja de
# mirar. Los otros tres se agregan con `agregar()` el dia que existan.
#
# La barra ES el HBox, anclado arriba a la derecha y creciendo hacia la
# IZQUIERDA. Ese `grow_horizontal` es lo que la hace correcta: el ancho depende
# de cuantos botones tenga, y con anclaje a la derecha el contenedor se reajusta
# solo al agregar uno. Un primer intento colocaba una fila a mano dentro de un
# Control a pantalla completa y no se veia nada, porque el ancho se pedia en el
# mismo fotograma en que se agregaba el boton — y un contenedor todavia no ha
# calculado su minimo ahi. Anclar en vez de medir evita la carrera entera.
class_name SysBar
extends HBoxContainer

const LADO := 36
const HUECO := 5
const MARGEN := 8
const ICONO := 16

var _botones := {}


func _ready() -> void:
	# Los CUATRO anclajes y los CUATRO offsets a mano, sin `set_anchors_preset`.
	# El preset recalcula los offsets que no toques para conservar el rect que la
	# barra tenia antes, y como al arrancar mide 0x0 a la izquierda, dejaba
	# `offset_left` en -ancho_de_pantalla: la barra acababa ocupando todo el ancho
	# con el boton pegado a la IZQUIERDA. Poner los ocho valores no deja nada que
	# se recalcule a tu espalda.
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	# ancho y alto CERO: el crecimiento hace el resto, y por eso la barra se
	# reajusta sola al agregar un boton sin volver a medir nada
	offset_left = -MARGEN
	offset_right = -MARGEN
	offset_top = MARGEN
	offset_bottom = MARGEN
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_END
	add_theme_constant_override("separation", HUECO)


## `tooltip` es la UNICA cadena localizable del boton: §1.4 prohibe texto fijo en
## barras de iconos, para que un idioma largo no pueda romper el ancho.
func agregar(clave: String, icono: String, tooltip: String, al_pulsar: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(LADO, LADO)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tooltip
	b.add_theme_stylebox_override("normal", _caja(NTheme.EDGE_SOFT, false))
	b.add_theme_stylebox_override("hover", _caja(NTheme.EDGE, true))
	b.add_theme_stylebox_override("pressed", _caja(NTheme.EDGE, true))
	b.pressed.connect(al_pulsar)

	var glifo := TextureRect.new()
	glifo.texture = load(icono)
	glifo.custom_minimum_size = Vector2(ICONO, ICONO)
	glifo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glifo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glifo.modulate = NTheme.MUTED
	glifo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glifo.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(glifo)

	b.mouse_entered.connect(func(): _tenir(clave, true))
	b.mouse_exited.connect(func(): _tenir(clave, false))
	_botones[clave] = {"boton": b, "glifo": glifo, "abierta": false}
	add_child(b)
	return b


## §1.3: UN SOLO codigo de estado. Ambar = su ventana esta abierta, neutro =
## cerrada. Sin cian para estados — el cian es hover y seleccion, y mezclarlos
## deja al jugador sin saber que le esta diciendo el color.
func marcar(clave: String, abierta: bool) -> void:
	if not _botones.has(clave):
		return
	_botones[clave]["abierta"] = abierta
	var b: Button = _botones[clave]["boton"]
	var borde := Color(NTheme.WARN, 0.55) if abierta else NTheme.EDGE_SOFT
	b.add_theme_stylebox_override("normal", _caja(borde, abierta, NTheme.WARN))
	_tenir(clave, false)


## Para que el autotest pueda comprobar el estado del icono, no solo el de la
## ventana: el codigo de color del §1.3 es parte del contrato, no decoracion.
func esta_marcado(clave: String) -> bool:
	return _botones.has(clave) and _botones[clave]["abierta"]


func _tenir(clave: String, hover: bool) -> void:
	var d: Dictionary = _botones[clave]
	var glifo: TextureRect = d["glifo"]
	if d["abierta"]:
		glifo.modulate = NTheme.WARN
	else:
		glifo.modulate = NTheme.CYAN if hover else NTheme.MUTED


func _caja(borde: Color, glow: bool, color_glow := NTheme.CYAN) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = NTheme.GLASS_2
	sb.border_color = borde
	sb.set_border_width_all(1)
	if glow:
		sb.shadow_color = Color(color_glow, 0.22)
		sb.shadow_size = 10
	return sb
