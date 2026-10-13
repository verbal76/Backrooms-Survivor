class_name GameInput
extends Node

const Platform = preload("res://scripts/platform/platform.gd")
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
const DEADZONE := 0.2               # default stick dead zone (Options > Stick Dead Zone changes it)
const TRIGGER_THRESH := 0.30        # LT / RT count as pressed above this (fire, tactical map)
const TRIGGER_EDGE := 0.50          # trigger-bound one-shot actions
const UI_DEADZONE := 0.35
const UI_FIRST_DELAY := 0.22
const UI_REPEAT := 0.10
const STICK_MAX_R := 50.0           # input.lua virtual stick radius
const DOUBLE_TAP_TIME := 0.4

## Rebindable actions. "key" = default physical keycode (0 = none), "pad" = default joypad code
## (JoyButton, 100 = left trigger, 101 = right trigger, -1 = unbound, -2 = fixed on the gamepad sticks).
const ACTIONS := [
	{"id": "move_up", "label": "Move Up", "key": KEY_W, "pad": -2},
	{"id": "move_down", "label": "Move Down", "key": KEY_S, "pad": -2},
	{"id": "move_left", "label": "Move Left", "key": KEY_A, "pad": -2},
	{"id": "move_right", "label": "Move Right", "key": KEY_D, "pad": -2},
	{"id": "sprint", "label": "Sprint", "key": KEY_SHIFT, "pad": JOY_BUTTON_A},
	{"id": "attack", "label": "Attack", "key": KEY_SPACE, "pad": 101},
	{"id": "bomb", "label": "Throw Bomb", "key": KEY_Q, "pad": JOY_BUTTON_RIGHT_SHOULDER},
	{"id": "weapon_next", "label": "Next Weapon", "key": KEY_E, "pad": JOY_BUTTON_B},
	{"id": "weapon_prev", "label": "Previous Weapon", "key": KEY_R, "pad": JOY_BUTTON_DPAD_RIGHT},
	{"id": "headlamp", "label": "Headlamp On/Off", "key": KEY_H, "pad": JOY_BUTTON_LEFT_SHOULDER},
	{"id": "battery", "label": "Replace Battery", "key": KEY_X, "pad": JOY_BUTTON_LEFT_STICK},
	{"id": "use_water", "label": "Drink Almond Water", "key": KEY_1, "pad": JOY_BUTTON_Y},
	{"id": "use_bandage", "label": "Use Bandage", "key": KEY_2, "pad": JOY_BUTTON_X},
	{"id": "use_food", "label": "Eat Food", "key": KEY_3, "pad": JOY_BUTTON_DPAD_LEFT},
	{"id": "tactical_map", "label": "Tactical Map (hold)", "key": KEY_M, "pad": 100},
	{"id": "status_hud", "label": "Status Panel (hold)", "key": KEY_C, "pad": JOY_BUTTON_DPAD_UP},
	{"id": "run_stats", "label": "Run Stats (hold)", "key": KEY_F2, "pad": JOY_BUTTON_DPAD_DOWN},
	{"id": "controls", "label": "Controls Help (hold)", "key": KEY_F1, "pad": JOY_BUTTON_RIGHT_STICK},
	{"id": "pause", "label": "Pause (Esc always works)", "key": KEY_P, "pad": -2},      # pad: Menu (Start), fixed
	# Steam Deck back grips (L4 / L5 / R4 / R5) as well as Elite / DualSense-edge paddles. Defaults suit the Deck.
	{"id": "quick_heal", "label": "Quick Heal (grip)", "key": 0, "pad": JOY_BUTTON_PADDLE2},
	{"id": "quick_drink", "label": "Quick Drink (grip)", "key": 0, "pad": JOY_BUTTON_PADDLE4},
	{"id": "quick_bomb", "label": "Quick Bomb (grip)", "key": 0, "pad": JOY_BUTTON_PADDLE1},
	{"id": "quick_lamp", "label": "Quick Lamp (grip)", "key": 0, "pad": JOY_BUTTON_PADDLE3},
]
## Actions that fire a one-frame just() edge when their key / button goes down.
const EDGE_ACTIONS := ["bomb", "weapon_next", "weapon_prev", "headlamp", "battery", "use_water", "use_bandage",
	"use_food", "status_hud", "run_stats", "controls", "pause", "quick_heal", "quick_drink", "quick_bomb", "quick_lamp"]
const RESERVED_KEYS := [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_BACKSPACE, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_F10]
const RESERVED_PADS := [JOY_BUTTON_START]
## Xbox-style names: that is what Steam Input presents on the Deck (A/B/X/Y, LB/RB, LT/RT, L3/R3, View, Menu).
## Back grips: Godot's PADDLE1..4 are R4 / L4 / R5 / L5 on the Deck's layout (SDL order).
const PAD_NAMES := {0: "A", 1: "B", 2: "X", 3: "Y", 4: "View", 5: "Steam", 6: "Menu", 7: "L3",
	8: "R3", 9: "LB", 10: "RB", 11: "D-Pad Up", 12: "D-Pad Down", 13: "D-Pad Left", 14: "D-Pad Right",
	15: "Share", 16: "R4", 17: "L4", 18: "R5", 19: "L5", 20: "Touchpad", 100: "LT", 101: "RT"}
## Touch button label per action ("" = no on-screen button).
const TOUCH_LABELS := {"attack": "ATTACK", "sprint": "SPRINT", "bomb": "BOMB", "weapon_next": "WPN", "weapon_prev": "WPN",
	"headlamp": "LAMP", "battery": "BAT", "use_water": "H2O", "use_bandage": "MED", "use_food": "EAT", "pause": "||"}

