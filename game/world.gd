# El mundo del slice: fondo generado, entidades del server, vuelo con
# prediccion local + reconciliacion contra el eco autoritativo.
# La mecanica de vuelo es la del prototipo: mantener presionado el click
# persigue al cursor (la camara sigue a la nave, asi que el punto bajo un
# cursor quieto tambien avanza), con reenvio por umbral de distancia.
extends Node2D

const CLICK_RADIUS := 34.0        # radio de click sobre entidades, en PIXELES de pantalla
const HOLD_RESEND_SEC := 0.25     # cadencia del reenvio con el boton sostenido
const HOLD_MIN_DELTA := 60.0      # el destino debe moverse al menos esto para reenviar
## Cuanto sigue un tirador encarando a su blanco tras el ultimo disparo. Los NPC
## disparan cada segundo, asi que tres aguanta un par de fallos y suelta rapido
## cuando la pelea se acaba de verdad.
const ATTACK_FACING_SEC := 3.0

# FASE 1 del plan-cliente-3d: la camara y su zoom viven en Mundo3D con las
# constantes del original (FOV 30, elevacion 45, d = 1740/zoom, zoom [1,3] con
# tween y acoplamiento tilt-zoom). El rango 0.621-1.157 calibrado para el mundo
# de sprites murio con el.

## Doble click (<500 ms) sobre una entidad = fijarla Y atacar, el gesto canonico
## del original. El primer click solo selecciona, como siempre.
const DOBLE_CLICK_MS := 500

var _conn: GameConnection
var _entidades := {}          # entity_id -> EntityNode
var _hero: EntityNode
var _mundo: Mundo3D
var _capa_juego: Node2D       # HUD del mundo (barras, nombres, numeros), proyectado
var _foco := Vector2.ZERO     # a donde mira la camara, en coordenadas de juego
var _fondo3d: Fondo3D         # el fondo completo del original (F3)
var _seq := 0
var _limites := Vector2(20800, 12800)
# zona radiactiva: cuanto se puede rebasar el limite antes del borde de
# verdad, POR LOS CUATRO LADOS — por el lado del 0 el destino va en negativo
# (Dials.RadiationMargin en el server — mismo numero en los dos lados)
const RADIACION_MARGEN := 1000.0

# vuelo sostenido (herencia del prototipo)
var _hold_move := false
var _hold_timer := 0.0
var _saltando := false
var _ultimo_click_ent := 0     # doble click: la entidad y el instante del anterior
var _ultimo_click_ms := 0
## Cursor simulado para la prueba del vuelo sostenido (INF = raton de verdad).
var _at_cursor := Vector2.INF
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
var _base: StationWindow
var _chat: ChatWindow
var _ajustes: SettingsWindow
var _sysbar: SysBar
var _respawn: RespawnPanel
var _muerto := false
var _estacion_pos := Vector2.ZERO
var _estacion_rango := 0.0
var _en_base := false
var _estacion: Node3D                            # el cuerpo de la base en la escena
var _estacion_sprite: Sprite3D                   # el camino quad (PNG o atlas), o null
var _estacion_anim_total := 0
var _estacion_anim_fps := 12.0
var _estacion_anim_t := 0.0
var _estacion_modelo: Node
var _estacion_mats: Array[BaseMaterial3D] = []
var _est_emision := 1.0
var _est_pulso_min := 0.55
var _est_pulso_max := 1.8
var _est_pulso_vel := 1.1
var _est_pulso_dureza := 1.6
var _laser_on := false
var _cajas := {}                  # box_id -> Node2D (posicion; su cuerpo vive en Mundo3D)
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
	_conn.jump_handoff.connect(_on_jump_handoff)
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

	# LA ESCENA UNICA (F1): el mundo 3D con la camara del original. Se entra en
	# el zoom mas alejado (1.0), que es el encuadre de juego.
	_mundo = Mundo3D.new()
	add_child(_mundo)
	# la capa del HUD del mundo: barras, nombres y numeros PROYECTADOS, entre el
	# 3D (debajo de todo) y las ventanas N (capas 11+)
	var capa_juego := CanvasLayer.new()
	capa_juego.layer = 5
	add_child(capa_juego)
	_capa_juego = Node2D.new()
	capa_juego.add_child(_capa_juego)
	EntityNode.capa_hud = _capa_juego
	_construir_hud()
	_estado("Abriendo enlace con %s..." % Session.game_host, NTheme.MUTED)
	_conn.connect_to(Session.game_host, Session.game_ticket)


## El fondo del mapa (F3): el Fondo3D completo del original — cielo con
## twinkle, telon, nebulosas a profundidad real, planetas, sol con flares y el
## polvo estelar anclado al mundo. Todo del data/maps/<code>.json de siempre.
func _construir_fondo(map_code: String) -> void:
	if _fondo3d != null:
		return                     # una reconexion reenvia EnterMap: no duplicar capas
	_fondo3d = Fondo3D.new()
	_mundo.add_child(_fondo3d)
	# semilla por mapa: el mismo sector monta el mismo cielo en cada visita
	var config := MapBgConfig.para(map_code, _limites)
	# pan del original: 25 grados en mapas con fondo 3D (su display3D esta
	# compuesto para esa camara), 0 en mapas planos
	_mundo.pan_grados = float(config.get("pan", 0.0))
	_fondo3d.build(config, _limites, map_code.hash())


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
	if _salto_t0 > 0:
		print("SALTO de pulsar J a tener el mapa: %d ms" % (Time.get_ticks_msec() - _salto_t0))
		_salto_t0 = 0
	# EnterMap llega tres veces por motivos distintos: al entrar, al reconectar y
	# al SALTAR de sector. Las dos primeras traen el mismo mapa y todo se conserva;
	# la tercera trae otro, y lo que sobrevive es solo lo que no pertenece al mapa
	# —las ventanas, el chat, los ajustes—. El mobiliario, las entidades y el fondo
	# son del mapa viejo y se van con el.
	if _map_code != "" and _map_code != em.map_code:
		_desmontar_mapa()
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
	if _minimapa != null:
		_minimapa.renombrar(em.map_code)
	_estado("Sector %s (%dx%d) · riesgo de carga %d%%"
		% [em.map_code, em.limits_x, em.limits_y, em.cargo_risk_pct], NTheme.MUTED)


## Tira todo lo que pertenecia al mapa anterior. Se llama SOLO al saltar: en una
## reconexion el mapa es el mismo y rehacerlo tiraria el fondo y las entidades
## para volver a construir lo idéntico.
func _desmontar_mapa() -> void:
	for id in _entidades:
		_entidades[id].queue_free()
	_entidades.clear()
	for id in _cajas:
		_cajas[id].queue_free()
	_cajas.clear()
	for id in _portales:
		_portales[id].queue_free()
	_portales.clear()
	if _estacion != null:
		_estacion.queue_free()
		_estacion = null
		_estacion_sprite = null
		_estacion_mats = []
		_estacion_anim_total = 0
	if _fondo3d != null:
		_fondo3d.queue_free()
		_fondo3d = null
	_hero = null
	_at_target = 0
	_pending_box = 0
	_caja_anim_total = 0
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
	_saltando = false


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
	_estacion = Node3D.new()
	_estacion.position = Vector3(_estacion_pos.x, 0.0, _estacion_pos.y)
	_mundo.add_child(_estacion)

	# El anillo de la zona segura, ahora GEOMETRIA en el plano: un toro fino que
	# la camara inclinada ve como la elipse que le toca — perspectiva gratis.
	var aro: Dictionary = d.get("safe_ring", {})
	var anillo := MeshInstance3D.new()
	var toro := TorusMesh.new()
	toro.inner_radius = _estacion_rango - float(aro.get("width", 3.0))
	toro.outer_radius = _estacion_rango
	var mat_aro := StandardMaterial3D.new()
	mat_aro.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_aro.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_aro.albedo_color = Color(AssetDefs.color(aro.get("color", "00E5FF"), NTheme.CYAN),
		float(aro.get("alpha", 0.22)))
	toro.material = mat_aro
	anillo.mesh = toro
	anillo.position.y = 1.0
	_estacion.add_child(anillo)

	# DOS caminos en la escena unica: la MALLA directamente en el mundo (ya sin
	# viewport intermedio — la torre ensenia su altura con la camara a 45), o el
	# quad tumbado con su PNG/atlas. La emisiva 2D del reactor viejo murio con el
	# canvas: pertenecia al PNG fijo del mundo de sprites.
	_estacion_anim_total = 0
	if Quality.nivel("collectable") >= 2 and _montar_estacion_3d(d):
		return
	var anim: Dictionary = d.get("frames", {}) if Quality.nivel("collectable") >= 2 else {}
	var tex: Texture2D
	if anim.is_empty():
		tex = load(d.get("texture", "res://assets/world/station.png"))
	else:
		tex = load(anim.get("atlas", "res://assets/world/station-anim.png"))
	# `world_size` es la HUELLA de la base; con el quad manda el ancho del
	# fotograma, como siempre
	var ancho_px := float(tex.get_width()) / maxf(float(anim.get("hframes", 1)), 1.0)
	var alto_px := float(tex.get_height()) / maxf(float(anim.get("vframes", 1)), 1.0)
	var tam := float(d.get("world_size", 820)) * alto_px / maxf(ancho_px, 1.0)
	_estacion_sprite = Mundo3D.sprite_plano(tex, tam, int(anim.get("vframes", 1)))
	if not anim.is_empty():
		_estacion_sprite.hframes = int(anim.get("hframes", 1))
		_estacion_sprite.vframes = int(anim.get("vframes", 1))
		_estacion_anim_total = int(anim.get("count",
			_estacion_sprite.hframes * _estacion_sprite.vframes))
		_estacion_anim_fps = float(anim.get("fps", 12))
		_estacion_anim_t = 0.0
	_estacion.add_child(_estacion_sprite)


