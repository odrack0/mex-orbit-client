# Catalogo de definiciones en JSON: naves, NPCs y mapas.
# Heredero del maps-config.xml + la tabla de anclajes de llamas del cliente
# original: nada de particularidades por asset hardcodeadas en el codigo.
# Los JSON viven en data/ y se cargan una vez (cache en memoria).
class_name AssetDefs

const SHIPS_PATH := "res://data/ships/%s.json"
const NPCS_PATH := "res://data/npcs/%s.json"
const MAPS_PATH := "res://data/maps/%s.json"
const PROPS_PATH := "res://data/props/%s.json"
const AMMO_PATH := "res://data/ammo/%s.json"
const CONFIG_PATH := "res://data/config/%s.json"

static var _cache := {}
## Overrides en memoria del TALLER de assets (solo dev): un JSON editado en vivo
## pisa al del disco hasta que se limpie. path -> Dictionary.
static var _overrides := {}

## Los diales de la luz y el material: data/config/lighting.json. Se declara
## ANTES de las estaticas que lo leen (las `static var` se inicializan en orden
## de declaracion) y despues de `_cache`, que usa la carga.
static var CFG: Dictionary = config("lighting")
static var _WORLD_LIGHT: Dictionary = CFG.get("world_light", {})
static var _HERO_LIGHT: Dictionary = CFG.get("hero_light", {})
static var _MATERIAL: Dictionary = CFG.get("material", {})
static var _GLOW: Dictionary = CFG.get("glow", {})
static var _REFLECTION_SKY: Dictionary = CFG.get("reflection_sky", {})
static var _MEASURE_CAMERA: Dictionary = CFG.get("measure_camera", {})

## De donde viene la luz del mundo, en grados de pantalla (0 = derecha, 90 =
## abajo). UNA sola para todo lo que se ilumine, o el mundo se rompe: dos objetos
## con su propia luz se leen como dos recortes pegados, no como dos cosas en el
## mismo sitio. Es la razon de que viva aqui y no en el JSON de cada asset — un
## dial por asset invitaria justo a eso.
##
## 315 grados = arriba y a la izquierda. Es la convencion de toda la vida en arte
## 2D, y no por capricho: el ojo humano da por supuesta la luz de arriba, y el
## sesgo a la izquierda desambigua bulto de hueco.
static var WORLD_LIGHT_DEG: float = num(_WORLD_LIGHT, "deg", 315.0)

## Color, elevacion y energia de esa misma luz, para el camino 3D. Viven AQUI y no
## en entity_node por el motivo de arriba: son del MUNDO, no del asset. Estaban
## sueltas en el codigo del viewport, separadas del azimut que si estaba aqui, y
## eso invita a que alguien las toque por bicho sin darse cuenta de que rompe la
## unidad de la escena.
##
## LA LUZ DEL display3D (dictamen 31-ago-2026: "tal cual DarkOrbit 3D, pero en
## Godot"). Los defaults del XML <light> del original: color BLANCO, diffuse 1,
## specular 0.7, tilt 100, pan 35 — es LA luz de los mapas 3D y bania naves,
## bichos y props de fondo por igual. El cian 0.8 anterior venia de otro rincon
## del legacy y despegaba los props del ambiente. OJO homologacion: cambiar esto
## descalibra el horneado de media (HORNO_SOL); media se rehornea despues.
static var WORLD_LIGHT_COLOR: Color = color(_WORLD_LIGHT.get("color", ""), Color.WHITE)
static var WORLD_LIGHT_ENERGY: float = num(_WORLD_LIGHT, "energy", 1.0)
static var WORLD_LIGHT_SPECULAR: float = num(_WORLD_LIGHT, "specular", 0.7)
## Direccion por la formula esferica del original (la de su camara/luz):
## offset = (sin t sin p, -cos t, -sin t cos p) con t=tilt 100, p=pan 35,
## apuntando al origen y con la z espejada a Godot.
static var WORLD_LIGHT_TILT: float = num(_WORLD_LIGHT, "tilt", 100.0)
static var WORLD_LIGHT_PAN: float = num(_WORLD_LIGHT, "pan", 35.0)

