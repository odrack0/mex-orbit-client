extends SceneTree

## Lista los marcadores tobera_*/canon_* tal y como los ve GODOT tras importar el
## GLB, con su posicion ya convertida a pixeles de pantalla. El validador los lee
## del fichero; esto comprueba que ademas SOBREVIVEN al importador.
func _init() -> void:
	var raiz := (load("res://assets/ships/phoenix.glb") as PackedScene).instantiate()
	var caja := AABB()
	var primera := true
	for m in raiz.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = (m as MeshInstance3D).transform * (m as MeshInstance3D).get_aabb()
		caja = a if primera else caja.merge(a)
		primera = false
	var ext: float = maxf(caja.size.x, caja.size.z)
	var escala := 141.0 / ext
	print("extension=%.3f  escala=%.1f px/unidad" % [ext, escala])
	var n := 0
	for x in raiz.find_children("*", "Node3D", true, false):
		var nom := str(x.name)
		if nom.begins_with("tobera") or nom.begins_with("canon"):
			var p: Vector3 = (x as Node3D).position
			var es: Vector3 = (x as Node3D).scale
			print("  %-10s pantalla(%+.1f, %+.1f) px   escala=%.3f -> ancho %.1f px"
				% [nom, p.x * escala, p.z * escala, es.x, es.x * escala])
			n += 1
	print("TOTAL %d marcadores" % n)
	print("--- todos los hijos del modelo ---")
	for x in raiz.find_children("*", "", true, false):
		print("  %s (%s)" % [x.name, x.get_class()])
	quit()
