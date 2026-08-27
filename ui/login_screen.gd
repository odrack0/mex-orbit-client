# Pantalla de entrada (sistema N): logo, card de cristal, secuencia real de conexion.
#
# DOS FLUJOS en el mismo card, no dos pantallas:
#
#   ENLACE -> POST /v1/auth/login    -> Session -> world.tscn
#   ALTA   -> POST /v1/auth/register -> y entra solo, sin pedir los datos otra vez
#
# Se eligen con el SELECTOR SEGMENTADO del §7, que es el componente que el
# sistema ya tiene para escoger entre dos y cuatro opciones excluyentes. Una
# pantalla aparte habria significado un segundo logo, un segundo card y un
# "volver" — tres cosas nuevas para un formulario que comparte dos de sus cuatro
# campos con el que ya existia.
#
# El registro estaba abierto en el server desde el primer despliegue y el cliente
# no tenia por donde usarlo: la unica forma de crear una cuenta era un `curl`.
extends Control

## Reglas del server (`/v1/auth/register`), repetidas aqui a proposito para poder
## decir QUE esta mal antes de gastar un viaje y recibir un 400 que no explica
## nada. El server sigue validando: esto es cortesia, no seguridad.
const MIN_USUARIO := 3
const MAX_USUARIO := 32
const MIN_CLAVE := 8

var _modo := "enlace"
var _segmentos := {}
var _user: LineEdit
var _pass: LineEdit
var _correo: LineEdit
var _piloto: LineEdit
var _fila_correo: Control
var _fila_piloto: Control
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

	inner.add_child(_selector())
	inner.add_child(NTheme.label("Usuario", NTheme.exo2(), 12, NTheme.MUTED))
	_user = _campo(inner)
	_fila_correo = _bloque(inner, "Correo")
	_correo = _campo(inner)
	_fila_piloto = _bloque(inner, "Nombre de piloto")
	_piloto = _campo(inner)
	inner.add_child(NTheme.label("Contraseña", NTheme.exo2(), 12, NTheme.MUTED))
	_pass = _campo(inner)
	_pass.secret = true

	_boton = Button.new()
	_boton.add_theme_font_override("font", NTheme.michroma())
	_boton.add_theme_font_size_override("font_size", 10)
	_boton.add_theme_color_override("font_color", NTheme.CYAN)
	_boton.custom_minimum_size = Vector2(0, 38)
	_boton.pressed.connect(_enviar)
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
	_aplicar_modo()

	# autotest: entra solo con la cuenta de pruebas (una sesion por cuenta:
	# TestBot es del bot, la cuenta del usuario jamas se usa en automatico)
	if Session.autotest_screenshot != "":
		await _probar_alta()
		_user.text = "testbot"
		_pass.text = "dev1234"
		_enviar.call_deferred()


## El alta se comprueba ANTES de entrar, y sin red: que el selector cambie de
## modo, que aparezcan los dos campos que solo existen ahi, y que la validacion
## rechace un formulario vacio diciendo POR QUE.
##
## No se registra una cuenta de verdad a proposito: correr el gate ensuciaria la
## base con una cuenta nueva por pasada. Lo que se prueba aqui es lo unico que se
## puede romper sin que nadie se entere — que el boton lleve al sitio y que los
## campos esten. Que el server acepta el alta ya lo prueba el despliegue.
func _probar_alta() -> void:
	_cambiar_modo("alta")
	# y una foto, que esta pantalla no la retrata nadie mas: el gate entra
	# derecho al juego y las capturas de arte son todas del mundo
	_correo.text = "piloto@ejemplo.mx"
	_piloto.text = "PilotoNuevo"
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		Session.autotest_screenshot.replace(".png", "-alta.png"))
	_correo.text = ""
	_piloto.text = ""
	if not campos_de_alta_visibles():
		push_error("AUTOTEST FALLO — el modo ALTA no muestra correo ni nombre de piloto")
		get_tree().quit(1)
		return
	_user.text = ""
	_pass.text = ""
	if _revisar_alta() == "":
		push_error("AUTOTEST FALLO — el alta acepta un formulario vacio")
		get_tree().quit(1)
		return
	_cambiar_modo("enlace")
	if campos_de_alta_visibles():
		push_error("AUTOTEST FALLO — los campos del alta siguen visibles en ENLACE")
		get_tree().quit(1)