signal mode_changed(new_mode: String)
signal binding_captured(device: String, action: String, message: String)

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
var debug_force_pad := -1              # tests: treat this joypad id as connected (headless has none)
var debug_insets := Vector4(-1, -1, -1, -1)   # tests: override the safe-area insets (l, t, r, b)

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
var _sprint_latched := false           # touch SPRINT toggle (tap on / tap off); gamepad and keyboard still hold
const TOUCH_DEADZONE := 0.15            # of the move-stick radius; past it the stick gives a full-speed DIRECTION only
const TOUCH_SPRINT_MIN_STAMINA := 5.0   # a sprint can only be switched on with at least this much stamina
var _fire_latch := false              # an attack press that happened between two ticks
var _refuse_cd := 0.0
var refused_t := 0.0                   # > 0 while an attack is refused for lack of stamina
var _opts_fallback := GameOptions.new()
var _key_edge := {}                    # keycode -> Array[String] of just() actions
var _key_move := {}                    # keycode -> ui nav action (move keys)
var _maps_dirty := true
var _capture := {}                     # {device, action} while waiting for a key / button
var _capture_cooldown := 0.0
var _platform_mode := "keyboard"
var _mouse_acc := 0.0                  # recent real mouse movement in px (hysteresis while a pad is in use)
var _rumble_last := {}                 # kind -> msec of the last rumble


## A new run starts with the touch SPRINT toggle off.
func reset_run() -> void:
	_sprint_latched = false


func setup(g) -> void:
	game = g
	_platform_mode = "touch" if OS.has_feature("mobile") else ("gamepad" if Platform.is_deck_like() else "keyboard")
	mode = _platform_mode
	if not OS.has_feature("mobile") and (not Input.get_connected_joypads().is_empty() or Platform.is_deck_like()):
		mode = "gamepad"                 # a controller is attached at launch (always on a Deck): default to it
	Input.joy_connection_changed.connect(_on_joy_connection)
	_layer = CanvasLayer.new()
	_layer.layer = 60
	_touch_ui = Control.new()
	_touch_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_touch_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch_ui.draw.connect(_draw_touch)
	_layer.add_child(_touch_ui)
	add_child(_layer)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		# drop held state so nothing sticks after alt-tab / Steam overlay / Deck suspend
		_just.clear()
		_fire_latch = false
		_prev_btn.clear()
		stop_rumble()


func _on_joy_connection(_device: int, connected: bool) -> void:
	if connected:
		_set_detected("gamepad")
	elif mode == "gamepad" and Input.get_connected_joypads().is_empty():
		_set_mode(_platform_mode)


# ---- options / bindings -----------------------------------------------------------------

func opts() -> GameOptions:
	if game and game.ui and game.ui.get("options") != null:
		return game.ui.options
	return _opts_fallback


static func action_def(id: String) -> Dictionary:
	for a in ACTIONS:
		if a.id == id:
			return a
	return {}


func key_of(action: String) -> int:
	var o := opts()
	if o.key_binds.has(action):
		return int(o.key_binds[action])
	return int(action_def(action).get("key", 0))


func pad_of(action: String) -> int:
	var o := opts()
	if o.pad_binds.has(action):
		return int(o.pad_binds[action])
	return int(action_def(action).get("pad", -1))


func _rebuild_maps() -> void:
	_maps_dirty = false
	_key_edge.clear()
	_key_move.clear()
	for a in EDGE_ACTIONS:
		var k := key_of(a)
		if k > 0:
			if not _key_edge.has(k):
				_key_edge[k] = []
			_key_edge[k].append(a)
	for pair in [["move_up", "ui_up"], ["move_down", "ui_down"], ["move_left", "ui_left"], ["move_right", "ui_right"]]:
		var k := key_of(pair[0])
		if k > 0:
			_key_move[k] = pair[1]


func mark_bindings_dirty() -> void:
	_maps_dirty = true


## Bind a keyboard key. Returns a human-readable result (mentions a swap when the key was already used).
func set_key(action: String, keycode: int) -> String:
	var o := opts()
	var old := key_of(action)
	var msg := "%s = %s" % [action_def(action).get("label", action), key_name(keycode)]
	for a in ACTIONS:
		if a.id != action and key_of(a.id) == keycode and keycode > 0:
			o.key_binds[a.id] = old
			msg += "   (swapped with %s)" % a.label
	o.key_binds[action] = keycode
	_maps_dirty = true
	o.notify()
	return msg


func set_pad(action: String, code: int) -> String:
	var o := opts()
	var old := pad_of(action)
	var msg := "%s = %s" % [action_def(action).get("label", action), pad_name(code)]
	for a in ACTIONS:
		if a.id != action and int(a.pad) != -2 and pad_of(a.id) == code and code >= 0:
			o.pad_binds[a.id] = old
			msg += "   (swapped with %s)" % a.label
	o.pad_binds[action] = code
	_maps_dirty = true
	o.notify()
	return msg


func reset_bindings(device: String) -> void:
	var o := opts()
	if device == "keyboard":
		o.key_binds.clear()
	else:
		o.pad_binds.clear()
	_maps_dirty = true
	o.notify()


func is_default(device: String, action: String) -> bool:
	var d := action_def(action)
	return key_of(action) == int(d.key) if device == "keyboard" else pad_of(action) == int(d.pad)


func begin_capture(device: String, action: String) -> void:
	_capture = {"device": device, "action": action}


func cancel_capture() -> void:
	if not _capture.is_empty():
		_capture_cooldown = 0.3          # swallow the press that cancelled it; opening a page must not lock input
	_capture = {}


func capturing() -> bool:
	return not _capture.is_empty()


func _finish_capture(msg: String) -> void:
	var dev: String = _capture.device
	var act: String = _capture.action
	_capture = {}
	_capture_cooldown = 0.3
	binding_captured.emit(dev, act, msg)


var _key_names := {}


func key_name(k: int) -> String:
	if k <= 0:
		return "None"
	if _key_names.has(k):
		return _key_names[k]
	var kc := k
	# layout-aware label only where the display server supports it (not headless/Android: it errors every call)
	# (skipped under Proton / on the Deck: names then come from the physical keycode, which is always safe)
	if (OS.has_feature("windows") or OS.has_feature("macos") or OS.has_feature("linuxbsd")) \
			and not Platform.is_proton() and not Platform.is_deck_like():
		if DisplayServer.get_name() != "headless":
			var m: int = DisplayServer.keyboard_get_keycode_from_physical(k as Key)
			if m > 0:
				kc = m
	var n := OS.get_keycode_string(kc as Key)
	var out: String = n if n != "" else "Key %d" % k
	_key_names[k] = out
	return out


