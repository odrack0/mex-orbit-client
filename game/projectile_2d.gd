# Un disparo: sprite que VIAJA de la boca del cañón al punto donde estaba el
# objetivo, con DURACIÓN fija (no velocidad) — el modelo del prototipo.
#
# El aspecto sale del JSON de la munición (data/ammo/<code>.json): color, largo,
# grosor y duración, con su variante `beam_skilled` (el disparo potenciado por
# el perfil de piloto: más grueso y brillante, como el skillLaser del original).
class_name Projectile2D
extends Sprite2D

var _desde := Vector2.ZERO
var _hasta := Vector2.ZERO
var _duracion := 0.15
var _t := 0.0


## Dispara un haz. `desde` es la boca del cañón ya en coordenadas de mundo.
static func fire(parent: Node, desde: Vector2, hasta: Vector2,
		ammo_id: String, skilled: bool) -> Projectile2D:
	var d := AssetDefs.ammo(ammo_id)
	var haz: Dictionary = d.get("beam_skilled" if skilled else "beam", {})

	var p := Projectile2D.new()
	p.texture = load(haz.get("texture",
		"res://assets/fx/beam-skilled.png" if skilled else "res://assets/fx/beam.png"))
	p.modulate = AssetDefs.color(haz.get("color", "FA0000"))
	p.material = _material_add()
	p.z_index = 4
	p._duracion = maxf(float(haz.get("duration", 0.15)), 0.01)

	var largo: float = float(haz.get("length", 96))
	var grosor: float = float(haz.get("thickness", 1.0))
	var ancho_tex := float(p.texture.get_width())
	p.scale = Vector2(largo / ancho_tex, grosor)

	# recorte del prototipo: si el blanco está más cerca que el propio haz, no
	# se dibuja; si no, el destino se acorta ese largo para no clavarse encima
	var delta := hasta - desde
	if delta.length() < largo:
		p.queue_free()
		return null
	p._desde = desde
	p._hasta = hasta - delta.normalized() * largo * 0.5
	p.position = desde
	p.rotation = delta.angle()      # el arte apunta a +X
	parent.add_child(p)
	return p


static func _material_add() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


func _process(delta: float) -> void:
	_t += delta
	var k := minf(_t / _duracion, 1.0)
	position = _desde.lerp(_hasta, k)
	if k >= 1.0:
		queue_free()
