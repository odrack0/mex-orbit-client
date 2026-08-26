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
var _fondo: MapBackground
var _seq := 0
var _limites := Vector2(20800, 12800)

# vuelo sostenido (herencia del prototipo)
var _hold_move := false
var _hold_timer := 0.0
var _last_sent_target := Vector2.INF
var _seleccionada := 0        # entity_id con seleccion local

# combate y loot (E2/I5)
const COLLECT_ARRIVE := 200.0     # llegar a esto de la caja = recolectar (server valida 250)
const AUTOPILOT_ARRIVE := 120.0   # a esta distancia el autopiloto declara llegada

# autopiloto del minimapa (herencia del prototipo): destino sostenido que se
# reemite si el heroe queda detenido sin llegar; el vuelo manual lo cancela
var _autopilot := Vector2.INF
var _minimapa: MinimapWindow

# la base (E2/I6)
var _base: StationPanel
var _chat: ChatWindow
var _ajustes: SettingsWindow
var _sysbar: SysBar
var _respawn: RespawnPanel
var _muerto := false
var _estacion_pos := Vector2.ZERO
var _estacion_rango := 0.0
var _en_base := false
var _estacion: Sprite2D
var _estacion_reactor: Sprite2D
var _reactor_min := 0.55
var _reactor_max := 1.8
var _reactor_speed := 1.1
var _reactor_sharp := 1.6
var _laser_on := false
var _cajas := {}                  # box_id -> Sprite2D
var _caja_anim_total := 0         # >0 = la caja es un atlas animado
var _caja_anim_fps := 12.0
var _portales := {}               # portal_id -> PortalNode
var _pending_box := 0             # flujo del prototipo: volar a la caja y recoger al llegar
var _pending_box_pos := Vector2.ZERO
var _req_id := 0
var _frames_explosion: SpriteFrames

# HUD (sistema N minimo de la iteracion: panel de nave + estado del enlace)
var _hud_estado: Label
var _nave: ShipWindow
var _taskbar: Taskbar

# autotest: vuela solo y guarda captura
var _autotest_t := 0.0


func _ready() -> void:
	# la calidad se carga antes de construir nada: es POR CUENTA, asi que hasta
	# aqui no se sabia de quien son los ajustes
	Quality.cargar(Session.account_id)
	if Session.calidad_forzada != "":
		Quality.niveles = Quality.PRESETS[Session.calidad_forzada].duplicate()
		Quality.preset = Session.calidad_forzada
	elif Session.autotest_modo != "":
		# Una prueba NO puede heredar estado de la corrida anterior. La del cambio
		# en caliente dejaba la cuenta en "baja" de forma persistente, asi que las
		# siguientes corrian degradadas sin decirlo: el portal montaba su camino
		# fijo y la afirmacion del atlas se saltaba sola, dando OK sin probar nada.
		# Sin -Calidad, el autotest arranca SIEMPRE en alta.
		Quality.niveles = Quality.PRESETS["alta"].duplicate()
		Quality.preset = "alta"
	Quality.cambiada.connect(_on_calidad_cambiada)

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
	_conn.error_reply.connect(_on_error)
	_conn.chat_message.connect(_on_chat)
	_conn.resume_ok.connect(_on_resume_ok)
	_conn.session_replaced.connect(_on_session_replaced)
	_conn.disconnected.connect(_on_disconnected)


	# la explosion del pipeline: 8 frames de 128
	_frames_explosion = SpriteFrames.new()
	_frames_explosion.add_animation("boom")
	_frames_explosion.set_animation_loop("boom", false)
	_frames_explosion.set_animation_speed("boom", 16.0)
	var hoja: Texture2D = load("res://assets/fx/explosion-sheet.png")
	for i in 8:
		var frame := AtlasTexture.new()
		frame.atlas = hoja
		frame.region = Rect2(i * 128, 0, 128, 128)
		_frames_explosion.add_frame("boom", frame)

	_camara = Camera2D.new()
	add_child(_camara)
	_construir_hud()
	_estado("Abriendo enlace con %s..." % Session.game_host, NTheme.MUTED)
	_conn.connect_to(Session.game_host, Session.game_ticket)


func _construir_fondo(map_code: String) -> void:
	if _fondo != null:
		return                     # una reconexion reenvia EnterMap: no duplicar capas
	# el stack de capas del prototipo: mosaicos + fondo principal + planetas
	# + sol con lentes + polvo estelar, todos con su paralaje propio
	_fondo = MapBackground.new()
	add_child(_fondo)
	_fondo.build(MapBgConfig.para(map_code, _limites))


func _construir_hud() -> void:
	var capa := CanvasLayer.new()
	add_child(capa)

	# La NAVE deja de ser un panel suelto con cinco etiquetas y pasa a ser una
	# ventana de verdad, con las barras segmentadas del §7. Una barra dice cuanto
	# queda DE LO QUE HABIA, que es lo que se lee de un vistazo en combate.
	_nave = ShipWindow.crear()
	capa.add_child(_nave)
	# debajo de la taskbar (8 de margen + 44 de boton + 8 de aire), no encima
	if not _nave.cargar_posicion():
		_nave.position = Vector2(12, 8 + Taskbar.LADO + 10)

	# la linea de estado vive abajo al CENTRO: las esquinas son del chat y del
	# minimapa, y antes se pisaban entre si
	_hud_estado = NTheme.label("", NTheme.exo2(), 12, NTheme.MUTED)
	_hud_estado.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_estado.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hud_estado.offset_left = 430
	_hud_estado.offset_right = -430
	_hud_estado.offset_top = -34
	_hud_estado.offset_bottom = -14
	capa.add_child(_hud_estado)


func _estado(texto: String, color: Color) -> void:
	_hud_estado.text = texto
	_hud_estado.add_theme_color_override("font_color", color)


func _on_welcome(w) -> void:
	_conn.reconnect_token = w.reconnect_token      # con esto se vuelve tras una caída
	_reintentos = 0
	_estado("Enlace establecido · cuenta %d · tick %d Hz" % [w.account_id, w.tick_rate], NTheme.CYAN)
	if _chat != null:
		_chat.add_system("Enlace establecido con el sector")


# ---- reconexión (ventana de gracia del server: 60 s) ----
const MAX_REINTENTOS := 8
var _reintentos := 0
var _sesion_reemplazada := false


