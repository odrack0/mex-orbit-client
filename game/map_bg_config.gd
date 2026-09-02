# Traduce el JSON del mapa (data/maps/<code>.json — heredero del maps-config.xml)
# al formato que consume Fondo3D (F3). Si el mapa no tiene JSON, solo el cielo.
class_name MapBgConfig


static func for_whom(map_code: String, world: Vector2) -> Dictionary:
	var d := AssetDefs.map_data(map_code)
	if d.is_empty():
		return {"world": world}

	var cfg := {"world": world}
	if d.has("main"):
		cfg["main"] = load(d.main)
	cfg["tiles_far"] = _tiles(d.get("tiles_far", []))
	cfg["tiles_near"] = _tiles(d.get("tiles_near", []))

	var planets := []
	for p in d.get("planets", []):
		var path: String = p.get("tex", "")
		planets.append({
			"tex": load(path) if ResourceLoader.exists(path) else null,
			"pos": Vector2(float(p.get("x", 0)), float(p.get("y", 0))),
			"p_factor": float(p.get("p_factor", 5.0)),
			"scale": float(p.get("scale", 1.0)),
		})
	cfg["planets"] = planets

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
	# pan de camara en mapas con fondo 3D. El signo va INVERTIDO respecto al
	# original (nuestro mundo espeja su z y eso voltea la quiralidad del giro)
	# y la MAGNITUD esta calibrada contra el DO 3D jugado en vivo (31-ago), no
	# contra el 25 de la guia, que no reproduce lo observado. Con -5 cuadran
	# las cuatro referencias del usuario a la vez: en la base el sol queda
	# justo fuera del borde derecho (no se ve), aparece bajando en diagonal
	# hacia (4200,3500), parado en el portal queda a la derecha con aire
	# (~360 px), y el portal cae ~25-28% dentro del disco del planeta.
	# Segunda pasada en vivo: "falta recorrer planeta y sol ~5%" — un 5% de
	# pantalla son ~5 grados de pan: queda en 0.
	# El JSON puede fijarlo con pan_camara.
	cfg["pan"] = float(d.get("pan_camara", 0.0))
	return cfg


static func _tiles(items: Array) -> Array:
	var output := []
	for t in items:
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
		if t.has("side"):
			e["side"] = float(t.side)
		if t.has("margin"):
			e["margin"] = float(t.margin)
		if t.has("mask") and ResourceLoader.exists(str(t.mask)):
			e["mask"] = load(str(t.mask))
		output.append(e)
	return output
