# GENERADO por tools/gen.py — no editar a mano. Fuente: schema/messages.yaml
class_name MexProtocol

enum EntityKind { PLAYER = 0, NPC = 1 }
enum DespawnReason { RANGE = 0, LEFT = 1, DEAD = 2 }
enum BoxDespawnReason { COLLECTED = 0, EXPIRED = 1, RANGE = 2 }
enum Weapon { LASER = 0 }
enum DeathCause { NPC = 0, PLAYER = 1 }
enum StorageReason { COLLECT = 0, REFINE_IN = 1, REFINE_OUT = 2, SELL = 3, UNLOAD = 4 }
enum ChatChannel { GLOBAL = 0, FACTION = 1, CLAN = 2 }
enum ErrorCode { GENERIC = 0, BAD_TICKET = 1, VERSION_UNSUPPORTED = 2, BANNED = 3, RESUME_EXPIRED = 4, TOO_FAR = 5, GONE = 6, INSUFFICIENT = 7, RATE_LIMITED = 8, INVALID = 9 }

class Wire:
	static func write_varint(buf: PackedByteArray, v: int) -> void:
		while v >= 0x80 or v < 0:
			buf.append((v & 0x7F) | 0x80)
			v = v >> 7 if v >= 0 else (v >> 7) & 0x1FFFFFFFFFFFFFF
		buf.append(v)

	static func read_varint(b: PackedByteArray, pos: Array) -> int:
		var v := 0
		var shift := 0
		while true:
			assert(pos[0] < b.size(), "varint truncado")
			var x := b[pos[0]]
			pos[0] += 1
			v |= (x & 0x7F) << shift
			if (x & 0x80) == 0:
				return v
			shift += 7
			assert(shift <= 63, "varint demasiado largo")
		return v

	static func zig(v: int) -> int:
		return (v << 1) ^ (v >> 63)

	static func zag(u: int) -> int:
		return (u >> 1) ^ -(u & 1)

	static func write_tag(buf: PackedByteArray, tag: int, wt: int) -> void:
		write_varint(buf, (tag << 3) | wt)

	static func write_string(buf: PackedByteArray, v: String) -> void:
		var bytes := v.to_utf8_buffer()
		write_varint(buf, bytes.size())
		buf.append_array(bytes)

	static func read_string(b: PackedByteArray, pos: Array) -> String:
		var len := read_varint(b, pos)
		assert(pos[0] + len <= b.size(), "string truncado")
		var s := b.slice(pos[0], pos[0] + len).get_string_from_utf8()
		pos[0] += len
		return s

	static func write_f32(buf: PackedByteArray, v: float) -> void:
		var tmp := PackedByteArray()
		tmp.resize(4)
		tmp.encode_float(0, v)
		buf.append_array(tmp)

	static func read_f32(b: PackedByteArray, pos: Array) -> float:
		assert(pos[0] + 4 <= b.size(), "fixed32 truncado")
		var v := b.decode_float(pos[0])
		pos[0] += 4
		return v

	static func read_slice(b: PackedByteArray, pos: Array) -> PackedByteArray:
		var len := read_varint(b, pos)
		assert(pos[0] + len <= b.size(), "submensaje truncado")
		var s := b.slice(pos[0], pos[0] + len)
		pos[0] += len
		return s

	static func skip(b: PackedByteArray, pos: Array, wt: int) -> void:
		match wt:
			0: read_varint(b, pos)
			2:
				var len := read_varint(b, pos)
				pos[0] += len
			5: pos[0] += 4
			_: assert(false, "wiretype desconocido")
		assert(pos[0] <= b.size(), "skip fuera de rango")

class MaterialAmount:
	var material_id: String = ""
	var amount: int = 0

	func validate() -> void:
		assert(material_id.length() <= 64, "MaterialAmount.material_id demasiado largo")
		assert(amount <= 1000000, "MaterialAmount.amount > 1000000")

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 2)
		Wire.write_string(buf, material_id)
		Wire.write_tag(buf, 2, 0)
		Wire.write_varint(buf, amount)

	static func decode_from(b: PackedByteArray, pos: Array) -> MaterialAmount:
		var m := MaterialAmount.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.material_id = Wire.read_string(b, pos)
				2: m.amount = Wire.read_varint(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	static func decode_struct(b: PackedByteArray) -> MaterialAmount:
		return decode_from(b, [0])

class RespawnOption:
	var option_id: int = 0
	var label_key: String = ""
	var cost_credits: int = 0
	var available: bool = false

	func validate() -> void:
		assert(option_id <= 16, "RespawnOption.option_id > 16")
		assert(label_key.length() <= 64, "RespawnOption.label_key demasiado largo")

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, option_id)
		Wire.write_tag(buf, 2, 2)
		Wire.write_string(buf, label_key)
		Wire.write_tag(buf, 3, 0)
		Wire.write_varint(buf, cost_credits)
		Wire.write_tag(buf, 4, 0)
		Wire.write_varint(buf, 1 if available else 0)

	static func decode_from(b: PackedByteArray, pos: Array) -> RespawnOption:
		var m := RespawnOption.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.option_id = Wire.read_varint(b, pos)
				2: m.label_key = Wire.read_string(b, pos)
				3: m.cost_credits = Wire.read_varint(b, pos)
				4: m.available = Wire.read_varint(b, pos) != 0
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	static func decode_struct(b: PackedByteArray) -> RespawnOption:
		return decode_from(b, [0])

