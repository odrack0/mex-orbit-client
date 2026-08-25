# El mundo del slice: fondo generado, entidades del server, vuelo con
# prediccion local + reconciliacion contra el eco autoritativo.
# La mecanica de vuelo es la del prototipo: mantener presionado el click
# persigue al cursor (la camara sigue a la nave, asi que el punto bajo un
# cursor quieto tambien avanza), con reenvio por umbral de distancia.
extends Node2D

const CLICK_RADIUS := 34.0        # radio de click sobre entidades (escalado por zoom)
const HOLD_RESEND_SEC := 0.25     # cadencia del reenvio con el boton sostenido
const HOLD_MIN_DELTA := 60.0      # el destino debe moverse al menos esto para reenviar

var _conn: GameConnection
var _entidades := {}          # entity_id -> EntityNode
var _hero: EntityNode
var _camara: Camera2D
var _seq := 0
var _limites := Vector2(20800, 12800)

# vuelo sostenido (herencia del prototipo)
var _hold_move := false
var _hold_timer := 0.0
var _last_sent_target := Vector2.INF
var _seleccionada := 0        # entity_id con seleccion local

# HUD (sistema N minimo de la iteracion: panel de nave + estado del enlace)
var _hud_estado: Label
var _hud_hp: Label
var _hud_pos: Label
var _hud_credits: Label

# autotest: vuela solo y guarda captura
var _autotest_t := 0.0


func _ready() -> void:
	_conn = GameConnection.new()
	add_child(_conn)
	_conn.welcome.connect(_on_welcome)
	_conn.enter_map.connect(_on_enter_map)
	_conn.entity_spawn.connect(_on_spawn)
	_conn.entity_despawn.connect(_on_despawn)
	_conn.entity_move.connect(_on_move)
	_conn.hero_stats.connect(_on_hero_stats)
	_conn.error_reply.connect(func(e): _estado("ErrorReply %d: %s" % [e.code, e.detail], NTheme.HOSTILE))
	_conn.session_replaced.connect(func(): _estado("Sesión reemplazada por otra conexión", NTheme.WARN))
	_conn.disconnected.connect(func(): _estado("Enlace perdido", NTheme.HOSTILE))

	_camara = Camera2D.new()
	add_child(_camara)
	_construir_hud()
	_estado("Abriendo enlace con %s..." % Session.game_host, NTheme.MUTED)
	_conn.connect_to(Session.game_host, Session.game_ticket)


func _construir_fondo() -> void:
	# nebulosa del pipeline estirada al mapa + tile de estrellas repetido encima
	var neb := Sprite2D.new()
	neb.texture = load("res://assets/world/map-1-1.png")
	neb.centered = false
	neb.scale = _limites / Vector2(neb.texture.get_width(), neb.texture.get_height())
	neb.z_index = -10
	add_child(neb)

	var stars := Sprite2D.new()
	var tex: Texture2D = load("res://assets/world/starfield-tile.png")
	stars.texture = tex
	stars.centered = false
	stars.region_enabled = true
	stars.region_rect = Rect2(0, 0, _limites.x, _limites.y)
	stars.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	stars.z_index = -9
	add_child(stars)


func _construir_hud() -> void:
	var capa := CanvasLayer.new()
	add_child(capa)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", NTheme.glass_panel())
	panel.position = Vector2(12, 12)
	capa.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	col.add_child(NTheme.label("NAVE", NTheme.michroma(), 8, NTheme.CYAN))
	_hud_hp = NTheme.label("--", NTheme.mono(), 12, NTheme.WARN)
	col.add_child(_hud_hp)
	_hud_credits = NTheme.label("--", NTheme.mono(), 12, NTheme.WARN)
	col.add_child(_hud_credits)
	_hud_pos = NTheme.label("(0, 0)", NTheme.mono(), 11, NTheme.MUTED)
	col.add_child(_hud_pos)

	_hud_estado = NTheme.label("", NTheme.exo2(), 12, NTheme.MUTED)
	_hud_estado.position = Vector2(12, 700 - 24)
	capa.add_child(_hud_estado)


func _estado(texto: String, color: Color) -> void:
	_hud_estado.text = texto
	_hud_estado.add_theme_color_override("font_color", color)


func _on_welcome(w) -> void:
	_estado("Enlace establecido · cuenta %d · tick %d Hz" % [w.account_id, w.tick_rate], NTheme.CYAN)


func _on_enter_map(em) -> void:
	_limites = Vector2(em.limits_x, em.limits_y)
	_construir_fondo()
	_estado("Sector %s (%dx%d) · riesgo de carga %d%%"
		% [em.map_code, em.limits_x, em.limits_y, em.cargo_risk_pct], NTheme.MUTED)


func _on_spawn(sp) -> void:
	if _entidades.has(sp.entity_id):
		return
	var nodo := EntityNode.new()
	var es_heroe: bool = sp.entity_id == Session.account_id
	nodo.setup(sp, es_heroe)
	add_child(nodo)
	_entidades[sp.entity_id] = nodo
	if es_heroe:
		_hero = nodo
		_camara.position = nodo.position
		_camara.make_current()


