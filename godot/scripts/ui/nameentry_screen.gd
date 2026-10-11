extends UIScreen
## New-subject name entry with an on-screen keyboard (drawNameEntry / handleName*).
## Fully usable with a controller alone: D-Pad / sticks move, A types, B deletes, X = space, Y = next page,
## Menu = done. Three pages (letters + digits, accented letters, symbols). Physical typing, tap/click and the
## system / Steam on-screen keyboard (Steam + X on the Deck, or the KBD key) type into the same box.

const Platform = preload("res://scripts/platform/platform.gd")
const PAGES := [
	{"name": "ABC", "rows": [
		["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"],
		["K", "L", "M", "N", "O", "P", "Q", "R", "S", "T"],
		["U", "V", "W", "X", "Y", "Z", "0", "1", "2", "3"],
		["4", "5", "6", "7", "8", "9", "-", "_", ".", "'"],
	]},
	{"name": "ÀÉÑ", "rows": [
		["À", "Á", "Â", "Ã", "Ä", "Å", "Æ", "Ç", "È", "É"],
		["Ê", "Ë", "Ì", "Í", "Î", "Ï", "Ñ", "Ò", "Ó", "Ô"],
		["Õ", "Ö", "Ø", "Œ", "Ù", "Ú", "Û", "Ü", "Ý", "Ÿ"],
		["ß", "Þ", "Ð", "Ł", "Š", "Ž", "Č", "Ř", "Ş", "Ğ"],
	]},
	{"name": "#&!", "rows": [
		["!", "?", ",", ":", ";", "&", "+", "=", "#", "@"],
		["(", ")", "[", "]", "/", "*", "%", "~", "^", "$"],
		["€", "£", "¥", "<", ">", "|", "\"", "`", "°", "¿"],
		["¡", "«", "»", "ª", "º", "·", "§", "¶", "†", "•"],
	]},
]
const ACTIONS := ["PAGE", "SPACE", "DEL", "KBD", "OK"]    # bottom row, same on every page
const MAX_LEN := 16
const EXTRA_CHARS := " -_.'!&+#@()"                     # typed on a physical keyboard besides letters / digits

var page := 0
var row := 0
var col := 0
var text := ""
var _key_rects := {}          # Vector2i(row, col) -> Rect2
var _press_flash := {}        # Vector2i -> seconds
var _vk_shown := false


func _rows() -> Array:
	return PAGES[page].rows


func _row_len(r: int) -> int:
	return ACTIONS.size() if r >= _rows().size() else _rows()[r].size()


func _label(r: int, c: int) -> String:
	return ACTIONS[c] if r >= _rows().size() else _rows()[r][c]


func _on_open(_arg) -> void:
	page = 0
	row = 0
	col = 0
	text = ""
	_press_flash.clear()
	ui.input.text_entry = true
	if ui.options.steam_keyboard:
		_show_system_keyboard()


func close() -> void:
	super.close()
	if ui and ui.input:
		ui.input.text_entry = false
	_hide_system_keyboard()


## Raises the platform's on-screen keyboard where the DisplayServer implements it (Android / iOS / web). On the
## Deck the Steam keyboard is opened by the player with Steam + X and types real key events into this box.
func _show_system_keyboard() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_show(text, Rect2(Vector2.ZERO, Vector2(size.x, 60)), DisplayServer.KEYBOARD_TYPE_DEFAULT, MAX_LEN, text.length(), text.length())
		_vk_shown = true


func _hide_system_keyboard() -> void:
	if _vk_shown and DisplayServer.get_name() != "headless":
		DisplayServer.virtual_keyboard_hide()
	_vk_shown = false


func _allowed(ch: String) -> bool:
	if ch.length() != 1:
		return false
	if ch in EXTRA_CHARS:
		return true
	if ch >= "0" and ch <= "9":
		return true
	return ch.to_lower() != ch.to_upper()           # any letter, accented ones included


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed:
		return
	var k: InputEventKey = event
	if k.physical_keycode == KEY_BACKSPACE:
		_backspace()
		get_viewport().set_input_as_handled()
		return
	if k.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		return
	if k.unicode > 32 and not k.echo:
		var ch := char(k.unicode).to_upper()
		if _allowed(ch):
			_add(ch)
			var pos := _find_key(ch)
			if pos.x >= 0:
				_press_flash[pos] = 0.15
	elif k.unicode == 32 and not k.echo:
		_add(" ")


func _find_key(ch: String) -> Vector2i:
	for r in _rows().size():
		for c in _rows()[r].size():
			if _rows()[r][c] == ch:
				return Vector2i(r, c)
	return Vector2i(-1, -1)