func _on_disconnected() -> void:
	if _sesion_reemplazada:
		return                                     # nos echaron: no insistir
	if _conn.reconnect_token == "" or _reintentos >= MAX_REINTENTOS:
		_estado("Enlace perdido", NTheme.HOSTILE)
		return
	_reintentos += 1
	_estado("Enlace perdido · reconectando (%d/%d)…" % [_reintentos, MAX_REINTENTOS], NTheme.WARN)
	if _chat != null:
		_chat.add_system("Enlace perdido, reconectando…", NTheme.WARN)
	# reintento con espera creciente, dentro de la ventana de gracia
	await get_tree().create_timer(minf(1.0 * _reintentos, 5.0)).timeout
	_conn.reconnect()


func _on_resume_ok() -> void:
	# el server nos devolvió nuestra nave: se limpia el mundo local y se
	# reconstruye con la re-sincronización que viene detrás
	for id in _entidades:
		_entidades[id].queue_free()
	_entidades.clear()
	for id in _cajas:
		_cajas[id].queue_free()
	_cajas.clear()
	_hero = null
	_seleccionada = 0
	_laser_on = false
	_reintentos = 0
	_at_reconectado = true
	_estado("Reconectado: seguías en vuelo", NTheme.HP)
	if _chat != null:
		_chat.add_system("Reconectado: tu nave seguía en el sector", NTheme.HP)


func _on_session_replaced() -> void:
	_sesion_reemplazada = true
	_estado("Sesión reemplazada por otra conexión", NTheme.WARN)
	if _chat != null:
		_chat.add_system("Otra conexión tomó esta cuenta", NTheme.WARN)


func _on_chat(msg) -> void:
	_at_chat_ok = true
	if _chat != null:
		_chat.add_message(msg.channel, msg.from_name, msg.text)


var _map_code := ""


func _on_enter_map(em) -> void:
	_limites = Vector2(em.limits_x, em.limits_y)
	_map_code = em.map_code
	_estacion_pos = Vector2(em.station_x, em.station_y)
	_estacion_rango = float(em.station_range)
	_construir_fondo(em.map_code)
	_construir_estacion()
	_construir_portales(em.portals)
	_construir_minimapa(em.map_code)
	_construir_base()
	_construir_chat()
	_construir_respawn()
	_construir_ajustes()
	_estado("Sector %s (%dx%d) · riesgo de carga %d%%"
		% [em.map_code, em.limits_x, em.limits_y, em.cargo_risk_pct], NTheme.MUTED)


func _construir_minimapa(map_code: String) -> void:
	if _minimapa != null:
		return
	var capa := CanvasLayer.new()
	capa.layer = 11
	add_child(capa)
	_minimapa = MinimapWindow.new()
	capa.add_child(_minimapa)
	_minimapa.setup(self, map_code)
	_minimapa.fly_to.connect(_on_autopilot)


## Los portales del mapa: llegan COMPLETOS en EnterMap (no por relevancia), con
## su posicion y su destino desde BD. Aqui solo se instancian.
func _construir_portales(portales: Array) -> void:
	if not _portales.is_empty():
		return                     # EnterMap puede repetirse al reconectar
	for p in portales:
		var nodo := PortalNode.new()
		nodo.setup(p)
		add_child(nodo)
		_portales[nodo.portal_id] = nodo


func _construir_estacion() -> void:
	if _estacion != null:
		return                     # idem: EnterMap puede repetirse al reconectar
	# la estacion y su zona segura, con las particularidades de su JSON
	var d := AssetDefs.prop("station")
	var aro: Dictionary = d.get("safe_ring", {})
	var color_aro := AssetDefs.color(aro.get("color", "00E5FF"), NTheme.CYAN)
	var alfa_aro: float = float(aro.get("alpha", 0.22))
	var grosor_aro: float = float(aro.get("width", 3.0))

	var anillo := Node2D.new()
	anillo.position = _estacion_pos
	anillo.z_index = -1
	anillo.draw.connect(func():
		anillo.draw_arc(Vector2.ZERO, _estacion_rango, 0, TAU, 96,
			Color(color_aro, alfa_aro), grosor_aro))
	add_child(anillo)
	anillo.queue_redraw()

	_estacion = Sprite2D.new()
	_estacion.texture = load(d.get("texture", "res://assets/world/station.png"))
	_estacion.position = _estacion_pos
	# tamaño en unidades de MUNDO segun el JSON, sea cual sea la resolucion del render
	var lado := float(_estacion.texture.get_width())
	_estacion.scale = Vector2.ONE * (float(d.get("world_size", 820)) / lado)
	_estacion.z_index = -1
	add_child(_estacion)

	# el reactor late con su capa emisiva (mas lento y suave que un alien)
	if d.has("emissive"):
		_estacion_reactor = Sprite2D.new()
		_estacion_reactor.texture = load(d.emissive)
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_estacion_reactor.material = mat
		_estacion.add_child(_estacion_reactor)
		var p: Dictionary = d.get("pulse", {})
		_reactor_min = float(p.get("min_intensity", 0.55))
		_reactor_max = float(p.get("max_intensity", 1.8))
		_reactor_speed = float(p.get("speed", 1.1))
		_reactor_sharp = float(p.get("sharpness", 1.6))


func _construir_base() -> void:
	if _base != null:
		return
	var capa := CanvasLayer.new()
	capa.layer = 11
	add_child(capa)
	_base = StationPanel.new()
	capa.add_child(_base)
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


func _construir_chat() -> void:
	if _chat != null:
		return
	var capa := CanvasLayer.new()
	capa.layer = 11
	add_child(capa)
	_chat = ChatWindow.crear()
	capa.add_child(_chat)
	_chat.send_message.connect(func(canal: int, texto: String):
		_req_id += 1
		var msg := MexProtocol.ChatSend.new()
		msg.request_id = _req_id
		msg.channel = canal
		msg.text = texto
		_conn.send(msg.encode()))


