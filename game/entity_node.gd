# Una entidad en pantalla: sprite orientado a su rumbo + nombre + barra de vida.
# Sus PARTICULARIDADES (textura, tamaño, anclajes de toberas, capa emisiva)
# salen de su JSON en data/ — nada hardcodeado por asset.
# Se mueve por interpolacion local y se reconcilia contra los ecos del server.
class_name EntityNode
extends Node2D

# Giro heredado del prototipo: tween de 0.1 s por el camino corto, orientacion
# cuantizada a 32 pasos de 11.25 grados (el look de los 32 frames del original)
# y zona muerta para no vibrar persiguiendo el cursor.
const TURN_TIME := 0.1
const TURN_STEPS := 32
const DEAD_ZONE := 2.0

## Giro al EMPRENDER VUELO. Los bichos tienen su propio ritmo (el peso de su
## especie) para el giro perezoso en reposo, pero para encarar un destino todos
## son briosos: si no, arrancan a toda velocidad mientras siguen girando y se
## desplazan de lado, como un cangrejo. La proa va delante SIEMPRE.
const TURN_FLIGHT_DEG_PER_SEC := 420.0

# barras de estado (dos: casco y escudo)
const BARRA_ANCHO := 60.0
const BARRA_ALTO := 3.0
const BARRA_SEPARACION := 5.0

var entity_id := 0
var type_id := ""            # el code del catalogo: "vex", "vexor", "skarn", "phoenix"
var speed := 0.0
var objetivo := Vector2.ZERO
var es_heroe := false
var es_npc := false
var click_radius := 42.0
## Giro: pasos de cuantizacion (0 = continuo) y velocidad angular
## (0 = duracion fija TURN_TIME, el modelo de nave del prototipo).
var turn_steps := TURN_STEPS
var turn_deg_per_sec := 0.0
## Objetivo de ataque: mientras exista GOBIERNA el rumbo (prioridad del
## prototipo: objetivo de ataque > destino de vuelo), incluso con la nave quieta.
var attack_target: EntityNode = null

var _sprite: Sprite2D
## La definicion del JSON se guarda: al cambiar la calidad hay que rehacer la
## parte visual sin volver a pedirle nada al server.
var _def := {}
var _nombre: Label
# dos barras y solo dos: casco y escudo. v1 NO tiene nano-casco (la tercera
# barra amarilla del prototipo): se decidió dejarlo fuera del juego.
var _hp: ColorRect
var _escudo: ColorRect
var _hp_pct := 1.0
var _shield_pct := 0.0
var _seleccionada := false
var max_hp_abs := 0
var max_shield_abs := 0

var _visual_angle := 0.0          # grados de pantalla de la proa
var _turn_tween: Tween
var _idle_timer := 0.0

# motores (modelo del prototipo): una LLAMA por tobera anclada a la nave que
# crece con el empuje, mas una estela de CHISPAS soltadas al mundo
var _flames: Array[Sprite2D] = []
var _trails: Array[GPUParticles2D] = []
var _thrust := 0.0

# bocas de cañón (espacio de la textura) y a cuál toca disparar
var _canones: Array[Vector2] = []
var _canon_actual := 0
var _impactos_casco := 0        # tope del prototipo: 5 simultáneos
var _impactos_escudo := 0       # tope del prototipo: 9

# ondulacion (solo los bichos que la definen en su JSON): el cuerpo serpentea
# y la capa emisiva serpentea CON el, o las visceras se quedarian rectas
var _ondas: Array[ShaderMaterial] = []
var _onda_gain := 0.0
var _onda_idle := 0.35

# ATLAS ANIMADO (segundo tipo de asset): en vez de un PNG con shaders encima,
# una rejilla de fotogramas sacada de un video en bucle. La luz va COCIDA en
# ellos, asi que estos bichos no llevan capa emisiva ni shaders — su vida ya
# esta en el asset. Es lo que hacia el original con sus aliens (`loopPlay`),
# salvo que los suyos por eso no rotaban y los nuestros si.
var _anim_total := 0
var _anim_vaiven := false
var _anim_fps := 12.0
var _anim_t := 0.0

