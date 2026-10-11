class_name GameInput
extends Node
## Unified input provider (port of input.lua + the key handling of main.lua): keyboard + mouse,
## gamepad, Android touch (virtual sticks + on-screen buttons).
##
## Public API read by every other system:
##   move: Vector2 (-1..1), aim_world: Vector2 (world px), fire: bool, alt_fire: bool, sprint: bool
##   just(action) -> bool: true for one frame after an edge press of a named action.
##   Action names: use_water, use_bandage, use_food, bomb, weapon_next, weapon_prev, headlamp,
##   battery, pause, interact, ui_left, ui_right, ui_up, ui_down, ui_accept, ui_back, status_hud
##   Extra: options (F10), run_stats, controls (edge presses of the held overlays)
## Held overlays: show_status / show_run_stats / show_controls (bool), alt_fire doubles as "tactical map".
## Other: aim_active, mode ("keyboard"|"gamepad"|"touch"), active_mode(), text_entry (set true by the UI
##   while a name box is open so letter keys do not produce menu pulses), press(action) to inject.
##
## Keyboard (as main.lua): WASD/arrows move (aim-relative like the Lua, see AIM_RELATIVE_KEYS), mouse aim,
## LMB/Space fire, RMB tactical map, Shift sprint, H headlamp, X battery, Q bomb, E/Tab/wheel cycle weapon,
## 1 water, 2 bandage, 3 food, Esc pause, F1 (hold) controls, F2 (hold) run stats, C (hold) status, F10 options.

const AIM_RELATIVE_KEYS := true     # Lua: keyboard W = towards the cursor, A/D strafe
const DEADZONE := 0.2               # input.lua deadzone
const UI_DEADZONE := 0.35
const UI_FIRST_DELAY := 0.22
const UI_REPEAT := 0.10
const STICK_MAX_R := 50.0           # input.lua virtual stick radius
const DOUBLE_TAP_TIME := 0.4

const SCHEMES := {
	"keyboard": {"name": "Keyboard + Mouse", "controls": [
		["W/A/S/D", "Move (aim-relative)"], ["Mouse", "Aim direction"], ["Left Click / Space", "Fire weapon"],
		["Right Click (Hold)", "Tactical Map"], ["Shift", "Sprint"], ["H", "Toggle Headlamp"], ["X", "Use Battery"],
		["Q", "Use bomb"], ["E / Tab / Scroll", "Cycle weapons"], ["1", "Almond Water"], ["2", "Bandage"], ["3", "Food"],
		["C (Hold)", "Status HUD"], ["ESC", "Pause / Menu"], ["F1 (Hold)", "Show Controls"], ["F2 (Hold)", "Run Stats"]]},
	"gamepad": {"name": "Xbox Controller", "controls": [
		["Left Stick", "Move"], ["Right Stick", "Aim"], ["Right Trigger", "Fire weapon"],
		["Left Trigger (Hold)", "Tactical Map"], ["A Button (Hold)", "Sprint"], ["Left Bumper", "Toggle Headlamp"],
		["Left Stick Click", "Use Battery"], ["Right Bumper", "Use Bomb"], ["B Button", "Cycle weapons"],
		["Y Button", "Almond Water"], ["X Button", "Bandage"], ["D-Pad Left", "Food"], ["D-Pad Up (Hold)", "Status HUD"],
		["D-Pad Down (Hold)", "Run Stats"], ["Right Stick Click (Hold)", "Show Controls"], ["Back/View", "Pause / Menu"]]},
	"touch": {"name": "Touchscreen", "controls": [
		["Left Side Drag", "Move (virtual stick)"], ["Right Side Drag", "Aim (virtual stick)"],
		["Right Stick Hold", "Auto-fire"], ["BOMB Button", "Use bomb"], ["WPN Button", "Cycle weapon"],
		["H2O / MED / EAT", "Use items"], ["LAMP / BAT", "Headlamp / battery"], ["Pause Button", "Pause / Menu"],
		["Double-Tap Center", "Pause / Menu"]]},
}

