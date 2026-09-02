# Autoload: el estado de la sesion entre escenas (ticket, cuenta, hosts).
# dev_login.cfg (NO versionado) permite precargar credenciales de dev.
extends Node

## Diales de data/config/net.json (sub-objeto `session`). AssetDefs no depende
## de Session, asi que leerlo desde este autoload no cierra ningun ciclo.
static var CFG: Dictionary = AssetDefs.config("net").get("session", {})
## A donde llama el cliente en escritorio si project.godot no lo dice.
static var API_BASE_DEFAULT: String = str(CFG.get("api_base_default", "http://127.0.0.1:5100"))
## Ruta de la api dentro del mismo origen, en web, si project.godot no la dice.
static var API_PATH_DEFAULT: String = str(CFG.get("api_path_default", "/api"))
## Credenciales de dev (fuera del repo).
static var DEV_LOGIN_PATH: String = str(CFG.get("dev_login_path", "res://dev_login.cfg"))

var api_base := ""            # se resuelve en _ready(): ver project.godot [mexorbit]
var game_host := ""
var game_ticket := ""
var session_token := ""
var account_id := 0
var pilot_name := ""

# argumentos de autotest (--screenshot=ruta.png): volar solo y guardar captura
var autotest_screenshot := ""
## Que prueba corre. "loop" es la pasada e2e completa que cierra el gate; para
## trabajo de arte esa pasada es un peaje de tres minutos, asi que "bestiary"
## solo retrata a cada bicho y sale.
var autotest_mode := "loop"
## Preajuste de calidad forzado por linea de comandos (--quality=baja|media|alta).
## Lo usa la prueba para retratar la MISMA escena en los tres niveles; vacio =
## se respeta lo que el jugador tenga guardado.
var forced_quality := ""


func _ready() -> void:
	api_base = _resolve_api()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--api="):
			api_base = arg.trim_prefix("--api=")
		elif arg.begins_with("--screenshot="):
			autotest_screenshot = arg.trim_prefix("--screenshot=")
		elif arg.begins_with("--mode="):
			autotest_mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--quality="):
			forced_quality = arg.trim_prefix("--quality=")


## A donde llama el cliente.
##
## EN EL NAVEGADOR se deduce del ORIGEN DE LA PAGINA, no de un ajuste. La
## primera version usaba la anulacion por feature de project.godot
## (`api_base.web`) y no funcionaba, por dos motivos que conviene no repetir:
##
##   1. `ProjectSettings.get_setting()` NO aplica las anulaciones. Devuelve el
##      valor crudo. La que las aplica es `get_setting_with_override()`, y la
##      diferencia no se nota en escritorio —donde no hay anulacion que aplicar—
##      asi que el fallo solo existia en la unica plataforma que lo necesitaba.
##   2. Aun arreglado, seguiria siendo una URL escrita a mano en un sitio que
##      hay que acordarse de cambiar el dia que cambie el dominio.
##
## Deducirla del origen no puede equivocarse: la api se sirve en `/api` del mismo
## host que sirvio el juego, que es exactamente la razon por la que se monto en
## el mismo origen —evitar CORS—. Si el juego carga, la api esta donde se dice.
##
## En escritorio manda `project.godot`, y un `--api=` por linea de comandos pisa
## las dos: sirve para apuntar un cliente de escritorio a produccion.
func _resolve_api() -> String:
	if OS.has_feature("web"):
		var origin := str(JavaScriptBridge.eval("location.origin", true))
		var path := str(ProjectSettings.get_setting("mexorbit/api_path", API_PATH_DEFAULT))
		# Si el origen no se puede leer se devuelve la ruta a secas, que fallara
		# nombrandola — y eso es informacion. Caer aqui al valor de escritorio
		# seria volver a 127.0.0.1, o sea el fallo que esto viene a arreglar
		# disfrazado de respaldo.
		return (origin + path) if origin != "" else path
	return str(ProjectSettings.get_setting("mexorbit/api_base", API_BASE_DEFAULT))


## Credenciales de dev desde dev_login.cfg (fuera del repo).
## Se parsea a mano en vez de con ConfigFile porque el archivo suele generarse
## desde PowerShell, que lo escribe con BOM: ConfigFile no reconoce la seccion
## con esos bytes invisibles delante y el login salia vacio.
func dev_credentials() -> Dictionary:
	var output := {"username": "", "password": ""}
	if not FileAccess.file_exists(DEV_LOGIN_PATH):
		return output
	var txt := FileAccess.get_file_as_string(DEV_LOGIN_PATH)
	for line in txt.split("\n"):
		var l := line.strip_edges()
		if l.is_empty() or l.begins_with(";") or l.begins_with("#") or l.begins_with("["):
			continue
		var parts := l.split("=", true, 1)
		if parts.size() != 2:
			continue
		var key := parts[0].strip_edges()
		var value := parts[1].strip_edges().trim_prefix("\"").trim_suffix("\"")
		if output.has(key):
			output[key] = value
	return output
