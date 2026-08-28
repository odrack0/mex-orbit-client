# Banco de pruebas: cuantos bichos VIVOS aguanta el cliente.
#
# No es el juego: es la pregunta que decide si el pipeline de modelo unico entra
# o no. Monta N modelos girando bajo una camara ortografica en la elevacion que
# se le pida, con UNA luz direccional clavada en el mundo —la misma idea que
# AssetDefs.LUZ_MUNDO_GRADOS—, mide los fps sostenidos y se va.
#
# Uso:
#   Godot --path . pruebas/banco_3d.tscn -- --n=15 --elev=70 --shot=C:/ruta.png
extends Node3D

var _ruta := "res://pruebas/vexor.glb"
var _animados := 0
## "player" = un AnimationPlayer por bicho. "directo" = se escribe el valor de la
## clave de forma desde _process, que es lo que el cliente real haria: ya mueve
## asi el gain de undulate y la intensidad del pulso.
var _modo_anim := "player"
var _mallas: Array[MeshInstance3D] = []
var _fase: PackedFloat32Array = PackedFloat32Array()
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
var _pulso := "sync"
var _materiales: Array[BaseMaterial3D] = []
## Pares [ala_izq, ala_der] por bicho, o [] si el modelo no viene partido.
var _alas: Array = []
## Cuanto se pliegan, en grados.
var ALAS_GRADOS := 34.0

## Segmentos de cola por bicho, de la union hacia la punta.
var _colas: Array = []

## ---- esqueleto ----
## Cuando el modelo trae huesos (de riguear-modelo.py) no hay piezas que rotar:
## hay una sola malla y se mueven los HUESOS. La diferencia que importa no es de
## API sino de resultado: con piezas, un vertice pertenece entero a una y al
## rotar se abre rendija en la union; con huesos, un vertice de la bisagra pesa
## entre dos y la superficie se estira. No hay costura porque no hubo corte.
var _esqueletos: Array[Skeleton3D] = []
var _huesos: Array = []          # por bicho: {ala_izq, ala_der, cola_1..N} -> indice
## Que eje local mueve cada cosa. Se deja fuera porque el marco local de un hueso
## depende de como se creo y de la permutacion de ejes de glTF: es mas barato
## medirlo que razonarlo.
var _eje_alas := 1               # 0=X 1=Y 2=Z
var _eje_cola := 2
## Grados POR SEGMENTO. Se acumulan por la cadena: con 3 segmentos la punta llega
## al triple. Poco por segmento y varios segmentos se lee como algo que ondula;
## mucho en uno solo se lee como una bisagra.
var COLA_GRADOS := 9.0
## Un ciclo cada 1,5 s: es el `speed: 4.2` de undulate en vexor.json (2*PI/4,2).
## NO va sincronizada con las alas, igual que hoy en el sprite: son dos partes del
## cuerpo con su propio ritmo, y eso es lo que hace que se lea como bicho.
const COLA_CICLO := 1.50
## Retraso de cada segmento respecto al anterior, en vueltas. Es lo que convierte
## tres rotaciones en una ONDA que viaja: sin esto la cola se mece entera de una
## pieza, como un limpiaparabrisas.
const COLA_DESFASE := 0.22
var _traza := false
var _proxima_traza := 0.0
## Grados por segundo que gira cada bicho. 0 los deja quietos, para mirar el
## aleteo y la cola sin que el giro los tape.
var _giro := 100.0
var _doble_cara := true
## Triangulos por bicho, contados del modelo al montarlo.
var _tris_bicho := 0

## Los diales del Vexor, tal cual estan en data/npcs/vexor.json.
const PULSO_MIN := 0.25
const PULSO_MAX := 2.6
const PULSO_SHARP := 2.4
const PULSO_SPEED := 3.2      # solo en modo "libre": su reloj propio
const CICLO_ALAS := 2.17      # 26 fotogramas a 12 fps, el atlas actual
const LUZ_MUNDO_GRADOS := 315.0

