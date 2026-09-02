## Aviso de PELIGRO PERSISTENTE: la zona radiactiva (§9 del sistema N).
##
## Es la anatomia del toast —Michroma 10 px con tracking, mayusculas, panel
## oscuro con borde de 1 px, centro-superior a 88 px— con la sustitucion del §4
## para peligro: texto y borde en `--hostile`. Dos diferencias con el toast, y
## las dos son la definicion de "persistente": NO caduca (vive mientras dure la
## condicion, no 2,6 s) y LATE — el pulso es el idioma de peligro del sistema,
## el mismo del anillo hostil del minimapa. Debajo, una viñeta hostil en los
## bordes del viewport, transparente al centro y en fase con el pulso: la
## lectura periferica, para que se sienta sin tener que leer.
##
## No sabe de red ni de reglas: el mundo le dice `actualizar(activo, delta)`
## cada frame. La condicion (fuera de los limites publicados del mapa) es la
## misma geometria que aplica el server; el coste ya llega por HeroStats.
class_name RadiationWarning
extends Control

const PANEL_TOP := 88.0            # el toast del prototipo vive a 88 px
const FADE := 0.25              # la transicion del toast (.25 s)
const PULSE_PERIOD := 1.2         # s por latido
const PULSE_MIN := 0.55            # el rotulo nunca baja de esto mientras hay peligro
const VIGNETTE_ALPHA := 0.18          # hostil al 18 % en el borde, 0 al centro

var _panel: PanelContainer
var _vignette: TextureRect
var _phase := 0.0
var _alpha := 0.0                   # 0 = oculto, 1 = plena presencia


static func create() -> RadiationWarning:
	var w := RadiationWarning.new()
	w.set_anchors_preset(Control.PRESET_FULL_RECT)
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w.visible = false

	# la viñeta: degradado radial, transparente al centro, hostil en el borde.
	# El TextureRect estira el cuadrado al viewport (elipse), igual que el
	# `radial-gradient(90% 90% ...)` del prototipo
	var grad := Gradient.new()
	grad.set_color(0, Color(NTheme.HOSTILE, 0.0))
	grad.set_color(1, Color(NTheme.HOSTILE, 1.0))
	grad.set_offset(0, 0.45)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 256
	tex.height = 256
	w._vignette = TextureRect.new()
	w._vignette.texture = tex
	w._vignette.stretch_mode = TextureRect.STRETCH_SCALE
	w._vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	w._vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w.add_child(w._vignette)

	# el rotulo: el toast, en hostil
	w._panel = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(7.0 / 255, 10.0 / 255, 18.0 / 255, 0.85)
	box.border_color = Color(NTheme.HOSTILE, 0.35)    # el `--edge` del toast, en hostil
	box.set_border_width_all(1)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 9
	box.content_margin_bottom = 9
	w._panel.add_theme_stylebox_override("panel", box)
	w._panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Michroma 10 px con .14em de tracking (~1,4 px a ese cuerpo), mayusculas
	var caption := NTheme.label("ZONA RADIACTIVA", NTheme.michroma_track(1), 10, NTheme.HOSTILE)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w._panel.add_child(caption)
	w._panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	w._panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	w._panel.position.y = PANEL_TOP
	w.add_child(w._panel)
	return w


## Un frame. `activo` es la condicion viva; el aviso entra y sale con el
## fundido del toast y, mientras esta, late.
func refresh(is_active: bool, delta: float) -> void:
	_alpha = move_toward(_alpha, 1.0 if is_active else 0.0, delta / FADE)
	if _alpha <= 0.0:
		visible = false
		return
	visible = true
	_phase = fmod(_phase + delta / PULSE_PERIOD, 1.0)
	# latido: seno entre PULSO_MIN y 1, suave en los dos extremos
	var heartbeat := PULSE_MIN + (1.0 - PULSE_MIN) * (0.5 + 0.5 * sin(_phase * TAU))
	_panel.modulate = Color(1, 1, 1, _alpha * heartbeat)
	_vignette.modulate = Color(1, 1, 1, _alpha * VIGNETTE_ALPHA * heartbeat)
