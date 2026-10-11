extends UIScreen
## "How to Play": paged reference for every mechanic (TutorialData.PAGES). Reachable from the title, pause and
## options menus. Wording follows the active control scheme (keyboard / gamepad / touch); UP/DOWN (or tapping the
## scheme chip) previews the other schemes. LEFT/RIGHT (or swipe / tap the arrows or tabs) change page.

const MODE_NAMES := {"keyboard": "KEYBOARD + MOUSE", "gamepad": "CONTROLLER", "touch": "TOUCH"}

var return_to := "title"
var page := 0
var view_mode := ""
var _tab_rects: Array = []
var _prev_rect := Rect2()
var _next_rect := Rect2()
var _back_rect := Rect2()
var _chip_rect := Rect2()
var _down_x := -1.0


func _on_open(arg) -> void:
	return_to = arg if arg is String else "title"
	page = 0
	view_mode = ""
	input_delay = 0.2


## Schemes the player can flip through. A controller player only ever sees controller wording.
func _modes() -> Array:
	if ui.input.active_mode() == "gamepad":
		return ["gamepad"]
	return ["keyboard", "gamepad", "touch"]


func _mode() -> String:
	return view_mode if view_mode != "" else ui.input.active_mode()


func _count() -> int:
	return TutorialData.PAGES.size() + 1      # + the live controls reference page


func _go(d: int) -> void:
	page = posmod(page + d, _count())


func _back() -> void:
	ui.show_screen(return_to)


func handle_input(inp: GameInput, _d: float) -> void:
	if inp.just("ui_left"):
		_go(-1)
	if inp.just("ui_right") or inp.just("ui_accept"):
		_go(1)
	if (inp.just("ui_up") or inp.just("ui_down")) and _modes().size() > 1:
		var i := _modes().find(_mode())
		view_mode = _modes()[posmod(i + (1 if inp.just("ui_down") else -1), _modes().size())]
	if inp.just("ui_back") or inp.just("pause"):
		_back()


func on_pointer_down(p: Vector2) -> void:
	_down_x = p.x
	if _back_rect.has_point(p):
		_back()
		_down_x = -1.0
	elif _prev_rect.has_point(p):
		_go(-1)
		_down_x = -1.0
	elif _next_rect.has_point(p):
		_go(1)
		_down_x = -1.0
	elif _chip_rect.has_point(p) and _modes().size() > 1:
		var i := _modes().find(_mode())
		view_mode = _modes()[posmod(i + 1, _modes().size())]
		_down_x = -1.0
	else:
		for i in _tab_rects.size():
			if _tab_rects[i].has_point(p):
				page = i
				_down_x = -1.0
				return


func on_pointer_up(p: Vector2) -> void:
	if _down_x >= 0.0 and absf(p.x - _down_x) > 90.0:
		_go(-1 if p.x > _down_x else 1)
	_down_x = -1.0


func _visible_lines(lines: Array, m: String) -> Array:
	var out: Array = []
	for l in lines:
		var s: String = l
		var only := ""
		for pair in [["[kb] ", "keyboard"], ["[pad] ", "gamepad"], ["[touch] ", "touch"]]:
			if s.begins_with(pair[0]):
				only = pair[1]
				s = s.substr(pair[0].length())
		if only != "" and only != m:
			continue
		out.append(ui.input.fill(s.replace("{day_minutes}", _day_text()), m))
	return out


func _day_text() -> String:
	var secs: float = ui.game.day_seconds if ui.game else 300.0
	var mins := secs / 60.0
	return "%d minutes" % int(mins) if absf(mins - roundf(mins)) < 0.01 else "%.1f minutes" % mins