var _n := 15
var _elev := 70.0
var _shot := ""
var _segundos := 6.0

var _bichos: Array[Node3D] = []
var _label: Label
var _t := 0.0
var _fps_min := 9999.0
var _fps_suma := 0.0
var _fps_muestras := 0

## Todos los tiempos de fotograma, para poder sacar percentiles. El MINIMO
## ABSOLUTO no es una estadistica: es "lo peor que he visto", y solo puede
## empeorar cuanto mas tiempo miras. En pasadas de 6 s daba 70 fps y dejando la
## ventana abierta unos minutos bajaba a 38 — sin que el juego fuera a peor, solo
## por haber visto veinte veces mas fotogramas. Lo que se compara entre pasadas
## es el 1% PEOR, que si converge.
var _dts := PackedFloat32Array()
var _p1 := 0.0
var _proximo_recalculo := 0.0

## Un tiron visible: por debajo de 30 fps en un solo fotograma.
const TIRON_MS := 33.3
## Frontera para separar "esto se compilo tarde" de "esto pasa siempre". El
## driver de OpenGL compila shaders la primera vez que los usa y bloquea; si
## todos los tirones caen antes de esta marca, no son del juego.
const PRONTO_S := 10.0

var _calentamiento := 2.0
var _t_peor := 0.0
var _tirones_pronto := 0
var _tirones_tarde := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--n="):
			_n = int(arg.trim_prefix("--n="))
		elif arg.begins_with("--elev="):
			_elev = float(arg.trim_prefix("--elev="))
		elif arg.begins_with("--shot="):
			_shot = arg.trim_prefix("--shot=")
		elif arg.begins_with("--eje-alas="):
			_eje_alas = int(arg.trim_prefix("--eje-alas="))
		elif arg.begins_with("--eje-cola="):
			_eje_cola = int(arg.trim_prefix("--eje-cola="))
		elif arg.begins_with("--cola-grados="):
			COLA_GRADOS = float(arg.trim_prefix("--cola-grados="))
		elif arg.begins_with("--alas-grados="):
			ALAS_GRADOS = float(arg.trim_prefix("--alas-grados="))
		elif arg == "--traza":
			_traza = true
		elif arg == "--una-cara":
			_doble_cara = false
		elif arg.begins_with("--giro="):
			_giro = float(arg.trim_prefix("--giro="))   # grados/s; 0 = quietos
		elif arg.begins_with("--pulso="):
			_pulso = arg.trim_prefix("--pulso=")         # sync | libre | no
		elif arg.begins_with("--anim="):
			_modo_anim = arg.trim_prefix("--anim=")     # player | directo | no
		elif arg.begins_with("--modelo="):
			_ruta = arg.trim_prefix("--modelo=")
		elif arg.begins_with("--calentamiento="):
			_calentamiento = float(arg.trim_prefix("--calentamiento="))
		elif arg.begins_with("--segundos="):
			# 0 = no se cierra solo. Para mirarlo en vez de medirlo: la medida
			# sigue actualizandose en pantalla y se cierra a mano.
			_segundos = float(arg.trim_prefix("--segundos="))

	var escena: PackedScene = load(_ruta)
	if escena == null:
		push_error("BANCO: no se pudo cargar " + _ruta)
		get_tree().quit(1)
		return

	# rejilla lo mas cuadrada posible, separacion algo mayor que el bicho (1,9)
	var lado := int(ceil(sqrt(float(_n))))
	var sep := 2.4
	for i in _n:
		var m := escena.instantiate()
		var fila := i / lado
		var col := i % lado
		m.position = Vector3((col - (lado - 1) * 0.5) * sep, 0.0,
			(fila - (lado - 1) * 0.5) * sep)
		# cada uno con su fase, para que no giren todos igual y el ojo lo note
		m.rotation.y = TAU * float(i) / float(_n)
		add_child(m)
		_bichos.append(m)
		_arrancar_animacion(m, i)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.043, 0.051, 0.071)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.40, 0.55)
	e.ambient_light_energy = 0.35
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
	var sol := DirectionalLight3D.new()
	sol.light_energy = 2.6
	sol.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(LUZ_MUNDO_GRADOS), 0.0)
	sol.shadow_enabled = false
	add_child(sol)

	var extension := float(lado) * sep
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = extension * 1.15
	var el := deg_to_rad(_elev)
	var d := extension * 3.0
	add_child(cam)
	# look_at exige estar YA en el arbol; llamarlo antes de add_child solo
	# imprime un error y deja la camara mirando a donde estaba.
	cam.position = Vector3(0.0, d * sin(el), d * cos(el))
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.current = true

	# Sin esto la medida no vale nada: con vsync el contador se queda pegado a la
	# frecuencia del monitor y "60 fps" solo significa "no bajo de 60".
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var capa := CanvasLayer.new()
	add_child(capa)
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.85, 0.90, 1.0))
	capa.add_child(_label)

	var largo := 0.0
	for ap in _players:
		if ap != null:
			largo = ap.current_animation_length
			break
	# Los triangulos se CUENTAN del modelo, no se suponen. Estaba fijo a 15 000 por
	# bicho y llevaba media sesion mintiendo: con el asset a 10 254 o a 50 000 el
	# cartel seguia diciendo lo mismo, que es justo el tipo de numero que uno lee
	# de reojo y se cree.
	_tris_bicho = 0
	for m in _mallas:
		if m.mesh != null:
			for s in m.mesh.get_surface_count():
				_tris_bicho += m.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
		break
	print("BANCO n=%d elev=%.0f tris=%d (%d/bicho) modelo=%s animados=%d/%d pulso=%s ciclo=%.2fs (atlas: %.2fs)"
		% [_n, _elev, _n * _tris_bicho, _tris_bicho, _ruta.get_file(), _animados, _n,
		_pulso, largo, CICLO_ALAS])


