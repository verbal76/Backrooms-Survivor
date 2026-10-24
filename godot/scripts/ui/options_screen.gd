extends UIScreen
## Options (options.lua): volumes, brightness, headlamp, tips, window - plus two sub-pages:
##   CONTROLS: scheme (Auto / Keyboard + Mouse / Gamepad / Touch) and rebinding of every action for keyboard and
##             gamepad ("press a key / button" capture, conflicts swap, reset to defaults).
##   TOUCH CONTROLS: button size, opacity, left-handed mirror, haptics, with a live layout preview.

const Platform = preload("res://scripts/platform/platform.gd")

var menu := MenuList.new()
var display_menu := MenuList.new()
var pad_menu := MenuList.new()
var touch_menu := MenuList.new()
var return_to := "title"
var section := "main"                 # "main" | "display" | "gamepad" | "controls" | "touch"

# controls page
var device := "keyboard"              # which binding table is shown / edited
var csel := 0
var cscroll := 0
var _crows: Array = []                # row descriptors
var _crects: Array = []               # [index, Rect2] of the drawn rows
var _msg := ""
var _msg_t := 0.0
var _back_rect := Rect2()


func _on_bound() -> void:
	design_min = Vector2(640, 340)         # phone landscape at 2x: the page lays out in ~800 x 360
	var o: GameOptions = ui.options
	var pct := func(v: float) -> String: return "%d%%" % int(round(v * 100.0))
	menu.row_h = 38.0
	menu.add_slider("Music Volume", func(): return o.music_volume, func(v): o.music_volume = v)
	menu.add_slider("SFX Volume", func(): return o.sfx_volume, func(v): o.sfx_volume = v)
	menu.add_slider("Brightness", func(): return o.brightness, func(v): o.brightness = v)
	menu.add_slider("Headlamp", func(): return o.headlamp_brightness, func(v): o.headlamp_brightness = v, 0.1, 1.0)
	menu.add_toggle("Tips", func(): return o.tips_enabled, func(_d): o.tips_enabled = not o.tips_enabled)
	menu.add_button("[ DISPLAY & PERFORMANCE ]", func(): _open_section("display"))
	menu.add_button("[ CONTROLS ]", func(): _open_section("controls"))
	menu.add_button("[ CONTROLLER ]", func(): _open_section("gamepad"))
	if OS.has_feature("mobile"):
		menu.add_button("[ TOUCH CONTROLS ]", func(): _open_section("touch"))
	menu.add_button("[ HOW TO PLAY ]", func(): ui.show_screen("howto", return_to))
	menu.add_button("[ REPLAY TIPS ]", _replay_tips)
	menu.add_button("[ BACK ]", _back)

	display_menu.row_h = 38.0
	var scale := display_menu.add_slider("UI Scale", func(): return o.ui_scale, _set_scale, 0.8, 1.5, 0.05)
	scale["fmt"] = pct
	display_menu.add_toggle("High Contrast Text", func(): return o.high_contrast, _tog_contrast)
	display_menu.add_choice("Quality", func(): return GameOptions.QUALITY_NAMES[o.quality], _cycle_quality)
	display_menu.add_choice("Frame Limit", _fps_text, _cycle_fps)
	display_menu.add_toggle("VSync", func(): return o.vsync, _tog_vsync)
	display_menu.add_toggle("Auto-Pause", func(): return o.pause_on_focus_loss, func(_d): o.pause_on_focus_loss = not o.pause_on_focus_loss)
	if not OS.has_feature("mobile"):
		if not Platform.is_deck_like():
			display_menu.add_choice("Resolution", func(): return "%dx%d" % [GameOptions.RESOLUTIONS[o.res_index].x, GameOptions.RESOLUTIONS[o.res_index].y], _cycle_res)
		display_menu.add_toggle("Fullscreen", func(): return o.fullscreen, _toggle_fullscreen)
	display_menu.add_button("[ BACK ]", func(): _open_section("main"))

	pad_menu.row_h = 38.0
	pad_menu.add_toggle("Rumble", func(): return o.rumble, _tog_rumble)
	var rs := pad_menu.add_slider("Rumble Strength", func(): return o.rumble_strength, _set_rumble_strength, 0.1, 1.0, 0.1)
	rs["fmt"] = pct
	var dz := pad_menu.add_slider("Stick Dead Zone", func(): return o.pad_deadzone, func(v): o.pad_deadzone = v, 0.05, 0.4, 0.05)
	dz["fmt"] = pct
	pad_menu.add_choice("Button Prompts", func(): return GameOptions.PROMPT_STYLES[clampi(o.prompt_style, 0, GameOptions.PROMPT_STYLES.size() - 1)], func(d): o.prompt_style = posmod(o.prompt_style + d, GameOptions.PROMPT_STYLES.size()))
	pad_menu.add_toggle("System Keyboard", func(): return o.steam_keyboard, func(_d): o.steam_keyboard = not o.steam_keyboard)
	pad_menu.add_button("[ BUTTON LAYOUT ]", func(): _open_section("controls"))
	pad_menu.add_button("[ BACK ]", func(): _open_section("main"))

	touch_menu.row_h = 40.0
	var s_size := touch_menu.add_slider("Button Size", func(): return o.touch_size, func(v): o.touch_size = v, 0.6, 1.5, 0.05)
	s_size["fmt"] = pct
	var s_op := touch_menu.add_slider("Opacity", func(): return o.touch_opacity, func(v): o.touch_opacity = v, 0.2, 1.0, 0.05)
	s_op["fmt"] = pct
	touch_menu.add_toggle("Left-Handed", func(): return o.touch_left_handed, _toggle_lefty)
	touch_menu.add_toggle("Vibration", func(): return o.haptics, _toggle_haptics)
	touch_menu.add_button("[ DEFAULTS ]", _touch_defaults)
	touch_menu.add_button("[ BACK ]", func(): _open_section("main"))
	ui.input.binding_captured.connect(_on_captured)
	o.changed.connect(_rebuild_rows)


