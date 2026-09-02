# Banco de pruebas: cuantos bichos VIVOS aguanta el cliente.
#
# No es el juego: es la pregunta que decide si el pipeline de modelo unico entra
# o no. Monta N modelos girando bajo una camara ortografica en la elevacion que
# se le pida, con UNA luz direccional clavada en el mundo —la misma idea que
# AssetDefs.LUZ_MUNDO_GRADOS—, mide los fps sostenidos y se va.
#
# Uso:
#   Godot --path . tests/bench_3d.tscn -- --n=15 --elev=70 --shot=C:/ruta.png
extends Node3D

## Diales de data/config/tests.json: `bench_3d` es lo propio del banco y `common`
## lo que comparten todas las escenas de tests/ (encuadre, camara, carpeta).
static var CFG: Dictionary = AssetDefs.config("tests").get("bench_3d", {})
static var CFG_COMMON: Dictionary = AssetDefs.config("tests").get("common", {})
static var FRAME_MARGIN: float = AssetDefs.num(CFG_COMMON, "frame_margin", 1.15)
static var DEFAULT_MODEL: String = str(CFG.get("default_model", "res://tests/vexor.glb"))
static var DEFAULT_COUNT: int = int(AssetDefs.num(CFG, "default_count", 15))
static var DEFAULT_ELEVATION_DEG: float = AssetDefs.num(CFG, "default_elevation_deg", 70.0)
static var DEFAULT_SECONDS: float = AssetDefs.num(CFG, "default_seconds", 6.0)
static var DEFAULT_WARMUP_S: float = AssetDefs.num(CFG, "default_warmup_s", 2.0)
static var DEFAULT_SPIN_DEG_S: float = AssetDefs.num(CFG, "default_spin_deg_s", 100.0)
static var DEFAULT_ANIM_MODE: String = str(CFG.get("default_anim_mode", "player"))
static var DEFAULT_PULSE: String = str(CFG.get("default_pulse", "sync"))
## Rejilla, camara y luz del banco (valores de perf, no la referencia de aspecto).
static var GRID_SPACING: float = AssetDefs.num(CFG, "grid_spacing", 2.4)
static var CAMERA_DISTANCE_FACTOR: float = AssetDefs.num(CFG, "camera_distance_factor", 3.0)
static var BACKGROUND_COLOR: Color = AssetDefs.color(CFG.get("background_color"), Color("0b0d12"))
static var SUN_ENERGY: float = AssetDefs.num(CFG, "sun_energy", 2.6)
static var SUN_PITCH_DEG: float = AssetDefs.num(CFG, "sun_pitch_deg", -48.0)
static var LABEL_POS: Vector2 = AssetDefs.vec2(CFG.get("label_pos"), Vector2(16, 12))
static var LABEL_FONT_SIZE: int = int(AssetDefs.num(CFG, "label_font_size", 18))
static var LABEL_COLOR: Color = AssetDefs.color(CFG.get("label_color"), Color("d9e6ff"))
## Cada bicho gira a (base + step * (i % groups)) veces la velocidad pedida.
static var SPIN_VARIATION_BASE: float = AssetDefs.num(CFG, "spin_variation_base", 0.6)
static var SPIN_VARIATION_STEP: float = AssetDefs.num(CFG, "spin_variation_step", 0.4)
static var SPIN_VARIATION_GROUPS: int = int(AssetDefs.num(CFG, "spin_variation_groups", 3))
## Huesos de cola que se mapean y hasta que cola_N se buscan nodos en el GLB.
static var TAIL_BONES: int = int(AssetDefs.num(CFG, "tail_bones", 3))
static var TAIL_SEGMENTS_MAX: int = int(AssetDefs.num(CFG, "tail_segments_max", 8))
## Estadistica: percentil que se compara, cuando se recalcula y cada cuanto traza.
static var WORST_PERCENTILE: float = AssetDefs.num(CFG, "worst_percentile", 1.0)
static var PERCENTILE_MIN_SAMPLES: int = int(AssetDefs.num(CFG, "percentile_min_samples", 100))
static var PERCENTILE_INTERVAL_S: float = AssetDefs.num(CFG, "percentile_interval_s", 0.5)
static var TRACE_INTERVAL_S: float = AssetDefs.num(CFG, "trace_interval_s", 0.4)
static var DIAG_TRACKS_MAX: int = int(AssetDefs.num(CFG, "diag_tracks_max", 4))

