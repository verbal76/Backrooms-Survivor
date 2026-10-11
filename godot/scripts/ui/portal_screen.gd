extends UIScreen
## Exit-portal prompt (escape / stay) and the victory screen after escaping.

const CARD_W := 260.0
const CARD_H := 160.0
const GAP := 50.0

const CHOICES := [
	{"title": "ESCAPE", "subtitle": "Complete your run", "desc": "Earn 2x token bonus.\nYour survival is recorded.\nReturn to title screen.", "color": Color(0.2, 1, 0.5)},
	{"title": "STAY", "subtitle": "Become a Living Legend", "desc": "No more exits.\nThe game continues until death.\nMaximize your scores.", "color": Color(1, 0.7, 0.2)},
]

var mode := "prompt"
var sel := 0
var _rects: Array = [Rect2(), Rect2()]
var _hover_t := [0.0, 0.0]


func _init() -> void:
	super._init()
	input_delay = 0.5


func _on_open(arg) -> void:
	mode = arg if arg is String else "prompt"
	sel = 0
	_hover_t = [0.0, 0.0]
	input_delay = 0.5 if mode == "prompt" else 1.2


func handle_input(inp: GameInput, _d: float) -> void:
	if mode == "victory":
		if inp.just("ui_accept") or inp.just("ui_back"):
			ui.back_to_title()
		return
	if inp.just("ui_left") or inp.just("headlamp"):
		sel = 0
	if inp.just("ui_right") or inp.just("bomb"):
		sel = 1
	if inp.just("use_water"):
		sel = 0
		ui.resolve_portal(true)
	elif inp.just("use_bandage"):
		sel = 1
		ui.resolve_portal(false)
	elif inp.just("ui_accept"):
		ui.resolve_portal(sel == 0)
	elif inp.just("ui_back"):
		ui.dismiss_portal_prompt()


func frame(delta: float) -> void:
	super.frame(delta)
	for i in 2:
		_hover_t[i] = move_toward(_hover_t[i], 1.0 if sel == i else 0.0, delta * 6.0)


func on_pointer_move(p: Vector2) -> void:
	if mode != "prompt" or age < input_delay:
		return
	for i in 2:
		if _rects[i].has_point(p):
			sel = i


func on_pointer_down(p: Vector2) -> void:
	if age < input_delay:
		return
	if mode == "victory":
		ui.back_to_title()
		return
	for i in 2:
		if _rects[i].has_point(p):
			sel = i
			ui.resolve_portal(i == 0)
			return


func _draw() -> void:
	if mode == "victory":
		_draw_victory()
	else:
		_draw_prompt()