func _process(delta: float) -> void:
	# El giro sirve para ver que el reflejo BARRE, pero tapa el aleteo y la cola:
	# con --giro=0 los bichos se quedan quietos y solo se mueve lo que se anima.
	if _giro > 0.0:
		for i in _bichos.size():
			_bichos[i].rotation.y += deg_to_rad(_giro) * delta * (0.6 + 0.4 * float(i % 3))

	# Un ciclo de alas cada 2,17 s, que es lo que dura el atlas actual del Vexor
	# (26 fotogramas a 12 fps). Cada bicho con su fase.
	for i in _mallas.size():
		# LA FASE SALE DE QUIEN MUEVE LAS ALAS, no de un reloj paralelo. Con
		# AnimationPlayer se le pregunta a el; sin el, del reloj propio que
		# tambien mueve la clave de forma. Un reloj, dos consumidores.
		var t: float
		var ap: AnimationPlayer = _players[i] if i < _players.size() else null
		if ap != null and ap.current_animation_length > 0.0:
			t = ap.current_animation_position / ap.current_animation_length
		else:
			t = fposmod(_t / CICLO_ALAS + _fase[i], 1.0)
		var pliegue := 0.5 - 0.5 * cos(TAU * t)      # 0 = alas abiertas, 1 = plegadas

		if _modo_anim == "directo" and _mallas[i].get_blend_shape_count() > 0:
			_mallas[i].set_blend_shape_value(0, pliegue)

		if i < _alas.size() and not _alas[i].is_empty():
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
			var a: float = deg_to_rad(ALAS_GRADOS) * bat
			_alas[i][0].rotation.z = -a
			_alas[i][1].rotation.z = a

		# ---- esqueleto: mismas curvas, distinta manera de aplicarlas ----
		if i < _esqueletos.size() and _esqueletos[i] != null:
			var sk: Skeleton3D = _esqueletos[i]
			var mapa: Dictionary = _huesos[i]
			if _traza and i == 0 and _t > _proxima_traza:
				print("  ESQ  entra al bloque, mapa=%s  t=%.2f" % [mapa.keys(), t])
			var bat := sin(TAU * t)
			var a := deg_to_rad(ALAS_GRADOS) * bat
			_poner_hueso(sk, mapa, "ala_izq", _eje_alas, -a)
			_poner_hueso(sk, mapa, "ala_der", _eje_alas, a)
			var tc := _t / COLA_CICLO + _fase[i]
			for k in 3:
				var ang := deg_to_rad(COLA_GRADOS) * sin(TAU * (tc - k * COLA_DESFASE))
				_poner_hueso(sk, mapa, "cola_%d" % (k + 1), _eje_cola, ang)

		# ---- la cola ----
		# Sobre Y, la vertical: vista desde arriba la cola serpentea de lado a
		# lado, que es lo que hace `undulate` en el sprite. Y con su propio reloj,
		# no el de las alas: en el sprite tambien son independientes.
		if i < _colas.size() and not _colas[i].is_empty():
			var tc := _t / COLA_CICLO + _fase[i]
			for k in _colas[i].size():
				var seg: Node3D = _colas[i][k]
				seg.rotation.y = deg_to_rad(COLA_GRADOS) * sin(TAU * (tc - k * COLA_DESFASE))

		if _pulso != "no" and i < _materiales.size():
			# SINCRONIZADO: la emision lee el MISMO pliegue que mueve las alas,
			# asi que el destello cae en el aleteo por construccion — no hay dos
			# relojes que puedan separarse.
			# LIBRE: reproduce lo que hace hoy entity_node, un seno con su propia
			# velocidad. Es la comparacion, no la propuesta.
			# El destello cae en el golpe de BAJADA, el punto mas bajo del batido.
			# Misma fase que mueve el ala, distinto punto de la curva: el ala usa
			# el seno y el pulso su desfase de un cuarto.
			var onda := 0.5 - 0.5 * cos(TAU * t)
			if _pulso == "libre":
				onda = 0.5 + 0.5 * sin(_t * PULSO_SPEED + _fase[i] * TAU)
			onda = pow(onda, PULSO_SHARP)   # sharpness: valles largos, pico marcado
			_materiales[i].emission_energy_multiplier = (
				PULSO_MIN + (PULSO_MAX - PULSO_MIN) * onda)

	_t += delta
	# Se mide el TIEMPO DE FOTOGRAMA, no el contador de Godot: el contador es una
	# media movil y esconde justo lo que interesa, que es el peor fotograma.
	var fps := 1.0 / maxf(delta, 0.000001)
	# los dos primeros segundos no cuentan: shaders y texturas se estan calentando
	if _t > _calentamiento:
		_fps_suma += fps
		_fps_muestras += 1
		if fps < _fps_min:
			_fps_min = fps
			_t_peor = _t          # CUANDO fue el peor dice mas que cuanto fue
		_dts.append(delta)
		if delta * 1000.0 > TIRON_MS:
			if _t < PRONTO_S:
				_tirones_pronto += 1
			else:
				_tirones_tarde += 1

	# El percentil se recalcula cada medio segundo, no por fotograma: ordenar
	# miles de muestras a 100 fps seria medir el coste de medir.
	# Traza del primer bicho cada medio segundo: si el valor de la forma no se
	# mueve, no es que "no se vea" — es que no esta pasando nada.
	if _traza and _t > _proxima_traza and not _mallas.is_empty():
		_proxima_traza = _t + 0.4
		var ap0: AnimationPlayer = _players[0] if not _players.is_empty() else null
		var ala_deg := 999.0
		var ala_alto := 0.0
		if not _alas.is_empty() and not _alas[0].is_empty():
			var ala: Node3D = _alas[0][1]
			ala_deg = rad_to_deg(ala.rotation.z)
			# La ALTURA de la punta del ala en el mundo: es lo que dice si bate de
			# arriba abajo o se abre de lado. El angulo solo no lo distingue.
			var aabb := (ala as MeshInstance3D).get_aabb() if ala is MeshInstance3D else AABB()
			ala_alto = (ala.global_transform * aabb.get_endpoint(7)).y
		# La punta de la COLA en X: si serpentea, esto oscila. El angulo del ultimo
		# segmento no vale — con la cadena mal encadenada tambien cambiaria.
		var cola_x := 0.0
		if not _colas.is_empty() and not _colas[0].is_empty():
			var ult: Node3D = _colas[0][_colas[0].size() - 1]
			cola_x = ult.global_position.x - _bichos[0].global_position.x
		print("TRAZA t=%.1f  anim_pos=%.2f  forma=%.3f  ala=%.1f deg  punta_y=%+.3f  cola_x=%+.3f  emision=%.2f" % [
			_t,
			ap0.current_animation_position if ap0 != null else -1.0,
			_mallas[0].get_blend_shape_value(0) if _mallas[0].get_blend_shape_count() > 0 else -1.0,
			ala_deg,
			ala_alto,
			cola_x,
			_materiales[0].emission_energy_multiplier if not _materiales.is_empty() else -1.0])

	if _t > _proximo_recalculo and _dts.size() > 100:
		_proximo_recalculo = _t + 0.5
		_p1 = _percentil_bajo(1.0)

	var media := _fps_suma / maxf(1.0, float(_fps_muestras))
	_label.text = ("%d bichos vivos · %d tris · elev %.0f°\n%d fps  (media %.0f · 1%% peor %.0f · minimo %.0f en t=%.1fs)"
		+ "\ntirones >%.0f ms:  %d en los primeros %ds  ·  %d despues") % [
		_n, _n * _tris_bicho, _elev, int(fps), media, _p1, _fps_min, _t_peor,
		TIRON_MS, _tirones_pronto, int(PRONTO_S), _tirones_tarde]

	# En web no se cierra: no hay a quien devolverle el codigo de salida y la
	# medida se lee de la pantalla, asi que sigue girando y actualizando.
	# Con --segundos=0 tampoco, que es el modo "mirarlo" en vez de "medirlo".
	if _segundos > 0.0 and _t >= _segundos and not OS.has_feature("web"):
		set_process(false)
		_terminar(media)


