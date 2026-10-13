extends UIScreen
## Death screen (drawDeathScreen): run summary, tokens earned (count-up), retry / upgrades / main menu.

var menu := MenuList.new()
var _tokens_shown := 0.0


func _init() -> void:
	super._init()
	input_delay = 0.8


func _on_bound() -> void:
	design_min = Vector2(640, 340)        # phone landscape at 2x: verified by screenshot
	menu.row_h = 38.0
	menu.half_w = 150.0
	menu.add_button("[ TRY AGAIN ]", func(): ui.start_game())
	menu.add_button("[ UPGRADES ]", _open_shop)
	menu.add_button("[ MAIN MENU ]", func(): ui.back_to_title())


func _open_shop() -> void:
	ui.shop_return = "death"
	ui.show_screen("shop")


func _on_open(_arg) -> void:
	menu.sel = 0
	menu.enter_t = -1.2
	menu.hl_y = -1.0
	_tokens_shown = 0.0


func _input(event: InputEvent) -> void:
	if visible and age > input_delay and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_R:
		ui.start_game()


func handle_input(inp: GameInput, _d: float) -> void:
	if inp.just("ui_up"):
		menu.nav(-1)
	if inp.just("ui_down"):
		menu.nav(1)
	if inp.just("ui_accept"):
		menu.activate()
	elif inp.just("ui_back"):
		ui.back_to_title()
	elif inp.just("pad_start"):
		ui.start_game()


func on_pointer_move(p: Vector2) -> void:
	if age >= input_delay:
		menu.pointer_move(p)


func on_pointer_down(p: Vector2) -> void:
	if age >= input_delay:
		menu.pointer_down(p)


func frame(delta: float) -> void:
	super.frame(delta)
	if age > 0.9:
		_tokens_shown = move_toward(_tokens_shown, float(ui.tokens_earned), maxf(4.0, ui.tokens_earned * 0.9) * delta)


func _draw() -> void:
	var w := size.x
	var h := size.y
	var g = ui.game
	var p = g.player
	var a := clampf(age / 0.6, 0.0, 1.0)
	fill(Color(0.02, 0.0, 0.0, 0.86 * a))
	# blood-red edge pulse
	var pulse := 0.5 + 0.5 * sin(ui.clock * 1.6)
	UITheme.vignette(self, size, 0.9, Color(0.5, 0.0, 0.0))
	draw_rect(Rect2(0, 0, w, h), Color(0.4, 0, 0, 0.05 + 0.04 * pulse))

	var nm: String = ui.player_name.to_upper() if ui.player_name != "" else "SUBJECT"
	var block_h := 330.0
	var top := floorf((h - block_h) * 0.5)
	var drop := (1.0 - clampf(age / 0.5, 0.0, 1.0)) * -30.0
	var tsz := UITheme.fit("%s DIED IN THE BACKROOMS" % nm, 40, w - 40, UITheme.title_font())
	UITheme.head(self, "%s DIED IN THE BACKROOMS" % nm, 0, top + drop, tsz, Color(1, 0.2, 0.2, a), HORIZONTAL_ALIGNMENT_CENTER, w)
	var days: int = g.day
	var sub := "%s survived %d Day%s" % [ui.player_name if ui.player_name != "" else "Subject", days, "s" if days > 1 else ""]
	UITheme.head(self, sub, 0, top + 52, 24, Color(0.9, 0.8, 0.2, a), HORIZONTAL_ALIGNMENT_CENTER, w)
	var stats := "Time: %s  |  Kills: %d  |  Level: %d  |  Best Streak: %d" % [UITheme.fmt_time(g.run_time), g.kills, p.level, p.best_run_streak]
	UITheme.text(self, stats, 0, top + 88, 16, Color(0.7, 0.7, 0.7, a), HORIZONTAL_ALIGNMENT_CENTER, w)

	var ta := clampf((age - 0.8) / 0.3, 0.0, 1.0)
	var shown := int(_tokens_shown)
	var done: bool = shown >= ui.tokens_earned
	var fs := 30 + (4 if not done else 0)
	UITheme.head(self, "+%d Tokens Earned" % shown, 0, top + 118, fs, Color(1, 0.85, 0.2, ta), HORIZONTAL_ALIGNMENT_CENTER, w)
	var prof: Dictionary = ui.progression.profile(ui.difficulty)
	UITheme.text(self, "Total Tokens: %d  |  Best Day: %d  |  Best Streak: %d  |  Runs: %d" % [prof.tokens, prof.bestDay, prof.bestStreak, prof.totalRuns],
		0, top + 160, 15, Color(0.7, 0.6, 0.2, ta), HORIZONTAL_ALIGNMENT_CENTER, w)
	if p.active_run_perks.size() > 0:
		var names: Array = []
		for pk in p.active_run_perks:
			names.append(pk.name)
		UITheme.text(self, "Perks: " + ", ".join(names), 40, top + 182, 14, Color(0.3, 0.8, 0.5, 0.7 * ta), HORIZONTAL_ALIGNMENT_CENTER, w - 80)

	menu.draw(self, w * 0.5, top + 212.0, dt, ui.clock)
	UITheme.text(self, "%s was lost in the Backrooms." % (ui.player_name if ui.player_name != "" else "Subject"), 0,
		top + 212.0 + menu.total_height() + 14, 14, Color(0.6, 0.6, 0.6, a), HORIZONTAL_ALIGNMENT_CENTER, w)
	UITheme.text(self, ui.input.hint("UP/DOWN select    ENTER confirm    R try again", "D-Pad select    A confirm    Menu try again    B main menu",
		"TAP to select"), 0, h - 26, 13, UITheme.HINT, HORIZONTAL_ALIGNMENT_CENTER, w)