# capa emisiva pulsante (nucleo y venas del Vex)
var _emissive: Sprite2D
var _pulse_min := 0.2          # intensidad del blend aditivo (>1 sobreexpone)
var _pulse_max := 2.4
var _pulse_speed := 2.6
var _pulse_sharp := 2.8        # 1 = seno suave; 3+ = destello marcado con valles largos


func setup(spawn, heroe: bool) -> void:   # spawn: MexProtocol.EntitySpawn
	entity_id = spawn.entity_id
	es_heroe = heroe
	es_npc = spawn.kind == MexProtocol.EntityKind.NPC
	type_id = spawn.type_id
	speed = float(spawn.speed)
	position = Vector2(spawn.x, spawn.y)
	objetivo = position
	_idle_timer = 2.0 + randf() * 5.0
	_hp_pct = spawn.hp_pct

	var d := AssetDefs.entidad(spawn.type_id)
	click_radius = float(d.get("click_radius", 42))
	var giro: Dictionary = d.get("turn", {})
	turn_steps = int(giro.get("steps", TURN_STEPS))
	turn_deg_per_sec = float(giro.get("deg_per_sec", 0.0))

	_def = d
	_construir_visual()

	# bocas de cañón del JSON (espacio de la textura; se alternan al disparar)
	for canon in d.get("cannons", []):
		_canones.append(Vector2(float(canon.get("x", 0)), float(canon.get("y", 0))))
	_construir_etiquetas(d, heroe, spawn)


## Todo lo que depende de la CALIDAD vive aqui, para poder rehacerlo en caliente.
func _construir_visual() -> void:
	var d := _def
	_sprite = Sprite2D.new()
	# ALTA monta el atlas del video; MEDIA y BAJA caen al PNG fijo, que por eso
	# nunca se borro al convertir un bicho a atlas.
	var anim: Dictionary = d.get("frames", {}) if Quality.nivel("npc") >= 2 else {}
	if anim.is_empty():
		_sprite.texture = _textura(d.get("texture", ""), "res://assets/npcs/vex-base.png")
	else:
		_sprite.texture = _textura(anim.get("atlas", ""), "res://assets/npcs/vex-base.png")
		_sprite.hframes = int(anim.get("hframes", 1))
		_sprite.vframes = int(anim.get("vframes", 1))
		_anim_total = int(anim.get("count", _sprite.hframes * _sprite.vframes))
		_anim_vaiven = bool(anim.get("pingpong", false))
		_anim_fps = float(anim.get("fps", 12.0))
		# desfase por entidad: tres Gravon animando al unisono cantan igual que
		# cantaban los gusanos ondulando en fase. Con vaiven el periodo es casi el
		# DOBLE, y repartir sobre `count` dejaria a todos los Vex en la misma mitad
		# de la onda — abriendo el ala a la vez, que es justo lo que se evita.
		var periodo_ := (_anim_total * 2 - 2) if _anim_vaiven else _anim_total
		_anim_t = randf() * float(periodo_) / maxf(_anim_fps, 1.0)
	# tamaño en pantalla constante segun el JSON, sea cual sea la resolucion del
	# export. Con atlas manda el alto del FOTOGRAMA, no el de la textura entera.
	# MIPMAPS, y solo cuando NO es atlas.
	#
	# La nave se dibuja a 141 px desde una textura de 512, y el zoom baja hasta
	# 0,1: ahi son treinta pixeles de una textura de quinientos. Sin mipmaps la
	# GPU muestrea la textura entera con un filtro de 2x2 texeles, asi que el
	# detalle fino no se promedia, se ALIASA — hierve al moverse y se lee como
	# ruido. Es la mitad tecnica de "de lejos no se ve bien"; la otra mitad es
	# cuanto detalle trae el render.
	#
	# Con ATLAS no: los mipmaps promedian a ciegas y en los niveles bajos mezclan
	# celdas vecinas, o sea un fotograma con el siguiente. Esa distincion ya
	# estaba calculada aqui arriba, que es la razon de ponerlo en este punto.
	_sprite.texture_filter = (CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if anim.is_empty()
		else CanvasItem.TEXTURE_FILTER_LINEAR)
	var alto_tex := float(_sprite.texture.get_height()) / maxf(float(_sprite.vframes), 1.0)
	var factor: float = float(d.get("screen_size", 141)) / alto_tex
	_sprite.scale = Vector2.ONE * factor
	add_child(_sprite)

	# capa emisiva (si la define su JSON y su PNG existe de verdad). Un bicho de
	# atlas no la lleva: su luz ya viene cocida en los fotogramas.
	var tex_emisiva := _textura(d.get("emissive", ""), "") \
		if _anim_total == 0 and Quality.nivel("emissive") >= 1 else null
	if tex_emisiva != null:
		_emissive = Sprite2D.new()
		_emissive.texture = tex_emisiva
		_emissive.material = _material_add()
		_sprite.add_child(_emissive)
		var p: Dictionary = d.get("pulse", {})
		_pulse_min = float(p.get("min_intensity", 0.2))
		_pulse_max = float(p.get("max_intensity", 2.4))
		_pulse_speed = float(p.get("speed", 2.6))
		_pulse_sharp = float(p.get("sharpness", 2.8))

	_montar_ondulacion(d)

	# motores en los anclajes del JSON. Nivel 0 = sin llamas; 1 = llamas sin
	# chispas (las particulas son lo caro); 2+ = completo.
	var trail: Dictionary = d.get("engine_trail", {})
	if Quality.nivel("engine") >= 1:
		for motor in d.get("engines", []):
			_flames.append(_crear_llama(motor, trail))
			if Quality.nivel("engine") >= 2:
				_trails.append(_crear_estela(motor, trail))


