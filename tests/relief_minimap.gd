extends Control

## El MINIMAPA del banco del relieve (prueba de concepto). Sale del mismo dato que
## el terreno — `Relief3D.minimap_image()`, un pixel por vertice de la rejilla de
## alturas — y lleva NIEBLA: lo que no has recorrido se ve apagado. Es la mitad
## barata de "explorar": el mapa se va encendiendo y lo que falta se nota.
##
## Marca la nave (con su rumbo), hacia donde mira la camara, los bichos que ya
## quedaron a la vista y los nombres de las zonas descubiertas.

const WIDTH := 520.0
const REVEAL := 1150.0             # radio que se destapa alrededor de la nave, en unidades
const MASK_W := 300                # ancho de la mascara de niebla, en pixeles
const REFRESH := 0.2

const FOG_SHADER := "
shader_type canvas_item;
uniform sampler2D mask : filter_linear;
uniform float dim = 0.38;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float m = texture(mask, UV).r;
	COLOR = vec4(c.rgb * mix(dim, 1.0, m), c.a * mix(0.6, 1.0, m));
}
"

var bench: Node
var combat: Node
var _world := Rect2()
var _mask: Image
var _mask_tex: ImageTexture
var _map: TextureRect
var _over: Control
var _wait := 0.0
var _zones: Array = []


func setup(relief: Relief3D, zones: Array) -> bool:
	var img := relief.minimap_image(int(WIDTH))
	_world = relief.world_rect()
	if img == null or _world.size.x <= 0.0:
		visible = false
		return false
	_zones = zones
	size = Vector2(WIDTH, WIDTH * _world.size.y / _world.size.x)
	var back := ColorRect.new()
	back.color = Color(0.02, 0.03, 0.05, 0.72)
	back.size = size
	add_child(back)

	_mask = Image.create(MASK_W, int(MASK_W * _world.size.y / _world.size.x), false, Image.FORMAT_L8)
	_mask.fill(Color.BLACK)
	_mask_tex = ImageTexture.create_from_image(_mask)
	var shader := Shader.new()
	shader.code = FOG_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("mask", _mask_tex)
	_map = TextureRect.new()
	_map.texture = ImageTexture.create_from_image(img)
	_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map.stretch_mode = TextureRect.STRETCH_SCALE
	_map.size = size
	_map.material = mat
	add_child(_map)

	_over = Control.new()
	_over.size = size
	_over.draw.connect(_draw_over)
	add_child(_over)
	return true


## Fraccion del mapa ya destapada (0..1): cuanto mundo llevas visto.
func explored() -> float:
	if _mask == null:
		return 0.0
	var total := 0.0
	for y in range(0, _mask.get_height(), 3):
		for x in range(0, _mask.get_width(), 3):
			total += _mask.get_pixel(x, y).r
	return total / (ceil(_mask.get_height() / 3.0) * ceil(_mask.get_width() / 3.0))


func _process(delta: float) -> void:
	if not visible or _mask == null:
		return
	var view := get_viewport().get_visible_rect().size
	position = Vector2(view.x - size.x - 14.0, view.y - size.y - 14.0)   # abajo a la derecha
	_wait -= delta
	if _wait <= 0.0:
		_wait = REFRESH
		_reveal(bench._pos)
	_over.queue_redraw()


func _reveal(at: Vector2) -> void:
	var px_per_u := float(_mask.get_width()) / _world.size.x
	var c := (at - _world.position) * px_per_u
	var r := REVEAL * px_per_u
	var changed := false
	for y in range(maxi(int(c.y - r), 0), mini(int(c.y + r) + 1, _mask.get_height())):
		for x in range(maxi(int(c.x - r), 0), mini(int(c.x + r) + 1, _mask.get_width())):
			var v := 1.0 - smoothstep(r * 0.7, r, Vector2(x, y).distance_to(c))
			if v > _mask.get_pixel(x, y).r + 0.01:
				_mask.set_pixel(x, y, Color(v, v, v))
				changed = true
	if changed:
		_mask_tex.update(_mask)


func _to_map(p: Vector2) -> Vector2:
	return (p - _world.position) / _world.size * size


func _seen(p: Vector2) -> bool:
	var q := (p - _world.position) / _world.size * Vector2(_mask.get_width(), _mask.get_height())
	if q.x < 0.0 or q.y < 0.0 or q.x >= _mask.get_width() or q.y >= _mask.get_height():
		return false
	return _mask.get_pixel(int(q.x), int(q.y)).r > 0.5


func _draw_over() -> void:
	var font := ThemeDB.fallback_font
	for z: Dictionary in _zones:
		if bench._discovered.has(str(z.name)):
			var at := _to_map(Vector2(float(z.x), float(z.y)))
			var text := str(z.name)
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			_over.draw_string(font, at + Vector2(-w * 0.5, 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
				Color(1, 1, 1, 0.8))
	if combat != null:
		for i in combat.npcs.size():
			var n = combat.npcs[i]
			if not n.alive() or not (_seen(n.pos) or n.aggro):
				continue
			var at := _to_map(n.pos)
			if not Rect2(Vector2.ZERO, size).has_point(at):
				continue
			_over.draw_circle(at, 4.0 if n.elite else 2.6,
				Color(1.0, 0.7, 0.2) if n.elite else (Color(1.0, 0.3, 0.25) if n.aggressive else Color(0.9, 0.8, 0.5)))
			if i == combat.target:
				_over.draw_arc(at, 7.0, 0.0, TAU, 20, Color(1.0, 0.3, 0.25), 1.5)
	# la nave: un triangulo que apunta a su rumbo, y la cunia de lo que mira la camara
	var ship := _to_map(bench._pos)
	var facing := Vector2.from_angle(bench._face)
	if bench._chase:
		var look := Vector2(sin(bench._cam_yaw), cos(bench._cam_yaw))
		var half := deg_to_rad(bench._fov * 0.5 * 1.6)
		_over.draw_line(ship, ship + look.rotated(-half) * 46.0, Color(1, 1, 1, 0.35), 1.0)
		_over.draw_line(ship, ship + look.rotated(half) * 46.0, Color(1, 1, 1, 0.35), 1.0)
	var side := facing.orthogonal() * 4.5
	_over.draw_colored_polygon(PackedVector2Array([ship + facing * 9.0, ship - facing * 5.0 + side,
		ship - facing * 5.0 - side]), Color(0.4, 0.95, 1.0))
	_over.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.35), false, 1.0)
