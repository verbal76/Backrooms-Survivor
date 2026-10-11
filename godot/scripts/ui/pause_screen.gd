extends UIScreen
## Pause menu (drawPauseMenu): run summary + volume/brightness/headlamp sliders, aim assist, resume, options, quit.

var menu := MenuList.new()


func _on_bound() -> void:
	var o: GameOptions = ui.options
	menu.row_h = 34.0
	menu.add_slider("Music", func(): return o.music_volume, func(v): o.music_volume = v)
	menu.add_slider("Enemy Sounds", func(): return o.sfx_volume, func(v): o.sfx_volume = v)
	menu.add_slider("Brightness", func(): return o.brightness, func(v): o.brightness = v)
	menu.add_slider("Headlamp", func(): return o.headlamp_brightness, func(v): o.headlamp_brightness = v, 0.1, 1.0)
	var aim := menu.add_choice("Aim Assist", _aim_text, _toggle_aim, _aim_color)
	aim["enabled"] = func(): return ui.difficulty < 3
	menu.add_button("[ RESUME ]", _resume)
	menu.add_button("[ HOW TO PLAY ]", func(): ui.show_screen("howto", "pause"))
	menu.add_button("[ OPTIONS ]", func(): ui.show_screen("options", "pause"))
	menu.add_button("[ QUIT TO MENU ]", func(): ui.back_to_title(), Color(1, 0.4, 0.3))


func _aim_text() -> String:
	return "LOCKED" if ui.difficulty >= 3 else ("ON" if ui.options.aim_assist else "OFF")


func _aim_color() -> Color:
	if ui.difficulty >= 3:
		return Color(0.6, 0.6, 0.6)
	return Color(0.3, 1, 0.3) if ui.options.aim_assist else Color(1, 0.3, 0.3)


func _toggle_aim(_d: int) -> void:
	if ui.difficulty < 3:
		ui.options.aim_assist = not ui.options.aim_assist


func _resume() -> void:
	ui.options.save()
	ui.game.set_state("playing")


func _on_open(_arg) -> void:
	menu.sel = 5
	menu.enter_t = 0.0
	menu.hl_y = -1.0
	menu.pop.clear()


func handle_input(inp: GameInput, _d: float) -> void:
	if inp.just("pause") or inp.just("ui_back"):
		_resume()
		return
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
		ui.show_screen("options", "pause")


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
	var a := clampf(age / 0.2, 0.0, 1.0)
	fill(Color(0, 0, 0, 0.86 * a))
	var g = ui.game
	var total := 80.0 + menu.total_height()
	var top := floorf((h - total) * 0.5)
	UITheme.head(self, "PAUSED", 0, top - (1.0 - a) * 16, 40, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, w)
	var line := "Day %d  |  %s  |  Kills %d  |  Streak %d  |  %s" % [g.day, UITheme.fmt_time(g.run_time), g.kills, g.player.current_streak,
		UITheme.DIFF_NAMES[ui.difficulty - 1]]
	UITheme.text(self, line, 0, top + 48, 16, Color(0.9, 0.8, 0.2, a), HORIZONTAL_ALIGNMENT_CENTER, w)
	menu.draw(self, w * 0.5, top + 80.0, dt, ui.clock)
	UITheme.scanlines(self, size, Color(0, 0, 0, 0.12), 3.0)
	UITheme.vignette(self, size, 0.5)
