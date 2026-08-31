# El FONDO del mundo (F3 del plan-cliente-3d, G§10): profundidad DE VERDAD.
# Ya no hay formula de paralaje — cada capa vive a su cota y la camara en
# perspectiva hace el resto, que es exactamente como lo hacia el original:
#
#   cielo      -> Sky del Environment (shaders/cielo.gdshader): estrellas con
#                 twinkle, infinito, recentrado gratis
#   telon      -> el arte del mapa a y=-4200, la capa mas profunda
#   nebulosas  -> mosaicos de quads a y = -3500 + capa*550, CADA tile con su
#                 propio jitter vertical (-500..-200): el paralaje entre tiles
#                 lo produce la camara (la joya del tilemap del original)
#   planetas   -> a cota segun su p_factor (heredado del JSON del mapa)
#   sol        -> quad aditivo girando + cadena de flares proyectada al HUD
#   polvo      -> GPUParticles3D anclado al MUNDO que se recentra a saltos de
#                 rejilla siguiendo a la camara: la capa que vende el vuelo
#
# Todo sale del MISMO data/maps/<code>.json de siempre (via MapBgConfig): los
# p_factor del 2D se reinterpretan como profundidad. Determinista por mapa:
# mismas semillas, mismo cielo.
class_name Fondo3D
extends Node3D

## Cotas del original: capas de nebulosa desde -3500 subiendo 550 por capa,
## jitter por tile entre -500 y -200 (G§10.2).
const CAPA_BASE := -3500.0
const CAPA_PASO := 550.0
const JITTER_MIN := -500.0
const JITTER_MAX := -200.0
const TELON_Y := -4200.0
## Tamanio del tile en mundo = ancho_textura * scale * este factor (el original
## usaba 5 sobre tiles de ~256; nuestro arte es de 1024).
const TILE_FACTOR := 1.5
## Fraccion de celdas VACIAS del mosaico (rompe la repeticion, como la mascara
## de agujeros del original).
const TILE_HUECOS := 0.25
## Cuanto cubre el mosaico mas alla del mapa.
const MARGEN := 1.5

## El polvo estelar (G§10.4): volumen alrededor del foco, anclado al mundo.
const POLVO_N := 1500
const POLVO_CAJA := Vector3(4200.0, 300.0, 4200.0)
const POLVO_Y := -160.0
const POLVO_REJILLA := 1000.0
const POLVO_VIDA := 25.0

var _limites := Vector2.ONE
var _polvo: GPUParticles3D
var _sol: MeshInstance3D
var _sol_spin := -9.0
var _sol_pos := Vector2.ZERO
var _ghosts: Array[Sprite2D] = []

## fantasmas de la cadena de lentes: fraccion del eje sol->centro, escala y tinte
const GHOSTS := [
	[0.35, 0.30, Color(0.5, 0.9, 1.0, 0.35)],
	[0.65, 0.18, Color(1.0, 0.85, 0.5, 0.30)],
	[1.15, 0.42, Color(0.7, 0.6, 1.0, 0.25)],
	[1.55, 0.24, Color(0.5, 1.0, 0.9, 0.22)],
]


## Monta el fondo del mapa. `config` es el de MapBgConfig.para().
func build(config: Dictionary, limites: Vector2, semilla: int) -> void:
	_limites = limites
	var nivel := Quality.nivel("background")
	var tinte: Color = config.get("starfield_tint", Color(0.4, 0.95, 1.0))
	Mundo3D.instancia.poner_cielo(tinte)
	if nivel < 1:
		return                    # baja: solo el cielo

	# el telon: el arte del mapa como la capa mas profunda
	if config.has("main"):
		var tex: Texture2D = config.main
		var telon := MeshInstance3D.new()
		var q := QuadMesh.new()
		var alto := limites.y * 1.8
		q.size = Vector2(alto * float(tex.get_width()) / float(tex.get_height()), alto)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = tex
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		q.material = mat
		telon.mesh = q
		telon.rotation.x = -PI / 2
		telon.position = Vector3(limites.x * 0.5, TELON_Y, limites.y * 0.5)
		add_child(telon)

	# planetas y sol, a la cota que dicta su p_factor (mas factor = mas hondo)
	for p: Dictionary in config.get("planets", []):
		if p.tex == null:
			continue
		var prof: float = float(p.p_factor) * 250.0
		var pos: Vector2 = (p.pos as Vector2) * 10.0
		# a mas hondo, mas grande, para que EN PANTALLA mida como su arte pedia
		var aparente := (1740.0 + prof) / 1740.0
		var s := Mundo3D.sprite_plano(p.tex,
			float((p.tex as Texture2D).get_height()) * float(p.get("scale", 1.0)) * aparente)
		s.position = Vector3(pos.x, -prof, pos.y)
		add_child(s)
	if config.has("sun"):
		var tex_sol: Texture2D = load("res://assets/world/layers/sun.png")
		var prof_sol: float = float(config.sun.get("p_factor", 10.0)) * 250.0
		var pos_sol: Vector2 = (config.sun.pos as Vector2) * 10.0
		_sol_pos = pos_sol
		var aparente_sol := (1740.0 + prof_sol) / 1740.0
		_sol = Mundo3D.quad_aditivo(tex_sol,
			float(tex_sol.get_width()) * float(config.sun.get("scale", 0.9)) * aparente_sol, false)
		_sol.position = Vector3(pos_sol.x, -prof_sol, pos_sol.y)
		add_child(_sol)
		_sol_spin = float(config.sun.get("spin", -9.0))
		_montar_flares()

	# PROPS de fondo (F3+): las mallas y planos que habitan el mapa — lunas,
	# estaciones mineras, satelites — a su cota, con giro lento. Es la pieza que
	# el descriptor display3D del original monta por mapa; los transforms vienen
	# del JSON del mapa tal cual.
	for prop: Dictionary in config.get("props", []):
		_montar_prop(prop)

	# el polvo estelar que vende el vuelo
	_montar_polvo(tinte, float(config.get("starfield_tint_ratio", 0.35)))

	if nivel < 2:
		return                    # media: sin mosaicos de nebulosa

	# los mosaicos de profundidad: far abajo, near arriba (orden = su lista)
	var capas: Array = []
	for t in config.get("tiles_far", []):
		capas.append(t)
	for t in config.get("tiles_near", []):
		capas.append(t)
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	for i in capas.size():
		_montar_mosaico(capas[i], CAPA_BASE + float(i) * CAPA_PASO, rng)


