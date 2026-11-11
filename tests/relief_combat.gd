extends Node

## El COMBATE del banco del relieve (prueba de concepto, 10-nov-2026). No es el
## combate del juego: es lo minimo para responder UNA pregunta — ¿se puede pelear
## al estilo DarkOrbit (seleccionar, disparar, leer la pelea) con la camara detras
## de la nave y con terreno de por medio?
##
##   click en un bicho = seleccionar (otro click en el mismo = atacar)
##   TAB = siguiente objetivo, por cercania · ESPACIO = atacar / dejar de atacar
##
## Tres cosas que la vista cenital da gratis y aqui hay que construir:
##   - el objetivo puede quedar FUERA DE CUADRO (o detras): un indicador en el
##     borde de la pantalla dice hacia donde y a que distancia;
##   - quien te dispara sin estar seleccionado tambien sale en el borde;
##   - el terreno TAPA: sin linea de vision no se dispara, ni tu ni ellos.
##
## Todo es local y de mentira: sin servidor, sin escudos, sin municion.

const RANGE := 650.0               # alcance del laser, en el plano
const HERO_HP := 4000.0
const HERO_DAMAGE := 600.0
const HERO_COOLDOWN := 1.0
const NPC_DAMAGE := 130.0
const NPC_COOLDOWN := 1.5
const NPC_SPEED := 200.0
const NPC_WANDER_SPEED := 70.0
const NPC_WANDER_RADIUS := 260.0
const NPC_KEEP := 380.0            # distancia a la que el bicho deja de acercarse
const NPC_AGGRO := 430.0           # te ve a esta distancia (con linea de vision)
const NPC_LEASH := 2200.0          # mas lejos que esto de su casa, se rinde y vuelve
const NPC_RESPAWN := 9.0
const THINK_DIST := 3200.0         # mas lejos que esto, y sin pelea, el bicho no se procesa
const NPC_HP := 6500.0             # subio de 4200 con las habilidades: la nave pega ~2,5 veces mas
const MAX_SLOPE := 1.2
const LOS_STEPS := 16
const LOS_MARGIN := 12.0
const BEAM_LIFE := 0.16
const EDGE_MARGIN := 70.0
const EDGE_TOP := 175.0

const DEFAULT_NPCS := [
	{"code": "vex", "x": 2900, "y": 2300},
	{"code": "vex", "x": 2650, "y": 1650},
	{"code": "vexor", "x": 4700, "y": 2560},
	{"code": "vex", "x": 6050, "y": 2890},
	{"code": "skarnox", "x": 5000, "y": 1900},
	{"code": "gravon", "x": 6000, "y": 5300},
]


class Npc:
	var code := ""
	var name := ""
	var max_hp := 0.0
	var damage := 0.0
	var aggressive := true         # false = no ataca si no lo tocas
	var elite := false
	var home := Vector2.ZERO
	var pos := Vector2.ZERO
	var alt := 80.0
	var heading := Vector2.RIGHT
	var hp := 0.0
	var radius := 50.0
	var node: Node3D
	var aggro := false
	var cooldown := 0.0
	var dead_for := -1.0           # < 0 = vivo
	var wander_to := Vector2.ZERO
	var wander_wait := 0.0
	var tag: Label
	var bar_bg: ColorRect
	var bar: ColorRect
	# la capa de habilidades (tests/relief_skills.gd)
	var cast := {}                 # el amago en curso
	var skill_cd := 2.0
	var kit_i := 0
	var stagger := 0.0
	var shield := 0.0
	var bubble: MeshInstance3D
	var punch := 0.0               # el "golpe" visual al recibir danio

	func alive() -> bool:
		return dead_for < 0.0

	func world() -> Vector3:
		return Vector3(pos.x, alt, pos.y)


var bench: Node                    # tests/view_relief.gd (el banco): pos, altura, terreno, camara
var npcs: Array[Npc] = []
var target := -1
var attacking := false
var hero_hp := HERO_HP
var hero_cooldown := 0.0
var auto := false                  # --fight: selecciona y ataca solo (verificacion)
var auto_index := -1