func _construir_ajustes() -> void:
	if _ajustes != null:
		return
	var capa := CanvasLayer.new()
	capa.layer = 21               # por encima del killscreen
	add_child(capa)

	_ajustes = SettingsWindow.crear()
	capa.add_child(_ajustes)
	_ajustes.preset_elegido.connect(func(nombre: String):
		var claves := Quality.aplicar(nombre)
		if not claves.is_empty():
			_estado("Calidad %s" % Quality.ETIQUETAS[nombre], NTheme.CYAN))

	# §1.9: la sysbar va arriba a la derecha y FUERA del menu de ventanas. Hoy
	# lleva un solo boton porque es el unico que tiene algo detras; ayuda,
	# pantalla completa y salir se cuelgan con `agregar()` cuando existan.
	# §5: el menu de TODAS las ventanas del juego. Es la otra mitad del §1 — "todo
	# es ventana" solo funciona si hay de donde reabrirlas, y sin esto cerrar una
	# ventana la perdia para siempre.
	_taskbar = Taskbar.new()
	capa.add_child(_taskbar)
	_taskbar.agregar("nave", ShipWindow.ICONO, "Nave", func(): _alternar_ventana("nave", _nave))
	_taskbar.separador()
	_taskbar.agregar("chat", ChatWindow.ICONO, "Chat", func(): _alternar_ventana("chat", _chat))
	_taskbar.agregar("minimapa", MinimapWindow.ICONO, "Minimapa",
		func(): _alternar_ventana("minimapa", _minimapa))
	for par in [["nave", _nave], ["chat", _chat], ["minimapa", _minimapa]]:
		if par[1] != null:
			_taskbar.marcar(par[0], par[1].visible)
			par[1].cerrada.connect(_taskbar.marcar.bind(par[0], false))

	_sysbar = SysBar.new()
	capa.add_child(_sysbar)
	_sysbar.agregar("ajustes", SettingsWindow.ICONO, "Ajustes", _alternar_ajustes)
	# §1.3: el icono se pone ambar cuando su ventana esta abierta, y vuelve a
	# neutro tanto si se cierra desde el icono como desde la `×` de la ventana.
	_ajustes.cerrada.connect(func(): _sysbar.marcar("ajustes", false))


## §1.5: el icono ABRE y CIERRA su ventana. Y al reabrirla vuelve al frente, que
## es el §1.10 — si no, una ventana enterrada parece que no se abrio.
func _alternar_ventana(clave: String, v: NWindow) -> void:
	if v == null:
		return
	v.visible = not v.visible
	if v.visible:
		v.move_to_front()
	_taskbar.marcar(clave, v.visible)


func _alternar_ajustes() -> void:
	if _ajustes == null:
		return
	_ajustes.alternar()
	_sysbar.marcar("ajustes", _ajustes.visible)


## El cambio de calidad se aplica AL INSTANTE: cada entidad rehace su parte
## visual, las cajas se recrean y el fondo se reconstruye. Nada de esperar a
## reconectar — la nave, su rumbo y el estado del mundo no se tocan.
func _on_calidad_cambiada(claves: Array) -> void:
	if claves.has("npc") or claves.has("emissive") or claves.has("shader") \
			or claves.has("engine"):
		for id in _entidades:
			_entidades[id].reconstruir()
	if claves.has("collectable"):
		for id in _portales:
			_portales[id].reconstruir()
	if claves.has("collectable") or claves.has("emissive"):
		var pendientes := []
		for id in _cajas:
			pendientes.append([id, _cajas[id].position])
			_cajas[id].queue_free()
		_cajas.clear()
		_caja_anim_total = 0
		for par in pendientes:
			_crear_caja(par[0], par[1])
	if claves.has("background") and _fondo != null:
		_fondo.queue_free()
		_fondo = null
		_construir_fondo(_map_code)


func _construir_respawn() -> void:
	if _respawn != null:
		return
	var capa := CanvasLayer.new()
	capa.layer = 20            # por encima de todo: mientras estas muerto, manda
	add_child(capa)
	_respawn = RespawnPanel.new()
	capa.add_child(_respawn)
	_respawn.option_chosen.connect(func(option_id: int):
		var msg := MexProtocol.RespawnSelect.new()
		msg.option_id = option_id
		_conn.send(msg.encode()))


## La nave fue destruida: el server manda las opciones de vuelta al juego.
func _on_respawn_options(msg) -> void:
	_muerto = true
	_hold_move = false
	_laser_on = false
	_autopilot = Vector2.INF
	_pending_box = 0
	if _respawn != null:
		_respawn.mostrar(msg)
	if _chat != null:
		_chat.add_system("Tu nave fue destruida por %s" % msg.killer_name, NTheme.HOSTILE)
	_estado("Nave destruida", NTheme.HOSTILE)
	# el autotest no tiene dedos: acepta la primera opcion y sigue con el loop
	if Session.autotest_screenshot != "" and not msg.options.is_empty():
		# un frame de margen para que el killscreen ya este dibujado en la captura
		await get_tree().process_frame
		var img_m := get_viewport().get_texture().get_image()
		img_m.save_png(Session.autotest_screenshot.replace(".png", "-muerte.png"))
		_at_muertes += 1
		if _respawn != null:
			_respawn.visible = false
		var sel := MexProtocol.RespawnSelect.new()
		sel.option_id = msg.options[0].option_id
		_conn.send(sel.encode())
		_at_fase = 0
		_at_target = 0


func _on_station_range(msg) -> void:
	_en_base = msg.in_range
	if _base != null:
		_base.visible = msg.in_range
	_estado("En la base: descarga tu bodega y vende al NPC" if msg.in_range
		else "Sector %s" % _map_code, NTheme.CYAN if msg.in_range else NTheme.MUTED)


func _on_unload_result(res) -> void:
	var partes := []
	for m in res.stored:
		partes.append("%d × %s" % [m.amount, m.material_id.trim_prefix("material_").capitalize()])
	var texto := "Almacenado: " + (", ".join(partes) if not partes.is_empty() else "nada")
	for m in res.refined:
		texto += "  ·  REFINADO: %d × %s" % [m.amount, m.material_id.trim_prefix("material_").capitalize()]
	_estado(texto, NTheme.HP if not res.refined.is_empty() else NTheme.WARN)
	_at_descargado = true


func _on_sell_result(res) -> void:
	_estado("Vendido: +%s C  ·  saldo %s C" % [_miles(res.credits_gained), _miles(res.new_credits)],
		NTheme.WARN)
	_at_vendido = true


func _on_autopilot(destino: Vector2) -> void:
	_autopilot = destino.clamp(Vector2.ZERO, _limites)
	_estado("Autopiloto hacia (%d, %d)" % [_autopilot.x, _autopilot.y], NTheme.MUTED)
	_volar_a(_autopilot)


