extends UIScreen
## Options menu (options.lua): volumes, brightness, headlamp, controller, controls viewer, window.

var menu := MenuList.new()
var return_to := "title"
var showing_controls := false
var _back_rect := Rect2()


func _on_bound() -> void:
	var o: GameOptions = ui.options
	menu.row_h = 40.0
	menu.add_slider("Music Volume", func(): return o.music_volume, func(v): o.music_volume = v)
	menu.add_slider("SFX Volume", func(): return o.sfx_volume, func(v): o.sfx_volume = v)
	menu.add_slider("Brightness", func(): return o.brightness, func(v): o.brightness = v)
	menu.add_slider("Headlamp", func(): return o.headlamp_brightness, func(v): o.headlamp_brightness = v, 0.1, 1.0)
	menu.add_choice("Controller", func(): return String(o.get_control_mode()).to_upper(), _cycle_control)
	menu.add_button("[ VIEW CONTROLS ]", func(): showing_controls = true)
	if not OS.has_feature("mobile"):
		menu.add_choice("Resolution", func(): return "%dx%d" % [GameOptions.RESOLUTIONS[o.res_index].x, GameOptions.RESOLUTIONS[o.res_index].y], _cycle_res)
		menu.add_toggle("Fullscreen", func(): return o.fullscreen, _toggle_fullscreen)
	menu.add_button("[ BACK ]", _back)


func _cycle_control(d: int) -> void:
	var o: GameOptions = ui.options
	o.control_mode = posmod(o.control_mode + d, GameOptions.CONTROL_MODES.size())


func _cycle_res(d: int) -> void:
	var o: GameOptions = ui.options
	o.res_index = posmod(o.res_index + d, GameOptions.RESOLUTIONS.size())
	o.apply_window()


func _toggle_fullscreen(_d: int) -> void:
	var o: GameOptions = ui.options
	o.fullscreen = not o.fullscreen
	o.apply_window()


func _back() -> void:
	ui.options.save()
	ui.show_screen(return_to)


func _on_open(arg) -> void:
	return_to = arg if arg is String else "title"
	showing_controls = false
	menu.enter_t = 0.0
	menu.hl_y = -1.0
	menu.sel = 0


func handle_input(inp: GameInput, _d: float) -> void:
	if showing_controls:
		if inp.just("ui_back") or inp.just("ui_accept") or inp.just("pause"):
			showing_controls = false
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
	if inp.just("ui_back") or inp.just("pause"):
		_back()


func on_pointer_move(p: Vector2) -> void:
	if not showing_controls:
		menu.pointer_move(p)


func on_pointer_down(p: Vector2) -> void:
	if showing_controls:
		showing_controls = false
		return
	menu.pointer_down(p)


func on_pointer_drag(p: Vector2) -> void:
	menu.pointer_drag(p)


func on_pointer_up(_p: Vector2) -> void:
	menu.pointer_up()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if return_to == "pause":
		fill(Color(0, 0, 0, 0.9))
	else:
		fill(Color(0.01, 0.008, 0.004, 0.96))
		noise(200, Color(0.12, 0.1, 0.04))
	if showing_controls:
		_draw_controls(w, h)
	else:
		var total := menu.total_height()
		var top := floorf((h - total) * 0.5) + 10.0
		var a := clampf(age / 0.25, 0.0, 1.0)
		UITheme.head(self, "OPTIONS", 0, top - 70 - (1.0 - a) * 12, 40, Color(0.9, 0.8, 0.2, a), HORIZONTAL_ALIGNMENT_CENTER, w)
		menu.draw(self, w * 0.5, top, dt, ui.clock)
		UITheme.text(self, "LEFT/RIGHT adjust    ESC back", 0, h - 26, 13, Color(0.45, 0.42, 0.3, 0.8), HORIZONTAL_ALIGNMENT_CENTER, w)
	UITheme.vignette(self, size, 0.4)


func _draw_controls(w: float, h: float) -> void:
	var mode: String = ui.options.get_control_mode()
	if mode == "auto":
		mode = ui.input.active_mode()
	var scheme: Dictionary = GameInput.SCHEMES.get(mode, GameInput.SCHEMES.keyboard)
	var controls: Array = scheme.controls
	var row_h := 28.0
	var pw := minf(w - 80.0, 620.0)
	var ph := row_h * controls.size() + 150.0
	var r := Rect2((w - pw) * 0.5, maxf(20.0, (h - ph) * 0.5), pw, ph)
	UITheme.panel(self, r, Color(0.03, 0.025, 0.012, 0.96), Color(0.9, 0.8, 0.2, 0.55), 8, 2)
	UITheme.head(self, "CONTROLS: %s" % String(scheme.name).to_upper(), r.position.x, r.position.y + 14, 26, UITheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER, pw)
	UITheme.line_sep(self, r.position.x + 30, r.end.x - 30, r.position.y + 56)
	var y := r.position.y + 68.0
	var key_w := pw * 0.42
	for c in controls:
		UITheme.text(self, c[0], r.position.x + 16, y, 16, Color(1, 0.9, 0.3), HORIZONTAL_ALIGNMENT_RIGHT, key_w)
		UITheme.text(self, c[1], r.position.x + 16 + key_w + 20, y, 16, Color(0.8, 0.8, 0.8))
		y += row_h
	UITheme.line_sep(self, r.position.x + 30, r.end.x - 30, y + 6)
	UITheme.text(self, "ONE LIFE SURVIVAL - No saves, no loads", r.position.x, y + 16, 14, Color(0.7, 0.7, 0.7), HORIZONTAL_ALIGNMENT_CENTER, pw)
	UITheme.text(self, "1 Day = %d minutes - Survive as long as you can" % int(ui.game.DAY_SECONDS / 60.0), r.position.x, y + 36, 14, Color(0.7, 0.7, 0.7), HORIZONTAL_ALIGNMENT_CENTER, pw)