# contadores para verificar sin manos
var shots := 0
var kills := 0
var los_denied := 0
var hits_taken := 0
var deaths := 0
var skills: Node                   # tests/relief_skills.gd

var _rng := RandomNumberGenerator.new()
var _layer: CanvasLayer
var _ring: MeshInstance3D
var _beams: Array = []             # [{node, left}]
var _floaters: Array = []          # [{label, world, left}]
var _blasts: Array = []            # [{node, mat, left}]
var _edge_tags: Array[Label] = []
var _hero_tag: Label
var _hero_bar_bg: ColorRect
var _hero_bar: ColorRect
var _burn_note := 0.0
var _note := ""
var _note_left := 0.0


func setup(defs: Array) -> void:
	_rng.seed = 5
	_layer = CanvasLayer.new()
	add_child(_layer)
	for d: Dictionary in (defs if not defs.is_empty() else DEFAULT_NPCS):
		_spawn(d)

	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	torus.rings = 48
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(1.0, 0.25, 0.2)
	ring_mat.no_depth_test = true
	torus.material = ring_mat
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.visible = false
	bench._stage.add_child(_ring)

	_hero_bar_bg = ColorRect.new()
	_hero_bar_bg.color = Color(0, 0, 0, 0.6)
	_hero_bar_bg.size = Vector2(260, 12)
	_layer.add_child(_hero_bar_bg)
	_hero_bar = ColorRect.new()
	_hero_bar.color = Color(0.3, 0.9, 0.4)
	_hero_bar.size = Vector2(260, 12)
	_layer.add_child(_hero_bar)
	_hero_tag = Label.new()
	_layer.add_child(_hero_tag)

	skills = (load("res://tests/relief_skills.gd") as GDScript).new()
	skills.combat = self
	skills.bench = bench
	add_child(skills)
	skills.setup()


## Un bicho del trazado: {code, x, y} y, opcionales, name, hp, damage,
## aggressive (false = solo responde si lo atacas) y elite.
func _spawn(d: Dictionary) -> void:
	var code := str(d.get("code", "vex"))
	var at := Vector2(float(d.get("x", 0)), float(d.get("y", 0)))
	var def := AssetDefs.npc(code)
	var n := Npc.new()
	n.code = code
	n.elite = bool(d.get("elite", false))
	n.name = ("* " if n.elite else "") + str(d.get("name", code.capitalize()))
	n.max_hp = float(d.get("hp", NPC_HP))
	n.damage = float(d.get("damage", NPC_DAMAGE))
	n.aggressive = bool(d.get("aggressive", true))
	n.home = at
	n.pos = at
	n.wander_to = at
	n.hp = n.max_hp
	n.radius = float(def.get("click_radius", 50)) * (1.5 if n.elite else 1.0)
	n.alt = bench._target_alt(at)
	n.node = Node3D.new()
	bench._stage.add_child(n.node)
	var path := str(def.get("model", ""))
	if path != "" and ResourceLoader.exists(path):
		var model: Node3D = (load(path) as PackedScene).instantiate()
		model.scale = Vector3.ONE * (float(def.get("screen_size", 150)) / AssetDefs.extent_3d(model)) \
			* (1.5 if n.elite else 1.0)
		model.rotation_degrees.y = float((def.get("orientation", {}) as Dictionary).get("yaw", 0.0))
		n.node.add_child(model)
	n.bar_bg = ColorRect.new()
	n.bar_bg.color = Color(0, 0, 0, 0.6)
	_layer.add_child(n.bar_bg)
	n.bar = ColorRect.new()
	n.bar.color = Color(0.9, 0.25, 0.2)
	_layer.add_child(n.bar)
	n.tag = Label.new()
	n.tag.add_theme_font_size_override("font_size", 13)
	_layer.add_child(n.tag)
	npcs.append(n)


# ---- entrada ----

