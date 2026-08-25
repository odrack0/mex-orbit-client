# Una entidad en pantalla: sprite orientado a su rumbo + nombre + barra de vida.
# Sus PARTICULARIDADES (textura, tamaño, anclajes de toberas, capa emisiva)
# salen de su JSON en data/ — nada hardcodeado por asset.
# Se mueve por interpolacion local y se reconcilia contra los ecos del server.
class_name EntityNode
extends Node2D

# Giro heredado del prototipo: tween de 0.1 s por el camino corto, orientacion
# cuantizada a 32 pasos de 11.25 grados (el look de los 32 frames del original)
# y zona muerta para no vibrar persiguiendo el cursor.
const TURN_TIME := 0.1
const TURN_STEPS := 32
const DEAD_ZONE := 2.0

var entity_id := 0
var speed := 0.0
var objetivo := Vector2.ZERO
var es_heroe := false
var es_npc := false
var click_radius := 42.0

var _sprite: Sprite2D
var _nombre: Label
var _hp: ColorRect
var _hp_pct := 1.0
var _seleccionada := false
var max_hp_abs := 0
var max_shield_abs := 0

var _visual_angle := 0.0          # grados de pantalla de la proa
var _turn_tween: Tween
var _idle_timer := 0.0

# motores (modelo del prototipo): una LLAMA por tobera anclada a la nave que
# crece con el empuje, mas una estela de CHISPAS soltadas al mundo
var _flames: Array[Sprite2D] = []
var _trails: Array[GPUParticles2D] = []
var _thrust := 0.0

# capa emisiva pulsante (nucleo y venas del Vex)
var _emissive: Sprite2D
var _pulse_min := 0.2          # intensidad del blend aditivo (>1 sobreexpone)
var _pulse_max := 2.4
var _pulse_speed := 2.6
var _pulse_sharp := 2.8        # 1 = seno suave; 3+ = destello marcado con valles largos


func setup(spawn, heroe: bool) -> void:   # spawn: MexProtocol.EntitySpawn
	entity_id = spawn.entity_id
	es_heroe = heroe
	es_npc = spawn.kind == MexProtocol.EntityKind.NPC
	speed = float(spawn.speed)
	position = Vector2(spawn.x, spawn.y)
	objetivo = position
	_idle_timer = 2.0 + randf() * 5.0
	_hp_pct = spawn.hp_pct

	var d := AssetDefs.entidad(spawn.type_id)
	click_radius = float(d.get("click_radius", 42))

	_sprite = Sprite2D.new()
	_sprite.texture = load(d.get("texture", "res://assets/npcs/vex-base.png"))
	# tamaño en pantalla constante segun el JSON, sea cual sea la resolucion del export
	var alto_tex := float(_sprite.texture.get_height())
	var factor: float = float(d.get("screen_size", 141)) / alto_tex
	_sprite.scale = Vector2.ONE * factor
	add_child(_sprite)

	# capa emisiva (si la define su JSON)
	if d.has("emissive"):
		_emissive = Sprite2D.new()
		_emissive.texture = load(d.emissive)
		_emissive.material = _material_add()
		_sprite.add_child(_emissive)
		var p: Dictionary = d.get("pulse", {})
		_pulse_min = float(p.get("min_intensity", 0.2))
		_pulse_max = float(p.get("max_intensity", 2.4))
		_pulse_speed = float(p.get("speed", 2.6))
		_pulse_sharp = float(p.get("sharpness", 2.8))

	# motores en los anclajes del JSON (espacio de la textura)
	var trail: Dictionary = d.get("engine_trail", {})
	for motor in d.get("engines", []):
		_flames.append(_crear_llama(motor, trail))
		_trails.append(_crear_estela(motor, trail))

	var color := NTheme.CYAN if heroe else (NTheme.TXT if not es_npc else NTheme.HOSTILE)
	_nombre = NTheme.label(spawn.name, NTheme.exo2(), 12, color)
	_nombre.position = Vector2(-60, -96)
	_nombre.custom_minimum_size = Vector2(120, 0)
	_nombre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_nombre)

	var pista := ColorRect.new()
	pista.color = Color(0, 0, 0, 0.55)
	pista.position = Vector2(-31, -78)
	pista.size = Vector2(62, 5)
	add_child(pista)
	_hp = ColorRect.new()
	_hp.color = NTheme.HP if not es_npc else NTheme.HOSTILE
	_hp.position = Vector2(-30, -77)
	_hp.size = Vector2(60 * _hp_pct, 3)
	add_child(_hp)