var _path := DEFAULT_MODEL
var _animated := 0
## "player" = un AnimationPlayer por bicho. "directo" = se escribe el valor de la
## clave de forma desde _process, que es lo que el cliente real haria: ya mueve
## asi el gain de undulate y la intensidad del pulso.
var _anim_mode := DEFAULT_ANIM_MODE
var _meshes: Array[MeshInstance3D] = []
var _phase: PackedFloat32Array = PackedFloat32Array()
## Uno por bicho, o null. En modo "player" la fase del pulso se LEE de aqui:
## quien manda es el reproductor de la animacion, no un reloj paralelo.
var _players: Array[AnimationPlayer] = []

## "sync" = la emision late CON el aleteo, leyendo la misma fase.
## "libre" = late en su propio reloj, como hace hoy entity_node.
## "no"    = sin pulso.
##
## Hoy los dos relojes existen y NO estan acoplados: el pulso del Vexor corre a
## `speed: 3.2` (periodo 1,96 s) y su ciclo de alas dura 2,17 s, asi que se
## separan del todo cada ~21 s. Que parezca sincronizado es el ojo encontrando
## patron en dos ritmos casi iguales.
var _pulse := DEFAULT_PULSE
var _materials: Array[BaseMaterial3D] = []
## Pares [ala_izq, ala_der] por bicho, o [] si el modelo no viene partido.
var _wings: Array = []
## Cuanto se pliegan, en grados.
var WINGS_DEG: float = AssetDefs.num(CFG, "wings_deg", 34.0)

## Segmentos de cola por bicho, de la union hacia la punta.
var _tails: Array = []

## ---- esqueleto ----
## Cuando el modelo trae huesos (de riguear-modelo.py) no hay piezas que rotar:
## hay una sola malla y se mueven los HUESOS. La diferencia que importa no es de
## API sino de resultado: con piezas, un vertice pertenece entero a una y al
## rotar se abre rendija en la union; con huesos, un vertice de la bisagra pesa
## entre dos y la superficie se estira. No hay costura porque no hubo corte.
var _skeletons: Array[Skeleton3D] = []
var _bones: Array = []          # por bicho: {ala_izq, ala_der, cola_1..N} -> indice
## Que eje local mueve cada cosa. Se deja fuera porque el marco local de un hueso
## depende de como se creo y de la permutacion de ejes de glTF: es mas barato
## medirlo que razonarlo.
var _wing_axis_v := 1               # 0=X 1=Y 2=Z
var _tail_axis_v := 2
## Grados POR SEGMENTO. Se acumulan por la cadena: con 3 segmentos la punta llega
## al triple. Poco por segmento y varios segmentos se lee como algo que ondula;
## mucho en uno solo se lee como una bisagra.
var TAIL_DEG: float = AssetDefs.num(CFG, "tail_deg", 9.0)
## Un ciclo cada 1,5 s: es el `speed: 4.2` de undulate en vexor.json (2*PI/4,2).
## NO va sincronizada con las alas, igual que hoy en el sprite: son dos partes del
## cuerpo con su propio ritmo, y eso es lo que hace que se lea como bicho.
static var TAIL_CYCLE: float = AssetDefs.num(CFG, "tail_cycle", 1.50)
## Retraso de cada segmento respecto al anterior, en vueltas. Es lo que convierte
## tres rotaciones en una ONDA que viaja: sin esto la cola se mece entera de una
## pieza, como un limpiaparabrisas.
static var TAIL_PHASE: float = AssetDefs.num(CFG, "tail_phase", 0.22)
var _trace := false
var _next_trace := 0.0
## Grados por segundo que gira cada bicho. 0 los deja quietos, para mirar el
## aleteo y la cola sin que el giro los tape.
var _spin := DEFAULT_SPIN_DEG_S
var _double_sided := true
## Triangulos por bicho, contados del modelo al montarlo.
var _creature_tris := 0

