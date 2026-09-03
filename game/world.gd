# El mundo del slice: fondo generado, entidades del server, vuelo con
# prediccion local + reconciliacion contra el eco autoritativo.
# La mecanica de vuelo es la del prototipo: mantener presionado el click
# persigue al cursor (la camara sigue a la nave, asi que el punto bajo un
# cursor quieto tambien avanza), con reenvio por umbral de distancia.
extends Node2D

## Los DIALES de este archivo viven en data/config/world.json (juego/vista) y en
## data/config/autotest.json (autotest/bestiario): aqui solo se leen, una vez, en
## `static var` con el mismo nombre que tenia cada constante. Nada calibrable
## queda escrito en el codigo (ver el README).
static var CFG: Dictionary = AssetDefs.config("world")
static var AT_CFG: Dictionary = AssetDefs.config("autotest")

static var CLICK_RADIUS: float = AssetDefs.num(CFG, "click_radius", 34.0)        # radio de click sobre entidades, en PIXELES de pantalla
static var HOLD_CFG: Dictionary = CFG.get("hold_move", {})
static var HOLD_RESEND_SEC: float = AssetDefs.num(HOLD_CFG, "resend_sec", 0.25)     # cadencia del reenvio con el boton sostenido
static var HOLD_MIN_DELTA: float = AssetDefs.num(HOLD_CFG, "min_delta", 60.0)      # el destino debe moverse al menos esto para reenviar
## Cuanto sigue un tirador encarando a su blanco tras el ultimo disparo. Los NPC
## disparan cada segundo, asi que tres aguanta un par de fallos y suelta rapido
## cuando la pelea se acaba de verdad.
static var ATTACK_FACING_SEC: float = AssetDefs.num(CFG, "attack_facing_sec", 3.0)

# FASE 1 del plan-cliente-3d: la camara y su zoom viven en Mundo3D con las
# constantes del original (FOV 30, elevacion 45, d = 1740/zoom, zoom [1,3] con
# tween y acoplamiento tilt-zoom). El rango 0.621-1.157 calibrado para el mundo
# de sprites murio con el.

## Doble click (<500 ms) sobre una entidad = fijarla Y atacar, el gesto canonico
## del original. El primer click solo selecciona, como siempre.
static var DOUBLE_CLICK_MS: int = int(AssetDefs.num(CFG, "double_click_ms", 500))

var _conn: GameConnection
var _entities := {}          # entity_id -> EntityNode
var _hero: EntityNode
var _stage: Stage3D
var _game_layer: Node2D       # HUD del mundo (barras, nombres, numeros), proyectado
var _radiation_warning: RadiationWarning   # peligro persistente: fuera de los limites
var _in_radiation := false                # edge-trigger para el Registro
var _focus := Vector2.ZERO     # a donde mira la camara, en coordenadas de juego
var _backdrop3d: Backdrop3D         # el fondo completo del original (F3)
var _seq := 0
static var MAP_CFG: Dictionary = CFG.get("map", {})
static var DEFAULT_BOUNDS: Vector2 = AssetDefs.vec2(MAP_CFG.get("default_bounds"), Vector2(20800, 12800))
var _bounds: Vector2 = DEFAULT_BOUNDS
# zona radiactiva: la radiacion NO es una pared, es un reloj — la nave sigue
# volando mas alla del limite hasta explotar. Esto es el tope estructural del
# server (Dials.RadiationReach, mismo numero), por los cuatro lados y negativo
# por el lado del 0; esta puesto donde nadie llega con vida.
static var RADIATION_CFG: Dictionary = CFG.get("radiation", {})
static var RADIATION_REACH: float = AssetDefs.num(RADIATION_CFG, "reach", 50000.0)

# vuelo sostenido (herencia del prototipo)
var _hold_move := false
var _hold_timer := 0.0
var _jumping := false
var _last_click_ent := 0     # doble click: la entidad y el instante del anterior
var _last_click_ms := 0
## Cursor simulado para la prueba del vuelo sostenido (INF = raton de verdad).
var _at_cursor := Vector2.INF
var _last_sent_target := Vector2.INF
var _selected := 0        # entity_id con seleccion local

# combate y loot (E2/I5)
static var COLLECT_CFG: Dictionary = CFG.get("collect", {})
static var AUTOPILOT_CFG: Dictionary = CFG.get("autopilot", {})
static var COLLECT_ARRIVE: float = AssetDefs.num(COLLECT_CFG, "arrive_dist", 200.0)     # llegar a esto de la caja = recolectar (server valida 250)
static var AUTOPILOT_ARRIVE: float = AssetDefs.num(AUTOPILOT_CFG, "arrive_dist", 120.0)   # a esta distancia el autopiloto declara llegada
## A menos de esto de su destino, una nave cuenta como llegada (o quieta).
static var GOAL_REACHED_DIST: float = AssetDefs.num(CFG, "goal_reached_dist", 1.0)

# autopiloto del minimapa (herencia del prototipo): destino sostenido que se
# reemite si el heroe queda detenido sin llegar; el vuelo manual lo cancela
var _autopilot := Vector2.INF
var _minimap: MinimapWindow

# la base (E2/I6)
var _base: StationWindow
var _chat: ChatWindow
var _settings: SettingsWindow
var _sysbar: SysBar
var _respawn: RespawnPanel
var _dead := false
var _station_pos := Vector2.ZERO
var _station_range := 0.0
var _at_base := false
var _station: Node3D                            # el cuerpo de la base en la escena
var _station_model: Node
var _station_mats: Array[BaseMaterial3D] = []
var _station_emission: float = STATION_EMISSION
var _station_pulse_min: float = STATION_PULSE_MIN
var _station_pulse_max: float = STATION_PULSE_MAX
var _station_pulse_speed: float = STATION_PULSE_SPEED
var _station_pulse_sharpness: float = STATION_PULSE_SHARPNESS
var _laser_on := false
var _boxes := {}                  # box_id -> Node2D (posicion; su cuerpo vive en Mundo3D)
var _portals := {}               # portal_id -> PortalNode
var _pending_box := 0             # flujo del prototipo: volar a la caja y recoger al llegar
var _pending_box_pos := Vector2.ZERO
var _req_id := 0
var _explosion_frames: SpriteFrames

# HUD (sistema N minimo de la iteracion: panel de nave + estado del enlace)
var _hud_state: Label
var _ship: ShipWindow
var _taskbar: Taskbar

# autotest: vuela solo y guarda captura
var _autotest_t := 0.0


func _ready() -> void:
	# la calidad se carga antes de construir nada: es POR CUENTA, asi que hasta
	# aqui no se sabia de quien son los ajustes
	Quality.load_data(Session.account_id)
	if Session.forced_quality != "":
		Quality.levels = Quality.PRESETS[Session.forced_quality].duplicate()
		Quality.preset = Session.forced_quality
	elif Session.autotest_mode != "":
		# Una prueba NO puede heredar estado de la corrida anterior. La del cambio
		# en caliente dejaba la cuenta en "baja" de forma persistente, asi que las
		# siguientes corrian degradadas sin decirlo: el portal montaba su camino
		# fijo y la afirmacion del atlas se saltaba sola, dando OK sin probar nada.
		# Sin -Calidad, el autotest arranca SIEMPRE en alta.
		Quality.levels = Quality.PRESETS["alta"].duplicate()
		Quality.preset = "alta"
	Quality.changed.connect(_on_quality_changed)

	_conn = GameConnection.new()
	add_child(_conn)
	_conn.welcome.connect(_on_welcome)
	_conn.enter_map.connect(_on_enter_map)
	_conn.entity_spawn.connect(_on_spawn)
	_conn.entity_despawn.connect(_on_despawn)
	_conn.entity_move.connect(_on_move)
	_conn.hero_stats.connect(_on_hero_stats)
	_conn.target_info.connect(_on_target_info)
	_conn.attack_event.connect(_on_attack)
	_conn.entity_destroyed.connect(_on_destroyed)
	_conn.box_spawn.connect(_on_box_spawn)
	_conn.box_despawn.connect(_on_box_despawn)
	_conn.collect_result.connect(_on_collect_result)
	_conn.storage_state.connect(func(s): if _base != null: _base.set_storage(s.materials))
	_conn.npc_prices.connect(func(p): if _base != null: _base.set_prices(p.prices))
	_conn.station_range.connect(_on_station_range)
	_conn.unload_result.connect(_on_unload_result)
	_conn.sell_result.connect(_on_sell_result)
	_conn.respawn_options.connect(_on_respawn_options)
	_conn.jump_handoff.connect(_on_jump_handoff)
	_conn.error_reply.connect(_on_error)
	_conn.chat_message.connect(_on_chat)
	_conn.resume_ok.connect(_on_resume_ok)
	_conn.session_replaced.connect(_on_session_replaced)
	_conn.disconnected.connect(_on_disconnected)


	# la explosion del pipeline: 8 frames de 128
	_explosion_frames = SpriteFrames.new()
	_explosion_frames.add_animation("boom")
	_explosion_frames.set_animation_loop("boom", false)
	_explosion_frames.set_animation_speed("boom", EXPLOSION_FPS)
	var sheet: Texture2D = load("res://assets/fx/explosion-sheet.png")
	for i in EXPLOSION_SHEET_FRAMES:
		var frame := AtlasTexture.new()
		frame.atlas = sheet
		frame.region = Rect2(i * EXPLOSION_FRAME_PX, 0, EXPLOSION_FRAME_PX, EXPLOSION_FRAME_PX)
		_explosion_frames.add_frame("boom", frame)

	# LA ESCENA UNICA (F1): el mundo 3D con la camara del original. Se entra en
	# el zoom mas alejado (1.0), que es el encuadre de juego.
	_stage = Stage3D.new()
	add_child(_stage)
	# la capa del HUD del mundo: barras, nombres y numeros PROYECTADOS, entre el
	# 3D (debajo de todo) y las ventanas N (capas 11+)
	var game_layer := CanvasLayer.new()
	game_layer.layer = LAYER_GAME_HUD
	add_child(game_layer)
	_game_layer = Node2D.new()
	game_layer.add_child(_game_layer)
	EntityNode.hud_layer = _game_layer
	_build_hud()
	_state("Abriendo enlace con %s..." % Session.game_host, NTheme.MUTED)
	_conn.connect_to(Session.game_host, Session.game_ticket)


## El fondo del mapa (F3): el Fondo3D completo del original — cielo con
## twinkle, telon, nebulosas a profundidad real, planetas, sol con flares y el
## polvo estelar anclado al mundo. Todo del data/maps/<code>.json de siempre.
func _build_backdrop(map_code: String) -> void:
	if _backdrop3d != null:
		return                     # una reconexion reenvia EnterMap: no duplicar capas
	_backdrop3d = Backdrop3D.new()
	_stage.add_child(_backdrop3d)
	# semilla por mapa: el mismo sector monta el mismo cielo en cada visita
	var config := MapBgConfig.for_whom(map_code, _bounds)
	# pan del original: 25 grados en mapas con fondo 3D (su display3D esta
	# compuesto para esa camara), 0 en mapas planos
	_stage.pan_deg = float(config.get("pan", 0.0))
	_backdrop3d.build(config, _bounds, map_code.hash())


## Diales del HUD (data/config/world.json, "hud"): capas, ventana Nave y linea
## de estado.
static var HUD_CFG: Dictionary = CFG.get("hud", {})
static var LAYERS_CFG: Dictionary = HUD_CFG.get("layers", {})
static var LAYER_GAME_HUD: int = int(AssetDefs.num(LAYERS_CFG, "game", 5))
static var LAYER_RADIATION_WARNING: int = int(AssetDefs.num(LAYERS_CFG, "radiation_warning", 8))
static var LAYER_WINDOWS: int = int(AssetDefs.num(LAYERS_CFG, "windows", 11))
static var LAYER_RESPAWN: int = int(AssetDefs.num(LAYERS_CFG, "respawn", 20))
static var LAYER_SETTINGS: int = int(AssetDefs.num(LAYERS_CFG, "settings", 21))
static var SHIP_WINDOW_X: float = AssetDefs.num(HUD_CFG, "ship_window_x", 12)
static var SHIP_WINDOW_TOP_MARGIN: float = AssetDefs.num(HUD_CFG, "ship_window_top_margin", 8)
static var SHIP_WINDOW_TOP_GAP: float = AssetDefs.num(HUD_CFG, "ship_window_top_gap", 10)
static var STATE_FONT_SIZE: int = int(AssetDefs.num(HUD_CFG, "state_font_size", 12))
static var STATE_SIDE_INSET: float = AssetDefs.num(HUD_CFG, "state_side_inset", 430)
static var STATE_OFFSET_TOP: float = AssetDefs.num(HUD_CFG, "state_offset_top", -34)
static var STATE_OFFSET_BOTTOM: float = AssetDefs.num(HUD_CFG, "state_offset_bottom", -14)


func _build_hud() -> void:
	var layer_node := CanvasLayer.new()
	add_child(layer_node)

	# La NAVE deja de ser un panel suelto con cinco etiquetas y pasa a ser una
	# ventana de verdad, con las barras segmentadas del §7. Una barra dice cuanto
	# queda DE LO QUE HABIA, que es lo que se lee de un vistazo en combate.
	_ship = ShipWindow.create()
	layer_node.add_child(_ship)
	# debajo de la taskbar (8 de margen + 44 de boton + 8 de aire), no encima
	if not _ship.load_position():
		_ship.position = Vector2(SHIP_WINDOW_X, SHIP_WINDOW_TOP_MARGIN + Taskbar.SIDE + SHIP_WINDOW_TOP_GAP)

	# la linea de estado vive abajo al CENTRO: las esquinas son del chat y del
	# minimapa, y antes se pisaban entre si
	_hud_state = NTheme.label("", NTheme.exo2(), STATE_FONT_SIZE, NTheme.MUTED)
	_hud_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_state.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hud_state.offset_left = STATE_SIDE_INSET
	_hud_state.offset_right = -STATE_SIDE_INSET
	_hud_state.offset_top = STATE_OFFSET_TOP
	_hud_state.offset_bottom = STATE_OFFSET_BOTTOM
	layer_node.add_child(_hud_state)

	# el aviso de la zona radiactiva: encima del HUD proyectado (capa 5) y
	# debajo de las ventanas N (11+), como el toast del prototipo (z 40)
	var warning_layer := CanvasLayer.new()
	warning_layer.layer = LAYER_RADIATION_WARNING
	add_child(warning_layer)
	_radiation_warning = RadiationWarning.create()
	warning_layer.add_child(_radiation_warning)


func _state(txt: String, color: Color) -> void:
	_hud_state.text = txt
	_hud_state.add_theme_color_override("font_color", color)


func _on_welcome(w) -> void:
	_conn.reconnect_token = w.reconnect_token      # con esto se vuelve tras una caída
	_retries = 0
	_state("Enlace establecido · cuenta %d · tick %d Hz" % [w.account_id, w.tick_rate], NTheme.CYAN)
	if _chat != null:
		_chat.add_system("Enlace establecido con el sector")


# ---- reconexión (ventana de gracia del server: 60 s) ----
static var RECONNECT_CFG: Dictionary = CFG.get("reconnect", {})
static var MAX_RETRIES: int = int(AssetDefs.num(RECONNECT_CFG, "max_retries", 8))
static var RETRY_STEP_SEC: float = AssetDefs.num(RECONNECT_CFG, "retry_step_sec", 1.0)
static var RETRY_MAX_SEC: float = AssetDefs.num(RECONNECT_CFG, "retry_max_sec", 5.0)
var _retries := 0
var _session_replaced := false


func _on_disconnected() -> void:
	if _session_replaced:
		return                                     # nos echaron: no insistir
	if _conn.reconnect_token == "" or _retries >= MAX_RETRIES:
		_state("Enlace perdido", NTheme.HOSTILE)
		return
	_retries += 1
	_state("Enlace perdido · reconectando (%d/%d)…" % [_retries, MAX_RETRIES], NTheme.WARN)
	if _chat != null:
		_chat.add_system("Enlace perdido, reconectando…", NTheme.WARN)
	# reintento con espera creciente, dentro de la ventana de gracia
	await get_tree().create_timer(minf(RETRY_STEP_SEC * _retries, RETRY_MAX_SEC)).timeout
	_conn.reconnect()


