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
var _portales := {}               # portal_id -> PortalNode
var _pending_box := 0             # flujo del prototipo: volar a la caja y recoger al llegar
var _pending_box_pos := Vector2.ZERO
var _req_id := 0
var _frames_explosion: SpriteFrames

# HUD (sistema N minimo de la iteracion: panel de nave + estado del enlace)
var _hud_estado: Label
var _hud_hp: Label
var _hud_shield: Label
var _hud_pos: Label
var _hud_credits: Label
var _hud_cargo: Label

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

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", NTheme.glass_panel())
	panel.position = Vector2(12, 12)
	capa.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	col.add_child(NTheme.label("NAVE", NTheme.michroma(), 8, NTheme.CYAN))
	_hud_hp = NTheme.label("--", NTheme.mono(), 12, NTheme.HP)
	col.add_child(_hud_hp)
	_hud_shield = NTheme.label("--", NTheme.mono(), 12, NTheme.SHIELD)
	col.add_child(_hud_shield)
	_hud_credits = NTheme.label("--", NTheme.mono(), 12, NTheme.WARN)
	col.add_child(_hud_credits)
	_hud_cargo = NTheme.label("--", NTheme.mono(), 12, NTheme.WARN)
	col.add_child(_hud_cargo)
	_hud_pos = NTheme.label("(0, 0)", NTheme.mono(), 11, NTheme.MUTED)
	col.add_child(_hud_pos)

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
	_chat = ChatWindow.new()
	capa.add_child(_chat)
	_chat.send_message.connect(func(canal: int, texto: String):
		_req_id += 1
		var msg := MexProtocol.ChatSend.new()
		msg.request_id = _req_id
		msg.channel = canal
		msg.text = texto
		_conn.send(msg.encode()))


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
	_hud_hp.text = "HP %s / %s" % [_miles(hs.hp), _miles(hs.max_hp)]
	_hud_shield.text = "ESC %s / %s" % [_miles(hs.shield), _miles(hs.max_shield)]
	_hud_credits.text = "%s C" % _miles(hs.credits)
	_hud_cargo.text = "Bodega %s / %s" % [_miles(hs.cargo), _miles(hs.max_cargo)]
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
	var anim := AnimatedSprite2D.new()
	anim.sprite_frames = _frames_explosion
	anim.position = pos
	anim.scale = Vector2.ONE * 1.4
	anim.z_index = 4
	add_child(anim)
	anim.play("boom")
	anim.animation_finished.connect(anim.queue_free)


func _on_box_spawn(msg) -> void:
	if _cajas.has(msg.box_id):
		return
	# todas las particularidades de la caja salen de su JSON (data/props/cargo-box.json)
	var d := AssetDefs.prop("cargo-box")
	var caja := Sprite2D.new()
	caja.texture = load(d.get("texture", "res://assets/world/cargo-box.png"))
	caja.position = Vector2(msg.x, msg.y)
	# tamaño en unidades de MUNDO, sea cual sea la resolucion del render
	var lado := float(caja.texture.get_width())
	caja.scale = Vector2.ONE * (float(d.get("world_size", 48)) / lado)
	caja.z_index = 1
	add_child(caja)
	# la banda emisiva late en ALFA para llamar al jugador (fase por caja)
	if d.has("emissive"):
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
	_cajas[msg.box_id] = caja


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
	# ¿click sobre un portal? rumbo a el (el salto de sector llega en E3)
	var portal := _portal_at(world_pos)
	if portal != null:
		_pending_box = 0
		_autopilot = portal.position
		_volar_a(portal.position)
		_estado("Rumbo al portal · sector %s" % portal.target_map_code
			if portal.is_working else "Ese portal está inactivo", NTheme.VIOLET)
		return
	# click en vacio: volar; mientras siga presionado, _process persigue al cursor
	# (el vuelo manual cancela el autopiloto, como en el prototipo)
	_pending_box = 0
	_autopilot = Vector2.INF
	_volar_a(world_pos)
	_hold_move = true
	_hold_timer = 0.0


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
		_hud_pos.text = "(%d, %d)" % [_hero.position.x, _hero.position.y]

	# (los disparos son proyectiles que viajan, uno por AttackEvent del server:
	# ya no hay haz permanente entre las naves)

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
var _at_camara_libre := false     # el autotest suelta la camara para retratar el mapa
var _at_camara_t := -1.0
## Los bichos a los que el autotest les toma retrato de QA (uno por especie).
const AT_BESTIARIO := ["vexor", "skarn", "ferox", "skarnox"]
var _at_bicho := 0


var _at_muertes := 0


func _autotest(delta: float) -> void:
	_autotest_t += delta
	# muerto o aun sin nave: no hay nada que pilotar este frame. Sin esta guarda,
	# cualquier fase que use _hero reventaba en cuanto un Ferox hacia su trabajo.
	if _muerto or (_hero == null and _at_fase > 0):
		return
	if _autotest_t > 150.0:
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
					_volar_a(cercano.position + Vector2(120, 0))
					_at_fase = 1
		1:
			var vex: EntityNode = _entidades.get(_at_target)
			if vex == null:
				_at_fase = 0     # se murio o despawneo: buscar otro
				return
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
			if _autotest_t - _at_ultimo_vuelo > 1.5:
				var img_p := get_viewport().get_texture().get_image()
				img_p.save_png(Session.autotest_screenshot.replace(".png", "-portal.png"))
				_at_fase = 10
		10:
			# retrato de cada bicho del bestiario: la camara los visita sin volar
			# hasta ellos. Agregar un alien = agregarlo a AT_BESTIARIO, nada mas.
			if _at_bicho >= AT_BESTIARIO.size():
				_at_fase = 11
				return
			var especie: String = AT_BESTIARIO[_at_bicho]
			var bicho := _primero_de_especie(especie)
			if bicho == null:
				_at_captura("AUTOTEST FALLO — no hay ningun %s en el mapa" % especie, 1)
				return
			_camara.position = bicho.position
			if _at_camara_t < 0.0:
				_at_camara_t = _autotest_t
			if _autotest_t - _at_camara_t > 1.2:
				var img_b := get_viewport().get_texture().get_image()
				img_b.save_png(Session.autotest_screenshot.replace(".png", "-%s.png" % especie))
				_at_camara_t = -1.0
				_at_bicho += 1
		11:
			_at_camara_libre = false
			# una ventana que no se construyo (error de script en su .gd) pasaba
			# desapercibida: el autotest seguia dando OK sin minimapa
			if _minimapa == null or _chat == null or _base == null:
				_at_captura("AUTOTEST FALLO — falta una ventana (minimapa/chat/base)", 1)
				return
			_at_captura("AUTOTEST OK — loop, chat, reconexion, portal, bestiario (%d especies) y %d muerte(s)"
				% [AT_BESTIARIO.size(), _at_muertes], 0)


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
