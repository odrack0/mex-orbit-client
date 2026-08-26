# ESTACIÓN — descargar la bodega (dispara el refinado) y vender al NPC.
#
# Era el ultimo panel hecho a mano, y el que peor encajaba en el §1: aparecia y
# desaparecia solo segun la distancia a la base, sin icono ni forma de abrirlo.
#
# Al pasarlo a ventana hay que resolver el choque, y la respuesta no es quitarle
# la automatica:
#
#   **La cercania condiciona las ACCIONES, no la ventana.** Se puede abrir
#   siempre desde su icono —para mirar el almacen desde el otro lado del mapa—,
#   pero descargar y vender solo se habilitan estando en rango. Que un boton
#   exista y este apagado ensenia que ahi hay algo; que la ventana entera
#   desaparezca no ensenia nada.
#
# Y conserva la comodidad: al ENTRAR en rango se abre sola. Pero si el jugador la
# cierra estando atracado, no se le vuelve a abrir en la cara hasta que salga y
# vuelva. Una ventana que se reabre sola despues de cerrarla no es comoda, es
# terca.
class_name StationWindow
extends NWindow

signal unload_pressed
signal sell_pressed(material_id: String, amount: int)

const ICONO := "res://assets/ui/icons/hangar.svg"
const ANCHO := 268

var _lista: VBoxContainer
var _aviso: Label
var _descargar: Button
var _precios := {}          # loot_id -> precio
var _almacen := {}          # loot_id -> cantidad
var _en_rango := false
var _cerrada_a_mano := false


static func crear() -> StationWindow:
	var v := StationWindow.new()
	v.clave = "estacion"
	v._construir("Estación", ICONO)
	v._cuerpo()
	return v


func _ready() -> void:
	custom_minimum_size = Vector2(ANCHO, 0)
	visible = false
	# si la cierra el jugador, que no se le vuelva a abrir sola hasta salir y volver
	cerrada.connect(func(): _cerrada_a_mano = _en_rango)


func _cuerpo() -> void:
	_descargar = _boton("DESCARGAR BODEGA")
	_descargar.pressed.connect(func(): unload_pressed.emit())
	contenido.add_child(_descargar)

	_aviso = NTheme.label("", NTheme.exo2(), 11, NTheme.WARN)
	_aviso.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_aviso.custom_minimum_size = Vector2(ANCHO - 20, 0)
	contenido.add_child(_aviso)

	contenido.add_child(NTheme.label("Almacén — venta al NPC", NTheme.exo2(), 11, NTheme.MUTED))
	_lista = VBoxContainer.new()
	_lista.add_theme_constant_override("separation", 3)
	contenido.add_child(_lista)
	_refrescar()


## El server manda si estamos en rango (`in_range`). Aqui eso decide que se puede
## HACER, y solo la primera vez decide tambien que se vea.
func en_rango(dentro: bool) -> void:
	if dentro and not _en_rango and not _cerrada_a_mano:
		visible = true
		if not cargar_posicion():
			_colocar()
	if not dentro:
		_cerrada_a_mano = false      # al salir se olvida: la proxima vez vuelve a abrirse
	_en_rango = dentro
	_refrescar()


## Para que el autotest pueda afirmar el contrato nuevo: la cercania condiciona
## las ACCIONES. Que la ventana se vea no dice nada de si se puede vender.
func acciones_activas() -> bool:
	return _descargar != null and not _descargar.disabled


## El primer material que el almacen TIENE y el NPC compra, o "" si no hay
## ninguno. Lo usa el autotest: vender un material fijo a ciegas se cuelga la
## tarde que el bicho no suelta ese material.
func primer_vendible() -> String:
	for id in _almacen:
		if _almacen[id] > 0 and _precios.has(id):
			return str(id)
	return ""


func _colocar() -> void:
	await get_tree().process_frame
	position = Vector2(12, get_viewport_rect().size.y * 0.5 - size.y * 0.5)


func _boton(texto: String) -> Button:
	var b := Button.new()
	b.text = texto
	b.add_theme_font_override("font", NTheme.michroma())
	b.add_theme_font_size_override("font_size", 7)
	b.add_theme_color_override("font_color", NTheme.CYAN)
	b.add_theme_color_override("font_disabled_color", NTheme.FAINT)
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 26)
	return b


## §6: bloqueado = 45% de opacidad. El boton sigue ahi, apagado, diciendo que la
## accion existe y que falta algo para poder usarla.
func _bloquear(b: Button, bloqueado: bool) -> void:
	b.disabled = bloqueado
	b.modulate = Color(1, 1, 1, 0.45 if bloqueado else 1.0)


func set_prices(prices: Array) -> void:
	_precios.clear()
	for p in prices:
		_precios[p.material_id] = p.price_credits
	_refrescar()


func set_storage(materials: Array) -> void:
	_almacen.clear()
	for m in materials:
		_almacen[m.material_id] = m.amount
	_refrescar()


func _refrescar() -> void:
	if _lista == null:
		return
	_bloquear(_descargar, not _en_rango)
	_aviso.text = "" if _en_rango else "Fuera de rango de la base · vuela hasta la estación para descargar y vender"
	_aviso.visible = not _en_rango

	for hijo in _lista.get_children():
		hijo.queue_free()
	if _almacen.is_empty():
		_lista.add_child(NTheme.label("(almacén vacío)", NTheme.exo2(), 11, NTheme.FAINT))
		return
	for loot_id in _almacen:
		var fila := HBoxContainer.new()
		fila.add_theme_constant_override("separation", 6)
		var nombre: String = str(loot_id).trim_prefix("material_").capitalize()
		var etiqueta := NTheme.label("%s  %s" % [nombre, _miles(_almacen[loot_id])],
			NTheme.mono(), 11, NTheme.WARN)
		etiqueta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		etiqueta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fila.add_child(etiqueta)
		if _precios.has(loot_id):
			var b := _boton("VENDER  %d C" % _precios[loot_id])
			b.custom_minimum_size = Vector2(96, 22)
			var id: String = loot_id
			b.pressed.connect(func(): sell_pressed.emit(id, 0))   # 0 = todo
			_bloquear(b, not _en_rango)
			fila.add_child(b)
		_lista.add_child(fila)


static func _miles(n) -> String:
	var s := str(int(n))
	var salida := ""
	var cuenta := 0
	for i in range(s.length() - 1, -1, -1):
		salida = s[i] + salida
		cuenta += 1
		if cuenta % 3 == 0 and i > 0:
			salida = "." + salida
	return salida