## Rehace la parte visual con la calidad actual. Lo demas —nombre, barras,
## cañones, rumbo— no depende del nivel y se queda como esta.
func reconstruir() -> void:
	for n in [_sprite]:
		if n != null:
			n.queue_free()
	_sprite = null
	_emissive = null
	_flames.clear()      # eran hijos del sprite: se van con el
	_trails.clear()
	_ondas.clear()
	_anim_total = 0
	_anim_vaiven = false
	_construir_visual()
	# el sprite vuelve al fondo: si no, se dibujaria sobre las barras y el nombre
	move_child(_sprite, 0)
	_set_visual_angle(_visual_angle)


func _construir_etiquetas(d: Dictionary, heroe: bool, spawn) -> void:
	# nombre y barra DEBAJO de la nave, como el prototipo (con contorno negro
	# para que se lean sobre el fondo estelar). El offset sale del tamaño real.
	var mitad: float = float(d.get("screen_size", 141)) * 0.5
	var color := NTheme.CYAN if heroe else (NTheme.TXT if not es_npc else NTheme.HOSTILE)
	_nombre = NTheme.label(spawn.name, NTheme.exo2(), 12, color)
	_nombre.position = Vector2(-70, mitad + 6)
	_nombre.custom_minimum_size = Vector2(140, 0)
	_nombre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nombre.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_nombre.add_theme_constant_override("outline_size", 4)
	add_child(_nombre)

	# las barras van ENCIMA de la nave (el nombre abajo): escudo arriba, casco
	# abajo. Son DOS: el nano-casco del prototipo no existe en v1.
	_shield_pct = clampf(spawn.shield_pct, 0.0, 1.0)
	var barra_y := -mitad - 14.0
	_escudo = _crear_barra(barra_y - BARRA_SEPARACION, NTheme.SHIELD, _shield_pct)
	_hp = _crear_barra(barra_y, NTheme.HP if not es_npc else NTheme.HOSTILE, _hp_pct)