func _draw_prompt() -> void:
	var w := size.x
	var h := size.y
	var t: float = ui.clock
	var a := clampf(age / 0.25, 0.0, 1.0)
	var g = ui.game
	fill(Color(0, 0.02, 0.01, 0.82 * a))
	# portal glow
	for i in 5:
		var r := 120.0 + i * 70.0 + sin(t * 2.0 + i) * 10.0
		draw_arc(Vector2(w * 0.5, h * 0.5), r, 0, TAU, 64, Color(0.2, 1, 0.7, 0.05 * a), 3.0)
	UITheme.head(self, "EXIT PORTAL ACTIVE", 0, h * 0.14 - (1.0 - a) * 16, 40, Color(0.2, 1, 0.6, a), HORIZONTAL_ALIGNMENT_CENTER, w)
	UITheme.head(self, "You cleared the horde. The portal beckons.", 0, h * 0.14 + 54, 22, Color(0.7, 0.8, 0.7, a), HORIZONTAL_ALIGNMENT_CENTER, w)
	UITheme.text(self, "Day %d  |  %d Kills  |  %s  |  Lv.%d" % [g.day, g.kills, UITheme.fmt_time(g.run_time), g.player.level], 0,
		h * 0.14 + 92, 15, Color(0.5, 0.5, 0.5, a), HORIZONTAL_ALIGNMENT_CENTER, w)
	var x0 := floorf((w - (CARD_W * 2 + GAP)) * 0.5)
	var y0 := h * 0.40
	for i in 2:
		var c: Dictionary = CHOICES[i]
		var col: Color = c.color
		var ca := clampf((age - i * 0.1) / 0.3, 0.0, 1.0)
		var hv: float = _hover_t[i]
		var rect := Rect2(x0 + i * (CARD_W + GAP), y0 + (1.0 - ca) * 50.0, CARD_W, CARD_H)
		_rects[i] = Rect2(rect.position.x, y0, CARD_W, CARD_H)
		var r := rect.grow(hv * 6.0)
		if hv > 0.01:
			UITheme.panel(self, r.grow(8), Color(col.r, col.g, col.b, (0.1 + 0.05 * sin(t * 4.0)) * hv), Color(0, 0, 0, 0), 14)
		var fillc := Color(0.1, 0.2, 0.1, 0.96 * ca).lerp(Color(0.06, 0.06, 0.06, 0.96 * ca), 1.0 - hv)
		var edge := Color(col.r, col.g, col.b, (0.35 + 0.55 * hv) * ca)
		UITheme.panel(self, r, fillc, edge, 8, 2)
		var dim := 1.0 - hv
		UITheme.head(self, "[%d]" % (i + 1), r.position.x, r.position.y + 10, 22, col.lerp(Color(0.4, 0.4, 0.4), dim), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		UITheme.head(self, c.title, r.position.x, r.position.y + 38, 30, Color(1, 1, 1).lerp(Color(0.5, 0.5, 0.5), dim), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		UITheme.text(self, c.subtitle, r.position.x, r.position.y + 74, 15, col.lerp(Color(0.4, 0.4, 0.4), dim), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		UITheme.wrapped(self, c.desc, r.position.x + 10, r.position.y + 98, r.size.x - 20, 13, Color(0.7, 0.8, 0.7).lerp(Color(0.35, 0.35, 0.35), dim))
	var hint := "LEFT/RIGHT choose    ENTER confirm    ESC not yet"
	if ui.input.active_mode() == "gamepad":
		hint = "D-PAD / BUMPERS choose    A confirm    B not yet"
	UITheme.text(self, hint, 0, h - 40, 13, Color(0.5, 0.5, 0.5, 0.8 * a), HORIZONTAL_ALIGNMENT_CENTER, w)
	UITheme.vignette(self, size, 0.5)


func _draw_victory() -> void:
	var w := size.x
	var h := size.y
	var t: float = ui.clock
	var g = ui.game
	var p = g.player
	fill(Color(0, 0, 0))
	for i in 40:
		var px := (sin(t * 0.3 + i * 7.3) * 0.5 + 0.5) * w
		var py := (cos(t * 0.2 + i * 5.7) * 0.5 + 0.5) * h
		var br := sin(t * 2.0 + i) * 0.3 + 0.4
		draw_circle(Vector2(px, py), 2.0 + sin(t + i) * 1.5, Color(0.1, br, br * 0.7, 0.3))
	var a := clampf(age / 0.8, 0.0, 1.0)
	var cy := h * 0.10
	UITheme.head(self, "ESCAPED", 0, cy - (1.0 - a) * 30, 72, Color(0.2, 1, 0.5, a), HORIZONTAL_ALIGNMENT_CENTER, w)
	var nm: String = ui.player_name if ui.player_name != "" else "Subject"
	UITheme.head(self, "%s found the way out." % nm, 0, cy + 76, 30, Color(0.8, 0.9, 0.7, a), HORIZONTAL_ALIGNMENT_CENTER, w)
	var y := cy + 130.0
	UITheme.head(self, "FINAL STATS", 0, y, 24, Color(0.9, 0.8, 0.2, a), HORIZONTAL_ALIGNMENT_CENTER, w)
	y += 38.0
	var lines := [
		["Day Survived", str(g.day)], ["Total Kills", str(g.kills)], ["Best Streak", str(p.best_run_streak)],
		["Level Reached", str(p.level)], ["Time Survived", UITheme.fmt_time(g.run_time)],
		["Difficulty", UITheme.DIFF_NAMES[ui.difficulty - 1]],
	]
	for i in lines.size():
		var la := clampf((age - 0.4 - i * 0.12) / 0.25, 0.0, 1.0)
		UITheme.text(self, lines[i][0], w * 0.5 - 200, y, 17, Color(0.6, 0.6, 0.6, la), HORIZONTAL_ALIGNMENT_RIGHT, 180)
		UITheme.text(self, lines[i][1], w * 0.5 + 20, y, 17, Color(1, 1, 1, la))
		y += 24.0
	if p.active_run_perks.size() > 0:
		var names: Array = []
		for pk in p.active_run_perks:
			names.append(pk.name)
		UITheme.text(self, "Perks: " + ", ".join(names), 40, y + 6, 14, Color(0.3, 0.8, 0.5, 0.7), HORIZONTAL_ALIGNMENT_CENTER, w - 80)
		y += 26.0
	y += 16.0
	var ta := clampf((age - 1.4) / 0.4, 0.0, 1.0)
	UITheme.head(self, "+%d TOKENS (2x Escape Bonus!)" % ui.victory_tokens, 0, y - (1.0 - ta) * 10, 26, Color(0.9, 0.8, 0.2, ta), HORIZONTAL_ALIGNMENT_CENTER, w)
	y += 52.0
	var blink := 0.5 + 0.5 * sin(t * 3.0)
	UITheme.text(self, "[ Press Enter / A to continue ]", 0, y, 16, Color(0.7, 0.8, 0.7, (0.4 + 0.6 * blink) * ta), HORIZONTAL_ALIGNMENT_CENTER, w)
	UITheme.vignette(self, size, 0.5)