## La luz de FONDO del mundo 3D y el tonemap, hermanas de las de arriba y con el
## mismo contrato: son del MUNDO, no del asset. Estaban copiadas a mano en OCHO
## sitios (entity_node, mundo_3d y seis escenas de pruebas — el banco ademas con
## 0.35 propio), asi que subir el ambiente exigia acertar ocho ediciones o la
## homologacion mentia segun que escena midiera.
##
## El AMBIENTE del display3D (defaults del XML <light>): 0xFFA5AE a 0.2 — el
## relleno rosado tenue del original. El 0.5 anterior lavaba los colores de los
## props (se veian vivos, despegados del entorno). Se conserva el tonemap
## FILMIC, que es de Godot y no del legacy, porque el lineal aplana los medios.
## Desde el 1-sep no hay horneado que recalibrar: la malla es el unico cuerpo.
static var WORLD_LIGHT_AMBIENT_COLOR: Color = color(_WORLD_LIGHT.get("ambient_color", ""), Color("ffa5ae"))
static var WORLD_LIGHT_AMBIENT: float = num(_WORLD_LIGHT, "ambient", 0.2)

## La LUZ DEL HEROE: un punto azul (0x2E7DFF, diffuse 0.6) pegado a tu propia nave,
## portado del legacy: en la escena unica vive en el mundo compartido y bania a
## las entidades cercanas con radio 450 unidades de mundo, como el original
## (la monta entity_node; solo con `luces` >= 1).
static var HERO_LIGHT_COLOR: Color = color(_HERO_LIGHT.get("color", ""), Color("2e7dff"))
static var HERO_LIGHT_ENERGY: float = num(_HERO_LIGHT, "energy", 0.6)

## MATERIAL 3D: la mitad BARATA del look "no plano", portada del material de nave del
## legacy (Away3D). Son dos cosas:
##  - ROUGHNESS: el legacy usa gloss 50 (BasicSpecularMethod) — un brillo cerrado, no
##    mate. En Godot eso es una rugosidad baja; 0.35 es el arranque (se barre en el
##    bestiario). Las mallas de Meshy vienen casi mate y uniformes, y eso es la mitad
##    de por que se ven planas: sin un brillo que recorra la forma al girar, no hay
##    volumen.
##  - RIM: el FresnelSpecularMethod del legacy (fresnelPower 5) realza el borde. En
##    Godot es `rim`; separa la silueta del negro del espacio.
## Lo que de verdad quita lo plano —la reflexion de entorno (FresnelEnvMapMethod)— NO
## esta aqui: necesita una fuente de reflexion en el viewport y va aparte.
static var MAT_ROUGHNESS: float = num(_MATERIAL, "roughness", 0.35)
static var MAT_ROUGHNESS_SCALE: float = num(_MATERIAL, "roughness_scale", 0.9)
static var MAT_METALLIC_SCALE: float = num(_MATERIAL, "metallic_scale", 0.35)
static var MAT_RIM: float = num(_MATERIAL, "rim", 0.3)
static var MAT_RIM_TINT: float = num(_MATERIAL, "rim_tint", 0.5)

## GLOW por defecto del viewport propio de un asset (`stage_3d`) cuando su JSON
## no trae el suyo — ver el comentario de ahi: se calibro con vetas finas.
static var GLOW_INTENSITY: float = num(_GLOW, "intensity", 1.0)
static var GLOW_BLOOM: float = num(_GLOW, "bloom", 0.25)
static var GLOW_THRESHOLD: float = num(_GLOW, "threshold", 0.9)

## Distancia al origen de la camara ORTOGRAFICA de medicion y encuadre
## (`stage_3d` y `view_extent` deben usar LA MISMA, o el encuadre miente).
static var MEASURE_CAM_DIST: float = num(_MEASURE_CAMERA, "distance", 8.0)