func _on_resume_ok() -> void:
	# el server nos devolvió nuestra nave: se limpia el mundo local y se
	# reconstruye con la re-sincronización que viene detrás
	for id in _entities:
		_entities[id].queue_free()
	_entities.clear()
	for id in _boxes:
		_boxes[id].queue_free()
	_boxes.clear()
	_hero = null
	_selected = 0
	_laser_on = false
	_retries = 0
	_at_reconnected = true
	_state("Reconectado: seguías en vuelo", NTheme.HP)
	if _chat != null:
		_chat.add_system("Reconectado: tu nave seguía en el sector", NTheme.HP)


func _on_session_replaced() -> void:
	_session_replaced = true
	_state("Sesión reemplazada por otra conexión", NTheme.WARN)
	if _chat != null:
		_chat.add_system("Otra conexión tomó esta cuenta", NTheme.WARN)


func _on_chat(msg) -> void:
	_at_chat_ok = true
	if _chat != null:
		_chat.add_message(msg.channel, msg.from_name, msg.text)


var _map_code := ""


func _on_enter_map(em) -> void:
	if _jump_t0 > 0:
		print("SALTO de pulsar J a tener el mapa: %d ms" % (Time.get_ticks_msec() - _jump_t0))
		_jump_t0 = 0
	# EnterMap llega tres veces por motivos distintos: al entrar, al reconectar y
	# al SALTAR de sector. Las dos primeras traen el mismo mapa y todo se conserva;
	# la tercera trae otro, y lo que sobrevive es solo lo que no pertenece al mapa
	# —las ventanas, el chat, los ajustes—. El mobiliario, las entidades y el fondo
	# son del mapa viejo y se van con el.
	if _map_code != "" and _map_code != em.map_code:
		_teardown_map()
	_bounds = Vector2(em.limits_x, em.limits_y)
	_map_code = em.map_code
	_station_pos = Vector2(em.station_x, em.station_y)
	_station_range = float(em.station_range)
	_build_backdrop(em.map_code)
	_build_station()
	_build_portals(em.portals)
	_build_minimap(em.map_code)
	_build_base()
	_build_chat()
	_build_respawn()
	_build_settings()
	if _minimap != null:
		_minimap.rename_to(em.map_code)
	_state("Sector %s (%dx%d) · riesgo de carga %d%%"
		% [em.map_code, em.limits_x, em.limits_y, em.cargo_risk_pct], NTheme.MUTED)


## Tira todo lo que pertenecia al mapa anterior. Se llama SOLO al saltar: en una
## reconexion el mapa es el mismo y rehacerlo tiraria el fondo y las entidades
## para volver a construir lo idéntico.
func _teardown_map() -> void:
	for id in _entities:
		_entities[id].queue_free()
	_entities.clear()
	for id in _boxes:
		_boxes[id].queue_free()
	_boxes.clear()
	for id in _portals:
		_portals[id].queue_free()
	_portals.clear()
	if _station != null:
		_station.queue_free()
		_station = null
		_station_mats = []
	if _backdrop3d != null:
		_backdrop3d.queue_free()
		_backdrop3d = null
	_hero = null
	_at_target = 0
	_pending_box = 0
	# El destino del movimiento pertenece al MAPA, no al jugador.
	#
	# Al hacer clic en un portal se guarda su posicion como autopiloto, y esas
	# son coordenadas del mapa VIEJO. Sin limpiarlas, al aterrizar el heroe salia
	# disparado hacia ese punto en el mapa nuevo: se llegaba encima del portal y
	# un instante despues la nave pegaba un salto a la nada.
	#
	# `_hold_move` NO se toca a proposito: se recalcula del cursor en cada
	# fotograma, asi que si el jugador sigue con el boton pulsado —que es lo
	# normal cuando se salta huyendo— la marcha continua sola y hacia donde
	# apunta, que es lo que se espera.
	_autopilot = Vector2.INF
	_last_sent_target = Vector2.INF
	_hold_timer = 0.0
	_jumping = false


func _build_minimap(map_code: String) -> void:
	if _minimap != null:
		return
	var layer_node := CanvasLayer.new()
	layer_node.layer = LAYER_WINDOWS
	add_child(layer_node)
	_minimap = MinimapWindow.new()
	layer_node.add_child(_minimap)
	_minimap.setup(self, map_code)
	_minimap.fly_to.connect(_on_autopilot)


## Los portales del mapa: llegan COMPLETOS en EnterMap (no por relevancia), con
## su posicion y su destino desde BD. Aqui solo se instancian.
func _build_portals(portal_list: Array) -> void:
	if not _portals.is_empty():
		return                     # EnterMap puede repetirse al reconectar
	for p in portal_list:
		var node := PortalNode.new()
		node.setup(p)
		add_child(node)
		_portals[node.portal_id] = node


func _build_station() -> void:
	if _station != null:
		return                     # idem: EnterMap puede repetirse al reconectar
	# la estacion y su zona segura, con las particularidades de su JSON
	var d := AssetDefs.prop("station")
	_station = Node3D.new()
	_station.position = Vector3(_station_pos.x, 0.0, _station_pos.y)
	_stage.add_child(_station)

	# El anillo de la zona segura, ahora GEOMETRIA en el plano: un toro fino que
	# la camara inclinada ve como la elipse que le toca — perspectiva gratis.
	var ring_piece: Dictionary = d.get("safe_ring", {})
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = _station_range - float(ring_piece.get("width", 3.0))
	torus.outer_radius = _station_range
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(AssetDefs.color(ring_piece.get("color", "00E5FF"), NTheme.CYAN),
		float(ring_piece.get("alpha", 0.22)))
	torus.material = ring_mat
	ring.mesh = torus
	ring.position.y = STATION_RING_HEIGHT
	_station.add_child(ring)

	# La MALLA directamente en el mundo (ya sin viewport intermedio — la torre
	# ensenia su altura con la camara a 45), en TODOS los niveles: el quad PNG
	# murio con la calidad por niveles (1-sep). Sin malla, solo el anillo.
	if not _mount_station_3d(d):
		push_warning("estacion: sin `modelo` en data/props/station.json no se dibuja")


func _build_base() -> void:
	if _base != null:
		return
	var layer_node := CanvasLayer.new()
	layer_node.layer = LAYER_WINDOWS
	add_child(layer_node)
	_base = StationWindow.create()
	layer_node.add_child(_base)
	_base.unload_pressed.connect(func():
		_req_id += 1
		var msg := MexProtocol.UnloadCargo.new()
		msg.request_id = _req_id
		_conn.send(msg.encode()))
	_base.sell_pressed.connect(func(material_id: String, amount: int):
		_req_id += 1
		var msg := MexProtocol.SellToNpc.new()
		msg.request_id = _req_id
		msg.material_id = material_id
		msg.amount = amount
		_conn.send(msg.encode()))


func _build_chat() -> void:
	if _chat != null:
		return
	var layer_node := CanvasLayer.new()
	layer_node.layer = LAYER_WINDOWS
	add_child(layer_node)
	_chat = ChatWindow.create()
	layer_node.add_child(_chat)
	_chat.send_message.connect(func(chan: int, txt: String):
		_req_id += 1
		var msg := MexProtocol.ChatSend.new()
		msg.request_id = _req_id
		msg.channel = chan
		msg.text = txt
		_conn.send(msg.encode()))


func _build_settings() -> void:
	if _settings != null:
		return
	var layer_node := CanvasLayer.new()
	layer_node.layer = LAYER_SETTINGS   # por encima del killscreen
	add_child(layer_node)

	_settings = SettingsWindow.create()
	layer_node.add_child(_settings)
	_settings.preset_chosen.connect(func(entry_name: String):
		var keys := Quality.apply(entry_name)
		if not keys.is_empty():
			_state("Calidad %s" % Quality.LABELS[entry_name], NTheme.CYAN))

	# §1.9: la sysbar va arriba a la derecha y FUERA del menu de ventanas. Hoy
	# lleva un solo boton porque es el unico que tiene algo detras; ayuda,
	# pantalla completa y salir se cuelgan con `agregar()` cuando existan.
	# §5: el menu de TODAS las ventanas del juego. Es la otra mitad del §1 — "todo
	# es ventana" solo funciona si hay de donde reabrirlas, y sin esto cerrar una
	# ventana la perdia para siempre.
	_taskbar = Taskbar.new()
	layer_node.add_child(_taskbar)
	_taskbar.add_entry("nave", ShipWindow.ICON, "Nave", func(): _toggle_window("nave", _ship))
	_taskbar.separator()
	_taskbar.add_entry("estacion", StationWindow.ICON, "Estación",
		func(): _toggle_window("estacion", _base))
	_taskbar.separator()
	_taskbar.add_entry("chat", ChatWindow.ICON, "Chat", func(): _toggle_window("chat", _chat))
	_taskbar.add_entry("minimapa", MinimapWindow.ICON, "Minimapa",
		func(): _toggle_window("minimapa", _minimap))
	for par in [["nave", _ship], ["estacion", _base], ["chat", _chat], ["minimapa", _minimap]]:
		if par[1] != null:
			_taskbar.mark(par[0], par[1].visible)
			par[1].closed.connect(_taskbar.mark.bind(par[0], false))

	_sysbar = SysBar.new()
	layer_node.add_child(_sysbar)
	_sysbar.add_entry("ajustes", SettingsWindow.ICON, "Ajustes", _toggle_settings)
	# §1.3: el icono se pone ambar cuando su ventana esta abierta, y vuelve a
	# neutro tanto si se cierra desde el icono como desde la `×` de la ventana.
	_settings.closed.connect(func(): _sysbar.mark("ajustes", false))


## §1.5: el icono ABRE y CIERRA su ventana. Y al reabrirla vuelve al frente, que
## es el §1.10 — si no, una ventana enterrada parece que no se abrio.
func _toggle_window(key: String, v: NWindow) -> void:
	if v == null:
		return
	v.visible = not v.visible
	if v.visible:
		v.move_to_front()
	_taskbar.mark(key, v.visible)


func _toggle_settings() -> void:
	if _settings == null:
		return
	_settings.toggle()
	_sysbar.mark("ajustes", _settings.visible)


## El cambio de calidad se aplica AL INSTANTE: cada entidad rehace su parte
## visual, las cajas se recrean y el fondo se reconstruye. Nada de esperar a
## reconectar — la nave, su rumbo y el estado del mundo no se tocan.
func _on_quality_changed(keys: Array) -> void:
	# render y antialias no reconstruyen nada: van directos al viewport
	if keys.has("render") or keys.has("aa"):
		_stage.apply_render_quality()
	if keys.has("emissive") or keys.has("engine") or keys.has("luces"):
		for id in _entities:
			_entities[id].rebuild()
	if keys.has("collectable"):
		for id in _portals:
			_portals[id].rebuild()
	if keys.has("background") and _backdrop3d != null:
		_backdrop3d.queue_free()
		_backdrop3d = null
		_build_backdrop(_map_code)


func _build_respawn() -> void:
	if _respawn != null:
		return
	var layer_node := CanvasLayer.new()
	layer_node.layer = LAYER_RESPAWN # por encima de todo: mientras estas muerto, manda
	add_child(layer_node)
	_respawn = RespawnPanel.new()
	layer_node.add_child(_respawn)
	_respawn.option_chosen.connect(func(option_id: int):
		var msg := MexProtocol.RespawnSelect.new()
		msg.option_id = option_id
		_conn.send(msg.encode()))


## La nave fue destruida: el server manda las opciones de vuelta al juego.
func _on_respawn_options(msg) -> void:
	_dead = true
	_hold_move = false
	_laser_on = false
	_autopilot = Vector2.INF
	_pending_box = 0
	if _respawn != null:
		_respawn.display(msg)
	if _chat != null:
		_chat.add_system("Tu nave fue destruida por %s" % msg.killer_name, NTheme.HOSTILE)
	_state("Nave destruida", NTheme.HOSTILE)
	# el autotest no tiene dedos: acepta la primera opcion y sigue con el loop
	if Session.autotest_screenshot != "" and not msg.options.is_empty():
		# un frame de margen para que el killscreen ya este dibujado en la captura
		await get_tree().process_frame
		var img_m := get_viewport().get_texture().get_image()
		img_m.save_png(Session.autotest_screenshot.replace(".png", "-muerte.png"))
		_at_deaths += 1
		if _respawn != null:
			_respawn.visible = false
		var sel := MexProtocol.RespawnSelect.new()
		sel.option_id = msg.options[0].option_id
		_conn.send(sel.encode())
		_at_phase = 0
		_at_target = 0


func _on_station_range(msg) -> void:
	_at_base = msg.in_range
	if _base != null:
		# la cercania condiciona lo que se puede HACER; la ventana la abre y la
		# cierra el jugador desde su icono, como todas las demas (§1.5)
		_base.within_range(msg.in_range)
		_taskbar.mark("estacion", _base.visible)
	_state("En la base: descarga tu bodega y vende al NPC" if msg.in_range
		else "Sector %s" % _map_code, NTheme.CYAN if msg.in_range else NTheme.MUTED)


func _on_unload_result(res) -> void:
	var parts := []
	for m in res.stored:
		parts.append("%d × %s" % [m.amount, m.material_id.trim_prefix("material_").capitalize()])
	var txt := "Almacenado: " + (", ".join(parts) if not parts.is_empty() else "nada")
	for m in res.refined:
		txt += "  ·  REFINADO: %d × %s" % [m.amount, m.material_id.trim_prefix("material_").capitalize()]
	_state(txt, NTheme.HP if not res.refined.is_empty() else NTheme.WARN)
	_at_unloaded = true


func _on_sell_result(res) -> void:
	_state("Vendido: +%s C  ·  saldo %s C" % [_thousands(res.credits_gained), _thousands(res.new_credits)],
		NTheme.WARN)
	_at_sold = true


func _on_autopilot(dest: Vector2) -> void:
	_autopilot = dest.clamp(Vector2.ZERO, _bounds)
	_state("Autopiloto hacia (%d, %d)" % [_autopilot.x, _autopilot.y], NTheme.MUTED)
	_fly_to(_autopilot)


## Vuelo sostenido del autopiloto: si el heroe quedo detenido sin llegar
## (correccion del server, choque de estados), reemite el destino.
func _process_autopilot() -> void:
	if _autopilot == Vector2.INF or _hero == null:
		return
	if _hero.position.distance_to(_autopilot) <= AUTOPILOT_ARRIVE:
		_state("Autopiloto: destino alcanzado", NTheme.MUTED)
		_autopilot = Vector2.INF
		return
	if _hero.position.distance_to(_hero.goal) < GOAL_REACHED_DIST:
		_fly_to(_autopilot)


# ---- accesores para el minimapa ----
func bounds() -> Vector2: return _bounds
func framing_corners() -> Array[Vector2]: return _stage.framing_corners()
func hero() -> EntityNode: return _hero
func entities() -> Dictionary: return _entities
func boxes() -> Dictionary: return _boxes
func portal_list() -> Dictionary: return _portals
func station_pos() -> Vector2: return _station_pos
func autopilot_on() -> Vector2: return _autopilot
func map_code() -> String: return _map_code


func _on_spawn(sp) -> void:
	if _entities.has(sp.entity_id):
		return
	var node := EntityNode.new()
	var is_hero: bool = sp.entity_id == Session.account_id
	node.setup(sp, is_hero)
	add_child(node)
	_entities[sp.entity_id] = node
	if is_hero:
		_hero = node
		if _dead:
			_dead = false
			_state("Reparada en la base", NTheme.HP)
			if _chat != null:
				_chat.add_system("Nave reparada en la base", NTheme.HP)
		_focus = node.position
		_stage.refresh(_focus)


func _on_despawn(dp) -> void:
	if _entities.has(dp.entity_id):
		_note_if_visible(_entities[dp.entity_id], "EntityDespawn(razon %d)" % dp.reason)
		_entities[dp.entity_id].queue_free()
		_entities.erase(dp.entity_id)
	# Si se va lo que tenías fichado, la selección se va con ello. Hoy el server
	# protege al objetivo de salir por rango, así que esto no debería dispararse
	# nunca — pero si algún día lo hace, el síntoma sería la tecla de disparo sin
	# hacer nada y sin decir por qué, que es de los peores que hay.
	if _selected == dp.entity_id:
		_selected = 0
		_laser_on = false
		if _hero != null:
			_hero.set_attack_target(null)


func _on_move(mv) -> void:
	var node: EntityNode = _entities.get(mv.entity_id)
	if node == null:
		return
	node.reconcile(mv.x, mv.y, mv.target_x, mv.target_y, float(mv.speed), mv.teleport)


