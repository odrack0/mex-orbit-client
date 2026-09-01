# La ESCENA 3D UNICA del cliente (Fase 1 del plan-cliente-3d): el mundo entero
# vive aqui — mallas, quads, luces — y lo mira UNA camara en perspectiva con el
# rig orbital del cliente 3D original (guidelines G§3). Es lo que hace posible
# el acoplamiento tilt-zoom: al acercar, la camara baja hacia el horizonte y
# TODO el mundo cambia de perspectiva a la vez.
#
# Mapeo de coordenadas: juego (x, y) -> 3D (x, altura, +y), 1 unidad 3D = 1
# unidad de juego, naves a y=0. OJO: el original mapeaba z = -y porque Away3D
# es un motor ZURDO (Flash); Godot es diestro, y con z = -y una camara estandar
# no puede mostrar x->derecha e y->abajo a la vez — el mundo salia ESPEJADO
# respecto al minimapa (se cazo volando). z = +y es el equivalente diestro.
class_name Mundo3D
extends Node3D

## Camara del original (G§3): perspectiva FOV vertical 30, near 10, far 80000,
## distancia base 1740/zoom, tilt 135 (= 45 de elevacion), pan 0.
const FOV := 30.0
const NEAR := 10.0
const FAR := 80000.0
const DIST := 1740.0
const TILT := 135.0
## Pan del original (G§3): 0 en mapas planos, 25 en mapas CON fondo 3D — el
## display3D del 1-1 esta compuesto para verse con la camara girada 25 grados.
## Lo fija el mapa via MapBgConfig/world.
var pan_grados := 0.0
## Zoom continuo [1,3], rueda x1.2 / x0.8, tween 0.3 s Quad ease-out.
const ZOOM_MIN := 1.0
const ZOOM_MAX := 3.0
const ZOOM_PASO := 1.2
const ZOOM_TWEEN_SEC := 0.3
## Acoplamiento tilt-zoom (G§3): al acercar, la camara baja hasta 20 grados
## hacia el horizonte — el "picado bajo" que cambia la perspectiva de los
## aliens al hacer zoom. tiltEfectivo = TILT - clamp((zoom-1)/2 * 20, 0, 20).
const TILT_ZOOM_REDUC := 20.0

## La instancia viva (una por mundo): las entidades montan sus cuerpos aqui.
static var instancia: Mundo3D

## Pool de EXACTAMENTE 3 luces de efectos (G§7.2): pre-creadas y apagadas,
## reciclado circular, nunca se instancia una luz en gameplay. Los destellos de
## disparo y explosion salen de aqui.
var _luces: Array[OmniLight3D] = []
var _luz_i := 0

var camara: Camera3D
var zoom := ZOOM_MIN:
	set(v):
		zoom = clampf(v, ZOOM_MIN, ZOOM_MAX)
var _zoom_objetivo := ZOOM_MIN
var _zoom_tween: Tween
var _foco := Vector2.ZERO


func _init() -> void:
	instancia = self


var _env: Environment


func _ready() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color.BLACK
	AssetDefs.ambiente_mundo(_env)
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	# LA luz del mundo, una sola (el dial de AssetDefs). Sin sombras (G§7).
	add_child(AssetDefs.sol_mundo())
	camara = Camera3D.new()
	camara.fov = FOV
	camara.near = NEAR
	camara.far = FAR
	add_child(camara)
	camara.current = true
	for i in 3:
		var luz := OmniLight3D.new()
		luz.light_energy = 0.0
		luz.omni_range = 1.0
		luz.shadow_enabled = false
		add_child(luz)
		_luces.append(luz)
	actualizar(Vector2.ZERO)
	aplicar_calidad_render()


## Las dos palancas de GPU de la calidad (`render` y `aa`), sobre el viewport
## raiz: la escala del render 3D y el MSAA. El 2D (HUD, ventanas) no escala —
## el viewport solo reescala su buffer 3D y lo compone al tamanio de la
## ventana; con el estiramiento `canvas_items` del proyecto la interfaz sigue
## nitida. Es la unica parte de la calidad que no reconstruye nada: se aplica
## en caliente y el siguiente frame ya sale asi.
## MEDIA a 0,85 y no a 0,75 (1-sep, en vivo): con FSR la diferencia de coste es
## chica y la de nitidez se nota; BAJA se queda en 0,5, que es donde ahorra.
const ESCALAS_RENDER := [0.5, 0.85, 1.0]
const MSAA := [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X]