## La luz de fondo y el tonemap del mundo, aplicados a un Environment. UN solo
## sitio para los NUEVE sitios que montan un mundo 3D: cambiar el ambiente aqui
## cambia el juego, las pruebas y la homologacion a la vez, que es la unica
## manera de que sigan midiendo lo mismo.
static func world_ambient(ent: Environment) -> void:
	ent.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	ent.ambient_light_color = WORLD_LIGHT_AMBIENT_COLOR
	ent.ambient_light_energy = WORLD_LIGHT_AMBIENT
	# FILMIC y no lineal: el lineal recorta el hombro y aplana los medios — es
	# la otra mitad de "se ve mas muerto que en el visor", que tonemapea filmico.
	ent.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# CIELO DE REFLEXION (2-sep-2026): solo para el especular. El fondo sigue
	# siendo color y el ambiente el rosado plano; sin esto un metal refleja el
	# espacio negro y sale negro. Dial `reflection_sky` de lighting.json.
	if bool(_REFLECTION_SKY.get("enabled", false)):
		var mat := ProceduralSkyMaterial.new()
		mat.sky_top_color = color(_REFLECTION_SKY.get("top_color", "1c2434"))
		mat.sky_horizon_color = color(_REFLECTION_SKY.get("horizon_color", "3b2d28"))
		mat.ground_horizon_color = color(_REFLECTION_SKY.get("ground_horizon_color", "1a1412"))
		mat.ground_bottom_color = color(_REFLECTION_SKY.get("ground_color", "050608"))
		mat.sky_energy_multiplier = num(_REFLECTION_SKY, "energy", 0.6)
		mat.ground_energy_multiplier = num(_REFLECTION_SKY, "energy", 0.6)
		mat.sun_angle_max = 0.0     # el sol real es la DirectionalLight, no un disco pintado
		var sky := Sky.new()
		sky.sky_material = mat
		sky.radiance_size = Sky.RADIANCE_SIZE_64   # basta para un gradiente
		ent.sky = sky
		ent.reflected_light_source = Environment.REFLECTION_SOURCE_SKY


## El SOL del mundo 3D como nodo listo, HERMANO de ambiente_mundo(): color, energia
## y direccion en UN sitio. El sol estaba copiado suelto en cada viewport (el juego
## y sus rigs) con energia 1.0 y SIN color; el ambiente si estaba centralizado pero
## el sol no, y cada rig media contra una luz distinta. `energia` admite el override por bicho (`luz.sol` del JSON); por defecto,
## la del mundo. El banco NO usa esto a proposito: tiene sus valores de perf (2.6) y
## no es la referencia de aspecto.
static func world_sun(energy_val: float = NAN) -> DirectionalLight3D:
	# NAN = "la del mundo": el default de un parametro tiene que ser constante y
	# WORLD_LIGHT_ENERGY ya es un `static var` leido del JSON
	if is_nan(energy_val):
		energy_val = WORLD_LIGHT_ENERGY
	var sun := DirectionalLight3D.new()
	sun.light_color = WORLD_LIGHT_COLOR
	sun.light_energy = energy_val
	sun.light_specular = WORLD_LIGHT_SPECULAR
	var t := deg_to_rad(WORLD_LIGHT_TILT)
	var p := deg_to_rad(WORLD_LIGHT_PAN)
	# posicion esferica del original -> direccion hacia el origen, z espejada
	var dir := -Vector3(sin(t) * sin(p), -cos(t), sin(t) * cos(p)).normalized()
	sun.basis = Basis.looking_at(dir, Vector3.UP)
	sun.shadow_enabled = false
	return sun


static func ship(code: String) -> Dictionary:
	return _load_file(SHIPS_PATH % code)


static func npc(code: String) -> Dictionary:
	return _load_file(NPCS_PATH % code)