func _draw() -> void:
	var w := size.x
	var h := size.y
	fill(Color(0.012, 0.01, 0.006, 0.97))
	noise(160, Color(0.12, 0.1, 0.04))
	var m := _mode()
	var n := _count()
	var a := clampf(age / 0.25, 0.0, 1.0)
	var title: String = "CONTROLS" if page >= TutorialData.PAGES.size() else TutorialData.PAGES[page].title
	UITheme.head(self, "HOW TO PLAY", 0, 14, 34, Color(0.9, 0.8, 0.2, a), HORIZONTAL_ALIGNMENT_CENTER, w)
	# page tabs
	_tab_rects.clear()
	var tab_w := minf(150.0, (w - 40.0) / n)
	var tx := (w - tab_w * n) * 0.5
	for i in n:
		var r := Rect2(tx + i * tab_w, 58, tab_w - 4, 8)
		_tab_rects.append(Rect2(r.position.x, 50, r.size.x, 24))
		var on := i == page
		UITheme.panel(self, r, Color(1, 0.9, 0.3, 0.9) if on else Color(0.35, 0.32, 0.18, 0.7), Color(0, 0, 0, 0), 3)
	UITheme.head(self, "%d/%d  %s" % [page + 1, n, title], 0, 74, 24, Color(1, 0.95, 0.6, a), HORIZONTAL_ALIGNMENT_CENTER, w)
	# scheme chip
	var chip := "SHOWING: %s" % MODE_NAMES[m]
	var cwid := UITheme.text_w(chip, 13) + 24.0
	_chip_rect = Rect2(w - cwid - 16.0, 18, cwid, 26)
	UITheme.panel(self, _chip_rect, Color(0.1, 0.09, 0.05, 0.9), Color(0.9, 0.8, 0.2, 0.5), 5, 1)
	UITheme.text(self, chip, _chip_rect.position.x, _chip_rect.position.y + 5, 13, Color(0.95, 0.9, 0.6), HORIZONTAL_ALIGNMENT_CENTER, cwid)

	# body panel
	var pr := Rect2(36, 112, w - 72, h - 112 - 66)
	UITheme.panel(self, pr, Color(0.03, 0.026, 0.014, 0.92), Color(0.9, 0.8, 0.2, 0.4), 8, 1)
	var inner := Rect2(pr.position + Vector2(24, 16), pr.size - Vector2(48, 32))
	if page >= TutorialData.PAGES.size():
		_draw_controls(inner, m)
	else:
		_draw_page(inner, _visible_lines(TutorialData.PAGES[page].lines, m))

	# footer navigation
	var by := h - 52.0
	_back_rect = Rect2(36, by, 150, 36)
	button_rect(_back_rect, "[ BACK ]", _back_rect.has_point(pointer), 18)
	_prev_rect = Rect2(w - 36 - 310, by, 150, 36)
	_next_rect = Rect2(w - 36 - 150, by, 150, 36)
	button_rect(_prev_rect, "< PREV", _prev_rect.has_point(pointer), 18)
	button_rect(_next_rect, "NEXT >", _next_rect.has_point(pointer), 18)
	var hint: String = ui.input.hint("LEFT/RIGHT page    UP/DOWN other controls    ESC back", "D-Pad Left/Right page    A next    B back",
		"SWIPE or tap arrows    tap the chip for other controls")
	var hx := 36.0 + 150.0 + 14.0
	var hw := _prev_rect.position.x - 14.0 - hx
	UITheme.text(self, hint, hx, by + 9, UITheme.fit(hint, 13, hw), Color(0.7, 0.66, 0.46, 0.95), HORIZONTAL_ALIGNMENT_CENTER, hw)
	UITheme.scanlines(self, size, Color(0, 0, 0, 0.1), 3.0)
	UITheme.vignette(self, size, 0.4)


## Lays the wrapped lines out, shrinking the font until everything fits the panel.
func _draw_page(r: Rect2, lines: Array) -> void:
	var body := UITheme.body_font()
	var fs := 19
	var gap := 7.0
	var total := 0.0
	while fs >= 12:
		total = 0.0
		for l in lines:
			total += _line_h(body, l, r.size.x, fs) + gap
		if total - gap <= r.size.y:
			break
		fs -= 1
	var y := r.position.y + maxf(0.0, (r.size.y - (total - gap)) * 0.0)
	for l in lines:
		var s: String = l
		var lh := _line_h(body, s, r.size.x, fs)
		if s.begins_with("## "):
			y += 3.0
			UITheme.head(self, s.substr(3), r.position.x, y, fs + 2, UITheme.GOLD_BRIGHT)
		elif s.begins_with("- "):
			draw_circle(Vector2(r.position.x + 5, y + fs * 0.62), 2.6, Color(0.9, 0.8, 0.2))
			UITheme.wrapped(self, s.substr(2), r.position.x + 18, y, r.size.x - 18, fs, Color(0.85, 0.85, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
		else:
			UITheme.wrapped(self, s, r.position.x, y, r.size.x, fs, Color(0.85, 0.85, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
		y += lh + gap


func _line_h(body: Font, s: String, width: float, fs: int) -> float:
	if s.begins_with("## "):
		return body.get_height(fs + 2) + 3.0
	if s.begins_with("- "):
		return body.get_multiline_string_size(s.substr(2), HORIZONTAL_ALIGNMENT_LEFT, width - 18, fs).y
	return body.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, width, fs).y


func _draw_controls(r: Rect2, m: String) -> void:
	var list: Array = ui.input.controls_list(m)
	var cols := 2 if list.size() > 11 else 1
	var rows := ceili(float(list.size()) / cols)
	var row_h := minf(30.0, (r.size.y - 30.0) / maxf(rows, 1))        # leave room for the note under the table
	var fs := int(clampf(row_h * 0.6, 12, 17))
	var cw := r.size.x / cols
	for i in list.size():
		var col := i / rows
		var row := i % rows
		var x := r.position.x + col * cw
		var y := r.position.y + row * row_h
		UITheme.text(self, list[i][0], x, y, fs, Color(1, 0.9, 0.3), HORIZONTAL_ALIGNMENT_RIGHT, cw * 0.30)
		var desc: String = list[i][1]
		UITheme.text(self, desc, x + cw * 0.30 + 14, y, UITheme.fit(desc, fs, cw * 0.70 - 26), Color(0.82, 0.82, 0.82), HORIZONTAL_ALIGNMENT_LEFT, cw * 0.70 - 26)
	var note: String = ui.input.hint("Rebind keys and buttons in OPTIONS > CONTROLS. The game auto-detects keyboard, controller or touch.",
		"Rebind buttons in OPTIONS > CONTROLS. Back grips (L4 / L5 / R4 / R5) are quick-use shortcuts.")
	UITheme.text(self, note, r.position.x, r.end.y - 22, 13, Color(0.7, 0.68, 0.5))
