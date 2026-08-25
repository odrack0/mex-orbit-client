# Traduce el JSON del mapa (data/maps/<code>.json — heredero del maps-config.xml)
# al formato que consume MapBackground. Si el mapa no tiene JSON, solo polvo estelar.
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
	return cfg


static func _tiles(lista: Array) -> Array:
	var salida := []
	for t in lista:
		salida.append({
			"tex": load(t.tex),
			"p_factor": float(t.get("p_factor", 6.0)),
			"scale": float(t.get("scale", 1.0)),
			"alpha": float(t.get("alpha", 1.0)),
		})
	return salida
