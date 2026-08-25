# Una entidad en pantalla: sprite orientado a su rumbo + nombre + barra de vida.
# Se mueve por interpolacion local (pos -> target a su velocidad) y se
# reconcilia contra los ecos autoritativos del server.
class_name EntityNode
extends Node2D

const TEXTURAS := {
	"phoenix": preload("res://assets/ships/phoenix.png"),
	"vex": preload("res://assets/npcs/vex.png"),
}

var entity_id := 0
var speed := 0.0
var objetivo := Vector2.ZERO
var es_heroe := false

var _sprite: Sprite2D
var _nombre: Label
var _hp: ColorRect
var _hp_pct := 1.0
var _seleccionada := false


func setup(spawn, heroe: bool) -> void:   # spawn: MexProtocol.EntitySpawn
	entity_id = spawn.entity_id
	es_heroe = heroe
	speed = float(spawn.speed)
	position = Vector2(spawn.x, spawn.y)
	objetivo = position
	_hp_pct = spawn.hp_pct

	_sprite = Sprite2D.new()
	_sprite.texture = TEXTURAS.get(spawn.type_id, TEXTURAS["vex"])
	_sprite.scale = Vector2.ONE * 0.55
	add_child(_sprite)

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


func _process(delta: float) -> void:
	if position.distance_to(objetivo) > 0.5:
		position = position.move_toward(objetivo, speed * delta)
		var rumbo := objetivo - position
		if rumbo.length() > 1.0:
			# proa hacia arriba en el arte -> el angulo se corrige +90 grados
			_sprite.rotation = rumbo.angle() + PI / 2


## Eco autoritativo del server: correccion suave si la deriva es chica, snap si es grande.
func reconcile(x: float, y: float, tx: float, ty: float, nueva_vel: float, teleport: bool) -> void:
	speed = nueva_vel
	objetivo = Vector2(tx, ty)
	var server_pos := Vector2(x, y)
	if teleport or position.distance_to(server_pos) > 220.0:
		position = server_pos
	else:
		position = position.lerp(server_pos, 0.35)


func set_hp_pct(pct: float) -> void:
	_hp_pct = clampf(pct, 0.0, 1.0)
	_hp.size.x = 60 * _hp_pct


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
