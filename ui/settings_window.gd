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

signal preset_chosen(entry_name: String)

const ICON := "res://assets/ui/icons/gear.svg"
const WIDTH := 344                # el ancho del `#w-cfg` del prototipo
const ORDER := ["baja", "media", "alta"]
const DETAIL := {
	"baja": "Render a 0,65× · sin antialias · solo el sol · llamas solo en tu nave",
	"media": "Render a 0,85× · antialias 2× · luz de tu nave · polvo estelar",
	"alta": "Resolución completa · antialias 4× · todas las luces · nebulosas y planetas",
}

var _segments := {}
var _detail: Label
var _fps: Label
var _vram: Label


static func create() -> SettingsWindow:
	var v := SettingsWindow.new()
	v.key = "ajustes"
	v._build("Ajustes", ICON)
	v._body()
	return v


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	visible = false


func _body() -> void:
	content.add_child(_quality_row())

	_detail = NTheme.label("", NTheme.exo2(), 11, NTheme.FAINT)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(WIDTH - 20, 0)
	content.add_child(_detail)

	var sep := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = NTheme.EDGE_SOFT
	sep.add_theme_stylebox_override("separator", line)
	content.add_child(sep)

	# Los dos numeros que hacen falta para ELEGIR un preajuste, no para adornar:
	# cuantos fotogramas da la maquina y cuanta textura hay cargada. Desde que
	# todo es 3D la textura casi no cambia con el nivel (lo que baja es la
	# resolucion del render y el antialias), asi que el numero que responde al
	# ajuste es el de fotogramas.
	_fps = _number_row("Fotogramas por segundo")
	_vram = _number_row("Memoria de textura")

	content.add_child(NTheme.label("El cambio se aplica al instante",
		NTheme.exo2(), 11, NTheme.MUTED))
	_refresh()


## §7: fila de `.r` — etiqueta fria a la izquierda, valor a la derecha.
func _quality_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	var k := NTheme.label("Calidad", NTheme.exo2(), 11, NTheme.MUTED)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(k)
	var seg := HBoxContainer.new()
	seg.add_theme_constant_override("separation", 3)
	for entry_name in ORDER:
		var b := _segment(entry_name)
		_segments[entry_name] = b
		seg.add_child(b)
	row.add_child(seg)
	return row


func _number_row(tag: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	var k := NTheme.label(tag, NTheme.exo2(), 11, NTheme.MUTED)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(k)
	# la firma del sistema: etiqueta fria + numero ambar en JetBrains Mono
	var v := NTheme.label("—", NTheme.mono(), 10, NTheme.WARN)
	row.add_child(v)
	content.add_child(row)
	return v


## El segmento lo construye NTheme (§7): vivia aqui y ahora lo comparten esta
## ventana y la pantalla de entrada.
func _segment(entry_name: String) -> Button:
	var b := NTheme.segment(Quality.LABELS[entry_name])
	b.pressed.connect(func():
		preset_chosen.emit(entry_name)
		_refresh())
	return b


func _refresh() -> void:
	for entry_name in _segments:
		NTheme.mark_segment(_segments[entry_name], Quality.preset == entry_name)
	if _detail != null:
		_detail.text = DETAIL.get(Quality.preset, "")


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()
		if not load_position():
			center_on()


func _process(_delta: float) -> void:
	if not visible or _fps == null:
		return
	_fps.text = str(int(Engine.get_frames_per_second()))
	var bytes := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	_vram.text = "%s MB" % _with_comma(bytes / 1048576.0)


## Decimal con COMA, como se escribe en espaniol. El separador de miles con punto
## del §3 no aplica aqui porque el numero no llega a mil.
static func _with_comma(v: float) -> String:
	return ("%.1f" % v).replace(".", ",")