## Los diales del Vexor, tal cual estan en data/npcs/vexor.json.
static var PULSE_MIN: float = AssetDefs.num(CFG, "pulse_min", 0.25)
static var PULSE_MAX: float = AssetDefs.num(CFG, "pulse_max", 2.6)
static var PULSE_SHARP: float = AssetDefs.num(CFG, "pulse_sharp", 2.4)
static var PULSE_SPEED: float = AssetDefs.num(CFG, "pulse_speed", 3.2)      # solo en modo "libre": su reloj propio
static var WINGS_CYCLE: float = AssetDefs.num(CFG, "wings_cycle", 2.17)      # 26 fotogramas a 12 fps, el atlas actual
static var WORLD_LIGHT_DEG: float = AssetDefs.num(CFG, "sun_yaw_deg", 315.0)

var _n := DEFAULT_COUNT
var _elev := DEFAULT_ELEVATION_DEG
var _shot := ""
var _seconds := DEFAULT_SECONDS

var _creatures: Array[Node3D] = []
var _label: Label
var _t := 0.0
var _fps_min := 9999.0
var _fps_sum := 0.0
var _fps_samples := 0

## Todos los tiempos de fotograma, para poder sacar percentiles. El MINIMO
## ABSOLUTO no es una estadistica: es "lo peor que he visto", y solo puede
## empeorar cuanto mas tiempo miras. En pasadas de 6 s daba 70 fps y dejando la
## ventana abierta unos minutos bajaba a 38 — sin que el juego fuera a peor, solo
## por haber visto veinte veces mas fotogramas. Lo que se compara entre pasadas
## es el 1% PEOR, que si converge.
var _dts := PackedFloat32Array()
var _p1 := 0.0
var _next_recalc := 0.0

## Un tiron visible: por debajo de 30 fps en un solo fotograma.
static var HITCH_MS: float = AssetDefs.num(CFG, "hitch_ms", 33.3)
## Frontera para separar "esto se compilo tarde" de "esto pasa siempre". El
## driver de OpenGL compila shaders la primera vez que los usa y bloquea; si
## todos los tirones caen antes de esta marca, no son del juego.
static var EARLY_S: float = AssetDefs.num(CFG, "early_s", 10.0)

