extends UIScreen
## Meta-upgrade shop (drawUpgradeShop): spend tokens for permanent boosts, per difficulty profile.

const ROW_H := 36.0
const LIST_W := 560.0

var sel := 0
var _rects: Array = []
var _buy_rect := Rect2()
var _back_rect := Rect2()
var _flash := {}               # index -> {t: seconds, ok: bool}


func _on_open(_arg) -> void:
	sel = 0
	_flash.clear()


func _buy() -> void:
	var def: Dictionary = Progression.UPGRADES[sel]
	if ui.progression.buy_upgrade(ui.difficulty, def.id):
		_flash[sel] = {"t": 0.4, "ok": true}
		ui.game.fx.flash(Color(1.0, 0.85, 0.2, 0.12), 0.2)
	else:
		_flash[sel] = {"t": 0.35, "ok": false}


func _back() -> void:
	ui.show_screen(ui.shop_return)


func handle_input(inp: GameInput, _d: float) -> void:
	if inp.just("ui_up"):
		sel = posmod(sel - 1, Progression.UPGRADES.size())
	if inp.just("ui_down"):
		sel = posmod(sel + 1, Progression.UPGRADES.size())
	if inp.just("ui_accept"):
		_buy()
	if inp.just("ui_back") or inp.just("pause"):
		_back()


func frame(delta: float) -> void:
	super.frame(delta)
	for k in _flash.keys():
		_flash[k].t -= delta
		if _flash[k].t <= 0.0:
			_flash.erase(k)


func on_pointer_move(p: Vector2) -> void:
	for i in _rects.size():
		if _rects[i].has_point(p):
			sel = i


func on_pointer_down(p: Vector2) -> void:
	if _buy_rect.has_point(p):
		_buy()
	elif _back_rect.has_point(p):
		_back()
	else:
		for i in _rects.size():
			if _rects[i].has_point(p):
				sel = i
				if p.x > _rects[i].end.x - 110:
					_buy()
				return


func _draw() -> void:
	var w := size.x
	var h := size.y
	var cx := w * 0.5
	var t: float = ui.clock
	fill(Color(0.01, 0.008, 0.004, 0.97))
	noise(150, Color(0.1, 0.08, 0.03))
	var tokens: int = ui.progression.profile(ui.difficulty).tokens
	var a := clampf(age / 0.25, 0.0, 1.0)
	UITheme.head(self, "UPGRADES", 0, 20 - (1.0 - a) * 14, 36, Color(0.9, 0.8, 0.2, a), HORIZONTAL_ALIGNMENT_CENTER, w)
	# token counter with coin glint
	UITheme.head(self, "Tokens: %d  |  %s Profile" % [tokens, UITheme.DIFF_NAMES[ui.difficulty - 1]], 0, 64, 22,
		Color(1, 0.85, 0.2, a), HORIZONTAL_ALIGNMENT_CENTER, w)

	var list_top := 108.0
	var row_h := minf(ROW_H, (h - list_top - 170.0) / Progression.UPGRADES.size())
	_rects.clear()
	for i in Progression.UPGRADES.size():
		var def: Dictionary = Progression.UPGRADES[i]
		var level: int = ui.progression.upgrade_level(ui.difficulty, def.id)
		var maxed := level >= int(def.max)
		var cost: int = ui.progression.upgrade_cost(def.id, level)
		var can_buy := not maxed and tokens >= cost
		var is_sel := i == sel
		var y := list_top + i * row_h
		var ra := clampf((age - i * 0.03) / 0.2, 0.0, 1.0)
		var rect := Rect2(cx - LIST_W * 0.5, y, LIST_W, row_h - 3)
		_rects.append(rect)
		var shake := 0.0
		var fl = _flash.get(i)
		if fl != null and not fl.ok:
			shake = sin(fl.t * 70.0) * 5.0 * (fl.t / 0.35)
		var rx := shake
		if is_sel:
			UITheme.panel(self, Rect2(rect.position.x + rx, rect.position.y, rect.size.x, rect.size.y),
				Color(0.3, 0.25, 0.1, 0.6), Color(1, 0.9, 0.3, 0.4 + 0.15 * sin(t * 4.0)), 5, 1)
		if fl != null and fl.ok:
			UITheme.panel(self, rect, Color(0.3, 1.0, 0.4, fl.t * 0.6), Color(0, 0, 0, 0), 5)
		var nc := Color(1, 0.9, 0.3, ra) if is_sel else Color(0.7, 0.7, 0.7, ra)
		var ty := y + (row_h - 3 - UITheme.text_h(20, UITheme.title_font())) * 0.5
		UITheme.head(self, def.name, rect.position.x + 12 + rx, ty, 20, nc, HORIZONTAL_ALIGNMENT_LEFT, 220)
		# level pips
		var pip_x := rect.position.x + 235.0 + rx
		var pip_w := maxf(3.0, minf(10.0, 130.0 / int(def.max)))
		for p in int(def.max):
			var on := p < level
			var pr := Rect2(pip_x + p * (pip_w + 3.0), y + row_h * 0.5 - 8, pip_w, 12)
			if on:
				var pop := 0.0
				if fl != null and fl.ok and p == level - 1:
					pop = fl.t * 4.0
				UITheme.panel(self, pr.grow(pop), Color(0.3, 1, 0.3, ra), Color(0, 0, 0, 0), 2)
			else:
				UITheme.panel(self, pr, Color(0.2, 0.2, 0.2, ra), Color(0, 0, 0, 0), 2)
		var costx := rect.end.x - 100.0
		if maxed:
			UITheme.head(self, "MAXED", costx + rx, ty, 20, Color(0.4, 0.8, 0.4, ra), HORIZONTAL_ALIGNMENT_RIGHT, 92)
		else:
			var cc := Color(1, 0.85, 0.2, ra) if can_buy else Color(0.55, 0.32, 0.22, ra)
			UITheme.head(self, "%d T" % cost, costx + rx, ty, 20, cc, HORIZONTAL_ALIGNMENT_RIGHT, 92)

	var sel_def: Dictionary = Progression.UPGRADES[sel]
	var desc_y := list_top + Progression.UPGRADES.size() * row_h + 8.0
	UITheme.text(self, sel_def.desc, 0, desc_y, 16, Color(0.7, 0.7, 0.7), HORIZONTAL_ALIGNMENT_CENTER, w)

	var by := h - 70.0
	_buy_rect = Rect2(cx - 190, by, 170, 42)
	_back_rect = Rect2(cx + 20, by, 170, 42)
	var def2: Dictionary = Progression.UPGRADES[sel]
	var lvl2: int = ui.progression.upgrade_level(ui.difficulty, def2.id)
	var affordable: bool = ui.progression.can_afford(ui.difficulty, def2.id)
	button_rect(_buy_rect, "BUY" if lvl2 < int(def2.max) else "MAXED", affordable and _buy_rect.has_point(pointer) or (affordable and pointer.x < 0),
		20, Color(1, 0.85, 0.2) if affordable else Color(0.5, 0.4, 0.3))
	button_rect(_back_rect, "BACK", _back_rect.has_point(pointer), 20)
	var hint := "UP/DOWN select    ENTER buy    ESC back"
	if ui.input.active_mode() == "gamepad":
		hint = "D-PAD select    A buy    B back"
	UITheme.text(self, hint, 0, h - 22, 12, Color(0.45, 0.42, 0.3, 0.8), HORIZONTAL_ALIGNMENT_CENTER, w)
	UITheme.scanlines(self, size, Color(0, 0, 0, 0.1), 3.0)
	UITheme.vignette(self, size, 0.45)
