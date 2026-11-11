extends Node

## Banco del RELIEVE (prueba de concepto, 10-nov-2026): el 1-1 con su fondo, el
## canion de data/relief/1-1.json y una Phoenix que vuela. SIN servidor y sin
## login: es para mirar el terreno, no para jugar. La nave atraviesa las rocas —
## la colision es trabajo del servidor.
##
##   godot --path . res://tests/view_relief.tscn
##   godot --path . res://tests/view_relief.tscn -- --at=5300,2750 --cam=chase --shot=C:/Tools/relief.png
##
## Tres preguntas, tres teclas:
##   F = a que altura vuela: FIJA (el plano de siempre) / SIGUE EL TERRENO. La nave
##       sigue dando solo (x, y); la altura la pone el lugar, como en WoW el suelo.
##       Pendiente suave = rampa, se sube. Empinada = pared, no se pasa (bajar si).
##   T = como se arma el terreno: rocas sueltas / trinchera continua
##   V = desde donde se mira: CENITAL (la camara del juego, Stage3D) / PERSECUCION
##       (detras de la nave, mirando al horizonte). El movimiento es el mismo en
##       las dos: la nave nunca deja su plano. Lo unico que cambia es la camara.
##
## Volar como en DarkOrbit, en las dos camaras: click o mantener = ir ahi, cerca o
## lejos de la nave y en cualquier direccion (tambien hacia atras). La camara de
## persecucion NO gira sola al volar con clicks; se gira con el boton derecho.
## Tambien se puede pilotar: W avanzar · S frenar · A/D girar · Q/E de lado.
## Al atacar la camara sigue al objetivo (G lo quita): con el cursor mantenido a un
## lado de el, la nave lo rodea — el giro clasico alrededor de un bicho.
## Combate: MAYUS = esquivar (hacia el cursor) · 1 Rafaga · 2 Impacto (interrumpe) ·
## 3 Pulso · 4 Reparar. Los bichos anuncian sus golpes en el suelo: tests/relief_skills.gd
## F1/F2 velocidad · F3/F4 campo de vision · rueda distancia · X = valores de fabrica
## --dodge: en --fight, la nave sale sola de las zonas anunciadas
## --hold=fx,fy simula el cursor mantenido en esa fraccion de la pantalla
## C = recorte si/no · R = relieve si/no
## Mapa: por defecto el mini mundo abierto (data/relief/demo.json), con zonas que
## se descubren, minimapa con niebla y bichos por zona; --map=1-1 vuelve al canion
## suelto de las primeras pruebas.
## Argumentos: --at=x,y · --zoom= · --heading=grados · --cam=chase · --pitch=grados ·
## --variant=rocks|trench · --shot=ruta (captura y sale) · --seconds= · --cut=0 ·
## --relief=0 (la linea base) · --follow=0 (altura fija) · --dest=x,y (vuela ahi solo) ·
## --fight (selecciona y ataca sola al mas cercano; --fight=N al bicho N) · --novsync
## Combate (tests/relief_combat.gd): click en un bicho = seleccionar, otra vez = atacar ·
## TAB = siguiente objetivo · ESPACIO = atacar / dejar de atacar

const BACKDROP_MAP := "1-1"        # el cielo, el planeta y el polvo son los del 1-1
var BOUNDS := Vector2(20800, 12800)    # el mapa entero; el trazado puede declararlo (`bounds`)
const SHIP_MODEL := "res://assets/ships/phoenix.glb"
const SHIP_SIZE := 141.0
const SPEED := 320.0               # la de la Phoenix en el catalogo (dial en vivo: 1/2)
const TURN_DEG := 90.0             # giro con A/D, grados por segundo
const ACCEL := 1000.0              # u/s2: llega a la velocidad en ~0,3 s
const DECEL := 1400.0
const STEER_PER_PX := 0.004        # boton derecho: radianes de camara por pixel de raton

## El cuerpo de la nave, con los MISMOS diales que el cliente real
## (data/config/entity.json, game/entity_node.gd): el rumbo visual alcanza al
## comandado con ease de `turn.time`, y la nave se alabea con el error de rumbo.
static var _ENT: Dictionary = AssetDefs.config("entity")
static var TURN_TIME: float = AssetDefs.num(_ENT.get("turn", {}), "time", 0.2)
static var BANK_MAX: float = AssetDefs.num(_ENT.get("bank", {}), "max", 20.0)
static var BANK_EASE: float = AssetDefs.num(_ENT.get("bank", {}), "ease", 0.2)
const ARRIVE := 6.0
const WARMUP := 2.0