var _warmup := DEFAULT_WARMUP_S
var _t_worst := 0.0
var _hitches_early := 0
var _hitches_late := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--n="):
			_n = int(arg.trim_prefix("--n="))
		elif arg.begins_with("--elev="):
			_elev = float(arg.trim_prefix("--elev="))
		elif arg.begins_with("--shot="):
			_shot = arg.trim_prefix("--shot=")
		elif arg.begins_with("--wings-axis="):
			_wing_axis_v = int(arg.trim_prefix("--wings-axis="))
		elif arg.begins_with("--tail-axis="):
			_tail_axis_v = int(arg.trim_prefix("--tail-axis="))
		elif arg.begins_with("--tail-deg="):
			TAIL_DEG = float(arg.trim_prefix("--tail-deg="))
		elif arg.begins_with("--wings-deg="):
			WINGS_DEG = float(arg.trim_prefix("--wings-deg="))
		elif arg == "--trace":
			_trace = true
		elif arg == "--single-sided":
			_double_sided = false
		elif arg.begins_with("--spin="):
			_spin = float(arg.trim_prefix("--spin="))   # grados/s; 0 = quietos
		elif arg.begins_with("--pulse="):
			_pulse = arg.trim_prefix("--pulse=")         # sync | libre | no
		elif arg.begins_with("--anim="):
			_anim_mode = arg.trim_prefix("--anim=")     # player | directo | no
		elif arg.begins_with("--model="):
			_path = arg.trim_prefix("--model=")
		elif arg.begins_with("--warmup="):
			_warmup = float(arg.trim_prefix("--warmup="))
		elif arg.begins_with("--seconds="):
			# 0 = no se cierra solo. Para mirarlo en vez de medirlo: la medida
			# sigue actualizandose en pantalla y se cierra a mano.
			_seconds = float(arg.trim_prefix("--seconds="))

	var scene: PackedScene = load(_path)
	if scene == null:
		push_error("BANCO: no se pudo cargar " + _path)
		get_tree().quit(1)
		return

	# rejilla lo mas cuadrada posible, separacion algo mayor que el bicho (1,9)
	var side := int(ceil(sqrt(float(_n))))
	var sep := GRID_SPACING
	for i in _n:
		var m := scene.instantiate()
		var row := i / side
		var col := i % side
		m.position = Vector3((col - (side - 1) * 0.5) * sep, 0.0,
			(row - (side - 1) * 0.5) * sep)
		# cada uno con su fase, para que no giren todos igual y el ojo lo note
		m.rotation.y = TAU * float(i) / float(_n)
		add_child(m)
		_creatures.append(m)
		_start_animation(m, i)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = BACKGROUND_COLOR
	# La luz de fondo del MUNDO, no una del banco: tenia un 0.35 propio y el banco
	# medias con una luz que el juego no usaba.
	AssetDefs.world_ambient(e)
	# El fondo lo pinta la CAMARA, no solo el entorno: en el renderizador de
	# compatibilidad el color del Environment no llegaba al borrado y la escena
	# salia sobre un gris azulado —el color de la luz ambiente— en vez de sobre el
	# negro del espacio.
	RenderingServer.set_default_clear_color(e.background_color)
	e.glow_enabled = true
	env.environment = e
	add_child(env)

	# La luz NO gira con los bichos: es lo unico que distingue un objeto de una
	# calcomania, y es la misma regla que ya vive en AssetDefs.
	var sun := DirectionalLight3D.new()
	sun.light_energy = SUN_ENERGY
	sun.rotation = Vector3(deg_to_rad(SUN_PITCH_DEG), deg_to_rad(WORLD_LIGHT_DEG), 0.0)
	sun.shadow_enabled = false
	add_child(sun)

	var extent := float(side) * sep
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = extent * FRAME_MARGIN
	var elev_rad := deg_to_rad(_elev)
	var d := extent * CAMERA_DISTANCE_FACTOR
	add_child(cam)
	# look_at exige estar YA en el arbol; llamarlo antes de add_child solo
	# imprime un error y deja la camara mirando a donde estaba.
	cam.position = Vector3(0.0, d * sin(elev_rad), d * cos(elev_rad))
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.current = true

	# Sin esto la medida no vale nada: con vsync el contador se queda pegado a la
	# frecuencia del monitor y "60 fps" solo significa "no bajo de 60".
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var layer_node := CanvasLayer.new()
	add_child(layer_node)
	_label = Label.new()
	_label.position = LABEL_POS
	_label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	_label.add_theme_color_override("font_color", LABEL_COLOR)
	layer_node.add_child(_label)

	var span_len := 0.0
	for ap in _players:
		if ap != null:
			span_len = ap.current_animation_length
			break
	# Los triangulos se CUENTAN del modelo, no se suponen. Estaba fijo a 15 000 por
	# bicho y llevaba media sesion mintiendo: con el asset a 10 254 o a 50 000 el
	# cartel seguia diciendo lo mismo, que es justo el tipo de numero que uno lee
	# de reojo y se cree.
	_creature_tris = 0
	for m in _meshes:
		if m.mesh != null:
			for s in m.mesh.get_surface_count():
				_creature_tris += m.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
		break
	print("BANCO n=%d elev=%.0f tris=%d (%d/bicho) modelo=%s animados=%d/%d pulso=%s ciclo=%.2fs (atlas: %.2fs)"
		% [_n, _elev, _n * _creature_tris, _creature_tris, _path.get_file(), _animated, _n,
		_pulse, span_len, WINGS_CYCLE])