## Shaders vivos de la criatura. Dos efectos INDEPENDIENTES, ambos del JSON:
##
## - `undulate`: el cuerpo serpentea. Va en el sprite Y en su capa emisiva (una
##   con blend aditivo), o el brillo interior se quedaria recto sobre una carne
##   que se dobla.
## - `peristalsis`: una onda de luz recorriendo el interior. Solo en la emisiva.
## - `rings`: anillos concentricos girando. Solo tiene sentido en los bichos de
##   metal, donde la pieza ES concentrica.
## - `flicker`: ruido que hace temblar el brillo. El magma no late limpio como
##   un reactor; arde desigual.
##
## Se piden por separado a proposito: un Skarnox podria tener magma corriendo
## por sus grietas sin que la roca se menee un milimetro.
func _montar_ondulacion(d: Dictionary) -> void:
	var o: Dictionary = d.get("undulate", {})
	var peri: Dictionary = d.get("peristalsis", {})
	var anillos: Dictionary = d.get("rings", {})
	var titileo: Dictionary = d.get("flicker", {})
	if Quality.nivel("shader") < 1:
		return          # calidad baja: ni se crea el material
	if _anim_total > 0:
		# El atlas YA trae el movimiento cocido en sus fotogramas. Montarle encima
		# un shader de cuerpo lo contaria dos veces: al Gravit se le abren los aros
		# en el video Y se los giraria el shader. La animacion manda sobre el truco.
		return
	if o.is_empty() and peri.is_empty() and anillos.is_empty() and titileo.is_empty():
		return
	_onda_idle = float(o.get("idle", 0.35))
	_onda_gain = _onda_idle
	var fase := float(entity_id % 628) * 0.01
	var objetivos := [[_sprite, "res://game/shaders/undulate.gdshader"]]
	if _emissive != null:
		objetivos.append([_emissive, "res://game/shaders/undulate_add.gdshader"])
	for par in objetivos:
		var mat := ShaderMaterial.new()
		mat.shader = load(par[1])
		# sin bloque `undulate` la amplitud es CERO, no el defecto del shader:
		# pedir solo peristalsis no puede poner a bailar al bicho de propina
		mat.set_shader_parameter("amplitude", float(o.get("amplitude", 0.0)))
		mat.set_shader_parameter("frequency", float(o.get("frequency", 2.0)))
		mat.set_shader_parameter("speed", float(o.get("speed", 3.0)))
		mat.set_shader_parameter("from_y", float(o.get("from", 0.25)))
		# fase por entidad: un banco de gusanos al unisono canta a bucle
		mat.set_shader_parameter("phase", fase)
		mat.set_shader_parameter("gain", _onda_gain)
		mat.set_shader_parameter("peri_amount", float(peri.get("amount", 0.0)))
		mat.set_shader_parameter("peri_frequency", float(peri.get("frequency", 2.0)))
		mat.set_shader_parameter("peri_speed", float(peri.get("speed", 2.5)))
		mat.set_shader_parameter("peri_sharpness", float(peri.get("sharpness", 3.0)))
		# radial = la onda sale del centro en vez de recorrer el cuerpo: es como
		# irradia un nucleo fundido, y es lo que separa una roca de un gusano
		mat.set_shader_parameter("peri_radial", 1.0 if peri.get("radial", false) else 0.0)
		mat.set_shader_parameter("flicker_amount", float(titileo.get("amount", 0.0)))
		mat.set_shader_parameter("flicker_scale", float(titileo.get("scale", 6.0)))
		mat.set_shader_parameter("flicker_speed", float(titileo.get("speed", 1.0)))
		mat.set_shader_parameter("ring_speed", float(anillos.get("speed", 0.0)))
		mat.set_shader_parameter("ring_bands", float(anillos.get("bands", 3.0)))
		mat.set_shader_parameter("ring_inner", float(anillos.get("inner", 0.05)))
		mat.set_shader_parameter("ring_outer", float(anillos.get("outer", 0.40)))
		mat.set_shader_parameter("ring_falloff", float(anillos.get("falloff", 0.5)))
		par[0].material = mat
		if not o.is_empty():
			_ondas.append(mat)   # solo la ondulacion se modula por frame