## Definicion de una entidad por su type_id, sea nave o alien (vacia si no existe).
static func entity(type_id: String) -> Dictionary:
	var d := ship(type_id)
	return d if not d.is_empty() else npc(type_id)


static func map_data(code: String) -> Dictionary:
	return _load_file(MAPS_PATH % code)


## Props del mundo (estacion, portal, caja...).
static func prop(code: String) -> Dictionary:
	return _load_file(PROPS_PATH % code)


## Municion por loot_id ("ammo_cel_1") o por code ("cel-1").
static func ammo(id: String) -> Dictionary:
	var code := id.trim_prefix("ammo_").replace("_", "-")
	return _load_file(AMMO_PATH % code)


## Diales del cliente por modulo: data/config/<name>.json (camera, entity, world,
## backdrop, quality, ui...). Desde el 2-sep-2026 NADA calibrable vive en el codigo:
## un numero suelto en un .gd que no sea una identidad matematica es un bug.
## Se carga una vez y se cachea; si falta el archivo se avisa y se devuelve vacio
## (los `static var` que leen de aqui caen entonces en su valor por defecto).
static func config(name: String) -> Dictionary:
	var d := _load_file(CONFIG_PATH % name)
	if d.is_empty():
		push_error("falta data/config/%s.json" % name)
	return d


## Un numero de un JSON (que siempre llega como float) como float, con defecto.
static func num(d: Dictionary, key: String, fallback: float) -> float:
	return float(d.get(key, fallback))


## Vector2 desde un JSON `[x, y]`.
static func vec2(v: Variant, fallback := Vector2.ZERO) -> Vector2:
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return fallback


## Vector3 desde un JSON `[x, y, z]`.
static func vec3(v: Variant, fallback := Vector3.ZERO) -> Vector3:
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return fallback


## Ruta del JSON de un asset por categoria (npcs/ships/props/maps/ammo) y code.
static func path_for(category: String, code: String) -> String:
	match category:
		"ships": return SHIPS_PATH % code
		"npcs": return NPCS_PATH % code
		"props": return PROPS_PATH % code
		"maps": return MAPS_PATH % code
		"ammo": return AMMO_PATH % code
	return ""


## Los codes que hay en data/<categoria>/ (nombres de archivo sin .json, sin comentarios).
static func codes_of(category: String) -> Array[String]:
	var out: Array[String] = []
	var dir := "res://data/%s" % category
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json"):
			out.append(f.trim_suffix(".json"))
	out.sort()
	return out


## Taller: pisa (o quita, con {}) el JSON de una ruta sin tocar el disco.
static func set_override(path: String, data: Dictionary) -> void:
	if data.is_empty():
		_overrides.erase(path)
	else:
		_overrides[path] = data


## Taller: relee un JSON del disco saltandose la cache (tras guardar o descartar).
## Se llama `reread` y no `reload` porque AssetDefs es un Script y `reload()` ya existe.
static func reread(path: String) -> Dictionary:
	_cache.erase(path)
	return _load_file(path)


static func _load_file(path: String) -> Dictionary:
	if _overrides.has(path):
		return _overrides[path]
	if _cache.has(path):
		return _cache[path]
	if not FileAccess.file_exists(path):
		_cache[path] = {}
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("JSON invalido: " + path)
		data = {}
	_cache[path] = data
	return data


## Convierte "00E5FF" (o "#00E5FF") a Color; blanco si falta.
static func color(hex: Variant, fallback := Color.WHITE) -> Color:
	if typeof(hex) != TYPE_STRING or (hex as String).is_empty():
		return fallback
	return Color.html(hex as String)


