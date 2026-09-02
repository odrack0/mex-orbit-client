# Un portal del mapa. Su POSICION es dato del server (map_portal -> EnterMap);
# aqui solo viven sus particularidades de arte, en data/props/portal.json.
#
# El nodo sigue siendo la LOGICA (posicion de juego, rango de salto, senial de
# encendido). Su cuerpo es su MALLA en la escena unica, en todos los niveles de
# calidad — y desde el 1-sep va DE PIE, como el jumpgate del DO 3D: un anillo
# DE CARA A LA CAMARA (su normal es la direccion del rig: tilt base + pan del
# mapa, fija, no un billboard) y CENTRADO en el plano de vuelo, asi que la nave
# se queda dentro del aro, con la mitad de abajo por delante — en el espacio
# no hay suelo que lo apoye. Con el balanceo de +-3 grados
# y el pulso de 5 s del original (G: `<floating rotation 3>`, `<glow
# duration="5">`). El encendido son los 2,1 s que cubren la latencia del
# salto: las luces del aro suben en rampa PARPADEANDO, el CENTRO (el vortice,
# pieza aparte del GLB llamada `centro` — la parte `tools/partir-centro.py` del
# repo de arte) que en reposo NO ESTA puede aparecer creciendo y girando —
# solo con `encendido.vortice` en el JSON; desde el 2-sep va apagado porque
# en vivo no gusto—, y un destello del pool de luces; al final queda ABIERTO
# (luces fijas) y avisa. El aro no gira nunca. La etiqueta del sector vive en la capa
# HUD del mundo, proyectada.
class_name PortalNode
extends Node2D

## Se emite cuando el encendido llega a su final (la senial que el salto
## espera: el mapa se muestra cuando terminan la animacion Y el server).
signal ignition_finished(portal_id: int)

var portal_id := 0
var target_map_code := ""
var is_working := true
var click_radius := 190.0

## A que distancia se puede SALTAR. Tiene que casar con `JumpRange` del server
## (el cliente propone y el server dispone); el radio de click es aparte y mas
## chico a proposito.
const JUMP_RANGE := 600.0

var _data = null                 # MexProtocol.MapPortal, para poder reconstruir
var _body: Node3D               # el cuerpo en la escena unica
var _model: Node3D               # la malla (null si el JSON no trae `modelo`)
var _core: Node3D               # la pieza `centro` del GLB: oculta en reposo, gira al encender
var _mats: Array[BaseMaterial3D] = []          # los del aro (cada pieza tiene su copia)
var _mats_core: Array[BaseMaterial3D] = []
var _tag: Label              # en la capa HUD del mundo, proyectada
var _scale_factor := 1.0
var _size_px := 380.0

# pose de reposo (JSON `orientacion` / `flotar`)
var _pan := 0.0                   # giro EXTRA sobre la cara a camara (0 = de frente)
var _base := Basis()              # la cara a camara, calculada una vez
var _float_deg := 3.0         # el `floating rotation` del original
var _float_cycle := 6.0
var _phase := 0.0

# pulso de reposo (JSON `pulse`): el `<glow duration=5>` del original
var _pulse_min_e := 0.45
var _pulse_max_e := 1.6
var _pulse_speed_e := 0.9
var _pulse_sharpness := 1.4

# encendido (JSON `encendido`)
var _ign_sec := 2.1
var _ign_glow := 4.0
var _ign_spin_dps := 240.0
var _ign_flash := 6.0
var _ign_blink_hz := 6.0       # las luces del aro van y vienen mientras carga
var _ign_blink_min := 0.15     # a cuanto bajan en el "apagado" del parpadeo
var _ign_vortex := false         # si el centro (el vortice) aparece al encender
var _igniting := false
var _open := false
var _anim_t := 0.0
var _spin := 0.0                  # grados acumulados sobre el eje del aro


func setup(p) -> void:      # p: MexProtocol.MapPortal
	_data = p
	portal_id = p.portal_id
	target_map_code = p.target_map_code
	is_working = p.is_working
	position = Vector2(p.x, p.y)
	_build()


## Rehace solo la parte visual al cambiar la calidad en caliente.
func rebuild() -> void:
	_clear()
	_build()


func _clear() -> void:
	if _body != null:
		_body.queue_free()
	if _tag != null:
		_tag.queue_free()
	_body = null
	_model = null
	_core = null
	_mats.clear()
	_mats_core.clear()
	_tag = null
	_igniting = false
	_open = false
	_anim_t = 0.0
	_spin = 0.0


