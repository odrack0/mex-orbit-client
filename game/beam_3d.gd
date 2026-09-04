# El disparo laser como HAZ del cliente 3D original (G§9.4, F2 del plan): un
# quad tumbado que se ESTIRA de la boca del cañón al blanco, con el patrón
# fluyendo por UV-scroll, rampa de salida y fundido al morir. Sigue VIVO a las
# dos naves mientras dura — si el atacante vira con banking, el haz nace de la
# boca real, porque la boca gira con el cuerpo.
#
# El aspecto sale del JSON de la munición (data/ammo/<code>.json): color, largo
# del patrón, grosor y su variante `beam_skilled`. El proyectil que viajaba
# (modelo del prototipo 2D) murió aquí.
class_name Beam3D
extends Node3D

## Diales del haz: data/config/beam.json (nada calibrable vive en el codigo).
static var CFG: Dictionary = AssetDefs.config("beam")
## Vida del haz de un disparo, la rampa de salida y el fundido (diales F2).
static var DURATION_SEC: float = AssetDefs.num(CFG, "duration_sec", 0.35)
static var RAMP_SEC: float = AssetDefs.num(CFG, "ramp_sec", 0.10)
static var FADE_SEC: float = AssetDefs.num(CFG, "fade_sec", 0.10)
## Scroll del patrón: segundos por repetición (0.3-0.5 en el original).
static var CYCLE_SEC: float = AssetDefs.num(CFG, "cycle_sec", 0.4)
## Altura del haz sobre el plano del juego.
static var HEIGHT: float = AssetDefs.num(CFG, "height", 15.0)
static var SHADER_PATH: String = str(CFG.get("shader_path", "res://game/shaders/beam_scroll.gdshader"))
## Grosor del quad: unidades de mundo por unidad de `thickness` de la municion,
## y el grosor minimo; largo minimo del patron.
static var THICKNESS_SCALE: float = AssetDefs.num(CFG, "thickness_scale", 3.0)
static var MIN_THICKNESS: float = AssetDefs.num(CFG, "min_thickness", 3.0)
static var MIN_PATTERN_LENGTH: float = AssetDefs.num(CFG, "min_pattern_length", 8.0)
## Defaults cuando `beam`/`beam_skilled` de la municion no trae la clave.
static var DEFAULTS: Dictionary = CFG.get("defaults", {})
## El destello del disparo en la boca (luz del pool del mundo).
static var FLASH: Dictionary = CFG.get("flash", {})
static var FLASH_COLOR: Color = AssetDefs.color(FLASH.get("color", ""), Color("f7c0c0"))
static var FLASH_ENERGY: float = AssetDefs.num(FLASH, "energy", 1.2)
static var FLASH_RANGE: float = AssetDefs.num(FLASH, "range", 200.0)
static var FLASH_HOLD_SEC: float = AssetDefs.num(FLASH, "hold_sec", 0.05)
static var FLASH_FADE_SEC: float = AssetDefs.num(FLASH, "fade_sec", 0.15)

var _attacker: EntityNode
var _target: EntityNode
var _local_cannon := Vector2.ZERO
var _since := Vector2.ZERO       # ultimas posiciones conocidas (por si mueren)
var _until := Vector2.ZERO
var _alt_since := 0.0            # alturas de vuelo de atacante y blanco
var _alt_until := 0.0
var _pattern_length: float = AssetDefs.num(DEFAULTS, "length", 96.0)
var _quad: MeshInstance3D
var _mat: ShaderMaterial
var _t := 0.0


static func fire(attacker: EntityNode, target: EntityNode,
		ammo_id: String, skilled: bool) -> Beam3D:
	var d := AssetDefs.ammo(ammo_id)
	var beam: Dictionary = d.get("beam_skilled" if skilled else "beam", {})

	var b := Beam3D.new()
	b._attacker = attacker
	b._target = target
	b._local_cannon = attacker.next_local_cannon()
	b._pattern_length = maxf(AssetDefs.num(beam, "length", AssetDefs.num(DEFAULTS, "length", 96.0)),
		MIN_PATTERN_LENGTH)

	var tex: Texture2D = load(beam.get("texture",
		str(DEFAULTS.get("texture_skilled_path" if skilled else "texture_path",
			"res://assets/fx/beam-skilled.png" if skilled else "res://assets/fx/beam.png"))))
	b._mat = ShaderMaterial.new()
	b._mat.shader = load(SHADER_PATH)
	b._mat.set_shader_parameter("patron", tex)
	b._mat.set_shader_parameter("color",
		AssetDefs.color(beam.get("color", DEFAULTS.get("color", "FA0000"))))
	b._mat.set_shader_parameter("cycle", CYCLE_SEC)
	b._mat.set_shader_parameter("intensidad", 0.0)

	b._quad = MeshInstance3D.new()
	var q := QuadMesh.new()
	# 1 unidad de largo con el ORIGEN en el arranque: estirar es escalar en X
	q.size = Vector2(1.0, maxf(AssetDefs.num(beam, "thickness",
		AssetDefs.num(DEFAULTS, "thickness", 1.0)) * THICKNESS_SCALE, MIN_THICKNESS))
	q.center_offset = Vector3(0.5, 0.0, 0.0)
	q.material = b._mat
	b._quad.mesh = q
	b._quad.rotation.x = -PI / 2       # tumbado en el plano del juego
	b.add_child(b._quad)

	# el destello del disparo en la boca (pool de luces del mundo, G§7.2)
	Stage3D.instance.effect_light(b._origin3(), FLASH_COLOR, FLASH_ENERGY, FLASH_RANGE,
		FLASH_HOLD_SEC, FLASH_FADE_SEC)
	Stage3D.instance.add_child(b)
	b._follow()
	return b


func _origin3() -> Vector3:
	return Vector3(_since.x, HEIGHT + _alt_since, _since.y)


## Reapunta el haz a donde ESTAN las naves ahora mismo.
func _follow() -> void:
	if _attacker != null and is_instance_valid(_attacker):
		_since = _attacker.position \
			+ _local_cannon.rotated(deg_to_rad(_attacker.visual_angle()))
		_alt_since = _attacker.altitude
	if _target != null and is_instance_valid(_target):
		_until = _target.position
		_alt_until = _target.altitude
	# el haz une las dos naves A SU ALTURA (3-sep): el eje X del nodo va del
	# canion al blanco en 3D, con el quad tumbado sobre la horizontal
	# perpendicular al haz; con las dos alturas iguales es el giro plano de antes
	var delta := Vector3(_until.x - _since.x, _alt_until - _alt_since, _until.y - _since.y)
	var dist := maxf(delta.length(), 1.0)
	var x_axis := delta / dist
	var z_axis := x_axis.cross(Vector3.UP)
	if z_axis.length_squared() < 0.000001:
		z_axis = Vector3.FORWARD
	z_axis = z_axis.normalized()
	transform = Transform3D(Basis(x_axis * dist, z_axis.cross(x_axis), z_axis),
		Vector3(_since.x, HEIGHT + _alt_since, _since.y))
	_mat.set_shader_parameter("repeticiones", dist / _pattern_length)


func _process(delta: float) -> void:
	_t += delta
	if _t >= DURATION_SEC:
		queue_free()
		return
	_follow()
	# rampa de salida y fundido al morir, la envolvente del original
	var k := minf(_t / RAMP_SEC, 1.0)
	var rest_of := DURATION_SEC - _t
	if rest_of < FADE_SEC:
		k = minf(k, rest_of / FADE_SEC)
	_mat.set_shader_parameter("intensidad", k)
