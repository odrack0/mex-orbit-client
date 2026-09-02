# Un portal del mapa. Su POSICION es dato del server (map_portal -> EnterMap);
# aqui solo viven sus particularidades de arte, en data/props/portal.json.
#
# El nodo sigue siendo la LOGICA (posicion de juego, rango de salto, senial de
# encendido). Su cuerpo es su MALLA en la escena unica, en todos los niveles de
# calidad — y desde el 1-sep va DE PIE, como el jumpgate del DO 3D: un anillo
# vertical a tres cuartos, apoyado en el plano, con el balanceo de +-3 grados
# y el pulso de 5 s del original (G: `<floating rotation 3>`, `<glow
# duration="5">`). El encendido son los 2,1 s que cubren la latencia del
# salto: las luces suben en rampa, el aro gira sobre su eje (una sola pieza:
# girar el anillo entero se lee como que gira el centro) y un destello del pool
# de luces; al final queda ABIERTO y avisa. La etiqueta del sector vive en la
# capa HUD del mundo, proyectada.
class_name PortalNode
extends Node2D

## Se emite cuando el encendido llega a su final (la senial que el salto
## espera: el mapa se muestra cuando terminan la animacion Y el server).
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
var _modelo: Node3D               # la malla (null si el JSON no trae `modelo`)
var _mats: Array[BaseMaterial3D] = []
var _etiqueta: Label              # en la capa HUD del mundo, proyectada
var _escala := 1.0
var _tam := 380.0

# pose de reposo (JSON `orientacion` / `flotar`)
var _pan := 35.0                  # giro en el plano: tres cuartos, como en la captura del DO
var _tilt := 0.0
var _flotar_grados := 3.0         # el `floating rotation` del original
var _flotar_ciclo := 6.0
var _fase := 0.0

# pulso de reposo (JSON `pulse`): el `<glow duration=5>` del original
var _pulso_min := 0.45
var _pulso_max := 1.6
var _pulso_vel := 0.9
var _pulso_dureza := 1.4

# encendido (JSON `encendido`)
var _enc_seg := 2.1
var _enc_glow := 4.0
var _enc_giro_dps := 240.0
var _enc_destello := 6.0
var _encendiendo := false
var _abierto := false
var _anim_t := 0.0
var _giro := 0.0                  # grados acumulados sobre el eje del aro


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
	_modelo = null
	_mats.clear()
	_etiqueta = null
	_encendiendo = false
	_abierto = false
	_anim_t = 0.0
	_giro = 0.0


func _exit_tree() -> void:
	_limpiar()


func _construir() -> void:
	var d := AssetDefs.prop("portal")
	click_radius = float(d.get("click_radius", 190))
	_tam = float(d.get("world_size", 380))

	_cuerpo = Node3D.new()
	_cuerpo.position = Vector3(position.x, 1.0, position.y)
	Mundo3D.instancia.add_child(_cuerpo)

	var ruta := str(d.get("modelo", ""))
	if ruta != "" and ResourceLoader.exists(ruta):
		var escena: PackedScene = load(ruta)
		if escena != null:
			_modelo = escena.instantiate()
			_cuerpo.add_child(_modelo)
			# `world_size` es el DIAMETRO del aro: se escala por la huella, como
			# la estacion (el anillo de pie mide su diametro en X)
			_escala = _tam / AssetDefs.extension_3d(_modelo)
			# apoyado en el plano: la base del aro a la altura del cuerpo. El
			# giro de pose es alrededor de Y y no cambia la altura de la caja.
			var caja := AssetDefs.caja_3d(_modelo)
			_modelo.position.y = -caja.position.y * _escala
			_mats = AssetDefs.materiales_3d(_modelo)

	var ori: Dictionary = d.get("orientacion", {})
	_pan = float(ori.get("pan", 35.0))
	_tilt = float(ori.get("tilt", 0.0))
	var fl: Dictionary = d.get("flotar", {})
	_flotar_grados = float(fl.get("grados", 3.0))
	_flotar_ciclo = float(fl.get("ciclo", 6.0))
	var pul: Dictionary = d.get("pulse", {})
	_pulso_min = float(pul.get("min_intensity", 0.45))
	_pulso_max = float(pul.get("max_intensity", 1.6))
	_pulso_vel = float(pul.get("speed", 0.9))
	_pulso_dureza = float(pul.get("sharpness", 1.4))
	var enc: Dictionary = d.get("encendido", {})
	_enc_seg = float(enc.get("segundos", 2.1))
	_enc_glow = float(enc.get("glow", 4.0))
	_enc_giro_dps = float(enc.get("giro_dps", 240.0))
	_enc_destello = float(enc.get("destello", 6.0))
	_fase = randf() * TAU
	_aplicar_pose()
	_montar_etiqueta(d)