## Short glyph name for tight spots (HUD quick-item row).
func pad_short(c: int) -> String:
	match c:
		JOY_BUTTON_DPAD_UP: return "D-Up"
		JOY_BUTTON_DPAD_DOWN: return "D-Down"
		JOY_BUTTON_DPAD_LEFT: return "D-Left"
		JOY_BUTTON_DPAD_RIGHT: return "D-Right"
	return pad_name(c)


func pad_name(c: int) -> String:
	return PAD_NAMES.get(c, "None" if c < 0 else "Button %d" % c)


# ---- text helpers (platform-aware prompts) ----------------------------------------------

func move_prompt(m := "") -> String:
	m = active_mode() if m == "" else m
	match m:
		"gamepad":
			return "Left Stick"
		"touch":
			return "the left stick"
		_:
			return "%s%s%s%s" % [key_name(key_of("move_up")), key_name(key_of("move_left")),
				key_name(key_of("move_down")), key_name(key_of("move_right"))]


func aim_prompt(m := "") -> String:
	m = active_mode() if m == "" else m
	match m:
		"gamepad":
			return "Right Stick"
		"touch":
			return "the right stick (drag)"
		_:
			return "the mouse"


func prompt(action: String, m := "") -> String:
	m = active_mode() if m == "" else m
	if action == "move":
		return move_prompt(m)
	if action == "aim":
		return aim_prompt(m)
	if action in ["accept", "back", "menu"]:
		match m:
			"gamepad":
				return {"accept": "[A]", "back": "[B]", "menu": "[Menu]"}[action]
			"touch":
				return {"accept": "tap", "back": "the back button", "menu": "the pause button"}[action]
			_:
				return {"accept": "[Enter]", "back": "[Esc]", "menu": "[Esc]"}[action]
	match m:
		"gamepad":
			var c := pad_of(action)
			if action in ["menu", "pause"]:
				return "[Menu]"
			if action in ["accept", "interact"]:
				return "[A]"
			if action == "back":
				return "[B]"
			return "[%s]" % pad_name(c) if c >= 0 else "(unbound)"
		"touch":
			if TOUCH_LABELS.has(action):
				var l: String = TOUCH_LABELS[action]
				return "the %s button" % l if l != "||" else "the pause button"
			return "(keyboard / gamepad only)"
		_:
			var n := "[%s]" % key_name(key_of(action))
			if action == "attack":
				return "%s / Left Click" % n
			if action == "tactical_map":
				return "%s / Right Click" % n
			if action == "pause":
				return "[Esc]"
			return n


## Replaces {action} tokens (e.g. "Press {use_water}") with the prompt for the active scheme.
func fill(template: String, m := "") -> String:
	var out := template
	var rx := RegEx.new()
	rx.compile("\\{([a-z_]+)\\}")
	for mt in rx.search_all(template):
		var tok: String = mt.get_string(1)
		out = out.replace("{%s}" % tok, prompt(tok, m))
	return out


## One-line footer / prompt text for the ACTIVE device. Keyboard wording is never returned while a controller
## (or touch) is in use. This and prompt() are the only places that name physical inputs, so real Steam Input
## glyph textures can replace them later in one spot.
func hint(kb: String, pad: String, touch := "") -> String:
	match active_mode():
		"gamepad":
			return pad
		"touch":
			return touch if touch != "" else pad
		_:
			return kb


func controls_list(m := "") -> Array:
	m = active_mode() if m == "" else m
	var out: Array = []
	match m:
		"touch":
			out = [["Left side drag", "Move (floating stick)"], ["Right side drag", "Aim, auto-fires"],
				["ATTACK (hold)", "Attack, auto-aims at nearest enemy"], ["SPRINT", "Tap to toggle sprint on / off"],
				["BOMB", "Throw a bomb"], ["WPN", "Cycle weapon"], ["H2O / MED / EAT", "Drink / bandage / eat"],
				["LAMP / BAT", "Headlamp / replace battery"], ["||", "Pause / menu"], ["Double-tap centre", "Pause / menu"]]
		"gamepad":
			out = [["Left Stick", "Move"], ["Right Stick", "Aim (auto-aim when idle)"]]
			for a in ACTIONS:
				if int(a.pad) != -2 and pad_of(a.id) >= 0:
					out.append([pad_name(pad_of(a.id)), String(a.label)])
			out.append(["Menu", "Pause / menu"])
			out.append(["View", "Dismiss tip (hold: tips off)"])
		_:
			out = [[move_prompt("keyboard"), "Move (relative to aim)"], ["Mouse", "Aim"], ["Left Click", "Attack"],
				["Right Click (hold)", "Tactical Map"], ["Wheel", "Change weapon"]]
			for a in ACTIONS:
				if not String(a.id).begins_with("move_") and key_of(a.id) > 0:
					out.append([key_name(key_of(a.id)), String(a.label)])
			out.append(["F10", "Options"])
	return out


func scheme() -> Dictionary:
	var m := active_mode()
	return {"name": {"keyboard": "Keyboard + Mouse", "gamepad": "Gamepad", "touch": "Touchscreen"}.get(m, "Keyboard + Mouse"),
		"controls": controls_list(m)}


## Controller rumble. kind: hit | kill | damage | explosion | levelup | refuse. `scale` multiplies the strength
## (e.g. damage / 30). Honours Options > Rumble / Rumble Strength; no-op unless a pad is the active device.
const RUMBLE := {"hit": [0.0, 0.30, 0.06, 90], "kill": [0.25, 0.45, 0.10, 120], "damage": [0.45, 0.85, 0.22, 100],
	"explosion": [0.90, 1.00, 0.40, 200], "levelup": [0.35, 0.30, 0.30, 400], "refuse": [0.10, 0.25, 0.08, 300]}


func rumble(kind: String, scale := 1.0) -> void:
	var o := opts()
	if not o.rumble or _gp < 0 or active_mode() != "gamepad" or not RUMBLE.has(kind):
		return
	var r: Array = RUMBLE[kind]
	var now := Time.get_ticks_msec()
	if now - int(_rumble_last.get(kind, -10000)) < int(r[3]):
		return
	_rumble_last[kind] = now
	var k := o.rumble_strength * clampf(scale, 0.3, 1.5)
	Input.start_joy_vibration(_gp, clampf(r[0] * k, 0.0, 1.0), clampf(r[1] * k, 0.0, 1.0), r[2])


