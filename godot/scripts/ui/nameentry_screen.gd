extends UIScreen
## New-subject name entry with an on-screen keyboard (drawNameEntry / handleName*).
## Works with physical typing, d-pad/stick + A, and tap/click on the keys.

const ROWS := [
	["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"],
	["K", "L", "M", "N", "O", "P", "Q", "R", "S", "T"],
	["U", "V", "W", "X", "Y", "Z", "0", "1", "2", "3"],
	["4", "5", "6", "7", "8", "9", "-", "_", "DEL", "OK"],
]
const MAX_LEN := 16

var row := 0
var col := 0
var text := ""
var _key_rects := {}          # Vector2i(row, col) -> Rect2
var _press_flash := {}        # Vector2i -> seconds


func _on_open(_arg) -> void:
	row = 0
	col = 0
	text = ""
	_press_flash.clear()
	ui.input.text_entry = true


func close() -> void:
	super.close()
	if ui and ui.input:
		ui.input.text_entry = false


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed:
		return
	var k: InputEventKey = event
	if k.physical_keycode == KEY_BACKSPACE:
		text = text.substr(0, text.length() - 1)
		get_viewport().set_input_as_handled()
		return
	if k.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		return
	if k.unicode > 0 and not k.echo:
		var ch := char(k.unicode).to_upper()
		if ch.length() == 1 and (ch >= "A" and ch <= "Z" or ch >= "0" and ch <= "9" or ch in ["-", " ", "_"]):
			_add(ch)
			var pos := _find_key(ch)
			if pos.x >= 0:
				_press_flash[pos] = 0.15


func _find_key(ch: String) -> Vector2i:
	for r in ROWS.size():
		for c in ROWS[r].size():
			if ROWS[r][c] == ch:
				return Vector2i(r, c)
	return Vector2i(-1, -1)


func _add(ch: String) -> void:
	if text.length() < MAX_LEN:
		text += ch


func _press_key(r: int, c: int) -> void:
	var ch: String = ROWS[r][c]
	_press_flash[Vector2i(r, c)] = 0.18
	match ch:
		"OK":
			_finish()
		"DEL":
			text = text.substr(0, text.length() - 1)
		_:
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


func handle_input(inp: GameInput, _d: float) -> void:
	if inp.just("ui_up"):
		row = posmod(row - 1, ROWS.size())
		col = mini(col, ROWS[row].size() - 1)
	if inp.just("ui_down"):
		row = posmod(row + 1, ROWS.size())
		col = mini(col, ROWS[row].size() - 1)
	if inp.just("ui_left"):
		col = posmod(col - 1, ROWS[row].size())
	if inp.just("ui_right"):
		col = posmod(col + 1, ROWS[row].size())
	if inp.just("ui_accept"):
		_press_key(row, col)
	if inp.just("pad_start"):
		_finish()
	if inp.just("pad_b"):
		if text.length() > 0:
			text = text.substr(0, text.length() - 1)
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

	var key_w := 46.0 if touch else 42.0
	var key_h := 42.0 if touch else 38.0
	var pad := 6.0
	var kb_w := 10 * (key_w + pad) - pad
	var kb_h := 4 * (key_h + pad) - pad
	var content_h := 190.0 + kb_h + 50.0
	var y0 := maxf(46.0, floorf((h - content_h) * 0.5))

	UITheme.head(self, "ASYNC RESEARCH TERMINAL v4.31", 0, y0, 22, Color(0.1, 0.7, 0.1), HORIZONTAL_ALIGNMENT_CENTER, w)
	UITheme.line_sep(self, cx - 240, cx + 240, y0 + 32, Color(0, 0.4, 0, 0.8))
	UITheme.head(self, "> NEW SUBJECT FILE", 0, y0 + 46, 22, Color(0.1, 0.8, 0.1), HORIZONTAL_ALIGNMENT_CENTER, w)
	UITheme.head(self, "> ENTER SUBJECT NAME TO PROCEED", 0, y0 + 74, 22, Color(0.1, 0.8, 0.1), HORIZONTAL_ALIGNMENT_CENTER, w)

	var box := Rect2(cx - 190, y0 + 118, 380, 44)
	UITheme.panel(self, box, Color(0, 0.2, 0, 0.5), Color(0.1, 0.7, 0.1), 5, 1)
	var cursor := "_" if sin(t * 4.0) > 0.0 else ""
	UITheme.head(self, text + cursor, box.position.x + 12, box.position.y + 8, 24, Color(0.2, 1, 0.2), HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 24)
	UITheme.text(self, "%d/%d" % [text.length(), MAX_LEN], box.end.x - 60, box.position.y + 14, 12, Color(0, 0.55, 0), HORIZONTAL_ALIGNMENT_RIGHT, 52)

	var kx0 := cx - kb_w * 0.5
	var ky0 := y0 + 180.0
	_key_rects.clear()
	for r in ROWS.size():
		for c in ROWS[r].size():
			var rect := Rect2(kx0 + c * (key_w + pad), ky0 + r * (key_h + pad), key_w, key_h)
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
			var label: String = ROWS[r][c]
			var fs := 14 if label.length() > 1 else 20
			var colr := Color(0.9, 1, 0.9) if sel else Color(0.1, 0.75, 0.1, a)
			UITheme.head(self, label, rect.position.x, rect.position.y + (key_h - UITheme.text_h(fs, UITheme.title_font())) * 0.5, fs, colr,
				HORIZONTAL_ALIGNMENT_CENTER, key_w)
	var hint := "Type or pick letters, then select OK"
	if ui.input.active_mode() == "gamepad":
		hint = "D-PAD + A to type    B delete    START finish"
	UITheme.text(self, hint, 0, ky0 + kb_h + 22, 13, Color(0, 0.5, 0, 0.8), HORIZONTAL_ALIGNMENT_CENTER, w)
	UITheme.vignette(self, size, 0.6)
	var fade_in := 1.0 - clampf(age / 0.3, 0.0, 1.0)
	if fade_in > 0.0:
		fill(Color(0, 0, 0, fade_in * 0.6))
