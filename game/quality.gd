# Autoload: niveles de calidad grafica, por SUBSISTEMA.
#
# Portado del prototipo (game/quality.gd), que a su vez replicaba el
# QualitySettings del cliente original. La idea que importa no es el interruptor
# alto/medio/bajo, sino que cada sistema pregunte por LO SUYO al dibujar:
# `Quality.nivel("engine") > 0`. Los tres presets solo mueven ese diccionario, y
# eso deja la puerta abierta a un "personalizado" sin rehacer nada.
#
# Se persiste en user:// y POR CUENTA: dos personas que comparten un PC guardan
# ajustes distintos, y a la vez el valor NO viaja con la cuenta a otra maquina —
# la calidad es una capacidad del equipo, no una preferencia de la partida.
extends Node

## Claves que cambiaron; quien dibuje algo afectado se reconstruye.
signal cambiada(claves: Array)

const RUTA := "user://quality.cfg"

## Que controla cada clave:
##  - npc:         0-1 PNG fijo · 2+ atlas animado (los videos en bucle)
##  - shader:      0 sin ondulacion/peristalsis/anillos · 1+ con ellos
##  - emissive:    0 capa emisiva apagada · 1+ encendida y pulsando
##  - engine:      0 sin llamas · 1+ llamas (el nivel 2 era las chispas, que se quitaron)
##  - collectable: 0-1 caja congelada en su primer fotograma · 2+ animada
##  - background:  0 solo estrellas · 1 fondo sin mosaicos · 2+ completo
##  - explosion:   0 sin animacion de explosion · 1+ con ella
var niveles := {
	"npc": 2, "shader": 1, "emissive": 1, "engine": 1,
	"collectable": 2, "background": 2, "explosion": 1,
}

## Los tres preajustes. El corte caro esta entre MEDIA y ALTA: ahi es donde los
## atlas animados dejan de cargarse y se liberan ~58 MB de VRAM.
## MEDIA conserva los shaders a proposito — cuestan casi nada (una operacion de
## fragment sobre un sprite que ya se dibuja) y son lo unico que da vida a los
## bichos que nunca tendran video.
const PRESETS := {
	"baja":  {"npc": 0, "shader": 0, "emissive": 0, "engine": 0,
			  "collectable": 0, "background": 0, "explosion": 0},
	"media": {"npc": 1, "shader": 1, "emissive": 1, "engine": 1,
			  "collectable": 1, "background": 1, "explosion": 1},
	"alta":  {"npc": 2, "shader": 1, "emissive": 1, "engine": 1,
			  "collectable": 2, "background": 2, "explosion": 1},
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
## mapa de TOPES por clave; lo que no aparece no se toca.
const AQ_ESCALERA := [
	{},
	{"background": 1},
	{"background": 1, "engine": 0},
	{"background": 1, "engine": 0, "explosion": 0},
	{"background": 1, "engine": 0, "explosion": 0, "npc": 1, "collectable": 1},
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