## El MUNDO 3D de un asset: viewport propio, entorno, la luz del mundo y una
## camara ortografica. Devuelve {vp, modelo, cam}.
##
## Vive aqui porque ya son DOS los sitios que lo montan —los bichos y naves en
## `EntityNode`, y la estacion en `world.gd`— y esta receta tiene demasiadas
## trampas para tenerla escrita dos veces. Cada linea de aqui abajo esta puesta
## por un fallo concreto que ya ocurrio, y una copia que se quede atras los
## repite todos.
##
## `lado` es el tamanio del destino en pixeles y `extension` el lado mayor del
## modelo en unidades del mundo 3D. `elevacion` en grados: 90 es cenital.
static func stage_3d(scene: PackedScene, side: int, extent: float,
		elevation: float, con_glow: bool, glow: Dictionary = {}) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = Vector2i(side, side)
	# Fondo transparente: el asset se compone sobre el mundo 2D, no lo tapa.
	vp.transparent_bg = true
	# MUNDO PROPIO, obligatorio. Sin esto los viewports comparten el World3D del
	# padre: todos los modelos viven en el mismo mundo y en el mismo origen, y
	# cada camara los ve TODOS — una bola de copias que crece segun entran mas.
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# BORRAR SIEMPRE, explicito. Sin esto el destino acumula y cada fotograma deja
	# su copia encima del anterior.
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS

	var model := scene.instantiate()
	vp.add_child(model)

	var ent := Environment.new()
	ent.background_mode = Environment.BG_CLEAR_COLOR
	world_ambient(ent)
	# GLOW: sin el, la emision se RECORTA a 1.0 y lo encendido se lee como
	# "claro" en vez de como "ignition".
	# Los valores por defecto se calibraron con las VETAS de un bicho: lineas
	# finas donde el problema era que no se leyeran como encendidas. Un asset con
	# una zona emisiva grande —el reactor de la estacion— con esos mismos numeros
	# revienta en un halo que se sale de la geometria. Por eso son ajustables por
	# asset y no una constante.
	if con_glow:
		ent.glow_enabled = true
		ent.glow_intensity = float(glow.get("intensity", GLOW_INTENSITY))
		ent.glow_bloom = float(glow.get("bloom", GLOW_BLOOM))
		ent.glow_hdr_threshold = float(glow.get("threshold", GLOW_THRESHOLD))
	var we := WorldEnvironment.new()
	we.environment = ent
	vp.add_child(we)

	# La MISMA luz del mundo que usa el relieve en 2D: si cada asset se ilumina
	# por su cuenta, dos vecinos se leen como dos recortes pegados.
	vp.add_child(world_sun())

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	# El encuadre se MIDE del modelo, nunca una constante: con una a ojo el asset
	# desborda su propio hueco.
	cam.size = extent
	vp.add_child(cam)
	var elev_rad := deg_to_rad(elevation)
	# `look_at_from_position` y no `look_at`: esto corre antes de estar en el
	# arbol. Y el "arriba" es -Z, no Y: a 90 grados la camara mira justo por Y y
	# el vector de arriba seria paralelo a su eje de vista.
	cam.look_at_from_position(
		Vector3(0.0, MEASURE_CAM_DIST * sin(elev_rad), MEASURE_CAM_DIST * cos(elev_rad)),
		Vector3.ZERO, Vector3.FORWARD)
	cam.current = true
	return {"vp": vp, "model": model, "cam": cam}


## La HUELLA del modelo —su lado mayor en el plano XZ— en unidades de su mundo.
## Se usa para encuadrar la camara cenital.
##
## No entra la altura (Y) a proposito: con una camara desde arriba lo que tiene
## que caber es la planta. Metiendo el alto, una torre como la estacion —1,92 de
## alto contra 1,05 de planta— obligaria a alejar la camara casi al doble y la
## estacion saldria diminuta dentro de su propio hueco.
##
## (`caja_3d` es la caja entera; `extension_3d` su huella, `extension_vista` lo que ve la camara.)
## Y la transformacion se acumula A MANO hasta la raiz: `transform` es solo la
## local y `global_transform` NO vale, porque esto corre antes de que el modelo
## entre en el arbol. Usarlo devuelve la identidad y suelta un error por consola
## que no detiene nada — el encuadre sale mal y el juego sigue.
static func bounds_3d(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst: MeshInstance3D = m
		var tr := Transform3D()
		var n: Node = mesh_inst
		while n != null and n != node:
			if n is Node3D:
				tr = (n as Node3D).transform * tr
			n = n.get_parent()
		var a := tr * mesh_inst.get_aabb()
		box = a if first else box.merge(a)
		first = false
	if first:
		return AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))   # sin malla: 2 de lado, como siempre
	return box


