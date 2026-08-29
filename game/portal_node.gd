# Un portal del mapa. Su POSICION es dato del server (map_portal -> EnterMap);
# aqui solo viven sus particularidades de arte, en data/props/portal.json.
#
# F1 del plan-cliente-3d: el nodo sigue siendo la LOGICA (posicion de juego,
# rango de salto, senial de encendido — nada de eso cambio), y su cuerpo es un
# quad tumbado en la escena unica. La etiqueta del sector vive en la capa HUD
# del mundo, proyectada.
#
# Dos caminos, como los bichos animados:
#   ALTA  -> ATLAS DE ENCENDIDO. Reposa en su primer fotograma y al activarlo
#            reproduce los 2,1 s una sola vez: el hueco donde cabe el salto.
#   MEDIA y BAJA -> aro quieto con su vortice girando y latiendo.
class_name PortalNode
extends Node2D

## Se emite cuando el encendido llega a su ultimo fotograma (la senial que el
## salto espera: el mapa se muestra cuando terminan la animacion Y el server).
signal encendido_terminado(portal_id: int)

var portal_id := 0
var target_map_code := ""
var is_working := true
var click_radius := 190.0

## A que distancia se puede SALTAR. Tiene que casar con `JumpRange` del server
## (el cliente propone y el server dispone); el radio de click es aparte y mas
## chico a proposito.
const RANGO_SALTO := 600.0

var _datos = null                 # MexProtocol.MapPortal, para poder reconstruir
var _cuerpo: Node3D               # el cuerpo en la escena unica
var _aro: Sprite3D                # aro fijo (media y baja)
var _vortice: Sprite3D
var _etiqueta: Label              # en la capa HUD del mundo, proyectada
var _pulse_min := 0.45
var _pulse_max := 1.6
var _pulse_speed := 0.9
var _pulse_sharp := 1.4
var _spin := -0.5

var _anim: Sprite3D               # camino animado (nulo en media y baja)
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
	_construir()


## Rehace solo la parte visual al cambiar la calidad en caliente.
func reconstruir() -> void:
	_limpiar()
	_construir()


func _limpiar() -> void:
	if _cuerpo != null:
		_cuerpo.queue_free()
	if _etiqueta != null:
		_etiqueta.queue_free()
	_cuerpo = null
	_aro = null
	_vortice = null
	_anim = null
	_etiqueta = null
	_anim_total = 0
	_encendiendo = false
	_anim_t = 0.0


func _exit_tree() -> void:
	_limpiar()


func _construir() -> void:
	var d := AssetDefs.prop("portal")
	click_radius = float(d.get("click_radius", 190))
	var tam := float(d.get("world_size", 380))

	_cuerpo = Node3D.new()
	_cuerpo.position = Vector3(position.x, 1.0, position.y)
	Mundo3D.instancia.add_child(_cuerpo)

	# ALTA monta el atlas del encendido; MEDIA y BAJA caen al aro fijo.
	var anim: Dictionary = d.get("frames", {}) if Quality.nivel("collectable") >= 2 else {}
	if not anim.is_empty():
		_montar_encendido(anim, tam)
	else:
		_montar_aro(d, tam)
	_montar_etiqueta(d)


func _montar_encendido(anim: Dictionary, tam: float) -> void:
	var tex: Texture2D = load(anim.get("atlas", "res://assets/world/portal-anim.png"))
	_anim = Mundo3D.sprite_plano(tex, tam, int(anim.get("vframes", 5)))
	_anim.hframes = int(anim.get("hframes", 5))
	_anim.vframes = int(anim.get("vframes", 5))
	_anim_total = int(anim.get("count", _anim.hframes * _anim.vframes))
	_anim_fps = float(anim.get("fps", 12))
	_anim.frame = 0           # reposo: el aro dormido
	_cuerpo.add_child(_anim)