class MaterialPrice:
	var material_id: String = ""
	var price_credits: int = 0

	func validate() -> void:
		assert(material_id.length() <= 64, "MaterialPrice.material_id demasiado largo")

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 2)
		Wire.write_string(buf, material_id)
		Wire.write_tag(buf, 2, 0)
		Wire.write_varint(buf, price_credits)

	static func decode_from(b: PackedByteArray, pos: Array) -> MaterialPrice:
		var m := MaterialPrice.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.material_id = Wire.read_string(b, pos)
				2: m.price_credits = Wire.read_varint(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	static func decode_struct(b: PackedByteArray) -> MaterialPrice:
		return decode_from(b, [0])

class Hello:
	const MSG_ID := 1
	var protocol_version: int = 0
	var game_ticket: String = ""

	func validate() -> void:
		assert(protocol_version >= 1, "Hello.protocol_version < 1")
		assert(protocol_version <= 1000, "Hello.protocol_version > 1000")
		assert(game_ticket.length() <= 512, "Hello.game_ticket demasiado largo")

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, protocol_version)
		Wire.write_tag(buf, 2, 2)
		Wire.write_string(buf, game_ticket)

	static func decode_from(b: PackedByteArray, pos: Array) -> Hello:
		var m := Hello.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.protocol_version = Wire.read_varint(b, pos)
				2: m.game_ticket = Wire.read_string(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 1)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> Hello:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 1, "msg_id inesperado")
		return decode_from(b, pos)

class Welcome:
	const MSG_ID := 2
	var account_id: int = 0
	var reconnect_token: String = ""
	var server_time_ms: int = 0
	var tick_rate: int = 0

	func validate() -> void:
		assert(reconnect_token.length() <= 128, "Welcome.reconnect_token demasiado largo")
		assert(tick_rate >= 1, "Welcome.tick_rate < 1")
		assert(tick_rate <= 100, "Welcome.tick_rate > 100")

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, account_id)
		Wire.write_tag(buf, 2, 2)
		Wire.write_string(buf, reconnect_token)
		Wire.write_tag(buf, 3, 0)
		Wire.write_varint(buf, server_time_ms)
		Wire.write_tag(buf, 4, 0)
		Wire.write_varint(buf, tick_rate)

	static func decode_from(b: PackedByteArray, pos: Array) -> Welcome:
		var m := Welcome.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.account_id = Wire.read_varint(b, pos)
				2: m.reconnect_token = Wire.read_string(b, pos)
				3: m.server_time_ms = Wire.read_varint(b, pos)
				4: m.tick_rate = Wire.read_varint(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 2)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> Welcome:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 2, "msg_id inesperado")
		return decode_from(b, pos)

class Resume:
	const MSG_ID := 3
	var protocol_version: int = 0
	var reconnect_token: String = ""

	func validate() -> void:
		assert(protocol_version >= 1, "Resume.protocol_version < 1")
		assert(protocol_version <= 1000, "Resume.protocol_version > 1000")
		assert(reconnect_token.length() <= 128, "Resume.reconnect_token demasiado largo")

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, protocol_version)
		Wire.write_tag(buf, 2, 2)
		Wire.write_string(buf, reconnect_token)

	static func decode_from(b: PackedByteArray, pos: Array) -> Resume:
		var m := Resume.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.protocol_version = Wire.read_varint(b, pos)
				2: m.reconnect_token = Wire.read_string(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 3)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> Resume:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 3, "msg_id inesperado")
		return decode_from(b, pos)

class ResumeOk:
	const MSG_ID := 4

	func validate() -> void:
		pass

	func encode_fields(buf: PackedByteArray) -> void:
		pass

	static func decode_from(b: PackedByteArray, pos: Array) -> ResumeOk:
		var m := ResumeOk.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 4)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> ResumeOk:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 4, "msg_id inesperado")
		return decode_from(b, pos)

class Ping:
	const MSG_ID := 5
	var nonce: int = 0

	func validate() -> void:
		pass

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, nonce)

	static func decode_from(b: PackedByteArray, pos: Array) -> Ping:
		var m := Ping.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.nonce = Wire.read_varint(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 5)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> Ping:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 5, "msg_id inesperado")
		return decode_from(b, pos)

class Pong:
	const MSG_ID := 6
	var nonce: int = 0

	func validate() -> void:
		pass

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, nonce)

	static func decode_from(b: PackedByteArray, pos: Array) -> Pong:
		var m := Pong.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.nonce = Wire.read_varint(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 6)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> Pong:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 6, "msg_id inesperado")
		return decode_from(b, pos)

class ErrorReply:
	const MSG_ID := 7
	var request_id: int = 0
	var code: int = 0
	var detail: String = ""

	func validate() -> void:
		assert(detail.length() <= 256, "ErrorReply.detail demasiado largo")

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, request_id)
		Wire.write_tag(buf, 2, 0)
		Wire.write_varint(buf, code)
		Wire.write_tag(buf, 3, 2)
		Wire.write_string(buf, detail)

	static func decode_from(b: PackedByteArray, pos: Array) -> ErrorReply:
		var m := ErrorReply.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.request_id = Wire.read_varint(b, pos)
				2: m.code = Wire.read_varint(b, pos)
				3: m.detail = Wire.read_string(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 7)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> ErrorReply:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 7, "msg_id inesperado")
		return decode_from(b, pos)