func aplicar_calidad_render() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var escala: float = ESCALAS_RENDER[clampi(Quality.nivel("render"), 0, 2)]
	# FSR y no bilineal (1-sep, reportado en vivo): el bilineal amplia cada
	# pixel del render chico tal cual, y sobre una silueta contra el negro
	# del espacio eso son escalones de 2 px — "la nave se ve pixelada". FSR
	# (FidelityFX 1.0) reconstruye los bordes al ampliar y afila: a 0,75x
	# queda casi nativo y a 0,5x blando, pero sin dientes. A 1x no hay nada
	# que ampliar y el bilineal es gratis.
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if escala < 1.0 \
		else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = escala
	vp.msaa_3d = MSAA[clampi(Quality.nivel("aa"), 0, 2)]
	# se deja dicho, como la auto-calidad: es lo unico que permite saber desde
	# un log si el ajuste llego al viewport o se quedo en el diccionario
	print("Calidad: render %.2fx (viewport %.2fx) · MSAA %s" % [
		ESCALAS_RENDER[clampi(Quality.nivel("render"), 0, 2)], vp.scaling_3d_scale,
		["off", "2x", "4x"][clampi(Quality.nivel("aa"), 0, 2)]])


## Un destello del pool: sube de golpe y se funde solo. Cuantas luces hay
## disponibles lo dice la calidad (`luces`: 0 ninguna, 1 una, 2 el pool entero).
func luz_efecto(pos: Vector3, color: Color, energia: float, rango: float,
		mantener: float, fundido: float) -> void:
	var n := 0
	match Quality.nivel("luces"):
		0: n = 0
		1: n = 1
		_: n = _luces.size()
	if n == 0:
		return
	_luz_i = (_luz_i + 1) % n
	var luz := _luces[_luz_i]
	if luz.has_meta("tw"):
		var previo = luz.get_meta("tw")
		if previo is Tween and (previo as Tween).is_valid():
			(previo as Tween).kill()  # la luz se recicla: el fundido viejo no manda
	luz.position = pos
	luz.light_color = color
	luz.omni_range = rango
	luz.light_energy = energia
	var tw := luz.create_tween()
	tw.tween_property(luz, "light_energy", 0.0, fundido).set_delay(mantener)
	luz.set_meta("tw", tw)


## Recoloca la camara sobre su foco (coordenadas de JUEGO).
##
## ANTES snapeaba `foco.floor()` (seguimiento RIGIDO a enteros, como el
## original), con el razonamiento de que "la suavidad viene de que el heroe
## ya llega interpolado por el modelo". Ese razonamiento estaba incompleto:
## en el original 2D, la NAVE tambien se dibujaba pixel-snapeada, asi que
## camara y nave saltaban JUNTAS y no habia desajuste. Aqui el cuerpo del
## heroe se posiciona en su `position` CONTINUA (game/entity_node.gd,
## `_cuerpo.position`), sin redondear — asi que redondear solo la camara
## abre una brecha entre donde esta la nave y hacia donde mira la camara,
## que crece con el movimiento y se resetea de golpe cada vez que `foco`
## cruza un limite de unidad entera: un serrucho continuo en la posicion EN
## PANTALLA del heroe (el unico punto que la camara seguia), aunque su
## posicion logica sea perfectamente suave. Reportado 31-ago como "vibracion
## de proa, solo mi nave, incluso sin tocar el mouse" — dos pruebas lo
## aislaron: seguia sin input (no es del control) y no le pasaba a los NPC
## (no los sigue la camara). Foco CONTINUO: sin el desajuste no hace falta.
func actualizar(foco: Vector2) -> void:
	_foco = foco
	var reduc := clampf((zoom - ZOOM_MIN) / (ZOOM_MAX - ZOOM_MIN) * TILT_ZOOM_REDUC,
		0.0, TILT_ZOOM_REDUC)
	var t := deg_to_rad(TILT - reduc)
	var p := deg_to_rad(pan_grados)
	var d := DIST / zoom
	var mira := Vector3(_foco.x, 0.0, _foco.y)
	# la camara queda del lado del ESPECTADOR (z+, el borde inferior de la
	# pantalla) mirando hacia el fondo: x->derecha, y de juego->abajo, como el
	# minimapa y el original
	var pos := mira + Vector3(d * sin(t) * sin(p), -d * cos(t), d * sin(t) * cos(p))
	camara.look_at_from_position(pos, mira, Vector3.UP)
	if _skybox != null:
		_skybox.position = mira    # el skybox sigue a la camara (el original)


## Zoom por rueda: compone sobre el OBJETIVO (una rafaga no pierde peldanios) y
## llega con tween, el gesto del original.
func zoom_por_rueda(acercar: bool) -> void:
	zoom_a(_zoom_objetivo * ZOOM_PASO if acercar else _zoom_objetivo / ZOOM_PASO)


func zoom_a(objetivo: float) -> void:
	_zoom_objetivo = clampf(objetivo, ZOOM_MIN, ZOOM_MAX)
	if _zoom_tween != null:
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.tween_property(self, "zoom", _zoom_objetivo, ZOOM_TWEEN_SEC) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Fija el zoom en el acto (autotest); el proximo tween compone desde aqui.
func zoom_directo(v: float) -> void:
	if _zoom_tween != null:
		_zoom_tween.kill()
	zoom = v
	_zoom_objetivo = zoom


var _skybox: MeshInstance3D


