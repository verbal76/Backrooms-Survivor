extends Control
## Boot scene. In debug builds it asks the dev release for a newer patch pack,
## downloads + verifies it, loads it, then starts the game scene.
## Keep this file small and stable: a patch can replace the game, but this
## boot code only changes with a new full build (bump min_base_build.txt if it does).

const Patcher = preload("res://scripts/patcher.gd")
const GAME_SCENE := "res://scenes/game.tscn"
const MANIFEST_TIMEOUT := 8.0
const DOWNLOAD_TIMEOUT := 120.0

var _status: Label
var _base_build := 0


func _ready() -> void:
	_build_ui()
	_base_build = int(Patcher.read_info().get("build", 0))  # read before any patch loads
	if Patcher.updater_enabled():
		if Patcher.apply_installed(_base_build):
			_set_status("Loaded installed patch")
		await _check_for_update()
	await get_tree().create_timer(0.4).timeout
	get_tree().change_scene_to_file(GAME_SCENE)


func _check_for_update() -> void:
	var info := Patcher.read_info()
	var current := int(info.get("build", 0))
	var manifest_url: String = info.get("manifest_url", "")
	if manifest_url == "":
		return

	_set_status("Checking for updates...")
	var result := await _http_get(manifest_url, "", MANIFEST_TIMEOUT)
	if not result.ok:
		_set_status("Update server unreachable - starting installed build")
		return
	var manifest: Variant = JSON.parse_string(result.body.get_string_from_utf8())
	if not (manifest is Dictionary):
		_set_status("Bad update manifest - starting installed build")
		return

	var latest := int(manifest.get("build", 0))
	if latest <= current:
		_set_status("Up to date (build %d)" % current)
		return

	var min_base := int(manifest.get("min_base_build", 0))
	if _base_build < min_base:
		_set_status("Build %d needs a new full install:\n%s" % [latest, info.get("release_page", "")])
		await get_tree().create_timer(3.0).timeout
		return

	var pck_url := _sibling_url(manifest_url, str(manifest.get("pck", "patch.pck")))
	_set_status("Downloading build %d (%.1f MB)..." % [latest, float(manifest.get("size", 0)) / 1048576.0])
	var tmp := "user://patch_download.tmp"
	var dl := await _http_get(pck_url, tmp, DOWNLOAD_TIMEOUT)
	if not dl.ok:
		_set_status("Download failed - starting installed build")
		return
	if Patcher.sha256_of(tmp) != str(manifest.get("sha256", "")).to_lower():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		_set_status("Checksum mismatch - update rejected")
		return

	var installed := Patcher.install(tmp, latest, _base_build)
	if installed == "" or not ProjectSettings.load_resource_pack(installed, true):
		_set_status("Could not install update - starting installed build")
		return
	_set_status("Updated to build %d" % latest)


## Resolves `file_name` next to `url` (same folder).
func _sibling_url(url: String, file_name: String) -> String:
	return url.get_base_dir() + "/" + file_name


func _http_get(url: String, to_file: String, timeout: float) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = timeout
	if to_file != "":
		req.download_file = to_file
	add_child(req)
	if req.request(url) != OK:
		req.queue_free()
		return {"ok": false, "body": PackedByteArray()}
	var res: Array = await req.request_completed  # [result, code, headers, body]
	req.queue_free()
	return {"ok": res[0] == HTTPRequest.RESULT_SUCCESS and res[1] == 200, "body": res[3]}


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.02)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_FULL_RECT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 22)
	_status.add_theme_color_override("font_color", Color(0.79, 0.71, 0.35))
	add_child(_status)


func _set_status(text: String) -> void:
	_status.text = text