## La llama de una tobera: pluma anclada a la nave que rota con ella y crece
## con el empuje. Su boquilla queda EN la tobera y se afila hacia la popa.
func _crear_llama(motor: Dictionary, trail: Dictionary) -> Sprite2D:
	var llama := Sprite2D.new()
	llama.texture = load("res://assets/fx/engine-flame.png")
	llama.position = Vector2(float(motor.get("x", 0)), float(motor.get("y", 0)))
	# el arte de la llama apunta hacia ABAJO (+Y), que es la popa: sin rotar.
	# el pivote va en la boquilla para que crezca hacia atras, no hacia los lados
	llama.offset = Vector2(0, llama.texture.get_height() * 0.5)
	llama.modulate = AssetDefs.color(trail.get("color", "00E5FF"))
	llama.material = _material_add()
	llama.z_index = -1                   # detras del casco
	_sprite.add_child(llama)
	return llama


## Estela de chispas soltadas AL MUNDO (no siguen a la nave): el rastro que
## queda atras, como el humo de motor del prototipo.
func _crear_estela(motor: Dictionary, trail: Dictionary) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.position = Vector2(float(motor.get("x", 0)), float(motor.get("y", 0)))
	p.amount = 96                   # densas: la estela debe leerse continua
	p.lifetime = float(trail.get("lifetime", 0.42))
	p.local_coords = false          # se quedan en el mundo: se ve el rastro
	p.texture = load("res://assets/fx/spark.png")

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = float(trail.get("width", 9)) * 0.3
	mat.direction = Vector3(0, 1, 0)     # hacia la popa (+Y de la textura)
	mat.spread = 5.0
	mat.gravity = Vector3.ZERO
	var largo: float = float(trail.get("length", 96))
	mat.initial_velocity_min = largo * 0.15
	mat.initial_velocity_max = largo * 0.35
	mat.damping_min = largo * 1.0
	mat.damping_max = largo * 1.6
	mat.scale_min = 0.04            # finas: chispas, no bolas
	mat.scale_max = 0.10
	# las chispas se encogen al apagarse
	var curva := Curve.new()
	curva.add_point(Vector2(0, 1.0))
	curva.add_point(Vector2(1, 0.0))
	var curva_tex := CurveTexture.new()
	curva_tex.curve = curva
	mat.scale_curve = curva_tex

	var grad := Gradient.new()
	var nucleo := AssetDefs.color(trail.get("core_color", "DFFBFF"))
	var color := AssetDefs.color(trail.get("color", "00E5FF"))
	grad.set_color(0, nucleo)
	grad.set_color(1, Color(color, 0.0))
	grad.add_point(0.3, color)
	var rampa := GradientTexture1D.new()
	rampa.gradient = grad
	mat.color_ramp = rampa

	p.process_material = mat
	p.material = _material_add()
	p.emitting = false
	_sprite.add_child(p)
	return p


static func _material_add() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