func _exit_tree() -> void:
	_clear()


func _build() -> void:
	var d := AssetDefs.prop("portal")
	click_radius = float(d.get("click_radius", 190))
	_size_px = float(d.get("world_size", 380))

	_body = Node3D.new()
	_body.position = Vector3(position.x, 1.0, position.y)
	Stage3D.instance.add_child(_body)

	var path := str(d.get("modelo", ""))
	if path != "" and ResourceLoader.exists(path):
		var scene: PackedScene = load(path)
		if scene != null:
			_model = scene.instantiate()
			_body.add_child(_model)
			# `world_size` es el DIAMETRO del aro: se escala por la huella, como
			# la estacion (el anillo de pie mide su diametro en X)
			_scale_factor = _size_px / AssetDefs.extent_3d(_model)
			# CENTRADO en el plano de vuelo (no apoyado): la nave se queda dentro
			# del aro, como en el original. La caja del modelo ya viene centrada
			# por el normalizador (pivote al centro).
			_mats = AssetDefs.materials_3d(_model)
			# el vortice: si el GLB viene partido, esa pieza NO ESTA en reposo y
			# aparece girando al encender; con sus materiales aparte, que el
			# aro parpadea y el vortice sube en rampa. Si el GLB es de una
			# pieza, gira el aro entero, que es el respaldo.
			_core = _model.find_child("centro", true, false) as Node3D
			if _core != null:
				for m in _core.find_children("*", "MeshInstance3D", true, false):
					var mat = (m as MeshInstance3D).get_surface_override_material(0)
					if mat is BaseMaterial3D:
						_mats_core.append(mat)
						_mats.erase(mat)
				_core.visible = false

	var orient_def: Dictionary = d.get("orientacion", {})
	_pan = float(orient_def.get("pan", 0.0))
	# de cara a la camara: la normal del aro (Z del modelo) apunta a donde
	# esta la camara del rig con el tilt BASE (sin el acoplamiento del zoom:
	# es una pose, no un billboard) y el pan del mapa, mas el giro extra
	var t := deg_to_rad(Stage3D.TILT)
	var pn := deg_to_rad(Stage3D.instance.pan_deg + _pan)
	var towards := Vector3(sin(t) * sin(pn), -cos(t), sin(t) * cos(pn)).normalized()
	_base = Basis.looking_at(-towards, Vector3.UP)   # -Z mira a -hacia: +Z (la normal) mira a la camara
	var fl: Dictionary = d.get("flotar", {})
	_float_deg = float(fl.get("grados", 3.0))
	_float_cycle = float(fl.get("ciclo", 6.0))
	var pulse_def: Dictionary = d.get("pulse", {})
	_pulse_min_e = float(pulse_def.get("min_intensity", 0.45))
	_pulse_max_e = float(pulse_def.get("max_intensity", 1.6))
	_pulse_speed_e = float(pulse_def.get("speed", 0.9))
	_pulse_sharpness = float(pulse_def.get("sharpness", 1.4))
	var enc: Dictionary = d.get("encendido", {})
	_ign_sec = float(enc.get("segundos", 2.1))
	_ign_glow = float(enc.get("glow", 4.0))
	_ign_spin_dps = float(enc.get("giro_dps", 240.0))
	_ign_flash = float(enc.get("destello", 6.0))
	_ign_blink_hz = float(enc.get("parpadeo_hz", 6.0))
	_ign_blink_min = float(enc.get("parpadeo_min", 0.15))
	_ign_vortex = bool(enc.get("vortice", false))
	_phase = randf() * TAU
	_apply_pose()
	_mount_tag(d)


## La pose del aro: la cara a camara y el balanceo lento del original. El giro
## del encendido va SOLO al centro, sobre su propio eje (Z del modelo: la normal
## del anillo, que queda mirando a la camara — un circulo que rota).
## Se compone entera cada frame — la base lleva tambien la escala, y asignar
## una base nueva la pisaria.
func _apply_pose() -> void:
	if _model == null:
		return
	var t := Time.get_ticks_msec() * 0.001 / _float_cycle * TAU + _phase
	var bal := deg_to_rad(_float_deg)
	var rot := _base \
		* Basis(Vector3.RIGHT, sin(t) * bal) \
		* Basis(Vector3.UP, cos(t * 0.8) * bal)
	if _core != null:
		_core.rotation = Vector3(0.0, 0.0, deg_to_rad(_spin))
	else:
		rot = rot * Basis(Vector3.BACK, deg_to_rad(_spin))
	_model.basis = rot.scaled(Vector3.ONE * _scale_factor)


