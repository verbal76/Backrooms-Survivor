extends UIScreen
## Title screen (drawTitle / handleTitleInput): difficulty, sliders, START, UPGRADES, CHARACTER, Options, EXIT.

var menu := MenuList.new()
var _blob: GradientTexture2D


func _on_bound() -> void:
	_blob = GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.35, 0.22))
	g.set_color(1, Color(1.0, 0.85, 0.35, 0.0))
	_blob.gradient = g
	_blob.fill = GradientTexture2D.FILL_RADIAL
	_blob.fill_from = Vector2(0.5, 0.5)
	_blob.fill_to = Vector2(1.0, 0.5)
	_blob.width = 256
	_blob.height = 256

	var o: GameOptions = ui.options
	menu.row_h = 36.0
	menu.add_choice("Difficulty", func(): return UITheme.DIFF_NAMES[ui.difficulty - 1],
		_change_difficulty, func(): return UITheme.DIFF_COLORS[ui.difficulty - 1])
	menu.add_slider("Brightness", func(): return o.brightness, func(v): o.brightness = v)
	menu.add_slider("Music", func(): return o.music_volume, func(v): o.music_volume = v)
	menu.add_slider("Enemy Sounds", func(): return o.sfx_volume, func(v): o.sfx_volume = v)
	menu.add_slider("Headlamp", func(): return o.headlamp_brightness, func(v): o.headlamp_brightness = v, 0.1, 1.0)
	var aim := menu.add_choice("Aim Assist", _aim_text, _toggle_aim, _aim_color)
	aim["enabled"] = func(): return ui.difficulty < 3
	menu.add_button("[ START GAME ]", func(): ui.start_game())
	var up := menu.add_button("", _open_shop)
	up["label_fn"] = func(): return "[ UPGRADES ]  (%d Tokens)" % ui.progression.profile(ui.difficulty).tokens
	var ch := menu.add_button("", func(): ui.show_screen("charselect"))
	ch["label_fn"] = func(): return "[ CHARACTER: %s ]" % ui.progression.active_name().to_upper()
	menu.add_button("[ OPTIONS ]", func(): ui.show_screen("options", "title"))
	menu.add_button("[ EXIT ]", func(): get_tree().quit(), Color(1, 0.4, 0.3))
	menu.sel = 6


func _change_difficulty(d: int) -> void:
	ui.difficulty = clampi(ui.difficulty + d, 1, 4)


func _aim_text() -> String:
	return "LOCKED" if ui.difficulty >= 3 else ("ON" if ui.options.aim_assist else "OFF")


func _aim_color() -> Color:
	if ui.difficulty >= 3:
		return Color(0.6, 0.6, 0.6)
	return Color(0.3, 1, 0.3) if ui.options.aim_assist else Color(1, 0.3, 0.3)


func _toggle_aim(_d: int) -> void:
	if ui.difficulty < 3:
		ui.options.aim_assist = not ui.options.aim_assist


func _open_shop() -> void:
	ui.shop_return = "title"
	ui.show_screen("shop")


func _on_open(_arg) -> void:
	menu.enter_t = 0.0
	menu.hl_y = -1.0
	menu.pop.clear()
	if menu.sel < 0 or menu.sel >= menu.items.size():
		menu.sel = 6


func handle_input(inp: GameInput, _d: float) -> void:
	if inp.just("ui_up"):
		menu.nav(-1)
	if inp.just("ui_down"):
		menu.nav(1)
	if inp.just("ui_left"):
		menu.adjust(-1)
	if inp.just("ui_right"):
		menu.adjust(1)
	if inp.just("ui_accept"):
		menu.activate()
	if inp.just("options"):
		ui.show_screen("options", "title")


func on_pointer_move(p: Vector2) -> void:
	menu.pointer_move(p)


func on_pointer_down(p: Vector2) -> void:
	menu.pointer_down(p)


func on_pointer_drag(p: Vector2) -> void:
	menu.pointer_drag(p)