## La camara de persecucion. Son valores de primera pasada para poder JUZGAR la
## vista, no una calibracion: si esto sigue, se van a data/config/camera.json.
##
## La proporcion que manda es VELOCIDAD / DISTANCIA DE CAMARA: en WoW se corre a
## 7 yardas/s con la camara a unas 15 (0,47 distancias de camara por segundo). La
## primera pasada tenia 320 u/s con la camara a 430 (0,74) y FOV 60: la misma nave
## se sentia un 60 % mas rapida que un personaje de WoW. A 700 queda en 0,46.
const CHASE_FOV := 50.0            # dial en vivo: 3/4
const CHASE_DIST := 700.0          # dial en vivo: rueda
const CHASE_DIST_MIN := 220.0
const CHASE_DIST_MAX := 1800.0
const CHASE_PITCH_DEG := 26.0      # elevacion de la camara sobre la nave
const CHASE_LOOK_AHEAD := 60.0     # casi a la nave: tiene que quedar suelo clicable DETRAS de ella
const ORDER_MAX := 2600.0          # lo mas lejos que llega una orden de un click
const CHASE_LOOK_UP := 40.0
const CHASE_FOLLOW := 1.8          # rapidez con que la camara alcanza el rumbo
const COMBAT_FOLLOW := 2.6         # ... y con que gira hacia el objetivo al atacar
const COMBAT_PULL := 0.5           # se aleja esta fraccion de la distancia al objetivo
const COMBAT_PULL_MAX := 520.0
const COMBAT_LOOK := 0.4           # mira a este punto del tramo nave -> objetivo
const COMBAT_TILT_DEG := 12.0      # ... y sube estos grados, para que la nave no lo tape
const LOOK_EASE := 6.0
const CAM_CLEARANCE := 70.0        # la camara no baja de esto sobre el terreno
const CHASE_PROFILE := "chase"     # perfil de terreno de data/relief/<mapa>.json

## Seguir el terreno. Primera pasada, como la camara.
const CLEARANCE := 80.0            # holgura sobre la superficie
const MAX_SLOPE := 1.2             # pendiente maxima que se SUBE (1.0 = 45 grados; las paredes pasan de 2,5)
const ALT_RATE := 5.0              # rapidez con que la altura alcanza su objetivo
const PITCH_PROBE := 40.0          # base para medir la pendiente bajo la nave

static var ALT: float = AssetDefs.num(AssetDefs.config("entity").get("altitude", {}), "hero", 80.0)

var _stage: Stage3D
var _backdrop: Backdrop3D
var _relief: Relief3D
var _ship: Node3D
var _pos := Vector2(3700, 2330)
var _dest := Vector2(3700, 2330)
var _heading := Vector2.RIGHT
var _cut := true
var _label: Label
var _shot := ""
var _seconds := 1.5
var _t := 0.0
var _no_relief := false
var _variant := ""                 # vacio = la que diga data/relief/<mapa>.json
var _frames := 0                   # fotogramas contados tras el calentamiento
var _measured := 0.0

var _follow := true
var _alt := 80.0
var _nose := 0.0                   # cabeceo visual de la nave (radianes)
var _blocked := false
var _combat: Node                  # tests/relief_combat.gd
var _mouse_eaten := false          # el click cayo en un bicho: no es una orden de volar
var _start := Vector2(3700, 2330)
var _fight := false
var _fight_index := -1
var _arg_dest := Vector2.INF       # --dest=x,y: vuela ahi solo (para verificar sin manos)
var _chase := false
var _cam_yaw := 0.0
var _pitch := deg_to_rad(CHASE_PITCH_DEG)
var _chase_dist := CHASE_DIST
var _orbit_last := Vector2.INF
var _orbit_deg := 0.0
var _orbit_min := INF
var _orbit_max := 0.0
var _map := "demo"                 # --map=: que trazado de data/relief/ se monta
var _has_profiles := false
var _zones: Array = []
var _safe_zones: Array = []
var _zone := ""                    # la zona en la que esta la nave
var _discovered := {}              # nombre -> true
var _banner: Label
var _banner_left := 0.0
var _minimap: Control              # tests/relief_minimap.gd
var _auto_dodge := false           # --dodge: la verificacion esquiva sola
var _shake := 0.0                  # sacudida de camara, en unidades
var _track := true                 # G: al atacar, la camara sigue al objetivo
var _hold := Vector2.INF           # --hold=fx,fy: cursor mantenido en esa fraccion de pantalla
var _cam_tilt := 0.0
var _cam_lift := 0.0               # lo que sube para no meterse en el terreno
var _cam_extra := 0.0              # lo que la camara se aleja en combate
var _cam_look := Vector3.INF       # a donde mira, suavizado
var _fov := CHASE_FOV
var _speed := SPEED
var _vel := 0.0                    # velocidad actual (acelera y frena)
var _move_dir := Vector2.RIGHT     # hacia donde se desplaza (puede no ser el rumbo: Q/E)
var _face := 0.0                   # rumbo VISUAL de la nave, radianes en el plano
var _roll := 0.0                   # alabeo, grados
var _piloting := false