func _process(delta: float) -> void:
	var en_vuelo := position.distance_to(objetivo) > 0.5

	# acelerador: el empuje sube en vuelo y cae al frenar (modelo del prototipo)
	if not _flames.is_empty() or not _trails.is_empty():
		_thrust = clampf(_thrust + (3.0 if en_vuelo else -4.0) * delta, 0.0, 1.0)
		# la llama crece a lo largo con el empuje y respira; el ancho apenas cambia
		var respiro := 1.0 + 0.10 * sin(Time.get_ticks_msec() * 0.02 + entity_id)
		for llama in _flames:
			llama.visible = _thrust > 0.02
			llama.scale = Vector2(0.55 + 0.15 * _thrust, _thrust * respiro)
			llama.self_modulate.a = 0.35 + 0.65 * _thrust
		for t in _trails:
			t.emitting = _thrust > 0.15
			t.self_modulate.a = _thrust

	# el latido de la capa emisiva (fase por entidad: no laten al unisono).
	# Se modula la INTENSIDAD del blend aditivo, no solo el alfa: por encima de
	# 1 sobreexpone y el nucleo se pone blanco, que es lo que hace visible el pulso.
	if _emissive != null:
		var onda := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * _pulse_speed + entity_id * 1.7)
		onda = pow(onda, _pulse_sharp)
		var k: float = _pulse_min + (_pulse_max - _pulse_min) * onda
		_emissive.self_modulate = Color(k, k, k, 1.0)

	if en_vuelo:
		position = position.move_toward(objetivo, speed * delta)
	elif es_npc:
		# NPCs parados: giro perezoso aleatorio cada 2-7 s (vida del original)
		_idle_timer -= delta
		if _idle_timer <= 0.0:
			_idle_timer = 2.0 + randf() * 5.0
			_girar_a(_visual_angle + (randf() - 0.5) * 360.0)


## Fija el destino y orienta la proa UNA vez (no cada frame, como el prototipo).
func set_objetivo(destino: Vector2) -> void:
	# zona muerta del prototipo: un destino encima de la nave en pleno vuelo
	# no re-orienta (evita el trompo al clickear sobre ti mismo)
	var en_vuelo := position.distance_to(objetivo) > 0.5
	if en_vuelo and absf(destino.x - position.x) <= DEAD_ZONE \
			and absf(destino.y - position.y) <= DEAD_ZONE:
		objetivo = destino
		return
	objetivo = destino
	var rumbo := destino - position
	if rumbo.length() > 1.0:
		# proa hacia arriba en el arte -> +90 grados de pantalla
		_girar_a(rad_to_deg(rumbo.angle()) + 90.0)


## Giro del prototipo: cuantizado a TURN_STEPS y tweenado por el camino corto.
func _girar_a(grados: float) -> void:
	var paso := 360.0 / TURN_STEPS
	var destino_ang := fposmod(roundf(grados / paso) * paso, 360.0)
	var delta := fposmod(destino_ang - _visual_angle + 180.0, 360.0) - 180.0
	if is_zero_approx(delta):
		return
	if _turn_tween != null:
		_turn_tween.kill()
	_turn_tween = create_tween()
	_turn_tween.tween_method(_set_visual_angle, _visual_angle, _visual_angle + delta, TURN_TIME)


func _set_visual_angle(grados: float) -> void:
	_visual_angle = fposmod(grados, 360.0)
	# el giro SALTA de posicion en posicion durante el tween, como el flip de
	# frames del sheet original: es el look que distingue al prototipo
	var paso := 360.0 / TURN_STEPS
	_sprite.rotation_degrees = roundf(_visual_angle / paso) * paso


## Eco autoritativo del server: correccion suave si la deriva es chica, snap si es grande.
func reconcile(x: float, y: float, tx: float, ty: float, nueva_vel: float, teleport: bool) -> void:
	speed = nueva_vel
	var server_pos := Vector2(x, y)
	if teleport or position.distance_to(server_pos) > 220.0:
		position = server_pos
	else:
		position = position.lerp(server_pos, 0.35)
	set_objetivo(Vector2(tx, ty))


func set_hp_pct(pct: float) -> void:
	_hp_pct = clampf(pct, 0.0, 1.0)
	_hp.size.x = 60 * _hp_pct


func set_hp_abs(hp: int) -> void:
	if max_hp_abs > 0:
		set_hp_pct(float(hp) / max_hp_abs)


## Seleccion local: esquinas de mira alrededor de la entidad (estilo N).
func set_selected(sel: bool) -> void:
	_seleccionada = sel
	queue_redraw()


func _draw() -> void:
	if not _seleccionada:
		return
	var r := 58.0
	var l := 16.0
	var c := NTheme.HOSTILE if not es_heroe else NTheme.CYAN
	for esquina in [Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)]:
		var dx := -l if esquina.x > 0 else l
		var dy := -l if esquina.y > 0 else l
		draw_line(esquina, esquina + Vector2(dx, 0), c, 2.0)
		draw_line(esquina, esquina + Vector2(0, dy), c, 2.0)