func _set_scale(v: float) -> void:
	ui.options.ui_scale = v
	ui.apply_options()


func _tog_contrast(_d: int) -> void:
	ui.options.high_contrast = not ui.options.high_contrast
	ui.apply_options()


func _tog_vsync(_d: int) -> void:
	ui.options.vsync = not ui.options.vsync
	ui.apply_options()


func _tog_rumble(_d: int) -> void:
	ui.options.rumble = not ui.options.rumble
	ui.input.rumble("damage")


func _set_rumble_strength(v: float) -> void:
	ui.options.rumble_strength = v
	ui.input.rumble("kill")





func _cycle_quality(d: int) -> void:
	var o: GameOptions = ui.options
	o.quality = posmod(o.quality + d, GameOptions.QUALITY_NAMES.size())
	ui.apply_options()


func _fps_text() -> String:
	var c: int = ui.options.fps_cap()
	return "Uncapped" if c == 0 else ("%d FPS" % c) + ("  (Deck 40 Hz)" if c == 40 else "")


func _cycle_fps(d: int) -> void:
	var o: GameOptions = ui.options
	o.fps_cap_index = posmod(o.fps_cap_index + d, GameOptions.FPS_CAPS.size())
	ui.apply_options()


func _toggle_lefty(_d: int) -> void:
	ui.options.touch_left_handed = not ui.options.touch_left_handed


func _toggle_haptics(_d: int) -> void:
	ui.options.haptics = not ui.options.haptics
	if ui.options.haptics and OS.has_feature("mobile"):
		Input.vibrate_handheld(40)


func _touch_defaults() -> void:
	var o: GameOptions = ui.options
	o.touch_size = 1.0
	o.touch_opacity = 0.6
	o.touch_left_handed = false
	o.haptics = true


func _replay_tips() -> void:
	ui.progression.reset_tips()
	ui.options.tips_enabled = true
	_flash("Tips will show again for %s." % ui.progression.active_name())


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


