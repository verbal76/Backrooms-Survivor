class_name GameOptions
extends RefCounted
## Port of options.lua settings (data only; the screens live in options_screen.gd).
## Persisted to user://options.json. Other systems read the public vars directly:
##   game.ui.options.music_volume / sfx_volume (0..1), brightness (0..1), headlamp_brightness (0.1..1).

const PATH := "user://options.json"
const CONTROL_MODES := ["auto", "keyboard", "gamepad", "touch"]
const RESOLUTIONS := [Vector2i(640, 480), Vector2i(800, 600), Vector2i(960, 720), Vector2i(1280, 720),
	Vector2i(1280, 960), Vector2i(1920, 1080), Vector2i(1280, 800), Vector2i(1920, 1200)]

const Platform = preload("res://scripts/platform/platform.gd")
## Frame limiter choices (0 = uncapped). 40 maps to the Steam Deck's 40 Hz refresh mode.
const FPS_CAPS := [30, 40, 45, 60, 0]
const QUALITY_NAMES := ["Low", "Medium", "High"]

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
# display / performance (Steam Deck friendly defaults are applied in apply_platform_defaults())
var ui_scale := 1.0                # 0.8 .. 1.5, scales HUD, menus, tutorial and tips
var high_contrast := false         # brighter, bolder text with darker panels
var vsync := true
var fps_cap_index := 4             # index in FPS_CAPS (desktop: uncapped, vsync paces it; the Deck defaults to 60)
var quality := 2                   # 0 Low / 1 Medium / 2 High
var pause_on_focus_loss := true
# gamepad
var rumble := true
var rumble_strength := 0.8         # 0.1 .. 1.0
var pad_deadzone := 0.2            # stick dead zone radius (0.05 .. 0.4)
var steam_keyboard := false        # name entry: also raise the system / Steam on-screen keyboard


func get_control_mode() -> String:
	return CONTROL_MODES[clampi(control_mode, 0, CONTROL_MODES.size() - 1)]


## Lua: Options:getAmbientBoost()
func get_ambient_boost() -> float:
	return brightness * 0.08


func notify() -> void:
	changed.emit()


## Steam Deck / SteamOS / Big Picture: controller first, fullscreen at the panel's native size, Medium quality,
## a slightly larger UI. Called before options.json is read, so a saved file always wins.
func apply_platform_defaults() -> void:
	if not Platform.is_deck_like():
		return
	fullscreen = true
	quality = 1
	ui_scale = 1.1
	fps_cap_index = FPS_CAPS.find(60)
	vsync = true
	rumble = true


func fps_cap() -> int:
	return FPS_CAPS[clampi(fps_cap_index, 0, FPS_CAPS.size() - 1)]


func apply_window() -> void:
	if OS.has_feature("mobile") or DisplayServer.get_name() == "headless":
		return
	if fullscreen:
		# borderless fullscreen at the display's native size (gamescope on the Deck gives 1280x800)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var r: Vector2i = RESOLUTIONS[clampi(res_index, 0, RESOLUTIONS.size() - 1)]
		DisplayServer.window_set_size(r)
	apply_runtime()


## Frame limiter + vsync (cheap, safe to call whenever an option changes).
func apply_runtime() -> void:
	Engine.max_fps = fps_cap()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


func to_dict() -> Dictionary:
	return {"music_volume": music_volume, "sfx_volume": sfx_volume, "brightness": brightness,
		"headlamp_brightness": headlamp_brightness, "control_mode": control_mode, "res_index": res_index,
		"fullscreen": fullscreen, "aim_assist": aim_assist, "difficulty": difficulty,
		"last_character": last_character, "key_binds": key_binds, "pad_binds": pad_binds,
		"touch_size": touch_size, "touch_opacity": touch_opacity, "touch_left_handed": touch_left_handed,
		"haptics": haptics, "tips_enabled": tips_enabled, "ui_scale": ui_scale, "high_contrast": high_contrast,
		"vsync": vsync, "fps_cap_index": fps_cap_index, "quality": quality, "pause_on_focus_loss": pause_on_focus_loss,
		"rumble": rumble, "rumble_strength": rumble_strength, "pad_deadzone": pad_deadzone,
		"steam_keyboard": steam_keyboard}


func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(to_dict(), "\t"))


func load_from_disk() -> void:
	apply_platform_defaults()
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
	ui_scale = clampf(float(d.get("ui_scale", ui_scale)), 0.8, 1.5)
	high_contrast = bool(d.get("high_contrast", high_contrast))
	vsync = bool(d.get("vsync", vsync))
	fps_cap_index = clampi(int(d.get("fps_cap_index", fps_cap_index)), 0, FPS_CAPS.size() - 1)
	quality = clampi(int(d.get("quality", quality)), 0, 2)
	pause_on_focus_loss = bool(d.get("pause_on_focus_loss", pause_on_focus_loss))
	rumble = bool(d.get("rumble", rumble))
	rumble_strength = clampf(float(d.get("rumble_strength", rumble_strength)), 0.1, 1.0)
	pad_deadzone = clampf(float(d.get("pad_deadzone", pad_deadzone)), 0.05, 0.4)
	steam_keyboard = bool(d.get("steam_keyboard", steam_keyboard))
	key_binds = _int_map(d.get("key_binds", {}))
	pad_binds = _int_map(d.get("pad_binds", {}))


static func _int_map(v: Variant) -> Dictionary:
	var out := {}
	if v is Dictionary:
		for k in v:
			out[str(k)] = int(v[k])
	return out