func _mount_tag(d: Dictionary) -> void:
	# el destino, proyectado bajo el aro: el jugador sabe a donde lleva
	var tag_def: Dictionary = d.get("label", {})
	var txt := "Sector %s" % target_map_code
	if not is_working:
		txt = "Sector %s · inactivo" % target_map_code
	_tag = NTheme.label(txt, NTheme.exo2(), int(tag_def.get("size", 12)),
		AssetDefs.color(tag_def.get("color", "A78BFA"), NTheme.VIOLET) if is_working else NTheme.MUTED)
	_tag.custom_minimum_size = Vector2(180, 0)
	_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_tag.add_theme_constant_override("outline_size", 4)
	if EntityNode.hud_layer != null:
		EntityNode.hud_layer.add_child(_tag)
	else:
		add_child(_tag)


## Lanza el encendido. Devuelve false si no hay nada que lanzar: portal apagado,
## ya encendiendose o ya abierto, o sin malla — ahi el salto ocurre sin ceremonia.
func activate() -> bool:
	if not is_working or _model == null or _igniting or _open:
		return false
	_igniting = true
	_anim_t = 0.0
	# el destello: una luz del pool sobre el aro, que aguanta el encendido
	# entero y se funde sola (solo con luces dinamicas, `luces` >= 1)
	Stage3D.instance.effect_light(Vector3(position.x, _size_px * 0.5, position.y), NTheme.CYAN,
		_ign_flash, _size_px * 1.5, _ign_sec, 0.6)
	return true


## Vuelve al reposo (solo hace falta si el salto se cae).
func rest() -> void:
	_igniting = false
	_open = false
	_anim_t = 0.0
	_spin = 0.0
	if _core != null:
		_core.visible = false


## Para que el autotest pueda AFIRMAR que el encendido llego al final.
func ignition_complete() -> bool:
	return _open


func _process(delta: float) -> void:
	# la etiqueta sigue al portal en pantalla (los portales no se mueven, pero
	# la camara si — y con el tilt-zoom la proyeccion cambia cada frame)
	if _tag != null and Stage3D.instance != null:
		var px := Stage3D.instance.to_screen(position)
		_tag.position = (px + Vector2(-90, 40)).floor()
	if _body != null:
		_body.visible = visible
	if _model == null:
		return

	# reposo: el glow senoidal de 5 s del original, con fase propia
	var wave := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * _pulse_speed_e + portal_id * 1.7)
	var e: float = _pulse_min_e + (_pulse_max_e - _pulse_min_e) * pow(wave, _pulse_sharpness)

	var e_core := 0.0
	if _igniting or _open:
		# encendido: las luces del aro suben en rampa PARPADEANDO, y el vortice
		# aparece creciendo con la rampa mientras acelera hasta su giro pleno;
		# abierto se queda en el pleno (luces fijas) hasta que el salto se resuelva
		var k := clampf(_anim_t / _ign_sec, 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		e = lerpf(e, _ign_glow, k)
		if _igniting:
			var par := 0.5 + 0.5 * sin(_anim_t * _ign_blink_hz * TAU)
			e *= lerpf(_ign_blink_min, 1.0, smoothstep(0.35, 0.65, par))
		_spin = fmod(_spin + lerpf(0.0, _ign_spin_dps, k) * delta, 360.0)
		e_core = lerpf(0.0, _ign_glow, k)
		if _core != null:
			# el vortice solo si el JSON lo pide (2-sep: apagado, no gusto en vivo)
			_core.visible = _ign_vortex
			_core.scale = Vector3.ONE * maxf(k, 0.02)
		if _igniting:
			_anim_t += delta
			if _anim_t >= _ign_sec:
				_igniting = false
				_open = true
				ignition_finished.emit(portal_id)
	elif _core != null:
		_core.visible = false
	if not is_working:
		e *= 0.25          # un portal apagado apenas alumbra
	for mat in _mats:
		mat.emission_energy_multiplier = e
	for mat in _mats_core:
		mat.emission_energy_multiplier = e_core
	_apply_pose()