func _ready() -> void:
	Quality.levels = Quality.PRESETS["alta"].duplicate()
	Quality.preset = "alta"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			_map = arg.trim_prefix("--map=")
	var layout := Relief3D.layout(_map)
	_zones = layout.get("zones", [])
	_safe_zones = layout.get("safe_zones", [])
	_has_profiles = layout.has("terrain_profiles")
	var declared: Array = layout.get("bounds", [])
	if declared.size() == 2:
		BOUNDS = Vector2(float(declared[0]), float(declared[1]))
	var start: Array = layout.get("start", [])
	if start.size() == 2:
		_pos = Vector2(float(start[0]), float(start[1]))
	_heading = Vector2.RIGHT.rotated(deg_to_rad(float(layout.get("start_heading", 0.0))))
	var zoom := 1.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--at="):
			var parts := arg.trim_prefix("--at=").split(",")
			if parts.size() == 2:
				_pos = Vector2(float(parts[0]), float(parts[1]))
		elif arg.begins_with("--zoom="):
			zoom = float(arg.trim_prefix("--zoom="))
		elif arg.begins_with("--heading="):
			_heading = Vector2.RIGHT.rotated(deg_to_rad(float(arg.trim_prefix("--heading="))))
		elif arg.begins_with("--shot="):
			_shot = arg.trim_prefix("--shot=")
		elif arg.begins_with("--seconds="):
			_seconds = float(arg.trim_prefix("--seconds="))
		elif arg == "--cut=0":
			_cut = false
		elif arg == "--cam=chase":
			_chase = true
		elif arg.begins_with("--pitch="):
			_pitch = deg_to_rad(float(arg.trim_prefix("--pitch=")))
		elif arg.begins_with("--variant="):
			_variant = arg.trim_prefix("--variant=")
		elif arg == "--relief=0":
			_no_relief = true
		elif arg == "--follow=0":
			_follow = false
		elif arg == "--dodge":
			_auto_dodge = true
		elif arg == "--fight":
			_fight = true
		elif arg.begins_with("--fight="):
			_fight = true
			_fight_index = int(arg.trim_prefix("--fight="))
		elif arg.begins_with("--hold="):
			var hp := arg.trim_prefix("--hold=").split(",")
			if hp.size() == 2:
				_hold = Vector2(float(hp[0]), float(hp[1]))
		elif arg == "--track=0":
			_track = false
		elif arg.begins_with("--dest="):
			var dp := arg.trim_prefix("--dest=").split(",")
			if dp.size() == 2:
				_arg_dest = Vector2(float(dp[0]), float(dp[1]))
		elif arg == "--novsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0
	_dest = _arg_dest if _arg_dest != Vector2.INF else _pos
	_face = _heading.angle()
	_move_dir = _heading
	_cam_yaw = atan2(_heading.x, _heading.y)

	_stage = Stage3D.new()
	add_child(_stage)
	_stage.zoom_direct(zoom)
	var config := MapBgConfig.for_whom(BACKDROP_MAP, BOUNDS)
	_stage.pan_deg = float(config.get("pan", 0.0))
	if _map != "1-1":
		# El universo no hereda los fondos ni los objetos del mapa 2D original
		# (telon, nebulosas en mosaico, el planeta y su techo, lunas y estaciones
		# mineras): ahora los planetas son los del trazado. Quedan el cielo de
		# estrellas, el polvo que vende el vuelo y el sol.
		config.erase("main")
		config["tiles_far"] = []
		config["tiles_near"] = []
		config["planets"] = []
		config["props"] = (config.get("props", []) as Array).filter(
			func(pr): return (pr as Dictionary).has("lensflare"))
	_backdrop = Backdrop3D.new()
	_stage.add_child(_backdrop)
	_backdrop.build(config, BOUNDS, BACKDROP_MAP.hash())
	_mount_relief()

	_ship = Node3D.new()
	_stage.add_child(_ship)
	var model: Node3D = (load(SHIP_MODEL) as PackedScene).instantiate()
	model.scale = Vector3.ONE * (SHIP_SIZE / AssetDefs.extent_3d(model))
	_ship.add_child(model)

	_alt = _target_alt(_pos)
	if start.size() == 2:
		_start = Vector2(float(start[0]), float(start[1]))
	_combat = (load("res://tests/relief_combat.gd") as GDScript).new()
	_combat.bench = self
	add_child(_combat)
	_combat.setup(layout.get("npcs", []))
	_combat.auto = _fight
	_combat.auto_index = _fight_index
	_combat.skills.auto_dodge = _auto_dodge

	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(12, 10)
	_label.add_theme_font_size_override("font_size", 13)
	layer.add_child(_label)
	_banner = Label.new()
	_banner.add_theme_font_size_override("font_size", 34)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0
	layer.add_child(_banner)
	_minimap = (load("res://tests/relief_minimap.gd") as GDScript).new()
	_minimap.bench = self
	_minimap.combat = _combat
	layer.add_child(_minimap)
	_minimap.setup(_relief, _zones)


