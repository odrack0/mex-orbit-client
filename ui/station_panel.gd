# Panel de la base — ventana del sistema N que aparece al entrar en el rango de
# la estacion: descargar la bodega (dispara el refinado) y vender al NPC.
class_name StationPanel
extends Control

signal unload_pressed
signal sell_pressed(material_id: String, amount: int)

var _lista: VBoxContainer
var _precios := {}          # loot_id -> precio
var _almacen := {}          # loot_id -> cantidad
var _panel: PanelContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", NTheme.glass_panel())
	_panel.custom_minimum_size = Vector2(268, 0)
	add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_panel.add_child(col)

	var titulo := NTheme.label("ESTACIÓN", NTheme.michroma(), 8, NTheme.CYAN)
	titulo.mouse_filter = Control.MOUSE_FILTER_STOP
	titulo.mouse_default_cursor_shape = Control.CURSOR_MOVE
	titulo.gui_input.connect(_drag)
	col.add_child(titulo)

	var descargar := _boton("DESCARGAR BODEGA")
	descargar.pressed.connect(func(): unload_pressed.emit())
	col.add_child(descargar)

	col.add_child(NTheme.label("Almacén — venta al NPC", NTheme.exo2(), 11, NTheme.MUTED))
	_lista = VBoxContainer.new()
	_lista.add_theme_constant_override("separation", 3)
	col.add_child(_lista)

	visible = false
	_reposicionar.call_deferred()


func _boton(texto: String) -> Button:
	var b := Button.new()
	b.text = texto
	b.add_theme_font_override("font", NTheme.michroma())
	b.add_theme_font_size_override("font_size", 7)
	b.add_theme_color_override("font_color", NTheme.CYAN)
	b.custom_minimum_size = Vector2(0, 26)
	return b


func _drag(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_panel.position += event.relative


func _reposicionar() -> void:
	await get_tree().process_frame
	_panel.position = Vector2(12, get_viewport_rect().size.y * 0.5 - _panel.size.y * 0.5)


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
		fila.add_child(etiqueta)
		if _precios.has(loot_id):
			var b := _boton("VENDER  %d C" % _precios[loot_id])
			b.custom_minimum_size = Vector2(96, 22)
			var id: String = loot_id
			b.pressed.connect(func(): sell_pressed.emit(id, 0))   # 0 = todo
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
