# TALLER DE ASSETS — solo en builds de desarrollo (OS.is_debug_build()).
#
# Una ventana N mas: elige un asset (NPC, nave o prop), carga su JSON de data/,
# enseña cada dial como control editable y aplica los cambios EN VIVO: el JSON
# editado pisa al del disco (AssetDefs.set_override) y el mundo reconstruye las
# entidades de esa especie. "Guardar" lo escribe al archivo; "Descartar" vuelve
# al disco. Y para NPC y naves, un dummy local que simula reposo, patrulla,
# ataque, bajo ataque y huida, para calibrar giro, alabeo, llamas, pulso e
# impactos sin depender del server ni de que aparezca un bicho a mano.
#
# Cerrada por defecto; se abre con F8 o desde la sysbar. Los diales de la
# ventana (anchos, tiempos de la simulacion) viven en ui.json -> asset_lab.
class_name AssetLabWindow
extends NWindow

static var CFG: Dictionary = AssetDefs.config("ui").get("asset_lab", {})
static var ICON: String = str(CFG.get("icon", "res://assets/ui/icons/lab.svg"))
static var WIDTH: int = int(AssetDefs.num(CFG, "width", 440))
static var ROWS_HEIGHT: int = int(AssetDefs.num(CFG, "rows_height", 320))
static var CATEGORIES: Dictionary = CFG.get("categories", {"npcs": "NPC", "ships": "Naves", "props": "Props"})
static var SKIP_KEYS: Array = CFG.get("skip_keys", ["code", "model"])
static var APPLY_DELAY_SEC: float = AssetDefs.num(CFG, "apply_delay_sec", 0.15)
static var LABEL_WIDTH: int = int(AssetDefs.num(CFG, "label_width", 150))
static var INDENT_PX: int = int(AssetDefs.num(CFG, "indent_px", 14))
static var _SIM: Dictionary = CFG.get("sim", {})
static var SIM_SPEED: float = AssetDefs.num(_SIM, "speed", 250.0)
static var SIM_SPAWN_OFFSET: Vector2 = AssetDefs.vec2(_SIM.get("spawn_offset"), Vector2(420, 0))
static var SIM_PATROL_RADIUS: float = AssetDefs.num(_SIM, "patrol_radius", 900.0)
static var SIM_PATROL_INTERVAL: float = AssetDefs.num(_SIM, "patrol_interval_sec", 3.0)
static var SIM_ATTACK_INTERVAL: float = AssetDefs.num(_SIM, "attack_interval_sec", 0.8)
static var SIM_HIT_PCT: float = AssetDefs.num(_SIM, "hit_pct", 0.06)
static var SIM_DAMAGE_NUMBER: int = int(AssetDefs.num(_SIM, "damage_number", 120))
static var SIM_FLEE_DIST: float = AssetDefs.num(_SIM, "flee_dist", 1500.0)
static var SIM_AMMO: String = str(_SIM.get("ammo", "ammo_cel_1"))

## Los modos de simulacion, en el orden de los segmentos.
const SIM_MODES := ["reposo", "patrulla", "ataca", "bajo_ataque", "huye"]
const SIM_LABELS := {"reposo": "REPOSO", "patrulla": "PATRULLA", "ataca": "ATACA",
	"bajo_ataque": "BAJO ATAQUE", "huye": "HUYE"}

var _world                        # World: quien reconstruye y presta el heroe
var _category := "npcs"
var _code := ""
var _path := ""
var _working := {}                # el JSON en edicion (copia profunda)
var _dirty := false               # hay cambios sin aplicar al mundo
var _apply_timer := 0.0
var _saved := true                # el archivo en disco coincide con _working
var _cat_segments := {}
var _codes: OptionButton
var _rows: VBoxContainer
var _status: Label
var _save_button: Button
var _sim_segments := {}
var _sim_mode := ""
var _sim_timer := 0.0
var _sim_anchor := Vector2.ZERO
var _sim_hp := 1.0
var _dummy: EntityNode


static func create(world) -> AssetLabWindow:
	var v := AssetLabWindow.new()
	v._world = world
	v.key = "taller"
	v._build("Taller de assets", ICON)
	v._body()
	return v


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	visible = false
	# la primera vez: arriba a la derecha, bajo la sysbar (no encima de la taskbar
	# ni de la ventana Nave); despues, donde el desarrollador la dejo
	if not load_position():
		_place.call_deferred()