## (Re)monta el relieve. La vista de persecucion pide OTRO terreno que la cenital:
## desde arriba la pared cercana va baja para no tapar el pasillo; desde atras eso
## es un bordillo, y las dos paredes tienen que subir por encima de la nave.
func _mount_relief() -> void:
	if _relief != null and not _has_profiles:
		return                     # un mundo sin perfiles por camara no se rehace
	var keep := _variant
	if _relief != null:
		keep = _relief.variant
		_relief.queue_free()
	_relief = Relief3D.new()
	_stage.add_child(_relief)
	_relief.build(_map, CHASE_PROFILE if _chase else "")
	_relief.visible = not _no_relief
	if keep != "":
		_relief.set_variant(keep)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hit: int = _combat.pick(event.position)
			if hit >= 0:
				_combat.select(hit)
				_mouse_eaten = true
		else:
			_mouse_eaten = false
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _chase:
				_chase_dist = maxf(_chase_dist / 1.12, CHASE_DIST_MIN)
			else:
				_stage.zoom_by_wheel(true)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _chase:
				_chase_dist = minf(_chase_dist * 1.12, CHASE_DIST_MAX)
			else:
				_stage.zoom_by_wheel(false)
	elif event is InputEventMouseMotion and _chase \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		# el boton derecho gira la CAMARA, no la nave: con el movimiento por clicks
		# la camara es tuya — no se mueve sola — y esta es la forma de recolocarla
		_cam_yaw -= event.relative.x * STEER_PER_PX
		_pitch = clampf(_pitch + event.relative.y * 0.004, deg_to_rad(4.0), deg_to_rad(75.0))
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_C:
				_cut = not _cut
			KEY_T:
				_relief.set_variant(Relief3D.VARIANT_ROCKS
					if _relief.variant == Relief3D.VARIANT_TRENCH else Relief3D.VARIANT_TRENCH)
			KEY_V:
				_chase = not _chase
				_cam_yaw = atan2(_heading.x, _heading.y)
				_cam_look = Vector3.INF
				_mount_relief()
			KEY_X:
				_pitch = deg_to_rad(CHASE_PITCH_DEG)
				_chase_dist = CHASE_DIST
				_fov = CHASE_FOV
				_speed = SPEED
			KEY_F1:
				_speed = maxf(_speed - 20.0, 80.0)
			KEY_F2:
				_speed = minf(_speed + 20.0, 800.0)
			KEY_F3:
				_fov = maxf(_fov - 3.0, 25.0)
			KEY_F4:
				_fov = minf(_fov + 3.0, 90.0)
			KEY_1:
				_combat.skills.use(0)
			KEY_2:
				_combat.skills.use(1)
			KEY_3:
				_combat.skills.use(2)
			KEY_4:
				_combat.skills.use(3)
			KEY_SHIFT:
				dash(_dash_wish())
			KEY_G:
				_track = not _track
			KEY_TAB:
				_combat.cycle()
			KEY_SPACE:
				_combat.toggle_attack()
			KEY_F:
				_follow = not _follow
			KEY_R:
				_relief.visible = not _relief.visible