## Carga una textura del JSON. Un asset que todavia no existe (arte en camino,
## ruta mal escrita) NO puede tirar el cliente: cae al respaldo, o a null si no
## lo hay, y se avisa por consola.
static func _textura(ruta: Variant, respaldo: String) -> Texture2D:
	var r := str(ruta)
	if not r.is_empty() and ResourceLoader.exists(r):
		return load(r)
	if not r.is_empty():
		push_warning("textura ausente en el JSON: " + r)
	if respaldo.is_empty():
		return null
	return load(respaldo)


## Una barra sobre su pista negra, del ancho del prototipo.
func _crear_barra(y: float, color: Color, pct: float) -> ColorRect:
	var pista := ColorRect.new()
	pista.color = Color(0, 0, 0, 0.55)
	pista.position = Vector2(-BARRA_ANCHO * 0.5 - 1, y - 1)
	pista.size = Vector2(BARRA_ANCHO + 2, BARRA_ALTO + 2)
	add_child(pista)
	var barra := ColorRect.new()
	barra.color = color
	barra.position = Vector2(-BARRA_ANCHO * 0.5, y)
	barra.size = Vector2(BARRA_ANCHO * pct, BARRA_ALTO)
	add_child(barra)
	return barra


## La llama de una tobera: pluma anclada a la nave que rota con ella y crece
## con el empuje. Su boquilla queda EN la tobera y se afila hacia la popa.
func _crear_llama(motor: Dictionary, trail: Dictionary) -> Sprite2D:
	var llama := Sprite2D.new()
	llama.texture = load("res://assets/fx/engine-flame.png")
	llama.position = Vector2(float(motor.get("x", 0)), float(motor.get("y", 0)))
	# el arte de la llama apunta hacia ABAJO (+Y), que es la popa: sin rotar.
	# el pivote va en la boquilla para que crezca hacia atras, no hacia los lados
	llama.offset = Vector2(0, llama.texture.get_height() * 0.5)
	llama.modulate = AssetDefs.color(trail.get("color", "00E5FF"))
	llama.material = _material_add()
	llama.z_index = -1                   # detras del casco
	_sprite.add_child(llama)
	return llama


## Estela de chispas soltadas AL MUNDO (no siguen a la nave): el rastro que
## queda atras, como el humo de motor del prototipo.
func _crear_estela(motor: Dictionary, trail: Dictionary) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.position = Vector2(float(motor.get("x", 0)), float(motor.get("y", 0)))
	p.amount = 96                   # densas: la estela debe leerse continua
	p.lifetime = float(trail.get("lifetime", 0.42))
	p.local_coords = false          # se quedan en el mundo: se ve el rastro
	p.texture = load("res://assets/fx/spark.png")

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = float(trail.get("width", 9)) * 0.3
	mat.direction = Vector3(0, 1, 0)     # hacia la popa (+Y de la textura)
	mat.spread = 5.0
	mat.gravity = Vector3.ZERO
	var largo: float = float(trail.get("length", 96))
	mat.initial_velocity_min = largo * 0.15
	mat.initial_velocity_max = largo * 0.35
	mat.damping_min = largo * 1.0
	mat.damping_max = largo * 1.6
	mat.scale_min = 0.04            # finas: chispas, no bolas
	mat.scale_max = 0.10
	# las chispas se encogen al apagarse
	var curva := Curve.new()
	curva.add_point(Vector2(0, 1.0))
	curva.add_point(Vector2(1, 0.0))
	var curva_tex := CurveTexture.new()
	curva_tex.curve = curva
	mat.scale_curve = curva_tex

	var grad := Gradient.new()
	var nucleo := AssetDefs.color(trail.get("core_color", "DFFBFF"))
	var color := AssetDefs.color(trail.get("color", "00E5FF"))
	grad.set_color(0, nucleo)
	grad.set_color(1, Color(color, 0.0))
	grad.add_point(0.3, color)
	var rampa := GradientTexture1D.new()
	rampa.gradient = grad
	mat.color_ramp = rampa

	p.process_material = mat
	p.material = _material_add()
	p.emitting = false
	_sprite.add_child(p)
	return p


static func _material_add() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


