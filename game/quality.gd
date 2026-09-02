# Autoload: niveles de calidad grafica, por SUBSISTEMA.
#
# Portado del prototipo (game/quality.gd), que a su vez replicaba el
# QualitySettings del cliente original. La idea que importa no es el interruptor
# alto/medio/bajo, sino que cada sistema pregunte por LO SUYO al dibujar:
# `Quality.nivel("engine") > 0`. Los tres presets solo mueven ese diccionario, y
# eso deja la puerta abierta a un "personalizado" sin rehacer nada.
#
# TODO ES 3D; CADA NIVEL SOLO QUITA COSTE (1-sep-2026). La escalera anterior
# venia del cliente 2D: "alta" era la malla y media/baja eran el PNG horneado
# del mismo modelo, tumbado en el plano. Con la escena unica eso no describia
# nada — un PNG cenital bajo una camara a 45 grados se ve roto, y no ahorra:
# cambia QUE es la cosa, no cuanto cuesta. Ahora una nave es siempre su malla
# y lo que baja con el nivel es lo que de verdad pesa: la resolucion del render
# 3D (la palanca grande de GPU, invisible al ojo en el primer escalon), el
# antialias, las luces dinamicas, las particulas y las capas del fondo. Lo
# que no cuesta (el pulso emisivo, la explosion) existe en todos los niveles.
#
# Se persiste en user:// y POR CUENTA: dos personas que comparten un PC guardan
# ajustes distintos, y a la vez el valor NO viaja con la cuenta a otra maquina —
# la calidad es una capacidad del equipo, no una preferencia de la partida.
extends Node

## Claves que cambiaron; quien dibuje algo afectado se reconstruye.
signal changed(keys: Array)

const PATH := "user://quality.cfg"

## Diales de la calidad: data/config/quality.json (nada calibrable vive en el
## codigo). Los numeros del JSON llegan como float y los niveles son enteros,
## de ahi las conversiones; las claves `_comentario` del JSON se descartan.
static var CFG: Dictionary = AssetDefs.config("quality")
static var _AQ: Dictionary = CFG.get("auto_quality", {})

## Que controla cada clave:
##  - render:      escala del render 3D (Viewport.scaling_3d_scale): 0 = 0,65x ·
##                 1 = 0,85x · 2 = 1x, ampliado con FSR. El 2D (HUD, ventanas)
##                 no escala nunca.
##  - aa:          MSAA del 3D: 0 ninguno · 1 = 2x · 2 = 4x (el 8-16x del
##                 original no paga en Vulkan; medido en el plan del cliente 3D).
##  - luces:       las DINAMICAS del mundo 3D (F2): 0 ninguna · 1 heroe + una
##                 de efecto · 2 heroe + el pool de 3 (el presupuesto del
##                 original, G§7.2). El sol no se apaga nunca: sin el, las
##                 mallas son siluetas.
##  - engine:      llamas: 0 solo las del heroe, a media particula (un emisor
##                 por NPC es lo unico que escala con 54 bichos; el original
##                 tambien las reservaba a HIGH) · 1 todas, a media particula ·
##                 2 todas, completas (+ estela cuando llegue, FASE 4).
##  - background:  0 solo skybox · 1 + polvo estelar (1500 quads en mosaico) ·
##                 2 + nebulosas, planetas y flares.
##  - collectable: 0 props quietos (la estacion no late) · 1 animados.
##  - explosion:   0 sin animacion de explosion · 1 con ella. Existe en los
##                 tres presets; solo la auto-calidad llega a apagarla.
##  - emissive:    0 emision fija (sin pulso ni lava) · 1 pulsando. Idem.
## (los niveles vivos son `levels`, mas abajo; arrancan en DEFAULT_PRESET)

## Los tres preajustes. BAJA es "todo lo de ALTA, mas barato" con UNA excepcion
## tomada del original: las llamas de los NPC — lo unico que escala con el
## numero de entidades. Todo lo demas es coste fijo y se ataca mejor con la
## resolucion y el antialias, que son invisibles al ojo y muy visibles al fps.
static var PRESETS: Dictionary = _presets_from(CFG.get("presets", {
	"baja":  {"render": 0, "aa": 0, "luces": 0, "engine": 0,
			  "background": 0, "collectable": 0, "explosion": 1, "emissive": 1},
	"media": {"render": 1, "aa": 1, "luces": 1, "engine": 1,
			  "background": 1, "collectable": 1, "explosion": 1, "emissive": 1},
	"alta":  {"render": 2, "aa": 2, "luces": 2, "engine": 2,
			  "background": 2, "collectable": 1, "explosion": 1, "emissive": 1},
}))

static var LABELS: Dictionary = _without_comments(CFG.get("labels",
	{"baja": "BAJA", "media": "MEDIA", "alta": "ALTA"}))

## Preajuste con el que arranca una cuenta sin ajustes guardados.
static var DEFAULT_PRESET: String = str(CFG.get("default_preset", "alta"))

## Los niveles vivos: arrancan en el preajuste por defecto.
var levels: Dictionary = (PRESETS.get(DEFAULT_PRESET, {}) as Dictionary).duplicate()

var preset: String = DEFAULT_PRESET
var _count := 0