## El bicho bajo el cursor, o -1. El radio de click es el del bicho proyectado a
## pantalla, con un minimo: de lejos un bicho son 10 px y no se le atina.
func pick(px: Vector2) -> int:
	var cam: Camera3D = bench._stage.cam_node
	var best := -1
	var best_d := INF
	for i in npcs.size():
		var n := npcs[i]
		if not n.alive() or cam.is_position_behind(n.world()):
			continue
		var sp := cam.unproject_position(n.world())
		var edge := cam.unproject_position(n.world() + cam.global_basis.x * n.radius)
		var d := px.distance_to(sp)
		if d <= maxf(sp.distance_to(edge), 26.0) and d < best_d:
			best = i
			best_d = d
	return best


func select(i: int) -> void:
	if i == target and i >= 0:
		attacking = true           # segundo click en el mismo: atacar
		return
	target = i
	attacking = false


## TAB: el siguiente vivo por cercania (ciclico).
func cycle() -> void:
	var order: Array = []
	for i in npcs.size():
		if npcs[i].alive():
			order.append(i)
	if order.is_empty():
		target = -1
		return
	order.sort_custom(func(a, b): return npcs[a].pos.distance_to(bench._pos) < npcs[b].pos.distance_to(bench._pos))
	var at := order.find(target)
	target = order[(at + 1) % order.size()]
	attacking = false


func toggle_attack() -> void:
	if target >= 0:
		attacking = not attacking


# ---- por frame ----

func tick(delta: float) -> void:
	var hero: Vector2 = bench._pos
	var hero_alt: float = bench._alt
	if auto:
		_auto_pilot()

	hero_cooldown = maxf(hero_cooldown - delta, 0.0)
	if target >= 0 and not npcs[target].alive():
		target = -1
		attacking = false
	if attacking and target >= 0 and hero_cooldown <= 0.0:
		var n := npcs[target]
		if hero.distance_to(n.pos) > RANGE:
			_say("fuera de alcance")
		elif not line_of_sight(hero, hero_alt, n.pos, n.alt):
			_say("sin linea de vision: el terreno tapa")
			los_denied += 1
			hero_cooldown = 0.4
		else:
			hero_cooldown = HERO_COOLDOWN
			shots += 1
			_beam(Vector3(hero.x, hero_alt, hero.y), n.world(), Color(0.3, 0.95, 1.0))
			_hurt(n, HERO_DAMAGE)

	for n in npcs:
		_tick_npc(n, hero, hero_alt, delta)
	skills.tick(delta)
	_tick_fx(delta)
	_draw_hud()


func _tick_npc(n: Npc, hero: Vector2, hero_alt: float, delta: float) -> void:
	# lejos y sin pelea, un bicho no piensa: con medio centenar repartidos por tres
	# planetas, mirar la linea de vision de todos cada frame no sale gratis
	if n.alive() and not n.aggro and n.pos.distance_to(hero) > THINK_DIST:
		return
	if not n.alive():
		n.dead_for += delta
		if n.dead_for >= NPC_RESPAWN:
			n.dead_for = -1.0
			n.hp = n.max_hp
			n.pos = n.home
			n.aggro = false
			n.node.visible = true
		return
	var dist := n.pos.distance_to(hero)
	var sees := line_of_sight(n.pos, n.alt, hero, hero_alt)
	if not n.aggro and n.aggressive and dist < NPC_AGGRO and sees:
		n.aggro = true
	# se rinde si se aleja demasiado de casa o si te metes en zona segura
	if n.aggro and (n.pos.distance_to(n.home) > NPC_LEASH or bench.hero_safe()):
		n.aggro = false
		n.hp = n.max_hp
	n.cooldown = maxf(n.cooldown - delta, 0.0)

	var goal := n.pos
	var speed := NPC_SPEED
	# amagando, embistiendo o aturdido: ni camina ni dispara
	var busy: bool = n.aggro and skills.npc_think(n, hero, dist, sees, delta)
	if busy:
		pass
	elif n.aggro:
		if dist > NPC_KEEP or not sees:
			goal = hero
		if dist <= RANGE and sees and n.cooldown <= 0.0:
			n.cooldown = NPC_COOLDOWN
			_beam(n.world(), Vector3(hero.x, hero_alt, hero.y), Color(1.0, 0.45, 0.2))
			hit_hero(n.damage)
	else:
		speed = NPC_WANDER_SPEED
		n.wander_wait -= delta
		if n.wander_wait <= 0.0:
			n.wander_wait = _rng.randf_range(4.0, 8.0)
			n.wander_to = n.home + Vector2.RIGHT.rotated(_rng.randf() * TAU) * _rng.randf() * NPC_WANDER_RADIUS
		goal = n.wander_to
	var to_goal := goal - n.pos
	if to_goal.length() > 8.0:
		var step := to_goal.normalized() * minf(speed * delta, to_goal.length())
		# la misma regla que la nave: lo empinado no se sube
		if bench._target_alt(n.pos + step) - bench._target_alt(n.pos) <= MAX_SLOPE * step.length():
			n.pos += step
			n.heading = step.normalized()
	if n.aggro and not busy:
		n.heading = (hero - n.pos).normalized() if dist > 1.0 else n.heading
	n.alt = lerpf(n.alt, bench._target_alt(n.pos), 1.0 - exp(-5.0 * delta))
	n.punch = maxf(n.punch - delta, 0.0)
	n.node.scale = Vector3.ONE * (1.0 + 2.2 * n.punch)
	n.node.position = n.world()
	n.node.rotation.y = atan2(-n.heading.x, -n.heading.y)


