extends Node

## COMBATE "MODERNO" del banco (prueba de concepto, 10-nov-2026). La capa que
## convierte "seleccionar y esperar" en una pelea que se juega con las manos:
##
##   · los enemigos ANUNCIAN sus golpes fuertes: una zona en el suelo que se
##     llena durante el amago. Te sales o lo recibes.
##   · ESQUIVA (Mayus): un impulso corto, invulnerable mientras dura.
##   · cuatro HABILIDADES con enfriamiento (1-4) ademas del laser automatico; una
##     de ellas INTERRUMPE el amago del enemigo.
##   · cada familia de bichos tiene su mecanica (KITS).
##
## La seleccion de objetivo, el laser y el giro alrededor del bicho siguen siendo
## los de DarkOrbit: esto se monta encima, no lo sustituye.

# ---- lo que hace cada bicho ----
const KITS := {
	"vexor": ["charge"], "ferox": ["charge"], "vorax": ["charge"], "aci-03": ["charge"],
	"skarn": ["slam"], "aci-02": ["slam"],
	"mordax": ["pool"], "aci-01": ["pool"], "aci-04": ["pool"],
	"gravon": ["shield", "slam"],
	"skarnox": ["slam", "charge", "pool"],
	"aci-05": ["pool", "slam", "pool"],
}
const LABELS := {"slam": "GOLPE", "charge": "EMBISTE", "pool": "ESCUPE", "shield": "SE CUBRE"}
const SKILL_GAP := 4.5             # segundos entre habilidades de un bicho
const SKILL_GAP_ELITE := 3.0
const SKILL_RANGE := 700.0         # no amaga si estas mas lejos
const SLAM_WINDUP := 1.1
const SLAM_RADIUS := 250.0
const SLAM_RADIUS_ELITE := 340.0
const SLAM_MULT := 3.0             # danio = el del bicho x esto
const CHARGE_WINDUP := 0.9
const CHARGE_LENGTH := 850.0
const CHARGE_WIDTH := 170.0
const CHARGE_TIME := 0.45
const CHARGE_MULT := 3.5
const POOL_WINDUP := 0.7
const POOL_RADIUS := 180.0
const POOL_LIFE := 6.0
const POOL_MULT := 1.2             # danio por segundo = el del bicho x esto
const SHIELD_TIME := 3.0
const SHIELD_FACTOR := 0.15        # danio que entra con el escudo arriba
const STAGGER := 1.6               # segundos aturdido tras una interrupcion
const GROUND_DROP := 72.0          # de la altura de vuelo al suelo, para pintar las zonas

# ---- lo que hace la nave ----
const DASH_TIME := 0.2
const DASH_SPEED := 2100.0         # ~420 u por esquiva
const DASH_COOLDOWN := 2.5
const DASH_GRACE := 0.12           # invulnerable un instante mas al salir
const BURST_SHOTS := 3
const BURST_GAP := 0.12
const BURST_DAMAGE := 500.0
const HEAVY_DAMAGE := 1800.0
const PULSE_RADIUS := 380.0
const PULSE_DAMAGE := 900.0
const REPAIR_TOTAL := 1400.0
const REPAIR_TIME := 4.0
## nombre, tecla, enfriamiento
const SKILLS := [
	["Rafaga", "1", 5.0],
	["Impacto", "2", 8.0],
	["Pulso", "3", 10.0],
	["Reparar", "4", 18.0],
]

var combat: Node                   # tests/relief_combat.gd
var bench: Node                    # tests/view_relief.gd
var auto_dodge := false            # --dodge: la verificacion esquiva sola

var cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0]
var dash_cooldown := 0.0
var dash_left := 0.0
var dash_dir := Vector2.ZERO
var _grace := 0.0
var _burst_left := 0
var _burst_wait := 0.0
var _repair_left := 0.0

# contadores para verificar sin manos
var telegraphs := 0
var dodged := 0
var skill_hits := 0
var interrupts := 0

var _zones: Array = []             # amagos y charcos activos
var _slots: Array = []             # la barra de habilidades [{bg, fill, label}]
var _layer: CanvasLayer