func _add(ch: String) -> void:
	if text.length() < MAX_LEN:
		text += ch


func _backspace() -> void:
	text = text.substr(0, text.length() - 1)


func _set_page(p: int) -> void:
	page = posmod(p, PAGES.size())
	if row < _rows().size():
		col = mini(col, _row_len(row) - 1)


func _press_key(r: int, c: int) -> void:
	var ch := _label(r, c)
	_press_flash[Vector2i(r, c)] = 0.18
	if r >= _rows().size():
		match ch:
			"PAGE":
				_set_page(page + 1)
			"SPACE":
				_add(" ")
			"DEL":
				_backspace()
			"KBD":
				_show_system_keyboard()
			"OK":
				_finish()
		return
	_add(ch)


func _finish() -> void:
	var nm := text.strip_edges()
	if nm == "":
		nm = "Subject"
	if ui.progression.add_character(nm):
		ui.progression.set_active(ui.progression.character_count() - 1)
		ui.player_name = nm
		ui.options.last_character = nm
		ui.options.save()
		ui.show_screen("title")
	else:
		ui.show_screen("charselect")


func _move_row(d: int) -> void:
	var n := _rows().size() + 1
	var old_len := _row_len(row)
	var nr := posmod(row + d, n)
	var new_len := _row_len(nr)
	col = clampi(int(floor((col + 0.5) * new_len / float(old_len))), 0, new_len - 1)
	row = nr


func handle_input(inp: GameInput, _d: float) -> void:
	if inp.just("pad_start"):
		_finish()                         # Menu = done
		return
	if inp.just("ui_up"):
		_move_row(-1)
	if inp.just("ui_down"):
		_move_row(1)
	if inp.just("ui_left"):
		col = posmod(col - 1, _row_len(row))
	if inp.just("ui_right"):
		col = posmod(col + 1, _row_len(row))
	if inp.just("ui_accept"):
		_press_key(row, col)
	if inp.just("pad_x"):
		_add(" ")
		_press_flash[Vector2i(_rows().size(), 1)] = 0.18
	if inp.just("pad_y"):
		_set_page(page + 1)
	if inp.just("pad_b"):
		if text.length() > 0:
			_backspace()
		else:
			ui.show_screen("charselect")
	elif inp.just("ui_back"):
		ui.show_screen("charselect")


func frame(delta: float) -> void:
	super.frame(delta)
	for k in _press_flash.keys():
		_press_flash[k] -= delta
		if _press_flash[k] <= 0.0:
			_press_flash.erase(k)


func on_pointer_move(p: Vector2) -> void:
	for k in _key_rects:
		if _key_rects[k].has_point(p):
			row = k.x
			col = k.y


func on_pointer_down(p: Vector2) -> void:
	for k in _key_rects:
		if _key_rects[k].has_point(p):
			row = k.x
			col = k.y
			_press_key(k.x, k.y)
			return
	if _box_rect.has_point(p):
		_show_system_keyboard()


