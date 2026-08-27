# La conexion al game server: WebSocket + contrato generado.
# Emite señales tipadas; el mundo no toca bytes jamas.
class_name GameConnection
extends Node

signal welcome(msg)          # MexProtocol.Welcome
signal enter_map(msg)        # MexProtocol.EnterMap
signal entity_spawn(msg)
signal entity_despawn(msg)
signal entity_move(msg)
signal hero_stats(msg)
signal target_info(msg)
signal attack_event(msg)
signal entity_destroyed(msg)
signal box_spawn(msg)
signal box_despawn(msg)
signal collect_result(msg)
signal storage_state(msg)
signal npc_prices(msg)
signal station_range(msg)
signal unload_result(msg)
signal sell_result(msg)
signal respawn_options(msg)
signal chat_message(msg)
signal resume_ok
signal jump_handoff(msg)
signal error_reply(msg)
signal session_replaced
signal disconnected

var _ws := WebSocketPeer.new()
var _abierto := false
var _ticket_pendiente := ""
var _url := ""
## Token de reconexion (lo entrega Welcome): con el se vuelve a la misma nave
## dentro de la ventana de gracia, sin pasar por la api.
var reconnect_token := ""
var _reanudando := false
var _reteniendo := false
var _buzon: Array[PackedByteArray] = []
var _reten_t0 := 0
var _reten_listo := -1


func connect_to(url: String, ticket: String) -> void:
	_url = url
	_ticket_pendiente = ticket
	_reanudando = false
	_abierto = false
	_ws = WebSocketPeer.new()
	_ws.connect_to_url(url)
	set_process(true)


## Reintento de reconexion con el token: el server nos devuelve nuestra nave.
func reconnect() -> void:
	if reconnect_token == "":
		return
	_reanudando = true
	_abierto = false
	_ws = WebSocketPeer.new()
	_ws.connect_to_url(_url)
	set_process(true)


## Reconecta contra OTRA direccion: es el salto de sector.
##
## No hace falta credencial nueva. El token de reconexion ya identifica la
## sesion y vale contra cualquier game server —la sesion vive en BD, no en la
## memoria de un proceso—, y el estado de la nave ya quedo persistido EN EL MAPA
## DESTINO antes de que el server cerrara el socket. Reconectar, por tanto,
## aterriza donde toca sin que el cliente tenga que decir a donde va.
func saltar_a(url: String) -> void:
	if reconnect_token == "":
		return
	_url = url
	reconnect()


## Corta el socket como si se cayera la red (autotest de reconexion).
func simular_caida() -> void:
	_ws.close(4000, "prueba de reconexion")


func _process(_delta: float) -> void:
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _abierto:
				_abierto = true
				if _reanudando:
					var resume := MexProtocol.Resume.new()
					resume.protocol_version = 1
					resume.reconnect_token = reconnect_token
					_ws.put_packet(resume.encode())
				else:
					var hello := MexProtocol.Hello.new()
					hello.protocol_version = 1
					hello.game_ticket = _ticket_pendiente
					_ws.put_packet(hello.encode())
			while _ws.get_available_packet_count() > 0:
				_despachar(_ws.get_packet())
		WebSocketPeer.STATE_CLOSED:
			if _abierto:
				_abierto = false
				disconnected.emit()
			set_process(false)


func send(frame: PackedByteArray) -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.put_packet(frame)


## Retener la llegada: lo que mande el server se guarda en vez de aplicarse.
##
## Sirve para conectar con el mapa destino EN PARALELO a la animacion del portal
## sin que el mundo nuevo se cuele en el viejo. Antes se retrasaba la conexion
## entera hasta terminar la animacion, y eso funcionaba en local —donde conectar
## cuesta nada— pero tiraba a la basura el motivo de tener 2,1 s de animacion: en
## cuanto el mapa destino viva en otra maquina, abrir el socket y hacer el
## handshake son cientos de milisegundos que se pagarian DESPUES, sumados en vez
## de solapados.
func retener() -> void:
	_reteniendo = true
	_buzon.clear()
	_reten_t0 = Time.get_ticks_msec()
	_reten_listo = -1


## Y soltarla de golpe, en orden. Quien llama decide cuando: normalmente al
## terminar el encendido del portal.
func soltar() -> void:
	if not _reteniendo:
		return
	_reteniendo = false
	if _reten_listo >= 0:
		print("SALTO conexion nueva lista en %d ms · se suelta a los %d ms · holgura %d ms"
			% [_reten_listo, Time.get_ticks_msec() - _reten_t0,
			   Time.get_ticks_msec() - _reten_t0 - _reten_listo])
	var pendientes := _buzon.duplicate()
	_buzon.clear()
	for frame: PackedByteArray in pendientes:
		_despachar(frame)