func _place() -> void:
	var vp := get_viewport_rect().size
	position = _inside(Vector2(vp.x - size.x - NTheme.SCREEN_MARGIN,
		NTheme.BAR_MARGIN + SysBar.SIDE + NTheme.STACK_GAP))


func _body() -> void:
	# fila 1: categoria (segmentos) + asset (desplegable)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", NTheme.SEGMENT_GAP)
	for cat in CATEGORIES:
		var b := NTheme.segment(str(CATEGORIES[cat]))
		b.pressed.connect(func(): _pick_category(cat))
		_cat_segments[cat] = b
		top.add_child(b)
	_codes = OptionButton.new()
	_codes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_codes.add_theme_font_override("font", NTheme.mono())
	_codes.add_theme_font_size_override("font_size", NTheme.BODY_FONT_SIZE)
	_codes.add_theme_color_override("font_color", NTheme.WARN)
	_codes.focus_mode = Control.FOCUS_NONE
	_codes.item_selected.connect(func(i: int): _pick_code(_codes.get_item_text(i)))
	top.add_child(_codes)
	content.add_child(top)

	# fila 2: los diales del JSON, con scroll
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDTH - NTheme.PANEL_PAD_LEFT - NTheme.PANEL_PAD_RIGHT, ROWS_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", NTheme.STACK_GAP)
	scroll.add_child(_rows)
	content.add_child(scroll)

	# fila 3: guardar / descartar + estado
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", NTheme.SEGMENT_GAP)
	_save_button = NTheme.segment("GUARDAR JSON")
	_save_button.pressed.connect(_save)
	actions.add_child(_save_button)
	var discard := NTheme.segment("DESCARTAR")
	NTheme.mark_segment(discard, false)
	discard.pressed.connect(_discard)
	actions.add_child(discard)
	_status = NTheme.label("", NTheme.exo2(), NTheme.ROW_LABEL_FONT_SIZE, NTheme.FAINT)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	actions.add_child(_status)
	content.add_child(actions)

	# fila 4: la simulacion (solo NPC y naves)
	var sim := HBoxContainer.new()
	sim.add_theme_constant_override("separation", NTheme.SEGMENT_GAP)
	for mode in SIM_MODES:
		var b := NTheme.segment(SIM_LABELS[mode])
		NTheme.mark_segment(b, false)
		b.pressed.connect(func(): _set_sim(mode))
		_sim_segments[mode] = b
		sim.add_child(b)
	var off := NTheme.segment("QUITAR")
	NTheme.mark_segment(off, false)
	off.pressed.connect(func(): _set_sim(""))
	sim.add_child(off)
	content.add_child(sim)

	_pick_category("npcs")


# ---------------------------------------------------------------- seleccion

func _pick_category(cat: String) -> void:
	_category = cat
	for c in _cat_segments:
		NTheme.mark_segment(_cat_segments[c], c == cat)
	_codes.clear()
	var codes := AssetDefs.codes_of(cat)
	for c in codes:
		_codes.add_item(c)
	if codes.is_empty():
		_code = ""
		_clear_rows()
		return
	_codes.select(0)
	_pick_code(codes[0])


func _pick_code(code: String) -> void:
	_set_sim("")
	_code = code
	_path = AssetDefs.path_for(_category, code)
	_working = AssetDefs.reread(_path).duplicate(true)
	_saved = true
	_dirty = false
	_rebuild_rows()
	_status.text = "%s/%s" % [_category, code]
	_update_save_button()


# ------------------------------------------------------------------- filas

func _clear_rows() -> void:
	for c in _rows.get_children():
		c.queue_free()


func _rebuild_rows() -> void:
	_clear_rows()
	_add_rows(_working, [], 0)