var game
var move := Vector2.ZERO
var aim_world := Vector2.ZERO
var fire := false
var alt_fire := false
var sprint := false
var aim_active := true
var show_status := false
var show_run_stats := false
var show_controls := false
var text_entry := false
var mode := "keyboard"                 # detected mode when options say "auto"
var aim_angle := 0.0                   # radians, last known aim direction

var _just := {}
var _gp := -1                          # joypad device id
var _prev_btn := {}
var _ui_hold := Vector2i.ZERO
var _ui_repeat := 0.0
var _touch_seen := false
var _sticks := {"left": {"id": -1, "o": Vector2.ZERO, "p": Vector2.ZERO},
	"right": {"id": -1, "o": Vector2.ZERO, "p": Vector2.ZERO}}
var _btn_touch := {}                   # touch index -> action (held buttons)
var _btn_flash := {}                   # action -> seconds of pressed feedback
var _tap_timer := 0.0
var _tap_count := 0
var _layer: CanvasLayer
var _touch_ui: Control
var _touch_aim_dir := Vector2.RIGHT
var _gp_aim_dir := Vector2.RIGHT


func setup(g) -> void:
	game = g
	if OS.has_feature("mobile"):
		mode = "touch"
	_layer = CanvasLayer.new()
	_layer.layer = 60
	_touch_ui = Control.new()
	_touch_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_touch_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch_ui.draw.connect(_draw_touch)
	_layer.add_child(_touch_ui)
	add_child(_layer)


# ---- public ----------------------------------------------------------------------------

func just(action: String) -> bool:
	return _just.has(action)


func press(action: String) -> void:
	_just[action] = true


## "keyboard" | "gamepad" | "touch" (resolves the options "Controller" setting).
func active_mode() -> String:
	var forced := _forced_mode()
	if forced != "auto":
		return forced
	return mode


func _forced_mode() -> String:
	if game and game.ui and game.ui.get("options") != null:
		return game.ui.options.get_control_mode()
	return "auto"


func has_gamepad() -> bool:
	return _gp >= 0


func scheme() -> Dictionary:
	return SCHEMES[active_mode() if SCHEMES.has(active_mode()) else "keyboard"]


# ---- per-frame ----------------------------------------------------------------------------

func tick(dt: float) -> void:
	_poll_gamepad_device()
	for k in _btn_flash.keys():
		_btn_flash[k] -= dt
		if _btn_flash[k] <= 0.0:
			_btn_flash.erase(k)
	if _tap_timer > 0.0:
		_tap_timer -= dt
		if _tap_timer <= 0.0:
			_tap_count = 0

	var playing: bool = game.state == "playing"
	move = Vector2.ZERO
	sprint = false
	fire = false
	alt_fire = false
	show_status = false
	show_run_stats = false
	show_controls = false

	var m := active_mode()
	if m == "gamepad" and _gp >= 0:
		_update_gamepad(dt)
	elif m == "touch":
		_update_touch(playing)
	else:
		_update_keyboard()

	if not playing:
		for s in _sticks.values():
			s.id = -1
		_btn_touch.clear()
		move = Vector2.ZERO
		fire = false
	_touch_ui.visible = (m == "touch" and playing)
	if _touch_ui.visible:
		_touch_ui.queue_redraw()


## Called by game.gd at the end of every frame.
func end_frame() -> void:
	_just.clear()


func _player_px() -> Vector2:
	return game.player.position if game and game.player else Vector2.ZERO