class SessionReplaced:
	const MSG_ID := 8

	func validate() -> void:
		pass

	func encode_fields(buf: PackedByteArray) -> void:
		pass

	static func decode_from(b: PackedByteArray, pos: Array) -> SessionReplaced:
		var m := SessionReplaced.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 8)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> SessionReplaced:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 8, "msg_id inesperado")
		return decode_from(b, pos)

class LogoutRequest:
	const MSG_ID := 9

	func validate() -> void:
		pass

	func encode_fields(buf: PackedByteArray) -> void:
		pass

	static func decode_from(b: PackedByteArray, pos: Array) -> LogoutRequest:
		var m := LogoutRequest.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 9)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> LogoutRequest:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 9, "msg_id inesperado")
		return decode_from(b, pos)

class LogoutCountdown:
	const MSG_ID := 10
	var seconds_left: int = 0

	func validate() -> void:
		assert(seconds_left <= 60, "LogoutCountdown.seconds_left > 60")

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, seconds_left)

	static func decode_from(b: PackedByteArray, pos: Array) -> LogoutCountdown:
		var m := LogoutCountdown.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.seconds_left = Wire.read_varint(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 10)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> LogoutCountdown:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 10, "msg_id inesperado")
		return decode_from(b, pos)

class LogoutDone:
	const MSG_ID := 11

	func validate() -> void:
		pass

	func encode_fields(buf: PackedByteArray) -> void:
		pass

	static func decode_from(b: PackedByteArray, pos: Array) -> LogoutDone:
		var m := LogoutDone.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 11)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> LogoutDone:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 11, "msg_id inesperado")
		return decode_from(b, pos)

class EnterMap:
	const MSG_ID := 50
	var map_id: int = 0
	var map_code: String = ""
	var limits_x: int = 0
	var limits_y: int = 0
	var cargo_risk_pct: int = 0
	var station_x: int = 0
	var station_y: int = 0
	var station_range: int = 0

	func validate() -> void:
		assert(map_code.length() <= 16, "EnterMap.map_code demasiado largo")
		assert(limits_x >= 1000, "EnterMap.limits_x < 1000")
		assert(limits_x <= 100000, "EnterMap.limits_x > 100000")
		assert(limits_y >= 1000, "EnterMap.limits_y < 1000")
		assert(limits_y <= 100000, "EnterMap.limits_y > 100000")
		assert(cargo_risk_pct <= 100, "EnterMap.cargo_risk_pct > 100")
		assert(station_x <= 100000, "EnterMap.station_x > 100000")
		assert(station_y <= 100000, "EnterMap.station_y > 100000")
		assert(station_range <= 10000, "EnterMap.station_range > 10000")

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, map_id)
		Wire.write_tag(buf, 2, 2)
		Wire.write_string(buf, map_code)
		Wire.write_tag(buf, 3, 0)
		Wire.write_varint(buf, limits_x)
		Wire.write_tag(buf, 4, 0)
		Wire.write_varint(buf, limits_y)
		Wire.write_tag(buf, 5, 0)
		Wire.write_varint(buf, cargo_risk_pct)
		Wire.write_tag(buf, 6, 0)
		Wire.write_varint(buf, station_x)
		Wire.write_tag(buf, 7, 0)
		Wire.write_varint(buf, station_y)
		Wire.write_tag(buf, 8, 0)
		Wire.write_varint(buf, station_range)

	static func decode_from(b: PackedByteArray, pos: Array) -> EnterMap:
		var m := EnterMap.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.map_id = Wire.read_varint(b, pos)
				2: m.map_code = Wire.read_string(b, pos)
				3: m.limits_x = Wire.read_varint(b, pos)
				4: m.limits_y = Wire.read_varint(b, pos)
				5: m.cargo_risk_pct = Wire.read_varint(b, pos)
				6: m.station_x = Wire.read_varint(b, pos)
				7: m.station_y = Wire.read_varint(b, pos)
				8: m.station_range = Wire.read_varint(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 50)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> EnterMap:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 50, "msg_id inesperado")
		return decode_from(b, pos)

class EntitySpawn:
	const MSG_ID := 52
	var entity_id: int = 0
	var kind: int = 0
	var type_id: String = ""
	var name: String = ""
	var faction: int = 0
	var x: int = 0
	var y: int = 0
	var hp_pct: float = 0.0
	var speed: int = 0
	var shield_pct: float = 0.0

	func validate() -> void:
		assert(type_id.length() <= 64, "EntitySpawn.type_id demasiado largo")
		assert(name.length() <= 64, "EntitySpawn.name demasiado largo")
		assert(faction <= 8, "EntitySpawn.faction > 8")
		assert(x <= 100000, "EntitySpawn.x > 100000")
		assert(y <= 100000, "EntitySpawn.y > 100000")
		assert(speed <= 2000, "EntitySpawn.speed > 2000")

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, entity_id)
		Wire.write_tag(buf, 2, 0)
		Wire.write_varint(buf, kind)
		Wire.write_tag(buf, 3, 2)
		Wire.write_string(buf, type_id)
		Wire.write_tag(buf, 4, 2)
		Wire.write_string(buf, name)
		Wire.write_tag(buf, 5, 0)
		Wire.write_varint(buf, faction)
		Wire.write_tag(buf, 6, 0)
		Wire.write_varint(buf, x)
		Wire.write_tag(buf, 7, 0)
		Wire.write_varint(buf, y)
		Wire.write_tag(buf, 8, 5)
		Wire.write_f32(buf, hp_pct)
		Wire.write_tag(buf, 9, 0)
		Wire.write_varint(buf, speed)
		Wire.write_tag(buf, 10, 5)
		Wire.write_f32(buf, shield_pct)

	static func decode_from(b: PackedByteArray, pos: Array) -> EntitySpawn:
		var m := EntitySpawn.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.entity_id = Wire.read_varint(b, pos)
				2: m.kind = Wire.read_varint(b, pos)
				3: m.type_id = Wire.read_string(b, pos)
				4: m.name = Wire.read_string(b, pos)
				5: m.faction = Wire.read_varint(b, pos)
				6: m.x = Wire.read_varint(b, pos)
				7: m.y = Wire.read_varint(b, pos)
				8: m.hp_pct = Wire.read_f32(b, pos)
				9: m.speed = Wire.read_varint(b, pos)
				10: m.shield_pct = Wire.read_f32(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 52)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> EntitySpawn:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 52, "msg_id inesperado")
		return decode_from(b, pos)

