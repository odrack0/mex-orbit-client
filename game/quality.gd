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
signal cambiada(claves: Array)

const RUTA := "user://quality.cfg"

## Que controla cada clave:
##  - render:      escala del render 3D (Viewport.scaling_3d_scale): 0 = 0,5x ·
##                 1 = 0,75x · 2 = 1x. El 2D (HUD, ventanas) no escala nunca.
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
var niveles := {
	"render": 2, "aa": 2, "luces": 2, "engine": 2,
	"background": 2, "collectable": 1, "explosion": 1, "emissive": 1,
}

## Los tres preajustes. BAJA es "todo lo de ALTA, mas barato" con UNA excepcion
## tomada del original: las llamas de los NPC — lo unico que escala con el
## numero de entidades. Todo lo demas es coste fijo y se ataca mejor con la
## resolucion y el antialias, que son invisibles al ojo y muy visibles al fps.
const PRESETS := {
	"baja":  {"render": 0, "aa": 0, "luces": 0, "engine": 0,
			  "background": 0, "collectable": 0, "explosion": 1, "emissive": 1},
	"media": {"render": 1, "aa": 1, "luces": 1, "engine": 1,
			  "background": 1, "collectable": 1, "explosion": 1, "emissive": 1},
	"alta":  {"render": 2, "aa": 2, "luces": 2, "engine": 2,
			  "background": 2, "collectable": 1, "explosion": 1, "emissive": 1},
}

const ETIQUETAS := {"baja": "BAJA", "media": "MEDIA", "alta": "ALTA"}

var preset := "alta"
var _cuenta := 0

## ---- Auto-calidad por FPS (guideline 3D, §12.2 del original) ----
## Promedia el FPS en ventanas de 20 s: por debajo de 10 sube UN escalon de
## recorte; por encima de 60 baja uno — histeresis: solo recupera con holgura.
## El recorte es TRANSITORIO: se aplica como TOPE sobre los niveles del preset y
## no se persiste — el preset por cuenta no se toca, que es la leccion del
## autotest que dejaba residuo. Sin foco no se mide (una ventana de fondo con
## los fps capados no es una maquina lenta), y en autotest no corre.
const AQ_VENTANA_SEC := 20.0
const AQ_FPS_BAJA := 10.0
const AQ_FPS_SUBE := 60.0
## La escalera de recortes, del mas barato al mas doloroso. Cada peldanio es un
## mapa de TOPES por clave; lo que no aparece no se toca. Los dos primeros
## (antialias, resolucion) no se ven; el ultimo es el que el original tambien
## reservaba para el final: sin explosiones ni pulso.
const AQ_ESCALERA := [
	{},
	{"aa": 0},
	{"aa": 0, "render": 1},
	{"aa": 0, "render": 1, "background": 1, "engine": 1},
	{"aa": 0, "render": 0, "background": 0, "engine": 0, "luces": 1},
	{"aa": 0, "render": 0, "background": 0, "engine": 0, "luces": 0,
	 "collectable": 0, "explosion": 0, "emissive": 0},
]
var auto_reduccion := 0
var _aq_acum := 0.0
var _aq_suma := 0.0
var _aq_muestras := 0


func nivel(clave: String) -> int:
	var base := int(niveles.get(clave, 2))
	if auto_reduccion <= 0:
		return base
	var topes: Dictionary = AQ_ESCALERA[auto_reduccion]
	return mini(base, int(topes.get(clave, base)))


func _process(delta: float) -> void:
	# medir en autotest o con calidad forzada contaminaria justo lo que prueban
	if Session.autotest_modo != "" or Session.calidad_forzada != "":
		return
	if not get_window().has_focus():
		return
	_aq_acum += delta
	if _aq_acum < 1.0:
		return                      # una muestra por segundo basta
	_aq_acum = 0.0
	_aq_suma += Engine.get_frames_per_second()
	_aq_muestras += 1
	if float(_aq_muestras) < AQ_VENTANA_SEC:
		return
	var media := _aq_suma / float(_aq_muestras)
	_aq_suma = 0.0
	_aq_muestras = 0
	if media < AQ_FPS_BAJA and auto_reduccion < AQ_ESCALERA.size() - 1:
		_reduccion_a(auto_reduccion + 1, media)
	elif media > AQ_FPS_SUBE and auto_reduccion > 0:
		_reduccion_a(auto_reduccion - 1, media)


func _reduccion_a(nuevo: int, media: float) -> void:
	# se avisa con las claves cuyo nivel EFECTIVO cambio, para que el mundo
	# reconstruya exactamente lo que toca — el mismo cable que el cambio manual
	var antes := {}
	for k in niveles:
		antes[k] = nivel(k)
	auto_reduccion = nuevo
	var claves := []
	for k in niveles:
		if nivel(k) != int(antes[k]):
			claves.append(k)
	print("AutoCalidad: reduccion %d (media %.0f fps)" % [auto_reduccion, media])
	if not claves.is_empty():
		cambiada.emit(claves)


## Carga los ajustes de esta cuenta. Se llama al entrar al mundo, no en _ready:
## antes del login no se sabe de quien son.
func cargar(cuenta: int) -> void:
	_cuenta = cuenta
	var cfg := ConfigFile.new()
	if cfg.load(RUTA) != OK:
		return
	var guardado: Variant = cfg.get_value(str(cuenta), "preset", "")
	if guardado is String and PRESETS.has(guardado):
		preset = guardado
		niveles = PRESETS[guardado].duplicate()


## Aplica un preajuste y avisa de las claves que cambiaron. Devuelve esa lista
## para que quien llame sepa si hace falta reconstruir algo.
func aplicar(nombre: String) -> Array:
	if not PRESETS.has(nombre):
		return []
	var nuevos: Dictionary = PRESETS[nombre]
	var claves := []
	for k in nuevos:
		if int(niveles.get(k, -1)) != int(nuevos[k]):
			claves.append(k)
	niveles = nuevos.duplicate()
	preset = nombre
	_guardar()
	if not claves.is_empty():
		cambiada.emit(claves)
	return claves


func _guardar() -> void:
	var cfg := ConfigFile.new()
	cfg.load(RUTA)                       # conserva los ajustes de otras cuentas
	cfg.set_value(str(_cuenta), "preset", preset)
	cfg.save(RUTA)
