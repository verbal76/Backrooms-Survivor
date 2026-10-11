class_name GameOptions
extends RefCounted
## Port of options.lua settings (data only; the screens live in options_screen.gd).
## Persisted to user://options.json. Other systems read the public vars directly:
##   game.ui.options.music_volume / sfx_volume (0..1), brightness (0..1), headlamp_brightness (0.1..1).

const PATH := "user://options.json"
const CONTROL_MODES := ["auto", "keyboard", "gamepad", "touch"]
const RESOLUTIONS := [Vector2i(640, 480), Vector2i(800, 600), Vector2i(960, 720), Vector2i(1280, 720),
	Vector2i(1280, 960), Vector2i(1920, 1080)]

signal changed

var music_volume := 0.75
var sfx_volume := 0.75
var brightness := 1.0              # title/pause "Brightness" slider
var headlamp_brightness := 1.0
var control_mode := 0              # index in CONTROL_MODES
var res_index := 2
var fullscreen := false
var aim_assist := true
var difficulty := 1                # 1..4 (last selected)
var last_character := ""
# controls (see GameInput.ACTIONS for the action ids). Only rebound entries are stored; the rest use defaults.
var key_binds := {}                # action -> physical keycode (int)
var pad_binds := {}                # action -> joypad code (JoyButton, or 100 = left trigger, 101 = right trigger, -1 = none)
# touch controls
var touch_size := 1.0              # 0.6 .. 1.5
var touch_opacity := 0.6           # 0.2 .. 1.0
var touch_left_handed := false     # mirror the layout
var haptics := true                # vibrate on hits / damage (Android)
var tips_enabled := true           # context tips (tutorial)


func get_control_mode() -> String:
	return CONTROL_MODES[clampi(control_mode, 0, CONTROL_MODES.size() - 1)]


## Lua: Options:getAmbientBoost()
func get_ambient_boost() -> float:
	return brightness * 0.08


func notify() -> void:
	changed.emit()


func apply_window() -> void:
	if OS.has_feature("mobile") or DisplayServer.get_name() == "headless":
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var r: Vector2i = RESOLUTIONS[clampi(res_index, 0, RESOLUTIONS.size() - 1)]
		DisplayServer.window_set_size(r)


func to_dict() -> Dictionary:
	return {"music_volume": music_volume, "sfx_volume": sfx_volume, "brightness": brightness,
		"headlamp_brightness": headlamp_brightness, "control_mode": control_mode, "res_index": res_index,
		"fullscreen": fullscreen, "aim_assist": aim_assist, "difficulty": difficulty,
		"last_character": last_character, "key_binds": key_binds, "pad_binds": pad_binds,
		"touch_size": touch_size, "touch_opacity": touch_opacity, "touch_left_handed": touch_left_handed,
		"haptics": haptics, "tips_enabled": tips_enabled}


func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(to_dict(), "\t"))


func load_from_disk() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (parsed is Dictionary):
		return
	var d: Dictionary = parsed
	music_volume = clampf(float(d.get("music_volume", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(d.get("sfx_volume", sfx_volume)), 0.0, 1.0)
	brightness = clampf(float(d.get("brightness", brightness)), 0.0, 1.0)
	headlamp_brightness = clampf(float(d.get("headlamp_brightness", headlamp_brightness)), 0.1, 1.0)
	control_mode = clampi(int(d.get("control_mode", control_mode)), 0, CONTROL_MODES.size() - 1)
	res_index = clampi(int(d.get("res_index", res_index)), 0, RESOLUTIONS.size() - 1)
	fullscreen = bool(d.get("fullscreen", fullscreen))
	aim_assist = bool(d.get("aim_assist", aim_assist))
	difficulty = clampi(int(d.get("difficulty", difficulty)), 1, 4)
	last_character = str(d.get("last_character", last_character))
	touch_size = clampf(float(d.get("touch_size", touch_size)), 0.6, 1.5)
	touch_opacity = clampf(float(d.get("touch_opacity", touch_opacity)), 0.2, 1.0)
	touch_left_handed = bool(d.get("touch_left_handed", touch_left_handed))
	haptics = bool(d.get("haptics", haptics))
	tips_enabled = bool(d.get("tips_enabled", tips_enabled))
	key_binds = _int_map(d.get("key_binds", {}))
	pad_binds = _int_map(d.get("pad_binds", {}))


static func _int_map(v: Variant) -> Dictionary:
	var out := {}
	if v is Dictionary:
		for k in v:
			out[str(k)] = int(v[k])
	return out