func _process(delta: float) -> void:
	# El giro sirve para ver que el reflejo BARRE, pero tapa el aleteo y la cola:
	# con --spin=0 los bichos se quedan quietos y solo se mueve lo que se anima.
	if _spin > 0.0:
		for i in _creatures.size():
			_creatures[i].rotation.y += deg_to_rad(_spin) * delta * (
				SPIN_VARIATION_BASE + SPIN_VARIATION_STEP * float(i % SPIN_VARIATION_GROUPS))

	# Un ciclo de alas cada 2,17 s, que es lo que dura el atlas actual del Vexor
	# (26 fotogramas a 12 fps). Cada bicho con su fase.
	for i in _meshes.size():
		# LA FASE SALE DE QUIEN MUEVE LAS ALAS, no de un reloj paralelo. Con
		# AnimationPlayer se le pregunta a el; sin el, del reloj propio que
		# tambien mueve la clave de forma. Un reloj, dos consumidores.
		var t: float
		var ap: AnimationPlayer = _players[i] if i < _players.size() else null
		if ap != null and ap.current_animation_length > 0.0:
			t = ap.current_animation_position / ap.current_animation_length
		else:
			t = fposmod(_t / WINGS_CYCLE + _phase[i], 1.0)
		var fold := 0.5 - 0.5 * cos(TAU * t)      # 0 = alas abiertas, 1 = plegadas

		if _anim_mode == "directo" and _meshes[i].get_blend_shape_count() > 0:
			_meshes[i].set_blend_shape_value(0, fold)

		if i < _wings.size() and not _wings[i].is_empty():
			# Sobre Z, NO sobre Y. El ala tiene que girar alrededor del eje del
			# CUERPO para batir de arriba abajo, y ese eje cambia de nombre al
			# exportar: en Blender el largo va por Y, pero glTF permuta y en Godot
			# es Z (la Y de Godot es la vertical). Rotando sobre Y las alas se
			# abrian como una puerta, de atras hacia adelante.
			#
			# Y el batido es un SENO, no el mismo 0->1->0 del pliegue: un aleteo
			# oscila ALREDEDOR de la posicion de reposo, arriba y abajo. Con la
			# curva del pliegue el ala solo bajaba y volvia, que se lee como que se
			# dobla, no como que bate.
			var bat := sin(TAU * t)                       # -1 arriba .. +1 abajo
			var a: float = deg_to_rad(WINGS_DEG) * bat
			_wings[i][0].rotation.z = -a
			_wings[i][1].rotation.z = a

		# ---- esqueleto: mismas curvas, distinta manera de aplicarlas ----
		if i < _skeletons.size() and _skeletons[i] != null:
			var sk: Skeleton3D = _skeletons[i]
			var map_data: Dictionary = _bones[i]
			if _trace and i == 0 and _t > _next_trace:
				print("  ESQ  entra al bloque, mapa=%s  t=%.2f" % [map_data.keys(), t])
			var bat := sin(TAU * t)
			var a := deg_to_rad(WINGS_DEG) * bat
			_set_bone(sk, map_data, "ala_izq", _wing_axis_v, -a)
			_set_bone(sk, map_data, "ala_der", _wing_axis_v, a)
			var tc := _t / TAIL_CYCLE + _phase[i]
			for k in TAIL_BONES:
				var ang := deg_to_rad(TAIL_DEG) * sin(TAU * (tc - k * TAIL_PHASE))
				_set_bone(sk, map_data, "cola_%d" % (k + 1), _tail_axis_v, ang)

		# ---- la cola ----
		# Sobre Y, la vertical: vista desde arriba la cola serpentea de lado a
		# lado, que es lo que hace `undulate` en el sprite. Y con su propio reloj,
		# no el de las alas: en el sprite tambien son independientes.
		if i < _tails.size() and not _tails[i].is_empty():
			var tc := _t / TAIL_CYCLE + _phase[i]
			for k in _tails[i].size():
				var seg: Node3D = _tails[i][k]
				seg.rotation.y = deg_to_rad(TAIL_DEG) * sin(TAU * (tc - k * TAIL_PHASE))

		if _pulse != "no" and i < _materials.size():
			# SINCRONIZADO: la emision lee el MISMO pliegue que mueve las alas,
			# asi que el destello cae en el aleteo por construccion — no hay dos
			# relojes que puedan separarse.
			# LIBRE: reproduce lo que hace hoy entity_node, un seno con su propia
			# velocidad. Es la comparacion, no la propuesta.
			# El destello cae en el golpe de BAJADA, el punto mas bajo del batido.
			# Misma fase que mueve el ala, distinto punto de la curva: el ala usa
			# el seno y el pulso su desfase de un cuarto.
			var wave := 0.5 - 0.5 * cos(TAU * t)
			if _pulse == "libre":
				wave = 0.5 + 0.5 * sin(_t * PULSE_SPEED + _phase[i] * TAU)
			wave = pow(wave, PULSE_SHARP)   # sharpness: valles largos, pico marcado
			_materials[i].emission_energy_multiplier = (
				PULSE_MIN + (PULSE_MAX - PULSE_MIN) * wave)

	_t += delta
	# Se mide el TIEMPO DE FOTOGRAMA, no el contador de Godot: el contador es una
	# media movil y esconde justo lo que interesa, que es el peor fotograma.
	var fps := 1.0 / maxf(delta, 0.000001)
	# los dos primeros segundos no cuentan: shaders y texturas se estan calentando
	if _t > _warmup:
		_fps_sum += fps
		_fps_samples += 1
		if fps < _fps_min:
			_fps_min = fps
			_t_worst = _t          # CUANDO fue el peor dice mas que cuanto fue
		_dts.append(delta)
		if delta * 1000.0 > HITCH_MS:
			if _t < EARLY_S:
				_hitches_early += 1
			else:
				_hitches_late += 1

	# El percentil se recalcula cada medio segundo, no por fotograma: ordenar
	# miles de muestras a 100 fps seria medir el coste de medir.
	# Traza del primer bicho cada medio segundo: si el valor de la forma no se
	# mueve, no es que "no se vea" — es que no esta pasando nada.
	if _trace and _t > _next_trace and not _meshes.is_empty():
		_next_trace = _t + TRACE_INTERVAL_S
		var ap0: AnimationPlayer = _players[0] if not _players.is_empty() else null
		var wing_deg := 999.0
		var wing_height := 0.0
		if not _wings.is_empty() and not _wings[0].is_empty():
			var wing: Node3D = _wings[0][1]
			wing_deg = rad_to_deg(wing.rotation.z)
			# La ALTURA de la punta del ala en el mundo: es lo que dice si bate de
			# arriba abajo o se abre de lado. El angulo solo no lo distingue.
			var aabb := (wing as MeshInstance3D).get_aabb() if wing is MeshInstance3D else AABB()
			wing_height = (wing.global_transform * aabb.get_endpoint(7)).y
		# La punta de la COLA en X: si serpentea, esto oscila. El angulo del ultimo
		# segmento no vale — con la cadena mal encadenada tambien cambiaria.
		var tail_x := 0.0
		if not _tails.is_empty() and not _tails[0].is_empty():
			var last: Node3D = _tails[0][_tails[0].size() - 1]
			tail_x = last.global_position.x - _creatures[0].global_position.x
		print("TRAZA t=%.1f  anim_pos=%.2f  forma=%.3f  ala=%.1f deg  punta_y=%+.3f  cola_x=%+.3f  emision=%.2f" % [
			_t,
			ap0.current_animation_position if ap0 != null else -1.0,
			_meshes[0].get_blend_shape_value(0) if _meshes[0].get_blend_shape_count() > 0 else -1.0,
			wing_deg,
			wing_height,
			tail_x,
			_materials[0].emission_energy_multiplier if not _materials.is_empty() else -1.0])

	if _t > _next_recalc and _dts.size() > PERCENTILE_MIN_SAMPLES:
		_next_recalc = _t + PERCENTILE_INTERVAL_S
		_p1 = _low_percentile(WORST_PERCENTILE)

	var medium := _fps_sum / maxf(1.0, float(_fps_samples))
	_label.text = ("%d bichos vivos · %d tris · elev %.0f°\n%d fps  (media %.0f · 1%% peor %.0f · minimo %.0f en t=%.1fs)"
		+ "\ntirones >%.0f ms:  %d en los primeros %ds  ·  %d despues") % [
		_n, _n * _creature_tris, _elev, int(fps), medium, _p1, _fps_min, _t_worst,
		HITCH_MS, _hitches_early, int(EARLY_S), _hitches_late]

	# En web no se cierra: no hay a quien devolverle el codigo de salida y la
	# medida se lee de la pantalla, asi que sigue girando y actualizando.
	# Con --seconds=0 tampoco, que es el modo "mirarlo" en vez de "medirlo".
	if _seconds > 0.0 and _t >= _seconds and not OS.has_feature("web"):
		set_process(false)
		_finish(medium)


