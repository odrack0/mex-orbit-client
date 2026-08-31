# Traduce el JSON del mapa (data/maps/<code>.json — heredero del maps-config.xml)
# al formato que consume Fondo3D (F3). Si el mapa no tiene JSON, solo el cielo.
class_name MapBgConfig


static func para(map_code: String, world: Vector2) -> Dictionary:
	var d := AssetDefs.mapa(map_code)
	if d.is_empty():
		return {"world": world}

	var cfg := {"world": world}
	if d.has("main"):
		cfg["main"] = load(d.main)
	cfg["tiles_far"] = _tiles(d.get("tiles_far", []))
	cfg["tiles_near"] = _tiles(d.get("tiles_near", []))

	var planetas := []
	for p in d.get("planets", []):
		var ruta: String = p.get("tex", "")
		planetas.append({
			"tex": load(ruta) if ResourceLoader.exists(ruta) else null,
			"pos": Vector2(float(p.get("x", 0)), float(p.get("y", 0))),
			"p_factor": float(p.get("p_factor", 5.0)),
			"scale": float(p.get("scale", 1.0)),
		})
	cfg["planets"] = planetas

	if d.has("sun"):
		var s: Dictionary = d.sun
		cfg["sun"] = {
			"pos": Vector2(float(s.get("x", 0)), float(s.get("y", 0))),
			"p_factor": float(s.get("p_factor", 10.0)),
			"scale": float(s.get("scale", 0.9)),
			"spin": float(s.get("spin_deg_per_sec", -9.0)),
		}
	cfg["starfield_tint"] = AssetDefs.color(d.get("starfield_tint", "66F2FF"))
	cfg["starfield_tint_ratio"] = float(d.get("starfield_tint_ratio", 0.35))
	cfg["props"] = d.get("props", [])   # mallas y planos del fondo (F3+)
	# pan de camara: el original usa 25 grados en mapas con fondo 3D (su
	# display3D esta compuesto para esa camara); el JSON puede fijarlo
	cfg["pan"] = float(d.get("pan_camara", 25.0 if not (cfg.props as Array).is_empty() else 0.0))
	return cfg


static func _tiles(lista: Array) -> Array:
	var salida := []
	for t in lista:
		var e := {
			"tex": load(t.tex),
			"p_factor": float(t.get("p_factor", 6.0)),
			"scale": float(t.get("scale", 1.0)),
			"alpha": float(t.get("alpha", 1.0)),
			# atlas de variantes (F3): rejilla grid x grid con `celdas` nubes
			"celdas": int(t.get("celdas", 1)),
			"grid": int(t.get("grid", 2)),
		}
		# el tilemap del display3D original: cota absoluta, lado del tile en
		# unidades de mundo, mapScale y mascara de agujeros (blanco = nube)
		if t.has("y"):
			e["y"] = float(t.y)
		if t.has("lado"):
			e["lado"] = float(t.lado)
		if t.has("margen"):
			e["margen"] = float(t.margen)
		if t.has("mask") and ResourceLoader.exists(str(t.mask)):
			e["mask"] = load(str(t.mask))
		salida.append(e)
	return salida