class EntityDespawn:
	const MSG_ID := 53
	var entity_id: int = 0
	var reason: int = 0

	func validate() -> void:
		pass

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, entity_id)
		Wire.write_tag(buf, 2, 0)
		Wire.write_varint(buf, reason)

	static func decode_from(b: PackedByteArray, pos: Array) -> EntityDespawn:
		var m := EntityDespawn.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.entity_id = Wire.read_varint(b, pos)
				2: m.reason = Wire.read_varint(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 53)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> EntityDespawn:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 53, "msg_id inesperado")
		return decode_from(b, pos)

class EntityMove:
	const MSG_ID := 54
	var entity_id: int = 0
	var x: int = 0
	var y: int = 0
	var target_x: int = 0
	var target_y: int = 0
	var speed: int = 0
	var teleport: bool = false

	func validate() -> void:
		assert(x <= 100000, "EntityMove.x > 100000")
		assert(y <= 100000, "EntityMove.y > 100000")
		assert(target_x <= 100000, "EntityMove.target_x > 100000")
		assert(target_y <= 100000, "EntityMove.target_y > 100000")
		assert(speed <= 2000, "EntityMove.speed > 2000")

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, entity_id)
		Wire.write_tag(buf, 2, 0)
		Wire.write_varint(buf, x)
		Wire.write_tag(buf, 3, 0)
		Wire.write_varint(buf, y)
		Wire.write_tag(buf, 4, 0)
		Wire.write_varint(buf, target_x)
		Wire.write_tag(buf, 5, 0)
		Wire.write_varint(buf, target_y)
		Wire.write_tag(buf, 6, 0)
		Wire.write_varint(buf, speed)
		Wire.write_tag(buf, 7, 0)
		Wire.write_varint(buf, 1 if teleport else 0)

	static func decode_from(b: PackedByteArray, pos: Array) -> EntityMove:
		var m := EntityMove.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.entity_id = Wire.read_varint(b, pos)
				2: m.x = Wire.read_varint(b, pos)
				3: m.y = Wire.read_varint(b, pos)
				4: m.target_x = Wire.read_varint(b, pos)
				5: m.target_y = Wire.read_varint(b, pos)
				6: m.speed = Wire.read_varint(b, pos)
				7: m.teleport = Wire.read_varint(b, pos) != 0
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 54)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> EntityMove:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 54, "msg_id inesperado")
		return decode_from(b, pos)

class SpeedChange:
	const MSG_ID := 55
	var entity_id: int = 0
	var speed: int = 0

	func validate() -> void:
		assert(speed <= 2000, "SpeedChange.speed > 2000")

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, entity_id)
		Wire.write_tag(buf, 2, 0)
		Wire.write_varint(buf, speed)

	static func decode_from(b: PackedByteArray, pos: Array) -> SpeedChange:
		var m := SpeedChange.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.entity_id = Wire.read_varint(b, pos)
				2: m.speed = Wire.read_varint(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 55)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> SpeedChange:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 55, "msg_id inesperado")
		return decode_from(b, pos)

class HeroStats:
	const MSG_ID := 56
	var hp: int = 0
	var max_hp: int = 0
	var shield: int = 0
	var max_shield: int = 0
	var cargo: int = 0
	var max_cargo: int = 0
	var credits: int = 0
	var experience: int = 0
	var level: int = 0

	func validate() -> void:
		assert(level <= 200, "HeroStats.level > 200")

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, hp)
		Wire.write_tag(buf, 2, 0)
		Wire.write_varint(buf, max_hp)
		Wire.write_tag(buf, 3, 0)
		Wire.write_varint(buf, shield)
		Wire.write_tag(buf, 4, 0)
		Wire.write_varint(buf, max_shield)
		Wire.write_tag(buf, 5, 0)
		Wire.write_varint(buf, cargo)
		Wire.write_tag(buf, 6, 0)
		Wire.write_varint(buf, max_cargo)
		Wire.write_tag(buf, 7, 0)
		Wire.write_varint(buf, credits)
		Wire.write_tag(buf, 8, 0)
		Wire.write_varint(buf, experience)
		Wire.write_tag(buf, 9, 0)
		Wire.write_varint(buf, level)

	static func decode_from(b: PackedByteArray, pos: Array) -> HeroStats:
		var m := HeroStats.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.hp = Wire.read_varint(b, pos)
				2: m.max_hp = Wire.read_varint(b, pos)
				3: m.shield = Wire.read_varint(b, pos)
				4: m.max_shield = Wire.read_varint(b, pos)
				5: m.cargo = Wire.read_varint(b, pos)
				6: m.max_cargo = Wire.read_varint(b, pos)
				7: m.credits = Wire.read_varint(b, pos)
				8: m.experience = Wire.read_varint(b, pos)
				9: m.level = Wire.read_varint(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 56)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> HeroStats:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 56, "msg_id inesperado")
		return decode_from(b, pos)