func _construir_base() -> void:
	if _base != null:
		return
	var capa := CanvasLayer.new()
	capa.layer = 11
	add_child(capa)
	_base = StationWindow.crear()
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
	_taskbar.agregar("estacion", StationWindow.ICONO, "Estación",
		func(): _alternar_ventana("estacion", _base))
	_taskbar.separador()
	_taskbar.agregar("chat", ChatWindow.ICONO, "Chat", func(): _alternar_ventana("chat", _chat))
	_taskbar.agregar("minimapa", MinimapWindow.ICONO, "Minimapa",
		func(): _alternar_ventana("minimapa", _minimapa))
	for par in [["nave", _nave], ["estacion", _base], ["chat", _chat], ["minimapa", _minimapa]]:
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
			or claves.has("engine") or claves.has("luces"):
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
	if claves.has("background") and _fondo3d != null:
		_fondo3d.queue_free()
		_fondo3d = null
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
		# la cercania condiciona lo que se puede HACER; la ventana la abre y la
		# cierra el jugador desde su icono, como todas las demas (§1.5)
		_base.en_rango(msg.in_range)
		_taskbar.marcar("estacion", _base.visible)
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
func esquinas_encuadre() -> Array[Vector2]: return _mundo.esquinas_encuadre()
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
		_foco = nodo.position
		_mundo.actualizar(_foco)