## ¿Hay visual directa entre dos puntos? Se camina la recta y se compara su altura
## con la del terreno. Solo el TERRENO tapa: las piezas sueltas (pecio, rocas) no.
func line_of_sight(a: Vector2, a_alt: float, b: Vector2, b_alt: float) -> bool:
	var relief: Relief3D = bench._relief
	for i in range(1, LOS_STEPS):
		var k := float(i) / float(LOS_STEPS)
		var h := relief.height_at(a.lerp(b, k))
		if not is_nan(h) and h > lerpf(a_alt, b_alt, k) - LOS_MARGIN:
			return false
	return true


func _hurt(n: Npc, dmg: float) -> void:
	if not n.alive():
		return
	var covered := n.shield > 0.0
	if covered:
		dmg *= skills.SHIELD_FACTOR
	n.hp -= dmg
	n.aggro = true
	n.punch = 0.09                 # el bicho ACUSA el golpe: un respingo
	_float(("%d (cubierto)" if covered else "%d") % dmg, n.world() + Vector3.UP * 60.0,
		Color(0.6, 0.8, 1.0) if covered else Color(1, 1, 1))
	if n.hp <= 0.0:
		kills += 1
		n.dead_for = 0.0
		n.node.visible = false
		if not n.cast.is_empty():
			skills._drop_zone(n.cast.get("zone"))
			n.cast = {}
		_blast(n.world(), n.radius * 4.0)
		bench.shake(12.0 if n.elite else 7.0)


## Un golpe a la nave. Si esta esquivando no entra. Devuelve si hizo danio.
func hit_hero(amount: float) -> bool:
	var at := Vector3(bench._pos.x, bench._alt + 60.0, bench._pos.y)
	if skills.invulnerable():
		_float("ESQUIVADO", at, Color(0.5, 1.0, 1.0))
		skills.dodged += 1
		return false
	hits_taken += 1
	hero_hp -= amount
	_float("-%d" % amount, at, Color(1.0, 0.5, 0.3))
	bench.shake(clampf(amount / 60.0, 3.0, 14.0))
	if hero_hp <= 0.0:
		_hero_down()
	return true


## Danio del entorno (lava): sin atacante.
func burn(amount: float, what: String) -> void:
	hero_hp -= amount
	_burn_note -= amount
	if _burn_note <= 0.0:
		_burn_note = 120.0
		_say("te quema la %s" % what)
	if hero_hp <= 0.0:
		_hero_down()


func _hero_down() -> void:
	deaths += 1
	_say("NAVE DESTRUIDA — reaparece en el inicio")
	hero_hp = HERO_HP
	attacking = false
	target = -1
	for n in npcs:
		n.aggro = false
	bench.respawn()