func _on_hero_stats(hs) -> void:
	_ship.put("vida", hs.hp, hs.max_hp)
	_ship.put("escudo", hs.shield, hs.max_shield)
	_ship.put("bodega", hs.cargo, hs.max_cargo)
	_ship.set_text("creditos", "%s C" % _thousands(hs.credits))
	# tus propias barras salen de aquí: HeroStats es la única fuente de tus máximos
	if _hero != null:
		_hero.max_hp_abs = hs.max_hp
		_hero.max_shield_abs = hs.max_shield
		_hero.set_state_abs(hs.hp, hs.shield)


func _on_target_info(ti) -> void:
	var node: EntityNode = _entities.get(ti.entity_id)
	if node == null:
		return
	# casco y escudo cada uno contra su máximo: son dos barras, no una suma
	node.max_hp_abs = ti.max_hp
	node.max_shield_abs = ti.max_shield
	node.set_state_abs(ti.hp, ti.shield)


## Colores de daño del original (su tabla hitpointColors).
static var DMG_CFG: Dictionary = CFG.get("damage_numbers", {})
static var HIT_DEALT: Color = AssetDefs.color(DMG_CFG.get("dealt_color"), Color("FF0000"))      # el daño que haces
static var HIT_TAKEN: Color = AssetDefs.color(DMG_CFG.get("taken_color"), Color("DB63E2"))    # el daño que te hacen
static var DMG_FONT_SIZE: int = int(AssetDefs.num(DMG_CFG, "font_size", 24))
static var DMG_OUTLINE_ALPHA: float = AssetDefs.num(DMG_CFG, "outline_alpha", 0.95)
static var DMG_OUTLINE_SIZE: int = int(AssetDefs.num(DMG_CFG, "outline_size", 6))
static var DMG_MIN_WIDTH: float = AssetDefs.num(DMG_CFG, "min_width", 120)
static var DMG_OFFSET: Vector2 = AssetDefs.vec2(DMG_CFG.get("offset"), Vector2(-60, -90))
static var DMG_Z_INDEX: int = int(AssetDefs.num(DMG_CFG, "z_index", 20))
static var DMG_RISE_PX: float = AssetDefs.num(DMG_CFG, "rise_px", 42)
static var DMG_DURATION_SEC: float = AssetDefs.num(DMG_CFG, "duration_sec", 1.0)
static var DMG_FADE_DELAY_SEC: float = AssetDefs.num(DMG_CFG, "fade_delay_sec", 0.35)


func _on_attack(ev) -> void:
	var white: EntityNode = _entities.get(ev.target_id)
	var shooter: EntityNode = _entities.get(ev.attacker_id)
	if white == null:
		return

	_at_shots += 1
	# el disparo: un HAZ del original (F2) que nace de la boca de cañón viva del
	# tirador, se estira hasta el blanco y fluye por UV-scroll
	if shooter != null:
		var ammo: String = ev.ammo_id if ev.ammo_id != "" else "ammo_cel_1"
		Beam3D.fire(shooter, white, ammo, ev.skilled)
		# QUIEN DISPARA, ENCARA.
		#
		# Un bicho que te persigue se plantaba a 300 y se ponía a girar sobre su
		# eje con el giro perezoso, disparándote de costado. El mecanismo para
		# evitarlo ya existía —`attack_target` manda sobre el rumbo de vuelo— pero
		# solo lo usaba tu nave. La señal para los demás estaba aquí desde
		# siempre: este mismo evento dice quién dispara a quién.
		#
		# El héroe se excluye porque su rumbo lo gobierna la tecla de disparo, que
		# NO caduca: si no, esperar fuera de alcance le apagaría el encaramiento.
		if shooter != _hero:
			shooter.set_attack_target(white, ATTACK_FACING_SEC)

	if ev.missed:
		_floating_number(white, "MISS", HIT_TAKEN if white == _hero else HIT_DEALT)
		return

	white.set_state_abs(ev.target_hp, ev.target_shield)
	# impacto: en el escudo si aún queda, en el casco si no
	if ev.target_shield > 0 and shooter != null:
		white.shield_impact(shooter.position)
	else:
		white.hull_impact()
	# Aqui NO hay shake de camara, y no es un olvido: el original tampoco sacude
	# con dano normal. Su shakeScreen() solo dispara con el tipo de dano "I"
	# (detonaciones tipo mina/kamikaze) y con efectos que declaran
	# shakeScreen="true" en su XML — verificado jugando DO 3D y confirmado en el
	# decompilado. Se porto por error, se sintio mal, y la prueba en vivo mando.
	# Si v1 gana minas, la receta esta en el historial (espiral 24 ms en offset).
	_floating_number(white, str(ev.damage), HIT_TAKEN if white == _hero else HIT_DEALT)


## Número de combate: sube 42 px en 1 s sobre la entidad, con contorno negro.
## Golpes seguidos del mismo color sobre el mismo blanco se ACUMULAN en el
## número vivo y reinician el vuelo, como en el prototipo.
var _numbers := {}


func _floating_number(over: EntityNode, txt: String, color: Color) -> void:
	var key := "%d:%s" % [over.entity_id, color.to_html(false)]
	var alive = _numbers.get(key)
	if alive != null and is_instance_valid(alive) and txt.is_valid_int():
		alive.set_meta("suma", int(alive.get_meta("suma", 0)) + int(txt))
		alive.text = str(alive.get_meta("suma"))
		alive.position = _stage.to_screen(over.position) + DMG_OFFSET
		return

	# 24: registrado en el §9 del sistema de diseño. Desde F1 el numero vive en
	# el HUD proyectado (pixeles de pantalla), asi que ya no lo encoge el zoom.
	var label := NTheme.label(txt, NTheme.mono(), DMG_FONT_SIZE, color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, DMG_OUTLINE_ALPHA))
	label.add_theme_constant_override("outline_size", DMG_OUTLINE_SIZE)
	label.custom_minimum_size = Vector2(DMG_MIN_WIDTH, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# el numero vive en el HUD proyectado (pixeles): el zoom ya no lo encoge
	label.position = _stage.to_screen(over.position) + DMG_OFFSET
	label.z_index = DMG_Z_INDEX
	if txt.is_valid_int():
		label.set_meta("suma", int(txt))
	_game_layer.add_child(label)
	_numbers[key] = label
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y - DMG_RISE_PX, DMG_DURATION_SEC)
	tw.tween_property(label, "modulate:a", 0.0, DMG_DURATION_SEC).set_delay(DMG_FADE_DELAY_SEC)
	tw.chain().tween_callback(func():
		_numbers.erase(key)
		label.queue_free())


func _on_destroyed(msg) -> void:
	var node: EntityNode = _entities.get(msg.entity_id)
	if node != null and node == _hero:
		_hero = null              # el spawn de la reaparicion lo vuelve a crear
	if node != null:
		if Quality.level("explosion") < 1:
			# sin explosión dibujada, una muerte se ve EXACTAMENTE como una
			# desaparición: si el bicho que se esfumó fue esto, hay que saberlo
			_note_if_visible(node, "EntityDestroyed sin explosión (calidad)")
		_explode(node.position, node.click_radius)
		node.queue_free()
		_entities.erase(msg.entity_id)
	if _selected == msg.entity_id:
		_selected = 0
		_laser_on = false
		if _hero != null:
			_hero.set_attack_target(null)   # sin presa, el rumbo vuelve al vuelo


## Deja constancia de que algo se fue de la pantalla ESTANDO a la vista.
##
## No es logging de adorno: con relevancia por rango, el server no puede retirar
## nada dentro del encuadre —el radio visible son ~1250 unidades y el umbral de
## salida son 2200— así que si esto escribe una línea, el server hizo algo que no
## debía y aquí está el frame que lo hizo. Y si alguien VE esfumarse un bicho y
## este archivo sigue vacío, entonces el nodo no se borró: se dejó de dibujar, y
## el sitio donde mirar es otro (el SubViewport 3D de vex/vexor/vorax).
func _note_if_visible(node: EntityNode, why: String) -> void:
	if _hero == null or node == _hero:
		return
	var visible_rect := get_viewport_rect().size * _stage.units_per_pixel()
	var radius := visible_rect.length() * 0.5
	var d := _hero.position.distance_to(node.position)
	if d > radius:
		return                    # se fue fuera de pantalla: es lo esperado
	var f := FileAccess.open("res://logs/anomalias.log", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("res://logs/anomalias.log", FileAccess.WRITE)
	if f == null:
		return                    # sin sitio donde anotar, no se estorba al juego
	f.seek_end()
	f.store_line("%s · %s (%s) a %d u · radio visible %d u · %s"
		% [Time.get_datetime_string_from_system(), node.type_id, node.entity_id,
			int(d), int(radius), why])
	f.close()


## La explosion multi-capa del original (guidelines 3D, §9.4): el flipbook del
## pipeline + un FLASH central de un instante + una rafaga de CHISPAS radiales
## aditivas. El flash escala con el radio de click de la victima — un Skarnox no
## revienta como un Vex.
var _tex_flash: GradientTexture2D
var _pm_sparks: ParticleProcessMaterial
var _spark_tex: GradientTexture2D

## Diales de la explosion (data/config/world.json, "explosion").
static var EXPLOSION_CFG: Dictionary = CFG.get("explosion", {})
static var EXPLOSION_SHEET_FRAMES: int = int(AssetDefs.num(EXPLOSION_CFG, "sheet_frames", 8))
static var EXPLOSION_FRAME_PX: int = int(AssetDefs.num(EXPLOSION_CFG, "sheet_frame_px", 128))
static var EXPLOSION_FPS: float = AssetDefs.num(EXPLOSION_CFG, "fps", 16.0)
static var EXPLOSION_PIXEL_SIZE: float = AssetDefs.num(EXPLOSION_CFG, "pixel_size", 1.4)
static var EXPLOSION_HEIGHT: float = AssetDefs.num(EXPLOSION_CFG, "height", 20.0)
static var FLASH_CFG: Dictionary = EXPLOSION_CFG.get("flash", {})
static var FLASH_COLOR_IN: Color = _rgba(FLASH_CFG.get("color_in"), Color(1.0, 0.95, 0.8, 1.0))
static var FLASH_COLOR_OUT: Color = _rgba(FLASH_CFG.get("color_out"), Color(1.0, 0.5, 0.1, 0.0))
static var FLASH_TEXTURE_PX: int = int(AssetDefs.num(FLASH_CFG, "texture_px", 256))
static var FLASH_QUAD_SIZE: float = AssetDefs.num(FLASH_CFG, "quad_size", 256.0)
static var FLASH_HEIGHT: float = AssetDefs.num(FLASH_CFG, "height", 25.0)
static var FLASH_START_SCALE: float = AssetDefs.num(FLASH_CFG, "start_scale", 0.01)
static var FLASH_DIAMETER_FACTOR: float = AssetDefs.num(FLASH_CFG, "diameter_factor", 6.0)
static var FLASH_GROW_SEC: float = AssetDefs.num(FLASH_CFG, "grow_sec", 0.25)
static var FLASH_FADE_SEC: float = AssetDefs.num(FLASH_CFG, "fade_sec", 0.2)
static var FLASH_FADE_DELAY_SEC: float = AssetDefs.num(FLASH_CFG, "fade_delay_sec", 0.05)
static var EXPLOSION_LIGHT_CFG: Dictionary = EXPLOSION_CFG.get("light", {})
static var EXPLOSION_LIGHT_COLOR: Color = AssetDefs.color(EXPLOSION_LIGHT_CFG.get("color"), Color("dee4c8"))
static var EXPLOSION_LIGHT_ENERGY: float = AssetDefs.num(EXPLOSION_LIGHT_CFG, "energy", 2.0)
static var EXPLOSION_LIGHT_RANGE: float = AssetDefs.num(EXPLOSION_LIGHT_CFG, "range", 400.0)
static var EXPLOSION_LIGHT_HOLD_SEC: float = AssetDefs.num(EXPLOSION_LIGHT_CFG, "hold_sec", 0.1)
static var EXPLOSION_LIGHT_FADE_SEC: float = AssetDefs.num(EXPLOSION_LIGHT_CFG, "fade_sec", 0.25)
static var EXPLOSION_LIGHT_HEIGHT: float = AssetDefs.num(EXPLOSION_LIGHT_CFG, "height", 30.0)
static var SPARKS_CFG: Dictionary = EXPLOSION_CFG.get("sparks", {})
static var SPARKS_SPREAD_DEG: float = AssetDefs.num(SPARKS_CFG, "spread_deg", 180.0)
static var SPARKS_FLATNESS: float = AssetDefs.num(SPARKS_CFG, "flatness", 1.0)
static var SPARKS_VELOCITY_MIN: float = AssetDefs.num(SPARKS_CFG, "velocity_min", 100.0)
static var SPARKS_VELOCITY_MAX: float = AssetDefs.num(SPARKS_CFG, "velocity_max", 200.0)
static var SPARKS_SCALE_MIN: float = AssetDefs.num(SPARKS_CFG, "scale_min", 0.02)
static var SPARKS_SCALE_MAX: float = AssetDefs.num(SPARKS_CFG, "scale_max", 0.05)
static var SPARKS_LIFETIME_RANDOMNESS: float = AssetDefs.num(SPARKS_CFG, "lifetime_randomness", 0.8)
static var SPARKS_RAMP_START: Color = _rgba(SPARKS_CFG.get("ramp_start"), Color(1.0, 1.0, 0.9, 1.0))
static var SPARKS_RAMP_MID: Color = _rgba(SPARKS_CFG.get("ramp_mid"), Color(1.0, 0.7, 0.3, 0.8))
static var SPARKS_RAMP_MID_POS: float = AssetDefs.num(SPARKS_CFG, "ramp_mid_pos", 0.4)
static var SPARKS_RAMP_END: Color = _rgba(SPARKS_CFG.get("ramp_end"), Color(1.0, 0.3, 0.1, 0.0))
static var SPARKS_TEXTURE_PX: int = int(AssetDefs.num(SPARKS_CFG, "texture_px", 32))
static var SPARKS_MESH_SIZE: float = AssetDefs.num(SPARKS_CFG, "mesh_size", 32.0)
static var SPARKS_AMOUNT: int = int(AssetDefs.num(SPARKS_CFG, "amount", 24))
static var SPARKS_LIFETIME_SEC: float = AssetDefs.num(SPARKS_CFG, "lifetime_sec", 0.8)


## Color con alfa desde un JSON `[r, g, b, a]` en flotantes: los degradados de
## la explosion no caben en hex (0.95 no es un byte).
static func _rgba(v: Variant, fallback: Color) -> Color:
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 4:
		return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
	return fallback


func _explode(pos: Vector2, radius: float) -> void:
	if Quality.level("explosion") < 1:
		return                    # el evento sigue ocurriendo; solo no se dibuja
	var anim := AnimatedSprite3D.new()
	anim.sprite_frames = _explosion_frames
	anim.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	anim.shaded = false
	anim.pixel_size = EXPLOSION_PIXEL_SIZE
	anim.position = Vector3(pos.x, EXPLOSION_HEIGHT, pos.y)
	_stage.add_child(anim)
	anim.play("boom")
	anim.animation_finished.connect(anim.queue_free)

	# FLASH: un resplandor radial que nace a cero, revienta en 0.25 s y muere.
	# Es la capa que "vende" el estallido; textura procedural, cero assets.
	if _tex_flash == null:
		var g := Gradient.new()
		g.set_color(0, FLASH_COLOR_IN)
		g.set_color(1, FLASH_COLOR_OUT)
		_tex_flash = GradientTexture2D.new()
		_tex_flash.gradient = g
		_tex_flash.width = FLASH_TEXTURE_PX
		_tex_flash.height = FLASH_TEXTURE_PX
		_tex_flash.fill = GradientTexture2D.FILL_RADIAL
		_tex_flash.fill_from = Vector2(0.5, 0.5)
		_tex_flash.fill_to = Vector2(0.5, 0.0)
	var flash := Stage3D.additive_quad(_tex_flash, FLASH_QUAD_SIZE)
	flash.position = Vector3(pos.x, FLASH_HEIGHT, pos.y)
	flash.scale = Vector3.ONE * FLASH_START_SCALE
	_stage.add_child(flash)
	# el diametro final ~6x el radio de click (la proporcion del original:
	# flash de 250 para naves de ~80 de radio)
	var flash_scale := radius * FLASH_DIAMETER_FACTOR / FLASH_QUAD_SIZE
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(flash, "scale", Vector3.ONE * flash_scale, FLASH_GROW_SEC) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash, "transparency", 1.0, FLASH_FADE_SEC).set_delay(FLASH_FADE_DELAY_SEC)
	tw.chain().tween_callback(flash.queue_free)

	# CHISPAS: rafaga radial de un disparo en el plano del juego, velocidades y
	# vidas aleatorias (la desincronizacion estadistica del original).
	if _pm_sparks == null:
		_pm_sparks = ParticleProcessMaterial.new()
		_pm_sparks.direction = Vector3(1, 0, 0)
		_pm_sparks.spread = SPARKS_SPREAD_DEG
		_pm_sparks.flatness = SPARKS_FLATNESS        # la rafaga vive en el plano, como el mundo
		_pm_sparks.initial_velocity_min = SPARKS_VELOCITY_MIN
		_pm_sparks.initial_velocity_max = SPARKS_VELOCITY_MAX
		_pm_sparks.gravity = Vector3.ZERO
		_pm_sparks.scale_min = SPARKS_SCALE_MIN
		_pm_sparks.scale_max = SPARKS_SCALE_MAX
		_pm_sparks.lifetime_randomness = SPARKS_LIFETIME_RANDOMNESS
		var ramp := Gradient.new()
		ramp.set_color(0, SPARKS_RAMP_START)
		ramp.add_point(SPARKS_RAMP_MID_POS, SPARKS_RAMP_MID)
		ramp.set_color(1, SPARKS_RAMP_END)
		var rt := GradientTexture1D.new()
		rt.gradient = ramp
		_pm_sparks.color_ramp = rt
		var gc := Gradient.new()
		gc.set_color(0, Color.WHITE)
		gc.set_color(1, Color(1, 1, 1, 0))
		_spark_tex = GradientTexture2D.new()
		_spark_tex.gradient = gc
		_spark_tex.width = SPARKS_TEXTURE_PX
		_spark_tex.height = SPARKS_TEXTURE_PX
		_spark_tex.fill = GradientTexture2D.FILL_RADIAL
		_spark_tex.fill_from = Vector2(0.5, 0.5)
		_spark_tex.fill_to = Vector2(0.5, 0.0)
	# el destello de la explosion (pool de luces del mundo; preset del original:
	# 0xDEE4C8, fallOff 400, encendida ~0.1 s)
	_stage.effect_light(Vector3(pos.x, EXPLOSION_LIGHT_HEIGHT, pos.y), EXPLOSION_LIGHT_COLOR,
		EXPLOSION_LIGHT_ENERGY, EXPLOSION_LIGHT_RANGE, EXPLOSION_LIGHT_HOLD_SEC, EXPLOSION_LIGHT_FADE_SEC)

	var sparks := GPUParticles3D.new()
	sparks.amount = SPARKS_AMOUNT
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.lifetime = SPARKS_LIFETIME_SEC
	sparks.process_material = _pm_sparks
	sparks.draw_pass_1 = _spark_mesh()
	sparks.position = Vector3(pos.x, EXPLOSION_HEIGHT, pos.y)
	sparks.emitting = true
	_stage.add_child(sparks)
	sparks.finished.connect(sparks.queue_free)