class MoveIntent:
	const MSG_ID := 60
	var seq: int = 0
	var target_x: int = 0
	var target_y: int = 0

	func validate() -> void:
		assert(target_x >= 0, "MoveIntent.target_x < 0")
		assert(target_x <= 100000, "MoveIntent.target_x > 100000")
		assert(target_y >= 0, "MoveIntent.target_y < 0")
		assert(target_y <= 100000, "MoveIntent.target_y > 100000")

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, seq)
		Wire.write_tag(buf, 2, 0)
		Wire.write_varint(buf, target_x)
		Wire.write_tag(buf, 3, 0)
		Wire.write_varint(buf, target_y)

	static func decode_from(b: PackedByteArray, pos: Array) -> MoveIntent:
		var m := MoveIntent.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.seq = Wire.read_varint(b, pos)
				2: m.target_x = Wire.read_varint(b, pos)
				3: m.target_y = Wire.read_varint(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 60)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> MoveIntent:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 60, "msg_id inesperado")
		return decode_from(b, pos)

class SelectTarget:
	const MSG_ID := 100
	var entity_id: int = 0

	func validate() -> void:
		pass

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, entity_id)

	static func decode_from(b: PackedByteArray, pos: Array) -> SelectTarget:
		var m := SelectTarget.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.entity_id = Wire.read_varint(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 100)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> SelectTarget:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 100, "msg_id inesperado")
		return decode_from(b, pos)

class TargetInfo:
	const MSG_ID := 101
	var entity_id: int = 0
	var hp: int = 0
	var max_hp: int = 0
	var shield: int = 0
	var max_shield: int = 0

	func validate() -> void:
		pass

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, entity_id)
		Wire.write_tag(buf, 2, 0)
		Wire.write_varint(buf, hp)
		Wire.write_tag(buf, 3, 0)
		Wire.write_varint(buf, max_hp)
		Wire.write_tag(buf, 4, 0)
		Wire.write_varint(buf, shield)
		Wire.write_tag(buf, 5, 0)
		Wire.write_varint(buf, max_shield)

	static func decode_from(b: PackedByteArray, pos: Array) -> TargetInfo:
		var m := TargetInfo.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.entity_id = Wire.read_varint(b, pos)
				2: m.hp = Wire.read_varint(b, pos)
				3: m.max_hp = Wire.read_varint(b, pos)
				4: m.shield = Wire.read_varint(b, pos)
				5: m.max_shield = Wire.read_varint(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 101)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> TargetInfo:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 101, "msg_id inesperado")
		return decode_from(b, pos)

class LaserToggle:
	const MSG_ID := 102
	var active: bool = false

	func validate() -> void:
		pass

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, 1 if active else 0)

	static func decode_from(b: PackedByteArray, pos: Array) -> LaserToggle:
		var m := LaserToggle.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.active = Wire.read_varint(b, pos) != 0
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 102)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> LaserToggle:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 102, "msg_id inesperado")
		return decode_from(b, pos)

class AttackEvent:
	const MSG_ID := 103
	var attacker_id: int = 0
	var target_id: int = 0
	var weapon: int = 0
	var damage: int = 0
	var target_hp: int = 0
	var target_shield: int = 0
	var missed: bool = false
	var ammo_id: String = ""
	var skilled: bool = false

	func validate() -> void:
		assert(ammo_id.length() <= 64, "AttackEvent.ammo_id demasiado largo")

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, attacker_id)
		Wire.write_tag(buf, 2, 0)
		Wire.write_varint(buf, target_id)
		Wire.write_tag(buf, 3, 0)
		Wire.write_varint(buf, weapon)
		Wire.write_tag(buf, 4, 0)
		Wire.write_varint(buf, damage)
		Wire.write_tag(buf, 5, 0)
		Wire.write_varint(buf, target_hp)
		Wire.write_tag(buf, 6, 0)
		Wire.write_varint(buf, target_shield)
		Wire.write_tag(buf, 7, 0)
		Wire.write_varint(buf, 1 if missed else 0)
		Wire.write_tag(buf, 8, 2)
		Wire.write_string(buf, ammo_id)
		Wire.write_tag(buf, 9, 0)
		Wire.write_varint(buf, 1 if skilled else 0)

	static func decode_from(b: PackedByteArray, pos: Array) -> AttackEvent:
		var m := AttackEvent.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.attacker_id = Wire.read_varint(b, pos)
				2: m.target_id = Wire.read_varint(b, pos)
				3: m.weapon = Wire.read_varint(b, pos)
				4: m.damage = Wire.read_varint(b, pos)
				5: m.target_hp = Wire.read_varint(b, pos)
				6: m.target_shield = Wire.read_varint(b, pos)
				7: m.missed = Wire.read_varint(b, pos) != 0
				8: m.ammo_id = Wire.read_string(b, pos)
				9: m.skilled = Wire.read_varint(b, pos) != 0
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 103)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> AttackEvent:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 103, "msg_id inesperado")
		return decode_from(b, pos)

