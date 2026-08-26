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
##  - engine:      0 sin llamas ni chispas · 1 llamas · 2+ llamas y chispas
##  - collectable: 0-1 caja congelada en su primer fotograma · 2+ animada
##  - background:  0 solo estrellas · 1 fondo sin mosaicos · 2+ completo
##  - explosion:   0 sin animacion de explosion · 1+ con ella
var niveles := {
	"npc": 2, "shader": 1, "emissive": 1, "engine": 2,
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
	"alta":  {"npc": 2, "shader": 1, "emissive": 1, "engine": 2,
			  "collectable": 2, "background": 2, "explosion": 1},
}

const ETIQUETAS := {"baja": "BAJA", "media": "MEDIA", "alta": "ALTA"}

var preset := "alta"
var _cuenta := 0


func nivel(clave: String) -> int:
	return int(niveles.get(clave, 2))


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