## Vuelo sostenido del autopiloto: si el heroe quedo detenido sin llegar
## (correccion del server, choque de estados), reemite el destino.
func _process_autopilot() -> void:
	if _autopilot == Vector2.INF or _hero == null:
		return
	if _hero.position.distance_to(_autopilot) <= AUTOPILOT_ARRIVE:
		_estado("Autopiloto: destino alcanzado", NTheme.MUTED)
		_autopilot = Vector2.INF
		return
	if _hero.position.distance_to(_hero.objetivo) < 1.0:
		_volar_a(_autopilot)


# ---- accesores para el minimapa ----
func limites() -> Vector2: return _limites
func heroe() -> EntityNode: return _hero
func entidades() -> Dictionary: return _entidades
func cajas() -> Dictionary: return _cajas
func portales() -> Dictionary: return _portales
func estacion_pos() -> Vector2: return _estacion_pos
func autopiloto() -> Vector2: return _autopilot
func map_code() -> String: return _map_code


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
		if _muerto:
			_muerto = false
			_estado("Reparada en la base", NTheme.HP)
			if _chat != null:
				_chat.add_system("Nave reparada en la base", NTheme.HP)
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
	_nave.poner("vida", hs.hp, hs.max_hp)
	_nave.poner("escudo", hs.shield, hs.max_shield)
	_nave.poner("bodega", hs.cargo, hs.max_cargo)
	_nave.poner_texto("creditos", "%s C" % _miles(hs.credits))
	# tus propias barras salen de aquí: HeroStats es la única fuente de tus máximos
	if _hero != null:
		_hero.max_hp_abs = hs.max_hp
		_hero.max_shield_abs = hs.max_shield
		_hero.set_estado_abs(hs.hp, hs.shield)


func _on_target_info(ti) -> void:
	var nodo: EntityNode = _entidades.get(ti.entity_id)
	if nodo == null:
		return
	# casco y escudo cada uno contra su máximo: son dos barras, no una suma
	nodo.max_hp_abs = ti.max_hp
	nodo.max_shield_abs = ti.max_shield
	nodo.set_estado_abs(ti.hp, ti.shield)


## Colores de daño del original (su tabla hitpointColors).
const HIT_HACES := Color("FF0000")      # el daño que haces
const HIT_RECIBES := Color("DB63E2")    # el daño que te hacen


func _on_attack(ev) -> void:
	var blanco: EntityNode = _entidades.get(ev.target_id)
	var tirador: EntityNode = _entidades.get(ev.attacker_id)
	if blanco == null:
		return

	_at_disparos += 1
	# el disparo: sale de una boca de cañón del tirador y viaja al blanco
	if tirador != null:
		var ammo: String = ev.ammo_id if ev.ammo_id != "" else "ammo_cel_1"
		Projectile2D.fire(self, tirador.siguiente_canon(), blanco.position, ammo, ev.skilled)

	if ev.missed:
		_numero_flotante(blanco, "MISS", HIT_RECIBES if blanco == _hero else HIT_HACES)
		return

	blanco.set_estado_abs(ev.target_hp, ev.target_shield)
	# impacto: en el escudo si aún queda, en el casco si no
	if ev.target_shield > 0 and tirador != null:
		blanco.impacto_escudo(tirador.position)
	else:
		blanco.impacto_casco()
	_numero_flotante(blanco, str(ev.damage), HIT_RECIBES if blanco == _hero else HIT_HACES)


## Número de combate: sube 42 px en 1 s sobre la entidad, con contorno negro.
## Golpes seguidos del mismo color sobre el mismo blanco se ACUMULAN en el
## número vivo y reinician el vuelo, como en el prototipo.
var _numeros := {}