class EntityDestroyed:
	const MSG_ID := 104
	var entity_id: int = 0
	var killer_id: int = 0

	func validate() -> void:
		pass

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, entity_id)
		Wire.write_tag(buf, 2, 0)
		Wire.write_varint(buf, killer_id)

	static func decode_from(b: PackedByteArray, pos: Array) -> EntityDestroyed:
		var m := EntityDestroyed.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.entity_id = Wire.read_varint(b, pos)
				2: m.killer_id = Wire.read_varint(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 104)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> EntityDestroyed:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 104, "msg_id inesperado")
		return decode_from(b, pos)

class RespawnOptions:
	const MSG_ID := 105
	var options: Array = []
	var cause: int = 0
	var killer_name: String = ""

	func validate() -> void:
		for v in options:
			v.validate()
		assert(killer_name.length() <= 64, "RespawnOptions.killer_name demasiado largo")

	func encode_fields(buf: PackedByteArray) -> void:
		for v in options:
			Wire.write_tag(buf, 1, 2)
			var sub_1 := PackedByteArray()
			v.encode_fields(sub_1)
			Wire.write_varint(buf, sub_1.size())
			buf.append_array(sub_1)
		Wire.write_tag(buf, 2, 0)
		Wire.write_varint(buf, cause)
		Wire.write_tag(buf, 3, 2)
		Wire.write_string(buf, killer_name)

	static func decode_from(b: PackedByteArray, pos: Array) -> RespawnOptions:
		var m := RespawnOptions.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.options.append(RespawnOption.decode_struct(Wire.read_slice(b, pos)))
				2: m.cause = Wire.read_varint(b, pos)
				3: m.killer_name = Wire.read_string(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 105)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> RespawnOptions:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 105, "msg_id inesperado")
		return decode_from(b, pos)

class RespawnSelect:
	const MSG_ID := 106
	var option_id: int = 0

	func validate() -> void:
		assert(option_id <= 16, "RespawnSelect.option_id > 16")

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, option_id)

	static func decode_from(b: PackedByteArray, pos: Array) -> RespawnSelect:
		var m := RespawnSelect.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.option_id = Wire.read_varint(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 106)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> RespawnSelect:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 106, "msg_id inesperado")
		return decode_from(b, pos)

class BoxSpawn:
	const MSG_ID := 150
	var box_id: int = 0
	var box_type: String = ""
	var x: int = 0
	var y: int = 0

	func validate() -> void:
		assert(box_type.length() <= 32, "BoxSpawn.box_type demasiado largo")
		assert(x <= 100000, "BoxSpawn.x > 100000")
		assert(y <= 100000, "BoxSpawn.y > 100000")

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, box_id)
		Wire.write_tag(buf, 2, 2)
		Wire.write_string(buf, box_type)
		Wire.write_tag(buf, 3, 0)
		Wire.write_varint(buf, x)
		Wire.write_tag(buf, 4, 0)
		Wire.write_varint(buf, y)

	static func decode_from(b: PackedByteArray, pos: Array) -> BoxSpawn:
		var m := BoxSpawn.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.box_id = Wire.read_varint(b, pos)
				2: m.box_type = Wire.read_string(b, pos)
				3: m.x = Wire.read_varint(b, pos)
				4: m.y = Wire.read_varint(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 150)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> BoxSpawn:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 150, "msg_id inesperado")
		return decode_from(b, pos)

class BoxDespawn:
	const MSG_ID := 151
	var box_id: int = 0
	var reason: int = 0

	func validate() -> void:
		pass

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, box_id)
		Wire.write_tag(buf, 2, 0)
		Wire.write_varint(buf, reason)

	static func decode_from(b: PackedByteArray, pos: Array) -> BoxDespawn:
		var m := BoxDespawn.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.box_id = Wire.read_varint(b, pos)
				2: m.reason = Wire.read_varint(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 151)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> BoxDespawn:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 151, "msg_id inesperado")
		return decode_from(b, pos)

class CollectBox:
	const MSG_ID := 152
	var request_id: int = 0
	var box_id: int = 0

	func validate() -> void:
		pass

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, request_id)
		Wire.write_tag(buf, 2, 0)
		Wire.write_varint(buf, box_id)

	static func decode_from(b: PackedByteArray, pos: Array) -> CollectBox:
		var m := CollectBox.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.request_id = Wire.read_varint(b, pos)
				2: m.box_id = Wire.read_varint(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 152)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> CollectBox:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 152, "msg_id inesperado")
		return decode_from(b, pos)

class CollectResult:
	const MSG_ID := 153
	var request_id: int = 0
	var drops: Array = []

	func validate() -> void:
		for v in drops:
			v.validate()

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, request_id)
		for v in drops:
			Wire.write_tag(buf, 2, 2)
			var sub_2 := PackedByteArray()
			v.encode_fields(sub_2)
			Wire.write_varint(buf, sub_2.size())
			buf.append_array(sub_2)

	static func decode_from(b: PackedByteArray, pos: Array) -> CollectResult:
		var m := CollectResult.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.request_id = Wire.read_varint(b, pos)
				2: m.drops.append(MaterialAmount.decode_struct(Wire.read_slice(b, pos)))
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 153)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> CollectResult:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 153, "msg_id inesperado")
		return decode_from(b, pos)

