# La ESCENA 3D UNICA del cliente (Fase 1 del plan-cliente-3d): el mundo entero
# vive aqui — mallas, quads, luces — y lo mira UNA camara en perspectiva con el
# rig orbital del cliente 3D original (guidelines G§3). Es lo que hace posible
# el acoplamiento tilt-zoom: al acercar, la camara baja hacia el horizonte y
# TODO el mundo cambia de perspectiva a la vez.
#
# Mapeo de coordenadas (G§2), literal del original: juego (x, y) -> 3D
# (x, altura, -y), 1 unidad 3D = 1 unidad de juego. Naves a y=0.
class_name Mundo3D
extends Node3D

## Camara del original (G§3): perspectiva FOV vertical 30, near 10, far 80000,
## distancia base 1740/zoom, tilt 135 (= 45 de elevacion), pan 0.
const FOV := 30.0
const NEAR := 10.0
const FAR := 80000.0
const DIST := 1740.0
const TILT := 135.0
const PAN := 0.0
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

var camara: Camera3D
var zoom := ZOOM_MIN:
	set(v):
		zoom = clampf(v, ZOOM_MIN, ZOOM_MAX)
var _zoom_objetivo := ZOOM_MIN
var _zoom_tween: Tween
var _foco := Vector2.ZERO


func _init() -> void:
	instancia = self


func _ready() -> void:
	var ent := Environment.new()
	ent.background_mode = Environment.BG_COLOR
	ent.background_color = Color.BLACK
	AssetDefs.ambiente_mundo(ent)
	var we := WorldEnvironment.new()
	we.environment = ent
	add_child(we)
	# LA luz del mundo, una sola (el dial de AssetDefs). Sin sombras (G§7).
	add_child(AssetDefs.sol_mundo())
	camara = Camera3D.new()
	camara.fov = FOV
	camara.near = NEAR
	camara.far = FAR
	add_child(camara)
	camara.current = true
	actualizar(Vector2.ZERO)


## Recoloca la camara sobre su foco (coordenadas de JUEGO). Seguimiento RIGIDO
## a enteros, como el original — la suavidad viene de que el heroe ya llega
## interpolado por el modelo.
func actualizar(foco: Vector2) -> void:
	_foco = foco.floor()
	var reduc := clampf((zoom - ZOOM_MIN) / (ZOOM_MAX - ZOOM_MIN) * TILT_ZOOM_REDUC,
		0.0, TILT_ZOOM_REDUC)
	var t := deg_to_rad(TILT - reduc)
	var p := deg_to_rad(PAN)
	var d := DIST / zoom
	var mira := Vector3(_foco.x, 0.0, -_foco.y)
	var pos := mira + Vector3(d * sin(t) * sin(p), -d * cos(t), -d * sin(t) * cos(p))
	camara.look_at_from_position(pos, mira, Vector3.UP)


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


# ---- proyecciones (G§4) ----

## Mundo (juego) -> pixel de pantalla.
func a_pantalla(p: Vector2, altura := 0.0) -> Vector2:
	return camara.unproject_position(Vector3(p.x, altura, -p.y))


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
	return Vector2(hit.x, -hit.z)


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