## Arranca la animacion del GLB, si la trae, DESFASADA por entidad.
##
## El desfase es el mismo truco que el pulso emisivo ya usa en entity_node
## (`entity_id * 1.7`): quince bichos aleteando al unisono se leen como un
## mecanismo, no como bichos. La diferencia es que aqui el desfase se aplica al
## RELOJ DE LA ANIMACION, que despues puede alimentar tambien la fase del pulso —
## y entonces el destello cae en el aleteo por construccion, en vez de correr en
## su propio reloj y desincronizarse cada 21 s como ahora.
func _arrancar_animacion(nodo: Node, i: int) -> void:
	# La FASE es una sola por bicho y la comparten el aleteo y el pulso. Ese es
	# el punto entero: mientras cada uno lleve su propio reloj, coinciden a ratos
	# y se separan solos.
	var mallas := nodo.find_children("*", "MeshInstance3D", true, false)
	var malla: MeshInstance3D = mallas[0] if not mallas.is_empty() else null
	if malla != null:
		_mallas.append(malla)
		_fase.append(float(i) / float(_n))
		if _pulso != "no":
			# Un material propio por bicho: la energia de emision es del
			# material, no del nodo, y compartirlo haria latir a los 150 igual.
			# Rompe el batching, y lo que eso cuesta se mide como todo lo demas.
			var m := malla.get_active_material(0)
			if m is BaseMaterial3D:
				var copia: BaseMaterial3D = m.duplicate()
				# A DOS CARAS. Blender dibuja las caras por los dos lados y Godot
				# descarta las traseras; la malla de Meshy son cientos de cascaras
				# solapadas con el giro inconsistente, asi que en Godot salian
				# huecos y esquirlas donde Blender enseniaba solido.
				if _doble_cara:
					copia.cull_mode = BaseMaterial3D.CULL_DISABLED
				malla.set_surface_override_material(0, copia)
				_materiales.append(copia)

	# ---- alas como NODOS ----
	# El modelo partido trae `ala_izq` y `ala_der` con su origen en la bisagra, y
	# plegarlas es rotar dos nodos. No hace falta AnimationPlayer ni clave de
	# forma: es lo mismo que el cliente ya hace con el pulso y la ondulacion,
	# movidos desde _process. Dos floats por bicho contra deltas por vertice.
	var izq := nodo.find_children("*ala_izq*", "Node3D", true, false)
	var der := nodo.find_children("*ala_der*", "Node3D", true, false)
	if not izq.is_empty() and not der.is_empty():
		_alas.append([izq[0], der[0]])
		if i == 0:
			print("DIAG  alas por nodo: %s en %s / %s en %s" % [
				izq[0].name, izq[0].position, der[0].name, der[0].position])
	else:
		_alas.append([])

	# ---- esqueleto, si lo trae ----
	var esqs := nodo.find_children("*", "Skeleton3D", true, false)
	if not esqs.is_empty():
		var sk: Skeleton3D = esqs[0]
		var mapa := {}
		for nombre in ["ala_izq", "ala_der", "cola_1", "cola_2", "cola_3"]:
			var idx := sk.find_bone(nombre)
			if idx >= 0:
				# Se guarda la rotacion de REPOSO. `set_bone_pose_rotation` fija la
				# pose entera, no un incremento: los huesos de la cola apuntan
				# hacia atras, asi que su reposo ya lleva rotacion, y escribir un
				# cuaternion "a secas" la machacaba. La malla salia aplastada SIN
				# haber rotado nada, que es lo que despisto — parecia un problema
				# de pesos y era de composicion.
				mapa[nombre] = {"i": idx, "rest": sk.get_bone_rest(idx).basis.get_rotation_quaternion()}
		_esqueletos.append(sk)
		_huesos.append(mapa)
		if i == 0:
			var todos := []
			for h in sk.get_bone_count():
				todos.append(sk.get_bone_name(h))
			print("DIAG  esqueleto: %d huesos %s  ->  mapeados %s"
				% [sk.get_bone_count(), todos, mapa.keys()])
	else:
		_esqueletos.append(null)
		_huesos.append({})

	# La cola viene ENCADENADA en el GLB (cola_2 cuelga de cola_1), asi que basta
	# rotar cada segmento un poco: la cadena compone las rotaciones sola.
	var segmentos: Array = []
	for k in range(1, 9):
		var s := nodo.find_children("*cola_%d" % k, "Node3D", true, false)
		if s.is_empty():
			break
		segmentos.append(s[0])
	_colas.append(segmentos)
	if i == 0 and not segmentos.is_empty():
		var nombres := ""
		for s in segmentos:
			nombres += " " + (s as Node3D).name
		print("DIAG  cola: %d segmentos —%s" % [segmentos.size(), nombres])

	if i == 0:
		# Diagnostico del primer bicho: sin esto, "no se mueve" puede ser la
		# malla sin morph, el material sin emision o la pista sin resolver, y
		# las tres se ven igual desde fuera.
		var mat := malla.get_active_material(0) if malla != null else null
		print("DIAG  malla=%s  morph=%d  material=%s  emision=%s"
			% [malla != null, malla.get_blend_shape_count() if malla else -1,
			mat.get_class() if mat else "null",
			str(mat.emission_enabled) if mat is BaseMaterial3D else "n/a"])
		if malla != null and malla.mesh != null:
			var nombres := []
			for b in malla.mesh.get_blend_shape_count():
				nombres.append(malla.mesh.get_blend_shape_name(b))
			print("DIAG  formas=%s" % str(nombres))

	_players.append(null)
	if _modo_anim == "no":
		return
	var players := nodo.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var ap: AnimationPlayer = players[0]
	if ap.get_animation_list().is_empty():
		return

	if _modo_anim == "directo":
		# El AnimationPlayer sobra: la animacion es UN numero entre 0 y 1. Se
		# apaga el nodo y se escribe la clave de forma a mano en _process.
		ap.process_mode = Node.PROCESS_MODE_DISABLED
		_animados += 1
		return

	var nombre := ap.get_animation_list()[0]
	# glTF no tiene bandera de bucle, asi que Godot importa con LOOP_NONE y
	# play() reproduce UNA vez. Sin esto el bicho aletea dos segundos mientras la
	# ventana aparece y se queda congelado para siempre — que se lee exactamente
	# igual que "la animacion no funciona".
	ap.get_animation(nombre).loop_mode = Animation.LOOP_LINEAR
	if i == 0:
		var anim := ap.get_animation(nombre)
		print("DIAG  anim='%s' largo=%.2fs pistas=%d" % [nombre, anim.length, anim.get_track_count()])
		for k in mini(4, anim.get_track_count()):
			print("DIAG    pista %d  tipo=%d  ruta=%s  claves=%d"
				% [k, anim.track_get_type(k), str(anim.track_get_path(k)), anim.track_get_key_count(k)])
	ap.play(nombre)
	ap.seek(ap.current_animation_length * float(i) / float(_n), true)
	_players[_players.size() - 1] = ap
	_animados += 1