func _update_keyboard() -> void:
	var raw := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
		- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
		- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	aim_world = game.get_global_mouse_position()
	var to := aim_world - _player_px()
	if to != Vector2.ZERO:
		aim_angle = to.angle()
	aim_active = true
	if AIM_RELATIVE_KEYS and raw != Vector2.ZERO:
		var fwd := Vector2.from_angle(aim_angle)
		var side := Vector2(-fwd.y, fwd.x)
		move = (fwd * -raw.y + side * raw.x)
		if move.length() > 1.0:
			move = move.normalized()
	else:
		move = raw.normalized() if raw.length() > 1.0 else raw
	sprint = Input.is_physical_key_pressed(KEY_SHIFT)
	fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_physical_key_pressed(KEY_SPACE)
	alt_fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	show_controls = Input.is_physical_key_pressed(KEY_F1)
	show_run_stats = Input.is_physical_key_pressed(KEY_F2)
	show_status = Input.is_physical_key_pressed(KEY_C) and not text_entry


func _poll_gamepad_device() -> void:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		_gp = -1
		if mode == "gamepad":
			mode = "keyboard"
	elif _gp not in pads:
		_gp = pads[0]


func _axis(a: JoyAxis) -> float:
	return Input.get_joy_axis(_gp, a) if _gp >= 0 else 0.0


func _btn(b: JoyButton) -> bool:
	return _gp >= 0 and Input.is_joy_button_pressed(_gp, b)


func _dz(v: float) -> float:
	return 0.0 if absf(v) < DEADZONE else v


func _update_gamepad(dt: float) -> void:
	var lx := _dz(_axis(JOY_AXIS_LEFT_X))
	var ly := _dz(_axis(JOY_AXIS_LEFT_Y))
	move = Vector2(lx, ly)
	if move.length() > 1.0:
		move = move.normalized()
	var rx := _dz(_axis(JOY_AXIS_RIGHT_X))
	var ry := _dz(_axis(JOY_AXIS_RIGHT_Y))
	aim_active = absf(rx) > DEADZONE or absf(ry) > DEADZONE
	if aim_active:
		_gp_aim_dir = Vector2(rx, ry).normalized()
		aim_angle = _gp_aim_dir.angle()
		aim_world = _player_px() + _gp_aim_dir * 5.0 * game.TILE
	else:
		aim_world = _player_px() + _gp_aim_dir * 5.0 * game.TILE
		_try_aim_assist()
	fire = _axis(JOY_AXIS_TRIGGER_RIGHT) > 0.2
	alt_fire = _axis(JOY_AXIS_TRIGGER_LEFT) > 0.15
	sprint = _btn(JOY_BUTTON_A)
	show_status = _btn(JOY_BUTTON_DPAD_UP)
	show_run_stats = _btn(JOY_BUTTON_DPAD_DOWN)
	show_controls = _btn(JOY_BUTTON_RIGHT_STICK)

	# edge-triggered buttons
	_edge(JOY_BUTTON_A, "ui_accept")
	_edge(JOY_BUTTON_START, "ui_accept")
	_edge(JOY_BUTTON_B, "ui_back")
	_edge(JOY_BUTTON_B, "pad_b")
	_edge(JOY_BUTTON_START, "pad_start")
	_edge(JOY_BUTTON_B, "weapon_next")
	_edge(JOY_BUTTON_BACK, "ui_back")
	_edge(JOY_BUTTON_BACK, "pause")
	_edge(JOY_BUTTON_Y, "use_water")
	_edge(JOY_BUTTON_X, "use_bandage")
	_edge(JOY_BUTTON_DPAD_LEFT, "use_food")
	_edge(JOY_BUTTON_LEFT_STICK, "battery")
	_edge(JOY_BUTTON_RIGHT_SHOULDER, "bomb")
	_edge(JOY_BUTTON_LEFT_SHOULDER, "headlamp")
	_edge(JOY_BUTTON_DPAD_UP, "status_hud")

	# UI navigation pulses (d-pad + both sticks), with hold-repeat
	var sx := lx if absf(lx) > absf(rx) else rx
	var sy := ly if absf(ly) > absf(ry) else ry
	var hx := 0
	var hy := 0
	if _btn(JOY_BUTTON_DPAD_LEFT) or sx < -UI_DEADZONE: hx = -1
	elif _btn(JOY_BUTTON_DPAD_RIGHT) or sx > UI_DEADZONE: hx = 1
	if _btn(JOY_BUTTON_DPAD_UP) or sy < -UI_DEADZONE: hy = -1
	elif _btn(JOY_BUTTON_DPAD_DOWN) or sy > UI_DEADZONE: hy = 1
	_ui_pulse(Vector2i(hx, hy), dt)


