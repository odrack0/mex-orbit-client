extends SceneTree

## Lista los marcadores tobera_*/canon_* tal y como los ve GODOT tras importar el
## GLB, con su posicion ya convertida a pixeles de pantalla. El validador los lee
## del fichero; esto comprueba que ademas SOBREVIVEN al importador.
func _init() -> void:
	var root := (load("res://assets/ships/phoenix.glb") as PackedScene).instantiate()
	var box := AABB()
	var first := true
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = (m as MeshInstance3D).transform * (m as MeshInstance3D).get_aabb()
		box = a if first else box.merge(a)
		first = false
	var ext: float = maxf(box.size.x, box.size.z)
	var scale_factor := 141.0 / ext
	print("extension=%.3f  escala=%.1f px/unidad" % [ext, scale_factor])
	var n := 0
	for x in root.find_children("*", "Node3D", true, false):
		var nm := str(x.name)
		if nm.begins_with("tobera") or nm.begins_with("canon"):
			var p: Vector3 = (x as Node3D).position
			var sc: Vector3 = (x as Node3D).scale
			print("  %-10s pantalla(%+.1f, %+.1f) px   escala=%.3f -> ancho %.1f px"
				% [nm, p.x * scale_factor, p.z * scale_factor, sc.x, sc.x * scale_factor])
			n += 1
	print("TOTAL %d marcadores" % n)
	print("--- todos los hijos del modelo ---")
	for x in root.find_children("*", "", true, false):
		print("  %s (%s)" % [x.name, x.get_class()])
	quit()