func _despachar(frame: PackedByteArray) -> void:
	var id := _msg_id(frame)
	# El Ping se contesta SIEMPRE, retenidos o no: es del transporte, no del
	# mundo. Guardarlo dos segundos seria dejar que el server nos diera por
	# muertos justo mientras llegamos.
	if _reteniendo and id != MexProtocol.Ping.MSG_ID:
		# el EnterMap es la senial de que el mapa destino ya esta sincronizado:
		# con eso se mide cuanta HOLGURA deja la animacion
		if id == MexProtocol.EnterMap.MSG_ID and _reten_listo < 0:
			_reten_listo = Time.get_ticks_msec() - _reten_t0
		_buzon.append(frame)
		return
	match id:
		MexProtocol.Welcome.MSG_ID: welcome.emit(MexProtocol.Welcome.decode(frame))
		MexProtocol.EnterMap.MSG_ID: enter_map.emit(MexProtocol.EnterMap.decode(frame))
		MexProtocol.EntitySpawn.MSG_ID: entity_spawn.emit(MexProtocol.EntitySpawn.decode(frame))
		MexProtocol.EntityDespawn.MSG_ID: entity_despawn.emit(MexProtocol.EntityDespawn.decode(frame))
		MexProtocol.EntityMove.MSG_ID: entity_move.emit(MexProtocol.EntityMove.decode(frame))
		MexProtocol.HeroStats.MSG_ID: hero_stats.emit(MexProtocol.HeroStats.decode(frame))
		MexProtocol.TargetInfo.MSG_ID: target_info.emit(MexProtocol.TargetInfo.decode(frame))
		MexProtocol.AttackEvent.MSG_ID: attack_event.emit(MexProtocol.AttackEvent.decode(frame))
		MexProtocol.EntityDestroyed.MSG_ID: entity_destroyed.emit(MexProtocol.EntityDestroyed.decode(frame))
		MexProtocol.BoxSpawn.MSG_ID: box_spawn.emit(MexProtocol.BoxSpawn.decode(frame))
		MexProtocol.BoxDespawn.MSG_ID: box_despawn.emit(MexProtocol.BoxDespawn.decode(frame))
		MexProtocol.CollectResult.MSG_ID: collect_result.emit(MexProtocol.CollectResult.decode(frame))
		MexProtocol.StorageState.MSG_ID: storage_state.emit(MexProtocol.StorageState.decode(frame))
		MexProtocol.NpcPrices.MSG_ID: npc_prices.emit(MexProtocol.NpcPrices.decode(frame))
		MexProtocol.StationRange.MSG_ID: station_range.emit(MexProtocol.StationRange.decode(frame))
		MexProtocol.UnloadResult.MSG_ID: unload_result.emit(MexProtocol.UnloadResult.decode(frame))
		MexProtocol.SellResult.MSG_ID: sell_result.emit(MexProtocol.SellResult.decode(frame))
		MexProtocol.RespawnOptions.MSG_ID: respawn_options.emit(MexProtocol.RespawnOptions.decode(frame))
		MexProtocol.Ping.MSG_ID:
			var pong := MexProtocol.Pong.new()
			pong.nonce = MexProtocol.Ping.decode(frame).nonce
			send(pong.encode())
		MexProtocol.ChatMessage.MSG_ID: chat_message.emit(MexProtocol.ChatMessage.decode(frame))
		MexProtocol.ResumeOk.MSG_ID: resume_ok.emit()
		MexProtocol.JumpHandoff.MSG_ID: jump_handoff.emit(MexProtocol.JumpHandoff.decode(frame))
		MexProtocol.ErrorReply.MSG_ID: error_reply.emit(MexProtocol.ErrorReply.decode(frame))
		MexProtocol.SessionReplaced.MSG_ID: session_replaced.emit()
		_: pass   # mensaje desconocido: se ignora (el contrato es saltable)


static func _msg_id(frame: PackedByteArray) -> int:
	var id := 0
	var shift := 0
	for i in mini(frame.size(), 4):
		var b := frame[i]
		id |= (b & 0x7F) << shift
		if (b & 0x80) == 0:
			return id
		shift += 7
	return -1