func _selector() -> Control:
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 3)
	for par in [["enlace", "ENLACE"], ["alta", "ALTA"]]:
		var b := NTheme.segmento(par[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var modo: String = par[0]
		b.pressed.connect(func(): _cambiar_modo(modo))
		_segmentos[modo] = b
		fila.add_child(b)
	return fila


## Etiqueta + su campo se muestran y se ocultan JUNTOS. Devolver la etiqueta y
## esconder solo el LineEdit dejaria un rotulo huerfano encima del siguiente
## campo, que es peor que no tener rotulo.
func _bloque(parent: Container, texto: String) -> Control:
	var l := NTheme.label(texto, NTheme.exo2(), 12, NTheme.MUTED)
	parent.add_child(l)
	return l


func _campo(parent: Container) -> LineEdit:
	var le := LineEdit.new()
	le.add_theme_font_override("font", NTheme.mono())
	le.add_theme_font_size_override("font_size", 12)
	le.custom_minimum_size = Vector2(0, 32)
	le.text_submitted.connect(func(_t): _enviar())
	parent.add_child(le)
	return le


func _cambiar_modo(modo: String) -> void:
	if _modo == modo:
		return
	_modo = modo
	_status.text = ""
	_aplicar_modo()


func _aplicar_modo() -> void:
	var alta := _modo == "alta"
	for m in _segmentos:
		NTheme.marcar_segmento(_segmentos[m], m == _modo)
	for n in [_fila_correo, _correo, _fila_piloto, _piloto]:
		n.visible = alta
	_boton.text = "CREAR CUENTA" if alta else "ESTABLECER ENLACE"


## Para que el autotest pueda AFIRMAR que el alta existe y se ve, en vez de
## limitarse a sacar una foto de la pantalla de entrada y darla por buena.
func modo_actual() -> String:
	return _modo


func campos_de_alta_visibles() -> bool:
	return _correo.visible and _piloto.visible


func _enviar() -> void:
	if _modo == "alta":
		_registrar()
	else:
		_login()


func _login() -> void:
	_boton.disabled = true
	_status.add_theme_color_override("font_color", NTheme.MUTED)
	_status.text = "Autenticando contra la api..."
	var cuerpo := JSON.stringify({"username": _user.text, "password": _pass.text})
	_http.request(Session.api_base + "/v1/auth/login",
		["Content-Type: application/json"], HTTPClient.METHOD_POST, cuerpo)


func _registrar() -> void:
	var falla := _revisar_alta()
	if falla != "":
		_error(falla)
		return
	_boton.disabled = true
	_status.add_theme_color_override("font_color", NTheme.MUTED)
	_status.text = "Dando de alta la cuenta..."
	var cuerpo := JSON.stringify({
		"username": _user.text.strip_edges(),
		"email": _correo.text.strip_edges(),
		"password": _pass.text,
		"pilotName": _piloto.text.strip_edges(),
	})
	_http.request(Session.api_base + "/v1/auth/register",
		["Content-Type: application/json"], HTTPClient.METHOD_POST, cuerpo)


## Dice QUE falta, no "datos invalidos". Un formulario que rechaza sin explicar
## obliga a adivinar cual de los cuatro campos era.
func _revisar_alta() -> String:
	var u := _user.text.strip_edges()
	var p := _piloto.text.strip_edges()
	if u.length() < MIN_USUARIO or u.length() > MAX_USUARIO:
		return "El usuario necesita entre %d y %d caracteres." % [MIN_USUARIO, MAX_USUARIO]
	if p.length() < MIN_USUARIO or p.length() > MAX_USUARIO:
		return "El nombre de piloto necesita entre %d y %d caracteres." % [MIN_USUARIO, MAX_USUARIO]
	if not _correo.text.strip_edges().contains("@"):
		return "El correo no parece un correo."
	if _pass.text.length() < MIN_CLAVE:
		return "La contraseña necesita al menos %d caracteres." % MIN_CLAVE
	return ""


func _error(texto: String) -> void:
	_boton.disabled = false
	_status.add_theme_color_override("font_color", NTheme.HOSTILE)
	_status.text = texto


## Godot pone la causa REAL en `result`, no en el codigo HTTP: cuando no hay
## nadie al otro lado el codigo es 0, que es el mensaje menos util que existe —
## manda a mirar la api cuando la api ni se ha enterado de que existes. Y se
## nombra la URL a la que se intento ir, porque el fallo suele ser justo ese:
## apuntar a un sitio distinto del que uno cree (un `--api=` viejo, la anulacion
## `.web` al exportar). Cadena vacia = el transporte fue bien.
func _fallo_de_red(result: int) -> String:
	match result:
		HTTPRequest.RESULT_SUCCESS:
			return ""
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CONNECTION_ERROR:
			return "No hay respuesta de la api en %s. ¿Está levantada? (tools/dev-run.ps1)" % Session.api_base
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "No se pudo resolver el host de %s." % Session.api_base
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "Falló el TLS contra %s. ¿Es https contra un puerto http?" % Session.api_base
		HTTPRequest.RESULT_TIMEOUT:
			return "La api de %s no contestó a tiempo." % Session.api_base
		_:
			return "La petición a %s falló antes de recibir respuesta (result %d)." % [Session.api_base, result]


## Mismo criterio que en el alta: un 401 se arregla tecleando otra vez y un 403
## no se arregla de ninguna manera. Juntarlos en "credenciales o api caida" hacia
## que un baneo pareciera un dedazo, y ademas culpaba a la api — que a estas
## alturas ya se sabe que contesto, porque si no habriamos salido por
## `_fallo_de_red`.
func _motivo_enlace(code: int) -> String:
	match code:
		401:
			return "Usuario o contraseña incorrectos."
		403:
			return "Esta cuenta está bloqueada o baneada."
		429:
			return "Demasiados intentos seguidos. Espera un momento y reintenta."
		_:
			return "La api rechazó el enlace (HTTP %d)." % code


func _on_respuesta(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_boton.disabled = false
	# El transporte se comprueba ANTES de mirar el modo: "no hay api" se cuenta
	# igual en el enlace que en el alta, y es el unico fallo que los dos comparten.
	var red := _fallo_de_red(result)
	if red != "":
		_error(red)
		return
	if _modo == "alta":
		_respuesta_alta(code)
		return
	if code != 200:
		_error(_motivo_enlace(code))
		return
	var datos: Dictionary = JSON.parse_string(body.get_string_from_utf8())
	Session.account_id = int(datos.account_id)
	Session.pilot_name = datos.pilot_name
	Session.session_token = datos.session_token
	Session.game_ticket = datos.game_ticket
	Session.game_host = datos.game_host
	_status.add_theme_color_override("font_color", NTheme.MUTED)
	_status.text = "Sesión OK (cuenta %d). Abriendo enlace con el sector..." % Session.account_id
	get_tree().change_scene_to_file.call_deferred("res://game/world.tscn")


## Cada codigo del server dice algo distinto y el jugador merece saber CUAL es su
## caso: "ya existe" se arregla cambiando el nombre y "registro cerrado" no se
## arregla de ninguna manera. Un mensaje generico los junta y hace que el jugador
## pruebe diez nombres contra una puerta cerrada.
func _respuesta_alta(code: int) -> void:
	match code:
		200:
			_status.add_theme_color_override("font_color", NTheme.HP)
			_status.text = "Cuenta creada. Entrando..."
			# entra solo: acaba de teclear estos mismos datos, pedirlos otra vez
			# no comprueba nada y solo cansa
			_modo = "enlace"
			_aplicar_modo()
			_login.call_deferred()
		403:
			_error("El registro esta cerrado en este servidor.")
		409:
			_error("Ese usuario o ese nombre de piloto ya existen.")
		400:
			_error("El servidor rechazo los datos. Revisa usuario, piloto y contraseña.")
		_:
			_error("No se pudo crear la cuenta (HTTP %d)." % code)