func _auto_pilot() -> void:
	if target >= 0 and npcs[target].alive():
		attacking = true
		return
	if auto_index >= 0 and auto_index < npcs.size() and npcs[auto_index].alive():
		target = auto_index
	else:
		target = -1
		var best := INF
		for i in npcs.size():
			var d := npcs[i].pos.distance_to(bench._pos)
			if npcs[i].alive() and d < best and auto_index < 0:
				best = d
				target = i
	attacking = target >= 0


# ---- efectos ----

func _beam(a: Vector3, b: Vector3, color: Color, thick := 5.0) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(thick, thick, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color
	box.material = mat
	mi.mesh = box
	bench._stage.add_child(mi)
	mi.look_at_from_position((a + b) * 0.5, b, Vector3.UP)
	mi.scale = Vector3(1.0, 1.0, a.distance_to(b))
	_beams.append({"node": mi, "left": BEAM_LIFE})


func _blast(at: Vector3, size: float, color := Color(1.0, 0.6, 0.2)) -> void:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color
	sphere.material = mat
	mi.mesh = sphere
	mi.position = at
	bench._stage.add_child(mi)
	_blasts.append({"node": mi, "mat": mat, "left": 0.45, "size": size})


func _float(text: String, world: Vector3, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 18)
	_layer.add_child(l)
	_floaters.append({"label": l, "world": world, "left": 0.9})


func _say(text: String) -> void:
	_note = text
	_note_left = 1.6


func _tick_fx(delta: float) -> void:
	_note_left = maxf(_note_left - delta, 0.0)
	for b: Dictionary in _beams:
		b.left -= delta
	for b: Dictionary in _beams.filter(func(x): return x.left <= 0.0):
		(b.node as Node).queue_free()
	_beams = _beams.filter(func(x): return x.left > 0.0)
	for b: Dictionary in _blasts:
		b.left -= delta
		var k: float = 1.0 - clampf(float(b.left) / 0.45, 0.0, 1.0)
		(b.node as MeshInstance3D).scale = Vector3.ONE * lerpf(20.0, float(b.size), k)
		(b.mat as StandardMaterial3D).albedo_color.a = 1.0 - k
	for b: Dictionary in _blasts.filter(func(x): return x.left <= 0.0):
		(b.node as Node).queue_free()
	_blasts = _blasts.filter(func(x): return x.left > 0.0)
	for f: Dictionary in _floaters:
		f.left -= delta
	for f: Dictionary in _floaters.filter(func(x): return x.left <= 0.0):
		(f.label as Node).queue_free()
	_floaters = _floaters.filter(func(x): return x.left > 0.0)


# ---- HUD ----

func _draw_hud() -> void:
	var cam: Camera3D = bench._stage.cam_node
	var view := get_viewport().get_visible_rect().size
	var hero: Vector2 = bench._pos
	var edge_i := 0
	for i in npcs.size():
		var n := npcs[i]
		var on := n.alive() and not cam.is_position_behind(n.world())
		var sp := cam.unproject_position(n.world() + Vector3.UP * (n.radius + 40.0)) if on else Vector2.ZERO
		var inside := on and Rect2(Vector2.ZERO, view).has_point(sp)
		var dist := n.pos.distance_to(hero)
		var near_enough := dist < 1700.0 or i == target or n.aggro
		n.tag.visible = inside and near_enough
		n.bar.visible = inside and near_enough
		n.bar_bg.visible = inside and near_enough
		if inside and near_enough:
			var chosen := i == target
			n.tag.text = (("[ %s ]  %d u" if chosen else "%s  %d u") % [n.name, dist]) + skills.cast_label(n)
			n.tag.add_theme_color_override("font_color",
				Color(1.0, 0.35, 0.3) if chosen else (Color(1.0, 0.75, 0.4) if n.aggro else Color(0.85, 0.85, 0.85)))
			n.tag.position = sp + Vector2(-n.tag.size.x * 0.5, -34.0)
			n.bar_bg.size = Vector2(70, 5)
			n.bar_bg.position = sp + Vector2(-35, -12)
			n.bar.size = Vector2(70.0 * clampf(n.hp / n.max_hp, 0.0, 1.0), 5)
			n.bar.position = n.bar_bg.position
		# fuera de cuadro: el objetivo y cualquiera que te este atacando salen en el borde
		if n.alive() and not inside and (i == target or n.aggro):
			var tag := _edge_tag(edge_i)
			edge_i += 1
			var raw := cam.unproject_position(n.world())
			var dir := raw - view * 0.5
			if cam.is_position_behind(n.world()):
				dir = -dir         # detras de la camara la proyeccion sale espejada
			if dir.length() < 1.0:
				dir = Vector2.DOWN
			var half := view * 0.5 - Vector2.ONE * EDGE_MARGIN
			var scale := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
			tag.text = "%s %s  %d u" % [_arrow(dir), n.name, dist]
			tag.add_theme_color_override("font_color",
				Color(1.0, 0.35, 0.3) if i == target else Color(1.0, 0.75, 0.4))
			tag.position = view * 0.5 + dir * scale - tag.size * 0.5
			tag.position.y = maxf(tag.position.y, EDGE_TOP)   # bajo el texto de ayuda del banco
			tag.visible = true
	for j in range(edge_i, _edge_tags.size()):
		_edge_tags[j].visible = false

	_ring.visible = target >= 0 and npcs[target].alive()
	if _ring.visible:
		var t := npcs[target]
		_ring.position = t.world() - Vector3.UP * 25.0
		_ring.scale = Vector3.ONE * t.radius * 1.5

	for f: Dictionary in _floaters:
		var l: Label = f.label
		var w: Vector3 = f.world
		l.visible = not cam.is_position_behind(w)
		l.position = cam.unproject_position(w) + Vector2(-12.0, -40.0 * (1.0 - float(f.left) / 0.9))
		l.modulate.a = clampf(float(f.left) / 0.4, 0.0, 1.0)

	_hero_bar_bg.position = Vector2(view.x * 0.5 - 130.0, view.y - 46.0)
	_hero_bar.position = _hero_bar_bg.position
	_hero_bar.size = Vector2(260.0 * clampf(hero_hp / HERO_HP, 0.0, 1.0), 12)
	_hero_tag.text = "CASCO %d / %d" % [hero_hp, HERO_HP]
	_hero_tag.position = Vector2(view.x * 0.5 - _hero_tag.size.x * 0.5, view.y - 74.0)


func _edge_tag(i: int) -> Label:
	while _edge_tags.size() <= i:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 17)
		_layer.add_child(l)
		_edge_tags.append(l)
	return _edge_tags[i]