func setup() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)
	var names := [["Esquiva", "Mayus"]]
	for s in SKILLS:
		names.append([s[0], s[1]])
	for entry in names:
		var bg := ColorRect.new()
		bg.color = Color(0.05, 0.07, 0.1, 0.8)
		bg.size = Vector2(92, 44)
		_layer.add_child(bg)
		var fill := ColorRect.new()
		fill.color = Color(0.25, 0.75, 0.95, 0.55)
		_layer.add_child(fill)
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 12)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size = Vector2(92, 44)
		label.text = "%s\n[%s]" % [entry[0], entry[1]]
		_layer.add_child(label)
		_slots.append({"bg": bg, "fill": fill, "label": label})


# ---------------- la nave ----------------

func invulnerable() -> bool:
	return dash_left > 0.0 or _grace > 0.0


## Mayus: un impulso en `dir` (direccion en el plano). Devuelve si salio.
func dash(dir: Vector2) -> bool:
	if dash_cooldown > 0.0 or dash_left > 0.0 or dir.length() < 0.01:
		return false
	dash_dir = dir.normalized()
	dash_left = DASH_TIME
	dash_cooldown = DASH_COOLDOWN
	return true


## Teclas 1-4.
func use(i: int) -> void:
	if i < 0 or i >= SKILLS.size() or cooldowns[i] > 0.0:
		return
	var has_target: bool = combat.target >= 0 and combat.npcs[combat.target].alive()
	match i:
		0, 1:
			if not has_target:
				combat._say("sin objetivo")
				return
			var n = combat.npcs[combat.target]
			if bench._pos.distance_to(n.pos) > combat.RANGE:
				combat._say("fuera de alcance")
				return
			if not combat.line_of_sight(bench._pos, bench._alt, n.pos, n.alt):
				combat._say("sin linea de vision: el terreno tapa")
				return
			if i == 0:
				_burst_left = BURST_SHOTS
				_burst_wait = 0.0
			else:
				combat._beam(bench._ship.position, n.world(), Color(1.0, 0.9, 0.4), 14.0)
				_interrupt(n)
				combat._hurt(n, HEAVY_DAMAGE)
				bench.shake(8.0)
			combat.attacking = true
		2:
			_ring_fx(bench._ship.position, PULSE_RADIUS, Color(0.4, 0.9, 1.0))
			for n in combat.npcs:
				if n.alive() and n.pos.distance_to(bench._pos) <= PULSE_RADIUS + n.radius:
					combat._hurt(n, PULSE_DAMAGE)
			bench.shake(6.0)
		3:
			_repair_left = REPAIR_TIME
	cooldowns[i] = float(SKILLS[i][2])


func _interrupt(n) -> void:
	if n.cast.is_empty() or str(n.cast.kind) == "run":
		return
	_drop_zone(n.cast.get("zone"))
	n.cast = {}
	n.stagger = STAGGER
	n.skill_cd = SKILL_GAP
	interrupts += 1
	combat._float("INTERRUMPIDO", n.world() + Vector3.UP * 110.0, Color(1.0, 0.9, 0.4))


func tick(delta: float) -> void:
	dash_cooldown = maxf(dash_cooldown - delta, 0.0)
	_grace = maxf(_grace - delta, 0.0)
	if dash_left > 0.0:
		dash_left -= delta
		if dash_left <= 0.0:
			_grace = DASH_GRACE
	for i in cooldowns.size():
		cooldowns[i] = maxf(cooldowns[i] - delta, 0.0)
	if _burst_left > 0:
		_burst_wait -= delta
		if _burst_wait <= 0.0:
			_burst_wait = BURST_GAP
			_burst_left -= 1
			if combat.target >= 0 and combat.npcs[combat.target].alive():
				var n = combat.npcs[combat.target]
				combat._beam(bench._ship.position, n.world(), Color(0.5, 1.0, 1.0), 7.0)
				combat._hurt(n, BURST_DAMAGE)
			else:
				_burst_left = 0
	if _repair_left > 0.0:
		var step := minf(delta, _repair_left)
		_repair_left -= step
		combat.hero_hp = minf(combat.hero_hp + REPAIR_TOTAL * step / REPAIR_TIME, combat.HERO_HP)
	if combat.auto:
		_auto_play()
	_tick_zones(delta)
	_draw_bar()