func stop_rumble() -> void:
	if _gp >= 0:
		Input.stop_joy_vibration(_gp)


## Light vibration on Android when haptics are enabled (touch mode only).
func vibrate(ms: int, amplitude := -1.0) -> void:
	if opts().haptics and active_mode() == "touch" and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms, amplitude)


# ---- public ----------------------------------------------------------------------------

func just(action: String) -> bool:
	return _just.has(action)


func press(action: String) -> void:
	if _capture_cooldown > 0.0 or not _capture.is_empty():
		return
	match action:
		"quick_bomb":
			action = "bomb"
		"quick_lamp":
			action = "headlamp"
		"quick_heal":
			action = _pick_heal()
		"quick_drink":
			action = _pick_drink()
	_just[action] = true


## Back-grip shortcuts: pick the item that helps most (bandage when hurt, else water, else food).
func _pick_heal() -> String:
	var p = game.player if game else null
	if p == null:
		return "use_bandage"
	if p.bandages > 0 and p.hp < p.max_hp:
		return "use_bandage"
	if p.almond_water > 0:
		return "use_water"
	if p.food > 0:
		return "use_food"
	return "use_bandage"


func _pick_drink() -> String:
	var p = game.player if game else null
	if p == null or p.almond_water > 0 or p.food <= 0:
		return "use_water"
	return "use_food"


## "keyboard" | "gamepad" | "touch" (resolves the options "Controller" setting).
func active_mode() -> String:
	var forced := _forced_mode()
	if forced != "auto":
		return forced
	return mode


func _forced_mode() -> String:
	return opts().get_control_mode()


func pad_held(b: JoyButton) -> bool:
	return _btn(b)


func has_gamepad() -> bool:
	return _gp >= 0


# ---- per-frame ----------------------------------------------------------------------------

func tick(dt: float) -> void:
	_mouse_acc = maxf(0.0, _mouse_acc - 200.0 * dt)
	if _maps_dirty:
		_rebuild_maps()
	if _capture_cooldown > 0.0:
		_capture_cooldown -= dt
	_poll_gamepad_device()
	Glyphs.sync(active_mode() == "gamepad", Input.get_joy_name(_gp) if _gp >= 0 else "", GameOptions.PROMPT_FAMILIES[clampi(opts().prompt_style, 0, GameOptions.PROMPT_FAMILIES.size() - 1)])
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
	refused_t = maxf(0.0, refused_t - dt)
	_refuse_cd = maxf(0.0, _refuse_cd - dt)
	if playing and fire and game.ui != null:
		var why: String = game.ui.attack_state()
		if why != "":
			refused_t = 0.35                  # HUD flashes the stamina bar / dims the weapon (every scheme)
			if _refuse_cd <= 0.0:
				_refuse_cd = 0.7
				_refuse_feedback(why)
	if not _capture.is_empty():
		fire = false
		alt_fire = false
		sprint = false
		move = Vector2.ZERO
	_touch_ui.visible = (m == "touch" and playing)
	if _touch_ui.visible:
		_touch_ui.queue_redraw()


func _refuse_feedback(why: String) -> void:
	if game.fx:
		game.fx.shake(2.0, 0.08)
	if why == "stamina":
		if game.audio:
			game.audio.play("gasp_for_air", null, 0.35, 1.2)
		game.ui.add_message("NO STAMINA", Color(1, 0.6, 0.2), 1.0)
		vibrate(30)
		rumble("refuse")
	elif game.audio:
		game.audio.play("swing_sound", null, 0.3, 1.8)    # dry click; weapons.gd shows NO AMMO
		vibrate(30)
		rumble("refuse")


## Called by game.gd at the end of every simulated frame (NOT during hit-stop), so presses made between
## ticks or during hit-stop stay queued until a real tick has read them.
func end_frame() -> void:
	_just.clear()
	_fire_latch = false


func _player_px() -> Vector2:
	return game.player.position if game and game.player else Vector2.ZERO


func _kheld(action: String) -> bool:
	var k := key_of(action)
	return k > 0 and Input.is_physical_key_pressed(k as Key)


func _update_keyboard() -> void:
	var raw := Vector2(
		float(_kheld("move_right") or Input.is_physical_key_pressed(KEY_RIGHT))
		- float(_kheld("move_left") or Input.is_physical_key_pressed(KEY_LEFT)),
		float(_kheld("move_down") or Input.is_physical_key_pressed(KEY_DOWN))
		- float(_kheld("move_up") or Input.is_physical_key_pressed(KEY_UP)))
	if text_entry:
		raw = Vector2.ZERO
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
	sprint = _kheld("sprint")
	fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or _kheld("attack") or _fire_latch
	alt_fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or _kheld("tactical_map")
	show_controls = _kheld("controls")
	show_run_stats = _kheld("run_stats")
	show_status = _kheld("status_hud") and not text_entry


func _poll_gamepad_device() -> void:
	if debug_force_pad >= 0:               # tests: pretend this joypad id is attached
		_gp = debug_force_pad
		return
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		_gp = -1
		if mode == "gamepad":
			_set_mode(_platform_mode)
	elif _gp not in pads:
		_gp = pads[0]


func _axis(a: JoyAxis) -> float:
	return Input.get_joy_axis(_gp, a) if _gp >= 0 else 0.0


func _btn(b: JoyButton) -> bool:
	return _gp >= 0 and Input.is_joy_button_pressed(_gp, b)


## Radial dead zone with rescaling: small drift is ignored, then the response ramps smoothly up to full
## deflection (reached at ~95% of the gate so a worn or square-gated stick still gets 100% speed).
func _stick(ax: JoyAxis, ay: JoyAxis) -> Vector2:
	var v := Vector2(_axis(ax), _axis(ay))
	var dz := clampf(opts().pad_deadzone, 0.05, 0.4)
	var l := v.length()
	if l <= dz:
		return Vector2.ZERO
	return v / l * clampf((l - dz) / (0.95 - dz), 0.0, 1.0)