static func _arrow(dir: Vector2) -> String:
	if absf(dir.x) > absf(dir.y):
		return "►" if dir.x > 0.0 else "◄"
	return "▼" if dir.y > 0.0 else "▲"


## ¿Hay pelea en curso? (atacando a un objetivo vivo): la camara y el morro de la
## nave giran hacia el.
func engaged() -> bool:
	return attacking and target >= 0 and npcs[target].alive()


func target_pos() -> Vector2:
	return npcs[target].pos


func target_world() -> Vector3:
	return npcs[target].world()


## Una linea para la etiqueta del banco.
func status() -> String:
	var who := "ninguno"
	if target >= 0:
		var n := npcs[target]
		who = "%s a %d u%s" % [n.name, n.pos.distance_to(bench._pos), "  ·  ATACANDO" if attacking else ""]
	var note := ("  ·  " + _note) if _note_left > 0.0 else ""
	return "click en bicho = seleccionar (otra vez = atacar) · TAB = siguiente · ESPACIO = atacar · MAYUS = esquivar · 1-4 = habilidades  ·  objetivo: %s%s" % [who, note]


func report() -> String:
	return "COMBATE: disparos %d, bajas %d, golpes recibidos %d, casco %d, sin linea de vision %d" % [
		shots, kills, hits_taken, hero_hp, los_denied]