func _montar_aro(d: Dictionary, tam: float) -> void:
	var tex: Texture2D = load(d.get("texture", "res://assets/world/portal.png"))
	_aro = Mundo3D.sprite_plano(tex, tam * float(tex.get_height()) / float(tex.get_width()))
	_cuerpo.add_child(_aro)
	if not d.has("emissive"):
		return
	var tex_v: Texture2D = load(d.emissive)
	_vortice = Mundo3D.sprite_plano(tex_v,
		tam * float(tex_v.get_height()) / float(tex_v.get_width()))
	_vortice.position.y = 1.5
	_cuerpo.add_child(_vortice)
	var pulso: Dictionary = d.get("pulse", {})
	_pulse_min = float(pulso.get("min_intensity", 0.45))
	_pulse_max = float(pulso.get("max_intensity", 1.6))
	_pulse_speed = float(pulso.get("speed", 0.9))
	_pulse_sharp = float(pulso.get("sharpness", 1.4))
	_spin = float(d.get("spin", {}).get("speed", -0.5))


func _montar_etiqueta(d: Dictionary) -> void:
	# el destino, proyectado bajo el aro: el jugador sabe a donde lleva
	var etq: Dictionary = d.get("label", {})
	var texto := "Sector %s" % target_map_code
	if not is_working:
		texto = "Sector %s · inactivo" % target_map_code
	_etiqueta = NTheme.label(texto, NTheme.exo2(), int(etq.get("size", 12)),
		AssetDefs.color(etq.get("color", "A78BFA"), NTheme.VIOLET) if is_working else NTheme.MUTED)
	_etiqueta.custom_minimum_size = Vector2(180, 0)
	_etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_etiqueta.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_etiqueta.add_theme_constant_override("outline_size", 4)
	if EntityNode.capa_hud != null:
		EntityNode.capa_hud.add_child(_etiqueta)
	else:
		add_child(_etiqueta)


## Lanza el encendido. Devuelve false si no hay nada que lanzar: portal apagado,
## ya encendiendose, o calidad sin atlas — ahi el salto ocurre sin ceremonia.
func activar() -> bool:
	if not is_working or _anim == null or _encendiendo:
		return false
	_encendiendo = true
	_anim_t = 0.0
	_anim.frame = 0
	return true


## Vuelve al reposo (solo hace falta si el salto se cae).
func reposo() -> void:
	_encendiendo = false
	_anim_t = 0.0
	if _anim != null:
		_anim.frame = 0


## Para que el autotest pueda AFIRMAR que el encendido llego al final.
func encendido_completo() -> bool:
	return _anim != null and not _encendiendo and _anim.frame == _anim_total - 1


func _process(delta: float) -> void:
	# la etiqueta sigue al portal en pantalla (los portales no se mueven, pero
	# la camara si — y con el tilt-zoom la proyeccion cambia cada frame)
	if _etiqueta != null and Mundo3D.instancia != null:
		var px := Mundo3D.instancia.a_pantalla(position)
		_etiqueta.position = (px + Vector2(-90, 40)).floor()
	if _cuerpo != null:
		_cuerpo.visible = visible

	if _encendiendo:
		_anim_t += delta
		var i := int(_anim_t * _anim_fps)
		if i >= _anim_total - 1:
			# se QUEDA en el ultimo fotograma: el portal abierto del todo
			_anim.frame = _anim_total - 1
			_encendiendo = false
			encendido_terminado.emit(portal_id)
		else:
			_anim.frame = i
		return
	if _vortice == null:
		return
	# el vortice gira dentro del aro quieto (alrededor de su normal, Y)...
	_vortice.rotation.y += _spin * delta
	# ...y late en intensidad
	var onda := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * _pulse_speed + portal_id * 1.7)
	onda = pow(onda, _pulse_sharp)
	var k: float = _pulse_min + (_pulse_max - _pulse_min) * onda
	if not is_working:
		k *= 0.25          # un portal apagado apenas alumbra
	_vortice.modulate = Color(k, k, k, 1.0)