class StorageState:
	const MSG_ID := 154
	var materials: Array = []

	func validate() -> void:
		for v in materials:
			v.validate()

	func encode_fields(buf: PackedByteArray) -> void:
		for v in materials:
			Wire.write_tag(buf, 1, 2)
			var sub_1 := PackedByteArray()
			v.encode_fields(sub_1)
			Wire.write_varint(buf, sub_1.size())
			buf.append_array(sub_1)

	static func decode_from(b: PackedByteArray, pos: Array) -> StorageState:
		var m := StorageState.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.materials.append(MaterialAmount.decode_struct(Wire.read_slice(b, pos)))
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 154)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> StorageState:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 154, "msg_id inesperado")
		return decode_from(b, pos)

class StorageDelta:
	const MSG_ID := 155
	var material_id: String = ""
	var delta: int = 0
	var reason: int = 0

	func validate() -> void:
		assert(material_id.length() <= 64, "StorageDelta.material_id demasiado largo")

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 2)
		Wire.write_string(buf, material_id)
		Wire.write_tag(buf, 2, 0)
		Wire.write_varint(buf, Wire.zig(delta))
		Wire.write_tag(buf, 3, 0)
		Wire.write_varint(buf, reason)

	static func decode_from(b: PackedByteArray, pos: Array) -> StorageDelta:
		var m := StorageDelta.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.material_id = Wire.read_string(b, pos)
				2: m.delta = Wire.zag(Wire.read_varint(b, pos))
				3: m.reason = Wire.read_varint(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 155)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> StorageDelta:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 155, "msg_id inesperado")
		return decode_from(b, pos)

class SellToNpc:
	const MSG_ID := 156
	var request_id: int = 0
	var material_id: String = ""
	var amount: int = 0

	func validate() -> void:
		assert(material_id.length() <= 64, "SellToNpc.material_id demasiado largo")
		assert(amount <= 1000000, "SellToNpc.amount > 1000000")

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, request_id)
		Wire.write_tag(buf, 2, 2)
		Wire.write_string(buf, material_id)
		Wire.write_tag(buf, 3, 0)
		Wire.write_varint(buf, amount)

	static func decode_from(b: PackedByteArray, pos: Array) -> SellToNpc:
		var m := SellToNpc.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.request_id = Wire.read_varint(b, pos)
				2: m.material_id = Wire.read_string(b, pos)
				3: m.amount = Wire.read_varint(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 156)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> SellToNpc:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 156, "msg_id inesperado")
		return decode_from(b, pos)

class SellResult:
	const MSG_ID := 157
	var request_id: int = 0
	var credits_gained: int = 0
	var new_credits: int = 0

	func validate() -> void:
		pass

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, request_id)
		Wire.write_tag(buf, 2, 0)
		Wire.write_varint(buf, credits_gained)
		Wire.write_tag(buf, 3, 0)
		Wire.write_varint(buf, new_credits)

	static func decode_from(b: PackedByteArray, pos: Array) -> SellResult:
		var m := SellResult.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.request_id = Wire.read_varint(b, pos)
				2: m.credits_gained = Wire.read_varint(b, pos)
				3: m.new_credits = Wire.read_varint(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 157)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> SellResult:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 157, "msg_id inesperado")
		return decode_from(b, pos)

class UnloadCargo:
	const MSG_ID := 158
	var request_id: int = 0

	func validate() -> void:
		pass

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, request_id)

	static func decode_from(b: PackedByteArray, pos: Array) -> UnloadCargo:
		var m := UnloadCargo.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.request_id = Wire.read_varint(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 158)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> UnloadCargo:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 158, "msg_id inesperado")
		return decode_from(b, pos)

class UnloadResult:
	const MSG_ID := 159
	var request_id: int = 0
	var stored: Array = []
	var refined: Array = []

	func validate() -> void:
		for v in stored:
			v.validate()
		for v in refined:
			v.validate()

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, request_id)
		for v in stored:
			Wire.write_tag(buf, 2, 2)
			var sub_2 := PackedByteArray()
			v.encode_fields(sub_2)
			Wire.write_varint(buf, sub_2.size())
			buf.append_array(sub_2)
		for v in refined:
			Wire.write_tag(buf, 3, 2)
			var sub_3 := PackedByteArray()
			v.encode_fields(sub_3)
			Wire.write_varint(buf, sub_3.size())
			buf.append_array(sub_3)

	static func decode_from(b: PackedByteArray, pos: Array) -> UnloadResult:
		var m := UnloadResult.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.request_id = Wire.read_varint(b, pos)
				2: m.stored.append(MaterialAmount.decode_struct(Wire.read_slice(b, pos)))
				3: m.refined.append(MaterialAmount.decode_struct(Wire.read_slice(b, pos)))
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 159)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> UnloadResult:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 159, "msg_id inesperado")
		return decode_from(b, pos)

