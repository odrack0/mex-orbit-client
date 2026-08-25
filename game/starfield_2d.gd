# Polvo estelar en coordenadas de PANTALLA, portado fiel del prototipo:
# - quieta: deriva fija (+8,+4) px logicos/s (el original nunca se detiene)
# - volando: velocidad = 30 x (delta de camara), en contra del avance
# - salto mayor al viewport (cambio de mapa): conserva la velocidad previa
# Variante de color por mapa (el 1-1 usa star_dust_colors_cyan): una fraccion
# de las particulas se tinta.
class_name Starfield2D
extends Node2D

const COUNT := 300
const IDLE_VELOCITY := Vector2(8, 4)
const CAMERA_FACTOR := 30.0
const LOGICAL_WIDTH := 1280.0

var tint := Color(0.4, 0.95, 1.0)   # cian del 1-1
var tint_ratio := 0.35              # fraccion de particulas tintadas

var _parts: Array = []
var _velocity := IDLE_VELOCITY
var _size := Vector2.ZERO
var _view_scale := 1.0
var _prev_camera := Vector2.INF


func resize(viewport: Vector2) -> void:
	if viewport == _size:
		return
	_size = viewport
	_view_scale = maxf(viewport.x / LOGICAL_WIDTH, 0.01)
	if _parts.is_empty() and _size.x > 0.0 and _size.y > 0.0:
		for i in COUNT:
			var depth := float(i) / float(COUNT)
			var gray := (depth * 238.0 + 17.0) / 255.0
			var color := Color(gray, gray, gray)
			if randf() < tint_ratio:
				color = Color(gray * tint.r, gray * tint.g, gray * tint.b)
			_parts.append([
				Vector2(randf() * _size.x, randf() * _size.y),
				depth * 3.0 + 0.5,
				color,
			])


func advance(camera: Vector2, delta: float) -> void:
	if _size.x <= 0.0 or _parts.is_empty():
		return
	if _prev_camera != Vector2.INF \
			and absf(_prev_camera.x - camera.x) <= _size.x \
			and absf(_prev_camera.y - camera.y) <= _size.y:
		_set_speed(CAMERA_FACTOR * (_prev_camera - camera))
	_prev_camera = camera
	var step := _velocity * delta * _view_scale
	for p: Array in _parts:
		var pos: Vector2 = p[0]
		pos += step * (p[1] as float)
		if pos.x < 0.0:
			pos.x += _size.x
		elif pos.x > _size.x:
			pos.x -= _size.x
		if pos.y < 0.0:
			pos.y += _size.y
		elif pos.y > _size.y:
			pos.y -= _size.y
		p[0] = pos
	queue_redraw()


func _set_speed(v: Vector2) -> void:
	_velocity = IDLE_VELOCITY if v == Vector2.ZERO else v


func _draw() -> void:
	var dot := Vector2.ONE * maxf(_view_scale, 1.0)
	for p: Array in _parts:
		draw_rect(Rect2(p[0], dot), p[2])