func _edge(b: JoyButton, action: String) -> void:
	var key := "%d_%s" % [b, action]
	var now := _btn(b)
	if now and not _prev_btn.get(key, false):
		press(action)
	_prev_btn[key] = now


func _ui_pulse(hold: Vector2i, dt: float) -> void:
	var emit := false
	if hold != _ui_hold:
		_ui_hold = hold
		_ui_repeat = 0.0
		emit = hold != Vector2i.ZERO
	elif hold != Vector2i.ZERO:
		_ui_repeat += dt
		if _ui_repeat >= UI_FIRST_DELAY:
			_ui_repeat = UI_FIRST_DELAY - UI_REPEAT
			emit = true
	if emit:
		if hold.x < 0:
			press("ui_left")
		elif hold.x > 0:
			press("ui_right")
		if hold.y < 0:
			press("ui_up")
		elif hold.y > 0:
			press("ui_down")


## Gamepad auto-aim (main.lua aimAssist): lock the nearest visible enemy while the aim stick is idle.
func _try_aim_assist() -> void:
	if game.state != "playing" or game.enemies == null or not game.enemies.has_method("get_enemies"):
		return
	var ui = game.ui
	if ui == null or not ui.get("aim_assist_enabled"):
		return
	var best := 15.0
	var target = null
	var ppos: Vector2 = game.player.tile_pos
	for e in game.enemies.get_enemies():
		var d: float = e.tile_pos.distance_to(ppos)
		if d < best and _has_los(ppos, e.tile_pos):
			best = d
			target = e
	if target != null:
		aim_world = target.tile_pos * game.TILE
		aim_active = true
		var to: Vector2 = aim_world - _player_px()
		if to != Vector2.ZERO:
			aim_angle = to.angle()


func _has_los(a: Vector2, b: Vector2) -> bool:
	if game.map == null:
		return true
	var steps := int(a.distance_to(b) * 2.0)
	for i in range(1, steps):
		var p := a.lerp(b, float(i) / steps)
		if game.map.is_solid(p.x, p.y):
			return false
	return true


# ---- touch -----------------------------------------------------------------------------------

func _view_size() -> Vector2:
	return get_viewport().get_visible_rect().size


## Scale factor for touch UI (phones have small physical screens).
func touch_scale() -> float:
	var s := _view_size()
	return clampf(minf(s.x / 960.0, s.y / 720.0), 1.0, 2.0) * 1.35


## input.lua getTouchButtons: bomb, weapon, three item buttons (+ headlamp, battery, pause).
func touch_buttons() -> Array:
	var v := _view_size()
	var k := touch_scale()
	var w := v.x
	var h := v.y
	return [
		{"pos": Vector2(w - 62 * k, h - 62 * k), "r": 32.0 * k, "action": "bomb", "label": "BOMB", "color": Color(1, 0.5, 0.1)},
		{"pos": Vector2(w - 52 * k, 200 * k), "r": 26.0 * k, "action": "weapon_next", "label": "WPN", "color": Color(0.7, 0.7, 0.7)},
		{"pos": Vector2(44 * k, h - 150 * k), "r": 24.0 * k, "action": "use_water", "label": "H2O", "color": Color(0.3, 0.8, 1)},
		{"pos": Vector2(100 * k, h - 150 * k), "r": 24.0 * k, "action": "use_bandage", "label": "MED", "color": Color(0.3, 1, 0.3)},
		{"pos": Vector2(156 * k, h - 150 * k), "r": 24.0 * k, "action": "use_food", "label": "EAT", "color": Color(0.8, 0.6, 0.2)},
		{"pos": Vector2(w - 142 * k, h - 44 * k), "r": 24.0 * k, "action": "headlamp", "label": "LAMP", "color": Color(1, 0.95, 0.6)},
		{"pos": Vector2(w - 52 * k, h - 142 * k), "r": 24.0 * k, "action": "battery", "label": "BAT", "color": Color(0.2, 1, 0.6)},
		{"pos": Vector2(w * 0.5, 32 * k), "r": 20.0 * k, "action": "pause", "label": "||", "color": Color(0.9, 0.8, 0.2)},
	]