func _process(delta: float) -> void:
	var en_vuelo := position.distance_to(objetivo) > 0.5

	# acelerador: el empuje sube en vuelo y cae al frenar (modelo del prototipo)
	if not _flames.is_empty() or not _trails.is_empty():
		_thrust = clampf(_thrust + (3.0 if en_vuelo else -4.0) * delta, 0.0, 1.0)
		# la llama crece a lo largo con el empuje y respira; el ancho apenas cambia
		var respiro := 1.0 + 0.10 * sin(Time.get_ticks_msec() * 0.02 + entity_id)
		for llama in _flames:
			llama.visible = _thrust > 0.02
			llama.scale = Vector2(0.55 + 0.15 * _thrust, _thrust * respiro)
			llama.self_modulate.a = 0.35 + 0.65 * _thrust
		for t in _trails:
			t.emitting = _thrust > 0.15
			t.self_modulate.a = _thrust

	if _anim_total > 0:
		_anim_t += delta
		var i := int(_anim_t * _anim_fps)
		if _anim_vaiven:
			# VAIVEN: ida y vuelta. El bucle cierra POR CONSTRUCCION —dos
			# fotogramas seguidos son siempre vecinos— asi que no hay costura que
			# medir ni que arreglar, y sale gratis: el atlas es el mismo.
			#
			# Se descarto para el Gravon y ahi estaba bien descartado: sus aros
			# tienen rotacion NETA, y al reves se mecerian en vez de girar. Un ala
			# que se abre no tiene ese problema — cerrarse ES su vuelta. La tecnica
			# no era mala, era el bicho equivocado.
			var periodo := _anim_total * 2 - 2
			i = i % maxi(periodo, 1)
			if i >= _anim_total:
				i = periodo - i
		else:
			i = i % _anim_total
		_sprite.frame = i

	# la ondulacion sube al nadar y baja al quedarse quieto (nunca a cero: un
	# bicho vivo respira aunque no avance)
	if not _ondas.is_empty():
		var objetivo := 1.0 if en_vuelo else _onda_idle
		_onda_gain = move_toward(_onda_gain, objetivo, 1.5 * delta)
		for mat in _ondas:
			mat.set_shader_parameter("gain", _onda_gain)

	# el latido de la capa emisiva (fase por entidad: no laten al unisono).
	# Se modula la INTENSIDAD del blend aditivo, no solo el alfa: por encima de
	# 1 sobreexpone y el nucleo se pone blanco, que es lo que hace visible el pulso.
	if _emissive != null:
		var onda := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * _pulse_speed + entity_id * 1.7)
		onda = pow(onda, _pulse_sharp)
		var k: float = _pulse_min + (_pulse_max - _pulse_min) * onda
		_emissive.self_modulate = Color(k, k, k, 1.0)

	if en_vuelo:
		# la punta va delante: mientras la proa no mire al destino apenas avanza,
		# y acelera segun se alinea (coseno del error). Sin esto, un Skarnox
		# arrancaba a 190 u/s de costado durante todo su giro.
		var factor := 1.0
		if turn_deg_per_sec > 0.0:
			factor = maxf(cos(deg_to_rad(_error_de_proa(objetivo))), 0.0)
		position = position.move_toward(objetivo, speed * factor * delta)

	# atacando: el rumbo sigue al objetivo aunque se muevan los dos (o ninguno)
	if attack_target != null:
		if is_instance_valid(attack_target):
			_encarar(attack_target.position)
		else:
			attack_target = null
	elif not en_vuelo and es_npc:
		# NPCs parados: giro perezoso aleatorio cada 2-7 s (vida del original)
		_idle_timer -= delta
		if _idle_timer <= 0.0:
			_idle_timer = 2.0 + randf() * 5.0
			_girar_a(_visual_angle + (randf() - 0.5) * 360.0)


## Fija (o limpia con null) el objetivo que gobierna el rumbo.
func set_attack_target(objetivo_ataque: EntityNode) -> void:
	attack_target = objetivo_ataque
	if attack_target != null and is_instance_valid(attack_target):
		_encarar(attack_target.position)