## Rota un hueso COMPONIENDO sobre su reposo, no sustituyendolo.
func _poner_hueso(sk: Skeleton3D, mapa: Dictionary, nombre: String, eje: int, ang: float) -> void:
	if not mapa.has(nombre):
		return
	var h: Dictionary = mapa[nombre]
	var q: Quaternion = (h["rest"] as Quaternion) * _giro_eje(eje, ang)
	sk.set_bone_pose_rotation(h["i"], q)
	if _traza and nombre == "cola_1" and _t > _proxima_traza:
		var leida := sk.get_bone_pose_rotation(h["i"])
		print("  HUESO cola_1 idx=%d  ang=%.1f deg  puesta=%s  leida=%s  igual=%s"
			% [h["i"], rad_to_deg(ang), str(q).substr(0, 28), str(leida).substr(0, 28),
			q.is_equal_approx(leida)])


## Cuaternion de giro alrededor de un eje local por indice (0=X 1=Y 2=Z).
func _giro_eje(eje: int, ang: float) -> Quaternion:
	var v := Vector3.RIGHT
	if eje == 1:
		v = Vector3.UP
	elif eje == 2:
		v = Vector3.BACK
	return Quaternion(v, ang)


## Media del PEOR `pct`% de fotogramas, en fps. Es la cifra que se compara entre
## pasadas: el minimo absoluto lo decide un hipo suelto —otro proceso, el reloj
## de la GPU— y no dice nada de como va el juego.
func _percentil_bajo(pct: float) -> float:
	var ordenados := _dts.duplicate()
	ordenados.sort()
	var cuantos := maxi(1, int(float(ordenados.size()) * pct / 100.0))
	var suma := 0.0
	for i in cuantos:
		suma += ordenados[ordenados.size() - 1 - i]   # los mas LARGOS = los peores
	return float(cuantos) / suma


func _terminar(media: float) -> void:
	await RenderingServer.frame_post_draw
	if _shot != "":
		get_viewport().get_texture().get_image().save_png(_shot)
	print("RESULTADO n=%d elev=%.0f media=%.1f  1%%peor=%.1f  minimo=%.1f (t=%.1fs)  tirones=%d/%d pronto/tarde"
		% [_n, _elev, media, _percentil_bajo(1.0), _fps_min, _t_peor,
		_tirones_pronto, _tirones_tarde])
	get_tree().quit(0)