func _numero_flotante(sobre: EntityNode, texto: String, color: Color) -> void:
	var clave := "%d:%s" % [sobre.entity_id, color.to_html(false)]
	var vivo = _numeros.get(clave)
	if vivo != null and is_instance_valid(vivo) and texto.is_valid_int():
		vivo.set_meta("suma", int(vivo.get_meta("suma", 0)) + int(texto))
		vivo.text = str(vivo.get_meta("suma"))
		vivo.position = sobre.position + Vector2(-60, -110)
		return

	var label := NTheme.label(texto, NTheme.mono(), 15, color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("outline_size", 5)
	label.custom_minimum_size = Vector2(120, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = sobre.position + Vector2(-60, -110)
	label.z_index = 20
	if texto.is_valid_int():
		label.set_meta("suma", int(texto))
	add_child(label)
	_numeros[clave] = label
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y - 42, 1.0)
	tw.tween_property(label, "modulate:a", 0.0, 1.0).set_delay(0.35)
	tw.chain().tween_callback(func():
		_numeros.erase(clave)
		label.queue_free())


func _on_destroyed(msg) -> void:
	var nodo: EntityNode = _entidades.get(msg.entity_id)
	if nodo != null and nodo == _hero:
		_hero = null              # el spawn de la reaparicion lo vuelve a crear
	if nodo != null:
		_explotar(nodo.position)
		nodo.queue_free()
		_entidades.erase(msg.entity_id)
	if _seleccionada == msg.entity_id:
		_seleccionada = 0
		_laser_on = false
		if _hero != null:
			_hero.set_attack_target(null)   # sin presa, el rumbo vuelve al vuelo


func _explotar(pos: Vector2) -> void:
	if Quality.nivel("explosion") < 1:
		return                    # el evento sigue ocurriendo; solo no se dibuja
	var anim := AnimatedSprite2D.new()
	anim.sprite_frames = _frames_explosion
	anim.position = pos
	anim.scale = Vector2.ONE * 1.4
	anim.z_index = 4
	add_child(anim)
	anim.play("boom")
	anim.animation_finished.connect(anim.queue_free)


func _on_box_spawn(msg) -> void:
	_crear_caja(msg.box_id, Vector2(msg.x, msg.y))


func _crear_caja(box_id: int, pos: Vector2) -> void:
	if _cajas.has(box_id):
		return
	# todas las particularidades de la caja salen de su JSON (data/props/cargo-box.json)
	var d := AssetDefs.prop("cargo-box")
	var caja := Sprite2D.new()
	# Los props entienden los DOS tipos de asset, igual que los bichos: PNG con
	# su capa emisiva, o atlas de fotogramas sacado de un video en bucle.
	# ALTA anima la caja; MEDIA y BAJA la dejan congelada en su fotograma 0, que
	# es exactamente lo que hacia el nivel 0 de `collectable` del original.
	var anim: Dictionary = d.get("frames", {}) if Quality.nivel("collectable") >= 2 else {}
	if anim.is_empty():
		caja.texture = load(d.get("texture", "res://assets/world/cargo-box-still.png"))
	else:
		caja.texture = load(anim.get("atlas", ""))
		caja.hframes = int(anim.get("hframes", 1))
		caja.vframes = int(anim.get("vframes", 1))
		_caja_anim_total = int(anim.get("count", caja.hframes * caja.vframes))
		_caja_anim_fps = float(anim.get("fps", 12.0))
		# desfase por caja: un campo de cajas parpadeando a la vez canta a bucle
		caja.set_meta("anim_t", randf() * float(_caja_anim_total) / maxf(_caja_anim_fps, 1.0))
	caja.position = pos
	# tamaño en unidades de MUNDO, sea cual sea la resolucion del render. Con
	# atlas manda el ancho del FOTOGRAMA, no el de la textura entera.
	var lado := float(caja.texture.get_width()) / maxf(float(caja.hframes), 1.0)
	caja.scale = Vector2.ONE * (float(d.get("world_size", 48)) / lado)
	caja.z_index = 1
	add_child(caja)
	# la banda emisiva late en ALFA para llamar al jugador (fase por caja). Una
	# caja de atlas no la lleva: su luz ya viene cocida en los fotogramas.
	if anim.is_empty() and d.has("emissive") and Quality.nivel("emissive") >= 1:
		var brillo := Sprite2D.new()
		brillo.texture = load(d.emissive)
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		brillo.material = mat
		caja.add_child(brillo)
		var p: Dictionary = d.get("pulse", {})
		var medio: float = float(p.get("half_period", 0.9))
		var tw := caja.create_tween().set_loops()
		tw.tween_property(brillo, "self_modulate:a", float(p.get("min_alpha", 0.25)), medio) \
			.set_trans(Tween.TRANS_SINE)
		tw.tween_property(brillo, "self_modulate:a", float(p.get("max_alpha", 1.0)), medio) \
			.set_trans(Tween.TRANS_SINE)
	_cajas[box_id] = caja


func _on_box_despawn(msg) -> void:
	if _cajas.has(msg.box_id):
		_cajas[msg.box_id].queue_free()
		_cajas.erase(msg.box_id)
	if _pending_box == msg.box_id:
		_pending_box = 0


func _on_collect_result(res) -> void:
	var partes := []
	for drop in res.drops:
		partes.append("%d × %s" % [drop.amount, drop.material_id.trim_prefix("material_").capitalize()])
	_estado("Recogido: " + ", ".join(partes), NTheme.WARN)
	_at_recogido = true


func _on_error(e) -> void:
	match e.code:
		MexProtocol.ErrorCode.TOO_FAR: _estado("Demasiado lejos de la caja", NTheme.HOSTILE)
		MexProtocol.ErrorCode.GONE: _estado("La caja ya no está", NTheme.MUTED)
		MexProtocol.ErrorCode.INSUFFICIENT: _estado("Bodega llena", NTheme.HOSTILE)
		_: _estado("ErrorReply %d: %s" % [e.code, e.detail], NTheme.HOSTILE)


func _unhandled_input(event: InputEvent) -> void:
	# Los ajustes se abren por su ENGRANAJE de la sysbar. Estuvieron en F1 y esa
	# tecla no era suya: el §6 reserva F1-F10 para la barra de accion II, asi que
	# el atajo se habria comido un slot en cuanto existan las barras. Escape los
	# cierra, que es la unica tecla que el documento no reparte.
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE and _ajustes != null and _ajustes.visible:
		_alternar_ajustes()
		get_viewport().set_input_as_handled()
		return
	# escribiendo en el chat, el teclado es suyo (Enter lo enfoca, como el original)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER:
		if _chat != null and not _chat.tiene_foco():
			_chat.enfocar()
			return
	if _chat != null and _chat.tiene_foco() and event is InputEventKey:
		return
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
	elif event is InputEventKey and event.pressed and not event.echo:
		# Ctrl = laser (el atajo por defecto del prototipo)
		if event.keycode == KEY_CTRL:
			_toggle_laser()


func _toggle_laser() -> void:
	if _muerto:
		return
	if _seleccionada == 0 or not _entidades.has(_seleccionada):
		return
	_laser_on = not _laser_on
	# disparando, el rumbo del heroe lo gobierna el objetivo (como el prototipo)
	if _hero != null:
		_hero.set_attack_target(_entidades[_seleccionada] if _laser_on else null)
	var msg := MexProtocol.LaserToggle.new()
	msg.active = _laser_on
	_conn.send(msg.encode())


func _handle_click(world_pos: Vector2) -> void:
	if _muerto:
		return                     # destruido: el mundo no acepta ordenes
	# las cajas tienen prioridad (flujo del prototipo): volar hasta ella y
	# recolectar al llegar — el server exige cercania, el cliente la procura
	var caja_id := _box_at(world_pos)
	if caja_id != 0:
		var caja: Sprite2D = _cajas[caja_id]
		_volar_a(caja.position)
		_pending_box = caja_id
		_pending_box_pos = caja.position
		_estado("Recogiendo caja…", NTheme.MUTED)
		return
	# ¿click sobre una entidad? seleccionar, no volar (como el prototipo)
	var bajo := _entity_at(world_pos)
	if bajo != null:
		_seleccionar(bajo)
		return
	# ¿click sobre un portal? Si ya estamos encima, ACTIVAR; si no, rumbo a el.
	var portal := _portal_at(world_pos)
	if portal != null:
		_pending_box = 0
		if not portal.is_working:
			_estado("Ese portal está inactivo", NTheme.VIOLET)
			return
		var encima := _hero != null and _hero.position.distance_to(portal.position) <= portal.click_radius
		if encima and portal.activar():
			# los 2,1 s del encendido son el hueco donde cabe la latencia: en E3
			# la peticion de salto sale AQUI y el mapa se muestra cuando hayan
			# terminado los dos. Hoy no hay salto, asi que solo se ve el encendido.
			if not portal.encendido_terminado.is_connected(_on_portal_encendido):
				portal.encendido_terminado.connect(_on_portal_encendido)
			_estado("Abriendo portal · sector %s" % portal.target_map_code, NTheme.VIOLET)
			return
		_autopilot = portal.position
		_volar_a(portal.position)
		_estado("Rumbo al portal · sector %s" % portal.target_map_code, NTheme.VIOLET)
		return
	# click en vacio: volar; mientras siga presionado, _process persigue al cursor
	# (el vuelo manual cancela el autopiloto, como en el prototipo)
	_pending_box = 0
	_autopilot = Vector2.INF
	_volar_a(world_pos)
	_hold_move = true
	_hold_timer = 0.0


## El encendido ha llegado a su ultimo fotograma. En E3 aqui se muestra el mapa
## destino si el server ya respondio; hoy solo se dice que el portal esta abierto.
func _on_portal_encendido(portal_id: int) -> void:
	var p: PortalNode = _portales.get(portal_id)
	if p == null:
		return
	_estado("Portal abierto · el salto al sector %s llega en E3" % p.target_map_code, NTheme.VIOLET)


func _portal_at(world_pos: Vector2) -> PortalNode:
	for id in _portales:
		var p: PortalNode = _portales[id]
		if p.position.distance_to(world_pos) < p.click_radius:
			return p
	return null


func _box_at(world_pos: Vector2) -> int:
	var min_radius := CLICK_RADIUS / _camara.zoom.x
	for id in _cajas:
		if _cajas[id].position.distance_to(world_pos) < min_radius:
			return id
	return 0


## Entidad interactuable bajo el punto. Cada entidad trae su radio de click del
## JSON, con el minimo del prototipo escalado por zoom (sin esto, con zoom lejano
## nada era clickable).
func _entity_at(world_pos: Vector2) -> EntityNode:
	var best: EntityNode = null
	var best_dist := INF
	var min_radius := CLICK_RADIUS / _camara.zoom.x
	for id in _entidades:
		var e: EntityNode = _entidades[id]
		if e == _hero:
			continue
		var d := e.position.distance_to(world_pos)
		if d < maxf(e.click_radius, min_radius) and d < best_dist:
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
	_process_pending_collect()
	_process_autopilot()
	if _fondo != null:
		_fondo.update_parallax(_camara.position, _camara.zoom, get_viewport_rect().size)

	# el reactor de la estacion respira
	if _estacion_reactor != null:
		var onda := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * _reactor_speed)
		onda = pow(onda, _reactor_sharp)
		var k: float = _reactor_min + (_reactor_max - _reactor_min) * onda
		_estacion_reactor.self_modulate = Color(k, k, k, 1.0)
	if _hero != null and not _at_camara_libre:
		_camara.position = _camara.position.lerp(_hero.position, 8.0 * delta)
		_nave.poner_texto("posicion", "(%d, %d)" % [_hero.position.x, _hero.position.y])

	# (los disparos son proyectiles que viajan, uno por AttackEvent del server:
	# ya no hay haz permanente entre las naves)

	if _caja_anim_total > 0:
		for caja in _cajas.values():
			var t: float = float(caja.get_meta("anim_t", 0.0)) + delta
			caja.set_meta("anim_t", t)
			caja.frame = int(t * _caja_anim_fps) % _caja_anim_total

	if Session.autotest_screenshot != "":
		_autotest(delta)