var _box_rect := Rect2()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var cx := w * 0.5
	var t: float = ui.clock
	var touch: bool = ui.input.active_mode() == "touch"
	fill(Color(0, 0, 0))
	UITheme.scanlines(self, size, Color(0, 0.04, 0, 0.3), 2.0)
	UITheme.panel(self, Rect2(30, 30, w - 60, h - 60), Color(0, 0, 0, 0), Color(0, 0.2, 0, 0.45), 8, 2)
	UITheme.panel(self, Rect2(34, 34, w - 68, h - 68), Color(0, 0, 0, 0), Color(0, 0.14, 0, 0.3), 8, 1)

	var key_w := 48.0 if touch else 46.0
	var key_h := 44.0 if touch else 40.0
	var pad := 6.0
	var rows := _rows().size() + 1
	var kb_w := 10 * (key_w + pad) - pad
	var kb_h := rows * (key_h + pad) - pad
	var compact := h < 600.0
	var head_h := 128.0 if compact else 190.0
	var content_h := head_h + kb_h + 44.0
	var y0 := maxf(40.0, floorf((h - content_h) * 0.5))

	if not compact:
		UITheme.head(self, "ASYNC RESEARCH TERMINAL v4.31", 0, y0, 22, Color(0.1, 0.7, 0.1), HORIZONTAL_ALIGNMENT_CENTER, w)
		UITheme.line_sep(self, cx - 240, cx + 240, y0 + 32, Color(0, 0.4, 0, 0.8))
		UITheme.head(self, "> NEW SUBJECT FILE", 0, y0 + 46, 22, Color(0.1, 0.8, 0.1), HORIZONTAL_ALIGNMENT_CENTER, w)
		UITheme.head(self, "> ENTER SUBJECT NAME TO PROCEED", 0, y0 + 74, 22, Color(0.1, 0.8, 0.1), HORIZONTAL_ALIGNMENT_CENTER, w)
	else:
		UITheme.head(self, "> NEW SUBJECT FILE: ENTER NAME", 0, y0, 22, Color(0.1, 0.8, 0.1), HORIZONTAL_ALIGNMENT_CENTER, w)

	var box := Rect2(cx - 190, y0 + (118.0 if not compact else 36.0), 380, 44)
	_box_rect = box
	UITheme.panel(self, box, Color(0, 0.2, 0, 0.5), Color(0.1, 0.7, 0.1), 5, 1)
	var cursor := "_" if sin(t * 4.0) > 0.0 else ""
	var shown := text + cursor
	var plain := true
	for i in text.length():
		if text.unicode_at(i) > 127:
			plain = false
	if plain:
		UITheme.head(self, shown, box.position.x + 12, box.position.y + 8, 24, Color(0.2, 1, 0.2), HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 24)
	else:
		UITheme.text(self, shown, box.position.x + 12, box.position.y + 8, 26, Color(0.2, 1, 0.2), HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 24)
	UITheme.text(self, "%d/%d" % [text.length(), MAX_LEN], box.end.x - 60, box.position.y + 14, 12, Color(0, 0.7, 0), HORIZONTAL_ALIGNMENT_RIGHT, 52)

	var kx0 := cx - kb_w * 0.5
	var ky0 := y0 + head_h - (10.0 if not compact else 0.0)
	_key_rects.clear()
	for r in rows:
		var n := _row_len(r)
		var span := kb_w if r < rows - 1 else kb_w
		var kw := (span + pad) / n - pad
		for c in n:
			var rect := Rect2(kx0 + c * (kw + pad), ky0 + r * (key_h + pad), kw, key_h)
			var key := Vector2i(r, c)
			_key_rects[key] = rect
			var sel: bool = r == row and c == col
			var fl: float = _press_flash.get(key, 0.0)
			var a := clampf((age - (r * 10 + c) * 0.008) / 0.2, 0.0, 1.0)
			var rr := rect
			if fl > 0.0:
				rr = rect.grow(-3.0)
			if sel:
				UITheme.panel(self, rect.grow(2), Color(0.1, 0.7, 0.1, 0.55 + fl * 2.0), Color(0.2, 1, 0.2, a), 4, 1)
			else:
				UITheme.panel(self, rr, Color(0, 0.15, 0, 0.45 * a), Color(0.1, 0.6, 0.1, a), 4, 1)
			var label: String = _label(r, c)
			if label == "PAGE":
				label = PAGES[(page + 1) % PAGES.size()].name
			var colr := Color(0.9, 1, 0.9) if sel else Color(0.15, 0.85, 0.15, a)
			if label.length() > 1 or page > 0:       # words and accented glyphs use the plain face (the display font lacks them)
				var fs2 := 16 if label.length() > 1 else 22
				UITheme.text(self, label, rect.position.x, rect.position.y + (key_h - UITheme.text_h(fs2)) * 0.5, fs2, colr,
					HORIZONTAL_ALIGNMENT_CENTER, kw)
			else:
				UITheme.head(self, label, rect.position.x, rect.position.y + (key_h - UITheme.text_h(22, UITheme.title_font())) * 0.5, 22, colr,
					HORIZONTAL_ALIGNMENT_CENTER, kw)
	var hint: String = ui.input.hint("Type, or pick letters and select OK    Backspace deletes",
		"D-Pad move    A type    B delete    X space    Y page    Menu done", "Tap the keys, then OK")
	UITheme.text(self, hint, 0, ky0 + kb_h + 14, 13, Color(0, 0.65, 0, 0.9), HORIZONTAL_ALIGNMENT_CENTER, w)
	if ui.input.active_mode() == "gamepad" and Platform.is_deck_like():
		UITheme.text(self, "Steam + X opens the Steam keyboard", 0, ky0 + kb_h + 34, 13, Color(0, 0.55, 0, 0.8), HORIZONTAL_ALIGNMENT_CENTER, w)
	UITheme.vignette(self, size, 0.6)
	var fade_in := 1.0 - clampf(age / 0.3, 0.0, 1.0)
	if fade_in > 0.0:
		fill(Color(0, 0, 0, fade_in * 0.6))
