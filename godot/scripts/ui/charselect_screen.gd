extends UIScreen
## Save-slot ("subject file") select + per-difficulty leaderboard (drawCharSelect).

const ROW_H := 42.0
const LIST_W := 520.0

var sel := 0
var scroll := 0
var confirm_delete := false
var delete_idx := 0
var confirm_sel := 1           # 0 = YES, 1 = NO
var _rects: Array = []         # row rects (index = list index)
var _del_rects: Array = []
var _yes_rect := Rect2()
var _no_rect := Rect2()
var _visible_rows := 6


func _on_open(_arg) -> void:
	confirm_delete = false
	var count: int = ui.progression.character_count()
	var want: String = ui.options.last_character
	sel = count if count < Progression.MAX_CHARACTERS else maxi(0, count - 1)
	for i in count:
		if ui.progression.characters[i].name == want:
			sel = i
			break
	if count > 0 and want == "":
		sel = 0
	scroll = 0
	_clamp_scroll()


func _row_count() -> int:
	var count: int = ui.progression.character_count()
	return count + 1 if count < Progression.MAX_CHARACTERS else count


func _clamp_scroll() -> void:
	if sel < scroll:
		scroll = sel
	if sel >= scroll + _visible_rows:
		scroll = sel - _visible_rows + 1
	scroll = clampi(scroll, 0, maxi(0, _row_count() - _visible_rows))


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if confirm_delete:
		match event.physical_keycode:
			KEY_Y:
				_do_delete()
			KEY_N, KEY_BACKSPACE:
				confirm_delete = false
	else:
		if event.physical_keycode in [KEY_DELETE, KEY_X]:
			_ask_delete()


func handle_input(inp: GameInput, _d: float) -> void:
	if confirm_delete:
		if inp.just("ui_left") or inp.just("ui_right"):
			confirm_sel = 1 - confirm_sel
		if inp.just("ui_accept"):
			if confirm_sel == 0:
				_do_delete()
			else:
				confirm_delete = false
		elif inp.just("ui_back"):
			confirm_delete = false
		return
	if inp.just("ui_up"):
		sel = posmod(sel - 1, _row_count())
		_clamp_scroll()
	if inp.just("ui_down"):
		sel = posmod(sel + 1, _row_count())
		_clamp_scroll()
	if inp.just("ui_accept"):
		_activate(sel)
	elif inp.just("use_bandage") and inp.active_mode() == "gamepad":
		_ask_delete()
	elif inp.just("ui_back") and ui.progression.active_idx >= 0:
		ui.show_screen("title")


func _activate(i: int) -> void:
	var count: int = ui.progression.character_count()
	if i < count:
		ui.progression.set_active(i)
		ui.player_name = ui.progression.active_name()
		ui.options.last_character = ui.player_name
		ui.options.save()
		ui.show_screen("title")
	elif count < Progression.MAX_CHARACTERS:
		ui.player_name = ""
		ui.show_screen("nameentry")


func _ask_delete() -> void:
	if sel < ui.progression.character_count():
		delete_idx = sel
		confirm_delete = true
		confirm_sel = 1


func _do_delete() -> void:
	ui.progression.delete_character(delete_idx)
	confirm_delete = false
	sel = clampi(sel, 0, maxi(0, _row_count() - 1))
	if ui.progression.active_idx < 0:
		ui.player_name = ""
	_clamp_scroll()


func on_pointer_move(p: Vector2) -> void:
	if confirm_delete:
		if _yes_rect.has_point(p):
			confirm_sel = 0
		elif _no_rect.has_point(p):
			confirm_sel = 1
		return
	for i in _rects.size():
		if _rects[i].has_point(p):
			sel = scroll + i


func on_pointer_down(p: Vector2) -> void:
	if confirm_delete:
		if _yes_rect.has_point(p):
			_do_delete()
		elif _no_rect.has_point(p):
			confirm_delete = false
		return
	for i in _del_rects.size():
		if _del_rects[i].has_point(p):
			sel = scroll + i
			_ask_delete()
			return
	for i in _rects.size():
		if _rects[i].has_point(p):
			sel = scroll + i
			_activate(sel)
			return