func _on_despawn(dp) -> void:
	if _entidades.has(dp.entity_id):
		_entidades[dp.entity_id].queue_free()
		_entidades.erase(dp.entity_id)


func _on_move(mv) -> void:
	var nodo: EntityNode = _entidades.get(mv.entity_id)
	if nodo == null:
		return
	nodo.reconcile(mv.x, mv.y, mv.target_x, mv.target_y, float(mv.speed), mv.teleport)


func _on_hero_stats(hs) -> void:
	_hud_hp.text = "HP %s / %s" % [_miles(hs.hp), _miles(hs.max_hp)]
	_hud_credits.text = "%s C" % _miles(hs.credits)


func _unhandled_input(event: InputEvent) -> void:
	# soltar el boton termina la persecucion del cursor
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_hold_move = false
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_handle_click(get_global_mouse_position())
			MOUSE_BUTTON_WHEEL_UP:
				_camara.zoom = (_camara.zoom * 1.1).clamp(Vector2(0.1, 0.1), Vector2(3, 3))
			MOUSE_BUTTON_WHEEL_DOWN:
				_camara.zoom = (_camara.zoom / 1.1).clamp(Vector2(0.1, 0.1), Vector2(3, 3))


func _handle_click(world_pos: Vector2) -> void:
	# ¿click sobre una entidad? seleccionar, no volar (como el prototipo)
	var bajo := _entity_at(world_pos)
	if bajo != null:
		_seleccionar(bajo)
		return
	# click en vacio: volar; mientras siga presionado, _process persigue al cursor
	_volar_a(world_pos)
	_hold_move = true
	_hold_timer = 0.0


## Entidad interactuable bajo el punto, con radio de click escalado por zoom
## (el minimo del prototipo: sin esto, con zoom lejano nada era clickable).
func _entity_at(world_pos: Vector2) -> EntityNode:
	var best: EntityNode = null
	var best_dist := INF
	var min_radius := CLICK_RADIUS / _camara.zoom.x
	for id in _entidades:
		var e: EntityNode = _entidades[id]
		if e == _hero:
			continue
		var d := e.position.distance_to(world_pos)
		if d < min_radius and d < best_dist:
			best = e
			best_dist = d
	return best


func _seleccionar(e: EntityNode) -> void:
	if _entidades.has(_seleccionada):
		_entidades[_seleccionada].set_selected(false)
	_seleccionada = e.entity_id
	e.set_selected(true)
	# el server es quien fija el objetivo real (I5 le da uso en combate)
	var sel := MexProtocol.SelectTarget.new()
	sel.entity_id = e.entity_id
	_conn.send(sel.encode())


## Reenvio periodico del destino mientras el boton siga presionado. La camara
## sigue a la nave, asi que el punto bajo un cursor quieto tambien avanza y la
## nave "persigue" al cursor de forma continua, como en el prototipo.
func _process_hold_move(delta: float) -> void:
	if not _hold_move:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_hold_move = false
		return
	_hold_timer += delta
	if _hold_timer < HOLD_RESEND_SEC:
		return
	_hold_timer = 0.0
	var target := get_global_mouse_position()
	if target.distance_to(_last_sent_target) >= HOLD_MIN_DELTA:
		_volar_a(target)


func _volar_a(destino: Vector2) -> void:
	if _hero == null:
		return
	# a diferencia del prototipo (mapa "infinito" + radiacion), v1 clampea igual
	# que el server: cliente y autoridad siempre coinciden en el destino
	destino = destino.clamp(Vector2.ZERO, _limites)
	# prediccion optimista: el heroe parte YA; el eco del server lo reconcilia
	_hero.set_objetivo(destino)
	_last_sent_target = destino
	_seq += 1
	var intent := MexProtocol.MoveIntent.new()
	intent.seq = _seq
	intent.target_x = int(destino.x)
	intent.target_y = int(destino.y)
	_conn.send(intent.encode())


func _process(delta: float) -> void:
	_process_hold_move(delta)
	if _hero != null:
		_camara.position = _camara.position.lerp(_hero.position, 8.0 * delta)
		_hud_pos.text = "(%d, %d)" % [_hero.position.x, _hero.position.y]

	if Session.autotest_screenshot != "":
		_autotest_t += delta
		if _autotest_t > 1.5 and _seq == 0 and _hero != null:
			_volar_a(_hero.position + Vector2(1400, 700))
		if _autotest_t > 5.0:
			var img := get_viewport().get_texture().get_image()
			img.save_png(Session.autotest_screenshot)
			print("AUTOTEST OK — captura en ", Session.autotest_screenshot,
				" · heroe en ", _hero.position if _hero else Vector2.ZERO,
				" · entidades: ", _entidades.size())
			get_tree().quit(0)


static func _miles(n) -> String:
	# separador de miles con punto (firma del sistema N)
	var s := str(int(n))
	var salida := ""
	var cuenta := 0
	for i in range(s.length() - 1, -1, -1):
		salida = s[i] + salida
		cuenta += 1
		if cuenta % 3 == 0 and i > 0:
			salida = "." + salida
	return salida