func _code_held(code: int, trig_thresh := TRIGGER_THRESH) -> bool:
	if code < 0:
		return false
	if code == 100:
		return _axis(JOY_AXIS_TRIGGER_LEFT) > trig_thresh
	if code == 101:
		return _axis(JOY_AXIS_TRIGGER_RIGHT) > trig_thresh
	return _btn(code as JoyButton)


func _update_gamepad(dt: float) -> void:
	var ls := _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
	var lx := ls.x
	var ly := ls.y
	move = ls
	var rs := _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
	var rx := rs.x
	var ry := rs.y
	aim_active = rs != Vector2.ZERO
	if aim_active:
		_gp_aim_dir = rs.normalized()
		aim_angle = _gp_aim_dir.angle()
		aim_world = _player_px() + _gp_aim_dir * 5.0 * game.TILE
	else:
		aim_world = _player_px() + _gp_aim_dir * 5.0 * game.TILE
		_try_aim_assist()
	fire = _code_held(pad_of("attack")) or _fire_latch
	alt_fire = _code_held(pad_of("tactical_map"))
	sprint = _code_held(pad_of("sprint"))
	show_status = _code_held(pad_of("status_hud"))
	show_run_stats = _code_held(pad_of("run_stats"))
	show_controls = _code_held(pad_of("controls"))

	# trigger-bound actions are polled (triggers are axes); buttons are event-driven in _input so a quick tap
	# between two ticks is never lost
	for a in EDGE_ACTIONS:
		var c := pad_of(a)
		if c < 100:
			continue
		var key: String = "act_" + str(a)
		var now := _code_held(c, TRIGGER_EDGE)
		if now and not _prev_btn.get(key, false):
			press(a)
		_prev_btn[key] = now

	# UI navigation pulses (d-pad + both sticks), with hold-repeat
	var sx := lx if absf(lx) > absf(rx) else rx
	var sy := ly if absf(ly) > absf(ry) else ry
	var hx := 0
	var hy := 0
	if absf(sx) >= absf(sy):
		sy = 0.0          # sticks navigate along their dominant axis only (no diagonal double steps)
	else:
		sx = 0.0
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


## Display-cutout / system-bar insets in logical UI pixels: Vector4(left, top, right, bottom).
func safe_insets() -> Vector4:
	if debug_insets.x >= 0.0:
		return debug_insets
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var win := Vector2(DisplayServer.window_get_size())
	var sa := DisplayServer.get_display_safe_area()
	if win.x <= 0.0 or win.y <= 0.0 or sa.size.x <= 0 or sa.size.y <= 0:
		return Vector4.ZERO
	var vis := _view_size()
	var sx := vis.x / win.x
	var sy := vis.y / win.y
	var l := maxf(0.0, sa.position.x) * sx
	var t := maxf(0.0, sa.position.y) * sy
	var r := maxf(0.0, win.x - sa.end.x) * sx
	var b := maxf(0.0, win.y - sa.end.y) * sy
	return Vector4(minf(l, vis.x * 0.2), minf(t, vis.y * 0.2), minf(r, vis.x * 0.2), minf(b, vis.y * 0.2))


## Scale factor for touch UI: the size option times a physical-size correction (phones are small).
func touch_scale() -> float:
	var k := opts().touch_size
	if OS.has_feature("mobile"):
		var win := DisplayServer.window_get_size()
		if win.y > 0:
			var ppi_logical := float(DisplayServer.screen_get_dpi()) * _view_size().y / float(win.y)
			k *= clampf(ppi_logical / 280.0, 0.7, 1.6)
	return k


func _tbtn(v: Vector2, lh: bool, x: float, y: float, r: float, action: String, color: Color) -> Dictionary:
	return {"pos": Vector2(v.x - x if lh else x, y), "r": r, "action": action, "label": TOUCH_LABELS[action], "color": color}


## Whole touch layout (landscape): buttons, the two sticks (resting positions + the half-screen zones that
## spawn a floating stick) and the usable rect inside the safe area. Mirrored when left-handed is on.
func touch_layout(view := Vector2.ZERO) -> Dictionary:
	var v := _view_size() if view == Vector2.ZERO else view
	var k := touch_scale()
	var ins := safe_insets() if view == Vector2.ZERO else Vector4.ZERO
	var L := ins.x + 16.0
	var R := v.x - ins.z - 16.0
	var T := ins.y + 12.0
	var B := v.y - ins.w - 16.0
	var lh := opts().touch_left_handed
	var stick_r := 86.0 * k
	var buttons: Array = []
	# right-hand cluster (mirrored when left-handed): big ATTACK in the corner, utility buttons arc above it
	buttons.append(_tbtn(v, lh, R - 92.0 * k, B - 92.0 * k, 80.0 * k, "attack", Color(1, 0.25, 0.2)))
	buttons.append(_tbtn(v, lh, R - 46.0 * k, B - 236.0 * k, 42.0 * k, "bomb", Color(1, 0.5, 0.1)))
	buttons.append(_tbtn(v, lh, R - 144.0 * k, B - 214.0 * k, 40.0 * k, "weapon_next", Color(0.75, 0.75, 0.8)))
	buttons.append(_tbtn(v, lh, R - 46.0 * k, B - 330.0 * k, 38.0 * k, "battery", Color(0.2, 1, 0.6)))
	buttons.append(_tbtn(v, lh, R - 144.0 * k, B - 308.0 * k, 38.0 * k, "headlamp", Color(1, 0.95, 0.6)))
	# left-hand cluster: sprint toggle by the move stick, quick-use row above it
	buttons.append(_tbtn(v, lh, L + 128.0 * k + stick_r + 56.0 * k, B - 60.0 * k, 40.0 * k, "sprint", Color(0.5, 0.8, 1)))
	var qy := B - 98.0 * k - stick_r - 56.0 * k
	buttons.append(_tbtn(v, lh, L + 44.0 * k, qy, 42.0 * k, "use_water", Color(0.3, 0.8, 1)))
	buttons.append(_tbtn(v, lh, L + 138.0 * k, qy, 42.0 * k, "use_bandage", Color(0.3, 1, 0.3)))
	buttons.append(_tbtn(v, lh, L + 232.0 * k, qy, 42.0 * k, "use_food", Color(0.85, 0.65, 0.25)))
	buttons.append({"pos": Vector2(v.x * 0.5, T + 30.0 * k), "r": 28.0 * k, "action": "pause", "label": "||", "color": Color(0.9, 0.8, 0.2)})
	var move_x := L + 128.0 * k
	var aim_x := R - 92.0 * k - 80.0 * k - 40.0 * k - stick_r
	var move_c := Vector2(v.x - move_x if lh else move_x, B - 98.0 * k)
	var aim_c := Vector2(v.x - aim_x if lh else aim_x, B - 98.0 * k)
	var half := v.x * 0.5
	var move_zone := Rect2(0, 0, half, v.y) if not lh else Rect2(half, 0, half, v.y)
	return {"k": k, "buttons": buttons, "stick_r": stick_r, "move_c": move_c, "aim_c": aim_c,
		"move_zone": move_zone, "safe": Rect2(L, T, R - L, B - T)}


