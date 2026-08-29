# Un disparo: quad ADITIVO que VIAJA de la boca del cañón al punto donde estaba
# el objetivo, con DURACIÓN fija (no velocidad). F1 del plan-cliente-3d: el haz
# vive tumbado en el plano del juego dentro de la escena única — F2 lo convierte
# en el beam sostenido con UV-scroll del original.
#
# El aspecto sale del JSON de la munición (data/ammo/<code>.json): color, largo,
# grosor y duración, con su variante `beam_skilled` (el disparo potenciado).
class_name Projectile2D
extends Node3D

var _desde := Vector2.ZERO
var _hasta := Vector2.ZERO
var _duracion := 0.15
var _t := 0.0


## Dispara un haz. `desde` es la boca del cañón ya en coordenadas de juego.
## `parent` se ignora desde F1: el cuerpo vive en la escena única.
static func fire(_parent: Node, desde: Vector2, hasta: Vector2,
		ammo_id: String, skilled: bool) -> Projectile2D:
	var d := AssetDefs.ammo(ammo_id)
	var haz: Dictionary = d.get("beam_skilled" if skilled else "beam", {})

	var largo: float = float(haz.get("length", 96))
	# recorte del original: si el blanco está más cerca que el propio haz, no se
	# dibuja; si no, el destino se acorta para no clavarse encima
	var delta := hasta - desde
	if delta.length() < largo:
		return null

	var p := Projectile2D.new()
	p._duracion = maxf(float(haz.get("duration", 0.15)), 0.01)
	p._desde = desde
	p._hasta = hasta - delta.normalized() * largo * 0.5

	var tex: Texture2D = load(haz.get("texture",
		"res://assets/fx/beam-skilled.png" if skilled else "res://assets/fx/beam.png"))
	var grosor: float = float(haz.get("thickness", 1.0))
	var cuerpo := Mundo3D.quad_aditivo(tex, 1.0, false)
	var q := cuerpo.mesh as QuadMesh
	q.size = Vector2(largo, maxf(grosor * 3.0, 3.0))
	(cuerpo.material_override as StandardMaterial3D).albedo_color = \
		AssetDefs.color(haz.get("color", "FA0000"))
	p.add_child(cuerpo)
	# el arte apunta a +X; la guiñada alrededor de Y con el ángulo de pantalla
	# deja el haz sobre la línea de tiro (juego (dx,dy) -> mundo (dx,+dy))
	p.rotation.y = -delta.angle()
	p.position = Vector3(desde.x, 15.0, desde.y)
	Mundo3D.instancia.add_child(p)
	return p


func _process(delta: float) -> void:
	_t += delta
	var k := minf(_t / _duracion, 1.0)
	var pos := _desde.lerp(_hasta, k)
	position = Vector3(pos.x, 15.0, pos.y)
	if k >= 1.0:
		queue_free()