func on_pointer_up(_p: Vector2) -> void:
	menu.pointer_up()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var t: float = ui.clock
	fill(Color(0.012, 0.01, 0.006))
	# drifting fluorescent light blobs
	var amb: float = ui.DIFF_AMBIENT[ui.difficulty - 1]
	var preview := clampf(amb + ui.options.brightness * 0.08, 0.0, 1.0)
	var darkness := 1.0 - minf(1.0, preview * 3.0)
	for i in 4:
		var bx := w * (0.2 + 0.2 * i) + sin(t * 0.13 + i * 2.1) * w * 0.08
		var by := h * (0.3 + 0.12 * (i % 2)) + cos(t * 0.11 + i) * h * 0.06
		var flick := 0.75 + 0.25 * sin(t * (1.3 + i * 0.37)) * (0.6 if fmod(t * 0.9 + i, 5.0) > 0.08 else 0.1)
		var r := 260.0 + 40.0 * sin(t * 0.3 + i)
		draw_texture_rect(_blob, Rect2(bx - r, by - r, r * 2, r * 2), false, Color(1, 1, 1, flick * (1.0 - darkness * 0.8)))
	noise(450, Color(0.15, 0.12, 0.05))
	if darkness > 0.02:
		fill(Color(0, 0, 0, darkness * 0.55))

	var s_alpha := clampf(age / 0.5, 0.0, 1.0)
	var item_n := menu.items.size()
	var title_h := 142.0
	var total := title_h + item_n * menu.row_h
	var top := maxf(8.0, floorf((h - total) * 0.5))
	var cx := w * 0.5

	# title with fluorescent flicker + chromatic fringe
	var flick_t := 1.0
	if fmod(t * 1.7, 9.0) < 0.06 or fmod(t * 0.77 + 3.0, 13.0) < 0.1:
		flick_t = 0.45
	var tsz := 64 if w >= 700 else 48
	var ty := top - (1.0 - s_alpha) * 18.0
	UITheme.head(self, "BACKROOMS SURVIVOR", cx - w * 0.5 + 3.0, ty, tsz, Color(1.0, 0.1, 0.1, 0.22 * flick_t * s_alpha), HORIZONTAL_ALIGNMENT_CENTER, w)
	UITheme.head(self, "BACKROOMS SURVIVOR", cx - w * 0.5 - 3.0, ty, tsz, Color(0.1, 0.9, 1.0, 0.18 * flick_t * s_alpha), HORIZONTAL_ALIGNMENT_CENTER, w)
	UITheme.head(self, "BACKROOMS SURVIVOR", 0, ty, tsz, Color(0.9, 0.8, 0.2, flick_t * s_alpha), HORIZONTAL_ALIGNMENT_CENTER, w)

	var name: String = ui.player_name
	var welcome := "Subject: %s  |  Status: STRANDED" % name if name != "" else "There is no saving. There is no loading. Only survival."
	UITheme.head(self, welcome, 0, top + 80, 22, Color(0.62, 0.56, 0.26, s_alpha), HORIZONTAL_ALIGNMENT_CENTER, w)
	if name != "":
		var st: Dictionary = ui.progression.profile_stats(ui.difficulty)
		if st.totalRuns > 0:
			var tstr: String = UITheme.fmt_time(st.bestTime) if st.bestTime > 0 else "--:--"
			var pb := "PB: Day %d  |  %d Kills  |  x%d Streak  |  %s  |  %d Runs" % [st.bestDay, st.bestKills, st.bestStreak, tstr, st.totalRuns]
			UITheme.text(self, pb, 0, top + 112, 14, Color(0.5, 0.5, 0.42, s_alpha), HORIZONTAL_ALIGNMENT_CENTER, w)

	menu.draw(self, cx, top + title_h, dt, t)

	var hint := "UP/DOWN select    LEFT/RIGHT adjust    ENTER confirm"
	var m: String = ui.input.active_mode() if ui.input else "keyboard"
	if m == "gamepad":
		hint = "D-PAD select    LEFT/RIGHT adjust    A confirm"
	elif m == "touch":
		hint = "TAP to select    DRAG sliders"
	UITheme.text(self, hint, 0, h - 26, 13, Color(0.45, 0.42, 0.3, 0.8), HORIZONTAL_ALIGNMENT_CENTER, w)
	UITheme.scanlines(self, size, Color(0, 0, 0, 0.12), 3.0)
	UITheme.vignette(self, size, 0.55)