## Recoleccion en vuelo (flujo del prototipo): al llegar junto a la caja,
## se manda el CollectBox; si el server nos corrigio lejos, se cancela sola.
func _process_pending_collect() -> void:
	if _pending_box == 0 or _hero == null:
		return
	if _hero.position.distance_to(_hero.objetivo) > 1.0:
		return   # sigue volando
	if _hero.position.distance_to(_pending_box_pos) <= COLLECT_ARRIVE:
		_req_id += 1
		var msg := MexProtocol.CollectBox.new()
		msg.request_id = _req_id
		msg.box_id = _pending_box
		_conn.send(msg.encode())
	_pending_box = 0


# autotest del loop I5: volar al Vex mas cercano -> laser -> caja -> recoger
var _at_fase := 0
var _at_target := 0
var _at_recogido := false
var _at_ultimo_vuelo := 0.0
var _at_descargado := false
var _at_vendido := false
var _at_disparos := 0
var _at_shot_combate := false
var _at_chat_ok := false
var _at_reconectado := false
var _at_camara_libre := false
var _at_portal_animado := false     # el autotest suelta la camara para retratar el mapa
var _at_camara_t := -1.0
## Los bichos a los que el autotest les toma retrato de QA (uno por especie).
const AT_BESTIARIO := ["vex", "vexor", "skarn", "ferox", "skarnox", "gravit", "mordax", "gravon", "vorax"]
var _at_bicho := 0
var _at_primer_frame := false
var _at_cambio_calidad := false
var _at_calidad_previa := "alta"
var _at_caza_desde := 0.0
var _at_shot_caja := false


var _at_muertes := 0