func _open_section(s: String) -> void:
	section = s
	ui.input.cancel_capture()
	csel = 0
	cscroll = 0
	_msg = ""
	var m := _menu_for(s)
	if m != null:
		m.enter_t = 0.0
		m.hl_y = -1.0
		m.sel = 0
		m.scroll = 0
	_rebuild_rows()


func _menu_for(s: String) -> MenuList:
	match s:
		"main": return menu
		"display": return display_menu
		"gamepad": return pad_menu
		"touch": return touch_menu
	return null


func _on_open(arg) -> void:
	return_to = arg if arg is String else "title"
	device = "gamepad" if ui.input.active_mode() == "gamepad" else "keyboard"
	_open_section("main")


func _flash(m: String) -> void:
	_msg = m
	_msg_t = 3.5


func _on_captured(_dev: String, _act: String, message: String) -> void:
	_flash(message)


# ---- controls rows ---------------------------------------------------------------------------

func _rebuild_rows() -> void:
	_crows.clear()
	var pad_in_use: bool = ui.input.active_mode() == "gamepad"
	if not pad_in_use:                     # a controller player never sees the keyboard tables
		_crows.append({"kind": "scheme"})
		_crows.append({"kind": "device"})
	for a in GameInput.ACTIONS:
		if device == "gamepad" and int(a.pad) == -2:
			continue
		if device == "keyboard" and int(a.key) == 0 and int(a.pad) >= 16:
			continue                       # back grips are pad-only
		_crows.append({"kind": "bind", "id": a.id, "label": a.label})
	_crows.append({"kind": "reset"})
	_crows.append({"kind": "back"})
	csel = clampi(csel, 0, _crows.size() - 1)


func _cycle_scheme(d: int) -> void:
	var o: GameOptions = ui.options
	o.control_mode = posmod(o.control_mode + d, GameOptions.CONTROL_MODES.size())
	if o.get_control_mode() in ["keyboard", "gamepad"]:
		device = o.get_control_mode()
		_rebuild_rows()


func _activate_row(i: int) -> void:
	var r: Dictionary = _crows[i]
	match r.kind:
		"scheme":
			_cycle_scheme(1)
		"device":
			device = "gamepad" if device == "keyboard" else "keyboard"
			_rebuild_rows()
		"bind":
			ui.input.begin_capture(device, r.id)
			_flash(ui.input.hint("Press a key for %s   (Esc cancels)" % String(r.label).to_upper(),
				"Press a button for %s   (Menu cancels)" % String(r.label).to_upper()))
		"reset":
			ui.input.reset_bindings(device)
			_flash("%s bindings reset to defaults" % device.to_upper())
		"back":
			_open_section("main")


func _adjust_row(i: int, d: int) -> void:
	var r: Dictionary = _crows[i]
	if r.kind == "scheme":
		_cycle_scheme(d)
	elif r.kind == "device":
		device = "gamepad" if device == "keyboard" else "keyboard"
		_rebuild_rows()


# ---- input ---------------------------------------------------------------------------------------

func handle_input(inp: GameInput, _d: float) -> void:
	if inp.capturing():
		return
	if section == "controls":
		if inp.just("ui_up"):
			csel = posmod(csel - 1, _crows.size())
		if inp.just("ui_down"):
			csel = posmod(csel + 1, _crows.size())
		if inp.just("ui_left"):
			_adjust_row(csel, -1)
		if inp.just("ui_right"):
			_adjust_row(csel, 1)
		if inp.just("ui_accept"):
			_activate_row(csel)
		if inp.just("ui_back") or inp.just("pause"):
			_open_section("main")
		return
	var m := _menu_for(section)
	if inp.just("ui_up"):
		m.nav(-1)
	if inp.just("ui_down"):
		m.nav(1)
	if inp.just("ui_left"):
		m.adjust(-1)
	if inp.just("ui_right"):
		m.adjust(1)
	if inp.just("ui_accept"):
		m.activate()
	if inp.just("ui_back") or inp.just("pause"):
		if section == "main":
			_back()
		else:
			_open_section("main")