## Una orden de vuelo desde un pixel de la pantalla, estilo DarkOrbit: el punto
## del plano bajo el cursor. Con la camara baja hay dos casos que la cenital no
## tiene: cerca del horizonte el punto cae lejisimos, y sobre el horizonte no cae
## en ninguna parte. En los dos la orden es "hacia alla": la DIRECCION del click,
## a ORDER_MAX de la nave.
func _order_to(px: Vector2) -> void:
	var hit := _stage.to_world(px, _alt)
	if not _chase:
		if hit != Vector2.INF:
			_dest = hit.clamp(Vector2.ZERO, BOUNDS)
		return
	var away := Vector2.ZERO
	if hit != Vector2.INF:
		away = hit - _pos
	else:
		var ray := _stage.cam_node.project_ray_normal(px)
		away = Vector2(ray.x, ray.z).normalized() * ORDER_MAX * 2.0
	if away.length() > ORDER_MAX:
		away = away.normalized() * ORDER_MAX
	_dest = (_pos + away).clamp(Vector2.ZERO, BOUNDS)


func _process(delta: float) -> void:
	_fly(delta)
	_alt = lerpf(_alt, _target_alt(_pos), 1.0 - exp(-ALT_RATE * delta))
	_orient(delta)
	_ship.position = Vector3(_pos.x, _alt, _pos.y)

	# la cenital es la del juego tal cual; la de persecucion pisa la camara despues
	_stage.cam_node.fov = _fov if _chase else Stage3D.FOV
	_stage.refresh(_pos, _alt)
	if _chase:
		_chase_camera(delta)
	_backdrop.update(_pos, delta)
	_relief.update(_ship.position, _cut)
	_combat.tick(delta)
	_track_zone(delta)
	# lo que quema: sobrevolar lava cuesta casco
	var hazard: Array = _relief.hazard_at(_pos)
	if float(hazard[0]) > 0.0:
		_combat.burn(float(hazard[0]) * delta, str(hazard[1]))
	# cuanto se ha rodeado al objetivo (para verificar el giro sin manos)
	if _combat.engaged():
		var around: Vector2 = _pos - _combat.target_pos()
		if _orbit_last != Vector2.INF:
			_orbit_deg += absf(rad_to_deg(_orbit_last.angle_to(around)))
		_orbit_last = around
		_orbit_min = minf(_orbit_min, around.length())
		_orbit_max = maxf(_orbit_max, around.length())
	else:
		_orbit_last = Vector2.INF
	_label.text = ("RELIEVE (prueba)  ·  %d fps  ·  (%d, %d)  altura %d%s  ·  zona: %s  ·  descubiertas %d/%d  ·  mapa visto %d%%\n"
		+ "V = camara [%s]  ·  F = altura [%s]  ·  T = terreno [%s]  ·  C = recorte %s  ·  R = relieve %s\n%s\n%s") % [
		Engine.get_frames_per_second(), _pos.x, _pos.y, _alt,
		"  ·  PARED: demasiado empinado" if _blocked else "",
		_zone_label(), _discovered.size(), _zones.size(), _minimap.explored() * 100.0,
		"PERSECUCION" if _chase else "CENITAL",
		"SIGUE EL TERRENO" if _follow else "FIJA", _relief.variant,
		"SI" if _cut else "NO", "SI" if _relief.visible else "NO",
			("click o mantener = volar ahi (cerca, lejos, atras) · boton derecho = girar la camara · G = camara sigue al objetivo [%s] · W/S/A/D/Q/E = pilotar\n"
				+ "velocidad %d (F1/F2)  ·  campo %d (F3/F4)  ·  distancia %d (rueda)  ·  elevacion %d  ·  X = valores de fabrica") % [
				"SI" if _track else "NO", _speed, _fov, _chase_dist, rad_to_deg(_pitch)]
				if _chase else "click = ir ahi · W/A/D/Q/E = volar · rueda = zoom  ·  velocidad %d (F1/F2)" % _speed,
		_combat.status()]

	_t += delta
	if _t >= WARMUP:
		_frames += 1
		_measured += delta
	if _shot != "" and _t >= _seconds:
		if _measured > 0.0:
			print("MEDIDA: %.1f fps de media en %.1f s (tras %.0f s de calentamiento)" % [
				_frames / _measured, _measured, WARMUP])
		print(_combat.report())
		print(_combat.skills.report())
		if _orbit_deg > 0.0:
			print("ORBITA: %d grados alrededor del objetivo, entre %d y %d u de el" % [
				_orbit_deg, _orbit_min, _orbit_max])
		print("ZONA: %s · descubiertas %d/%d" % [_zone_label(), _discovered.size(), _zones.size()])
		print("FINAL: pos (%d, %d) altura %d %s" % [_pos.x, _pos.y, _alt,
			"BLOQUEADA" if _blocked else "libre"])
		get_viewport().get_texture().get_image().save_png(_shot)
		get_tree().quit()