## Arranca la animacion del GLB, si la trae, DESFASADA por entidad.
##
## El desfase es el mismo truco que el pulso emisivo ya usa en entity_node
## (`entity_id * 1.7`): quince bichos aleteando al unisono se leen como un
## mecanismo, no como bichos. La diferencia es que aqui el desfase se aplica al
## RELOJ DE LA ANIMACION, que despues puede alimentar tambien la fase del pulso —
## y entonces el destello cae en el aleteo por construccion, en vez de correr en
## su propio reloj y desincronizarse cada 21 s como ahora.
func _start_animation(node: Node, i: int) -> void:
	# La FASE es una sola por bicho y la comparten el aleteo y el pulso. Ese es
	# el punto entero: mientras cada uno lleve su propio reloj, coinciden a ratos
	# y se separan solos.
	var meshes := node.find_children("*", "MeshInstance3D", true, false)
	var mesh_inst: MeshInstance3D = meshes[0] if not meshes.is_empty() else null
	if mesh_inst != null:
		_meshes.append(mesh_inst)
		_phase.append(float(i) / float(_n))
		if _pulse != "no":
			# Un material propio por bicho: la energia de emision es del
			# material, no del nodo, y compartirlo haria latir a los 150 igual.
			# Rompe el batching, y lo que eso cuesta se mide como todo lo demas.
			var m := mesh_inst.get_active_material(0)
			if m is BaseMaterial3D:
				var copy: BaseMaterial3D = m.duplicate()
				# A DOS CARAS. Blender dibuja las caras por los dos lados y Godot
				# descarta las traseras; la malla de Meshy son cientos de cascaras
				# solapadas con el giro inconsistente, asi que en Godot salian
				# huecos y esquirlas donde Blender enseniaba solido.
				if _double_sided:
					copy.cull_mode = BaseMaterial3D.CULL_DISABLED
				mesh_inst.set_surface_override_material(0, copy)
				_materials.append(copy)

	# ---- alas como NODOS ----
	# El modelo partido trae `ala_izq` y `ala_der` con su origen en la bisagra, y
	# plegarlas es rotar dos nodos. No hace falta AnimationPlayer ni clave de
	# forma: es lo mismo que el cliente ya hace con el pulso y la ondulacion,
	# movidos desde _process. Dos floats por bicho contra deltas por vertice.
	var lft := node.find_children("*ala_izq*", "Node3D", true, false)
	var rgt := node.find_children("*ala_der*", "Node3D", true, false)
	if not lft.is_empty() and not rgt.is_empty():
		_wings.append([lft[0], rgt[0]])
		if i == 0:
			print("DIAG  alas por nodo: %s en %s / %s en %s" % [
				lft[0].name, lft[0].position, rgt[0].name, rgt[0].position])
	else:
		_wings.append([])

	# ---- esqueleto, si lo trae ----
	var skels := node.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		var sk: Skeleton3D = skels[0]
		var map_data := {}
		var bone_names: Array[String] = ["ala_izq", "ala_der"]
		for k in TAIL_BONES:
			bone_names.append("cola_%d" % (k + 1))
		for entry_name in bone_names:
			var idx := sk.find_bone(entry_name)
			if idx >= 0:
				# Se guarda la rotacion de REPOSO. `set_bone_pose_rotation` fija la
				# pose entera, no un incremento: los huesos de la cola apuntan
				# hacia atras, asi que su reposo ya lleva rotacion, y escribir un
				# cuaternion "a secas" la machacaba. La malla salia aplastada SIN
				# haber rotado nada, que es lo que despisto — parecia un problema
				# de pesos y era de composicion.
				map_data[entry_name] = {"i": idx, "rest": sk.get_bone_rest(idx).basis.get_rotation_quaternion()}
		_skeletons.append(sk)
		_bones.append(map_data)
		if i == 0:
			var everything := []
			for h in sk.get_bone_count():
				everything.append(sk.get_bone_name(h))
			print("DIAG  esqueleto: %d huesos %s  ->  mapeados %s"
				% [sk.get_bone_count(), everything, map_data.keys()])
	else:
		_skeletons.append(null)
		_bones.append({})

	# La cola viene ENCADENADA en el GLB (cola_2 cuelga de cola_1), asi que basta
	# rotar cada segmento un poco: la cadena compone las rotaciones sola.
	var segments: Array = []
	for k in range(1, TAIL_SEGMENTS_MAX + 1):
		var s := node.find_children("*cola_%d" % k, "Node3D", true, false)
		if s.is_empty():
			break
		segments.append(s[0])
	_tails.append(segments)
	if i == 0 and not segments.is_empty():
		var names := ""
		for s in segments:
			names += " " + (s as Node3D).name
		print("DIAG  cola: %d segmentos —%s" % [segments.size(), names])

	if i == 0:
		# Diagnostico del primer bicho: sin esto, "no se mueve" puede ser la
		# malla sin morph, el material sin emision o la pista sin resolver, y
		# las tres se ven igual desde fuera.
		var mat := mesh_inst.get_active_material(0) if mesh_inst != null else null
		print("DIAG  malla=%s  morph=%d  material=%s  emision=%s"
			% [mesh_inst != null, mesh_inst.get_blend_shape_count() if mesh_inst else -1,
			mat.get_class() if mat else "null",
			str(mat.emission_enabled) if mat is BaseMaterial3D else "n/a"])
		if mesh_inst != null and mesh_inst.mesh != null:
			var names := []
			for b in mesh_inst.mesh.get_blend_shape_count():
				names.append(mesh_inst.mesh.get_blend_shape_name(b))
			print("DIAG  formas=%s" % str(names))

	_players.append(null)
	if _anim_mode == "no":
		return
	var players := node.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var ap: AnimationPlayer = players[0]
	if ap.get_animation_list().is_empty():
		return

	if _anim_mode == "directo":
		# El AnimationPlayer sobra: la animacion es UN numero entre 0 y 1. Se
		# apaga el nodo y se escribe la clave de forma a mano en _process.
		ap.process_mode = Node.PROCESS_MODE_DISABLED
		_animated += 1
		return

	var entry_name := ap.get_animation_list()[0]
	# glTF no tiene bandera de bucle, asi que Godot importa con LOOP_NONE y
	# play() reproduce UNA vez. Sin esto el bicho aletea dos segundos mientras la
	# ventana aparece y se queda congelado para siempre — que se lee exactamente
	# igual que "la animacion no funciona".
	ap.get_animation(entry_name).loop_mode = Animation.LOOP_LINEAR
	if i == 0:
		var anim := ap.get_animation(entry_name)
		print("DIAG  anim='%s' largo=%.2fs pistas=%d" % [entry_name, anim.length, anim.get_track_count()])
		for k in mini(DIAG_TRACKS_MAX, anim.get_track_count()):
			print("DIAG    pista %d  tipo=%d  ruta=%s  claves=%d"
				% [k, anim.track_get_type(k), str(anim.track_get_path(k)), anim.track_get_key_count(k)])
	ap.play(entry_name)
	ap.seek(ap.current_animation_length * float(i) / float(_n), true)
	_players[_players.size() - 1] = ap
	_animated += 1