var _spark_mesh_cache: QuadMesh


func _spark_mesh() -> QuadMesh:
	if _spark_mesh_cache == null:
		_spark_mesh_cache = QuadMesh.new()
		_spark_mesh_cache.size = Vector2(SPARKS_MESH_SIZE, SPARKS_MESH_SIZE)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_texture = _spark_tex
		m.vertex_color_use_as_albedo = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_spark_mesh_cache.material = m
	return _spark_mesh_cache


func _on_box_spawn(msg) -> void:
	_create_box(msg.box_id, Vector2(msg.x, msg.y))


static var BOX_CFG: Dictionary = CFG.get("box", {})
static var BOX_HEIGHT: float = AssetDefs.num(BOX_CFG, "height", 1.0)


func _create_box(box_id: int, pos: Vector2) -> void:
	if _boxes.has(box_id):
		return
	# todas las particularidades de la caja salen de su JSON (data/props/cargo-box.json)
	# El nodo del diccionario sigue siendo un Node2D con `position` en juego —
	# todo el flujo de recoger/minimapa lo lee asi—; su CUERPO vive en la
	# escena unica y muere con el (tree_exited).
	var d := AssetDefs.prop("cargo-box")
	var box := Node2D.new()
	box.position = pos
	add_child(box)
	var body_box := Node3D.new()
	body_box.position = Vector3(pos.x, BOX_HEIGHT, pos.y)
	_stage.add_child(body_box)
	box.tree_exited.connect(func(): if is_instance_valid(body_box): body_box.queue_free())

	# la malla, escalada a `world_size` por su huella, como la estacion. Sin
	# `modelo` la caja queda INVISIBLE (decision del 1-sep: el PNG murio con la
	# calidad por niveles): el nodo logico —recoger, minimapa, click— sigue vivo
	var path := str(d.get("model", ""))
	if path != "" and ResourceLoader.exists(path):
		var scene: PackedScene = load(path)
		if scene != null:
			var m: Node3D = scene.instantiate()
			body_box.add_child(m)
			m.scale = Vector3.ONE * (float(d.get("world_size", 64)) / AssetDefs.extent_3d(m))
	_boxes[box_id] = box


func _on_box_despawn(msg) -> void:
	if _boxes.has(msg.box_id):
		_boxes[msg.box_id].queue_free()
		_boxes.erase(msg.box_id)
	if _pending_box == msg.box_id:
		_pending_box = 0


func _on_collect_result(res) -> void:
	var parts := []
	for drop in res.drops:
		parts.append("%d × %s" % [drop.amount, drop.material_id.trim_prefix("material_").capitalize()])
	_state("Recogido: " + ", ".join(parts), NTheme.WARN)
	_at_collected = true


## El `detail` del server manda cuando lo trae. Antes se traducia el CODIGO a un
## texto fijo —"Demasiado lejos de la caja"— y en cuanto el salto de sector
## empezo a usar el mismo TOO_FAR, ese texto pasaba a mentir. Un codigo dice de
## que FAMILIA es el fallo; solo quien lo emite sabe de que iba.
func _on_error(e) -> void:
	# `request_id != 0` = es la RESPUESTA a algo que pedimos (el salto). Con 0, el
	# server cuenta algo por su cuenta — hoy, que el láser espera fuera de alcance.
	# Sin esa distinción, ese aviso daba por bueno el salto y la prueba mentía:
	# justo lo que advierte el comentario de arriba sobre compartir un código.
	_at_jump_rejected = _at_jump_rejected \
		or (e.code == MexProtocol.ErrorCode.TOO_FAR and e.request_id != 0)
	if e.detail != "":
		_state(e.detail, NTheme.HOSTILE if e.code != MexProtocol.ErrorCode.GONE else NTheme.MUTED)
		return
	match e.code:
		MexProtocol.ErrorCode.TOO_FAR: _state("Demasiado lejos", NTheme.HOSTILE)
		MexProtocol.ErrorCode.GONE: _state("Ya no está", NTheme.MUTED)
		MexProtocol.ErrorCode.INSUFFICIENT: _state("Bodega llena", NTheme.HOSTILE)
		_: _state("ErrorReply %d" % e.code, NTheme.HOSTILE)


func _unhandled_input(event: InputEvent) -> void:
	# J: saltar de sector. Es tecla y no clic a proposito — ver `_handle_click`.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_J \
			and (_chat == null or not _chat.is_focused()):
		_try_jump()
		get_viewport().set_input_as_handled()
		return
	# Los ajustes se abren por su ENGRANAJE de la sysbar. Estuvieron en F1 y esa
	# tecla no era suya: el §6 reserva F1-F10 para la barra de accion II, asi que
	# el atajo se habria comido un slot en cuanto existan las barras. Escape los
	# cierra, que es la unica tecla que el documento no reparte.
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE and _settings != null and _settings.visible:
		_toggle_settings()
		get_viewport().set_input_as_handled()
		return
	# escribiendo en el chat, el teclado es suyo (Enter lo enfoca, como el original)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER:
		if _chat != null and not _chat.is_focused():
			_chat.focus_on()
			return
	if _chat != null and _chat.is_focused() and event is InputEventKey:
		return
	# soltar el boton termina la persecucion del cursor
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_hold_move = false
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				var point := _stage.to_world(get_viewport().get_mouse_position())
				if point != Vector2.INF:
					_handle_click(point)
			MOUSE_BUTTON_WHEEL_UP:
				_stage.zoom_by_wheel(true)
			MOUSE_BUTTON_WHEEL_DOWN:
				_stage.zoom_by_wheel(false)
	elif event is InputEventKey and event.pressed and not event.echo:
		# Ctrl = laser (el atajo por defecto del prototipo)
		if event.keycode == KEY_CTRL:
			_toggle_laser()


func _toggle_laser() -> void:
	if _dead:
		return
	if _selected == 0 or not _entities.has(_selected):
		return
	_laser_on = not _laser_on
	# disparando, el rumbo del heroe lo gobierna el objetivo (como el prototipo)
	if _hero != null:
		_hero.set_attack_target(_entities[_selected] if _laser_on else null)
	var msg := MexProtocol.LaserToggle.new()
	msg.active = _laser_on
	_conn.send(msg.encode())


func _handle_click(world_pos: Vector2) -> void:
	if _dead:
		return                     # destruido: el mundo no acepta ordenes
	# las cajas tienen prioridad (flujo del prototipo): volar hasta ella y
	# recolectar al llegar — el server exige cercania, el cliente la procura
	var crate_id := _box_at(world_pos)
	if crate_id != 0:
		var box: Node2D = _boxes[crate_id]
		_fly_to(box.position)
		_pending_box = crate_id
		_pending_box_pos = box.position
		_state("Recogiendo caja…", NTheme.MUTED)
		return
	# ¿click sobre una entidad? seleccionar, no volar (como el prototipo).
	# DOBLE click sobre la misma = fijarla y ATACAR, el gesto canonico del original.
	var low := _entity_at(world_pos)
	if low != null:
		var now := Time.get_ticks_msec()
		var is_double: bool = low.entity_id == _last_click_ent \
			and now - _last_click_ms < DOUBLE_CLICK_MS
		_last_click_ent = low.entity_id
		_last_click_ms = now
		_select(low)
		if is_double and not _laser_on:
			_toggle_laser()
		return
	# ¿click sobre un portal? Si ya estamos encima, ACTIVAR; si no, rumbo a el.
	var portal := _portal_at(world_pos)
	if portal != null:
		_pending_box = 0
		if not portal.is_working:
			_state("Ese portal está inactivo", NTheme.VIOLET)
			return
		# El clic solo pone rumbo. Saltar es de la TECLA (J): con el salto en el
		# clic, aterrizar encima del portal de vuelta lo re-disparaba solo.
		_autopilot = portal.position
		_fly_to(portal.position)
		_state("Rumbo al portal · sector %s · pulsa J para saltar"
			% portal.target_map_code, NTheme.VIOLET)
		return
	# click en vacio: volar; mientras siga presionado, _process persigue al cursor
	# (el vuelo manual cancela el autopiloto, como en el prototipo)
	_pending_box = 0
	_autopilot = Vector2.INF
	_hold_move = true
	_hold_timer = 0.0
	if not _near_hero(world_pos):
		_fly_to(world_pos)


## El portal al alcance del salto, si lo hay. El server valida el rango otra vez:
## el cliente propone, el server dispone.
func _portal_in_reach() -> PortalNode:
	if _hero == null:
		return null
	for id in _portals:
		var p: PortalNode = _portals[id]
		if p.is_working and _hero.position.distance_to(p.position) <= PortalNode.JUMP_RANGE:
			return p
	return null


## Saltar. La peticion sale cuando ARRANCA el encendido, no cuando termina: los
## 2,1 s de animacion son exactamente el hueco donde cabe el viaje al server.
func _try_jump() -> void:
	var portal := _portal_in_reach()
	if portal == null:
		_state("No hay ningún portal al alcance", NTheme.MUTED)
		return
	if not portal.activate():
		# sin malla (o ya abierto) no hay encendido que esperar: el salto es
		# instantaneo y eso es lo correcto ahi
		_jump_portal = null
	else:
		_jump_portal = portal
		if not portal.ignition_finished.is_connected(_on_ignition_ready):
			portal.ignition_finished.connect(_on_ignition_ready)
	_jump_t0 = Time.get_ticks_msec()
	_req_id += 1
	var jump := MexProtocol.JumpRequest.new()
	jump.request_id = _req_id
	jump.portal_id = portal.portal_id
	_conn.send(jump.encode())
	_state("Saltando al sector %s…" % portal.target_map_code, NTheme.VIOLET)


## El destino lo sirve otro servidor — o el mismo, que el cliente ni lo mira. Se
## reconecta con el token que ya tiene: el estado de la nave quedo persistido en
## el mapa destino antes de que el server cerrara, asi que reconectar aterriza
## donde toca.
## El encendido llego a su ultimo fotograma: se suelta la llegada, que lleva
## esperando desde que la conexion nueva termino de sincronizar.
func _on_ignition_ready(_portal_id: int) -> void:
	_jump_portal = null
	_conn.release()


## Lo que se retrasa es la RECONEXION, no el mensaje.
##
## El primer intento aplazaba el `EnterMap` y montaba el mapa al terminar la
## animacion. No funcionaba: tras el `EnterMap` viene el resto del mundo nuevo
## —la nave, los NPC, las cajas— y eso seguia llegando y entrando en el mapa
## VIEJO, que se desmontaba dos segundos despues llevandoselo por delante.
##
## Retrasando la reconexion, la llegada entera ocurre despues del encendido y en
## un solo bloque. El socket viejo se queda abierto mientras tanto sin hacer
## dano: el server ya nos persistio en el destino y ya no nos tiene en su mapa.
func _on_jump_handoff(msg) -> void:
	var scheme := "wss" if msg.is_tls else "ws"
	var url := "%s://%s:%d/ws" % [scheme, msg.host, msg.port]
	_state("Enlazando con el sector %s…" % msg.map_code, NTheme.VIOLET)
	# Se conecta YA, en paralelo a la animacion, y se RETIENE lo que llegue. El
	# hueco de 2,1 s absorbe asi tambien el coste de abrir el socket contra el
	# server del destino, que es el que se vuelve caro al partir la carga.
	_jumping = true
	_conn.hold()
	_conn.jump_to(url)
	# sin animacion que esperar (calidad media o baja) no hay nada que retener
	if _jump_portal == null or not is_instance_valid(_jump_portal):
		_conn.release()


func _portal_at(world_pos: Vector2) -> PortalNode:
	for id in _portals:
		var p: PortalNode = _portals[id]
		if p.position.distance_to(world_pos) < p.click_radius:
			return p
	return null


func _box_at(world_pos: Vector2) -> int:
	var min_radius := CLICK_RADIUS * _stage.units_per_pixel()
	for id in _boxes:
		if _boxes[id].position.distance_to(world_pos) < min_radius:
			return id
	return 0


## Entidad interactuable bajo el punto. Cada entidad trae su radio de click del
## JSON, con el minimo del prototipo escalado por zoom (sin esto, con zoom lejano
## nada era clickable).
func _entity_at(world_pos: Vector2) -> EntityNode:
	var best: EntityNode = null
	var best_dist := INF
	var min_radius := CLICK_RADIUS * _stage.units_per_pixel()
	for id in _entities:
		var e: EntityNode = _entities[id]
		if e == _hero:
			continue
		var d := e.position.distance_to(world_pos)
		if d < maxf(e.click_radius, min_radius) and d < best_dist:
			best = e
			best_dist = d
	return best


func _select(e: EntityNode) -> void:
	if _entities.has(_selected):
		_entities[_selected].set_selected(false)
	_selected = e.entity_id
	e.set_selected(true)
	# el server es quien fija el objetivo real (I5 le da uso en combate)
	var sel := MexProtocol.SelectTarget.new()
	sel.entity_id = e.entity_id
	_conn.send(sel.encode())