## Orienta la proa hacia un punto del mundo (sin tocar el destino de vuelo).
func _encarar(punto: Vector2) -> void:
	var rumbo := punto - position
	if rumbo.length() > 1.0:
		_girar_a(_angulo_visual_hacia(punto),
			TURN_FLIGHT_DEG_PER_SEC if turn_deg_per_sec > 0.0 else 0.0)


## El angulo visual (proa arriba en el arte -> +90) que mira a un punto.
func _angulo_visual_hacia(punto: Vector2) -> float:
	return rad_to_deg((punto - position).angle()) + 90.0


## Cuanto se desvia la proa del rumbo, en grados (0 = mirando al frente).
func _error_de_proa(punto: Vector2) -> float:
	return absf(fposmod(_angulo_visual_hacia(punto) - _visual_angle + 180.0, 360.0) - 180.0)


## Fija el destino y orienta la proa UNA vez (no cada frame, como el prototipo).
func set_objetivo(destino: Vector2) -> void:
	# zona muerta del prototipo: un destino encima de la nave en pleno vuelo
	# no re-orienta (evita el trompo al clickear sobre ti mismo)
	var en_vuelo := position.distance_to(objetivo) > 0.5
	if en_vuelo and absf(destino.x - position.x) <= DEAD_ZONE \
			and absf(destino.y - position.y) <= DEAD_ZONE:
		objetivo = destino
		return
	objetivo = destino
	# atacando, el objetivo manda sobre el destino de vuelo (prioridad del prototipo)
	if attack_target != null and is_instance_valid(attack_target):
		return
	# proa hacia arriba en el arte -> +90 grados de pantalla
	_encarar(destino)


## Giro. Dos modelos, y la diferencia importa:
##
## - NAVES (turn_deg_per_sec = 0): duracion FIJA de TURN_TIME por el camino
##   corto, cuantizada a 32 pasos. Es el giro del prototipo, calibrado y
##   validado: da igual que el angulo sea de 11 o de 180 grados, siempre tarda
##   lo mismo. En una nave que persigue al cursor eso se siente responsivo.
##
## - BICHOS (turn_deg_per_sec > 0): velocidad ANGULAR constante y giro continuo.
##   Con el modelo de la nave, un alien se daba media vuelta en 0,1 s y parecia
##   un trompo. En el original esto no pasaba porque sus aliens eran animaciones
##   en bucle y NO rotaban nunca (`rotatable=false`); los nuestros son renders
##   con proa, asi que giran, pero a su ritmo: un Skarnox pesa y se nota.
func _girar_a(grados: float, dps := 0.0) -> void:
	var destino_ang := fposmod(grados, 360.0)
	if turn_steps > 0:
		var paso := 360.0 / turn_steps
		destino_ang = fposmod(roundf(grados / paso) * paso, 360.0)
	var delta := fposmod(destino_ang - _visual_angle + 180.0, 360.0) - 180.0
	if is_zero_approx(delta):
		return
	var duracion := TURN_TIME
	var vel := dps if dps > 0.0 else turn_deg_per_sec
	if vel > 0.0:
		duracion = clampf(absf(delta) / vel, 0.06, 8.0)
	if _turn_tween != null:
		_turn_tween.kill()
	_turn_tween = create_tween()
	_turn_tween.tween_method(_set_visual_angle, _visual_angle, _visual_angle + delta, duracion)


func _set_visual_angle(grados: float) -> void:
	_visual_angle = fposmod(grados, 360.0)
	if turn_steps <= 0:
		# giro continuo: un bicho girando despacio a 32 pasos se ve a tirones,
		# porque cada paso dura una eternidad
		_sprite.rotation_degrees = _visual_angle
		return
	# el giro SALTA de posicion en posicion durante el tween, como el flip de
	# frames del sheet original: es el look que distingue al prototipo
	var paso := 360.0 / turn_steps
	_sprite.rotation_degrees = roundf(_visual_angle / paso) * paso


## Eco autoritativo del server: correccion suave si la deriva es chica, snap si es grande.
func reconcile(x: float, y: float, tx: float, ty: float, nueva_vel: float, teleport: bool) -> void:
	speed = nueva_vel
	var server_pos := Vector2(x, y)
	if teleport or position.distance_to(server_pos) > 220.0:
		position = server_pos
	else:
		position = position.lerp(server_pos, 0.35)
	set_objetivo(Vector2(tx, ty))


