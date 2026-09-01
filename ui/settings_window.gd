# AJUSTES — la ventana del engranaje de la sysbar. Por ahora, solo calidad.
#
# Tres preajustes, no un slider de cuatro como el prototipo: el usuario pidio
# alta/media/baja. Por debajo siguen siendo NIVELES POR SUBSISTEMA, asi que
# anadir un modo "personalizado" luego es abrir esta ventana, no rehacer nada.
#
# El prototipo le pone cuatro pestanias (Pantalla, Jugabilidad, Sonido, Teclado)
# y aqui no hay ninguna: una sola pestania no es una barra de pestanias, es un
# adorno que promete tres secciones que no existen. Se agregan cuando haya que
# poner debajo.
class_name SettingsWindow
extends NWindow

signal preset_elegido(nombre: String)

const ICONO := "res://assets/ui/icons/gear.svg"
const ANCHO := 344                # el ancho del `#w-cfg` del prototipo
const ORDEN := ["baja", "media", "alta"]
const DETALLE := {
	"baja": "Todo en 3D a media resolución · sin antialias · solo el sol · llamas solo en tu nave",
	"media": "Render a 0,85× · antialias 2× · luz de tu nave · polvo estelar",
	"alta": "Resolución completa · antialias 4× · todas las luces · nebulosas y planetas",
}

var _segmentos := {}
var _detalle: Label
var _fps: Label
var _vram: Label


static func crear() -> SettingsWindow:
	var v := SettingsWindow.new()
	v.clave = "ajustes"
	v._construir("Ajustes", ICONO)
	v._cuerpo()
	return v


func _ready() -> void:
	custom_minimum_size = Vector2(ANCHO, 0)
	visible = false


func _cuerpo() -> void:
	contenido.add_child(_fila_calidad())

	_detalle = NTheme.label("", NTheme.exo2(), 11, NTheme.FAINT)
	_detalle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detalle.custom_minimum_size = Vector2(ANCHO - 20, 0)
	contenido.add_child(_detalle)

	var sep := HSeparator.new()
	var linea := StyleBoxLine.new()
	linea.color = NTheme.EDGE_SOFT
	sep.add_theme_stylebox_override("separator", linea)
	contenido.add_child(sep)

	# Los dos numeros que hacen falta para ELEGIR un preajuste, no para adornar:
	# cuantos fotogramas da la maquina y cuanta textura hay cargada. Desde que
	# todo es 3D la textura casi no cambia con el nivel (lo que baja es la
	# resolucion del render y el antialias), asi que el numero que responde al
	# ajuste es el de fotogramas.
	_fps = _fila_numero("Fotogramas por segundo")
	_vram = _fila_numero("Memoria de textura")

	contenido.add_child(NTheme.label("El cambio se aplica al instante",
		NTheme.exo2(), 11, NTheme.MUTED))
	_refrescar()


## §7: fila de `.r` — etiqueta fria a la izquierda, valor a la derecha.
func _fila_calidad() -> Control:
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 7)
	var k := NTheme.label("Calidad", NTheme.exo2(), 11, NTheme.MUTED)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fila.add_child(k)
	var seg := HBoxContainer.new()
	seg.add_theme_constant_override("separation", 3)
	for nombre in ORDEN:
		var b := _segmento(nombre)
		_segmentos[nombre] = b
		seg.add_child(b)
	fila.add_child(seg)
	return fila


func _fila_numero(etiqueta: String) -> Label:
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 7)
	var k := NTheme.label(etiqueta, NTheme.exo2(), 11, NTheme.MUTED)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila.add_child(k)
	# la firma del sistema: etiqueta fria + numero ambar en JetBrains Mono
	var v := NTheme.label("—", NTheme.mono(), 10, NTheme.WARN)
	fila.add_child(v)
	contenido.add_child(fila)
	return v


## El segmento lo construye NTheme (§7): vivia aqui y ahora lo comparten esta
## ventana y la pantalla de entrada.
func _segmento(nombre: String) -> Button:
	var b := NTheme.segmento(Quality.ETIQUETAS[nombre])
	b.pressed.connect(func():
		preset_elegido.emit(nombre)
		_refrescar())
	return b


func _refrescar() -> void:
	for nombre in _segmentos:
		NTheme.marcar_segmento(_segmentos[nombre], Quality.preset == nombre)
	if _detalle != null:
		_detalle.text = DETALLE.get(Quality.preset, "")


func alternar() -> void:
	visible = not visible
	if visible:
		_refrescar()
		if not cargar_posicion():
			centrar()


func _process(_delta: float) -> void:
	if not visible or _fps == null:
		return
	_fps.text = str(int(Engine.get_frames_per_second()))
	var bytes := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	_vram.text = "%s MB" % _con_coma(bytes / 1048576.0)


## Decimal con COMA, como se escribe en espaniol. El separador de miles con punto
## del §3 no aplica aqui porque el numero no llega a mil.
static func _con_coma(v: float) -> String:
	return ("%.1f" % v).replace(".", ",")