## Una fila por clave, recursivo en los sub-objetos. Las claves `_x` no se
## editan: son el comentario de `x` y salen como tooltip de su fila.
func _add_rows(d: Dictionary, path: Array, depth: int) -> void:
	for k in d.keys():
		var key := str(k)
		if key.begins_with("_") or SKIP_KEYS.has(key):
			continue
		var v = d[k]
		var hint := str(d.get("_" + key, ""))
		if v is Dictionary:
			var head := NTheme.label(key, NTheme.michroma_track(NWindow.TITLE_TRACKING) if depth == 0 else NTheme.exo2(),
				NTheme.ROW_LABEL_FONT_SIZE, NTheme.CYAN if depth == 0 else NTheme.MUTED)
			head.tooltip_text = hint
			head.mouse_filter = Control.MOUSE_FILTER_STOP
			var hrow := HBoxContainer.new()
			hrow.add_child(head)
			_indent(hrow, depth)
			_rows.add_child(hrow)
			_add_rows(v, path + [key], depth + 1)
		elif v is Array:
			if v.is_empty() or not (v[0] is float or v[0] is int):
				continue     # listas de texto u objetos: no son diales
			var row := _row(key, hint, depth)
			for i in v.size():
				row.add_child(_spin(float(v[i]), func(nv: float): _set_at(path + [key, i], nv)))
		elif v is bool:
			var row := _row(key, hint, depth)
			var cb := CheckBox.new()
			cb.button_pressed = v
			cb.focus_mode = Control.FOCUS_NONE
			cb.toggled.connect(func(on: bool): _set_at(path + [key], on))
			row.add_child(cb)
		elif v is float or v is int:
			var row := _row(key, hint, depth)
			row.add_child(_spin(float(v), func(nv: float): _set_at(path + [key], nv)))
		elif v is String:
			var row := _row(key, hint, depth)
			var le := LineEdit.new()
			le.text = v
			le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			le.add_theme_font_override("font", NTheme.mono())
			le.add_theme_font_size_override("font_size", NTheme.ROW_VALUE_FONT_SIZE)
			le.add_theme_color_override("font_color", NTheme.WARN)
			le.text_submitted.connect(func(t: String): _set_at(path + [key], t))
			row.add_child(le)


