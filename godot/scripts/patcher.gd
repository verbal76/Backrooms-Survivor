extends RefCounted
## Dev-only OTA helpers: build info, installed patch state, hash check.
## Used by boot.gd. Release builds never call any of this (see updater_enabled()).

const PATCH_DIR := "user://patch"
const STATE_PATH := "user://patch/state.json"
const BUILD_INFO_PATH := "res://build_info.json"


## Updates are a debug-build feature only: release exports (Steam / Play) skip them,
## so store builds only ever update through the store.
static func updater_enabled() -> bool:
	if OS.has_feature("editor"):
		return false
	if not OS.has_feature("debug"):
		return false
	return not ("--no-update" in OS.get_cmdline_user_args())


## Reads res://build_info.json. After a patch is loaded this returns the patch's copy.
static func read_info() -> Dictionary:
	return _read_json(BUILD_INFO_PATH)


static func read_state() -> Dictionary:
	return _read_json(STATE_PATH)


## Loads the previously downloaded patch pack, if it still applies to this base build.
## Call BEFORE anything from the game is loaded. `base_build` is the build baked into the app.
static func apply_installed(base_build: int) -> bool:
	var state := read_state()
	if state.is_empty():
		return false
	var file: String = state.get("file", "")
	var build := int(state.get("build", 0))
	if file == "" or not FileAccess.file_exists(file):
		return false
	# A newer full install supersedes an old patch.
	if build <= base_build or int(state.get("base_build", -1)) != base_build:
		_delete_patch_files()
		return false
	return ProjectSettings.load_resource_pack(file, true)


## Moves a verified download into place and records it. Returns the final pack path ("" on failure).
static func install(tmp_path: String, build: int, base_build: int) -> String:
	var final_path := "%s/patch_%d.pck" % [PATCH_DIR, build]
	_delete_patch_files()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PATCH_DIR))
	var err := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(tmp_path), ProjectSettings.globalize_path(final_path))
	if err != OK:
		return ""
	var f := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify({"build": build, "base_build": base_build, "file": final_path}))
	f.close()
	return final_path


static func sha256_of(path: String) -> String:
	return FileAccess.get_sha256(path).to_lower()


static func _delete_patch_files() -> void:
	var dir := DirAccess.open(PATCH_DIR)
	if dir == null:
		return
	for file_name in dir.get_files():
		dir.remove(file_name)


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
