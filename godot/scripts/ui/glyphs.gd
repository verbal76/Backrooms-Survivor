class_name Glyphs
extends RefCounted
## Controller glyph prompts. When a controller is the ACTIVE input, bracket tokens in UI strings
## ("[A]", "[LB]", "[D-Pad Up]" ...) are drawn as the matching button glyph (Xbox-style for Xbox / Steam Deck /
## Steam Controller / generic pads, PlayStation or Nintendo glyphs when such a pad is detected) instead of text.
## Tokens without a glyph in the active family (e.g. Xbox "Menu"/"View") stay as text, so nothing is ever blank.
## Art: "Input Prompts" by JulioCacko (CC0, see assets/glyphs/README.md). All drawing goes through UITheme.

const DIR := "res://assets/glyphs/"
const INDEX_PATH := "res://assets/glyphs/index.json"

static var enabled := false          # true only while the active input scheme is "gamepad"
static var family := "xbox"          # xbox | ps5 | ps4 | switch
static var _index: Dictionary = {}
static var _loaded := false
static var _raw: Dictionary = {}     # "family/file" -> Image
static var _cache: Dictionary = {}   # "family/token/px" -> ImageTexture
static var _rx: RegEx


static func _load_index() -> void:
	if _loaded:
		return
	_loaded = true
	if FileAccess.file_exists(INDEX_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
		if parsed is Dictionary:
			_index = parsed
	_rx = RegEx.new()
	_rx.compile("\\[([A-Za-z0-9][A-Za-z0-9 \\-]*)\\]")


## Called every frame by GameInput: pad_active = active scheme is gamepad, joy_name = the active pad's name.
static func sync(pad_active: bool, joy_name: String) -> void:
	enabled = pad_active
	family = family_for(joy_name)


static func family_for(joy_name: String) -> String:
	var n := joy_name.to_lower()
	if n.contains("dualsense") or n.contains("ps5"):
		return "ps5"
	if n.contains("dualshock") or n.contains("ps4") or n.contains("playstation") or n.contains("sony") or n.contains("ps3"):
		return "ps4"
	if n.contains("nintendo") or n.contains("switch") or n.contains("pro controller") or n.contains("joy-con"):
		return "switch"
	return "xbox"   # Xbox, XInput, Steam Deck, Steam Controller (Steam Input presents an Xbox-style pad)


static func has_token(token: String, fam: String = "") -> bool:
	_load_index()
	var f: Dictionary = _index.get(family if fam == "" else fam, {})
	return f.has(token)


## Splits `s` into [{"text": "..."} | {"glyph": "A"}] segments. Returns [] when glyph drawing is off or no token applies.
static func segments(s: String) -> Array:
	if not enabled or not s.contains("["):
		return []
	_load_index()
	var out: Array = []
	var pos := 0
	var any := false
	for m in _rx.search_all(s):
		var tok: String = m.get_string(1)
		if m.get_start() > pos:
			out.append({"text": s.substr(pos, m.get_start() - pos)})
		if has_token(tok):
			out.append({"glyph": tok})
			any = true
		else:
			out.append({"text": tok})     # no glyph in this family (e.g. Menu/View on Xbox): plain word
		pos = m.get_end()
	if not any:
		return []
	if pos < s.length():
		out.append({"text": s.substr(pos)})
	return out


## Glyph square size for a given font size.
static func glyph_px(font_size: int) -> int:
	return int(round(font_size * 1.35))


## Glyph texture scaled (once, cached) to px x px so small sizes stay crisp with nearest filtering.
static func texture(token: String, px: int) -> Texture2D:
	_load_index()
	var key := "%s/%s/%d" % [family, token, px]
	if _cache.has(key):
		return _cache[key]
	var file: String = _index.get(family, {}).get(token, "")
	if file == "":
		return null
	var raw_key := family + "/" + file
	if not _raw.has(raw_key):
		var src: Texture2D = load(DIR + file)   # imported resource: works inside exported packs on every platform
		var img: Image = src.get_image() if src else null
		if img == null:
			return null
		if img.is_compressed():
			img.decompress()
		_raw[raw_key] = img
	var scaled: Image = (_raw[raw_key] as Image).duplicate()
	scaled.resize(px, px, Image.INTERPOLATE_LANCZOS)
	var t := ImageTexture.create_from_image(scaled)
	_cache[key] = t
	return t