func _on_despawn(dp) -> void:
	if _entidades.has(dp.entity_id):
		_anotar_si_se_ve(_entidades[dp.entity_id], "EntityDespawn(razon %d)" % dp.reason)
		_entidades[dp.entity_id].queue_free()
		_entidades.erase(dp.entity_id)
	# Si se va lo que tenías fichado, la selección se va con ello. Hoy el server
	# protege al objetivo de salir por rango, así que esto no debería dispararse
	# nunca — pero si algún día lo hace, el síntoma sería la tecla de disparo sin
	# hacer nada y sin decir por qué, que es de los peores que hay.
	if _seleccionada == dp.entity_id:
		_seleccionada = 0
		_laser_on = false
		if _hero != null:
			_hero.set_attack_target(null)


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
	# el disparo: un HAZ del original (F2) que nace de la boca de cañón viva del
	# tirador, se estira hasta el blanco y fluye por UV-scroll
	if tirador != null:
		var ammo: String = ev.ammo_id if ev.ammo_id != "" else "ammo_cel_1"
		Beam3D.fire(tirador, blanco, ammo, ev.skilled)
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
		if tirador != _hero:
			tirador.set_attack_target(blanco, ATTACK_FACING_SEC)

	if ev.missed:
		_numero_flotante(blanco, "MISS", HIT_RECIBES if blanco == _hero else HIT_HACES)
		return

	blanco.set_estado_abs(ev.target_hp, ev.target_shield)
	# impacto: en el escudo si aún queda, en el casco si no
	if ev.target_shield > 0 and tirador != null:
		blanco.impacto_escudo(tirador.position)
	else:
		blanco.impacto_casco()
	# Aqui NO hay shake de camara, y no es un olvido: el original tampoco sacude
	# con dano normal. Su shakeScreen() solo dispara con el tipo de dano "I"
	# (detonaciones tipo mina/kamikaze) y con efectos que declaran
	# shakeScreen="true" en su XML — verificado jugando DO 3D y confirmado en el
	# decompilado. Se porto por error, se sintio mal, y la prueba en vivo mando.
	# Si v1 gana minas, la receta esta en el historial (espiral 24 ms en offset).
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
		vivo.position = _mundo.a_pantalla(sobre.position) + Vector2(-60, -90)
		return

	# 24: registrado en el §9 del sistema de diseño. Desde F1 el numero vive en
	# el HUD proyectado (pixeles de pantalla), asi que ya no lo encoge el zoom.
	var label := NTheme.label(texto, NTheme.mono(), 24, color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("outline_size", 6)
	label.custom_minimum_size = Vector2(120, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# el numero vive en el HUD proyectado (pixeles): el zoom ya no lo encoge
	label.position = _mundo.a_pantalla(sobre.position) + Vector2(-60, -90)
	label.z_index = 20
	if texto.is_valid_int():
		label.set_meta("suma", int(texto))
	_capa_juego.add_child(label)
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
		if Quality.nivel("explosion") < 1:
			# sin explosión dibujada, una muerte se ve EXACTAMENTE como una
			# desaparición: si el bicho que se esfumó fue esto, hay que saberlo
			_anotar_si_se_ve(nodo, "EntityDestroyed sin explosión (calidad)")
		_explotar(nodo.position, nodo.click_radius)
		nodo.queue_free()
		_entidades.erase(msg.entity_id)
	if _seleccionada == msg.entity_id:
		_seleccionada = 0
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
func _anotar_si_se_ve(nodo: EntityNode, motivo: String) -> void:
	if _hero == null or nodo == _hero:
		return
	var visible_rect := get_viewport_rect().size * _mundo.unidades_por_pixel()
	var radio := visible_rect.length() * 0.5
	var d := _hero.position.distance_to(nodo.position)
	if d > radio:
		return                    # se fue fuera de pantalla: es lo esperado
	var f := FileAccess.open("res://logs/anomalias.log", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("res://logs/anomalias.log", FileAccess.WRITE)
	if f == null:
		return                    # sin sitio donde anotar, no se estorba al juego
	f.seek_end()
	f.store_line("%s · %s (%s) a %d u · radio visible %d u · %s"
		% [Time.get_datetime_string_from_system(), nodo.type_id, nodo.entity_id,
			int(d), int(radio), motivo])
	f.close()


## La explosion multi-capa del original (guidelines 3D, §9.4): el flipbook del
## pipeline + un FLASH central de un instante + una rafaga de CHISPAS radiales
## aditivas. El flash escala con el radio de click de la victima — un Skarnox no
## revienta como un Vex.
var _tex_flash: GradientTexture2D
var _pm_chispas: ParticleProcessMaterial
var _tex_chispa: GradientTexture2D


func _explotar(pos: Vector2, radio := 42.0) -> void:
	if Quality.nivel("explosion") < 1:
		return                    # el evento sigue ocurriendo; solo no se dibuja
	var anim := AnimatedSprite3D.new()
	anim.sprite_frames = _frames_explosion
	anim.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	anim.shaded = false
	anim.pixel_size = 1.4
	anim.position = Vector3(pos.x, 20.0, pos.y)
	_mundo.add_child(anim)
	anim.play("boom")
	anim.animation_finished.connect(anim.queue_free)

	# FLASH: un resplandor radial que nace a cero, revienta en 0.25 s y muere.
	# Es la capa que "vende" el estallido; textura procedural, cero assets.
	if _tex_flash == null:
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 0.95, 0.8, 1.0))
		g.set_color(1, Color(1.0, 0.5, 0.1, 0.0))
		_tex_flash = GradientTexture2D.new()
		_tex_flash.gradient = g
		_tex_flash.width = 256
		_tex_flash.height = 256
		_tex_flash.fill = GradientTexture2D.FILL_RADIAL
		_tex_flash.fill_from = Vector2(0.5, 0.5)
		_tex_flash.fill_to = Vector2(0.5, 0.0)
	var flash := Mundo3D.quad_aditivo(_tex_flash, 256.0)
	flash.position = Vector3(pos.x, 25.0, pos.y)
	flash.scale = Vector3.ONE * 0.01
	_mundo.add_child(flash)
	# el diametro final ~6x el radio de click (la proporcion del original:
	# flash de 250 para naves de ~80 de radio)
	var escala_flash := radio * 6.0 / 256.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(flash, "scale", Vector3.ONE * escala_flash, 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash, "transparency", 1.0, 0.2).set_delay(0.05)
	tw.chain().tween_callback(flash.queue_free)

	# CHISPAS: rafaga radial de un disparo en el plano del juego, velocidades y
	# vidas aleatorias (la desincronizacion estadistica del original).
	if _pm_chispas == null:
		_pm_chispas = ParticleProcessMaterial.new()
		_pm_chispas.direction = Vector3(1, 0, 0)
		_pm_chispas.spread = 180.0
		_pm_chispas.flatness = 1.0        # la rafaga vive en el plano, como el mundo
		_pm_chispas.initial_velocity_min = 100.0
		_pm_chispas.initial_velocity_max = 200.0
		_pm_chispas.gravity = Vector3.ZERO
		_pm_chispas.scale_min = 0.02
		_pm_chispas.scale_max = 0.05
		_pm_chispas.lifetime_randomness = 0.8
		var rampa := Gradient.new()
		rampa.set_color(0, Color(1.0, 1.0, 0.9, 1.0))
		rampa.add_point(0.4, Color(1.0, 0.7, 0.3, 0.8))
		rampa.set_color(1, Color(1.0, 0.3, 0.1, 0.0))
		var rt := GradientTexture1D.new()
		rt.gradient = rampa
		_pm_chispas.color_ramp = rt
		var gc := Gradient.new()
		gc.set_color(0, Color.WHITE)
		gc.set_color(1, Color(1, 1, 1, 0))
		_tex_chispa = GradientTexture2D.new()
		_tex_chispa.gradient = gc
		_tex_chispa.width = 32
		_tex_chispa.height = 32
		_tex_chispa.fill = GradientTexture2D.FILL_RADIAL
		_tex_chispa.fill_from = Vector2(0.5, 0.5)
		_tex_chispa.fill_to = Vector2(0.5, 0.0)
	# el destello de la explosion (pool de luces del mundo; preset del original:
	# 0xDEE4C8, fallOff 400, encendida ~0.1 s)
	_mundo.luz_efecto(Vector3(pos.x, 30.0, pos.y), Color("dee4c8"), 2.0, 400.0, 0.1, 0.25)

	var chispas := GPUParticles3D.new()
	chispas.amount = 24
	chispas.one_shot = true
	chispas.explosiveness = 1.0
	chispas.lifetime = 0.8
	chispas.process_material = _pm_chispas
	chispas.draw_pass_1 = _malla_chispa()
	chispas.position = Vector3(pos.x, 20.0, pos.y)
	chispas.emitting = true
	_mundo.add_child(chispas)
	chispas.finished.connect(chispas.queue_free)


var _malla_chispa_cache: QuadMesh


func _malla_chispa() -> QuadMesh:
	if _malla_chispa_cache == null:
		_malla_chispa_cache = QuadMesh.new()
		_malla_chispa_cache.size = Vector2(32, 32)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_texture = _tex_chispa
		m.vertex_color_use_as_albedo = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_malla_chispa_cache.material = m
	return _malla_chispa_cache


func _on_box_spawn(msg) -> void:
	_crear_caja(msg.box_id, Vector2(msg.x, msg.y))


func _crear_caja(box_id: int, pos: Vector2) -> void:
	if _cajas.has(box_id):
		return
	# todas las particularidades de la caja salen de su JSON (data/props/cargo-box.json)
	# El nodo del diccionario sigue siendo un Node2D con `position` en juego —
	# todo el flujo de recoger/minimapa lo lee asi—; su CUERPO es un quad en la
	# escena unica, que muere con el (tree_exited).
	var d := AssetDefs.prop("cargo-box")
	var caja := Node2D.new()
	caja.position = pos
	add_child(caja)
	var cuerpo := Node3D.new()
	cuerpo.position = Vector3(pos.x, 1.0, pos.y)
	_mundo.add_child(cuerpo)
	caja.tree_exited.connect(func(): if is_instance_valid(cuerpo): cuerpo.queue_free())

	var anim: Dictionary = d.get("frames", {}) if Quality.nivel("collectable") >= 2 else {}
	var tex: Texture2D
	if anim.is_empty():
		tex = load(d.get("texture", "res://assets/world/cargo-box-still.png"))
	else:
		tex = load(anim.get("atlas", ""))
	var alto_px := float(tex.get_height()) / maxf(float(anim.get("vframes", 1)), 1.0)
	var ancho_px := float(tex.get_width()) / maxf(float(anim.get("hframes", 1)), 1.0)
	var tam := float(d.get("world_size", 48)) * alto_px / maxf(ancho_px, 1.0)
	var s := Mundo3D.sprite_plano(tex, tam, int(anim.get("vframes", 1)))
	if not anim.is_empty():
		s.hframes = int(anim.get("hframes", 1))
		s.vframes = int(anim.get("vframes", 1))
		_caja_anim_total = int(anim.get("count", s.hframes * s.vframes))
		_caja_anim_fps = float(anim.get("fps", 12.0))
		# desfase por caja: un campo de cajas parpadeando a la vez canta a bucle
		caja.set_meta("anim_t", randf() * float(_caja_anim_total) / maxf(_caja_anim_fps, 1.0))
		caja.set_meta("sprite", s)
	cuerpo.add_child(s)
	# la banda emisiva late en ALFA para llamar al jugador (fase por caja). Una
	# caja de atlas no la lleva: su luz ya viene cocida en los fotogramas.
	if anim.is_empty() and d.has("emissive") and Quality.nivel("emissive") >= 1:
		var brillo := Mundo3D.sprite_plano(load(d.emissive), tam)
		brillo.position.y = 1.5
		cuerpo.add_child(brillo)
		var p: Dictionary = d.get("pulse", {})
		var medio: float = float(p.get("half_period", 0.9))
		var tw := caja.create_tween().set_loops()
		tw.tween_property(brillo, "modulate:a", float(p.get("min_alpha", 0.25)), medio) \
			.set_trans(Tween.TRANS_SINE)
		tw.tween_property(brillo, "modulate:a", float(p.get("max_alpha", 1.0)), medio) \
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


## El `detail` del server manda cuando lo trae. Antes se traducia el CODIGO a un
## texto fijo —"Demasiado lejos de la caja"— y en cuanto el salto de sector
## empezo a usar el mismo TOO_FAR, ese texto pasaba a mentir. Un codigo dice de
## que FAMILIA es el fallo; solo quien lo emite sabe de que iba.
func _on_error(e) -> void:
	# `request_id != 0` = es la RESPUESTA a algo que pedimos (el salto). Con 0, el
	# server cuenta algo por su cuenta — hoy, que el láser espera fuera de alcance.
	# Sin esa distinción, ese aviso daba por bueno el salto y la prueba mentía:
	# justo lo que advierte el comentario de arriba sobre compartir un código.
	_at_salto_rechazado = _at_salto_rechazado \
		or (e.code == MexProtocol.ErrorCode.TOO_FAR and e.request_id != 0)
	if e.detail != "":
		_estado(e.detail, NTheme.HOSTILE if e.code != MexProtocol.ErrorCode.GONE else NTheme.MUTED)
		return
	match e.code:
		MexProtocol.ErrorCode.TOO_FAR: _estado("Demasiado lejos", NTheme.HOSTILE)
		MexProtocol.ErrorCode.GONE: _estado("Ya no está", NTheme.MUTED)
		MexProtocol.ErrorCode.INSUFFICIENT: _estado("Bodega llena", NTheme.HOSTILE)
		_: _estado("ErrorReply %d" % e.code, NTheme.HOSTILE)


func _unhandled_input(event: InputEvent) -> void:
	# J: saltar de sector. Es tecla y no clic a proposito — ver `_handle_click`.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_J \
			and (_chat == null or not _chat.tiene_foco()):
		_intentar_salto()
		get_viewport().set_input_as_handled()
		return
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
				var punto := _mundo.a_mundo(get_viewport().get_mouse_position())
				if punto != Vector2.INF:
					_handle_click(punto)
			MOUSE_BUTTON_WHEEL_UP:
				_mundo.zoom_por_rueda(true)
			MOUSE_BUTTON_WHEEL_DOWN:
				_mundo.zoom_por_rueda(false)
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
		var caja: Node2D = _cajas[caja_id]
		_volar_a(caja.position)
		_pending_box = caja_id
		_pending_box_pos = caja.position
		_estado("Recogiendo caja…", NTheme.MUTED)
		return
	# ¿click sobre una entidad? seleccionar, no volar (como el prototipo).
	# DOBLE click sobre la misma = fijarla y ATACAR, el gesto canonico del original.
	var bajo := _entity_at(world_pos)
	if bajo != null:
		var ahora := Time.get_ticks_msec()
		var doble: bool = bajo.entity_id == _ultimo_click_ent \
			and ahora - _ultimo_click_ms < DOBLE_CLICK_MS
		_ultimo_click_ent = bajo.entity_id
		_ultimo_click_ms = ahora
		_seleccionar(bajo)
		if doble and not _laser_on:
			_toggle_laser()
		return
	# ¿click sobre un portal? Si ya estamos encima, ACTIVAR; si no, rumbo a el.
	var portal := _portal_at(world_pos)
	if portal != null:
		_pending_box = 0
		if not portal.is_working:
			_estado("Ese portal está inactivo", NTheme.VIOLET)
			return
		# El clic solo pone rumbo. Saltar es de la TECLA (J): con el salto en el
		# clic, aterrizar encima del portal de vuelta lo re-disparaba solo.
		_autopilot = portal.position
		_volar_a(portal.position)
		_estado("Rumbo al portal · sector %s · pulsa J para saltar"
			% portal.target_map_code, NTheme.VIOLET)
		return
	# click en vacio: volar; mientras siga presionado, _process persigue al cursor
	# (el vuelo manual cancela el autopiloto, como en el prototipo)
	_pending_box = 0
	_autopilot = Vector2.INF
	_hold_move = true
	_hold_timer = 0.0
	if not _cerca_del_heroe(world_pos):
		_volar_a(world_pos)


## El portal al alcance del salto, si lo hay. El server valida el rango otra vez:
## el cliente propone, el server dispone.
func _portal_al_alcance() -> PortalNode:
	if _hero == null:
		return null
	for id in _portales:
		var p: PortalNode = _portales[id]
		if p.is_working and _hero.position.distance_to(p.position) <= PortalNode.RANGO_SALTO:
			return p
	return null


## Saltar. La peticion sale cuando ARRANCA el encendido, no cuando termina: los
## 2,1 s de animacion son exactamente el hueco donde cabe el viaje al server.
func _intentar_salto() -> void:
	var portal := _portal_al_alcance()
	if portal == null:
		_estado("No hay ningún portal al alcance", NTheme.MUTED)
		return
	if not portal.activar():
		# sin atlas (calidad media o baja) no hay animacion que esperar: el salto
		# es instantaneo y eso es lo correcto ahi
		_salto_portal = null
	else:
		_salto_portal = portal
		if not portal.encendido_terminado.is_connected(_on_encendido_listo):
			portal.encendido_terminado.connect(_on_encendido_listo)
	_salto_t0 = Time.get_ticks_msec()
	_req_id += 1
	var salto := MexProtocol.JumpRequest.new()
	salto.request_id = _req_id
	salto.portal_id = portal.portal_id
	_conn.send(salto.encode())
	_estado("Saltando al sector %s…" % portal.target_map_code, NTheme.VIOLET)


## El destino lo sirve otro servidor — o el mismo, que el cliente ni lo mira. Se
## reconecta con el token que ya tiene: el estado de la nave quedo persistido en
## el mapa destino antes de que el server cerrara, asi que reconectar aterriza
## donde toca.
## El encendido llego a su ultimo fotograma: se suelta la llegada, que lleva
## esperando desde que la conexion nueva termino de sincronizar.
func _on_encendido_listo(_portal_id: int) -> void:
	_salto_portal = null
	_conn.soltar()


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
	var esquema := "wss" if msg.is_tls else "ws"
	var url := "%s://%s:%d/ws" % [esquema, msg.host, msg.port]
	_estado("Enlazando con el sector %s…" % msg.map_code, NTheme.VIOLET)
	# Se conecta YA, en paralelo a la animacion, y se RETIENE lo que llegue. El
	# hueco de 2,1 s absorbe asi tambien el coste de abrir el socket contra el
	# server del destino, que es el que se vuelve caro al partir la carga.
	_saltando = true
	_conn.retener()
	_conn.saltar_a(url)
	# sin animacion que esperar (calidad media o baja) no hay nada que retener
	if _salto_portal == null or not is_instance_valid(_salto_portal):
		_conn.soltar()


func _portal_at(world_pos: Vector2) -> PortalNode:
	for id in _portales:
		var p: PortalNode = _portales[id]
		if p.position.distance_to(world_pos) < p.click_radius:
			return p
	return null


func _box_at(world_pos: Vector2) -> int:
	var min_radius := CLICK_RADIUS * _mundo.unidades_por_pixel()
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
	var min_radius := CLICK_RADIUS * _mundo.unidades_por_pixel()
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
	if not _sigue_pulsado():
		_hold_move = false
		return
	_hold_timer += delta
	if _hold_timer < HOLD_RESEND_SEC:
		return
	_hold_timer = 0.0
	var target := _cursor_mundo()
	if target.distance_to(_last_sent_target) >= HOLD_MIN_DELTA and not _cerca_del_heroe(target):
		_volar_a(target)


## El clic sobre la propia nave (o muy cerca) nunca cuenta como orden de
## vuelo — igual que DarkOrbit: el usuario lo confirmo jugando el original
## y aqui era ademas la ultima fuente real del "brinco" (31-ago): un destino
## practicamente encima de la nave deja `en_vuelo` en falso desde el
## arranque, asi que la correccion de reconcile() nunca se difiere (el
## guardia de "solo corrige si esta quieta" no protege lo que YA esta
## quieto) y cada eco del server se aplicaba directo. `_entity_at` ya excluye
## al heroe de la seleccion (linea de arriba, "if e == _hero: continue");
## esto es el mismo criterio aplicado al vuelo libre.
func _cerca_del_heroe(punto: Vector2) -> bool:
	return _hero != null and _hero.position.distance_to(punto) < _hero.click_radius


func _sigue_pulsado() -> bool:
	if _at_cursor != Vector2.INF:
		return true                       # la prueba sostiene el boton por su cuenta
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _cursor_mundo() -> Vector2:
	if _at_cursor != Vector2.INF:
		return _at_cursor
	var punto := _mundo.a_mundo(get_viewport().get_mouse_position())
	return punto if punto != Vector2.INF else (_hero.position if _hero != null else Vector2.ZERO)


func _volar_a(destino: Vector2) -> void:
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
	if _saltando:
		return
	# zona radiactiva: se puede rebasar el limite del mapa y seguir volando
	# (con danio por segundo, ver el server), asi que el clamp de aqui ya NO es
	# al limite a secas — es al mismo margen que aplica el server, por los
	# cuatro lados (negativo por el lado del 0), para que cliente y autoridad
	# sigan coincidiendo en el destino. El `Vector2.ZERO` que habia aqui era
	# una de las capas que dejaban el borde izquierdo/superior en pared.
	var margen := Vector2.ONE * RADIACION_MARGEN
	destino = destino.clamp(-margen, _limites + margen)
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
	if _fondo3d != null:
		_fondo3d.update(_foco, delta)

	# la base animada avanza sus fotogramas
	if _estacion_anim_total > 0 and _estacion_sprite != null:
		_estacion_anim_t += delta
		_estacion_sprite.frame = int(_estacion_anim_t * _estacion_anim_fps) % _estacion_anim_total

	# La estacion 3D RESPIRA por su emision. Es el mismo latido que tenia la capa
	# emisiva en 2D —los mismos diales `pulse` de su ficha— aplicado a la emision
	# del material en vez de al alfa de un sprite encima.
	#
	# Sin esto la emision es un color pintado en la textura: se ve encendida en la
	# foto y muerta en movimiento. Lo que hace que una luz parezca luz no es el
	# brillo, es que cambie.
	if not _estacion_mats.is_empty():
		var t := Time.get_ticks_msec() * 0.001 * _est_pulso_vel
		var w := pow(0.5 + 0.5 * sin(t), _est_pulso_dureza)
		var e: float = _est_emision * (_est_pulso_min + (_est_pulso_max - _est_pulso_min) * w)
		for mat in _estacion_mats:
			mat.emission_energy_multiplier = e

	# la camara del original: seguimiento RIGIDO al heroe (o al foco libre del
	# autotest); Mundo3D pone el rig orbital, el zoom y el tilt-zoom
	if _hero != null and not _at_camara_libre:
		_foco = _hero.position
		_nave.poner_texto("posicion", "(%d, %d)" % [_hero.position.x, _hero.position.y])
	_mundo.actualizar(_foco)
	# El HUD (nombre/barras) se proyecta AQUI, explicitamente despues de mover
	# la camara — nunca dentro del _process de cada EntityNode (ver el
	# comentario grande en sincronizar_hud()): es la unica forma de que la
	# posicion (ya actualizada, las entidades procesan con prioridad -10,
	# antes que World) y la camara (recien actualizada arriba) esten frescas
	# A LA VEZ para el mismo fotograma.
	for e: EntityNode in _entidades.values():
		e.sincronizar_hud()

	# (los disparos son proyectiles que viajan, uno por AttackEvent del server:
	# ya no hay haz permanente entre las naves)

	if _caja_anim_total > 0:
		for caja in _cajas.values():
			var s: Sprite3D = caja.get_meta("sprite", null)
			if s == null:
				continue
			var t: float = float(caja.get_meta("anim_t", 0.0)) + delta
			caja.set_meta("anim_t", t)
			s.frame = int(t * _caja_anim_fps) % _caja_anim_total

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
var _at_portal_animado := false
var _salto_portal: PortalNode = null
var _salto_t0 := 0
var _at_salto_pedido := false
var _at_salto_origen := ""
var _at_salto_destino := ""
var _at_salto_llegada := Vector2.ZERO
var _at_salto_camara := 0.0
var _at_salto_portal: PortalNode = null
var _at_salto_rechazado := false     # el autotest suelta la camara para retratar el mapa
var _at_camara_t := -1.0
## Los bichos a los que el autotest les toma retrato de QA (uno por especie).
const AT_BESTIARIO := ["vex", "vexor", "skarn", "ferox", "skarnox", "gravit", "mordax", "gravon", "vorax"]
var _at_bicho := 0
var _at_relieve := -1                      # paso de la prueba del relieve
var _at_casco_a := PackedFloat32Array()
var _at_relieve_resto := 0.0
var _at_mov_bicho := {}                    # especie -> cuanto se movio entre sus dos retratos
var _at_relieve_previo := 0.0
var _at_giro_a := 0.0
var _at_primer_frame := false
## Ejemplar fabricado para el retrato cuando la especie no anda cerca.
var _at_maniqui: EntityNode = null
var _at_cambio_calidad := false
var _at_calidad_previa := "alta"
var _at_caza_desde := 0.0
var _at_caza_dist := 0.0
var _at_shot_caja := false


var _at_muertes := 0


func _autotest(delta: float) -> void:
	_autotest_t += delta
	# muerto o aun sin nave: no hay nada que pilotar este frame. Sin esta guarda,
	# cualquier fase que use _hero reventaba en cuanto un Ferox hacia su trabajo.
	if _muerto or (_hero == null and _at_fase > 0):
		return
	# modo SALTO: volar hasta el portal y cruzarlo de verdad. Va aparte de la
	# pasada del loop porque el portal del 1-1 esta a ~19.000 unidades de la base
	# y llegar cuesta un minuto: meterlo en la puerta rapida la doblaria de largo.
	if Session.autotest_modo == "salto":
		_autotest_salto()
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
				var cercano := _mejor_presa()
				if cercano == null:
					# NO SE VE EL MAPA ENTERO.
					#
					# Con relevancia por rango el bot solo conoce lo que tiene a
					# 2000 unidades. Quedarse quieto esperando presa era una
					# moneda al aire: con 15 Vex repartidos en 20800x12800, la
					# probabilidad de tener uno a la vista al entrar es ~51%.
					# Patrullar es lo que haria un jugador, y de paso ejercita el
					# spawn/despawn por rango — que es justo lo que hay que probar.
					_at_patrullar()
					return
				_at_target = cercano.entity_id
				_at_caza_desde = _autotest_t
				_at_caza_dist = _hero.position.distance_to(cercano.position)
				_volar_a(cercano.position + Vector2(120, 0))
				_at_fase = 1
		1:
			var vex: EntityNode = _entidades.get(_at_target)
			if vex == null:
				_at_fase = 0     # se murio o despawneo: buscar otro
				return
			# Techo duro de la FASE, no de la presa. Reevaluar quita el runaway en
			# la practica, pero no lo prohibe: si ningun Vex se acercara nunca,
			# esto correria para siempre. Y un fallo con nombre —"la caza no
			# cerro en 45 s"— vale mil veces mas que un TIMEOUT generico, que no
			# dice en que se atasco ni por que.
			if _autotest_t - _at_caza_desde > 45.0:
				_at_captura("AUTOTEST FALLO — la caza no logro ponerse a tiro en 45 s "
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
			if _autotest_t - _at_ultimo_vuelo > 2.0:
				_at_ultimo_vuelo = _autotest_t
				# `_mejor_presa` ya ordena por tiempo de intercepcion, asi que si
				# devuelve otra es que se llega antes a esa. El margen del 20% de
				# la version anterior sobra: no hay que evitar un baile entre
				# equidistantes, porque dos presas equidistantes con rumbos
				# distintos NO valen lo mismo.
				var otro := _mejor_presa()
				if otro != null and otro.entity_id != _at_target:
					_at_target = otro.entity_id
					vex = otro
				if _hero.position.distance_to(vex.position) > 450.0:
					_volar_a(vex.position + Vector2(120, 0))
			if _hero.position.distance_to(vex.position) < 450.0:
				_seleccionar(vex)
				_laser_on = true
				var msg := MexProtocol.LaserToggle.new()
				msg.active = true
				_conn.send(msg.encode())
				# el minimo teorico es (distancia - alcance) / velocidad de la nave:
				# si el tiempo real se le parece, no hay nada que arreglar — es viaje
				var t_min: float = maxf(_at_caza_dist - 450.0, 0.0) / maxf(_hero.speed, 1.0)
				print("AUTOTEST caza: %.1f s (presa inicial a %.0f u · minimo teorico %.1f s)"
					% [_autotest_t - _at_caza_desde, _at_caza_dist, t_min])
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
				# al ENTRAR en rango la Estacion se abre sola y sus acciones se
				# encienden; el icono de la taskbar tiene que enterarse
				if not _base.visible or not _taskbar.esta_marcado("estacion"):
					_at_captura("AUTOTEST FALLO — la Estacion no se abrio al llegar a la base", 1)
					return
				if not _base.acciones_activas():
					_at_captura("AUTOTEST FALLO — en la base y las acciones siguen bloqueadas", 1)
					return
				# retrato de la ESTACION. La fase decia desde siempre que servia
				# para revisar su arte y no guardaba nada; ahora si.
				var img_b := get_viewport().get_texture().get_image()
				img_b.save_png(Session.autotest_screenshot.replace(".png", "-base.png"))
				_at_ultimo_vuelo = _autotest_t
				_req_id += 1
				var msg := MexProtocol.UnloadCargo.new()
				msg.request_id = _req_id
				_conn.send(msg.encode())
				_at_fase = 5
		5:
			# almacen recibido: vender el primer material que el NPC compre DE LOS
			# QUE HAY. Antes vendia "material_asterium" a ciegas y se colgaba la
			# tarde que los bichos no soltaban ese: la prueba esperaba para
			# siempre una confirmacion que no iba a llegar. Una prueba no puede
			# depender de que la suerte reparta un material concreto.
			if _at_descargado and _autotest_t - _at_ultimo_vuelo > 1.0:
				_at_ultimo_vuelo = _autotest_t
				var material := _base.primer_vendible()
				if material == "":
					_at_captura("AUTOTEST FALLO — el almacen quedo sin nada que el NPC compre", 1)
					return
				_req_id += 1
				var venta := MexProtocol.SellToNpc.new()
				venta.request_id = _req_id
				venta.material_id = material
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
				_foco = _portales.values()[0].position
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
			# El salto pedido de LEJOS tiene que ser rechazado por el server. Es
			# barato —no hay que volar 19.000 unidades— y prueba el cableado
			# entero: mensaje, ruta, validacion y ErrorReply de vuelta. El salto
			# que SI funciona se prueba en el modo -Salto, que si vuela.
			if not _at_salto_pedido and not _portales.is_empty():
				_at_salto_pedido = true
				_req_id += 1
				var lejos := MexProtocol.JumpRequest.new()
				lejos.request_id = _req_id
				lejos.portal_id = _portales.values()[0].portal_id
				_conn.send(lejos.encode())

			# Lejos de la base: la ventana se abre igual —para mirar el almacen—
			# pero descargar y vender siguen bloqueados. Que un boton exista y
			# este apagado ensenia que ahi hay algo; que la ventana desaparezca
			# no ensenia nada.
			if not _en_base:
				if not _base.visible:
					_alternar_ventana("estacion", _base)
				if not _base.visible:
					_at_captura("AUTOTEST FALLO — la Estacion no se abre lejos de la base", 1)
					return
				if _base.acciones_activas():
					_at_captura("AUTOTEST FALLO — se puede vender lejos de la base", 1)
					return
				_alternar_ventana("estacion", _base)

			_alternar_ventana("nave", _nave)
			if _nave.visible or _taskbar.esta_marcado("nave"):
				_at_captura("AUTOTEST FALLO — la taskbar no cerro la ventana Nave", 1)
				return
			_alternar_ventana("nave", _nave)
			if not _nave.visible or not _taskbar.esta_marcado("nave"):
				_at_captura("AUTOTEST FALLO — la taskbar no reabrio la ventana Nave", 1)
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
			for i in _minimapa.pasos_zoom():
				_minimapa.zoom_a(i)
				if _minimapa.deformacion() > 0.02:
					_at_captura("AUTOTEST FALLO — el minimapa se deforma en el paso %d (%.3f)"
						% [i, _minimapa.deformacion()], 1)
					return
			_minimapa.zoom_a(2)
			_at_ultimo_vuelo = _autotest_t
			_at_fase = 95
		95:
			if _autotest_t - _at_ultimo_vuelo > 0.5:
				if not _at_salto_rechazado:
					_at_captura("AUTOTEST FALLO — el server no rechazo un salto desde lejos", 1)
					return
				# ya hubo fotogramas de sobra para que el layout se asiente
				if not _minimapa.canvas_cuadra():
					_at_captura("AUTOTEST FALLO — el canvas del minimapa no mide lo que dice", 1)
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
				_mundo.zoom_directo(Mundo3D.ZOOM_MAX)
				_at_fase = 96
		96:
			if _autotest_t - _at_ultimo_vuelo > 0.4:
				var img_z := get_viewport().get_texture().get_image()
				img_z.save_png(Session.autotest_screenshot.replace(".png", "-zoom.png"))
				_mundo.zoom_directo(Mundo3D.ZOOM_MIN)
				_at_fase = 93
		93:
			_at_captura("AUTOTEST OK — loop, chat, reconexion, portal, ajustes, ventanas, bestiario (%d especies) y %d muerte(s)"
				% [AT_BESTIARIO.size(), _at_muertes], 0)


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
func _movimiento_retrato() -> float:
	var esp: String = AT_BESTIARIO[_at_bicho]
	var a := _leer_png(Session.autotest_screenshot.replace(".png", "-%s-alta.png" % esp))
	var b := _leer_png(Session.autotest_screenshot.replace(".png", "-%s-alta-b.png" % esp))
	if a == null or b == null or a.get_size() != b.get_size():
		return NAN
	var w := a.get_width()
	var h := a.get_height()
	var dif := 0.0
	var brillo := 0.0
	for y in range(int(h * 0.30), int(h * 0.70), 2):
		for x in range(int(w * 0.35), int(w * 0.65), 2):
			var la := a.get_pixel(x, y).get_luminance()
			var lb := b.get_pixel(x, y).get_luminance()
			dif += absf(la - lb)
			brillo += la
	return dif / maxf(brillo, 0.0001)


func _leer_png(ruta: String) -> Image:
	if not FileAccess.file_exists(ruta):
		return null
	return Image.load_from_file(ruta)


func _relieve_paso() -> int:
	# F1 del plan-cliente-3d: el relieve murio con los sprites. En la escena
	# unica la propiedad que esta prueba defendia —que la luz NO gire con la
	# nave— se cumple por construccion: gira el cuerpo dentro del mundo y la luz
	# direccional se queda quieta. `es_3d()` es true para todo cuerpo.
	return 1


## Cuanto se diferencian dos fotos del casco, como fraccion de su brillo medio.
## Las dos son de la nave en el MISMO sitio y el mismo rumbo, asi que aqui no hay
## rotacion ni remuestreo: si el shader ignorase `giro`, esto seria cero exacto.
func _diferencia_casco(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var dif := 0.0
	var brillo := 0.0
	var n := 0
	for i in a.size():
		var va: float = a[i]
		var vb: float = b[i]
		if is_nan(va) or is_nan(vb):
			continue
		dif += absf(va - vb)
		brillo += va
		n += 1
	if n < 400 or brillo <= 0.0001:
		return NAN
	return dif / brillo


## La estacion como MALLA, directamente EN la escena unica (F1): ya no hay
## viewport intermedio ni camara propia — es una torre en el mundo y la camara
## a 45 grados le ensenia la altura sola, que es justo lo que su elevacion
## oblicua fingia antes. Devuelve false si no hay modelo y se cae al quad.
func _montar_estacion_3d(d: Dictionary) -> bool:
	var ruta := str(d.get("modelo", ""))
	if ruta == "" or not ResourceLoader.exists(ruta):
		return false
	var escena: PackedScene = load(ruta)
	if escena == null:
		push_warning("estacion: no se pudo cargar %s; se cae al quad" % ruta)
		return false
	_estacion_modelo = escena.instantiate()
	_estacion.add_child(_estacion_modelo)
	# `world_size` es la HUELLA (lo que rodea el anillo): se escala contra la
	# extension en planta del modelo, como los bichos.
	var ext := AssetDefs.extension_3d(_estacion_modelo)
	(_estacion_modelo as Node3D).scale = Vector3.ONE * (float(d.get("world_size", 820)) / ext)
	_estacion_mats = AssetDefs.materiales_3d(_estacion_modelo)
	if _estacion_mats.is_empty():
		push_warning("estacion 3D sin materiales: la emision no va a latir")
	_est_emision = float(d.get("emision", 1.0))
	var pul: Dictionary = d.get("pulse", {})
	_est_pulso_min = float(pul.get("min_intensity", 0.55))
	_est_pulso_max = float(pul.get("max_intensity", 1.8))
	_est_pulso_vel = float(pul.get("speed", 1.1))
	_est_pulso_dureza = float(pul.get("sharpness", 1.6))
	return true


## Deja en el mundo SOLO al heroe, para las dos fotos de la prueba del relieve.
##
## Sin esto la comparacion no distingue nada, y el motivo es geometrico: al
## deshacer el giro de la nave, el FONDO queda girado — y el fondo no gira. Su
## diferencia entra igual en las dos mitades del cociente y lo empuja a 1 tanto si
## el relieve funciona como si no. Con la nave sola sobre negro, el negro no suma
## en ninguna de las dos y lo unico que se compara es el casco.
func _solo_heroe(activo: bool) -> void:
	if _fondo3d != null:
		_fondo3d.visible = not activo
	if _estacion != null:
		_estacion.visible = not activo
	for e in _entidades.values():
		if e != _hero:
			e.visible = not activo
	for c in _cajas.values():
		c.visible = not activo
	for pt in _portales.values():
		pt.visible = not activo
	_hero.solo_casco(activo)


## El casco recortado en una caja centrada en la nave, en luminancia. NAN dentro
## si el pixel cae fuera de la pantalla.
func _casco_luz() -> PackedFloat32Array:
	var img := get_viewport().get_texture().get_image()
	# `get_global_transform_with_canvas()` da coordenadas de LIENZO y la imagen
	# viene en pixeles FISICOS. Con `window/stretch/mode = canvas_items` no son lo
	# mismo: el lienzo mide 1370x720 y la ventana 1920x1009, un factor de 1,4. La
	# caja caia entera fuera de la nave, sobre campo de estrellas quieto — y dos
	# fotos de un fondo quieto salen identicas, que es exactamente lo que mide
	# "la luz no se movio". Un falso OK perfecto.
	var lienzo := get_viewport_rect().size
	var k := Vector2(float(img.get_width()) / lienzo.x, float(img.get_height()) / lienzo.y)
	var centro := _hero.get_global_transform_with_canvas().origin * k
	var out := PackedFloat32Array()
	out.resize(CAJA * CAJA)
	for y in CAJA:
		for x in CAJA:
			var px := Vector2i(int(centro.x) + x - CAJA / 2, int(centro.y) + y - CAJA / 2)
			var v := NAN
			if px.x >= 0 and px.y >= 0 and px.x < img.get_width() and px.y < img.get_height():
				v = img.get_pixelv(px).get_luminance()
			out[y * CAJA + x] = v
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
func _residuo_al_desgirar(a: PackedFloat32Array, b: PackedFloat32Array, grados: float) -> float:
	var c := cos(deg_to_rad(grados))
	var sn := sin(deg_to_rad(grados))
	var mitad := float(CAJA) / 2.0
	var dif_rot := 0.0
	var dif_bruta := 0.0
	var n := 0
	for y in CAJA:
		for x in CAJA:
			var va: float = a[y * CAJA + x]
			if is_nan(va):
				continue
			# el punto de A aparece GIRADO en B: se busca alli
			var p := Vector2(float(x) - mitad, float(y) - mitad)
			var q := Vector2(p.x * c - p.y * sn, p.x * sn + p.y * c) + Vector2(mitad, mitad)
			var qi := Vector2i(int(round(q.x)), int(round(q.y)))
			if qi.x < 0 or qi.y < 0 or qi.x >= CAJA or qi.y >= CAJA:
				continue
			var vb: float = b[qi.y * CAJA + qi.x]
			var vb_bruto: float = b[y * CAJA + x]
			if is_nan(vb) or is_nan(vb_bruto):
				continue
			dif_rot += absf(va - vb)
			dif_bruta += absf(va - vb_bruto)
			n += 1
	if n < 400 or dif_bruta <= 0.0001:
		return NAN
	return dif_rot / dif_bruta


## Especies de caza del autotest: las dos comunes y flojas. Ampliarlo de solo
## `vex` a `vex` + `vexor` sube la densidad de presa de 15 a 23 en el 1-1, y ya
## no hay motivo para exigir una especie concreta — desde que la venta pregunta
## al almacen que hay, al bot le sirve cualquier caja.
const AT_PRESAS := ["vex", "vexor"]

## Lado de la caja con la que se retrata el casco para la prueba del relieve.
const CAJA := 128

## Margen del encuadre de la estacion y ELEVACION de su camara, en grados: 90 es
## cenital y por debajo empieza el escorzo.
##
## La estacion es el unico asset que NO se mira desde arriba, y es una decision
## de direccion de arte, no un descuido: es una torre, y una torre vista en
## cenital es un punto. El resto del juego sigue siendo cenital.
##
## Al bajarla hay que encuadrar con `extension_vista` y no con la huella: la
## altura pasa a ocupar pantalla y con la huella la torre se sale por arriba.
const EST_MARGEN := 1.15
const EST_ELEVACION := 30.0

## Por debajo de esto un bicho se considera QUIETO entre sus dos retratos. Es un
## suelo de ruido, no un objetivo: dos capturas del mismo fotograma dan 0 exacto.
const MOV_MINIMO := 0.004

## Fotogramas de asiento antes de la primera foto del relieve.
const ASENTAR := 3
## Cuanto se gira la nave (y cuanto se le miente la luz) durante la prueba.
const GIRO_RELIEVE := 90.0
## Cuanto tienen que moverse los pixeles al mentirle la luz al shader. El umbral
## puede ser ridiculamente bajo porque el caso roto es CERO EXACTO: misma nave,
## mismo sitio, mismo rumbo, solo cambia un uniform que se estaria ignorando.
const MIN_EFECTO := 0.02


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
const AT_PATRULLA: Array[Vector2] = [
	Vector2(4000, 3000), Vector2(16000, 3000), Vector2(16000, 9500),
	Vector2(4000, 9500), Vector2(10400, 6400),
]

var _at_patrulla_i := -1


func _at_patrullar() -> void:
	if _at_patrulla_i >= 0 and _hero.position.distance_to(_at_destino_patrulla()) > 400.0:
		return                            # sigue en camino al waypoint actual
	_at_patrulla_i = (_at_patrulla_i + 1) % AT_PATRULLA.size()
	_volar_a(_at_destino_patrulla())


func _at_destino_patrulla() -> Vector2:
	return AT_PATRULLA[_at_patrulla_i].clamp(Vector2.ZERO, _limites)


func _mejor_presa() -> EntityNode:
	var elegida: EntityNode = null
	var mejor := INF
	for id in _entidades:
		var e: EntityNode = _entidades[id]
		if not AT_PRESAS.has(e.type_id):
			continue
		var hacia := e.position - _hero.position
		var d := hacia.length()
		if d <= 450.0:
			return e                      # ya esta a tiro: no hay nada mejor
		var dir := hacia / d
		var v := Vector2.ZERO
		if e.speed > 0.0 and e.objetivo.distance_to(e.position) > 1.0:
			v = (e.objetivo - e.position).normalized() * e.speed
		var cierre := _hero.speed - v.dot(dir)
		if cierre <= 1.0:
			continue                      # huye tan rapido como volamos: inalcanzable
		var t := (d - 450.0) / cierre
		if t < mejor:
			mejor = t
			elegida = e
	# si todas huyen, quedarse con la mas cercana: peor plan que ninguno, y con
	# quince vagabundos alguna cambiara de rumbo en breve
	if elegida == null:
		for id in _entidades:
			var e2: EntityNode = _entidades[id]
			if not AT_PRESAS.has(e2.type_id):
				continue
			var d2 := _hero.position.distance_to(e2.position)
			if d2 < mejor:
				mejor = d2
				elegida = e2
	return elegida


## El salto de sector, de punta a punta: volar al portal, cruzarlo, y comprobar
## que se llego a OTRO mapa con la nave entera.
func _autotest_salto() -> void:
	if _autotest_t > 150.0:
		_at_captura("SALTO TIMEOUT en la fase %d (mapa %s)" % [_at_fase, _map_code], 1)
		return
	match _at_fase:
		0:
			if _portales.is_empty() or _hero == null:
				return
			_at_salto_origen = _map_code
			_at_salto_portal = _portales.values()[0]
			_at_salto_destino = _at_salto_portal.target_map_code
			# como el jugador: clic en el portal deja AUTOPILOTO puesto, y era eso
			# —no el vuelo— lo que sobrevivia al salto y tiraba de la nave al llegar
			_on_autopilot(_at_salto_portal.position)
			_at_ultimo_vuelo = _autotest_t
			_at_fase = 1
		1:
			# reencaminar cada 2 s: el clamp del server y la deriva hacen que un
			# solo `volar_a` se quede corto en un viaje tan largo
			if _autotest_t - _at_ultimo_vuelo > 2.0:
				_at_ultimo_vuelo = _autotest_t
				_volar_a(_at_salto_portal.position)
			if _hero.position.distance_to(_at_salto_portal.position) < 400.0:
				var img := get_viewport().get_texture().get_image()
				img.save_png(Session.autotest_screenshot.replace(".png", "-salto-antes.png"))
				# Se salta EN MARCHA, con un destino lejos y sin alcanzar. Es el
				# caso real —se huye, se pulsa J sin soltar el raton— y es el
				# unico que reproduce el fallo: volando justo hasta el portal, el
				# autopiloto se completa y se limpia solo antes de saltar, asi
				# que la prueba pasaba aunque el arreglo no estuviera.
				_on_autopilot(Vector2(_limites.x - 2000, _limites.y - 2000))
				# y con el boton SOSTENIDO apuntando lejos, que es como se salta
				# huyendo: eso es lo que seguia mandando destinos del mapa viejo
				# por el socket del mapa nuevo
				_at_cursor = Vector2(_limites.x - 1500, _limites.y - 1500)
				_hold_move = true
				_hold_timer = 0.0
				# por el camino DEL JUGADOR, no mandando el mensaje a mano: asi la
				# prueba cubre el encendido, la espera y la medida del viaje
				_intentar_salto()
				_at_ultimo_vuelo = _autotest_t
				_at_fase = 2
		2:
			if _map_code == _at_salto_destino and _hero != null:
				_at_salto_llegada = _hero.position
				# EN EL INSTANTE de llegar: un fotograma despues el lerp ya habria
				# alcanzado y la comprobacion no probaria nada
				_at_salto_camara = _foco.distance_to(_hero.position)
				_at_cursor = Vector2.INF     # se suelta el boton al llegar
				_hold_move = false
				_at_ultimo_vuelo = _autotest_t
				_at_fase = 3
			elif _autotest_t - _at_ultimo_vuelo > 15.0:
				_at_captura("SALTO FALLO — se pidio el salto y el mapa sigue siendo %s" % _map_code, 1)
		3:
			if _autotest_t - _at_ultimo_vuelo < 1.5:
				return
			var img2 := get_viewport().get_texture().get_image()
			img2.save_png(Session.autotest_screenshot.replace(".png", "-salto-despues.png"))
			# llegar a otro mapa no basta: hay que llegar ENTERO y en su sitio
			if _hero == null:
				_at_captura("SALTO FALLO — se llego a %s sin nave" % _map_code, 1)
				return
			if _portales.is_empty():
				_at_captura("SALTO FALLO — %s llego sin portales: no habria vuelta" % _map_code, 1)
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
			if _at_salto_camara > 150.0:
				_at_captura("SALTO FALLO — al llegar, la camara estaba a %d unidades de la nave"
					% _at_salto_camara, 1)
				return
			var lejos := _hero.position.distance_to(_at_salto_llegada)
			if lejos > 200.0:
				_at_captura("SALTO FALLO — aterrizo en (%d, %d) y se fue a (%d, %d): %d unidades"
					% [_at_salto_llegada.x, _at_salto_llegada.y,
					   _hero.position.x, _hero.position.y, lejos], 1)
				return
			var vuelta := false
			for id in _portales:
				if _portales[id].target_map_code == _at_salto_origen:
					vuelta = true
			if not vuelta:
				_at_captura("SALTO FALLO — %s no tiene portal de vuelta a %s"
					% [_map_code, _at_salto_origen], 1)
				return
			_at_captura("SALTO OK — %s -> %s, nave en (%d, %d), %d portales y vuelta a casa"
				% [_at_salto_origen, _map_code, _hero.position.x, _hero.position.y,
				   _portales.size()], 0)


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
			# RELIEVE: que la luz NO gire con la nave. Vive en el bestiario y no
			# en el loop porque es una prueba de ARTE, y el bestiario existe
			# justo para eso — pagar tres minutos de loop para mirar un shader
			# es el peaje que nadie acaba pagando, y una prueba que no se corre
			# no es una prueba.
			var relieve := _relieve_paso()
			if relieve == 0:
				return          # aun midiendo
			if relieve == 2:
				return          # fallo, ya reportado
			_at_camara_libre = false
			# QUIETOS: los que no se movieron entre sus dos retratos. Se reporta la
			# lista, no se falla: hay bichos que legitimamente no animan, y el
			# umbral bueno todavia no esta medido en las nueve especies. Lo que no
			# puede seguir pasando es que nadie se entere.
			var quietos: Array[String] = []
			var detalle: Array[String] = []
			for esp in _at_mov_bicho:
				var m: float = _at_mov_bicho[esp]
				detalle.append("%s %.3f" % [esp, m])
				if m < MOV_MINIMO:
					quietos.append(str(esp))
			print("MOVIMIENTO por especie: %s" % ", ".join(detalle))
			_at_captura("BESTIARIO OK — %d retratos%s · relieve (efecto %.3f) · quietos: %s"
				% [AT_BESTIARIO.size(),
				" + cambio de calidad en caliente" if _at_cambio_calidad else "",
				_at_relieve_resto,
				"ninguno" if quietos.is_empty() else ", ".join(quietos)], 0)
		else:
			_at_fase = 11
		return
	var especie: String = AT_BESTIARIO[_at_bicho]
	var bicho := _primero_de_especie(especie)
	if bicho == null:
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
		if _at_maniqui == null or _at_maniqui.type_id != especie:
			_soltar_maniqui()
			_at_maniqui = _maniqui_de_especie(especie)
		bicho = _at_maniqui
	_foco = bicho.position
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
		# Y AQUI SE AFIRMA que se movio. Las dos fotos ya se tomaban —el
		# comentario de arriba lo dice— pero solo se guardaban: comparar quedaba
		# para el ojo de quien las mirase, y nadie las mira una por una.
		#
		# Es la averia que se colo con el Vorax: sus ocho brazos no se movian
		# porque el cliente mapeaba una lista FIJA de nombres de hueso y los
		# `brazo_*` no estaban. En la foto se veia un bicho perfecto, con sus
		# brazos en pose de reposo, y la pose de reposo de un bicho radial no se
		# distingue de una pose animada mirando UN fotograma.
		var mov := _movimiento_retrato()
		if not is_nan(mov):
			_at_mov_bicho[especie] = mov
	_soltar_maniqui()
	_at_camara_t = -1.0
	_at_primer_frame = false
	_at_bicho += 1


func _retrato(especie: String, sufijo: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if Session.calidad_forzada != "":
		sufijo = "-" + Session.calidad_forzada + sufijo
	img.save_png(Session.autotest_screenshot.replace(".png", "-%s%s.png" % [especie, sufijo]))


## Suelta el ejemplar fabricado, si lo hubo. No vive en `_entidades`: no es del
## mundo, es del retrato.
func _soltar_maniqui() -> void:
	if _at_maniqui != null:
		_at_maniqui.queue_free()
		_at_maniqui = null


## Un ejemplar de laboratorio para el retrato, cuando la especie no anda cerca.
## Se arma con un `EntitySpawn` de verdad para que pase por el MISMO `setup` que
## cualquier bicho del mundo: si el retrato saliera de un camino distinto, no
## probaria lo que se cree que prueba.
func _maniqui_de_especie(code: String) -> EntityNode:
	var sp := MexProtocol.EntitySpawn.new()
	sp.entity_id = 0
	sp.kind = MexProtocol.EntityKind.NPC
	sp.type_id = code
	sp.name = code.capitalize()
	sp.faction = 0
	# lejos del heroe y de la estacion, para que nada se cuele en el encuadre
	sp.x = int(_limites.x * 0.5)
	sp.y = int(_limites.y * 0.25)
	sp.hp_pct = 1.0
	sp.shield_pct = 1.0
	sp.speed = 0
	var nodo := EntityNode.new()
	nodo.setup(sp, false)
	add_child(nodo)
	return nodo


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
