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
var _laser_on := false
var _beam: Line2D
var _cajas := {}                  # box_id -> Sprite2D
var _pending_box := 0             # flujo del prototipo: volar a la caja y recoger al llegar
var _pending_box_pos := Vector2.ZERO
var _req_id := 0
var _tex_caja: Texture2D = preload("res://assets/world/cargo-box.svg")
var _frames_explosion: SpriteFrames

# HUD (sistema N minimo de la iteracion: panel de nave + estado del enlace)
var _hud_estado: Label
var _hud_hp: Label
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
	_conn.error_reply.connect(_on_error)
	_conn.session_replaced.connect(func(): _estado("Sesión reemplazada por otra conexión", NTheme.WARN))
	_conn.disconnected.connect(func(): _estado("Enlace perdido", NTheme.HOSTILE))

	# el haz del laser: se dibuja entre el heroe y su objetivo mientras dispara
	_beam = Line2D.new()
	_beam.width = 3.0
	_beam.default_color = NTheme.CYAN
	_beam.visible = false
	_beam.z_index = 5
	add_child(_beam)

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
	_hud_hp = NTheme.label("--", NTheme.mono(), 12, NTheme.WARN)
	col.add_child(_hud_hp)
	_hud_credits = NTheme.label("--", NTheme.mono(), 12, NTheme.WARN)
	col.add_child(_hud_credits)
	_hud_cargo = NTheme.label("--", NTheme.mono(), 12, NTheme.WARN)
	col.add_child(_hud_cargo)
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
	_construir_fondo(em.map_code)
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
	_hud_cargo.text = "Bodega %s / %s" % [_miles(hs.cargo), _miles(hs.max_cargo)]


func _on_target_info(ti) -> void:
	var nodo: EntityNode = _entidades.get(ti.entity_id)
	if nodo == null:
		return
	nodo.max_hp_abs = ti.max_hp + ti.max_shield
	nodo.set_hp_abs(ti.hp + ti.shield)


func _on_attack(ev) -> void:
	var blanco: EntityNode = _entidades.get(ev.target_id)
	if blanco == null:
		return
	blanco.set_hp_abs(ev.target_hp + ev.target_shield)
	# numero de daño flotante que sube y se desvanece
	var texto := NTheme.label(str(ev.damage), NTheme.mono(), 14, NTheme.WARN)
	texto.position = blanco.position + Vector2(randf_range(-30, 30), -70)
	texto.z_index = 6
	add_child(texto)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(texto, "position:y", texto.position.y - 46, 0.8)
	tw.tween_property(texto, "modulate:a", 0.0, 0.8)
	tw.chain().tween_callback(texto.queue_free)


func _on_destroyed(msg) -> void:
	var nodo: EntityNode = _entidades.get(msg.entity_id)
	if nodo != null:
		_explotar(nodo.position)
		nodo.queue_free()
		_entidades.erase(msg.entity_id)
	if _seleccionada == msg.entity_id:
		_seleccionada = 0
		_laser_on = false
		_beam.visible = false


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
	var caja := Sprite2D.new()
	caja.texture = _tex_caja
	caja.position = Vector2(msg.x, msg.y)
	caja.scale = Vector2.ONE * 0.75
	caja.z_index = 1
	add_child(caja)
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
	if _seleccionada == 0 or not _entidades.has(_seleccionada):
		return
	_laser_on = not _laser_on
	var msg := MexProtocol.LaserToggle.new()
	msg.active = _laser_on
	_conn.send(msg.encode())


func _handle_click(world_pos: Vector2) -> void:
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
	# click en vacio: volar; mientras siga presionado, _process persigue al cursor
	_pending_box = 0
	_volar_a(world_pos)
	_hold_move = true
	_hold_timer = 0.0


func _box_at(world_pos: Vector2) -> int:
	var min_radius := CLICK_RADIUS / _camara.zoom.x
	for id in _cajas:
		if _cajas[id].position.distance_to(world_pos) < min_radius:
			return id
	return 0


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
	_process_pending_collect()
	if _fondo != null:
		_fondo.update_parallax(_camara.position, _camara.zoom, get_viewport_rect().size)
	if _hero != null:
		_camara.position = _camara.position.lerp(_hero.position, 8.0 * delta)
		_hud_pos.text = "(%d, %d)" % [_hero.position.x, _hero.position.y]

	# el haz del laser sigue a los contendientes
	if _laser_on and _hero != null and _entidades.has(_seleccionada):
		_beam.visible = true
		_beam.points = PackedVector2Array([_hero.position, _entidades[_seleccionada].position])
	else:
		_beam.visible = false

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


func _autotest(delta: float) -> void:
	_autotest_t += delta
	if _autotest_t > 60.0:
		_at_captura("AUTOTEST TIMEOUT en fase %d" % _at_fase, 1)
		return
	match _at_fase:
		0:
			if _autotest_t > 1.5 and _hero != null:
				var cercano: EntityNode = null
				var mejor := INF
				for id in _entidades:
					var e: EntityNode = _entidades[id]
					if e.es_npc and _hero.position.distance_to(e.position) < mejor:
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
			# perseguir al objetivo si se aleja del rango del laser
			var objetivo_npc: EntityNode = _entidades.get(_at_target)
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
			if _at_recogido:
				_at_captura("AUTOTEST OK — Vex destruido, caja recogida; bodega y credits en HUD", 0)


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