## Reenvio periodico del destino mientras el boton siga presionado. La camara
## sigue a la nave, asi que el punto bajo un cursor quieto tambien avanza y la
## nave "persigue" al cursor de forma continua, como en el prototipo.
## El vuelo sostenido: mientras el boton siga pulsado, se reenvia el punto bajo
## el cursor.
##
## El cursor entra por `_cursor_mundo()` y el "sigue pulsado" por `_sigue_pulsado()`
## en vez de leerse de `Input` a pelo. No es ceremonia: sin eso este camino era
## INTESTABLE en headless —no hay raton que pulsar—, y resulta que era justo el
## camino donde vivia el fallo del salto. Un camino que solo existe con un dedo
## encima es un camino que nadie prueba.
func _process_hold_move(delta: float) -> void:
	if not _hold_move:
		return
	if not _still_pressed():
		_hold_move = false
		return
	_hold_timer += delta
	if _hold_timer < HOLD_RESEND_SEC:
		return
	_hold_timer = 0.0
	var target := _world_cursor()
	if target.distance_to(_last_sent_target) >= HOLD_MIN_DELTA and not _near_hero(target):
		_fly_to(target)


## El clic sobre la propia nave (o muy cerca) nunca cuenta como orden de
## vuelo — igual que DarkOrbit: el usuario lo confirmo jugando el original
## y aqui era ademas la ultima fuente real del "brinco" (31-ago): un destino
## practicamente encima de la nave deja `en_vuelo` en falso desde el
## arranque, asi que la correccion de reconcile() nunca se difiere (el
## guardia de "solo corrige si esta quieta" no protege lo que YA esta
## quieto) y cada eco del server se aplicaba directo. `_entity_at` ya excluye
## al heroe de la seleccion (linea de arriba, "if e == _hero: continue");
## esto es el mismo criterio aplicado al vuelo libre.
func _near_hero(point: Vector2) -> bool:
	return _hero != null and _hero.position.distance_to(point) < _hero.click_radius


func _still_pressed() -> bool:
	if _at_cursor != Vector2.INF:
		return true                       # la prueba sostiene el boton por su cuenta
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _world_cursor() -> Vector2:
	if _at_cursor != Vector2.INF:
		return _at_cursor
	var point := _stage.to_world(get_viewport().get_mouse_position())
	return point if point != Vector2.INF else (_hero.position if _hero != null else Vector2.ZERO)


## La zona radiactiva se DETECTA aqui, no llega por red: la regla es
## geometrica —fuera de los limites publicados del mapa— y es exactamente la
## que aplica el server (Geometry.OutsideBounds); el coste ya llega por
## HeroStats. Un mensaje propio seria estado duplicado del que ya se tiene.
func _process_radiation(delta: float) -> void:
	var outside := _hero != null and not _dead and _outside_map(_hero.position)
	_radiation_warning.refresh(outside, delta)
	if outside == _in_radiation:
		return
	_in_radiation = outside
	if outside:
		_state("Zona radiactiva: el casco pierde un 10% por segundo, y sube", NTheme.HOSTILE)
		if _chat != null:
			_chat.add_system("Entraste en la zona radiactiva", NTheme.HOSTILE)
	else:
		_state("De vuelta en el sector", NTheme.MUTED)
		if _chat != null:
			_chat.add_system("Saliste de la zona radiactiva")


func _outside_map(p: Vector2) -> bool:
	return p.x < 0.0 or p.y < 0.0 or p.x > _bounds.x or p.y > _bounds.y


func _fly_to(dest: Vector2) -> void:
	if _hero == null:
		return
	# MIENTRAS SE SALTA, el cliente no conduce la nave.
	#
	# Este era el fallo. Durante los ~2 s de encendido el socket YA es el del
	# servidor destino, pero en pantalla sigue el mapa viejo: la camara, el cursor
	# y el autopiloto hablan en coordenadas del mapa que se esta dejando. Con el
	# raton pulsado —lo normal al saltar huyendo— el vuelo sostenido seguia
	# mandando esas coordenadas al server NUEVO, que las aceptaba como buenas. Por
	# eso se aterrizaba encima del portal y un instante despues la nave salia
	# disparada: llevaba un destino del mapa anterior metido por la puerta de
	# atras.
	#
	# Entre pulsar J y ver el mapa nuevo, la nave no esta en ningun sitio que el
	# jugador pueda ver bien. Lo unico correcto es no tocarla.
	if _jumping:
		return
	# zona radiactiva: se puede rebasar el limite del mapa y seguir volando
	# hasta explotar (el danio por segundo es del server), asi que el clamp de
	# aqui ya NO es al limite — es al mismo alcance estructural que aplica el
	# server, por los cuatro lados (negativo por el lado del 0), para que
	# cliente y autoridad sigan coincidiendo en el destino. El `Vector2.ZERO`
	# que habia aqui era una de las capas que dejaban el borde izquierdo en
	# pared; el margen de 1000 que vino despues se sentia igual de pared.
	var reach := Vector2.ONE * RADIATION_REACH
	dest = dest.clamp(-reach, _bounds + reach)
	# prediccion optimista: el heroe parte YA; el eco del server lo reconcilia
	_hero.set_goal(dest)
	_last_sent_target = dest
	_seq += 1
	var intent := MexProtocol.MoveIntent.new()
	intent.seq = _seq
	intent.target_x = int(dest.x)
	intent.target_y = int(dest.y)
	_conn.send(intent.encode())


func _process(delta: float) -> void:
	_process_hold_move(delta)
	_process_pending_collect()
	_process_autopilot()
	if _backdrop3d != null:
		_backdrop3d.update(_focus, delta)

	# la base animada avanza sus fotogramas
	# La estacion 3D RESPIRA por su emision. Es el mismo latido que tenia la capa
	# emisiva en 2D —los mismos diales `pulse` de su ficha— aplicado a la emision
	# del material en vez de al alfa de un sprite encima.
	#
	# Sin esto la emision es un color pintado en la textura: se ve encendida en la
	# foto y muerta en movimiento. Lo que hace que una luz parezca luz no es el
	# brillo, es que cambie.
	if not _station_mats.is_empty():
		var t := Time.get_ticks_msec() * 0.001 * _station_pulse_speed
		var w := pow(0.5 + 0.5 * sin(t), _station_pulse_sharpness)
		var e: float = _station_emission * (_station_pulse_min + (_station_pulse_max - _station_pulse_min) * w)
		for mat in _station_mats:
			mat.emission_energy_multiplier = e

	# la camara del original: seguimiento RIGIDO al heroe (o al foco libre del
	# autotest); Mundo3D pone el rig orbital, el zoom y el tilt-zoom
	if _hero != null and not _at_free_camera:
		_focus = _hero.position
		_ship.set_text("posicion", "(%d, %d)" % [_hero.position.x, _hero.position.y])
	_stage.refresh(_focus)
	_process_radiation(delta)
	# El HUD (nombre/barras) se proyecta AQUI, explicitamente despues de mover
	# la camara — nunca dentro del _process de cada EntityNode (ver el
	# comentario grande en sincronizar_hud()): es la unica forma de que la
	# posicion (ya actualizada, las entidades procesan con prioridad -10,
	# antes que World) y la camara (recien actualizada arriba) esten frescas
	# A LA VEZ para el mismo fotograma.
	for e: EntityNode in _entities.values():
		e.sync_hud()

	# (los disparos son proyectiles que viajan, uno por AttackEvent del server:
	# ya no hay haz permanente entre las naves)

	if Session.autotest_screenshot != "":
		_autotest(delta)


## Recoleccion en vuelo (flujo del prototipo): al llegar junto a la caja,
## se manda el CollectBox; si el server nos corrigio lejos, se cancela sola.
func _process_pending_collect() -> void:
	if _pending_box == 0 or _hero == null:
		return
	if _hero.position.distance_to(_hero.goal) > GOAL_REACHED_DIST:
		return   # sigue volando
	if _hero.position.distance_to(_pending_box_pos) <= COLLECT_ARRIVE:
		_req_id += 1
		var msg := MexProtocol.CollectBox.new()
		msg.request_id = _req_id
		msg.box_id = _pending_box
		_conn.send(msg.encode())
	_pending_box = 0


# autotest del loop I5: volar al Vex mas cercano -> laser -> caja -> recoger
var _at_phase := 0
var _at_target := 0
var _at_collected := false
var _at_last_flight := 0.0
var _at_unloaded := false
var _at_sold := false
var _at_shots := 0
var _at_shot_combat := false
var _at_chat_ok := false
var _at_reconnected := false
var _at_free_camera := false
var _at_portal_animated := false
var _jump_portal: PortalNode = null
var _jump_t0 := 0
var _at_jump_requested := false
var _at_jump_origin := ""
var _at_jump_dest := ""
var _at_jump_arrival := Vector2.ZERO
var _at_jump_camera := 0.0
var _at_jump_portal: PortalNode = null
var _at_jump_rejected := false     # el autotest suelta la camara para retratar el mapa
var _at_camera_t := -1.0
## Los bichos a los que el autotest les toma retrato de QA (uno por especie).
static var AT_BESTIARY: Array = _strings(AT_CFG.get("bestiary"),
	["vex", "vexor", "skarn", "ferox", "skarnox", "gravit", "mordax", "gravon", "vorax", "aci-01", "aci-02", "aci-03", "aci-04"])
var _at_creature := 0
var _at_relief := -1                      # paso de la prueba del relieve
var _at_hull_at := PackedFloat32Array()
var _at_relief_rest := 0.0
var _at_creature_move := {}                    # especie -> cuanto se movio entre sus dos retratos
var _at_relief_previous := 0.0
var _at_turn_at := 0.0
var _at_first_frame := false
## Ejemplar fabricado para el retrato cuando la especie no anda cerca.
var _at_dummy: EntityNode = null
var _at_quality_change := false
var _at_previous_quality := "alta"
var _at_hunt_since := 0.0
var _at_hunt_dist := 0.0
var _at_shot_box := false


var _at_deaths := 0

## Diales del autotest (data/config/autotest.json): tiempos de fase, distancias
## de caza y umbrales. Los textos de FALLO citan algunos a mano.
static var AT_TIMEOUTS_CFG: Dictionary = AT_CFG.get("timeouts", {})
static var AT_LOOP_TIMEOUT_SEC: float = AssetDefs.num(AT_TIMEOUTS_CFG, "loop_sec", 190.0)
static var AT_BESTIARY_TIMEOUT_SEC: float = AssetDefs.num(AT_TIMEOUTS_CFG, "bestiary_sec", 60.0)
static var AT_JUMP_TIMEOUT_SEC: float = AssetDefs.num(AT_TIMEOUTS_CFG, "jump_sec", 150.0)
static var AT_FLIGHT_CFG: Dictionary = AT_CFG.get("flight", {})
static var AT_REROUTE_SEC: float = AssetDefs.num(AT_FLIGHT_CFG, "reroute_sec", 2.0)
static var AT_APPROACH_OFFSET: Vector2 = AssetDefs.vec2(AT_FLIGHT_CFG.get("approach_offset"), Vector2(120, 0))
static var AT_HUNT_CFG: Dictionary = AT_CFG.get("hunt", {})
static var AT_ENGAGE_DIST: float = AssetDefs.num(AT_HUNT_CFG, "engage_dist", 450.0)
static var AT_HUNT_TIMEOUT_SEC: float = AssetDefs.num(AT_HUNT_CFG, "timeout_sec", 45.0)
static var AT_MIN_CLOSURE_SPEED: float = AssetDefs.num(AT_HUNT_CFG, "min_closure_speed", 1.0)
static var AT_PHASES_CFG: Dictionary = AT_CFG.get("phases", {})
static var AT_START_DELAY_SEC: float = AssetDefs.num(AT_PHASES_CFG, "start_delay_sec", 1.5)
static var AT_SPAWN_SETTLE_SEC: float = AssetDefs.num(AT_PHASES_CFG, "spawn_settle_sec", 3.0)
static var AT_COMBAT_SHOTS_FOR_PHOTO: int = int(AssetDefs.num(AT_PHASES_CFG, "combat_shots_for_photo", 3))
static var AT_BOX_PHOTO_DIST: float = AssetDefs.num(AT_PHASES_CFG, "box_photo_dist", 520.0)
static var AT_STATION_APPROACH_OFFSET: Vector2 = AssetDefs.vec2(AT_PHASES_CFG.get("station_approach_offset"), Vector2(330, 60))
static var AT_STATION_NEAR_DIST: float = AssetDefs.num(AT_PHASES_CFG, "station_near_dist", 420.0)
static var AT_STEP_WAIT_SEC: float = AssetDefs.num(AT_PHASES_CFG, "step_wait_sec", 1.0)
static var AT_RECONNECT_WAIT_SEC: float = AssetDefs.num(AT_PHASES_CFG, "reconnect_wait_sec", 3.0)
static var AT_PORTAL_REST_SEC: float = AssetDefs.num(AT_PHASES_CFG, "portal_rest_sec", 1.5)
static var AT_PORTAL_OPEN_SEC: float = AssetDefs.num(AT_PHASES_CFG, "portal_open_sec", 3.0)
static var AT_SETTINGS_WAIT_SEC: float = AssetDefs.num(AT_PHASES_CFG, "settings_wait_sec", 0.6)
static var AT_WINDOWS_WAIT_SEC: float = AssetDefs.num(AT_PHASES_CFG, "windows_wait_sec", 0.5)
static var AT_ZOOM_WAIT_SEC: float = AssetDefs.num(AT_PHASES_CFG, "zoom_wait_sec", 0.4)
static var AT_MINIMAP_MAX_DEFORMATION: float = AssetDefs.num(AT_PHASES_CFG, "minimap_max_deformation", 0.02)
static var AT_MINIMAP_ZOOM_STEP: int = int(AssetDefs.num(AT_PHASES_CFG, "minimap_zoom_step", 2))
static var AT_JUMP_CFG: Dictionary = AT_CFG.get("jump", {})
static var AT_JUMP_PORTAL_NEAR_DIST: float = AssetDefs.num(AT_JUMP_CFG, "portal_near_dist", 400.0)
static var AT_JUMP_FAR_INSET: float = AssetDefs.num(AT_JUMP_CFG, "far_target_inset", 2000)
static var AT_JUMP_CURSOR_INSET: float = AssetDefs.num(AT_JUMP_CFG, "cursor_inset", 1500)
static var AT_JUMP_ARRIVAL_TIMEOUT_SEC: float = AssetDefs.num(AT_JUMP_CFG, "arrival_timeout_sec", 15.0)
static var AT_JUMP_SETTLE_SEC: float = AssetDefs.num(AT_JUMP_CFG, "settle_sec", 1.5)
static var AT_JUMP_MAX_CAMERA_DIST: float = AssetDefs.num(AT_JUMP_CFG, "max_camera_dist", 150.0)
static var AT_JUMP_MAX_DRIFT: float = AssetDefs.num(AT_JUMP_CFG, "max_drift", 200.0)
static var AT_PORTRAIT_CFG: Dictionary = AT_CFG.get("portrait", {})
static var AT_QUALITY_CHANGE_WAIT_SEC: float = AssetDefs.num(AT_PORTRAIT_CFG, "quality_change_wait_sec", 1.0)
static var AT_FIRST_FRAME_SEC: float = AssetDefs.num(AT_PORTRAIT_CFG, "first_frame_sec", 1.2)
static var AT_SECOND_FRAME_SEC: float = AssetDefs.num(AT_PORTRAIT_CFG, "second_frame_sec", 2.1)
static var AT_DUMMY_POS_FRACTION: Vector2 = AssetDefs.vec2(AT_PORTRAIT_CFG.get("dummy_pos_fraction"), Vector2(0.5, 0.25))
static var AT_CROP_Y_FROM: float = AssetDefs.num(AT_PORTRAIT_CFG, "crop_y_from", 0.30)
static var AT_CROP_Y_TO: float = AssetDefs.num(AT_PORTRAIT_CFG, "crop_y_to", 0.70)
static var AT_CROP_X_FROM: float = AssetDefs.num(AT_PORTRAIT_CFG, "crop_x_from", 0.35)
static var AT_CROP_X_TO: float = AssetDefs.num(AT_PORTRAIT_CFG, "crop_x_to", 0.65)
static var AT_CROP_STEP: int = int(AssetDefs.num(AT_PORTRAIT_CFG, "crop_step", 2))