func _update_touch(playing: bool) -> void:
	var k := touch_scale()
	var maxr := STICK_MAX_R * k
	var l: Dictionary = _sticks.left
	var r: Dictionary = _sticks.right
	aim_world = _player_px() + _touch_aim_dir * 200.0
	aim_active = false
	if l.id >= 0:
		var d: Vector2 = l.p - l.o
		if d.length() > 5.0:
			move = (d / maxr).limit_length(1.0)
			sprint = d.length() > maxr * 0.8
	if r.id >= 0:
		var d2: Vector2 = r.p - r.o
		if d2.length() > 10.0 * k:
			_touch_aim_dir = d2.normalized()
			aim_angle = d2.angle()
			aim_world = _player_px() + _touch_aim_dir * 5.0 * game.TILE
			aim_active = true
			fire = true


func _handle_touch(event: InputEventScreenTouch) -> void:
	if not _touch_seen:
		_touch_seen = true
	if _forced_mode() == "auto":
		mode = "touch"
	if game.state != "playing":
		return
	if not event.pressed:
		for s in _sticks.values():
			if s.id == event.index:
				s.id = -1
		_btn_touch.erase(event.index)
		return
	var pos := event.position
	var v := _view_size()
	# double-tap the centre of the screen to pause
	if absf(pos.x - v.x * 0.5) < 100 and absf(pos.y - v.y * 0.5) < 100:
		if _tap_timer > 0.0:
			_tap_count += 1
			if _tap_count >= 2:
				press("pause")
				_tap_count = 0
				_tap_timer = 0.0
				return
		else:
			_tap_count = 1
		_tap_timer = DOUBLE_TAP_TIME
	for b in touch_buttons():
		if pos.distance_to(b.pos) <= b.r * 1.15:
			press(b.action)
			_btn_flash[b.action] = 0.18
			_btn_touch[event.index] = b.action
			return
	var s: Dictionary = _sticks.left if pos.x < v.x * 0.5 else _sticks.right
	if s.id < 0:
		s.id = event.index
		s.o = pos
		s.p = pos


func _handle_drag(event: InputEventScreenDrag) -> void:
	for s in _sticks.values():
		if s.id == event.index:
			s.p = event.position