func touch_buttons() -> Array:
	return touch_layout().buttons


func _update_touch(_playing: bool) -> void:
	var lay := touch_layout()
	var maxr: float = lay.stick_r
	var k: float = lay.k
	var l: Dictionary = _sticks.left
	var r: Dictionary = _sticks.right
	aim_active = false
	var attacking: bool = _btn_touch.values().has("attack")
	if l.id >= 0:
		var d: Vector2 = l.p - l.o
		# Direction only: past the dead zone the move vector is always unit length, so there is exactly ONE walking
		# speed however far the thumb travels (diagonals are unit length too). Sprint never comes from the stick.
		if d.length() > maxf(8.0, maxr * TOUCH_DEADZONE):
			move = d.normalized()
	# SPRINT is a toggle. Running out of stamina switches it off and it does NOT come back by itself: tap again.
	var pl = game.player
	if _sprint_latched and pl != null and pl.stamina <= 0.0:
		_sprint_latched = false
		_btn_flash["sprint"] = 0.18
	if _sprint_latched and move.length() > 0.1:
		sprint = true
	var aimed := false
	if r.id >= 0:
		var d2: Vector2 = r.p - r.o
		if d2.length() > 10.0 * k:
			_touch_aim_dir = d2.normalized()
			aim_angle = d2.angle()
			aimed = true
			aim_active = true
			fire = true     # input.lua: dragging the right stick auto-fires
	if attacking:
		fire = true
		if not aimed:
			var tgt := _nearest_enemy_dir()
			if tgt != Vector2.ZERO:
				_touch_aim_dir = tgt
			elif move.length() > 0.2:
				_touch_aim_dir = move.normalized()
	elif not aimed and move.length() > 0.2:
		_touch_aim_dir = move.normalized()   # face where you walk when nothing is aimed
	aim_world = _player_px() + _touch_aim_dir * 5.0 * game.TILE


## Direction to the closest enemy within 7 tiles (used by the ATTACK button), or ZERO.
func _nearest_enemy_dir() -> Vector2:
	if game.enemies == null or game.player == null:
		return Vector2.ZERO
	var best := 7.0
	var dir := Vector2.ZERO
	for e in game.enemies.get_enemies():
		var d: Vector2 = e.tile_pos - game.player.tile_pos
		if d.length() < best:
			best = d.length()
			dir = d.normalized()
	return dir


## Index of the button a touch at pos hits (hit radius = max(1.4x visual, a minimum finger size); the nearest
## button edge wins when hit areas overlap), or -1.
func _pick_button(pos: Vector2, lay: Dictionary) -> int:
	var best := -1
	var best_d := INF
	var k: float = lay.k
	for i in lay.buttons.size():
		var b: Dictionary = lay.buttons[i]
		var hr := maxf(b.r * 1.4, 34.0 * k)
		var d: float = pos.distance_to(b.pos)
		if d <= hr and d - b.r < best_d:
			best_d = d - b.r
			best = i
	return best


func _release_touch(index: int) -> void:
	for s in _sticks.values():
		if s.id == index:
			s.id = -1
	_btn_touch.erase(index)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if not _touch_seen:
		_touch_seen = true
	_set_detected("touch")
	if game.state != "playing":
		return
	if event.canceled or not event.pressed:
		_release_touch(event.index)
		return
	_release_touch(event.index)             # a stale entry for this finger (missed release) must not stick
	var pos := event.position
	var v := _view_size()
	if game.ui and game.ui.get("tips") != null and game.ui.tips.try_tap(pos):
		return
	var lay := touch_layout()
	var bi := _pick_button(pos, lay)
	if bi >= 0:
		var b: Dictionary = lay.buttons[bi]
		_btn_flash[b.action] = 0.18               # instant pressed feedback
		if b.action == "sprint":
			if _sprint_latched:
				_sprint_latched = false
			elif touch_enabled("sprint"):
				_sprint_latched = true
			else:
				refused_t = 0.35                 # no stamina: HUD flashes the bar, the button shows it is unavailable
		else:
			press(b.action)
			_btn_touch[event.index] = b.action
		return
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
	# stick: left/right half; a touch inside the resting circle snaps to it (fixed stick), anywhere else floats
	var is_move: bool = lay.move_zone.has_point(pos)
	var s: Dictionary = _sticks.left if is_move else _sticks.right
	var rest: Vector2 = lay.move_c if is_move else lay.aim_c
	if s.id < 0:
		s.id = event.index
		s.o = rest if pos.distance_to(rest) <= lay.stick_r * 1.15 else pos
		s.p = pos


func _handle_drag(event: InputEventScreenDrag) -> void:
	for s in _sticks.values():
		if s.id == event.index:
			s.p = event.position