## Rota un hueso COMPONIENDO sobre su reposo, no sustituyendolo.
func _set_bone(sk: Skeleton3D, map_data: Dictionary, entry_name: String, axis: int, ang: float) -> void:
	if not map_data.has(entry_name):
		return
	var h: Dictionary = map_data[entry_name]
	var q: Quaternion = (h["rest"] as Quaternion) * _spin_axis(axis, ang)
	sk.set_bone_pose_rotation(h["i"], q)
	if _trace and entry_name == "cola_1" and _t > _next_trace:
		var read_rot := sk.get_bone_pose_rotation(h["i"])
		print("  HUESO cola_1 idx=%d  ang=%.1f deg  puesta=%s  leida=%s  igual=%s"
			% [h["i"], rad_to_deg(ang), str(q).substr(0, 28), str(read_rot).substr(0, 28),
			q.is_equal_approx(read_rot)])


## Cuaternion de giro alrededor de un eje local por indice (0=X 1=Y 2=Z).
func _spin_axis(axis: int, ang: float) -> Quaternion:
	var v := Vector3.RIGHT
	if axis == 1:
		v = Vector3.UP
	elif axis == 2:
		v = Vector3.BACK
	return Quaternion(v, ang)


## Media del PEOR `pct`% de fotogramas, en fps. Es la cifra que se compara entre
## pasadas: el minimo absoluto lo decide un hipo suelto —otro proceso, el reloj
## de la GPU— y no dice nada de como va el juego.
func _low_percentile(pct: float) -> float:
	var ordered := _dts.duplicate()
	ordered.sort()
	var count := maxi(1, int(float(ordered.size()) * pct / 100.0))
	var total := 0.0
	for i in count:
		total += ordered[ordered.size() - 1 - i]   # los mas LARGOS = los peores
	return float(count) / total


func _finish(medium: float) -> void:
	await RenderingServer.frame_post_draw
	if _shot != "":
		get_viewport().get_texture().get_image().save_png(_shot)
	print("RESULTADO n=%d elev=%.0f media=%.1f  1%%peor=%.1f  minimo=%.1f (t=%.1fs)  tirones=%d/%d pronto/tarde"
		% [_n, _elev, medium, _low_percentile(WORST_PERCENTILE), _fps_min, _t_worst,
		_hitches_early, _hitches_late])
	get_tree().quit(0)