func _autotest(delta: float) -> void:
	_autotest_t += delta
	# muerto o aun sin nave: no hay nada que pilotar este frame. Sin esta guarda,
	# cualquier fase que use _hero reventaba en cuanto un Ferox hacia su trabajo.
	if _dead or (_hero == null and _at_phase > 0):
		return
	# modo SALTO: volar hasta el portal y cruzarlo de verdad. Va aparte de la
	# pasada del loop porque el portal del 1-1 esta a ~19.000 unidades de la base
	# y llegar cuesta un minuto: meterlo en la puerta rapida la doblaria de largo.
	if Session.autotest_mode == "jump":
		_autotest_jump()
		return

	# modo BESTIARIO: solo los retratos. La pasada completa tarda ~3 min y para
	# calibrar un shader eso es un peaje: se salta directo a la fase 10.
	if Session.autotest_mode == "bestiary":
		if _autotest_t > AT_BESTIARY_TIMEOUT_SEC:
			_at_capture("BESTIARIO TIMEOUT en el bicho %d" % _at_creature, 1)
			return
		if _at_phase == 0:
			# margen para que lleguen todos los spawns del mapa
			if _autotest_t < AT_SPAWN_SETTLE_SEC or _hero == null:
				return
			_at_free_camera = true
			_at_phase = 10
		_autotest_bestiary()
		return
	if _autotest_t > AT_LOOP_TIMEOUT_SEC:
		_at_capture("AUTOTEST TIMEOUT en fase %d" % _at_phase, 1)
		return
	match _at_phase:
		0:
			if _autotest_t > AT_START_DELAY_SEC and _hero != null:
				# el Vex mas cercano, no el NPC mas cercano: con cinco especies en
				# el mapa el vecino podia ser un Skarnox de 47 s de TTK y el
				# autotest se comia su propio limite de tiempo peleando
				var nearest := _best_prey()
				if nearest == null:
					# NO SE VE EL MAPA ENTERO.
					#
					# Con relevancia por rango el bot solo conoce lo que tiene a
					# 2000 unidades. Quedarse quieto esperando presa era una
					# moneda al aire: con 15 Vex repartidos en 20800x12800, la
					# probabilidad de tener uno a la vista al entrar es ~51%.
					# Patrullar es lo que haria un jugador, y de paso ejercita el
					# spawn/despawn por rango — que es justo lo que hay que probar.
					_at_patrol()
					return
				_at_target = nearest.entity_id
				_at_hunt_since = _autotest_t
				_at_hunt_dist = _hero.position.distance_to(nearest.position)
				_fly_to(nearest.position + AT_APPROACH_OFFSET)
				_at_phase = 1
		1:
			var vex: EntityNode = _entities.get(_at_target)
			if vex == null:
				_at_phase = 0     # se murio o despawneo: buscar otro
				return
			# Techo duro de la FASE, no de la presa. Reevaluar quita el runaway en
			# la practica, pero no lo prohibe: si ningun Vex se acercara nunca,
			# esto correria para siempre. Y un fallo con nombre —"la caza no
			# cerro en 45 s"— vale mil veces mas que un TIMEOUT generico, que no
			# dice en que se atasco ni por que.
			if _autotest_t - _at_hunt_since > AT_HUNT_TIMEOUT_SEC:
				_at_capture("AUTOTEST FALLO — la caza no logro ponerse a tiro en 45 s "
					+ "(nave 320 contra Vex 270: revisa velocidades o densidad de bichos)", 1)
				return

			# LA CAZA NO SE ATA A UNA PRESA.
			#
			# La nave vuela a 320 y un Vex vagabundea a 270: si el bicho elige un
			# destino que se aleja, la persecucion cierra a 50 unidades por
			# segundo. A 3.000 de distancia eso es un minuto — mas de lo que dura
			# la prueba entera. Ese era el timeout intermitente del gate.
			#
			# Abandonar a los 20 s no lo arreglaba, solo lo repartia: cada mala
			# eleccion costaba 20 s y dos seguidas se comian el reloj igual. Y
			# mientras el bot perseguia a uno que huia, podia pasarle otro Vex por
			# delante sin que se enterase, porque estaba atado a su presa.
			#
			# Ahora se reevalua: cada dos segundos se mira quien es el mas cercano
			# AHORA y se cambia si compensa. Con quince Vex vagabundeando, la
			# presa acaba viniendo sola — el bot deja de correr detras de uno y
			# pasa a quedarse con el que se acerque.
			if _autotest_t - _at_last_flight > AT_REROUTE_SEC:
				_at_last_flight = _autotest_t
				# `_mejor_presa` ya ordena por tiempo de intercepcion, asi que si
				# devuelve otra es que se llega antes a esa. El margen del 20% de
				# la version anterior sobra: no hay que evitar un baile entre
				# equidistantes, porque dos presas equidistantes con rumbos
				# distintos NO valen lo mismo.
				var other := _best_prey()
				if other != null and other.entity_id != _at_target:
					_at_target = other.entity_id
					vex = other
				if _hero.position.distance_to(vex.position) > AT_ENGAGE_DIST:
					_fly_to(vex.position + AT_APPROACH_OFFSET)
			if _hero.position.distance_to(vex.position) < AT_ENGAGE_DIST:
				_select(vex)
				_laser_on = true
				var msg := MexProtocol.LaserToggle.new()
				msg.active = true
				_conn.send(msg.encode())
				# el minimo teorico es (distancia - alcance) / velocidad de la nave:
				# si el tiempo real se le parece, no hay nada que arreglar — es viaje
				var t_min: float = maxf(_at_hunt_dist - AT_ENGAGE_DIST, 0.0) / maxf(_hero.speed, 1.0)
				print("AUTOTEST caza: %.1f s (presa inicial a %.0f u · minimo teorico %.1f s)"
					% [_autotest_t - _at_hunt_since, _at_hunt_dist, t_min])
				_at_phase = 2
		2:
			# captura extra a media pelea: sirve de QA visual del combate
			if not _at_shot_combat and _at_shots >= AT_COMBAT_SHOTS_FOR_PHOTO:
				_at_shot_combat = true
				var img_c := get_viewport().get_texture().get_image()
				img_c.save_png(Session.autotest_screenshot.replace(".png", "-combate.png"))
			# perseguir al objetivo si se aleja del rango del laser
			var npc_goal: EntityNode = _entities.get(_at_target)
			if npc_goal != null and _hero.attack_target == null:
				_hero.set_attack_target(npc_goal)
			if npc_goal != null and _hero.position.distance_to(npc_goal.position) > AT_ENGAGE_DIST \
					and _autotest_t - _at_last_flight > AT_REROUTE_SEC:
				_at_last_flight = _autotest_t
				_fly_to(npc_goal.position + AT_APPROACH_OFFSET)
			# _on_destroyed limpia la seleccion; la caja aparece via BoxSpawn y
			# el click-flujo se simula fijando el pending directamente
			if not _entities.has(_at_target):
				for id in _boxes:
					_pending_box = id
					_pending_box_pos = _boxes[id].position
					_fly_to(_pending_box_pos)
					_at_phase = 3
					return
		3:
			# retrato de la caja al llegar a su lado, ANTES de recogerla: es el
			# unico momento en que se la puede fotografiar. Se dispara a 520 y no
			# pegado: al llegar encima, la nave la tapa entera.
			if not _at_shot_box and _pending_box != 0 \
					and _hero.position.distance_to(_pending_box_pos) < AT_BOX_PHOTO_DIST:
				_at_shot_box = true
				var img_k := get_viewport().get_texture().get_image()
				img_k.save_png(Session.autotest_screenshot.replace(".png", "-caja.png"))
			# recogida hecha: volver a la base
			if _at_collected:
				_fly_to(_station_pos + AT_STATION_APPROACH_OFFSET)
				_at_phase = 4
		4:
			# se acerca de verdad a la estacion antes de descargar (asi la
			# captura del autotest sirve tambien para revisar su arte)
			if _at_base and _hero.position.distance_to(_station_pos) < AT_STATION_NEAR_DIST \
					and _autotest_t - _at_last_flight > AT_STEP_WAIT_SEC:
				# al ENTRAR en rango la Estacion se abre sola y sus acciones se
				# encienden; el icono de la taskbar tiene que enterarse
				if not _base.visible or not _taskbar.is_marked("estacion"):
					_at_capture("AUTOTEST FALLO — la Estacion no se abrio al llegar a la base", 1)
					return
				if not _base.active_actions():
					_at_capture("AUTOTEST FALLO — en la base y las acciones siguen bloqueadas", 1)
					return
				# retrato de la ESTACION. La fase decia desde siempre que servia
				# para revisar su arte y no guardaba nada; ahora si.
				var img_b := get_viewport().get_texture().get_image()
				img_b.save_png(Session.autotest_screenshot.replace(".png", "-base.png"))
				_at_last_flight = _autotest_t
				_req_id += 1
				var msg := MexProtocol.UnloadCargo.new()
				msg.request_id = _req_id
				_conn.send(msg.encode())
				_at_phase = 5
		5:
			# almacen recibido: vender el primer material que el NPC compre DE LOS
			# QUE HAY. Antes vendia "material_asterium" a ciegas y se colgaba la
			# tarde que los bichos no soltaban ese: la prueba esperaba para
			# siempre una confirmacion que no iba a llegar. Una prueba no puede
			# depender de que la suerte reparta un material concreto.
			if _at_unloaded and _autotest_t - _at_last_flight > AT_STEP_WAIT_SEC:
				_at_last_flight = _autotest_t
				var material := _base.first_sellable()
				if material == "":
					_at_capture("AUTOTEST FALLO — el almacen quedo sin nada que el NPC compre", 1)
					return
				_req_id += 1
				var sale := MexProtocol.SellToNpc.new()
				sale.request_id = _req_id
				sale.material_id = material
				sale.amount = 0            # todo
				_conn.send(sale.encode())
				_at_phase = 6
		6:
			# chat: se manda al canal GLOBAL y debe volver por el mismo socket
			if _at_sold and _autotest_t - _at_last_flight > AT_STEP_WAIT_SEC:
				_at_last_flight = _autotest_t
				_chat.focus_on()
				_chat.send_message.emit(0, "autotest: hola sector")
				_at_phase = 7
		7:
			# eco del chat recibido -> cortar la red y volver con el token
			if _at_chat_ok and _autotest_t - _at_last_flight > AT_STEP_WAIT_SEC:
				_at_last_flight = _autotest_t
				_conn.simulate_drop()
				_at_phase = 8
		8:
			# QA visual del portal: volar hasta el borde del mapa costaria ~50 s de
			# reloj, asi que se suelta la camara y se retrata en su sitio
			if _at_reconnected and _hero != null \
					and _autotest_t - _at_last_flight > AT_RECONNECT_WAIT_SEC:
				_at_last_flight = _autotest_t
				if _portals.is_empty():
					_at_capture("AUTOTEST FALLO — el mapa llego sin portales", 1)
					return
				_at_free_camera = true
				_focus = _portals.values()[0].position
				_at_phase = 9
		9:
			# retrato en REPOSO: con atlas, el aro dormido del primer fotograma
			if _autotest_t - _at_last_flight > AT_PORTAL_REST_SEC:
				var img_p := get_viewport().get_texture().get_image()
				img_p.save_png(Session.autotest_screenshot.replace(".png", "-portal.png"))
				_at_last_flight = _autotest_t
				_at_portal_animated = _portals.values()[0].activate()
				_at_phase = 90
		90:
			# ...y retrato ABIERTO, tras los 2,1 s del encendido. Una foto sola no
			# prueba nada: se comprueba que la secuencia llego a su ultimo
			# fotograma, que es donde el portal se queda al saltar.
			if _autotest_t - _at_last_flight > AT_PORTAL_OPEN_SEC:
				var img_a := get_viewport().get_texture().get_image()
				img_a.save_png(Session.autotest_screenshot.replace(".png", "-portal-abierto.png"))
				# el encendido es del MODELO desde la tarde del 1-sep (luces en
				# rampa + giro, 2,1 s): se afirma que llego a su final, que es
				# donde el portal se queda al saltar
				if not _at_portal_animated:
					_at_capture("AUTOTEST FALLO — el portal no arranco el encendido", 1)
					return
				if not _portals.values()[0].ignition_complete():
					_at_capture("AUTOTEST FALLO — el encendido del portal no llego al final", 1)
					return
				_at_phase = 10
		10:
			_autotest_bestiary()
		11:
			_at_free_camera = false
			# una ventana que no se construyo (error de script en su .gd) pasaba
			# desapercibida: el autotest seguia dando OK sin minimapa
			if _minimap == null or _chat == null or _base == null or _sysbar == null:
				_at_capture("AUTOTEST FALLO — falta una ventana (minimapa/chat/base/sysbar)", 1)
				return
			# la ventana de Ajustes se abre COMO LA ABRE EL JUGADOR, por el
			# engranaje: probar `alternar()` a pelo se saltaria justo el cableado
			# que puede romperse (el boton, la senial y el estado ambar)
			_toggle_settings()
			_at_last_flight = _autotest_t
			_at_phase = 92
		92:
			if _autotest_t - _at_last_flight > AT_SETTINGS_WAIT_SEC:
				var img_c := get_viewport().get_texture().get_image()
				img_c.save_png(Session.autotest_screenshot.replace(".png", "-ajustes.png"))
				if not _settings.visible:
					_at_capture("AUTOTEST FALLO — el engranaje no abrio los Ajustes", 1)
					return
				# el codigo de color del §1.3 es contrato, no adorno
				if not _sysbar.is_marked("ajustes"):
					_at_capture("AUTOTEST FALLO — el engranaje no se puso ambar", 1)
					return
				_toggle_settings()
				if _settings.visible:
					_at_capture("AUTOTEST FALLO — el engranaje no cierra los Ajustes", 1)
					return
				_at_phase = 94
		94:
			# La taskbar es lo que hace cierto el §1: "todo es ventana" solo vale
			# si se pueden REABRIR. Se prueba el ciclo entero —cerrar, comprobar
			# que el icono vuelve a neutro, reabrir— porque una ventana que se
			# cierra y no vuelve es peor que una que no se cierra.
			# El salto pedido de LEJOS tiene que ser rechazado por el server. Es
			# barato —no hay que volar 19.000 unidades— y prueba el cableado
			# entero: mensaje, ruta, validacion y ErrorReply de vuelta. El salto
			# que SI funciona se prueba en el modo -Salto, que si vuela.
			if not _at_jump_requested and not _portals.is_empty():
				_at_jump_requested = true
				_req_id += 1
				var far_away := MexProtocol.JumpRequest.new()
				far_away.request_id = _req_id
				far_away.portal_id = _portals.values()[0].portal_id
				_conn.send(far_away.encode())

			# Lejos de la base: la ventana se abre igual —para mirar el almacen—
			# pero descargar y vender siguen bloqueados. Que un boton exista y
			# este apagado ensenia que ahi hay algo; que la ventana desaparezca
			# no ensenia nada.
			if not _at_base:
				if not _base.visible:
					_toggle_window("estacion", _base)
				if not _base.visible:
					_at_capture("AUTOTEST FALLO — la Estacion no se abre lejos de la base", 1)
					return
				if _base.active_actions():
					_at_capture("AUTOTEST FALLO — se puede vender lejos de la base", 1)
					return
				_toggle_window("estacion", _base)

			_toggle_window("nave", _ship)
			if _ship.visible or _taskbar.is_marked("nave"):
				_at_capture("AUTOTEST FALLO — la taskbar no cerro la ventana Nave", 1)
				return
			_toggle_window("nave", _ship)
			if not _ship.visible or not _taskbar.is_marked("nave"):
				_at_capture("AUTOTEST FALLO — la taskbar no reabrio la ventana Nave", 1)
				return
			# §8: el minimapa NUNCA se deforma. Se recorren TODOS los pasos de
			# zoom porque el fallo era justo ese, y `deformacion()` se puede
			# comprobar en el acto: sale del tamanio que el minimapa se propone,
			# no del que el contenedor le acabe dando.
			#
			# Nada de `await` aqui dentro: esto corre desde `_process` y un await
			# convertiria la maquina de fases en una corrutina que devuelve el
			# control a media prueba. El chequeo que SI necesita layout
			# —`canvas_cuadra`— espera a la fase siguiente.
			for i in _minimap.zoom_steps():
				_minimap.zoom_to(i)
				if _minimap.deformation() > AT_MINIMAP_MAX_DEFORMATION:
					_at_capture("AUTOTEST FALLO — el minimapa se deforma en el paso %d (%.3f)"
						% [i, _minimap.deformation()], 1)
					return
			_minimap.zoom_to(AT_MINIMAP_ZOOM_STEP)
			_at_last_flight = _autotest_t
			_at_phase = 95
		95:
			if _autotest_t - _at_last_flight > AT_WINDOWS_WAIT_SEC:
				if not _at_jump_rejected:
					_at_capture("AUTOTEST FALLO — el server no rechazo un salto desde lejos", 1)
					return
				# ya hubo fotogramas de sobra para que el layout se asiente
				if not _minimap.canvas_fits():
					_at_capture("AUTOTEST FALLO — el canvas del minimapa no mide lo que dice", 1)
					return
				var img_t := get_viewport().get_texture().get_image()
				img_t.save_png(Session.autotest_screenshot.replace(".png", "-ventanas.png"))
				# ZOOM CERCANO. Nacio como zoom LEJANO, para ver si un render
				# aguanta de lejos; ahora el lejano es el zoom por defecto, asi
				# que TODAS las capturas ya son esa foto y esta se quedaba sin
				# decir nada. Se reapunta al otro extremo del rango calibrado,
				# que es el que ninguna otra prueba mira.
				#
				# Va en ZOOM_MAX y no en un numero suelto: la foto tiene que ser
				# del sitio mas cercano al que el jugador PUEDE llegar. Con un
				# valor a mano, el dia que se recalibre el rango la prueba
				# retrataria un encuadre que ya no existe, que es peor que no
				# retratar nada.
				_stage.zoom_direct(Stage3D.ZOOM_MAX)
				_at_phase = 96
		96:
			if _autotest_t - _at_last_flight > AT_ZOOM_WAIT_SEC:
				var img_z := get_viewport().get_texture().get_image()
				img_z.save_png(Session.autotest_screenshot.replace(".png", "-zoom.png"))
				_stage.zoom_direct(Stage3D.ZOOM_MIN)
				_at_phase = 93
		93:
			_at_capture("AUTOTEST OK — loop, chat, reconexion, portal, ajustes, ventanas, bestiario (%d especies) y %d muerte(s)"
				% [AT_BESTIARY.size(), _at_deaths], 0)