## El movimiento, igual en las dos camaras y siempre en el plano. Dos formas de
## mandar, como en WoW: ordenar un punto (click) o pilotar (W avanza, S frena, A/D
## giran, Q/E desplazan de lado, boton derecho gobierna con el raton). Pilotar
## cancela la orden. La velocidad no salta: acelera y frena.
func _fly(delta: float) -> void:
	var skills: Node = _combat.skills if _combat != null else null
	if skills != null and skills.dash_left > 0.0:
		# esquivando: solo el impulso, resbalando por las paredes
		_try_move(skills.dash_dir * skills.DASH_SPEED * delta, true)
		_move_dir = skills.dash_dir
		_vel = _speed
		_dest = _pos
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _mouse_eaten:
		_order_to(get_viewport().get_mouse_position())   # mantener = seguir el cursor
	elif _hold != Vector2.INF:
		_order_to(get_viewport().get_visible_rect().size * _hold)   # --hold: cursor fijo simulado
	var turn := 0.0
	if Input.is_key_pressed(KEY_A):
		turn -= 1.0
	if Input.is_key_pressed(KEY_D):
		turn += 1.0
	var side := 0.0
	if Input.is_key_pressed(KEY_Q):
		side -= 1.0
	if Input.is_key_pressed(KEY_E):
		side += 1.0
	var thrust := Input.is_key_pressed(KEY_W)
	var brake := Input.is_key_pressed(KEY_S)
	_piloting = turn != 0.0 or side != 0.0 or thrust or brake
	var want := Vector2.ZERO
	var top := _speed
	if _piloting:
		_heading = _heading.rotated(deg_to_rad(TURN_DEG) * turn * delta).normalized()
		want = _heading * (1.0 if thrust else 0.0) + _heading.orthogonal() * side
		_dest = _pos
	else:
		var to_dest := _dest - _pos
		if to_dest.length() > ARRIVE:
			want = to_dest
			_heading = to_dest.normalized()
			# frenar a tiempo: la velocidad desde la que aun se puede parar en lo que queda
			top = minf(_speed, sqrt(2.0 * DECEL * to_dest.length()))
	if want.length() > 0.001:
		_move_dir = want.normalized()
		_vel = move_toward(_vel, top, (ACCEL if _vel < top else DECEL) * delta)
	else:
		_vel = move_toward(_vel, 0.0, DECEL * delta)
	if _vel > 0.5:
		_try_move(_move_dir * _vel * delta, _piloting)
		if _blocked:
			_vel = 0.0