## Whether a touch button currently does something (disabled ones are drawn greyed out but still react).
func touch_enabled(action: String) -> bool:
	var p = game.player
	if p == null:
		return true
	match action:
		"attack":
			return game.ui == null or game.ui.attack_state() == ""
		"sprint": return _sprint_latched or p.stamina >= TOUCH_SPRINT_MIN_STAMINA
		"use_water": return p.almond_water > 0
		"use_bandage": return p.bandages > 0 and p.hp < p.max_hp
		"use_food": return p.food > 0
		"battery": return p.batteries > 0
		"bomb": return game.ui == null or game.ui._bomb_count() > 0
		"weapon_next":
			var w2 = game.weapons
			if w2 and "unlocked" in w2:
				var n := 0
				for u in w2.unlocked:
					if u:
						n += 1
				return n > 1
	return true


func _draw_touch() -> void:
	var lay := touch_layout()
	var k: float = lay.k
	var maxr: float = lay.stick_r
	var op := opts().touch_opacity
	var font := UITheme.title_font()
	# "left" stick record = move stick, "right" = aim stick (regardless of which side they sit on)
	var rest := {"left": lay.move_c, "right": lay.aim_c}
	var names := {"left": "MOVE", "right": "AIM"}
	for key in ["left", "right"]:
		var s: Dictionary = _sticks[key]
		var col := Color(1, 1, 1) if key == "left" else Color(1, 0.3, 0.2)
		var o: Vector2 = s.o if s.id >= 0 else rest[key]
		var kp: Vector2 = s.p if s.id >= 0 else o
		draw_stick(o, maxr, kp, col, op if s.id >= 0 else op * 0.8, k)
		if s.id < 0:
			var gl: String = names[key]
			var gfs := maxi(12, int(13 * k))
			var gw := font.get_string_size(gl, HORIZONTAL_ALIGNMENT_LEFT, -1, gfs).x
			_touch_ui.draw_string(font, o + Vector2(-gw * 0.5, maxr + 18 * k), gl, HORIZONTAL_ALIGNMENT_LEFT, -1, gfs, Color(1, 1, 1, 0.8 * op))
	var p = game.player
	var ui = game.ui
	var f := op / 0.6
	for b in lay.buttons:
		var is_sprint: bool = b.action == "sprint"
		var sprint_on: bool = is_sprint and _sprint_latched
		var pressed: bool = _btn_flash.has(b.action) or sprint_on
		var c: Color = b.color
		var on := touch_enabled(b.action)
		var dim := 1.0 if on else 0.35
		if not on:
			c = Color(0.9, 0.3, 0.25) if is_sprint else Color(0.55, 0.55, 0.55)   # SPRINT without stamina reads red
		var r: float = b.r * (0.92 if pressed and not sprint_on else 1.0)
		if sprint_on:      # ON: solid lit button with a halo, unmistakable at a glance
			_touch_ui.draw_circle(b.pos, r * 1.28, Color(c, minf(1.0, 0.20 * f)))
			_touch_ui.draw_circle(b.pos, r, Color(c, minf(1.0, 0.85 * f)))
			_touch_ui.draw_arc(b.pos, r, 0, TAU, 40, Color(1, 1, 1, minf(1.0, 0.95 * f)), 4.0)
		else:
			_touch_ui.draw_circle(b.pos, r, Color(c, minf(1.0, (0.55 if pressed else 0.30) * f * dim)))
			_touch_ui.draw_arc(b.pos, r, 0, TAU, 40, Color(c, minf(1.0, 0.95 * f * dim)), (3.4 if pressed else 2.4))
		if is_sprint:      # state word under the button: ON / OFF / NO STAMINA
			var sw := "ON" if sprint_on else ("OFF" if on else "NO STAMINA")
			var sf := maxi(12, int(13 * k))
			var sww := font.get_string_size(sw, HORIZONTAL_ALIGNMENT_LEFT, -1, sf).x
			var scol := Color(1, 1, 1) if sprint_on else (Color(0.8, 0.85, 0.9) if on else Color(1, 0.45, 0.4))
			_touch_ui.draw_string(font, b.pos + Vector2(-sww * 0.5, b.r + sf + 4.0 * k), sw, HORIZONTAL_ALIGNMENT_LEFT, -1, sf, Color(scol, minf(1.0, 0.95 * f)))
		var fs := int(maxf(12.0, b.r * (0.36 if b.action == "attack" else 0.46)))
		var tw := font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if tw > r * 1.7:
			fs = maxi(10, int(fs * r * 1.7 / tw))
			tw = font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_touch_ui.draw_string(font, b.pos + Vector2(-tw * 0.5, fs * 0.33), b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(0.02, 0.06, 0.12, 1.0) if sprint_on else Color(1, 1, 1, minf(1.0, 0.95 * f * dim)))
		# inventory badge
		var count := -1
		if p:
			match b.action:
				"use_water": count = p.almond_water
				"use_bandage": count = p.bandages
				"use_food": count = p.food
				"battery": count = p.batteries
				"bomb": count = ui._bomb_count() if ui else -1
				"weapon_next":
					if ui and ui.weapon_info().get("type", "melee") == "ranged":
						count = ui.ammo()
		if count >= 0:
			var bp: Vector2 = b.pos + Vector2(b.r * 0.72, -b.r * 0.72)
			var cs := str(count)
			var bf := maxi(12, int(15 * k))
			var cw := ThemeDB.fallback_font.get_string_size(cs, HORIZONTAL_ALIGNMENT_LEFT, -1, bf).x
			var br := maxf(11.0 * k, cw * 0.5 + 5.0)
			_touch_ui.draw_circle(bp, br, Color(0, 0, 0, 0.8))
			_touch_ui.draw_arc(bp, br, 0, TAU, 20, Color(c, 0.8), 1.5)
			_touch_ui.draw_string(ThemeDB.fallback_font, bp + Vector2(-cw * 0.5, bf * 0.36), cs, HORIZONTAL_ALIGNMENT_LEFT, -1,
				bf, Color(1, 1, 1) if count > 0 else Color(1, 0.4, 0.4))


func draw_stick(o: Vector2, maxr: float, knob_p: Vector2, col: Color, a: float, k: float) -> void:
	var f := a / 0.6
	_touch_ui.draw_circle(o, maxr, Color(col, minf(1.0, 0.16 * f)))
	_touch_ui.draw_arc(o, maxr, 0, TAU, 48, Color(col, minf(1.0, 0.7 * f)), 2.5)
	var knob: Vector2 = o + (knob_p - o).limit_length(maxr)
	_touch_ui.draw_circle(knob, 34.0 * k, Color(col, minf(1.0, 0.34 * f)))
	_touch_ui.draw_arc(knob, 34.0 * k, 0, TAU, 28, Color(col, minf(1.0, 0.8 * f)), 2.5)