## La HUELLA del modelo (X y Z): lo que ocupa visto desde arriba.
static func extent_3d(node: Node) -> float:
	var box := bounds_3d(node)
	return maxf(maxf(box.size.x, box.size.z), 0.001)


## Lo que el modelo OCUPA EN PANTALLA con la camara a esa elevacion, en unidades
## de mundo. Es lo que hay que encuadrar cuando la camara no es cenital.
##
## `extension_3d` mide la HUELLA (X y Z) y a 90 grados eso es exactamente lo que
## se ve. En cuanto la camara baja deja de serlo: una torre de 1,92 de alto sobre
## una planta de 1,05 se sale por arriba, porque su altura pasa a proyectarse
## sobre la pantalla. Se proyectan las ocho esquinas de la caja al espacio de la
## camara y se toma el lado mayor — exacto y sin casos especiales.
static func view_extent(node: Node, elevation: float) -> float:
	var box := bounds_3d(node)
	# La misma camara que monta `mundo_3d`, para medir lo que ella va a ver.
	var elev_rad := deg_to_rad(elevation)
	var eye := Vector3(0.0, MEASURE_CAM_DIST * sin(elev_rad), MEASURE_CAM_DIST * cos(elev_rad))
	var view := Transform3D().looking_at(-eye, Vector3.FORWARD)
	view.origin = eye
	var inv := view.affine_inverse()
	var wdt := 0.0
	var hgt := 0.0
	for i in 8:
		var e := box.get_endpoint(i)
		var v := inv * e
		wdt = maxf(wdt, absf(v.x) * 2.0)
		hgt = maxf(hgt, absf(v.y) * 2.0)
	return maxf(maxf(wdt, hgt), 0.001)


## Los materiales del modelo, DUPLICADOS por instancia, para poder pulsar la
## emision de cada asset sin tocar a los demas: un material de Godot se comparte
## entre todas las instancias que lo usan.
static func materials_3d(node: Node) -> Array[BaseMaterial3D]:
	var output: Array[BaseMaterial3D] = []
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst: MeshInstance3D = m
		var mat = mesh_inst.get_active_material(0)
		if mat is BaseMaterial3D:
			var copy: BaseMaterial3D = mat.duplicate()
			# A DOS CARAS: la malla de Meshy trae el giro de las caras
			# inconsistente y con descarte trasero salen huecos donde Blender
			# enseniaba solido.
			copy.cull_mode = BaseMaterial3D.CULL_DISABLED
			# LOOK "NO PLANO" (mitad barata, portada del material de nave del legacy):
			# brillo cerrado (gloss 50 -> roughness) + fresnel de borde (fresnelPower 5
			# -> rim). Ver los dials MAT_* arriba. La reflexion de entorno va aparte.
			# CON mapa PBR (Meshy) se respeta el mapa: roughness/metallic son aqui
			# MULTIPLICADORES de la textura. Forzar 0,35 absoluto daba 0,35 x 0,47 =
			# 0,16 (espejo), y el metalico 0,6-0,9 de Meshy refleja un entorno que es
			# espacio negro: el ACI-01 salia como una bola negra sin oxido ni placas.
			if copy.roughness_texture != null:
				copy.roughness = MAT_ROUGHNESS_SCALE
			else:
				copy.roughness = MAT_ROUGHNESS
			if copy.metallic_texture != null:
				copy.metallic = MAT_METALLIC_SCALE
			copy.rim_enabled = true
			copy.rim = MAT_RIM
			copy.rim_tint = MAT_RIM_TINT
			mesh_inst.set_surface_override_material(0, copy)
			output.append(copy)
	return output