## Un mapa clave -> nivel del JSON, con los niveles como int.
static func _int_levels(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		if str(k).begins_with("_"):
			continue
		out[k] = int(d[k])
	return out


static func _without_comments(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		if not str(k).begins_with("_"):
			out[k] = d[k]
	return out


static func _presets_from(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		if not str(k).begins_with("_"):
			out[k] = _int_levels(d[k])
	return out


static func _ladder_from(items: Array) -> Array:
	var out := []
	for step: Dictionary in items:
		out.append(_int_levels(step))
	return out

## ---- Auto-calidad por FPS (guideline 3D, §12.2 del original) ----
## Promedia el FPS en ventanas de 20 s: por debajo de 10 sube UN escalon de
## recorte; por encima de 60 baja uno — histeresis: solo recupera con holgura.
## El recorte es TRANSITORIO: se aplica como TOPE sobre los niveles del preset y
## no se persiste — el preset por cuenta no se toca, que es la leccion del
## autotest que dejaba residuo. Sin foco no se mide (una ventana de fondo con
## los fps capados no es una maquina lenta), y en autotest no corre.
static var AQ_WINDOW_SEC: float = AssetDefs.num(_AQ, "window_sec", 20.0)
static var AQ_FPS_LOW: float = AssetDefs.num(_AQ, "fps_low", 10.0)
## Cada cuantos segundos se toma una muestra de FPS.
static var AQ_SAMPLE_SEC: float = AssetDefs.num(_AQ, "sample_sec", 1.0)
## Refresco que se asume si el DisplayServer no lo reporta.
static var AQ_REFRESH_FALLBACK_HZ: float = AssetDefs.num(_AQ, "refresh_fallback_hz", 60.0)
## El original recuperaba "por encima de 60" — era un SWF sin VSync. Aqui el
## VSync (default de Godot) clava el tope al refresco del monitor, asi que la
## media NUNCA pasa de 60 y la escalera podia bajar pero jamas volver a subir
## (1-sep). Se recupera al 90 % del refresco real: holgura de verdad, no un
## numero que el VSync hace inalcanzable.
static var AQ_RAISE_FRACTION: float = AssetDefs.num(_AQ, "raise_fraction", 0.9)


func _raise_threshold() -> float:
	var hz := DisplayServer.screen_get_refresh_rate()
	return (hz if hz > 0.0 else AQ_REFRESH_FALLBACK_HZ) * AQ_RAISE_FRACTION
## La escalera de recortes, del mas barato al mas doloroso. Cada peldanio es un
## mapa de TOPES por clave; lo que no aparece no se toca. Los dos primeros
## (antialias, resolucion) no se ven; el ultimo es el que el original tambien
## reservaba para el final: sin explosiones ni pulso.
static var AQ_LADDER: Array = _ladder_from(_AQ.get("ladder", [
	{},
	{"aa": 0},
	{"aa": 0, "render": 1},
	{"aa": 0, "render": 1, "background": 1, "engine": 1},
	{"aa": 0, "render": 0, "background": 0, "engine": 0, "luces": 1},
	{"aa": 0, "render": 0, "background": 0, "engine": 0, "luces": 0,
	 "collectable": 0, "explosion": 0, "emissive": 0},
]))
var auto_reduction := 0
var _aq_accum := 0.0
var _aq_sum := 0.0
var _aq_samples := 0


func level(key: String) -> int:
	var base := int(levels.get(key, 2))
	if auto_reduction <= 0:
		return base
	var limits: Dictionary = AQ_LADDER[auto_reduction]
	return mini(base, int(limits.get(key, base)))


func _process(delta: float) -> void:
	# medir en autotest o con calidad forzada contaminaria justo lo que prueban
	if Session.autotest_mode != "" or Session.forced_quality != "":
		return
	if not get_window().has_focus():
		return
	_aq_accum += delta
	if _aq_accum < AQ_SAMPLE_SEC:
		return                      # una muestra por segundo basta
	_aq_accum = 0.0
	_aq_sum += Engine.get_frames_per_second()
	_aq_samples += 1
	if float(_aq_samples) * AQ_SAMPLE_SEC < AQ_WINDOW_SEC:
		return
	var medium := _aq_sum / float(_aq_samples)
	_aq_sum = 0.0
	_aq_samples = 0
	if medium < AQ_FPS_LOW and auto_reduction < AQ_LADDER.size() - 1:
		_reduction_at(auto_reduction + 1, medium)
	elif medium > _raise_threshold() and auto_reduction > 0:
		_reduction_at(auto_reduction - 1, medium)


func _reduction_at(fresh: int, medium: float) -> void:
	# se avisa con las claves cuyo nivel EFECTIVO cambio, para que el mundo
	# reconstruya exactamente lo que toca — el mismo cable que el cambio manual
	var before := {}
	for k in levels:
		before[k] = level(k)
	auto_reduction = fresh
	var keys := []
	for k in levels:
		if level(k) != int(before[k]):
			keys.append(k)
	print("AutoCalidad: reduccion %d (media %.0f fps)" % [auto_reduction, medium])
	if not keys.is_empty():
		changed.emit(keys)


## Carga los ajustes de esta cuenta. Se llama al entrar al mundo, no en _ready:
## antes del login no se sabe de quien son.
func load_data(tally: int) -> void:
	_count = tally
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	var saved: Variant = cfg.get_value(str(tally), "preset", "")
	if saved is String and PRESETS.has(saved):
		preset = saved
		levels = PRESETS[saved].duplicate()


## Aplica un preajuste y avisa de las claves que cambiaron. Devuelve esa lista
## para que quien llame sepa si hace falta reconstruir algo.
func apply(entry_name: String) -> Array:
	if not PRESETS.has(entry_name):
		return []
	var new_ones: Dictionary = PRESETS[entry_name]
	var keys := []
	for k in new_ones:
		if int(levels.get(k, -1)) != int(new_ones[k]):
			keys.append(k)
	levels = new_ones.duplicate()
	preset = entry_name
	_save_file()
	if not keys.is_empty():
		changed.emit(keys)
	return keys


func _save_file() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)                       # conserva los ajustes de otras cuentas
	cfg.set_value(str(_count), "preset", preset)
	cfg.save(PATH)