# ---- events ----------------------------------------------------------------------------------

func _set_mode(m: String) -> void:
	if mode != m:
		mode = m
		mode_changed.emit(active_mode())


## Auto-detection: switch to whichever device the player just used (unless the options force a scheme).
func _set_detected(m: String) -> void:
	if _forced_mode() == "auto":
		_set_mode(m)


func _input(event: InputEvent) -> void:
	if game == null:
		return
	if not _capture.is_empty() and _capture_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		# On desktop / Steam Deck a touch is just a mouse click (Godot emulates it): never switch to the
		# on-screen touch controls unless the player forced "Touch" in Options.
		if _touch_controls_allowed():
			_handle_touch(event)
	elif event is InputEventScreenDrag:
		if _touch_controls_allowed():
			_handle_drag(event)
	elif event is InputEventKey and event.pressed:
		if not event.echo or _is_nav_key(event.physical_keycode):
			_set_detected("keyboard")
			_key_pressed(event)
	elif event is InputEventMouseButton and event.pressed:
		if event.device != InputEvent.DEVICE_ID_EMULATION and not _touch_recent():
			_set_detected("keyboard")
			_mouse_acc = 100.0
			if event.button_index == MOUSE_BUTTON_LEFT:
				_fire_latch = true
		if game.state == "playing":
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				press("weapon_next")
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				press("weapon_prev")
			elif event.button_index == MOUSE_BUTTON_LEFT:
				if game.ui and game.ui.get("tips") != null and game.ui.tips.try_tap(event.position):
					get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if event.device != InputEvent.DEVICE_ID_EMULATION and not _touch_recent():
			# while a pad is in use, a brushed trackpad / bumped mouse must not flip the prompts to keyboard
			_mouse_acc += event.relative.length()
			if _mouse_acc > (40.0 if mode == "gamepad" else 1.5):
				_set_detected("keyboard")
	elif event is InputEventJoypadButton and event.pressed:
		_gp = event.device                 # follow whichever pad is actually being used (Steam virtual pad etc.)
		_set_detected("gamepad")
		if active_mode() == "gamepad":
			_pad_button_pressed(event.button_index)
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) > 0.5:
			_gp = event.device
			_set_detected("gamepad")
		if active_mode() == "gamepad" and event.axis == JOY_AXIS_TRIGGER_RIGHT and event.axis_value > 0.3 \
				and pad_of("attack") == 101:
			_fire_latch = true
		elif active_mode() == "gamepad" and event.axis == JOY_AXIS_TRIGGER_LEFT and event.axis_value > 0.3 \
				and pad_of("attack") == 100:
			_fire_latch = true


## While a binding is being captured: returns true if the event was consumed.
func _capture_input(event: InputEvent) -> bool:
	var dev: String = _capture.device
	var act: String = _capture.action
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		cancel_capture()
		binding_captured.emit(dev, act, "Cancelled")
		return true
	if dev == "keyboard" and event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k in RESERVED_KEYS or k == 0:
			binding_captured.emit(dev, act, "%s is reserved - pick another key" % key_name(k))
			return true
		_finish_capture(set_key(act, k))
		return true
	if dev == "gamepad":
		if event is InputEventJoypadButton and event.pressed:
			var b: int = event.button_index
			if b == JOY_BUTTON_START:
				cancel_capture()
				binding_captured.emit(dev, act, "Cancelled")
				return true
			_finish_capture(set_pad(act, b))
			return true
		if event is InputEventJoypadMotion and absf(event.axis_value) > 0.6:
			if event.axis == JOY_AXIS_TRIGGER_LEFT:
				_finish_capture(set_pad(act, 100))
				return true
			if event.axis == JOY_AXIS_TRIGGER_RIGHT:
				_finish_capture(set_pad(act, 101))
				return true
	# ignore everything else but eat key presses so nothing leaks into the game / menus
	return event is InputEventKey and event.pressed


func _pad_button_pressed(b: int) -> void:
	match b:
		JOY_BUTTON_A:
			press("ui_accept")
		JOY_BUTTON_B:
			press("ui_back")
			press("pad_b")
		JOY_BUTTON_X:
			press("pad_x")
		JOY_BUTTON_Y:
			press("pad_y")
		JOY_BUTTON_START:
			press("pad_start")
			press("pause")             # Menu always pauses (and resumes) like on every console
		JOY_BUTTON_BACK:
			press("ui_back")
			press("pad_back")
	if _maps_dirty:
		_rebuild_maps()
	for a in EDGE_ACTIONS:
		if pad_of(a) == b:
			press(a)
	if pad_of("attack") == b:
		_fire_latch = true


func _touch_controls_allowed() -> bool:
	return OS.has_feature("mobile") or opts().get_control_mode() == "touch"


func _touch_recent() -> bool:
	return _touch_seen and mode == "touch"


func _is_nav_key(k: int) -> bool:
	return k in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_BACKSPACE]


func _key_pressed(event: InputEventKey) -> void:
	var k := event.physical_keycode
	var nav_ok := not text_entry
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
				press("tip_skip_all")
		KEY_ESCAPE:
			press("pause")
			press("ui_back")
		KEY_F10:
			press("options")
	if event.echo or k in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER, KEY_BACKSPACE, KEY_ESCAPE, KEY_F10]:
		return
	if _maps_dirty:
		_rebuild_maps()
	if k == key_of("attack") and nav_ok:
		_fire_latch = true
	if k == KEY_SPACE and nav_ok:
		press("ui_accept")
	if k == KEY_TAB and nav_ok:
		press("weapon_next")
	if _key_move.has(k) and nav_ok:
		press(_key_move[k])
	if _key_edge.has(k):
		# letter keys are ignored while a text box is open; function keys / digits still work
		if nav_ok or not (k >= KEY_A and k <= KEY_Z):
			for a in _key_edge[k]:
				press(a)
