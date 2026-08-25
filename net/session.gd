# Autoload: el estado de la sesion entre escenas (ticket, cuenta, hosts).
# dev_login.cfg (NO versionado) permite precargar credenciales de dev.
extends Node

var api_base := "http://127.0.0.1:5100"
var game_host := ""
var game_ticket := ""
var session_token := ""
var account_id := 0
var pilot_name := ""

# argumentos de autotest (--autotest ruta.png): volar solo y guardar captura
var autotest_screenshot := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			autotest_screenshot = arg.trim_prefix("--screenshot=")


func dev_credentials() -> Dictionary:
	# precarga de dev: user://../dev_login.cfg o res://dev_login.cfg (ignorado por git)
	var cfg := ConfigFile.new()
	if cfg.load("res://dev_login.cfg") == OK:
		return {
			"username": cfg.get_value("login", "username", ""),
			"password": cfg.get_value("login", "password", ""),
		}
	return {"username": "", "password": ""}