func _autotest(delta: float) -> void:
	_autotest_t += delta
	# muerto o aun sin nave: no hay nada que pilotar este frame. Sin esta guarda,
	# cualquier fase que use _hero reventaba en cuanto un Ferox hacia su trabajo.
	if _muerto or (_hero == null and _at_fase > 0):
		return
	# modo BESTIARIO: solo los retratos. La pasada completa tarda ~3 min y para
	# calibrar un shader eso es un peaje: se salta directo a la fase 10.
	if Session.autotest_modo == "bestiario":
		if _autotest_t > 60.0:
			_at_captura("BESTIARIO TIMEOUT en el bicho %d" % _at_bicho, 1)
			return
		if _at_fase == 0:
			# margen para que lleguen todos los spawns del mapa
			if _autotest_t < 3.0 or _hero == null:
				return
			_at_camara_libre = true
			_at_fase = 10
		_autotest_bestiario()
		return
	if _autotest_t > 190.0:
		_at_captura("AUTOTEST TIMEOUT en fase %d" % _at_fase, 1)
		return
	match _at_fase:
		0:
			if _autotest_t > 1.5 and _hero != null:
				# el Vex mas cercano, no el NPC mas cercano: con cinco especies en
				# el mapa el vecino podia ser un Skarnox de 47 s de TTK y el
				# autotest se comia su propio limite de tiempo peleando
				var cercano: EntityNode = null
				var mejor := INF
				for id in _entidades:
					var e: EntityNode = _entidades[id]
					if e.type_id != "vex":
						continue
					if _hero.position.distance_to(e.position) < mejor:
						mejor = _hero.position.distance_to(e.position)
						cercano = e
				if cercano != null:
					_at_target = cercano.entity_id
					_at_caza_desde = _autotest_t
					_volar_a(cercano.position + Vector2(120, 0))
					_at_fase = 1
		1:
			var vex: EntityNode = _entidades.get(_at_target)
			if vex == null:
				_at_fase = 0     # se murio o despawneo: buscar otro
				return
			# La nave vuela a 320 y un Vex vagabundea a 270: si el bicho elige un
			# destino que se aleja, la persecucion cierra a 50 unidades por
			# segundo y puede durar eternamente. De ahi salio un timeout
			# intermitente del gate. A los 20 s se abandona y se busca otro.
			if _autotest_t - _at_caza_desde > 20.0:
				_at_fase = 0
				_at_target = 0
				return
			# Desde que los NPC tienen IA, cruzan el mapa: volar UNA vez a donde
			# estaba dejaba al bot esperando en un hueco vacio para siempre.
			# Hay que perseguirlo, como ya hacia la fase 2.
			if _hero.position.distance_to(vex.position) > 450.0 					and _autotest_t - _at_ultimo_vuelo > 2.0:
				_at_ultimo_vuelo = _autotest_t
				_volar_a(vex.position + Vector2(120, 0))
			if _hero.position.distance_to(vex.position) < 450.0:
				_seleccionar(vex)
				_laser_on = true
				var msg := MexProtocol.LaserToggle.new()
				msg.active = true
				_conn.send(msg.encode())
				_at_fase = 2
		2:
			# captura extra a media pelea: sirve de QA visual del combate
			if not _at_shot_combate and _at_disparos >= 3:
				_at_shot_combate = true
				var img_c := get_viewport().get_texture().get_image()
				img_c.save_png(Session.autotest_screenshot.replace(".png", "-combate.png"))
			# perseguir al objetivo si se aleja del rango del laser
			var objetivo_npc: EntityNode = _entidades.get(_at_target)
			if objetivo_npc != null and _hero.attack_target == null:
				_hero.set_attack_target(objetivo_npc)
			if objetivo_npc != null and _hero.position.distance_to(objetivo_npc.position) > 450.0 \
					and _autotest_t - _at_ultimo_vuelo > 2.0:
				_at_ultimo_vuelo = _autotest_t
				_volar_a(objetivo_npc.position + Vector2(120, 0))
			# _on_destroyed limpia la seleccion; la caja aparece via BoxSpawn y
			# el click-flujo se simula fijando el pending directamente
			if not _entidades.has(_at_target):
				for id in _cajas:
					_pending_box = id
					_pending_box_pos = _cajas[id].position
					_volar_a(_pending_box_pos)
					_at_fase = 3
					return
		3:
			# retrato de la caja al llegar a su lado, ANTES de recogerla: es el
			# unico momento en que se la puede fotografiar. Se dispara a 520 y no
			# pegado: al llegar encima, la nave la tapa entera.
			if not _at_shot_caja and _pending_box != 0 \
					and _hero.position.distance_to(_pending_box_pos) < 520.0:
				_at_shot_caja = true
				var img_k := get_viewport().get_texture().get_image()
				img_k.save_png(Session.autotest_screenshot.replace(".png", "-caja.png"))
			# recogida hecha: volver a la base
			if _at_recogido:
				_volar_a(_estacion_pos + Vector2(330, 60))
				_at_fase = 4
		4:
			# se acerca de verdad a la estacion antes de descargar (asi la
			# captura del autotest sirve tambien para revisar su arte)
			if _en_base and _hero.position.distance_to(_estacion_pos) < 420.0 \
					and _autotest_t - _at_ultimo_vuelo > 1.0:
				_at_ultimo_vuelo = _autotest_t
				_req_id += 1
				var msg := MexProtocol.UnloadCargo.new()
				msg.request_id = _req_id
				_conn.send(msg.encode())
				_at_fase = 5
		5:
			# almacen recibido: vender el primer material que el NPC compre
			if _at_descargado and _autotest_t - _at_ultimo_vuelo > 1.0:
				_at_ultimo_vuelo = _autotest_t
				_req_id += 1
				var venta := MexProtocol.SellToNpc.new()
				venta.request_id = _req_id
				venta.material_id = "material_asterium"
				venta.amount = 0            # todo
				_conn.send(venta.encode())
				_at_fase = 6
		6:
			# chat: se manda al canal GLOBAL y debe volver por el mismo socket
			if _at_vendido and _autotest_t - _at_ultimo_vuelo > 1.0:
				_at_ultimo_vuelo = _autotest_t
				_chat.enfocar()
				_chat.send_message.emit(0, "autotest: hola sector")
				_at_fase = 7
		7:
			# eco del chat recibido -> cortar la red y volver con el token
			if _at_chat_ok and _autotest_t - _at_ultimo_vuelo > 1.0:
				_at_ultimo_vuelo = _autotest_t
				_conn.simular_caida()
				_at_fase = 8
		8:
			# QA visual del portal: volar hasta el borde del mapa costaria ~50 s de
			# reloj, asi que se suelta la camara y se retrata en su sitio
			if _at_reconectado and _hero != null \
					and _autotest_t - _at_ultimo_vuelo > 3.0:
				_at_ultimo_vuelo = _autotest_t
				if _portales.is_empty():
					_at_captura("AUTOTEST FALLO — el mapa llego sin portales", 1)
					return
				_at_camara_libre = true
				_camara.position = _portales.values()[0].position
				_at_fase = 9
		9:
			# retrato en REPOSO: con atlas, el aro dormido del primer fotograma
			if _autotest_t - _at_ultimo_vuelo > 1.5:
				var img_p := get_viewport().get_texture().get_image()
				img_p.save_png(Session.autotest_screenshot.replace(".png", "-portal.png"))
				_at_ultimo_vuelo = _autotest_t
				_at_portal_animado = _portales.values()[0].activar()
				_at_fase = 90
		90:
			# ...y retrato ABIERTO, tras los 2,1 s del encendido. Una foto sola no
			# prueba nada: se comprueba que la secuencia llego a su ultimo
			# fotograma, que es donde el portal se queda al saltar.
			if _autotest_t - _at_ultimo_vuelo > 3.0:
				var img_a := get_viewport().get_texture().get_image()
				img_a.save_png(Session.autotest_screenshot.replace(".png", "-portal-abierto.png"))
				var con_atlas := Quality.nivel("collectable") >= 2
				if Session.calidad_forzada == "" and not con_atlas:
					_at_captura("AUTOTEST FALLO — sin -Calidad esto corre en alta: "
						+ "el portal tenia que montar el atlas y no lo hizo", 1)
					return
				if con_atlas and not _at_portal_animado:
					_at_captura("AUTOTEST FALLO — el portal no arranco el encendido", 1)
					return
				if _at_portal_animado and not _portales.values()[0].encendido_completo():
					_at_captura("AUTOTEST FALLO — el encendido del portal no llego al final", 1)
					return
				_at_fase = 10
		10:
			_autotest_bestiario()
		11:
			_at_camara_libre = false
			# una ventana que no se construyo (error de script en su .gd) pasaba
			# desapercibida: el autotest seguia dando OK sin minimapa
			if _minimapa == null or _chat == null or _base == null or _sysbar == null:
				_at_captura("AUTOTEST FALLO — falta una ventana (minimapa/chat/base/sysbar)", 1)
				return
			# la ventana de Ajustes se abre COMO LA ABRE EL JUGADOR, por el
			# engranaje: probar `alternar()` a pelo se saltaria justo el cableado
			# que puede romperse (el boton, la senial y el estado ambar)
			_alternar_ajustes()
			_at_ultimo_vuelo = _autotest_t
			_at_fase = 92
		92:
			if _autotest_t - _at_ultimo_vuelo > 0.6:
				var img_c := get_viewport().get_texture().get_image()
				img_c.save_png(Session.autotest_screenshot.replace(".png", "-ajustes.png"))
				if not _ajustes.visible:
					_at_captura("AUTOTEST FALLO — el engranaje no abrio los Ajustes", 1)
					return
				# el codigo de color del §1.3 es contrato, no adorno
				if not _sysbar.esta_marcado("ajustes"):
					_at_captura("AUTOTEST FALLO — el engranaje no se puso ambar", 1)
					return
				_alternar_ajustes()
				if _ajustes.visible:
					_at_captura("AUTOTEST FALLO — el engranaje no cierra los Ajustes", 1)
					return
				_at_fase = 94
		94:
			# La taskbar es lo que hace cierto el §1: "todo es ventana" solo vale
			# si se pueden REABRIR. Se prueba el ciclo entero —cerrar, comprobar
			# que el icono vuelve a neutro, reabrir— porque una ventana que se
			# cierra y no vuelve es peor que una que no se cierra.
			_alternar_ventana("nave", _nave)
			if _nave.visible or _taskbar.esta_marcado("nave"):
				_at_captura("AUTOTEST FALLO — la taskbar no cerro la ventana Nave", 1)
				return
			_alternar_ventana("nave", _nave)
			if not _nave.visible or not _taskbar.esta_marcado("nave"):
				_at_captura("AUTOTEST FALLO — la taskbar no reabrio la ventana Nave", 1)
				return
			_at_ultimo_vuelo = _autotest_t
			_at_fase = 95
		95:
			if _autotest_t - _at_ultimo_vuelo > 0.5:
				var img_t := get_viewport().get_texture().get_image()
				img_t.save_png(Session.autotest_screenshot.replace(".png", "-ventanas.png"))
				_at_fase = 93
		93:
			_at_captura("AUTOTEST OK — loop, chat, reconexion, portal, ajustes, ventanas, bestiario (%d especies) y %d muerte(s)"
				% [AT_BESTIARIO.size(), _at_muertes], 0)


