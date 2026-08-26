# Autoload: el estado de la sesion entre escenas (ticket, cuenta, hosts).
# dev_login.cfg (NO versionado) permite precargar credenciales de dev.
extends Node

var api_base := "http://127.0.0.1:5100"
var game_host := ""
var game_ticket := ""
var session_token := ""
var account_id := 0
var pilot_name := ""

# argumentos de autotest (--screenshot=ruta.png): volar solo y guardar captura
var autotest_screenshot := ""
## Que prueba corre. "loop" es la pasada e2e completa que cierra el gate; para
## trabajo de arte esa pasada es un peaje de tres minutos, asi que "bestiario"
## solo retrata a cada bicho y sale.
var autotest_modo := "loop"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			autotest_screenshot = arg.trim_prefix("--screenshot=")
		elif arg.begins_with("--modo="):
			autotest_modo = arg.trim_prefix("--modo=")


## Credenciales de dev desde dev_login.cfg (fuera del repo).
## Se parsea a mano en vez de con ConfigFile porque el archivo suele generarse
## desde PowerShell, que lo escribe con BOM: ConfigFile no reconoce la seccion
## con esos bytes invisibles delante y el login salia vacio.
func dev_credentials() -> Dictionary:
	var salida := {"username": "", "password": ""}
	const RUTA := "res://dev_login.cfg"
	if not FileAccess.file_exists(RUTA):
		return salida
	var texto := FileAccess.get_file_as_string(RUTA)
	for linea in texto.split("\n"):
		var l := linea.strip_edges()
		if l.is_empty() or l.begins_with(";") or l.begins_with("#") or l.begins_with("["):
			continue
		var partes := l.split("=", true, 1)
		if partes.size() != 2:
			continue
		var clave := partes[0].strip_edges()
		var valor := partes[1].strip_edges().trim_prefix("\"").trim_suffix("\"")
		if salida.has(clave):
			salida[clave] = valor
	return salida