func _draw() -> void:
	var w := size.x
	var h := size.y
	var cx := w * 0.5
	var t: float = ui.clock
	fill(Color(0, 0, 0))
	UITheme.scanlines(self, size, Color(0, 0.04, 0, 0.3), 2.0)
	UITheme.panel(self, Rect2(30, 30, w - 60, h - 60), Color(0, 0, 0, 0), Color(0, 0.2, 0, 0.45), 8, 2)
	UITheme.panel(self, Rect2(34, 34, w - 68, h - 68), Color(0, 0, 0, 0), Color(0, 0.14, 0, 0.3), 8, 1)

	var count: int = ui.progression.character_count()
	var base_y := 46.0
	UITheme.head(self, "ASYNC RESEARCH TERMINAL v4.31", 0, base_y, 22, Color(0.1, 0.7, 0.1), HORIZONTAL_ALIGNMENT_CENTER, w)
	UITheme.line_sep(self, cx - 240, cx + 240, base_y + 32, Color(0, 0.4, 0, 0.8))
	UITheme.head(self, "> SELECT SUBJECT FILE", 0, base_y + 42, 22, Color(0.1, 0.8, 0.1), HORIZONTAL_ALIGNMENT_CENTER, w)
	UITheme.text(self, "%d/%d Subject Files on Record" % [count, Progression.MAX_CHARACTERS], 0, base_y + 72, 14,
		Color(0, 0.55, 0), HORIZONTAL_ALIGNMENT_CENTER, w)

	var list_y := base_y + 100.0
	# space left after list for the leaderboard (header + 5 rows) and footer
	var lb_h := 16.0 + 18.0 + 5 * 17.0 + 8.0
	_visible_rows = clampi(int((h - 60.0 - list_y - lb_h - 34.0) / ROW_H), 3, 11)
	_clamp_scroll()

	_rects.clear()
	_del_rects.clear()
	var rows := _row_count()
	var shown := mini(_visible_rows, rows - scroll)
	for r in shown:
		var i := scroll + r
		var y := list_y + r * ROW_H
		var is_sel := i == sel
		var a := clampf((age - r * 0.04) / 0.2, 0.0, 1.0)
		var rect := Rect2(cx - LIST_W * 0.5, y - 2, LIST_W, ROW_H - 4)
		_rects.append(rect)
		if is_sel:
			var pulse := 0.5 + 0.5 * sin(t * 4.0)
			UITheme.panel(self, rect, Color(0.1, 0.5, 0.1, 0.30 + 0.1 * pulse), Color(0.1, 0.8, 0.1, 0.7), 4, 1)
		var col := Color(0.2, 1, 0.2, a) if is_sel else Color(0.1, 0.7, 0.1, a)
		if i < count:
			var sm: Dictionary = ui.progression.summary(i)
			var prefix := "> " if is_sel else "  "
			UITheme.head(self, prefix + String(sm.name).to_upper(), rect.position.x + 10, y + 6, 20, col, HORIZONTAL_ALIGNMENT_LEFT, 230)
			var st := "Best Kills: %d  |  Best Streak: %d  |  Runs: %d" % [sm.bestKills, sm.bestStreak, sm.totalRuns]
			UITheme.text(self, st, rect.position.x + 240, y + 9, UITheme.fit(st, 13, LIST_W - 240 - 70), Color(0, 0.6, 0, a))
			var dr := Rect2(rect.end.x - 56, y + 2, 50, ROW_H - 12)
			_del_rects.append(dr)
			if is_sel or dr.has_point(pointer):
				button_rect(dr, "DEL", dr.has_point(pointer), 14, Color(1, 0.4, 0.3))
		else:
			_del_rects.append(Rect2())
			UITheme.head(self, ("> + NEW SUBJECT" if is_sel else "  + NEW SUBJECT"), rect.position.x + 10, y + 6, 20, col)
	if rows > _visible_rows:
		# scroll indicator
		var track := Rect2(cx + LIST_W * 0.5 + 10, list_y, 4, _visible_rows * ROW_H - 6)
		draw_rect(track, Color(0, 0.25, 0, 0.5))
		var th := track.size.y * float(_visible_rows) / rows
		draw_rect(Rect2(track.position.x, track.position.y + track.size.y * float(scroll) / rows, 4, th), Color(0.1, 0.8, 0.1))

	_draw_leaderboard(list_y + _visible_rows * ROW_H + 6.0)

	var hint := "UP/DOWN select    ENTER open    DEL delete"
	var m: String = ui.input.active_mode()
	if m == "gamepad":
		hint = "D-PAD select    A open    X delete"
	elif m == "touch":
		hint = "TAP a subject file to open"
	UITheme.text(self, hint, 0, h - 52, 12, Color(0, 0.45, 0, 0.8), HORIZONTAL_ALIGNMENT_CENTER, w)

	if confirm_delete:
		_draw_confirm(w, h)
	UITheme.vignette(self, size, 0.6)
	var fade_in := 1.0 - clampf(age / 0.3, 0.0, 1.0)
	if fade_in > 0.0:
		fill(Color(0, 0, 0, fade_in * 0.6))