func _row(key: String, hint: String, depth: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", NTheme.ROW_GAP)
	var k := NTheme.label(key, NTheme.exo2(), NTheme.ROW_LABEL_FONT_SIZE, NTheme.MUTED)
	k.custom_minimum_size = Vector2(LABEL_WIDTH - depth * INDENT_PX, 0)
	k.tooltip_text = hint
	k.mouse_filter = Control.MOUSE_FILTER_STOP     # sin esto no hay tooltip
	row.add_child(k)
	_indent(row, depth)
	_rows.add_child(row)
	return row


func _indent(c: Control, depth: int) -> void:
	# un espaciador delante: las cabeceras de sub-objeto van solas en su fila
	if depth > 0 and c is HBoxContainer:
		var sp := Control.new()
		sp.custom_minimum_size = Vector2(depth * INDENT_PX, 0)
		c.add_child(sp)
		c.move_child(sp, 0)


## El numero ambar en mono del sistema, editable. El paso sale de la magnitud
## del valor: 0,01 por debajo de 1, 0,1 por debajo de 10, 1 por encima.
func _spin(v: float, on_change: Callable) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = -1e9
	sb.max_value = 1e9
	sb.allow_greater = true
	sb.allow_lesser = true
	sb.step = 0.01 if absf(v) < 1.0 else (0.1 if absf(v) < 10.0 else 1.0)
	sb.value = v
	sb.custom_minimum_size = Vector2(0, 0)
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.focus_mode = Control.FOCUS_CLICK
	var le := sb.get_line_edit()
	le.add_theme_font_override("font", NTheme.mono())
	le.add_theme_font_size_override("font_size", NTheme.ROW_VALUE_FONT_SIZE)
	le.add_theme_color_override("font_color", NTheme.WARN)
	sb.value_changed.connect(on_change)
	return sb


# ----------------------------------------------------------- aplicar/guardar

func _set_at(path: Array, value) -> void:
	var d = _working
	for i in path.size() - 1:
		d = d[path[i]]
	d[path[path.size() - 1]] = value
	_dirty = true
	_saved = false
	_apply_timer = APPLY_DELAY_SEC
	_update_save_button()


func _apply() -> void:
	_dirty = false
	AssetDefs.set_override(_path, _working)
	if _world != null:
		_world.lab_rebuild(_category, _code)
	_status.text = "%s/%s · en vivo" % [_category, _code]


func _save() -> void:
	if _path == "":
		return
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		_status.text = "no se pudo escribir %s" % _path
		return
	f.store_string(JSON.stringify(_tidy(_working), "  ") + "\n")
	f.close()
	AssetDefs.set_override(_path, {})
	AssetDefs.reread(_path)
	_saved = true
	_status.text = "guardado %s" % _path
	_update_save_button()


func _discard() -> void:
	AssetDefs.set_override(_path, {})
	_pick_code(_code)
	if _world != null:
		_world.lab_rebuild(_category, _code)
	_status.text = "%s/%s · como en disco" % [_category, _code]


## Los floats enteros vuelven a int al escribir (JSON.parse los convierte todos
## en float, y un `90.0` donde habia `90` ensucia el diff).
func _tidy(v):
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _tidy(v[k])
		return out
	if v is Array:
		var arr := []
		for x in v:
			arr.append(_tidy(x))
		return arr
	if v is float and v == floorf(v) and absf(v) < 1e9:
		return int(v)
	return v


func _update_save_button() -> void:
	NTheme.mark_segment(_save_button, not _saved)


# -------------------------------------------------------------- simulacion

func _set_sim(mode: String) -> void:
	_sim_mode = mode
	for m in _sim_segments:
		NTheme.mark_segment(_sim_segments[m], m == mode)
	if mode == "" or _world == null or _category == "props":
		if _dummy != null:
			_world.lab_despawn()
			_dummy = null
		return
	if _dummy == null or not is_instance_valid(_dummy) or _dummy.type_id != _code:
		if _dummy != null:
			_world.lab_despawn()
		_dummy = _world.lab_spawn(_code, SIM_SPAWN_OFFSET, SIM_SPEED)
		_sim_anchor = _dummy.position
		_sim_hp = 1.0
	_sim_timer = 0.0
	match mode:
		"reposo":
			_dummy.set_attack_target(null)
			_dummy.set_goal(_dummy.position)
		"ataca":
			_dummy.set_goal(_dummy.position)
			_dummy.set_attack_target(_world.lab_hero(), 1e9)
		"bajo_ataque":
			_dummy.set_goal(_dummy.position)
			_dummy.set_attack_target(_world.lab_hero(), 1e9)
		_:
			_dummy.set_attack_target(null)


func _process(delta: float) -> void:
	if _dirty:
		_apply_timer -= delta
		if _apply_timer <= 0.0:
			_apply()
	if _sim_mode == "" or _dummy == null or not is_instance_valid(_dummy):
		return
	var hero: EntityNode = _world.lab_hero()
	_sim_timer -= delta
	match _sim_mode:
		"patrulla":
			if _sim_timer <= 0.0:
				_sim_timer = SIM_PATROL_INTERVAL
				_dummy.set_goal(_world.lab_clamp(_sim_anchor + Vector2.from_angle(randf() * TAU) * randf() * SIM_PATROL_RADIUS))
		"huye":
			if _sim_timer <= 0.0 and hero != null:
				_sim_timer = SIM_PATROL_INTERVAL
				var away := (_dummy.position - hero.position).normalized()
				_dummy.set_goal(_world.lab_clamp(_dummy.position + away * SIM_FLEE_DIST))
		"ataca":
			if _sim_timer <= 0.0 and hero != null:
				_sim_timer = SIM_ATTACK_INTERVAL
				Beam3D.fire(_dummy, hero, SIM_AMMO, false)
				hero.shield_impact(_dummy.position)
				_world.lab_hit_number(hero, "-%d" % SIM_DAMAGE_NUMBER, true)
		"bajo_ataque":
			if _sim_timer <= 0.0 and hero != null:
				_sim_timer = SIM_ATTACK_INTERVAL
				Beam3D.fire(hero, _dummy, SIM_AMMO, false)
				_sim_hp -= SIM_HIT_PCT
				if _sim_hp <= 0.0:
					_sim_hp = 1.0
				_dummy.set_hp_pct(_sim_hp)
				if _sim_hp > 0.5:
					_dummy.shield_impact(hero.position)
				else:
					_dummy.hull_impact()
				_world.lab_hit_number(_dummy, "-%d" % SIM_DAMAGE_NUMBER, false)


## Al cerrar la ventana, la simulacion se va con ella.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible and _sim_mode != "":
		_set_sim("")