## El cuerpo: el rumbo visual persigue al comandado con el ease del cliente real,
## y el error de rumbo se vuelve alabeo. Atacando, la nave ENCARA al objetivo (asi
## lo hace el juego) aunque se desplace hacia otro lado.
func _orient(delta: float) -> void:
	var goal := _heading.angle()
	if _combat != null and _combat.engaged():
		var to_target: Vector2 = _combat.target_pos() - _pos
		if to_target.length() > 1.0:
			goal = to_target.angle()
	var error := angle_difference(_face, goal)
	_face += error * minf(1.0, (delta / TURN_TIME) * (2.0 - delta / TURN_TIME))
	var bank_k := minf(1.0, (delta / BANK_EASE) * (2.0 - delta / BANK_EASE))
	_roll += (clampf(rad_to_deg(error), -BANK_MAX, BANK_MAX) - _roll) * bank_k
	var facing := Vector2.from_angle(_face)
	# el morro acompania la pendiente: sin esto la nave sube una rampa en horizontal
	var slope := (_target_alt(_pos + facing * PITCH_PROBE)
		- _target_alt(_pos - facing * PITCH_PROBE)) / (2.0 * PITCH_PROBE)
	_nose = lerpf(_nose, atan(clampf(slope, -MAX_SLOPE, MAX_SLOPE)), 1.0 - exp(-3.0 * delta))
	_ship.basis = Basis(Vector3.UP, atan2(-facing.x, -facing.y)) \
		* Basis(Vector3.RIGHT, _nose) * Basis(Vector3.BACK, deg_to_rad(_roll))


## ¿Esta la nave en zona segura? (los bichos sueltan la presa)
func hero_safe() -> bool:
	for z: Dictionary in _safe_zones:
		if _pos.distance_to(Vector2(float(z.x), float(z.y))) <= float(z.r):
			return true
	return false


func _zone_label() -> String:
	if _zone != "":
		return _zone
	var planet := _relief.planet_at(_pos)
	return planet if planet != "" else "espacio abierto"


## En que zona esta la nave (la mas chica que la contiene) y, al entrar en una, el
## rotulo: el nombre grande que se desvanece, con "descubierta" la primera vez.
func _track_zone(delta: float) -> void:
	var best := ""
	var best_r := INF
	var note := ""
	for z: Dictionary in _zones:
		var r := float(z.r)
		if r < best_r and _pos.distance_to(Vector2(float(z.x), float(z.y))) <= r:
			best = str(z.name)
			best_r = r
			note = str(z.get("note", ""))
	if best != _zone:
		_zone = best
		if best != "":
			var first := not _discovered.has(best)
			_discovered[best] = true
			_banner.text = best + ("\nzona descubierta" if first else "") + ("\n" + note if note != "" else "")
			_banner_left = 4.0
	_banner_left = maxf(_banner_left - delta, 0.0)
	_banner.modulate.a = clampf(_banner_left / 1.2, 0.0, 1.0)
	var view := get_viewport().get_visible_rect().size
	_banner.position = Vector2((view.x - _banner.size.x) * 0.5, view.y * 0.2)


## La ESQUIVA: un impulso corto en una direccion del plano, que respeta el
## terreno (no atraviesa paredes). Mientras dura, la nave no obedece ordenes.
func dash(dir: Vector2) -> bool:
	if not _combat.skills.dash(dir):
		return false
	_dest = _pos
	return true


## Hacia donde esquiva la nave si el jugador pulsa Mayus: pilotando, hacia donde
## se mueve; con clicks, hacia el cursor (como en los juegos de accion cenital).
func _dash_wish() -> Vector2:
	if _piloting and _vel > 10.0:
		return _move_dir
	var hit := _stage.to_world(get_viewport().get_mouse_position(), _alt)
	if hit != Vector2.INF and hit.distance_to(_pos) > 20.0:
		return (hit - _pos).normalized()
	return _heading


## Sacudida de camara: la respuesta al golpe.
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## La nave cayo en combate: vuelve al inicio.
func respawn() -> void:
	_pos = _start
	_dest = _start
	_vel = 0.0
	_cam_look = Vector3.INF
	_alt = _target_alt(_pos)


## La altura a la que la nave QUIERE volar en un punto: la del terreno mas la
## holgura, y nunca por debajo del plano de siempre (fuera del macizo, o con la
## altura fija, es ese plano).
func _target_alt(p: Vector2) -> float:
	if not _follow:
		return ALT
	var h := _relief.height_at(p)
	return ALT if is_nan(h) else maxf(h + CLEARANCE, ALT)


## Un paso en el plano, si el terreno lo permite: subir mas empinado que
## MAX_SLOPE es una pared. Bajar siempre se puede (la nave se deja caer).
func _try_move(step: Vector2, slide := false) -> void:
	if _climb_ok(step):
		_pos = (_pos + step).clamp(Vector2.ZERO, BOUNDS)
		_blocked = false
		return
	if slide:
		# pilotando con W: resbalar a lo largo de la pared (la curva de nivel)
		var e := 8.0
		var grad := Vector2(_target_alt(_pos + Vector2(e, 0)) - _target_alt(_pos - Vector2(e, 0)),
			_target_alt(_pos + Vector2(0, e)) - _target_alt(_pos - Vector2(0, e)))
		if grad.length() > 0.001:
			var tangent := grad.normalized().orthogonal()
			var along := tangent * step.dot(tangent)
			if along.length() > 0.001 and _climb_ok(along):
				_pos = (_pos + along).clamp(Vector2.ZERO, BOUNDS)
	_blocked = true
	_dest = _pos


