# Un portal del mapa. Su POSICION es dato del server (map_portal -> EnterMap);
# aqui solo viven sus particularidades de arte, en data/props/portal.json.
#
# F1 del plan-cliente-3d: el nodo sigue siendo la LOGICA (posicion de juego,
# rango de salto, senial de encendido — nada de eso cambio). Su cuerpo vive en
# la escena unica y es su MALLA (`modelo` en el JSON) en todos los niveles de
# calidad. Sin malla, el cuerpo queda VACIO: se ve la etiqueta del sector y se
# puede saltar, pero el portal no se dibuja — el aro PNG y el atlas de
# encendido murieron con la calidad por niveles (1-sep-2026); el encendido
# volvera como animacion del GLB. La etiqueta vive en la capa HUD del mundo,
# proyectada.
class_name PortalNode
extends Node2D

## Se emite cuando el encendido llega a su ultimo fotograma (la senial que el
## salto espera: el mapa se muestra cuando terminan la animacion Y el server).
## Hoy nadie la emite — no hay encendido sin malla — pero el salto ya sabe
## esperarla, y el dia que el GLB traiga la animacion se enchufa aqui.
signal encendido_terminado(portal_id: int)

var portal_id := 0
var target_map_code := ""
var is_working := true
var click_radius := 190.0

## A que distancia se puede SALTAR. Tiene que casar con `JumpRange` del server
## (el cliente propone y el server dispone); el radio de click es aparte y mas
## chico a proposito.
const RANGO_SALTO := 600.0

var _datos = null                 # MexProtocol.MapPortal, para poder reconstruir
var _cuerpo: Node3D               # el cuerpo en la escena unica (la malla, o vacio)
var _modelo: Node3D
var _etiqueta: Label              # en la capa HUD del mundo, proyectada


func setup(p) -> void:      # p: MexProtocol.MapPortal
	_datos = p
	portal_id = p.portal_id
	target_map_code = p.target_map_code
	is_working = p.is_working
	position = Vector2(p.x, p.y)
	_construir()


## Rehace solo la parte visual al cambiar la calidad en caliente.
func reconstruir() -> void:
	_limpiar()
	_construir()


func _limpiar() -> void:
	if _cuerpo != null:
		_cuerpo.queue_free()
	if _etiqueta != null:
		_etiqueta.queue_free()
	_cuerpo = null
	_modelo = null
	_etiqueta = null


func _exit_tree() -> void:
	_limpiar()


func _construir() -> void:
	var d := AssetDefs.prop("portal")
	click_radius = float(d.get("click_radius", 190))

	_cuerpo = Node3D.new()
	_cuerpo.position = Vector3(position.x, 1.0, position.y)
	Mundo3D.instancia.add_child(_cuerpo)

	# la malla, escalada a `world_size` por su huella, como la estacion
	var ruta := str(d.get("modelo", ""))
	if ruta != "" and ResourceLoader.exists(ruta):
		var escena: PackedScene = load(ruta)
		if escena != null:
			_modelo = escena.instantiate()
			_cuerpo.add_child(_modelo)
			_modelo.scale = Vector3.ONE * (float(d.get("world_size", 380))
				/ AssetDefs.extension_3d(_modelo))
	_montar_etiqueta(d)


func _montar_etiqueta(d: Dictionary) -> void:
	# el destino, proyectado bajo el aro: el jugador sabe a donde lleva
	var etq: Dictionary = d.get("label", {})
	var texto := "Sector %s" % target_map_code
	if not is_working:
		texto = "Sector %s · inactivo" % target_map_code
	_etiqueta = NTheme.label(texto, NTheme.exo2(), int(etq.get("size", 12)),
		AssetDefs.color(etq.get("color", "A78BFA"), NTheme.VIOLET) if is_working else NTheme.MUTED)
	_etiqueta.custom_minimum_size = Vector2(180, 0)
	_etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_etiqueta.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_etiqueta.add_theme_constant_override("outline_size", 4)
	if EntityNode.capa_hud != null:
		EntityNode.capa_hud.add_child(_etiqueta)
	else:
		add_child(_etiqueta)


## Lanza el encendido. Devuelve false si no hay nada que lanzar — y hoy nunca
## lo hay: sin malla no hay ceremonia y el salto ocurre en el acto.
func activar() -> bool:
	return false


## Vuelve al reposo (solo hace falta si el salto se cae).
func reposo() -> void:
	pass


## Para que el autotest pueda AFIRMAR que el encendido llego al final.
func encendido_completo() -> bool:
	return false


func _process(_delta: float) -> void:
	# la etiqueta sigue al portal en pantalla (los portales no se mueven, pero
	# la camara si — y con el tilt-zoom la proyeccion cambia cada frame)
	if _etiqueta != null and Mundo3D.instancia != null:
		var px := Mundo3D.instancia.a_pantalla(position)
		_etiqueta.position = (px + Vector2(-90, 40)).floor()
	if _cuerpo != null:
		_cuerpo.visible = visible
