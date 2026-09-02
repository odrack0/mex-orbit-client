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

const ICON := "res://assets/ui/icons/hangar.svg"
const WIDTH := 268

var _list: VBoxContainer
var _warning: Label
var _unload: Button
var _prices := {}          # loot_id -> precio
var _storage := {}          # loot_id -> cantidad
var _in_range := false
var _closed_by_hand := false


static func create() -> StationWindow:
	var v := StationWindow.new()
	v.key = "estacion"
	v._build("Estación", ICON)
	v._body()
	return v


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	visible = false
	# si la cierra el jugador, que no se le vuelva a abrir sola hasta salir y volver
	closed.connect(func(): _closed_by_hand = _in_range)


func _body() -> void:
	_unload = _button("DESCARGAR BODEGA")
	_unload.pressed.connect(func(): unload_pressed.emit())
	content.add_child(_unload)

	_warning = NTheme.label("", NTheme.exo2(), 11, NTheme.WARN)
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning.custom_minimum_size = Vector2(WIDTH - 20, 0)
	content.add_child(_warning)

	content.add_child(NTheme.label("Almacén — venta al NPC", NTheme.exo2(), 11, NTheme.MUTED))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 3)
	content.add_child(_list)
	_refresh()


## El server manda si estamos en rango (`in_range`). Aqui eso decide que se puede
## HACER, y solo la primera vez decide tambien que se vea.
func within_range(inside: bool) -> void:
	if inside and not _in_range and not _closed_by_hand:
		visible = true
		if not load_position():
			_place()
	if not inside:
		_closed_by_hand = false      # al salir se olvida: la proxima vez vuelve a abrirse
	_in_range = inside
	_refresh()


## Para que el autotest pueda afirmar el contrato nuevo: la cercania condiciona
## las ACCIONES. Que la ventana se vea no dice nada de si se puede vender.
func active_actions() -> bool:
	return _unload != null and not _unload.disabled


## El primer material que el almacen TIENE y el NPC compra, o "" si no hay
## ninguno. Lo usa el autotest: vender un material fijo a ciegas se cuelga la
## tarde que el bicho no suelta ese material.
func first_sellable() -> String:
	for id in _storage:
		if _storage[id] > 0 and _prices.has(id):
			return str(id)
	return ""


func _place() -> void:
	await get_tree().process_frame
	position = Vector2(12, get_viewport_rect().size.y * 0.5 - size.y * 0.5)


func _button(txt: String) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_override("font", NTheme.michroma())
	b.add_theme_font_size_override("font_size", 7)
	b.add_theme_color_override("font_color", NTheme.CYAN)
	b.add_theme_color_override("font_disabled_color", NTheme.FAINT)
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 26)
	return b


## §6: bloqueado = 45% de opacidad. El boton sigue ahi, apagado, diciendo que la
## accion existe y que falta algo para poder usarla.
func _lock(b: Button, locked: bool) -> void:
	b.disabled = locked
	b.modulate = Color(1, 1, 1, 0.45 if locked else 1.0)


func set_prices(prices: Array) -> void:
	_prices.clear()
	for p in prices:
		_prices[p.material_id] = p.price_credits
	_refresh()


func set_storage(materials: Array) -> void:
	_storage.clear()
	for m in materials:
		_storage[m.material_id] = m.amount
	_refresh()


func _refresh() -> void:
	if _list == null:
		return
	_lock(_unload, not _in_range)
	_warning.text = "" if _in_range else "Fuera de rango de la base · vuela hasta la estación para descargar y vender"
	_warning.visible = not _in_range

	for child in _list.get_children():
		child.queue_free()
	if _storage.is_empty():
		_list.add_child(NTheme.label("(almacén vacío)", NTheme.exo2(), 11, NTheme.FAINT))
		return
	for loot_id in _storage:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var entry_name: String = str(loot_id).trim_prefix("material_").capitalize()
		var tag := NTheme.label("%s  %s" % [entry_name, _thousands(_storage[loot_id])],
			NTheme.mono(), 11, NTheme.WARN)
		tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(tag)
		if _prices.has(loot_id):
			var b := _button("VENDER  %d C" % _prices[loot_id])
			b.custom_minimum_size = Vector2(96, 22)
			var id: String = loot_id
			b.pressed.connect(func(): sell_pressed.emit(id, 0))   # 0 = todo
			_lock(b, not _in_range)
			row.add_child(b)
		_list.add_child(row)


static func _thousands(n) -> String:
	var s := str(int(n))
	var output := ""
	var tally := 0
	for i in range(s.length() - 1, -1, -1):
		output = s[i] + output
		tally += 1
		if tally % 3 == 0 and i > 0:
			output = "." + output
	return output