func _draw_leaderboard(y0: float) -> void:
	var w := size.x
	var cx := w * 0.5
	var diff: int = ui.difficulty
	var rows := []
	for i in ui.progression.character_count():
		var sm: Dictionary = ui.progression.summary(i)
		rows.append({"idx": i, "name": sm.name, "bd": sm.bestDayByDiff, "runs": sm.totalRuns})
	rows.sort_custom(func(a, b):
		var ad: int = a.bd[diff - 1]
		var bd: int = b.bd[diff - 1]
		if ad == bd:
			return a.runs > b.runs
		return ad > bd)
	UITheme.text(self, "-- %s SAVES --" % String(UITheme.DIFF_NAMES[diff - 1]).to_upper(), 0, y0, 14, Color(0, 0.55, 0, 0.7), HORIZONTAL_ALIGNMENT_CENTER, w)
	var cols := [0.0, 28.0, 220.0, 290.0, 380.0, 500.0]
	var heads := ["#", "NAME", "EASY", "NORMAL", "GETTING WORSE", "HELL"]
	var left := cx - 320.0
	var y := y0 + 20.0
	for c in 6:
		UITheme.text(self, heads[c], left + cols[c], y, 12, Color(0, 0.5, 0, 0.8), HORIZONTAL_ALIGNMENT_LEFT, -1, null, false)
	y += 17.0
	for rank in mini(5, rows.size()):
		var r: Dictionary = rows[rank]
		var active: bool = r.idx == ui.progression.active_idx
		var col := Color(0.2, 0.95, 0.2) if active else Color(0, 0.6, 0, 0.85)
		var nm: String = r.name
		if nm.length() > 16:
			nm = nm.substr(0, 15) + "."
		UITheme.text(self, "%d." % (rank + 1), left, y, 13, col)
		UITheme.text(self, nm, left + cols[1], y, 13, col)
		for d in 4:
			UITheme.text(self, str(r.bd[d]), left + cols[2 + d], y, 13, col)
		y += 17.0


func _draw_confirm(w: float, h: float) -> void:
	fill(Color(0, 0, 0, 0.7))
	var bw := 460.0
	var bh := 190.0
	var r := Rect2((w - bw) * 0.5, (h - bh) * 0.5, bw, bh)
	UITheme.panel(self, r, Color(0.02, 0.0, 0.0, 0.95), Color(1, 0.3, 0.2, 0.85), 8, 2)
	var sm: Dictionary = ui.progression.summary(delete_idx)
	UITheme.head(self, "DELETE CHARACTER?", r.position.x, r.position.y + 14, 22, Color(1, 0.3, 0.2), HORIZONTAL_ALIGNMENT_CENTER, bw)
	UITheme.head(self, String(sm.get("name", "?")).to_upper(), r.position.x, r.position.y + 46, 22, UITheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER, bw)
	if not sm.is_empty():
		UITheme.text(self, "%d Runs  |  Best Day %d  |  Best Kills %d  |  %d Tokens" % [sm.totalRuns, sm.bestDay, sm.bestKills, sm.totalTokens],
			r.position.x, r.position.y + 78, 13, Color(0.6, 0.6, 0.6), HORIZONTAL_ALIGNMENT_CENTER, bw)
	UITheme.text(self, "This cannot be undone!", r.position.x, r.position.y + 100, 14, Color(1, 0.4, 0.3), HORIZONTAL_ALIGNMENT_CENTER, bw)
	_yes_rect = Rect2(r.position.x + 60, r.end.y - 52, 150, 36)
	_no_rect = Rect2(r.end.x - 210, r.end.y - 52, 150, 36)
	button_rect(_yes_rect, "YES (Y)", confirm_sel == 0, 18, Color(1, 0.35, 0.25))
	button_rect(_no_rect, "NO (N)", confirm_sel == 1, 18, Color(0.5, 1, 0.5))
