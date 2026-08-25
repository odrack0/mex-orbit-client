# Un portal del mapa: aro quieto, vortice que gira y late, y la etiqueta del
# sector destino debajo. Su POSICION es dato del server (map_portal -> EnterMap);
# aqui solo viven sus particularidades de arte, en data/props/portal.json.
class_name PortalNode
extends Node2D

var portal_id := 0
var target_map_code := ""
var is_working := true
var click_radius := 190.0

var _vortice: Sprite2D
var _pulse_min := 0.45
var _pulse_max := 1.6
var _pulse_speed := 0.9
var _pulse_sharp := 1.4
var _spin := -0.5


func setup(p) -> void:      # p: MexProtocol.MapPortal
	portal_id = p.portal_id
	target_map_code = p.target_map_code
	is_working = p.is_working
	position = Vector2(p.x, p.y)
	z_index = -1              # mobiliario del mapa: por debajo de las naves

	var d := AssetDefs.prop("portal")
	click_radius = float(d.get("click_radius", 190))

	var aro := Sprite2D.new()
	aro.texture = load(d.get("texture", "res://assets/world/portal.png"))
	# tamaño en unidades de MUNDO segun el JSON, sea cual sea la resolucion del render
	var lado := float(aro.texture.get_width())
	aro.scale = Vector2.ONE * (float(d.get("world_size", 380)) / lado)
	add_child(aro)

	if d.has("emissive"):
		_vortice = Sprite2D.new()
		_vortice.texture = load(d.emissive)
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_vortice.material = mat
		aro.add_child(_vortice)
		var pulso: Dictionary = d.get("pulse", {})
		_pulse_min = float(pulso.get("min_intensity", 0.45))
		_pulse_max = float(pulso.get("max_intensity", 1.6))
		_pulse_speed = float(pulso.get("speed", 0.9))
		_pulse_sharp = float(pulso.get("sharpness", 1.4))
		_spin = float(d.get("spin", {}).get("speed", -0.5))

	# el destino, debajo del aro: el jugador sabe a donde lleva antes de volar
	var etq: Dictionary = d.get("label", {})
	var texto := "Sector %s" % target_map_code
	if not is_working:
		texto = "Sector %s · inactivo" % target_map_code
	var nombre := NTheme.label(texto, NTheme.exo2(), int(etq.get("size", 12)),
		AssetDefs.color(etq.get("color", "A78BFA"), NTheme.VIOLET) if is_working else NTheme.MUTED)
	nombre.position = Vector2(-90, float(d.get("world_size", 380)) * 0.5 + float(etq.get("offset_y", 26)))
	nombre.custom_minimum_size = Vector2(180, 0)
	nombre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nombre.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	nombre.add_theme_constant_override("outline_size", 4)
	add_child(nombre)


func _process(delta: float) -> void:
	if _vortice == null:
		return
	# el vortice gira dentro del aro quieto...
	_vortice.rotation += _spin * delta
	# ...y late en INTENSIDAD del blend aditivo (por encima de 1 sobreexpone y el
	# nucleo se pone blanco, que es lo que hace visible el pulso)
	var onda := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * _pulse_speed + portal_id * 1.7)
	onda = pow(onda, _pulse_sharp)
	var k: float = _pulse_min + (_pulse_max - _pulse_min) * onda
	if not is_working:
		k *= 0.25          # un portal apagado apenas alumbra
	_vortice.self_modulate = Color(k, k, k, 1.0)
