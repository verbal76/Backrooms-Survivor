extends UIScreen
## Level-up perk choice (drawPerkChoice): pick 1 of 2 random run-only perks.

const CARD_W := 280.0
const CARD_H := 150.0
const GAP := 44.0

var sel := 0
var _rects: Array = [Rect2(), Rect2()]
var _hover_t := [0.0, 0.0]
var _chosen := -1
var _chosen_t := 0.0


func _init() -> void:
	super._init()
	input_delay = 0.7


func _on_open(_arg) -> void:
	sel = 0
	_chosen = -1
	_hover_t = [0.0, 0.0]


func _pick(i: int) -> void:
	if _chosen >= 0:
		return
	_chosen = i
	_chosen_t = 0.0


func handle_input(inp: GameInput, _d: float) -> void:
	if _chosen >= 0:
		return
	if inp.just("ui_left") or inp.just("weapon_prev"):
		sel = 0
	if inp.just("ui_right") or inp.just("weapon_next"):
		sel = 1
	if inp.just("use_water"):
		_pick(0)
	elif inp.just("use_bandage"):
		_pick(1)
	elif inp.just("ui_accept"):
		_pick(sel)


func frame(delta: float) -> void:
	super.frame(delta)
	for i in 2:
		_hover_t[i] = move_toward(_hover_t[i], 1.0 if sel == i else 0.0, delta * 6.0)
	if _chosen >= 0:
		_chosen_t += delta
		if _chosen_t > 0.28:
			var c := _chosen
			_chosen = -1
			ui.choose_perk(c)


func on_pointer_move(p: Vector2) -> void:
	if age < input_delay:
		return
	for i in 2:
		if _rects[i].has_point(p):
			sel = i


func on_pointer_down(p: Vector2) -> void:
	if age < input_delay:
		return
	for i in 2:
		if _rects[i].has_point(p):
			sel = i
			_pick(i)


func _draw() -> void:
	var choices: Array = ui.perk_choices
	if choices.size() < 2:
		return
	var w := size.x
	var h := size.y
	var t: float = ui.clock
	var a := clampf(age / 0.25, 0.0, 1.0)
	fill(Color(0, 0, 0, 0.78 * a))
	# floating embers
	for i in 26:
		var px := fposmod(sin(i * 12.9898) * 43758.5453, 1.0) * w
		var py := h - fposmod(t * (14.0 + (i % 5) * 6.0) + i * 97.0, h + 40.0)
		var al := 0.15 + 0.15 * sin(t * 2.0 + i)
		draw_circle(Vector2(px + sin(t + i) * 12.0, py), 1.5 + (i % 3), Color(1, 0.85, 0.3, al * a))

	UITheme.head(self, "LEVEL UP! CHOOSE A PERK", 0, h * 0.16 - (1.0 - a) * 20, 38, Color(0.9, 0.8, 0.2, a), HORIZONTAL_ALIGNMENT_CENTER, w)
	UITheme.head(self, "These perks last for this run only.", 0, h * 0.16 + 52, 22, Color(0.6, 0.6, 0.6, a), HORIZONTAL_ALIGNMENT_CENTER, w)

	var total_w := CARD_W * 2 + GAP
	var x0 := floorf((w - total_w) * 0.5)
	var y0 := h * 0.34
	for i in 2:
		var perk: Dictionary = choices[i]
		var delay := 0.08 + i * 0.1
		var ca := clampf((age - delay) / 0.3, 0.0, 1.0)
		var ease_a := 1.0 - pow(1.0 - ca, 3.0)
		var hv: float = _hover_t[i]
		var grow := hv * 6.0
		var rect := Rect2(x0 + i * (CARD_W + GAP), y0 + (1.0 - ease_a) * 60.0, CARD_W, CARD_H)
		_rects[i] = Rect2(rect.position.x, y0, CARD_W, CARD_H)
		var r := rect.grow(grow)
		var chosen := _chosen == i
		if chosen:
			r = r.grow(_chosen_t * 40.0)
		var fillc := Color(0.15, 0.3, 0.12, 0.96).lerp(Color(0.08, 0.08, 0.08, 0.96), 1.0 - hv)
		var edge := Color(0.3, 1, 0.3, 0.35 + 0.65 * hv).lerp(Color(0.35, 0.35, 0.35, 0.6), 1.0 - hv)
		if hv > 0.01:
			var glow := 0.12 + 0.06 * sin(t * 4.0)
			UITheme.panel(self, r.grow(8), Color(0.3, 1, 0.3, glow * hv * ca), Color(0, 0, 0, 0), 14)
		fillc.a *= ca
		edge.a *= ca
		UITheme.panel(self, r, fillc, edge, 8, 2)
		var badge := Color(1, 0.9, 0.3, ca) if sel == i else Color(0.45, 0.45, 0.45, ca)
		UITheme.head(self, "[%d]" % (i + 1), r.position.x, r.position.y + 10, 22, badge, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		var nc := Color(1, 1, 1, ca) if sel == i else Color(0.65, 0.65, 0.65, ca)
		var nm := String(perk.name).to_upper()
		UITheme.head(self, nm, r.position.x, r.position.y + 42, UITheme.fit(nm, 26, r.size.x - 20, UITheme.title_font()), nc,
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		var dc := Color(0.8, 0.9, 0.7, ca) if sel == i else Color(0.5, 0.5, 0.5, ca)
		UITheme.wrapped(self, perk.desc, r.position.x + 16, r.position.y + 82, r.size.x - 32, 15, dc)
		if chosen:
			UITheme.panel(self, r, Color(1, 1, 0.6, 0.4 * (1.0 - _chosen_t / 0.28)), Color(0, 0, 0, 0), 8)
	if ui.game.player.active_run_perks.size() > 0:
		var names: Array = []
		for p in ui.game.player.active_run_perks:
			names.append(p.name)
		UITheme.text(self, "Active: " + ", ".join(names), 40, y0 + CARD_H + 36, 14, Color(0.3, 0.8, 0.5, 0.7 * a), HORIZONTAL_ALIGNMENT_CENTER, w - 80)
	var hint := "LEFT/RIGHT or 1 / 2 to choose    ENTER confirm"
	if ui.input.active_mode() == "gamepad":
		hint = "D-PAD / BUMPERS choose    A confirm"
	elif ui.input.active_mode() == "touch":
		hint = "TAP a perk"
	UITheme.text(self, hint, 0, h - 40, 13, Color(0.5, 0.5, 0.5, 0.8 * a), HORIZONTAL_ALIGNMENT_CENTER, w)
	UITheme.vignette(self, size, 0.45)