## El CIELO: el DOSkybox del original — su malla skybox_geometry escalada
## x10000 siguiendo a la camara, con el pase exacto decompilado (dos mascaras
## moviles multiplicadas por la textura fina de estrellas; skybox_do.gdshader).
## No escribe profundidad y va con prioridad -10: todo lo demas (planeta,
## techo, tiles) se pinta encima. Si faltan los assets, cae al cielo
## procedural viejo (cielo.gdshader) tenido con el tinte del mapa.
func poner_cielo(tinte: Color) -> void:
	const MALLA := "res://assets/do-ref/skybox.obj"
	const STARS := "res://assets/do-ref/skybox-stars.png"
	const MASK := "res://assets/do-ref/skybox-mask.png"
	if ResourceLoader.exists(MALLA) and ResourceLoader.exists(STARS) \
			and ResourceLoader.exists(MASK):
		_skybox = MeshInstance3D.new()
		_skybox.mesh = load(MALLA)
		# El original escala x10000 (radio ~4300) porque su skybox es un
		# PRE-PASE sin test de profundidad: la distancia no importa. Aqui es un
		# transparente mas y SI testea profundidad, asi que la esfera debe
		# ENVOLVER todo lo opaco (los props llegan a ~17000 del foco y el
		# planeta a ~50000): radio nativo 0.43 x 160000 = ~69000, bajo el far
		# de 80000. Con 10000 tapaba con estrellas cualquier malla mas lejana.
		_skybox.scale = Vector3.ONE * 160000.0
		var mat := ShaderMaterial.new()
		mat.shader = load("res://game/shaders/skybox_do.gdshader")
		mat.set_shader_parameter("estrellas", load(STARS))
		mat.set_shader_parameter("mascara", load(MASK))
		mat.render_priority = -10
		_skybox.material_override = mat
		add_child(_skybox)
		return
	var mat := ShaderMaterial.new()
	mat.shader = load("res://game/shaders/cielo.gdshader")
	mat.set_shader_parameter("tinte", Vector3(tinte.r, tinte.g, tinte.b))
	var sky := Sky.new()
	sky.sky_material = mat
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky


# ---- proyecciones (G§4) ----

## Mundo (juego) -> pixel de pantalla.
func a_pantalla(p: Vector2, altura := 0.0) -> Vector2:
	return camara.unproject_position(Vector3(p.x, altura, p.y))


## Pixel de pantalla -> mundo (juego), por interseccion rayo-plano y=altura.
## Vector2.INF si el rayo es paralelo o el plano queda detras de la camara.
func a_mundo(px: Vector2, altura := 0.0) -> Vector2:
	var o := camara.project_ray_origin(px)
	var dir := camara.project_ray_normal(px)
	if absf(dir.y) < 0.000001:
		return Vector2.INF
	var t := (altura - o.y) / dir.y
	if t < 0.0:
		return Vector2.INF
	var hit := o + dir * t
	return Vector2(hit.x, hit.z)


## Unidades de juego que mide UN pixel en el centro de la pantalla (para radios
## de click constantes en pantalla, como el original).
func unidades_por_pixel() -> float:
	var centro := get_viewport().get_visible_rect().size * 0.5
	var a := a_mundo(centro)
	var b := a_mundo(centro + Vector2(10, 0))
	if a == Vector2.INF or b == Vector2.INF:
		return 1.0
	return maxf(a.distance_to(b) / 10.0, 0.001)


## Las 4 esquinas del viewport llevadas al plano del juego — el TRAPECIO del
## minimapa (G§4). Con la camara inclinada el encuadre no es un rectangulo.
func esquinas_encuadre() -> Array[Vector2]:
	var s := get_viewport().get_visible_rect().size
	var out: Array[Vector2] = []
	for px in [Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]:
		var m := a_mundo(px)
		if m == Vector2.INF:
			return []
		out.append(m)
	return out


# ---- ladrillos visuales ----

## Un sprite TUMBADO en el plano del juego (el arte cenital de siempre, ahora
## como quad en la escena — el placeholder del original, G§5.5). `alto_mundo` en
## unidades de juego; la textura manda el aspecto.
static func sprite_plano(tex: Texture2D, alto_mundo: float, vframes := 1) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.axis = Vector3.AXIS_Y            # tumbado: la normal apunta al cielo
	s.shaded = false
	var alto_px := float(tex.get_height()) / maxf(float(vframes), 1.0)
	s.pixel_size = alto_mundo / maxf(alto_px, 1.0)
	return s


## Un quad ADITIVO que mira a camara (flashes, resplandores). Los FX luminosos
## SUMAN luz (G§9.5); Sprite3D no sabe de blend add, esto si.
static func quad_aditivo(tex: Texture2D, lado_mundo: float, billboard := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(lado_mundo, lado_mundo)
	mi.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = tex
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	if billboard:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	else:
		mi.rotation.x = -PI / 2        # tumbado en el plano, como el sprite_plano
	mi.material_override = mat
	q.material = mat
	return mi