func _climb_ok(step: Vector2) -> bool:
	return _target_alt(_pos + step) - _target_alt(_pos) <= MAX_SLOPE * step.length()


## La camara de persecucion: detras y por encima de la nave, mirando por delante
## de ella. Sigue el rumbo con retraso y SOLO mientras la nave se mueve o se
## gobierna (el "smart" de WoW: parada, la camara se queda donde esta).
##
## AL ATACAR gira hacia el objetivo, se aleja lo bastante para que quepan los dos
## y mira a un punto entre la nave y el. Sin esto, un enemigo a la espalda queda
## entre la camara y la nave, enorme en primer plano, y uno a un lado ni se ve.
func _chase_camera(delta: float) -> void:
	var ship := _ship.position
	var engaged: bool = _combat.engaged()
	var extra_goal := 0.0
	var tracking := engaged and _track
	if tracking:
		var to_target: Vector2 = _combat.target_pos() - _pos
		if to_target.length() > 1.0:
			# EXACTAMENTE detras de la nave respecto al objetivo, sin ladearse: asi el
			# cursor a un lado de la nave es siempre "perpendicular al objetivo" y
			# mantenerlo ahi lo rodea igual por la izquierda que por la derecha
			_cam_yaw = lerp_angle(_cam_yaw, atan2(to_target.x, to_target.y),
				1.0 - exp(-COMBAT_FOLLOW * delta))
		extra_goal = minf(to_target.length() * COMBAT_PULL, COMBAT_PULL_MAX)
	elif _piloting:
		# solo PILOTANDO con el teclado la camara se alinea detras: W/A/D son
		# ordenes relativas al rumbo. Con clicks la camara se queda quieta — si
		# girara con la nave, un click "hacia atras" no existiria y mantenerlo
		# seria perseguirse la cola.
		_cam_yaw = lerp_angle(_cam_yaw, atan2(_heading.x, _heading.y),
			1.0 - exp(-CHASE_FOLLOW * delta))
	_cam_extra = lerpf(_cam_extra, extra_goal, 1.0 - exp(-2.5 * delta))
	# ... y para que la nave no tape al objetivo, la camara SUBE en vez de ladearse
	_cam_tilt = lerpf(_cam_tilt, deg_to_rad(COMBAT_TILT_DEG) if tracking else 0.0, 1.0 - exp(-2.5 * delta))
	var pitch := minf(_pitch + _cam_tilt, deg_to_rad(80.0))
	var fwd := Vector3(sin(_cam_yaw), 0.0, cos(_cam_yaw))
	var dist := _chase_dist + _cam_extra
	var cam_pos := ship - fwd * (dist * cos(pitch)) + Vector3.UP * (dist * sin(pitch))
	if _shake > 0.05:
		cam_pos += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
		_shake *= exp(-9.0 * delta)
	# que la camara no se meta en el terreno: si la superficie queda por encima,
	# sube (con suavidad, para que cruzar un borde no sea un salto)
	var ground := _relief.height_at(Vector2(cam_pos.x, cam_pos.z))
	var lift_goal := 0.0 if is_nan(ground) else maxf(ground + CAM_CLEARANCE - cam_pos.y, 0.0)
	_cam_lift = lerpf(_cam_lift, lift_goal, 1.0 - exp(-5.0 * delta))
	cam_pos.y += _cam_lift
	var look := ship + fwd * CHASE_LOOK_AHEAD + Vector3.UP * CHASE_LOOK_UP
	if tracking:
		look = ship.lerp(_combat.target_world(), COMBAT_LOOK) + Vector3.UP * CHASE_LOOK_UP
	_cam_look = look if _cam_look == Vector3.INF else _cam_look.lerp(look, 1.0 - exp(-LOOK_EASE * delta))
	_stage.cam_node.look_at_from_position(cam_pos, _cam_look, Vector3.UP)