## Un mosaico de quads con el MISMO arte, roto con las armas del original:
## celdas vacias, giros de 90 y el jitter vertical POR TILE que convierte la
## capa en profundidad de verdad.
func _montar_mosaico(t: Dictionary, y_base: float, rng: RandomNumberGenerator) -> void:
	var tex: Texture2D = t.tex
	if tex == null:
		return
	# ATLAS DE VARIANTES (el arma del original contra la repeticion): si el JSON
	# declara `celdas`, la textura es una rejilla `grid`x`grid` de nubes y cada
	# tile del mosaico sortea la suya — como la seleccion de tiles del original.
	var celdas := int(t.get("celdas", 1))
	var grid := int(t.get("grid", 1 if celdas <= 1 else 2))
	var lado_px := float(tex.get_width()) / float(grid)
	var lado := lado_px * float(t.get("scale", 1.0)) * TILE_FACTOR
	var alfa := float(t.get("alpha", 1.0))
	var span := _limites * MARGEN
	var origen := -_limites * (MARGEN - 1.0) * 0.5
	var nx := maxi(int(ceil(span.x / lado)), 1)
	var ny := maxi(int(ceil(span.y / lado)), 1)
	for cx in nx:
		for cy in ny:
			if rng.randf() < TILE_HUECOS:
				continue
			var s := Mundo3D.sprite_plano(tex, lado, grid)
			if celdas > 1:
				s.hframes = grid
				s.vframes = grid
				s.frame = rng.randi_range(0, celdas - 1)
			s.position = Vector3(origen.x + (float(cx) + 0.5) * lado,
				y_base + rng.randf_range(JITTER_MIN, JITTER_MAX),
				origen.y + (float(cy) + 0.5) * lado)
			s.rotation.y = float(rng.randi_range(0, 3)) * PI * 0.5
			s.modulate.a = alfa * rng.randf_range(0.7, 1.0)
			add_child(s)


var _girando: Array = []          # [{nodo, spin (grados/s por eje)}]


## Un prop del fondo: malla OBJ con su textura (iluminada por el sol del mundo)
## o un plano gigante. Campos del JSON: malla|plano, tex, x/y/z (unidades de
## mundo; y negativo = hondo), escala, rot_x/rot_y/rot_z (grados) y spin
## {x,y,z} en grados/segundo — el "append" del background_animation original.
func _montar_prop(p: Dictionary) -> void:
	var nodo: Node3D = null
	var tex: Texture2D = null
	var ruta_tex := str(p.get("tex", ""))
	if ruta_tex != "" and ResourceLoader.exists(ruta_tex):
		tex = load(ruta_tex)
	# `modulate` atenua (o tine) el prop: en un plano aditivo es LA palanca de
	# intensidad — un techo de nebulosa a plena potencia lava el cielo entero.
	var mod := AssetDefs.color(p.get("modulate", "FFFFFF"))
	if p.has("malla"):
		var ruta := str(p.malla)
		if not ResourceLoader.exists(ruta):
			push_warning("fondo: falta la malla %s" % ruta)
			return
		var mi := MeshInstance3D.new()
		mi.mesh = load(ruta)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.albedo_color = mod
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.8
		mi.material_override = mat
		nodo = mi
	elif p.has("plano"):
		var lado := float(p.get("escala", 1000.0))
		if bool(p.get("aditivo", false)):
			var mi := Mundo3D.quad_aditivo(tex, lado, false)
			(mi.material_override as StandardMaterial3D).albedo_color = mod
			mi.rotation.x = 0.0          # el JSON manda la orientacion completa
			nodo = mi
		else:
			var mi := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(lado, lado)
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_texture = tex
			mat.albedo_color = mod
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			q.material = mat
			mi.mesh = q
			nodo = mi
	else:
		return
	nodo.position = Vector3(float(p.get("x", 0)), float(p.get("y", -2000)), float(p.get("z", 0)))
	if p.has("malla"):
		nodo.scale = Vector3.ONE * float(p.get("escala", 1.0))
	nodo.rotation_degrees = Vector3(float(p.get("rot_x", 0)), float(p.get("rot_y", 0)),
		float(p.get("rot_z", 0)))
	add_child(nodo)
	var spin: Dictionary = p.get("spin", {})
	if not spin.is_empty():
		_girando.append({"nodo": nodo, "spin": Vector3(float(spin.get("x", 0)),
			float(spin.get("y", 0)), float(spin.get("z", 0)))})