# ---------------- los bichos ----------------

## Lo llama el combate por cada bicho en pelea. Devuelve true si esta OCUPADO
## (amagando, embistiendo o aturdido): entonces ni camina ni dispara.
func npc_think(n, hero: Vector2, dist: float, sees: bool, delta: float) -> bool:
	n.shield = maxf(n.shield - delta, 0.0)
	if n.bubble != null:
		n.bubble.visible = n.shield > 0.0
	if n.stagger > 0.0:
		n.stagger -= delta
		return true
	if not n.cast.is_empty():
		_advance_cast(n, hero, delta)
		return true
	n.skill_cd -= delta
	var kit: Array = KITS.get(n.code, [])
	if kit.is_empty() or n.skill_cd > 0.0 or not sees or dist > SKILL_RANGE:
		return false
	var kind := str(kit[n.kit_i % kit.size()])
	n.kit_i += 1
	n.skill_cd = SKILL_GAP_ELITE if n.elite else SKILL_GAP
	match kind:
		"slam":
			var r := SLAM_RADIUS_ELITE if n.elite else SLAM_RADIUS
			n.cast = {"kind": "slam", "left": SLAM_WINDUP, "total": SLAM_WINDUP, "at": hero, "r": r,
				"zone": _circle_zone(hero, r, Color(1.0, 0.2, 0.15))}
			telegraphs += 1
		"pool":
			n.cast = {"kind": "pool", "left": POOL_WINDUP, "total": POOL_WINDUP, "at": hero,
				"zone": _circle_zone(hero, POOL_RADIUS, Color(0.6, 1.0, 0.2))}
			telegraphs += 1
		"charge":
			var dir: Vector2 = (hero - n.pos).normalized()
			n.cast = {"kind": "charge", "left": CHARGE_WINDUP, "total": CHARGE_WINDUP, "from": n.pos, "dir": dir,
				"zone": _line_zone(n.pos, dir, CHARGE_LENGTH, CHARGE_WIDTH, Color(1.0, 0.45, 0.1))}
			telegraphs += 1
		"shield":
			n.shield = SHIELD_TIME
			_ensure_bubble(n)
			combat._float("SE CUBRE", n.world() + Vector3.UP * 110.0, Color(0.5, 0.8, 1.0))
			return false
	return true


func _advance_cast(n, hero: Vector2, delta: float) -> void:
	var c: Dictionary = n.cast
	c.left = float(c.left) - delta
	if str(c.kind) == "run":
		# la embestida en curso: avanza por su linea, frenada por el terreno
		var step: Vector2 = (c.dir as Vector2) * (CHARGE_LENGTH / CHARGE_TIME) * delta
		if bench._target_alt(n.pos + step) - bench._target_alt(n.pos) <= combat.MAX_SLOPE * step.length():
			n.pos += step
		n.heading = c.dir
		if not bool(c.hit) and Geometry2D.get_closest_point_to_segment(hero, c.from, n.pos).distance_to(hero) \
				<= CHARGE_WIDTH * 0.5:
			c.hit = true
			_strike(n, n.damage * CHARGE_MULT)
		if float(c.left) <= 0.0:
			n.cast = {}
		return
	var zone: Dictionary = c.zone
	zone.fill = 1.0 - clampf(float(c.left) / float(c.total), 0.0, 1.0)
	if float(c.left) > 0.0:
		return
	_drop_zone(zone)
	match str(c.kind):
		"slam":
			_ring_fx(_ground(c.at), float(c.r), Color(1.0, 0.3, 0.2))
			if hero.distance_to(c.at) <= float(c.r):
				_strike(n, n.damage * SLAM_MULT)
			else:
				_miss()
			n.cast = {}
		"pool":
			var pool := _circle_zone(c.at, POOL_RADIUS, Color(0.6, 1.0, 0.2))
			pool.life = POOL_LIFE
			pool.dps = n.damage * POOL_MULT
			pool.fill = 1.0
			if hero.distance_to(c.at) > POOL_RADIUS:
				_miss()
			n.cast = {}
		"charge":
			n.cast = {"kind": "run", "left": CHARGE_TIME, "dir": c.dir, "from": n.pos, "hit": false}