func on_pointer_move(p: Vector2) -> void:
	if section == "controls":
		for e in _crects:
			if e[1].has_point(p):
				csel = e[0]
		return
	_menu_for(section).pointer_move(p)


func on_pointer_down(p: Vector2) -> void:
	if section == "controls":
		if ui.input.capturing():
			ui.input.cancel_capture()
			return
		for e in _crects:
			if e[1].has_point(p):
				csel = e[0]
				var r: Dictionary = _crows[csel]
				if r.kind in ["scheme", "device"]:
					_adjust_row(csel, 1 if p.x >= e[1].get_center().x else -1)
				else:
					_activate_row(csel)
				return
		return
	_menu_for(section).pointer_down(p)


func on_pointer_drag(p: Vector2) -> void:
	if section != "controls":
		_menu_for(section).pointer_drag(p)


func on_pointer_up(_p: Vector2) -> void:
	if section != "controls":
		_menu_for(section).pointer_up()


func frame(delta: float) -> void:
	super.frame(delta)
	if _msg_t > 0.0:
		_msg_t -= delta
		if _msg_t <= 0.0:
			_msg = ""


# ---- drawing ---------------------------------------------------------------------------------------

func _draw() -> void:
	var w := size.x
	var h := size.y
	if return_to == "pause":
		fill(Color(0, 0, 0, 0.92))
	else:
		fill(Color(0.01, 0.008, 0.004, 0.96))
		noise(200, Color(0.12, 0.1, 0.04))
	var a := clampf(age / 0.25, 0.0, 1.0)
	match section:
		"controls":
			_draw_controls(w, h, a)
		"touch":
			_draw_touch(w, h, a)
		_:
			var m := _menu_for(section)
			var compact := h < 460.0
			m.compact = compact
			var head_h := 50.0 if compact else 0.0
			m.max_rows = m.rows_for(h - (head_h + 34.0 if compact else 150.0))
			var total := m.total_height()
			var top := head_h if compact else floorf((h - total) * 0.5) + 14.0
			var title: String = {"main": "OPTIONS", "display": "DISPLAY & PERFORMANCE", "gamepad": "CONTROLLER"}.get(section, "OPTIONS")
			UITheme.head(self, title, 0, 6.0 if compact else maxf(10.0, top - 62) - (1.0 - a) * 12, 30 if compact else 40, Color(0.9, 0.8, 0.2, a), HORIZONTAL_ALIGNMENT_CENTER, w)
			m.draw(self, w * 0.5, top, dt, ui.clock)
			UITheme.text(self, ui.input.hint("UP/DOWN select    LEFT/RIGHT adjust    ESC back", "D-Pad select    Left/Right adjust    A confirm    B back",
				"TAP a row    tap the sides to adjust" + ("    drag to scroll" if m.max_rows < m.items.size() else "")), 0, h - (22 if compact else 26), 14 if compact else 13, UITheme.HINT, HORIZONTAL_ALIGNMENT_CENTER, w)
	if _msg != "":
		UITheme.text(self, _msg, 0, h - (46 if h < 460.0 else 52), 15, Color(1, 0.9, 0.4, clampf(_msg_t, 0.0, 1.0)), HORIZONTAL_ALIGNMENT_CENTER, w)
	UITheme.vignette(self, size, 0.4)


func _binding_text(id: String) -> String:
	var inp: GameInput = ui.input
	if device == "keyboard":
		return inp.key_name(inp.key_of(id))
	var c := inp.pad_of(id)
	return inp.pad_name(c) if c >= 0 else "None"


