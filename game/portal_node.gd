# Un portal del mapa. Su POSICION es dato del server (map_portal -> EnterMap);
# aqui solo viven sus particularidades de arte, en data/props/portal.json.
#
# Dos caminos, como los bichos animados:
#
#   ALTA  -> ATLAS DE ENCENDIDO. El portal REPOSA en su primer fotograma, que es
#            el aro dormido, y al activarlo reproduce los 2,1 s de encendido una
#            sola vez. No es un bucle: nadie vuelve al principio. Esos dos
#            segundos son los que tapan el viaje al server mientras resuelve el
#            salto de sector, asi que la animacion no es adorno — es el hueco
#            donde cabe la latencia.
#   MEDIA y BAJA -> el camino de siempre: aro quieto y capa emisiva que gira y
#            late. El portal se ve encendido desde el principio y el salto pasa
#            sin ceremonia, que es exactamente lo que se espera de calidad baja.
class_name PortalNode
extends Node2D

## Se emite cuando el encendido llega a su ultimo fotograma. Es la senial que
## E3 espera para cambiar de mapa: la animacion corre mientras el server
## responde, y el salto se muestra cuando AMBOS han terminado.
signal encendido_terminado(portal_id: int)

var portal_id := 0
var target_map_code := ""
var is_working := true
var click_radius := 190.0

var _datos = null                 # MexProtocol.MapPortal, para poder reconstruir
var _vortice: Sprite2D
var _pulse_min := 0.45
var _pulse_max := 1.6
var _pulse_speed := 0.9
var _pulse_sharp := 1.4
var _spin := -0.5

var _anim: Sprite2D               # camino animado (nulo en media y baja)
var _anim_total := 0
var _anim_fps := 12.0
var _encendiendo := false
var _anim_t := 0.0


func setup(p) -> void:      # p: MexProtocol.MapPortal
	_datos = p
	portal_id = p.portal_id
	target_map_code = p.target_map_code
	is_working = p.is_working
	position = Vector2(p.x, p.y)
	z_index = -1              # mobiliario del mapa: por debajo de las naves
	_construir()


## Rehace solo la parte visual al cambiar la calidad en caliente. El estado del
## portal —cual es, a donde lleva, si funciona— no depende del nivel.
func reconstruir() -> void:
	for hijo in get_children():
		hijo.queue_free()
	_vortice = null
	_anim = null
	_anim_total = 0
	_encendiendo = false
	_anim_t = 0.0
	_construir()


func _construir() -> void:
	var d := AssetDefs.prop("portal")
	click_radius = float(d.get("click_radius", 190))
	var tam := float(d.get("world_size", 380))

	# ALTA monta el atlas del encendido; MEDIA y BAJA caen al aro fijo, que por
	# eso nunca se borro. Misma regla que los bichos, misma clave que las cajas.
	var anim: Dictionary = d.get("frames", {}) if Quality.nivel("collectable") >= 2 else {}
	if not anim.is_empty():
		_montar_encendido(anim, tam)
	else:
		_montar_aro(d, tam)
	_montar_etiqueta(d, tam)


func _montar_encendido(anim: Dictionary, tam: float) -> void:
	_anim = Sprite2D.new()
	_anim.texture = load(anim.get("atlas", "res://assets/world/portal-anim.png"))
	_anim.hframes = int(anim.get("hframes", 5))
	_anim.vframes = int(anim.get("vframes", 5))
	_anim_total = int(anim.get("count", _anim.hframes * _anim.vframes))
	_anim_fps = float(anim.get("fps", 12))
	_anim.frame = 0           # reposo: el aro dormido
	# el tamanio se calcula sobre el alto del FOTOGRAMA, no el de la textura
	# entera; olvidarlo hace al portal cinco veces mas pequenio
	var lado := float(_anim.texture.get_height()) / maxf(float(_anim.vframes), 1.0)
	_anim.scale = Vector2.ONE * (tam / lado)
	add_child(_anim)


func _montar_aro(d: Dictionary, tam: float) -> void:
	var aro := Sprite2D.new()
	aro.texture = load(d.get("texture", "res://assets/world/portal.png"))
	# tamaño en unidades de MUNDO segun el JSON, sea cual sea la resolucion del render
	var lado := float(aro.texture.get_width())
	aro.scale = Vector2.ONE * (tam / lado)
	add_child(aro)

	if not d.has("emissive"):
		return
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


func _montar_etiqueta(d: Dictionary, tam: float) -> void:
	# el destino, debajo del aro: el jugador sabe a donde lleva antes de volar
	var etq: Dictionary = d.get("label", {})
	var texto := "Sector %s" % target_map_code
	if not is_working:
		texto = "Sector %s · inactivo" % target_map_code
	var nombre := NTheme.label(texto, NTheme.exo2(), int(etq.get("size", 12)),
		AssetDefs.color(etq.get("color", "A78BFA"), NTheme.VIOLET) if is_working else NTheme.MUTED)
	nombre.position = Vector2(-90, tam * 0.5 + float(etq.get("offset_y", 26)))
	nombre.custom_minimum_size = Vector2(180, 0)
	nombre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nombre.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	nombre.add_theme_constant_override("outline_size", 4)
	add_child(nombre)


## Lanza el encendido. Devuelve false si no hay nada que lanzar: portal apagado,
## ya encendiendose, o calidad sin atlas — ahi el salto ocurre sin ceremonia y
## quien llama debe seguir adelante igual, no quedarse esperando la senial.
func activar() -> bool:
	if not is_working or _anim == null or _encendiendo:
		return false
	_encendiendo = true
	_anim_t = 0.0
	_anim.frame = 0
	return true


## Vuelve al reposo. Solo hace falta si el salto se cae: cuando sale bien, el
## mapa cambia y este nodo desaparece con el.
func reposo() -> void:
	_encendiendo = false
	_anim_t = 0.0
	if _anim != null:
		_anim.frame = 0


## Para que el autotest pueda AFIRMAR que el encendido llego al final, en vez de
## limitarse a sacar una foto y darla por buena.
func encendido_completo() -> bool:
	return _anim != null and not _encendiendo and _anim.frame == _anim_total - 1


func _process(delta: float) -> void:
	if _encendiendo:
		_anim_t += delta
		var i := int(_anim_t * _anim_fps)
		if i >= _anim_total - 1:
			# se QUEDA en el ultimo fotograma, con el portal abierto del todo:
			# es el estado en el que el jugador lo deja al saltar
			_anim.frame = _anim_total - 1
			_encendiendo = false
			encendido_terminado.emit(portal_id)
		else:
			_anim.frame = i
		return
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