## El relieve solo vale para algo si la luz se queda quieta MIENTRAS la nave gira.
## Se comprueba en DOS mitades, y las dos son exactas:
##
##   FONTANERIA — girar la nave mueve el uniform `giro`. Se lee el numero, no se
##     miran pixeles: exacto y sin depender de como interpole nadie.
##   EFECTO — con la nave QUIETA en el mismo sitio, cambiar solo ese numero tiene
##     que cambiar los pixeles. Si el shader lo ignora, las dos fotos salen
##     identicas al bit.
##
## Juntas prueban la cadena entera. La version anterior comparaba dos fotos a
## rumbos distintos deshaciendo el giro, y funcionaba, pero el motor dibuja el
## sprite girado con filtrado bilineal: dos rumbos nunca son una rotacion exacta
## el uno del otro, y ese suelo dejaba un margen de 0,03 sobre una varianza de
## 0,06 entre corridas. Una prueba que depende de acertar el umbral entre dos
## numeros que se mueven no es una prueba, es una moneda al aire con ceremonia.
## Aqui no hay rotacion entre las dos fotos, asi que no hay suelo que esquivar.
##
## Devuelve 0 en curso · 1 pasada · 2 fallada (ya reportada).
## Cuanto cambio el retrato entre sus DOS fotogramas, como fraccion del brillo.
## Cero exacto = el bicho esta congelado.
##
## Se mide sobre la caja central y no sobre la pantalla entera: el campo de
## estrellas tiene paralaje y se mueve solo, asi que la pantalla siempre
## "cambia" y la medida no diria nada del bicho.
func _portrait_motion() -> float:
	var species_code: String = AT_BESTIARY[_at_creature]
	var a := _read_png(Session.autotest_screenshot.replace(".png", "-%s-alta.png" % species_code))
	var b := _read_png(Session.autotest_screenshot.replace(".png", "-%s-alta-b.png" % species_code))
	if a == null or b == null or a.get_size() != b.get_size():
		return NAN
	var w := a.get_width()
	var h := a.get_height()
	var diff := 0.0
	var brightness := 0.0
	for y in range(int(h * AT_CROP_Y_FROM), int(h * AT_CROP_Y_TO), AT_CROP_STEP):
		for x in range(int(w * AT_CROP_X_FROM), int(w * AT_CROP_X_TO), AT_CROP_STEP):
			var lum_a := a.get_pixel(x, y).get_luminance()
			var lb := b.get_pixel(x, y).get_luminance()
			diff += absf(lum_a - lb)
			brightness += lum_a
	return diff / maxf(brightness, AT_EPSILON)


func _read_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	return Image.load_from_file(path)


func _relief_step() -> int:
	# F1 del plan-cliente-3d: el relieve murio con los sprites. En la escena
	# unica la propiedad que esta prueba defendia —que la luz NO gire con la
	# nave— se cumple por construccion: gira el cuerpo dentro del mundo y la luz
	# direccional se queda quieta. `es_3d()` es true para todo cuerpo.
	return 1