## El polvo (G§10.4): particulas en un volumen alrededor del foco, SUELTAS AL
## MUNDO (local_coords off) con deriva lenta; el emisor salta por la rejilla
## siguiendo a la camara y las particulas viejas se quedan donde nacieron.
func _montar_polvo(tinte: Color, tinte_ratio: float) -> void:
	_polvo = GPUParticles3D.new()
	_polvo.amount = POLVO_N
	_polvo.lifetime = POLVO_VIDA
	_polvo.preprocess = POLVO_VIDA
	_polvo.local_coords = false
	_polvo.explosiveness = 0.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = POLVO_CAJA * 0.5
	pm.direction = Vector3(1, 0, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 6.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	# la variedad de color del original: grises con una fraccion tenida del mapa
	var g := Gradient.new()
	g.set_color(0, Color(0.55, 0.55, 0.55))
	g.add_point(1.0 - tinte_ratio, Color(0.95, 0.95, 0.95))
	g.set_color(1, tinte)
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_initial_ramp = gt
	_polvo.process_material = pm

	var q := QuadMesh.new()
	q.size = Vector2(4.0, 4.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = _tex_mota()
	q.material = mat
	_polvo.draw_pass_1 = q
	add_child(_polvo)


static var _tex_mota_cache: GradientTexture2D


static func _tex_mota() -> GradientTexture2D:
	if _tex_mota_cache == null:
		var g := Gradient.new()
		g.set_color(0, Color.WHITE)
		g.set_color(1, Color(1, 1, 1, 0))
		_tex_mota_cache = GradientTexture2D.new()
		_tex_mota_cache.gradient = g
		_tex_mota_cache.width = 16
		_tex_mota_cache.height = 16
		_tex_mota_cache.fill = GradientTexture2D.FILL_RADIAL
		_tex_mota_cache.fill_from = Vector2(0.5, 0.5)
		_tex_mota_cache.fill_to = Vector2(0.5, 0.0)
	return _tex_mota_cache


## La cadena de lentes del sol, proyectada al HUD: N sprites sobre la recta
## sol->centro extendida al lado opuesto (la formula x3 del original). Sin
## oclusion todavia — F4, con el raycast.
func _montar_flares() -> void:
	var tex: Texture2D = load("res://assets/world/layers/flare-ghost.png")
	if tex == null or EntityNode.capa_hud == null:
		return
	for g: Array in GHOSTS:
		var ghost := Sprite2D.new()
		ghost.texture = tex
		ghost.scale = Vector2.ONE * g[1]
		ghost.modulate = g[2]
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		ghost.material = m
		ghost.z_index = -1        # bajo las barras y nombres
		EntityNode.capa_hud.add_child(ghost)
		_ghosts.append(ghost)


func _exit_tree() -> void:
	for ghost in _ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()
	_ghosts.clear()


## Por frame: el sol gira, el polvo se recentra a saltos y los flares siguen la
## proyeccion del sol.
func update(foco: Vector2, delta: float) -> void:
	if _sol != null:
		_sol.rotation.y += deg_to_rad(_sol_spin) * delta
	# el giro perezoso de los props (el "append" del original)
	for g: Dictionary in _girando:
		(g.nodo as Node3D).rotation_degrees += (g.spin as Vector3) * delta
	if _polvo != null:
		var centro := Vector3(foco.x, POLVO_Y, foco.y)
		if Vector2(_polvo.position.x, _polvo.position.z).distance_to(foco) > POLVO_REJILLA:
			_polvo.position = centro.snapped(Vector3.ONE * POLVO_REJILLA)
	if not _ghosts.is_empty():
		var px := Mundo3D.instancia.a_pantalla(_sol_pos, _sol.position.y)
		var viewport := get_viewport().get_visible_rect().size
		var dentro: bool = px.x > -100.0 and px.y > -100.0 \
			and px.x < viewport.x + 100.0 and px.y < viewport.y + 100.0
		var eje := viewport * 0.5 - px
		for i in _ghosts.size():
			_ghosts[i].visible = dentro
			_ghosts[i].position = px + eje * (GHOSTS[i][0] as float)