func set_hp_pct(pct: float) -> void:
	_hp_pct = clampf(pct, 0.0, 1.0)
	_hp.size.x = BARRA_ANCHO * _hp_pct


func set_shield_pct(pct: float) -> void:
	_shield_pct = clampf(pct, 0.0, 1.0)
	_escudo.size.x = BARRA_ANCHO * _shield_pct


## Casco y escudo absolutos del server; cada uno contra su propio máximo.
## Sin máximo conocido (entidad que nunca fue objetivo) la barra conserva lo
## que trajo su spawn: convertir absolutos sin denominador la haría mentir.
func set_estado_abs(hp: int, escudo: int) -> void:
	if max_hp_abs > 0:
		set_hp_pct(float(hp) / max_hp_abs)
	if max_shield_abs > 0:
		set_shield_pct(float(escudo) / max_shield_abs)


## Boca de cañón desde la que sale el próximo disparo, en coordenadas de MUNDO
## (respeta la rotación y escala del sprite). Sin cañones definidos, el centro.
func siguiente_canon() -> Vector2:
	if _canones.is_empty():
		return position
	var local := _canones[_canon_actual]
	_canon_actual = (_canon_actual + 1) % _canones.size()
	return _sprite.to_global(local)


## Chispazo en el casco: punto aleatorio del disco de click, suelto en el mundo.
func impacto_casco() -> void:
	if _impactos_casco >= 5:      # el tope del prototipo
		return
	_impactos_casco += 1
	var rnd := randf()
	var offset := Vector2.from_angle(rnd * TAU) * (click_radius * 0.5 * rnd)
	var anim := _sheet_anim("res://assets/fx/hull-impact.png", 96, 8, 0.45)
	anim.position = position + offset
	anim.rotation = randf() * TAU
	get_parent().add_child(anim)
	anim.tree_exited.connect(func(): _impactos_casco -= 1)


## Onda hexagonal en el escudo: sobre la circunferencia, del lado del atacante.
func impacto_escudo(desde: Vector2) -> void:
	if _impactos_escudo >= 9:     # el tope del prototipo
		return
	_impactos_escudo += 1
	var dir := (desde - position).normalized()
	var anim := _sheet_anim("res://assets/fx/shield-impact.png", 128, 8, 0.3)
	anim.position = dir * click_radius
	anim.rotation = dir.angle()
	anim.modulate = NTheme.SHIELD
	add_child(anim)               # hijo: sigue a la nave
	anim.tree_exited.connect(func(): _impactos_escudo -= 1)


static func _sheet_anim(ruta: String, lado: int, frames: int, duracion: float) -> AnimatedSprite2D:
	var sf := SpriteFrames.new()
	sf.add_animation("x")
	sf.set_animation_loop("x", false)
	sf.set_animation_speed("x", frames / duracion)
	var hoja: Texture2D = load(ruta)
	for i in frames:
		var f := AtlasTexture.new()
		f.atlas = hoja
		f.region = Rect2(i * lado, 0, lado, lado)
		sf.add_frame("x", f)
	var anim := AnimatedSprite2D.new()
	anim.sprite_frames = sf
	anim.z_index = 3
	anim.play("x")
	anim.animation_finished.connect(anim.queue_free)
	return anim


## Seleccion local: esquinas de mira alrededor de la entidad (estilo N).
func set_selected(sel: bool) -> void:
	_seleccionada = sel
	queue_redraw()


func _draw() -> void:
	if not _seleccionada:
		return
	var r := 58.0
	var l := 16.0
	var c := NTheme.HOSTILE if not es_heroe else NTheme.CYAN
	for esquina in [Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)]:
		var dx := -l if esquina.x > 0 else l
		var dy := -l if esquina.y > 0 else l
		draw_line(esquina, esquina + Vector2(dx, 0), c, 2.0)
		draw_line(esquina, esquina + Vector2(0, dy), c, 2.0)