## Retrato de cada bicho del bestiario: la camara los visita sin volar hasta
## ellos. Agregar un alien = agregarlo a AT_BESTIARIO, nada mas.
## Lo comparten los dos modos: en "loop" es la ultima fase, en "bestiario" es
## la unica.
func _autotest_bestiario() -> void:
	if _at_bicho >= AT_BESTIARIO.size():
		if Session.autotest_modo == "bestiario":
			# Prueba del cambio EN CALIENTE: se baja la calidad con el mundo ya
			# poblado y se retrata. Si reconstruir rompiera algo, revienta aqui.
			if Session.calidad_forzada == "" and not _at_cambio_calidad:
				_at_cambio_calidad = true
				_at_calidad_previa = Quality.preset
				Quality.aplicar("baja")
				_at_camara_t = _autotest_t
				return
			if _at_cambio_calidad and _autotest_t - _at_camara_t < 1.0:
				return
			if _at_cambio_calidad:
				_retrato("cambio-calidad", "")
				# y se DEVUELVE a donde estaba: una prueba que deja residuo
				# persistente contamina todas las corridas siguientes
				Quality.aplicar(_at_calidad_previa)
			_at_camara_libre = false
			_at_captura("BESTIARIO OK — %d retratos%s" % [AT_BESTIARIO.size(),
				" + cambio de calidad en caliente" if _at_cambio_calidad else ""], 0)
		else:
			_at_fase = 11
		return
	var especie: String = AT_BESTIARIO[_at_bicho]
	var bicho := _primero_de_especie(especie)
	if bicho == null:
		_at_captura("FALLO — no hay ningun %s en el mapa" % especie, 1)
		return
	_camara.position = bicho.position
	if _at_camara_t < 0.0:
		_at_camara_t = _autotest_t
	var dt := _autotest_t - _at_camara_t
	# En modo arte se toma un SEGUNDO fotograma casi un segundo despues del
	# primero: una foto fija no demuestra que un shader se MUEVA, con dos se
	# compara. En la pasada del loop sobra — ahi solo se comprueba que existan.
	var dos_frames := Session.autotest_modo == "bestiario"
	if not _at_primer_frame:
		if dt <= 1.2:
			return
		_at_primer_frame = true
		_retrato(especie, "")
		if dos_frames:
			return
	elif dt <= 2.1:
		return
	else:
		_retrato(especie, "-b")
	# siguiente bicho
	_at_camara_t = -1.0
	_at_primer_frame = false
	_at_bicho += 1


func _retrato(especie: String, sufijo: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if Session.calidad_forzada != "":
		sufijo = "-" + Session.calidad_forzada + sufijo
	img.save_png(Session.autotest_screenshot.replace(".png", "-%s%s.png" % [especie, sufijo]))


## Primer NPC de una especie, para los retratos de QA del autotest.
func _primero_de_especie(code: String) -> EntityNode:
	for id in _entidades:
		var e: EntityNode = _entidades[id]
		if e.type_id == code:
			return e
	return null


func _at_captura(mensaje: String, codigo: int) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(Session.autotest_screenshot)
	print(mensaje, " · captura en ", Session.autotest_screenshot)
	get_tree().quit(codigo)


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