func _strike(n, amount: float) -> void:
	if combat.hit_hero(amount):
		skill_hits += 1


## El amago se resolvio y la nave ya no estaba dentro: cuenta como esquivado.
func _miss() -> void:
	dodged += 1


func cast_label(n) -> String:
	if n.stagger > 0.0:
		return "  ATURDIDO"
	if n.shield > 0.0:
		return "  CUBIERTO"
	if n.cast.is_empty():
		return ""
	return "  >> " + str(LABELS.get(str(n.cast.kind), "EMBISTE"))


# ---------------- zonas en el suelo ----------------

func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x, bench._target_alt(p) - GROUND_DROP + 16.0, p.y)


static func _flat_material(color: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# CON prueba de profundidad: sin ella la zona se pintaba encima de la nave y la
	# tapaba justo cuando hay que verla. A cambio un bulto del suelo puede morderla.
	return mat


func _disc(color: Color, alpha: float) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 1.0
	mesh.radial_segments = 40
	mesh.material = _flat_material(color, alpha)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	bench._stage.add_child(mi)
	return mi


## Una zona circular: el borde fijo marca hasta donde llega, el relleno crece con
## el amago (lleno = cae el golpe).
func _circle_zone(at: Vector2, radius: float, color: Color) -> Dictionary:
	var edge := _disc(color, 0.18)
	var fill := _disc(color, 0.32)
	var pos := _ground(at)
	edge.position = pos
	edge.scale = Vector3(radius, 1.0, radius)
	fill.position = pos + Vector3.UP
	var zone := {"shape": "circle", "at": at, "r": radius, "edge": edge, "fill_node": fill, "fill": 0.0,
		"life": -1.0, "dps": 0.0}
	_zones.append(zone)
	return zone


func _line_zone(from: Vector2, dir: Vector2, length: float, width: float, color: Color) -> Dictionary:
	var nodes := []
	for alpha in [0.18, 0.34]:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.0, 1.0, 1.0)
		mesh.material = _flat_material(color, alpha)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.rotation.y = atan2(dir.x, dir.y)
		bench._stage.add_child(mi)
		nodes.append(mi)
	var zone := {"shape": "line", "from": from, "dir": dir, "len": length, "w": width,
		"edge": nodes[0], "fill_node": nodes[1], "fill": 0.0, "life": -1.0, "dps": 0.0}
	_zones.append(zone)
	return zone


func _drop_zone(zone) -> void:
	if zone == null or not (zone is Dictionary) or zone.is_empty():
		return
	(zone.edge as Node).queue_free()
	(zone.fill_node as Node).queue_free()
	_zones.erase(zone)


## ¿Esta el punto dentro de alguna zona activa? Devuelve hacia donde salir (o ZERO).
func escape_from(p: Vector2) -> Vector2:
	for zone: Dictionary in _zones:
		if str(zone.shape) == "circle":
			var away: Vector2 = p - (zone.at as Vector2)
			if away.length() <= float(zone.r) + 30.0:
				return away.normalized() if away.length() > 1.0 else Vector2.RIGHT
		else:
			var a: Vector2 = zone.from
			var b: Vector2 = a + (zone.dir as Vector2) * float(zone.len)
			var q := Geometry2D.get_closest_point_to_segment(p, a, b)
			if q.distance_to(p) <= float(zone.w) * 0.5 + 30.0:
				var side: Vector2 = (zone.dir as Vector2).orthogonal()
				return side if (p - q).dot(side) >= 0.0 else -side
	return Vector2.ZERO


