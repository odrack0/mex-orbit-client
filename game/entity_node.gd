# Una entidad en pantalla: sprite orientado a su rumbo + nombre + barra de vida.
# Se mueve por interpolacion local (pos -> target a su velocidad) y se
# reconcilia contra los ecos autoritativos del server.
class_name EntityNode
extends Node2D

const TEXTURAS := {
	"phoenix": preload("res://assets/ships/phoenix.png"),
	"vex": preload("res://assets/npcs/vex.png"),
}

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

var _visual_angle := 0.0          # grados de pantalla de la proa
var _turn_tween: Tween
var _idle_timer := 0.0
var max_hp_abs := 0               # llega con TargetInfo; permite barras absolutas
var max_shield_abs := 0

# llamas de motor con acelerador (herencia del prototipo: el empuje sube al
# volar y se apaga al frenar, la llama respira con el)
var _flames: Array[Sprite2D] = []
var _thrust := 0.0

var _sprite: Sprite2D
var _nombre: Label
var _hp: ColorRect
var _hp_pct := 1.0
var _seleccionada := false


func setup(spawn, heroe: bool) -> void:   # spawn: MexProtocol.EntitySpawn
	entity_id = spawn.entity_id
	es_heroe = heroe
	es_npc = spawn.kind == MexProtocol.EntityKind.NPC
	speed = float(spawn.speed)
	position = Vector2(spawn.x, spawn.y)
	objetivo = position
	_idle_timer = 2.0 + randf() * 5.0
	_hp_pct = spawn.hp_pct

	_sprite = Sprite2D.new()
	_sprite.texture = TEXTURAS.get(spawn.type_id, TEXTURAS["vex"])
	_sprite.scale = Vector2.ONE * 0.55
	add_child(_sprite)

	# toberas: dos llamas aditivas en la popa (solo naves, no bichos)
	if not es_npc:
		var tex: Texture2D = load("res://assets/fx/engine-flame.png")
		for lado in [-22.0, 22.0]:
			var llama := Sprite2D.new()
			llama.texture = tex
			llama.rotation_degrees = 90.0
			llama.position = Vector2(lado, 98.0)
			llama.offset = Vector2(118.0, 0.0)   # la llama nace en la tobera y crece hacia atras
			llama.scale = Vector2(0.0, 0.55)
			llama.material = _material_add()
			_sprite.add_child(llama)
			_flames.append(llama)

	var color := NTheme.CYAN if heroe else (NTheme.TXT if spawn.kind == MexProtocol.EntityKind.PLAYER else NTheme.HOSTILE)
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
	_hp.color = NTheme.HP if spawn.kind == MexProtocol.EntityKind.PLAYER else NTheme.HOSTILE
	_hp.position = Vector2(-30, -77)
	_hp.size = Vector2(60 * _hp_pct, 3)
	add_child(_hp)


static func _material_add() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


func _process(delta: float) -> void:
	# acelerador: el empuje sube en vuelo y se apaga al frenar; la llama respira
	var en_vuelo := position.distance_to(objetivo) > 0.5
	if not _flames.is_empty():
		_thrust = clampf(_thrust + (2.5 if en_vuelo else -3.5) * delta, 0.0, 1.0)
		var respiro := 1.0 + 0.12 * sin(Time.get_ticks_msec() * 0.02 + entity_id)
		for llama in _flames:
			llama.scale.x = 0.42 * _thrust * respiro
			llama.self_modulate.a = _thrust

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
