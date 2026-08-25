# Configuracion de capas de fondo por mapa: el stack del maps-config.xml del
# prototipo, con nuestros assets. Los planetas y el fondo principal definitivo
# son renders IA (prompts en mex-orbit-art/prompts/); sin textura se omiten.
class_name MapBgConfig


static func para(map_code: String, world: Vector2) -> Dictionary:
	match map_code:
		"1-1":
			return {
				"world": world,
				# capa 0 del XML: nube profunda pFactor 10, escala 2.5
				"tiles_far": [
					{"tex": load("res://assets/world/layers/dust-far.png"),
						"p_factor": 10.0, "scale": 2.5, "alpha": 0.9},
				],
				# capa 1: el fondo principal (isMain, pFactor 10)
				"main": load("res://assets/world/map-1-1.png"),
				# planetas del XML (114/115/116); sus renders llegan por prompts
				"planets": [
					{"tex": _opcional("res://assets/world/layers/planet-a.png"),
						"pos": Vector2(1110, 1100), "p_factor": 9.0, "scale": 1.0},
					{"tex": _opcional("res://assets/world/layers/planet-b.png"),
						"pos": Vector2(680, 740), "p_factor": 5.0, "scale": 1.0},
					{"tex": _opcional("res://assets/world/layers/planet-c.png"),
						"pos": Vector2(1800, 250), "p_factor": 6.0, "scale": 1.0},
				],
				# capas 3 y 4: nebulosas media (pF 6, x1.6) y cercana (pF 3, x1.8)
				"tiles_near": [
					{"tex": load("res://assets/world/layers/nebula-mid.png"),
						"p_factor": 6.0, "scale": 1.6, "alpha": 0.85},
					{"tex": load("res://assets/world/layers/nebula-near.png"),
						"p_factor": 3.0, "scale": 1.8, "alpha": 0.7},
				],
				# el sol del lensflare en (1740,1106) del espacio del fondo
				"sun": {"pos": Vector2(1740, 1106), "p_factor": 10.0},
			}
	# mapa sin configuracion: solo polvo estelar
	return {"world": world}


static func _opcional(ruta: String) -> Texture2D:
	return load(ruta) if ResourceLoader.exists(ruta) else null