## Cuanto se diferencian dos fotos del casco, como fraccion de su brillo medio.
## Las dos son de la nave en el MISMO sitio y el mismo rumbo, asi que aqui no hay
## rotacion ni remuestreo: si el shader ignorase `giro`, esto seria cero exacto.
func _hull_difference(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var diff := 0.0
	var brightness := 0.0
	var n := 0
	for i in a.size():
		var va: float = a[i]
		var vb: float = b[i]
		if is_nan(va) or is_nan(vb):
			continue
		diff += absf(va - vb)
		brightness += va
		n += 1
	if n < AT_RELIEF_MIN_SAMPLES or brightness <= AT_EPSILON:
		return NAN
	return diff / brightness


## La estacion como MALLA, directamente EN la escena unica (F1): ya no hay
## viewport intermedio ni camara propia — es una torre en el mundo y la camara
## a 45 grados le ensenia la altura sola, que es justo lo que su elevacion
## oblicua fingia antes. Devuelve false si no hay modelo y se cae al quad.
func _mount_station_3d(d: Dictionary) -> bool:
	var path := str(d.get("model", ""))
	if path == "" or not ResourceLoader.exists(path):
		return false
	var scene: PackedScene = load(path)
	if scene == null:
		push_warning("estacion: no se pudo cargar %s; se cae al quad" % path)
		return false
	_station_model = scene.instantiate()
	_station.add_child(_station_model)
	# `world_size` es la HUELLA (lo que rodea el anillo): se escala contra la
	# extension en planta del modelo, como los bichos.
	var ext := AssetDefs.extent_3d(_station_model)
	(_station_model as Node3D).scale = Vector3.ONE * (float(d.get("world_size", 820)) / ext)
	_station_mats = AssetDefs.materials_3d(_station_model)
	if _station_mats.is_empty():
		push_warning("estacion 3D sin materiales: la emision no va a latir")
	_station_emission = float(d.get("emission", STATION_EMISSION))
	var pulse_def: Dictionary = d.get("pulse", {})
	_station_pulse_min = float(pulse_def.get("min_intensity", STATION_PULSE_MIN))
	_station_pulse_max = float(pulse_def.get("max_intensity", STATION_PULSE_MAX))
	_station_pulse_speed = float(pulse_def.get("speed", STATION_PULSE_SPEED))
	_station_pulse_sharpness = float(pulse_def.get("sharpness", STATION_PULSE_SHARPNESS))
	return true


## Deja en el mundo SOLO al heroe, para las dos fotos de la prueba del relieve.
##
## Sin esto la comparacion no distingue nada, y el motivo es geometrico: al
## deshacer el giro de la nave, el FONDO queda girado — y el fondo no gira. Su
## diferencia entra igual en las dos mitades del cociente y lo empuja a 1 tanto si
## el relieve funciona como si no. Con la nave sola sobre negro, el negro no suma
## en ninguna de las dos y lo unico que se compara es el casco.
func _hero_only(is_active: bool) -> void:
	if _backdrop3d != null:
		_backdrop3d.visible = not is_active
	if _station != null:
		_station.visible = not is_active
	for e in _entities.values():
		if e != _hero:
			e.visible = not is_active
	for c in _boxes.values():
		c.visible = not is_active
	for pt in _portals.values():
		pt.visible = not is_active
	_hero.hull_only(is_active)


## El casco recortado en una caja centrada en la nave, en luminancia. NAN dentro
## si el pixel cae fuera de la pantalla.
func _hull_light() -> PackedFloat32Array:
	var img := get_viewport().get_texture().get_image()
	# `get_global_transform_with_canvas()` da coordenadas de LIENZO y la imagen
	# viene en pixeles FISICOS. Con `window/stretch/mode = canvas_items` no son lo
	# mismo: el lienzo mide 1370x720 y la ventana 1920x1009, un factor de 1,4. La
	# caja caia entera fuera de la nave, sobre campo de estrellas quieto — y dos
	# fotos de un fondo quieto salen identicas, que es exactamente lo que mide
	# "la luz no se movio". Un falso OK perfecto.
	var canvas_node := get_viewport_rect().size
	var k := Vector2(float(img.get_width()) / canvas_node.x, float(img.get_height()) / canvas_node.y)
	var center := _hero.get_global_transform_with_canvas().origin * k
	var out := PackedFloat32Array()
	out.resize(BOX * BOX)
	for y in BOX:
		for x in BOX:
			var px := Vector2i(int(center.x) + x - BOX / 2, int(center.y) + y - BOX / 2)
			var v := NAN
			if px.x >= 0 and px.y >= 0 and px.x < img.get_width() and px.y < img.get_height():
				v = img.get_pixelv(px).get_luminance()
			out[y * BOX + x] = v
	return out


## Compara dos fotos del casco a rumbos distintos DESHACIENDO el giro, y devuelve
## cuanto queda de diferencia respecto a compararlas sin deshacerlo.
##
## Es una prueba binaria por construccion, y ese fue el motivo de tirar la
## primera: medir "hacia donde cae el lado claro" parecia directo y no lo era,
## porque la propia textura tiene zonas claras que giran con la nave pase lo que
## pase, y esa senial tapaba a la del shader.
##
## Aqui no hay margen de interpretacion: si el relieve NO se contrarrota, la nave
## a 120 grados es EXACTAMENTE la misma imagen rotada 120 grados, asi que al
## deshacer el giro las dos fotos coinciden y el cociente se va a cero. Si la luz
## se queda quieta en el mundo, el sombreado cambia y no coinciden.
func _residue_on_unturn(a: PackedFloat32Array, b: PackedFloat32Array, degrees: float) -> float:
	var c := cos(deg_to_rad(degrees))
	var sn := sin(deg_to_rad(degrees))
	var half := float(BOX) / 2.0
	var rot_diff := 0.0
	var raw_diff := 0.0
	var n := 0
	for y in BOX:
		for x in BOX:
			var va: float = a[y * BOX + x]
			if is_nan(va):
				continue
			# el punto de A aparece GIRADO en B: se busca alli
			var p := Vector2(float(x) - half, float(y) - half)
			var q := Vector2(p.x * c - p.y * sn, p.x * sn + p.y * c) + Vector2(half, half)
			var qi := Vector2i(int(round(q.x)), int(round(q.y)))
			if qi.x < 0 or qi.y < 0 or qi.x >= BOX or qi.y >= BOX:
				continue
			var vb: float = b[qi.y * BOX + qi.x]
			var raw_vb: float = b[y * BOX + x]
			if is_nan(vb) or is_nan(raw_vb):
				continue
			rot_diff += absf(va - vb)
			raw_diff += absf(va - raw_vb)
			n += 1
	if n < AT_RELIEF_MIN_SAMPLES or raw_diff <= AT_EPSILON:
		return NAN
	return rot_diff / raw_diff


## Especies de caza del autotest: las dos comunes y flojas. Ampliarlo de solo
## `vex` a `vex` + `vexor` sube la densidad de presa de 15 a 23 en el 1-1, y ya
## no hay motivo para exigir una especie concreta — desde que la venta pregunta
## al almacen que hay, al bot le sirve cualquier caja.
static var AT_PREY: Array = _strings(AT_CFG.get("prey"), ["vex", "vexor"])

## Lado de la caja con la que se retrata el casco para la prueba del relieve.
static var RELIEF_CFG: Dictionary = AT_CFG.get("relief", {})
static var BOX: int = int(AssetDefs.num(RELIEF_CFG, "box_px", 128))

## Margen del encuadre de la estacion y ELEVACION de su camara, en grados: 90 es
## cenital y por debajo empieza el escorzo.
##
## La estacion es el unico asset que NO se mira desde arriba, y es una decision
## de direccion de arte, no un descuido: es una torre, y una torre vista en
## cenital es un punto. El resto del juego sigue siendo cenital.
##
## Al bajarla hay que encuadrar con `extension_vista` y no con la huella: la
## altura pasa a ocupar pantalla y con la huella la torre se sale por arriba.
static var STATION_CFG: Dictionary = CFG.get("station", {})
static var STATION_MARGIN: float = AssetDefs.num(STATION_CFG, "margin", 1.15)
static var STATION_ELEVATION: float = AssetDefs.num(STATION_CFG, "elevation_deg", 30.0)
## Altura del anillo de la zona segura y el latido de la emision por defecto (la
## ficha data/props/station.json manda cuando trae `emission`/`pulse`).
static var STATION_RING_HEIGHT: float = AssetDefs.num(STATION_CFG, "ring_height", 1.0)
static var STATION_EMISSION: float = AssetDefs.num(STATION_CFG, "emission", 1.0)
static var STATION_PULSE_CFG: Dictionary = STATION_CFG.get("pulse", {})
static var STATION_PULSE_MIN: float = AssetDefs.num(STATION_PULSE_CFG, "min_intensity", 0.55)
static var STATION_PULSE_MAX: float = AssetDefs.num(STATION_PULSE_CFG, "max_intensity", 1.8)
static var STATION_PULSE_SPEED: float = AssetDefs.num(STATION_PULSE_CFG, "speed", 1.1)
static var STATION_PULSE_SHARPNESS: float = AssetDefs.num(STATION_PULSE_CFG, "sharpness", 1.6)

## Por debajo de esto un bicho se considera QUIETO entre sus dos retratos. Es un
## suelo de ruido, no un objetivo: dos capturas del mismo fotograma dan 0 exacto.
static var MIN_MOVE: float = AssetDefs.num(AT_PORTRAIT_CFG, "min_move", 0.004)

## Fotogramas de asiento antes de la primera foto del relieve.
static var SETTLE: int = int(AssetDefs.num(RELIEF_CFG, "settle_frames", 3))
## Cuanto se gira la nave (y cuanto se le miente la luz) durante la prueba.
static var RELIEF_SPIN: float = AssetDefs.num(RELIEF_CFG, "spin_deg", 90.0)
## Cuanto tienen que moverse los pixeles al mentirle la luz al shader. El umbral
## puede ser ridiculamente bajo porque el caso roto es CERO EXACTO: misma nave,
## mismo sitio, mismo rumbo, solo cambia un uniform que se estaria ignorando.
static var MIN_EFFECT: float = AssetDefs.num(RELIEF_CFG, "min_effect", 0.02)
static var AT_RELIEF_MIN_SAMPLES: int = int(AssetDefs.num(RELIEF_CFG, "min_samples", 400))
static var AT_EPSILON: float = AssetDefs.num(RELIEF_CFG, "epsilon", 0.0001)


## La mejor presa NO es la mas cercana: es a la que se llega antes.
##
## Elegir por distancia es la peor metrica posible cuando la presa huye. La nave
## vuela a 320 y un Vex vagabundea a 270, asi que uno que se aleja cierra a 50
## unidades por segundo y otro un poco mas lejos que VIENE hacia ti cierra a 590
## — once veces mas rapido. Por distancia se elige siempre al peor de los dos.
##
## Aqui se calcula el tiempo real de ponerse a tiro, que se puede saber porque el
## nodo conoce su `objetivo` y su `speed`: la velocidad de acercamiento es la de
## la nave menos la componente de la presa en la linea que las une. Si esa
## componente iguala o supera a la nave, la presa es inalcanzable y se descarta
## en vez de perseguirla.
## Itinerario de patrulla: un recorrido FIJO por el sector, no puntos al azar.
## Un fallo del gate tiene que poder repetirse, y con destinos sorteados cada
## corrida barre un mapa distinto. Volando a 320 con 2000 de rango, cada tramo
## peina un pasillo de 4000 de ancho: con quince Vex sueltos, el primero suele
## aparecer antes de terminar el primer tramo.
static var AT_PATROL_CFG: Dictionary = AT_CFG.get("patrol", {})
static var AT_PATROL: Array[Vector2] = _vec2_list(AT_PATROL_CFG.get("waypoints"), [
	Vector2(4000, 3000), Vector2(16000, 3000), Vector2(16000, 9500),
	Vector2(4000, 9500), Vector2(10400, 6400),
])
static var AT_PATROL_ARRIVE_DIST: float = AssetDefs.num(AT_PATROL_CFG, "arrive_dist", 400.0)


## Lista de strings desde un JSON (la de respaldo si falta o esta vacia).
static func _strings(v: Variant, fallback: Array) -> Array:
	if typeof(v) == TYPE_ARRAY and not (v as Array).is_empty():
		return v as Array
	return fallback


## Lista de Vector2 desde un JSON `[[x, y], ...]` (la de respaldo si falta).
static func _vec2_list(v: Variant, fallback: Array[Vector2]) -> Array[Vector2]:
	if typeof(v) != TYPE_ARRAY or (v as Array).is_empty():
		return fallback
	var out: Array[Vector2] = []
	for p in v:
		out.append(AssetDefs.vec2(p))
	return out

var _at_patrol_i := -1


func _at_patrol() -> void:
	if _at_patrol_i >= 0 and _hero.position.distance_to(_at_patrol_dest()) > AT_PATROL_ARRIVE_DIST:
		return                            # sigue en camino al waypoint actual
	_at_patrol_i = (_at_patrol_i + 1) % AT_PATROL.size()
	_fly_to(_at_patrol_dest())


func _at_patrol_dest() -> Vector2:
	return AT_PATROL[_at_patrol_i].clamp(Vector2.ZERO, _bounds)


func _best_prey() -> EntityNode:
	var chosen: EntityNode = null
	var better := INF
	for id in _entities:
		var e: EntityNode = _entities[id]
		if not AT_PREY.has(e.type_id):
			continue
		var towards := e.position - _hero.position
		var d := towards.length()
		if d <= AT_ENGAGE_DIST:
			return e                      # ya esta a tiro: no hay nada mejor
		var dir := towards / d
		var v := Vector2.ZERO
		if e.speed > 0.0 and e.goal.distance_to(e.position) > GOAL_REACHED_DIST:
			v = (e.goal - e.position).normalized() * e.speed
		var closure := _hero.speed - v.dot(dir)
		if closure <= AT_MIN_CLOSURE_SPEED:
			continue                      # huye tan rapido como volamos: inalcanzable
		var t := (d - AT_ENGAGE_DIST) / closure
		if t < better:
			better = t
			chosen = e
	# si todas huyen, quedarse con la mas cercana: peor plan que ninguno, y con
	# quince vagabundos alguna cambiara de rumbo en breve
	if chosen == null:
		for id in _entities:
			var e2: EntityNode = _entities[id]
			if not AT_PREY.has(e2.type_id):
				continue
			var d2 := _hero.position.distance_to(e2.position)
			if d2 < better:
				better = d2
				chosen = e2
	return chosen


## El salto de sector, de punta a punta: volar al portal, cruzarlo, y comprobar
## que se llego a OTRO mapa con la nave entera.
func _autotest_jump() -> void:
	if _autotest_t > AT_JUMP_TIMEOUT_SEC:
		_at_capture("SALTO TIMEOUT en la fase %d (mapa %s)" % [_at_phase, _map_code], 1)
		return
	match _at_phase:
		0:
			if _portals.is_empty() or _hero == null:
				return
			_at_jump_origin = _map_code
			_at_jump_portal = _portals.values()[0]
			_at_jump_dest = _at_jump_portal.target_map_code
			# como el jugador: clic en el portal deja AUTOPILOTO puesto, y era eso
			# —no el vuelo— lo que sobrevivia al salto y tiraba de la nave al llegar
			_on_autopilot(_at_jump_portal.position)
			_at_last_flight = _autotest_t
			_at_phase = 1
		1:
			# reencaminar cada 2 s: el clamp del server y la deriva hacen que un
			# solo `volar_a` se quede corto en un viaje tan largo
			if _autotest_t - _at_last_flight > AT_REROUTE_SEC:
				_at_last_flight = _autotest_t
				_fly_to(_at_jump_portal.position)
			if _hero.position.distance_to(_at_jump_portal.position) < AT_JUMP_PORTAL_NEAR_DIST:
				var img := get_viewport().get_texture().get_image()
				img.save_png(Session.autotest_screenshot.replace(".png", "-salto-antes.png"))
				# Se salta EN MARCHA, con un destino lejos y sin alcanzar. Es el
				# caso real —se huye, se pulsa J sin soltar el raton— y es el
				# unico que reproduce el fallo: volando justo hasta el portal, el
				# autopiloto se completa y se limpia solo antes de saltar, asi
				# que la prueba pasaba aunque el arreglo no estuviera.
				_on_autopilot(_bounds - Vector2.ONE * AT_JUMP_FAR_INSET)
				# y con el boton SOSTENIDO apuntando lejos, que es como se salta
				# huyendo: eso es lo que seguia mandando destinos del mapa viejo
				# por el socket del mapa nuevo
				_at_cursor = _bounds - Vector2.ONE * AT_JUMP_CURSOR_INSET
				_hold_move = true
				_hold_timer = 0.0
				# por el camino DEL JUGADOR, no mandando el mensaje a mano: asi la
				# prueba cubre el encendido, la espera y la medida del viaje
				_try_jump()
				_at_last_flight = _autotest_t
				_at_phase = 2
		2:
			if _map_code == _at_jump_dest and _hero != null:
				_at_jump_arrival = _hero.position
				# EN EL INSTANTE de llegar: un fotograma despues el lerp ya habria
				# alcanzado y la comprobacion no probaria nada
				_at_jump_camera = _focus.distance_to(_hero.position)
				_at_cursor = Vector2.INF     # se suelta el boton al llegar
				_hold_move = false
				_at_last_flight = _autotest_t
				_at_phase = 3
			elif _autotest_t - _at_last_flight > AT_JUMP_ARRIVAL_TIMEOUT_SEC:
				_at_capture("SALTO FALLO — se pidio el salto y el mapa sigue siendo %s" % _map_code, 1)
		3:
			if _autotest_t - _at_last_flight < AT_JUMP_SETTLE_SEC:
				return
			var img2 := get_viewport().get_texture().get_image()
			img2.save_png(Session.autotest_screenshot.replace(".png", "-salto-despues.png"))
			# llegar a otro mapa no basta: hay que llegar ENTERO y en su sitio
			if _hero == null:
				_at_capture("SALTO FALLO — se llego a %s sin nave" % _map_code, 1)
				return
			if _portals.is_empty():
				_at_capture("SALTO FALLO — %s llego sin portales: no habria vuelta" % _map_code, 1)
				return
			# la nave tiene que seguir DONDE ATERRIZO, no arrastrada por un destino
			# del mapa anterior
			# 200 unidades de margen, no 900. La nave vuela a 320 u/s: en el segundo
			# y medio que se observa recorre 480 si algo tira de ella, asi que un
			# umbral de 900 no distingue "quieta" de "arrastrada" — con el puesto,
			# esta misma prueba daba OK con el fallo dentro.
			# la camara tiene que estar SOBRE la nave nada mas llegar: si se quedo
			# cruzando desde el mapa viejo, el cursor apunta a coordenadas de otro
			# sitio y el vuelo sostenido manda la nave alli
			if _at_jump_camera > AT_JUMP_MAX_CAMERA_DIST:
				_at_capture("SALTO FALLO — al llegar, la camara estaba a %d unidades de la nave"
					% _at_jump_camera, 1)
				return
			var far_away := _hero.position.distance_to(_at_jump_arrival)
			if far_away > AT_JUMP_MAX_DRIFT:
				_at_capture("SALTO FALLO — aterrizo en (%d, %d) y se fue a (%d, %d): %d unidades"
					% [_at_jump_arrival.x, _at_jump_arrival.y,
					   _hero.position.x, _hero.position.y, far_away], 1)
				return
			var returned := false
			for id in _portals:
				if _portals[id].target_map_code == _at_jump_origin:
					returned = true
			if not returned:
				_at_capture("SALTO FALLO — %s no tiene portal de vuelta a %s"
					% [_map_code, _at_jump_origin], 1)
				return
			_at_capture("SALTO OK — %s -> %s, nave en (%d, %d), %d portales y vuelta a casa"
				% [_at_jump_origin, _map_code, _hero.position.x, _hero.position.y,
				   _portals.size()], 0)


## Retrato de cada bicho del bestiario: la camara los visita sin volar hasta
## ellos. Agregar un alien = agregarlo a AT_BESTIARIO, nada mas.
## Lo comparten los dos modos: en "loop" es la ultima fase, en "bestiary" es
## la unica.
func _autotest_bestiary() -> void:
	if _at_creature >= AT_BESTIARY.size():
		if Session.autotest_mode == "bestiary":
			# Prueba del cambio EN CALIENTE: se baja la calidad con el mundo ya
			# poblado y se retrata. Si reconstruir rompiera algo, revienta aqui.
			if Session.forced_quality == "" and not _at_quality_change:
				_at_quality_change = true
				_at_previous_quality = Quality.preset
				Quality.apply("baja")
				_at_camera_t = _autotest_t
				return
			if _at_quality_change and _autotest_t - _at_camera_t < AT_QUALITY_CHANGE_WAIT_SEC:
				return
			if _at_quality_change:
				_portrait("cambio-calidad", "")
				# y se DEVUELVE a donde estaba: una prueba que deja residuo
				# persistente contamina todas las corridas siguientes
				Quality.apply(_at_previous_quality)
			# RELIEVE: que la luz NO gire con la nave. Vive en el bestiario y no
			# en el loop porque es una prueba de ARTE, y el bestiario existe
			# justo para eso — pagar tres minutos de loop para mirar un shader
			# es el peaje que nadie acaba pagando, y una prueba que no se corre
			# no es una prueba.
			var relief := _relief_step()
			if relief == 0:
				return          # aun midiendo
			if relief == 2:
				return          # fallo, ya reportado
			_at_free_camera = false
			# QUIETOS: los que no se movieron entre sus dos retratos. Se reporta la
			# lista, no se falla: hay bichos que legitimamente no animan, y el
			# umbral bueno todavia no esta medido en las nueve especies. Lo que no
			# puede seguir pasando es que nadie se entere.
			var still_ones: Array[String] = []
			var detail_text: Array[String] = []
			for species_code in _at_creature_move:
				var m: float = _at_creature_move[species_code]
				detail_text.append("%s %.3f" % [species_code, m])
				if m < MIN_MOVE:
					still_ones.append(str(species_code))
			print("MOVIMIENTO por especie: %s" % ", ".join(detail_text))
			_at_capture("BESTIARIO OK — %d retratos%s · relieve (efecto %.3f) · quietos: %s"
				% [AT_BESTIARY.size(),
				" + cambio de calidad en caliente" if _at_quality_change else "",
				_at_relief_rest,
				"ninguno" if still_ones.is_empty() else ", ".join(still_ones)], 0)
		else:
			_at_phase = 11
		return
	var species: String = AT_BESTIARY[_at_creature]
	var creature := _first_of_species(species)
	if creature == null:
		# EL BESTIARIO YA NO DEPENDE DE LO QUE HAYA EN EL MAPA.
		#
		# Es una prueba de ARTE: lo que demuestra es que el sprite, el shader y
		# las etiquetas de cada especie se montan bien. Que hubiera un ejemplar
		# de las nueve a la vista era andamio del 1-1 de pruebas, y se cayo por
		# dos sitios a la vez: la relevancia por rango solo deja ver ~2000
		# unidades, y el diseno del sector manda 3-4 especies por mapa (a veces
		# una). Retratar las nueve NUNCA iba a poder salir del mundo.
		#
		# Asi que se fabrica el ejemplar aqui, con el mismo `EntityNode` y el
		# mismo JSON de assets que usa el juego: lo que se retrata es
		# exactamente lo que se veria volando.
		#
		# UNO por especie, no uno por fotograma. Esta rama corre en CADA frame
		# de los ~2 s que dura el retrato: crear aqui sin comprobar dejaba un
		# centenar de maniquies apilados en el mismo punto, y en la foto se leian
		# las etiquetas de la especie anterior por debajo de la nueva.
		if _at_dummy == null or _at_dummy.type_id != species:
			_release_dummy()
			_at_dummy = _dummy_of_species(species)
		creature = _at_dummy
	_focus = creature.position
	if _at_camera_t < 0.0:
		_at_camera_t = _autotest_t
	var dt := _autotest_t - _at_camera_t
	# En modo arte se toma un SEGUNDO fotograma casi un segundo despues del
	# primero: una foto fija no demuestra que un shader se MUEVA, con dos se
	# compara. En la pasada del loop sobra — ahi solo se comprueba que existan.
	var two_frames := Session.autotest_mode == "bestiary"
	if not _at_first_frame:
		if dt <= AT_FIRST_FRAME_SEC:
			return
		_at_first_frame = true
		_portrait(species, "")
		if two_frames:
			return
	elif dt <= AT_SECOND_FRAME_SEC:
		return
	else:
		_portrait(species, "-b")
		# Y AQUI SE AFIRMA que se movio. Las dos fotos ya se tomaban —el
		# comentario de arriba lo dice— pero solo se guardaban: comparar quedaba
		# para el ojo de quien las mirase, y nadie las mira una por una.
		#
		# Es la averia que se colo con el Vorax: sus ocho brazos no se movian
		# porque el cliente mapeaba una lista FIJA de nombres de hueso y los
		# `brazo_*` no estaban. En la foto se veia un bicho perfecto, con sus
		# brazos en pose de reposo, y la pose de reposo de un bicho radial no se
		# distingue de una pose animada mirando UN fotograma.
		var mov := _portrait_motion()
		if not is_nan(mov):
			_at_creature_move[species] = mov
	_release_dummy()
	_at_camera_t = -1.0
	_at_first_frame = false
	_at_creature += 1


func _portrait(species: String, suffix: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if Session.forced_quality != "":
		suffix = "-" + Session.forced_quality + suffix
	img.save_png(Session.autotest_screenshot.replace(".png", "-%s%s.png" % [species, suffix]))


## Suelta el ejemplar fabricado, si lo hubo. No vive en `_entidades`: no es del
## mundo, es del retrato.
func _release_dummy() -> void:
	if _at_dummy != null:
		_at_dummy.queue_free()
		_at_dummy = null


## Un ejemplar de laboratorio para el retrato, cuando la especie no anda cerca.
## Se arma con un `EntitySpawn` de verdad para que pase por el MISMO `setup` que
## cualquier bicho del mundo: si el retrato saliera de un camino distinto, no
## probaria lo que se cree que prueba.
func _dummy_of_species(code: String) -> EntityNode:
	var sp := MexProtocol.EntitySpawn.new()
	sp.entity_id = 0
	sp.kind = MexProtocol.EntityKind.NPC
	sp.type_id = code
	sp.name = code.capitalize()
	sp.faction = 0
	# lejos del heroe y de la estacion, para que nada se cuele en el encuadre
	sp.x = int(_bounds.x * AT_DUMMY_POS_FRACTION.x)
	sp.y = int(_bounds.y * AT_DUMMY_POS_FRACTION.y)
	sp.hp_pct = 1.0
	sp.shield_pct = 1.0
	sp.speed = 0
	var node := EntityNode.new()
	node.heading_frozen = true     # retrato reproducible: proa al norte, sin giro perezoso
	node.setup(sp, false)
	add_child(node)
	return node


## Primer NPC de una especie, para los retratos de QA del autotest.
func _first_of_species(code: String) -> EntityNode:
	for id in _entities:
		var e: EntityNode = _entities[id]
		if e.type_id == code:
			return e
	return null


func _at_capture(message: String, code_str: int) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(Session.autotest_screenshot)
	print(message, " · captura en ", Session.autotest_screenshot)
	get_tree().quit(code_str)


static func _thousands(n) -> String:
	# separador de miles con punto (firma del sistema N)
	var s := str(int(n))
	var output := ""
	var tally := 0
	for i in range(s.length() - 1, -1, -1):
		output = s[i] + output
		tally += 1
		if tally % 3 == 0 and i > 0:
			output = "." + output
	return output