func _tick_zones(delta: float) -> void:
	var hero: Vector2 = bench._pos
	for zone: Dictionary in _zones.duplicate():
		var fill := clampf(float(zone.fill), 0.02, 1.0)
		if str(zone.shape) == "circle":
			(zone.fill_node as MeshInstance3D).scale = Vector3(float(zone.r) * fill, 1.0, float(zone.r) * fill)
		else:
			var from: Vector2 = zone.from
			var dir: Vector2 = zone.dir
			var length: float = zone.len
			var mid := _ground(from + dir * length * 0.5)
			(zone.edge as MeshInstance3D).position = mid
			(zone.edge as MeshInstance3D).scale = Vector3(float(zone.w), 1.0, length)
			(zone.fill_node as MeshInstance3D).position = _ground(from + dir * length * fill * 0.5) + Vector3.UP
			(zone.fill_node as MeshInstance3D).scale = Vector3(float(zone.w), 1.0, length * fill)
		if float(zone.life) >= 0.0:
			# un charco: quema mientras estes dentro y se apaga solo
			zone.life = float(zone.life) - delta
			if hero.distance_to(zone.at) <= float(zone.r) and not invulnerable():
				combat.burn(float(zone.dps) * delta, "acido")
			if float(zone.life) <= 0.0:
				_drop_zone(zone)


func _ring_fx(at: Vector3, radius: float, color: Color) -> void:
	combat._blast(at, radius * 2.0, color)


func _ensure_bubble(n) -> void:
	if n.bubble != null:
		return
	var mesh := SphereMesh.new()
	mesh.radius = n.radius * 1.6
	mesh.height = n.radius * 3.2
	mesh.material = _flat_material(Color(0.4, 0.75, 1.0), 0.28)
	n.bubble = MeshInstance3D.new()
	n.bubble.mesh = mesh
	n.node.add_child(n.bubble)


# ---------------- la barra ----------------

func _draw_bar() -> void:
	var view := get_viewport().get_visible_rect().size
	var total := float(_slots.size()) * 98.0
	for i in _slots.size():
		var slot: Dictionary = _slots[i]
		# corrida a la izquierda: abajo a la derecha vive el minimapa
		var at := Vector2(view.x * 0.5 - total * 0.5 - 150.0 + float(i) * 98.0, view.y - 132.0)
		var left := dash_cooldown if i == 0 else cooldowns[i - 1]
		var full := DASH_COOLDOWN if i == 0 else float(SKILLS[i - 1][2])
		var ready := 1.0 - clampf(left / full, 0.0, 1.0)
		(slot.bg as ColorRect).position = at
		(slot.fill as ColorRect).position = at + Vector2(0.0, 44.0 * (1.0 - ready))
		(slot.fill as ColorRect).size = Vector2(92.0, 44.0 * ready)
		(slot.fill as ColorRect).color = Color(0.25, 0.75, 0.95, 0.55) if ready >= 1.0 else Color(0.5, 0.5, 0.55, 0.4)
		(slot.label as Label).position = at


# ---------------- verificacion sin manos ----------------

## --fight: usa las habilidades con criterio simple. --dodge: ademas, sale de las
## zonas anunciadas (esquivando si puede, andando si no).
func _auto_play() -> void:
	if combat.target >= 0 and combat.npcs[combat.target].alive():
		var n = combat.npcs[combat.target]
		if cooldowns[1] <= 0.0 and not n.cast.is_empty() and str(n.cast.kind) != "run":
			use(1)                 # guardar el Impacto para interrumpir
		if cooldowns[0] <= 0.0:
			use(0)
		if cooldowns[2] <= 0.0 and bench._pos.distance_to(n.pos) <= PULSE_RADIUS:
			use(2)
	if cooldowns[3] <= 0.0 and combat.hero_hp < combat.HERO_HP * 0.55:
		use(3)
	if auto_dodge:
		var out := escape_from(bench._pos)
		if out != Vector2.ZERO:
			if not bench.dash(out):
				bench._dest = bench._pos + out * 320.0


func report() -> String:
	return "HABILIDADES: anuncios %d, esquivados %d, golpes recibidos de habilidad %d, interrupciones %d, muertes %d" % [
		telegraphs, dodged, skill_hits, interrupts, combat.deaths]