func _draw_controls(w: float, h: float, a: float) -> void:
	var inp: GameInput = ui.input
	var compact := h < 460.0
	UITheme.head(self, "CONTROLS", 0, 6 if compact else 12, 28 if compact else 36, Color(0.9, 0.8, 0.2, a), HORIZONTAL_ALIGNMENT_CENTER, w)
	var row_h := 28.0
	var top := 44.0 if compact else 62.0
	var vis := maxi(4, int((h - top - (34.0 if compact else 70.0)) / row_h))
	if csel < cscroll:
		cscroll = csel
	if csel >= cscroll + vis:
		cscroll = csel - vis + 1
	cscroll = clampi(cscroll, 0, maxi(0, _crows.size() - vis))
	var pw := minf(w - 60.0, 640.0)
	var px := (w - pw) * 0.5
	_crects.clear()
	var y := top
	for i in range(cscroll, mini(_crows.size(), cscroll + vis)):
		var r: Dictionary = _crows[i]
		var rect := Rect2(px, y, pw, row_h - 2)
		_crects.append([i, rect])
		var sel := i == csel
		if sel:
			UITheme.panel(self, rect, Color(0.4, 0.35, 0.15, 0.5), Color(1, 0.9, 0.3, 0.55), 5, 1)
		var col := UITheme.GOLD_BRIGHT if sel else Color(0.75, 0.75, 0.75)
		var ty := y + (row_h - 2 - UITheme.text_h(17)) * 0.5
		match r.kind:
			"scheme":
				var mode: String = ui.options.get_control_mode()
				var shown := mode.to_upper()
				if mode == "auto":
					shown = "AUTO  (now: %s)" % inp.active_mode().to_upper()
				UITheme.text(self, "Control Scheme", px + 14, ty, 17, col)
				UITheme.text(self, "<  %s  >" % shown, px, ty, 17, Color(0.5, 1, 0.6) if mode == "auto" else Color(1, 0.9, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, pw - 14)
			"device":
				UITheme.text(self, "Edit Bindings For", px + 14, ty, 17, col)
				UITheme.text(self, "<  %s  >" % ("KEYBOARD + MOUSE" if device == "keyboard" else "GAMEPAD"), px, ty, 17, Color(1, 0.9, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, pw - 14)
			"bind":
				UITheme.text(self, r.label, px + 14, ty, 17, col)
				var waiting: bool = inp.capturing() and sel
				var txt := _binding_text(r.id)
				var vcol := Color(1, 0.95, 0.5) if inp.is_default(device, r.id) else Color(0.5, 1, 0.6)
				if waiting:
					txt = "press a %s..." % ("key" if device == "keyboard" else "button")
					vcol = Color(1, 0.5, 0.3, 0.6 + 0.4 * sin(ui.clock * 10.0))
				var bw := 170.0
				UITheme.panel(self, Rect2(px + pw - bw - 10, y + 2, bw, row_h - 6), Color(0.1, 0.09, 0.05, 0.9), Color(vcol.r, vcol.g, vcol.b, 0.5), 4, 1)
				UITheme.text(self, txt, px + pw - bw - 10, ty, 16, vcol, HORIZONTAL_ALIGNMENT_CENTER, bw)
				if device == "keyboard" and String(r.id).begins_with("move_"):
					UITheme.text(self, "(arrow keys always work)", px + 200, ty + 2, 12, Color(0.45, 0.45, 0.4))
				if device == "keyboard" and r.id == "attack":
					UITheme.text(self, "(left click always works)", px + 200, ty + 2, 12, Color(0.45, 0.45, 0.4))
			"reset":
				UITheme.head(self, "[ RESET %s TO DEFAULTS ]" % device.to_upper(), px, ty - 1, 18, Color(1, 0.6, 0.3) if sel else Color(0.7, 0.45, 0.25), HORIZONTAL_ALIGNMENT_CENTER, pw)
			"back":
				UITheme.head(self, "[ BACK ]", px, ty - 1, 18, col, HORIZONTAL_ALIGNMENT_CENTER, pw)
		y += row_h
	if cscroll > 0:
		UITheme.text(self, "^", 0, top - 16, 14, Color(1, 0.9, 0.3), HORIZONTAL_ALIGNMENT_CENTER, w)
	if cscroll + vis < _crows.size():
		UITheme.text(self, "v", 0, y, 14, Color(1, 0.9, 0.3), HORIZONTAL_ALIGNMENT_CENTER, w)
	var hint: String = inp.hint("UP/DOWN select    ENTER rebind    LEFT/RIGHT change    ESC back",
		"D-Pad select    A rebind    B back    (while rebinding: Menu cancels)", "TAP a row to rebind    tap the arrows to change")
	if inp.capturing():
		hint = inp.hint("Waiting for input...  Esc cancels.  If a key is already used the two actions swap.",
			"Press the new button...  Menu cancels.  If a button is already used the two actions swap.")
	UITheme.text(self, hint, 0, h - (22 if compact else 26), 14 if compact else 13, UITheme.HINT, HORIZONTAL_ALIGNMENT_CENTER, w)


func _draw_touch(w: float, h: float, a: float) -> void:
	var compact := h < 460.0
	touch_menu.compact = compact
	var mtop := 44.0 if compact else 66.0
	UITheme.head(self, "TOUCH CONTROLS", 0, 6 if compact else 14, 28 if compact else 36, Color(0.9, 0.8, 0.2, a), HORIZONTAL_ALIGNMENT_CENTER, w)
	var total := touch_menu.total_height()
	touch_menu.draw(self, w * 0.5, mtop, dt, ui.clock)
	# live preview of the layout (landscape phone outline)
	var pw := minf(w - 80.0, 560.0)
	var ph := pw * 0.46
	var avail := h - (mtop + total) - (36.0 if compact else 50.0)
	if ph > avail:
		ph = maxf(80.0, avail)
		pw = ph / 0.46
	var pr := Rect2((w - pw) * 0.5, mtop + total + 8.0, pw, ph)
	UITheme.panel(self, pr, Color(0.02, 0.02, 0.015, 0.95), Color(0.9, 0.8, 0.2, 0.5), 10, 2)
	var vsize := Vector2(1600.0, 720.0) if pr.size.x / pr.size.y > 2.0 else Vector2(960.0, 720.0)
	vsize = Vector2(pr.size.x / pr.size.y * 720.0, 720.0)
	var lay: Dictionary = ui.input.touch_layout(vsize)
	var sc := pr.size.y / 720.0
	var op: float = ui.options.touch_opacity
	var f := op / 0.6
	var font := UITheme.title_font()
	for key in ["move_c"]:
		var c: Vector2 = pr.position + lay[key] * sc
		var col := Color(1, 1, 1) if key == "move_c" else Color(1, 0.3, 0.2)
		draw_circle(c, lay.stick_r * sc, Color(col, minf(1.0, 0.16 * f)))
		draw_arc(c, lay.stick_r * sc, 0, TAU, 32, Color(col, minf(1.0, 0.7 * f)), 1.5)
	for b in lay.buttons:
		var c2: Vector2 = pr.position + b.pos * sc
		var cc: Color = b.color
		draw_circle(c2, b.r * sc, Color(cc, minf(1.0, 0.3 * f)))
		draw_arc(c2, b.r * sc, 0, TAU, 24, Color(cc, minf(1.0, 0.95 * f)), 1.5)
		var fs := maxi(9, int(b.r * sc * 0.5))
		var tw := font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if tw > b.r * sc * 1.7:
			fs = maxi(9, int(fs * b.r * sc * 1.7 / tw))
			tw = font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, c2 + Vector2(-tw * 0.5, fs * 0.33), b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, minf(1.0, 0.95 * f)))
	UITheme.text(self, "PREVIEW", pr.position.x + 8, pr.position.y + 4, 12, Color(0.7, 0.7, 0.6, 0.8))
	UITheme.text(self, "Sticks float inside their half of the screen. Keep thumbs inside the safe area.", 0, h - (22 if compact else 26), 14 if compact else 13, UITheme.HINT, HORIZONTAL_ALIGNMENT_CENTER, w)