## La pose del aro: giro de tres cuartos, inclinacion, el balanceo lento del
## original y el giro sobre su propio eje (Z del modelo: la normal del anillo).
## Se compone entera cada frame — la base lleva tambien la escala, y asignar
## una base nueva la pisaria.
func _aplicar_pose() -> void:
	if _modelo == null:
		return
	var t := Time.get_ticks_msec() * 0.001 / _flotar_ciclo * TAU + _fase
	var bal := deg_to_rad(_flotar_grados)
	var rot := Basis(Vector3.UP, deg_to_rad(_pan)) \
		* Basis(Vector3.RIGHT, deg_to_rad(_tilt) + sin(t) * bal) \
		* Basis(Vector3.UP, cos(t * 0.8) * bal) \
		* Basis(Vector3.BACK, deg_to_rad(_giro))
	_modelo.basis = rot.scaled(Vector3.ONE * _escala)


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
## ya encendiendose o ya abierto, o sin malla — ahi el salto ocurre sin ceremonia.
func activar() -> bool:
	if not is_working or _modelo == null or _encendiendo or _abierto:
		return false
	_encendiendo = true
	_anim_t = 0.0
	# el destello: una luz del pool sobre el aro, que aguanta el encendido
	# entero y se funde sola (solo con luces dinamicas, `luces` >= 1)
	Mundo3D.instancia.luz_efecto(Vector3(position.x, _tam * 0.5, position.y), NTheme.CYAN,
		_enc_destello, _tam * 1.5, _enc_seg, 0.6)
	return true


## Vuelve al reposo (solo hace falta si el salto se cae).
func reposo() -> void:
	_encendiendo = false
	_abierto = false
	_anim_t = 0.0
	_giro = 0.0


## Para que el autotest pueda AFIRMAR que el encendido llego al final.
func encendido_completo() -> bool:
	return _abierto


func _process(delta: float) -> void:
	# la etiqueta sigue al portal en pantalla (los portales no se mueven, pero
	# la camara si — y con el tilt-zoom la proyeccion cambia cada frame)
	if _etiqueta != null and Mundo3D.instancia != null:
		var px := Mundo3D.instancia.a_pantalla(position)
		_etiqueta.position = (px + Vector2(-90, 40)).floor()
	if _cuerpo != null:
		_cuerpo.visible = visible
	if _modelo == null:
		return

	# reposo: el glow senoidal de 5 s del original, con fase propia
	var onda := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * _pulso_vel + portal_id * 1.7)
	var e: float = _pulso_min + (_pulso_max - _pulso_min) * pow(onda, _pulso_dureza)

	if _encendiendo or _abierto:
		# encendido: luces en rampa y el aro acelerando hasta su giro pleno;
		# abierto se queda en el pleno hasta que el salto se resuelva
		var k := clampf(_anim_t / _enc_seg, 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		e = lerpf(e, _enc_glow, k)
		_giro = fmod(_giro + lerpf(0.0, _enc_giro_dps, k) * delta, 360.0)
		if _encendiendo:
			_anim_t += delta
			if _anim_t >= _enc_seg:
				_encendiendo = false
				_abierto = true
				encendido_terminado.emit(portal_id)
	if not is_working:
		e *= 0.25          # un portal apagado apenas alumbra
	for mat in _mats:
		mat.emission_energy_multiplier = e
	_aplicar_pose()