class NpcPrices:
	const MSG_ID := 160
	var prices: Array = []

	func validate() -> void:
		for v in prices:
			v.validate()

	func encode_fields(buf: PackedByteArray) -> void:
		for v in prices:
			Wire.write_tag(buf, 1, 2)
			var sub_1 := PackedByteArray()
			v.encode_fields(sub_1)
			Wire.write_varint(buf, sub_1.size())
			buf.append_array(sub_1)

	static func decode_from(b: PackedByteArray, pos: Array) -> NpcPrices:
		var m := NpcPrices.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.prices.append(MaterialPrice.decode_struct(Wire.read_slice(b, pos)))
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 160)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> NpcPrices:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 160, "msg_id inesperado")
		return decode_from(b, pos)

class StationRange:
	const MSG_ID := 161
	var in_range: bool = false
	var station_id: int = 0

	func validate() -> void:
		pass

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, 1 if in_range else 0)
		Wire.write_tag(buf, 2, 0)
		Wire.write_varint(buf, station_id)

	static func decode_from(b: PackedByteArray, pos: Array) -> StationRange:
		var m := StationRange.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.in_range = Wire.read_varint(b, pos) != 0
				2: m.station_id = Wire.read_varint(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 161)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> StationRange:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 161, "msg_id inesperado")
		return decode_from(b, pos)

class ChatSend:
	const MSG_ID := 200
	var request_id: int = 0
	var channel: int = 0
	var text: String = ""

	func validate() -> void:
		assert(text.length() <= 256, "ChatSend.text demasiado largo")

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, request_id)
		Wire.write_tag(buf, 2, 0)
		Wire.write_varint(buf, channel)
		Wire.write_tag(buf, 3, 2)
		Wire.write_string(buf, text)

	static func decode_from(b: PackedByteArray, pos: Array) -> ChatSend:
		var m := ChatSend.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.request_id = Wire.read_varint(b, pos)
				2: m.channel = Wire.read_varint(b, pos)
				3: m.text = Wire.read_string(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 200)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> ChatSend:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 200, "msg_id inesperado")
		return decode_from(b, pos)

class ChatMessage:
	const MSG_ID := 201
	var channel: int = 0
	var from_name: String = ""
	var from_clan: String = ""
	var text: String = ""
	var server_time_ms: int = 0

	func validate() -> void:
		assert(from_name.length() <= 64, "ChatMessage.from_name demasiado largo")
		assert(from_clan.length() <= 16, "ChatMessage.from_clan demasiado largo")
		assert(text.length() <= 256, "ChatMessage.text demasiado largo")

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 0)
		Wire.write_varint(buf, channel)
		Wire.write_tag(buf, 2, 2)
		Wire.write_string(buf, from_name)
		Wire.write_tag(buf, 3, 2)
		Wire.write_string(buf, from_clan)
		Wire.write_tag(buf, 4, 2)
		Wire.write_string(buf, text)
		Wire.write_tag(buf, 5, 0)
		Wire.write_varint(buf, server_time_ms)

	static func decode_from(b: PackedByteArray, pos: Array) -> ChatMessage:
		var m := ChatMessage.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.channel = Wire.read_varint(b, pos)
				2: m.from_name = Wire.read_string(b, pos)
				3: m.from_clan = Wire.read_string(b, pos)
				4: m.text = Wire.read_string(b, pos)
				5: m.server_time_ms = Wire.read_varint(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 201)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> ChatMessage:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 201, "msg_id inesperado")
		return decode_from(b, pos)

class ChatSystem:
	const MSG_ID := 202
	var text_key: String = ""
	var params: Array = []

	func validate() -> void:
		assert(text_key.length() <= 64, "ChatSystem.text_key demasiado largo")
		for v in params:
			assert(v.length() <= 128, "ChatSystem.params demasiado largo")

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 2)
		Wire.write_string(buf, text_key)
		for v in params:
			Wire.write_tag(buf, 2, 2)
			Wire.write_string(buf, v)

	static func decode_from(b: PackedByteArray, pos: Array) -> ChatSystem:
		var m := ChatSystem.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.text_key = Wire.read_string(b, pos)
				2: m.params.append(Wire.read_string(b, pos))
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 202)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> ChatSystem:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 202, "msg_id inesperado")
		return decode_from(b, pos)

class ChatWhisper:
	const MSG_ID := 203
	var peer_name: String = ""
	var text: String = ""

	func validate() -> void:
		assert(peer_name.length() <= 64, "ChatWhisper.peer_name demasiado largo")
		assert(text.length() <= 256, "ChatWhisper.text demasiado largo")

	func encode_fields(buf: PackedByteArray) -> void:
		Wire.write_tag(buf, 1, 2)
		Wire.write_string(buf, peer_name)
		Wire.write_tag(buf, 2, 2)
		Wire.write_string(buf, text)

	static func decode_from(b: PackedByteArray, pos: Array) -> ChatWhisper:
		var m := ChatWhisper.new()
		while pos[0] < b.size():
			var key := Wire.read_varint(b, pos)
			var tag := key >> 3
			var wt := key & 7
			match tag:
				1: m.peer_name = Wire.read_string(b, pos)
				2: m.text = Wire.read_string(b, pos)
				_: Wire.skip(b, pos, wt)
		m.validate()
		return m

	func encode() -> PackedByteArray:
		validate()
		var buf := PackedByteArray()
		Wire.write_varint(buf, 203)
		encode_fields(buf)
		return buf

	static func decode(b: PackedByteArray) -> ChatWhisper:
		var pos := [0]
		var id := Wire.read_varint(b, pos)
		assert(id == 203, "msg_id inesperado")
		return decode_from(b, pos)
