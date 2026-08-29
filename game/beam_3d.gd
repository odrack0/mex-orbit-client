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

## Vida del haz de un disparo, la rampa de salida y el fundido (diales F2).
const DURACION_SEC := 0.35
const RAMPA_SEC := 0.10
const FUNDIDO_SEC := 0.10
## Scroll del patrón: segundos por repetición (0.3-0.5 en el original).
const CICLO_SEC := 0.4
## Altura del haz sobre el plano del juego.
const ALTURA := 15.0

var _attacker: EntityNode
var _target: EntityNode
var _canon_local := Vector2.ZERO
var _desde := Vector2.ZERO       # ultimas posiciones conocidas (por si mueren)
var _hasta := Vector2.ZERO
var _largo_patron := 96.0
var _quad: MeshInstance3D
var _mat: ShaderMaterial
var _t := 0.0


static func fire(attacker: EntityNode, target: EntityNode,
		ammo_id: String, skilled: bool) -> Beam3D:
	var d := AssetDefs.ammo(ammo_id)
	var haz: Dictionary = d.get("beam_skilled" if skilled else "beam", {})

	var b := Beam3D.new()
	b._attacker = attacker
	b._target = target
	b._canon_local = attacker.siguiente_canon_local()
	b._largo_patron = maxf(float(haz.get("length", 96)), 8.0)

	var tex: Texture2D = load(haz.get("texture",
		"res://assets/fx/beam-skilled.png" if skilled else "res://assets/fx/beam.png"))
	b._mat = ShaderMaterial.new()
	b._mat.shader = load("res://game/shaders/beam_scroll.gdshader")
	b._mat.set_shader_parameter("patron", tex)
	b._mat.set_shader_parameter("color", AssetDefs.color(haz.get("color", "FA0000")))
	b._mat.set_shader_parameter("ciclo", CICLO_SEC)
	b._mat.set_shader_parameter("intensidad", 0.0)

	b._quad = MeshInstance3D.new()
	var q := QuadMesh.new()
	# 1 unidad de largo con el ORIGEN en el arranque: estirar es escalar en X
	q.size = Vector2(1.0, maxf(float(haz.get("thickness", 1.0)) * 3.0, 3.0))
	q.center_offset = Vector3(0.5, 0.0, 0.0)
	q.material = b._mat
	b._quad.mesh = q
	b._quad.rotation.x = -PI / 2       # tumbado en el plano del juego
	b.add_child(b._quad)

	# el destello del disparo en la boca (pool de luces del mundo, G§7.2)
	Mundo3D.instancia.luz_efecto(b._origen3(), Color("f7c0c0"), 1.2, 200.0, 0.05, 0.15)
	Mundo3D.instancia.add_child(b)
	b._seguir()
	return b


func _origen3() -> Vector3:
	return Vector3(_desde.x, ALTURA, _desde.y)


## Reapunta el haz a donde ESTAN las naves ahora mismo.
func _seguir() -> void:
	if _attacker != null and is_instance_valid(_attacker):
		_desde = _attacker.position \
			+ _canon_local.rotated(deg_to_rad(_attacker.angulo_visual()))
	if _target != null and is_instance_valid(_target):
		_hasta = _target.position
	var delta := _hasta - _desde
	position = Vector3(_desde.x, ALTURA, _desde.y)
	rotation.y = -delta.angle()
	var dist := maxf(delta.length(), 1.0)
	scale = Vector3(dist, 1.0, 1.0)
	_mat.set_shader_parameter("repeticiones", dist / _largo_patron)


func _process(delta: float) -> void:
	_t += delta
	if _t >= DURACION_SEC:
		queue_free()
		return
	_seguir()
	# rampa de salida y fundido al morir, la envolvente del original
	var k := minf(_t / RAMPA_SEC, 1.0)
	var resto := DURACION_SEC - _t
	if resto < FUNDIDO_SEC:
		k = minf(k, resto / FUNDIDO_SEC)
	_mat.set_shader_parameter("intensidad", k)
