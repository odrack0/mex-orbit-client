# Pantalla de login (sistema N): logo, card de cristal, secuencia real de conexion.
# Flujo: POST /v1/auth/login -> Session -> world.tscn (el Hello lo hace el mundo).
extends Control

var _user: LineEdit
var _pass: LineEdit
var _status: Label
var _boton: Button
var _http: HTTPRequest


func _ready() -> void:
	var fondo := ColorRect.new()
	fondo.color = NTheme.BG
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fondo)

	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centro)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	centro.add_child(col)

	var logo := NTheme.label("MEX ORBIT", NTheme.michroma(), 30, NTheme.TXT)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(logo)
	var sub := NTheme.label("CLIENTE V1 · VERTICAL SLICE", NTheme.michroma(), 8, NTheme.FAINT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", NTheme.glass_panel())
	card.custom_minimum_size = Vector2(400, 0)
	col.add_child(card)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	card.add_child(inner)

	inner.add_child(NTheme.label("ENLACE DE NAVEGACIÓN", NTheme.michroma(), 9, NTheme.CYAN))
	inner.add_child(NTheme.label("Usuario", NTheme.exo2(), 12, NTheme.MUTED))
	_user = _campo(inner)
	inner.add_child(NTheme.label("Contraseña", NTheme.exo2(), 12, NTheme.MUTED))
	_pass = _campo(inner)
	_pass.secret = true

	_boton = Button.new()
	_boton.text = "ESTABLECER ENLACE"
	_boton.add_theme_font_override("font", NTheme.michroma())
	_boton.add_theme_font_size_override("font_size", 10)
	_boton.add_theme_color_override("font_color", NTheme.CYAN)
	_boton.custom_minimum_size = Vector2(0, 38)
	_boton.pressed.connect(_login)
	inner.add_child(_boton)

	_status = NTheme.label("", NTheme.mono(), 11, NTheme.MUTED)
	_status.custom_minimum_size = Vector2(0, 34)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(_status)

	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_respuesta)

	var dev: Dictionary = Session.dev_credentials()
	_user.text = dev.username
	_pass.text = dev.password

	# autotest: entra solo con la cuenta de pruebas (una sesion por cuenta:
	# TestBot es del bot, la cuenta del usuario jamas se usa en automatico)
	if Session.autotest_screenshot != "":
		_user.text = "testbot"
		_pass.text = "dev1234"
		_login.call_deferred()


func _campo(parent: Container) -> LineEdit:
	var le := LineEdit.new()
	le.add_theme_font_override("font", NTheme.mono())
	le.add_theme_font_size_override("font_size", 12)
	le.custom_minimum_size = Vector2(0, 32)
	le.text_submitted.connect(func(_t): _login())
	parent.add_child(le)
	return le


func _login() -> void:
	_boton.disabled = true
	_status.add_theme_color_override("font_color", NTheme.MUTED)
	_status.text = "Autenticando contra la api..."
	var cuerpo := JSON.stringify({"username": _user.text, "password": _pass.text})
	_http.request(Session.api_base + "/v1/auth/login",
		["Content-Type: application/json"], HTTPClient.METHOD_POST, cuerpo)


func _on_respuesta(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_boton.disabled = false
	if code != 200:
		_status.add_theme_color_override("font_color", NTheme.HOSTILE)
		_status.text = "Enlace rechazado (HTTP %d): credenciales o api caida." % code
		return
	var datos: Dictionary = JSON.parse_string(body.get_string_from_utf8())
	Session.account_id = int(datos.account_id)
	Session.pilot_name = datos.pilot_name
	Session.session_token = datos.session_token
	Session.game_ticket = datos.game_ticket
	Session.game_host = datos.game_host
	_status.text = "Sesión OK (cuenta %d). Abriendo enlace con el sector..." % Session.account_id
	get_tree().change_scene_to_file.call_deferred("res://game/world.tscn")