func _draw_touch() -> void:
	var k := touch_scale()
	var maxr := STICK_MAX_R * k
	for key in ["left", "right"]:
		var s: Dictionary = _sticks[key]
		if s.id < 0:
			continue
		var col := Color(1, 1, 1) if key == "left" else Color(1, 0.3, 0.2)
		_touch_ui.draw_circle(s.o, maxr, Color(col, 0.15))
		_touch_ui.draw_arc(s.o, maxr, 0, TAU, 40, Color(col, 0.45), 2.0)
		var knob: Vector2 = s.o + (s.p - s.o).limit_length(maxr)
		_touch_ui.draw_circle(knob, 20.0 * k, Color(col, 0.35))
		_touch_ui.draw_arc(knob, 20.0 * k, 0, TAU, 24, Color(col, 0.7), 2.0)
	var p = game.player
	for b in touch_buttons():
		var pressed: bool = _btn_flash.has(b.action)
		var c: Color = b.color
		var r: float = b.r * (0.9 if pressed else 1.0)
		_touch_ui.draw_circle(b.pos, r, Color(c, 0.5 if pressed else 0.26))
		_touch_ui.draw_arc(b.pos, r, 0, TAU, 32, Color(c, 0.85), 2.5 if pressed else 1.8)
		var fs := int(maxf(11.0, b.r * 0.5))
		var font := UITheme.title_font()
		var tw := font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_touch_ui.draw_string(font, b.pos + Vector2(-tw * 0.5, fs * 0.33), b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9))
		# inventory badge
		var count := -1
		if p:
			match b.action:
				"use_water": count = p.almond_water
				"use_bandage": count = p.bandages
				"use_food": count = p.food
				"battery": count = p.batteries
		if count >= 0:
			var bp: Vector2 = b.pos + Vector2(b.r * 0.7, -b.r * 0.7)
			_touch_ui.draw_circle(bp, 10.0 * k * 0.8, Color(0, 0, 0, 0.75))
			var cs := str(count)
			var cw := ThemeDB.fallback_font.get_string_size(cs, HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * k)).x
			_touch_ui.draw_string(ThemeDB.fallback_font, bp + Vector2(-cw * 0.5, 4.0 * k), cs, HORIZONTAL_ALIGNMENT_LEFT, -1,
				int(12 * k), Color(1, 1, 1) if count > 0 else Color(1, 0.4, 0.4))


# ---- events ----------------------------------------------------------------------------------

func _set_detected(m: String) -> void:
	if _forced_mode() == "auto":
		mode = m


func _input(event: InputEvent) -> void:
	if game == null:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)
	elif event is InputEventKey and event.pressed:
		if not event.echo or _is_nav_key(event.physical_keycode):
			_set_detected("keyboard")
			_key_pressed(event)
	elif event is InputEventMouseButton and event.pressed:
		if event.device != InputEvent.DEVICE_ID_EMULATION and not _touch_recent():
			_set_detected("keyboard")
		if game.state == "playing":
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				press("weapon_next")
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				press("weapon_prev")
	elif event is InputEventMouseMotion:
		if event.device != InputEvent.DEVICE_ID_EMULATION and not _touch_recent():
			if event.relative.length() > 1.5:
				_set_detected("keyboard")
	elif event is InputEventJoypadButton and event.pressed:
		_set_detected("gamepad")
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) > 0.5:
			_set_detected("gamepad")


func _touch_recent() -> bool:
	return _touch_seen and mode == "touch"


func _is_nav_key(k: int) -> bool:
	return k in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_BACKSPACE]


func _key_pressed(event: InputEventKey) -> void:
	var k := event.physical_keycode
	var nav_ok := not text_entry
	var echo := event.echo
	match k:
		KEY_UP:
			press("ui_up")
		KEY_DOWN:
			press("ui_down")
		KEY_LEFT:
			press("ui_left")
		KEY_RIGHT:
			press("ui_right")
		KEY_ENTER, KEY_KP_ENTER:
			press("ui_accept")
			press("interact")
		KEY_BACKSPACE:
			if not text_entry:
				press("ui_back")
		KEY_ESCAPE:
			press("pause")
			press("ui_back")
		KEY_F10:
			press("options")
		KEY_F1:
			press("controls")
		KEY_F2:
			press("run_stats")
		KEY_1:
			press("use_water")
		KEY_2:
			press("use_bandage")
		KEY_3:
			press("use_food")
		_:
			if not nav_ok or echo:
				return
			match k:
				KEY_W:
					press("ui_up")
				KEY_S:
					press("ui_down")
				KEY_A:
					press("ui_left")
				KEY_D:
					press("ui_right")
				KEY_SPACE:
					press("ui_accept")
				KEY_H:
					press("headlamp")
				KEY_X:
					press("battery")
				KEY_Q:
					press("bomb")
				KEY_E, KEY_TAB:
					press("weapon_next")
				KEY_C:
					press("status_hud")
