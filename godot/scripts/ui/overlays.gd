extends Control
## Held overlays: status HUD (Y / C), run stats (F2 / D-pad down), controls (F1), tactical map (RMB / LT).

var ui
var game
var _a_status := 0.0
var _a_stats := 0.0
var _a_controls := 0.0
var _a_map := 0.0
var _t := 0.0
var _raster_far := MapRaster.new()
var _raster_near := MapRaster.new()


func bind(p_ui, p_game) -> void:
	ui = p_ui
	game = p_game
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raster_far.setup(60, 0.35)      # Easy: whole known map (60 tiles each way)
	_raster_near.setup(10, 0.1)      # other difficulties: local 10-tile area
	visible = false


func frame(delta: float) -> void:
	_t += delta
	var inp: GameInput = game.input
	var playing: bool = game.state == "playing"
	var rate := delta * 9.0
	_a_status = move_toward(_a_status, 1.0 if (playing and inp.show_status) else 0.0, rate)
	_a_stats = move_toward(_a_stats, 1.0 if (playing and inp.show_run_stats) else 0.0, rate)
	_a_controls = move_toward(_a_controls, 1.0 if (playing and inp.show_controls) else 0.0, rate)
	_a_map = move_toward(_a_map, 1.0 if (playing and inp.alt_fire) else 0.0, rate)
	if _a_map > 0.0:
		var r := _raster_far if ui.difficulty == 1 else _raster_near
		r.refresh(game.map, game.player.tile_pos, _t)
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if _a_map > 0.01:
		_draw_tactical(w, h)
	if _a_status > 0.01:
		_draw_status(w, h)
	if _a_stats > 0.01:
		_draw_run_stats(w, h)
	if _a_controls > 0.01:
		_draw_controls(w, h)


func _panel(r: Rect2, a: float) -> void:
	UITheme.panel(self, r.grow(4), Color(0, 0, 0, 0.35 * a), Color(0, 0, 0, 0), 12)
	UITheme.panel(self, r, Color(0.02, 0.018, 0.01, 0.93 * a), Color(0.9, 0.8, 0.2, 0.6 * a), 8, 1)


func _row(x: float, y: float, label: String, value: String, a: float, vcol := Color.WHITE, lcol := Color(0.6, 0.6, 0.6), vx := 190.0) -> void:
	UITheme.text(self, label, x, y, 15, Color(lcol, a))
	UITheme.text(self, value, x + vx, y, 15, Color(vcol, a))


func _status_bar(r: Rect2, pct: float, col: Color, label: String, val: String, a: float) -> void:
	UITheme.panel(self, r, Color(0.15, 0.15, 0.15, a), Color(0, 0, 0, 0.5 * a), 3, 1)
	if pct > 0.0:
		UITheme.panel(self, Rect2(r.position, Vector2(maxf(3.0, r.size.x * clampf(pct, 0, 1)), r.size.y)), Color(col, 0.85 * a), Color(0, 0, 0, 0), 3)
	UITheme.text(self, label, r.position.x + 5, r.position.y + 1, 13, Color(1, 1, 1, a))
	UITheme.text(self, val, r.position.x, r.position.y + 1, 13, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 5)


func _draw_status(w: float, h: float) -> void:
	var a := _a_status
	var p = game.player
	var perks: Array = p.active_run_perks
	var pw := 340.0
	var ph := 300.0 + (20 + perks.size() * 15 if perks.size() > 0 else 0)
	var r := Rect2((w - pw) * 0.5, (h - ph) * 0.5 + (1.0 - a) * 14.0, pw, ph)
	_panel(r, a)
	var bx := r.position.x + 16
	var bw := pw - 32
	var y := r.position.y + 12
	var nm: String = ui.player_name.to_upper() if ui.player_name != "" else "STATUS"
	UITheme.head(self, nm, r.position.x, y, 22, Color(UITheme.GOLD, a), HORIZONTAL_ALIGNMENT_CENTER, pw)
	y += 30
	var hp: float = p.hp / p.max_hp
	_status_bar(Rect2(bx, y, bw, 16), hp, Color(1 - hp, hp, 0.1), "HEALTH", "%d/%d" % [int(p.hp), int(p.max_hp)], a)
	y += 20
	_status_bar(Rect2(bx, y, bw, 16), p.stamina / p.max_stamina, Color(0.2, 0.4, 0.9), "STAMINA", "%d/%d" % [int(p.stamina), int(p.max_stamina)], a)
	y += 20
	_status_bar(Rect2(bx, y, bw, 16), p.sanity / p.max_sanity, Color(0.6, 0.2, 0.8), "SANITY", "%d/%d" % [int(p.sanity), int(p.max_sanity)], a)
	y += 20
	_status_bar(Rect2(bx, y, bw, 16), p.hydration / p.max_hydration, Color(0.2, 0.7, 0.9), "HYDRATION", "%d/%d" % [int(p.hydration), int(p.max_hydration)], a)
	y += 20
	var bat: Dictionary = ui._battery()
	var bp: float = bat.pct
	_status_bar(Rect2(bx, y, bw, 16), bp, Color(0.2, 1, 0.3) if bp > 0.3 else Color(1, bp * 3.0, 0.3), "HEADLAMP", "%d%%" % int(bp * 100), a)
	y += 28
	UITheme.text(self, "Water: %d" % p.almond_water, bx, y, 15, Color(0.3, 0.8, 1, a))
	UITheme.text(self, "Med: %d" % p.bandages, bx + 82, y, 15, Color(0.3, 1, 0.3, a))
	UITheme.text(self, "Food: %d" % p.food, bx + 150, y, 15, Color(0.95, 0.75, 0.3, a))
	UITheme.text(self, "Bat: %d" % p.batteries, bx + 224, y, 15, Color(0.2, 1, 0.6, a))
	y += 24
	var wep: Dictionary = ui.weapon_info()
	UITheme.text(self, "Weapon: %s" % String(wep.get("name", "?")).to_upper(), bx, y, 15, Color(UITheme.color_of(wep.get("color", Color.WHITE)), a))
	if wep.get("type", "melee") == "ranged":
		UITheme.text(self, "Ammo: %d" % ui.ammo(), bx + 190, y, 15, Color(0.9, 0.7, 0.1, a))
	y += 24
	UITheme.text(self, "Bombs: %d/%d" % [ui._bomb_count(), ui.run_mods.max_bombs], bx, y, 15, Color(1, 0.5, 0.1, a))
	UITheme.text(self, "Bat: %d/%d" % [p.batteries, ui.run_mods.max_batteries], bx + 112, y, 15, Color(0.2, 1, 0.6, a))
	UITheme.text(self, "Level: %d" % p.level, bx + 226, y, 15, Color(UITheme.GOLD, a))
	y += 24
	UITheme.text(self, "Day %d  |  %s  |  Kills: %d" % [game.day, UITheme.fmt_time(game.run_time), game.kills], bx, y, 15, Color(0.7, 0.7, 0.7, a))
	y += 22
	if p.current_streak >= 3 or p.best_run_streak >= 5:
		UITheme.text(self, "Streak: %d  (Best: %d)" % [p.current_streak, p.best_run_streak], bx, y, 15, Color(1, 0.7, 0.2, a))
		var mult: float = p.get_streak_multiplier()
		if mult > 1.0:
			UITheme.text(self, "XP: %.1fx" % mult, bx + 226, y, 15, Color(0.3, 1, 0.3, a))
		y += 22
	if perks.size() > 0:
		y += 4
		UITheme.text(self, "PERKS:", bx, y, 14, Color(0.3, 0.9, 0.5, 0.8 * a))
		y += 16
		for pk in perks:
			UITheme.text(self, "  " + pk.name, bx, y, 13, Color(0.5, 0.8, 0.4, a))
			y += 15


func _draw_run_stats(w: float, h: float) -> void:
	var a := _a_stats
	var p = game.player
	var pw := 400.0
	var perks: Array = p.active_run_perks
	var ph := 420.0 + (perks.size() * 15 + 24 if perks.size() > 0 else 0)
	var r := Rect2((w - pw) * 0.5, maxf(8.0, (h - ph) * 0.5) + (1.0 - a) * 14.0, pw, ph)
	_panel(r, a)
	var c1 := r.position.x + 24
	var y := r.position.y + 14
	UITheme.head(self, "RUN STATS", r.position.x, y, 26, Color(UITheme.GOLD, a), HORIZONTAL_ALIGNMENT_CENTER, pw)
	y += 38
	var dcol: Color = UITheme.DIFF_COLORS[ui.difficulty - 1]
	_row(c1, y, "Subject", ui.player_name if ui.player_name != "" else "?", a, UITheme.GOLD, Color(0.5, 0.5, 0.5))
	y += 20
	_row(c1, y, "Difficulty", UITheme.DIFF_NAMES[ui.difficulty - 1], a, dcol, Color(0.5, 0.5, 0.5))
	y += 26
	_row(c1, y, "Day", str(game.day), a, Color(1, 0.9, 0.3))
	y += 20
	_row(c1, y, "Time", UITheme.fmt_time(game.run_time), a)
	y += 20
	_row(c1, y, "Level", str(p.level), a, UITheme.GOLD)
	y += 20
	var xp_pct := int(float(p.xp) / maxf(p.xp_need, 1.0) * 100.0)
	_row(c1, y, "XP", "%d/%d (%d%%)" % [p.xp, p.xp_need, xp_pct], a, Color(0.6, 0.8, 1))
	y += 26
	_row(c1, y, "Kills", str(game.kills), a, Color(1, 0.4, 0.3))
	y += 20
	var mult: float = p.get_streak_multiplier()
	var st := str(p.current_streak)
	if mult > 1.0:
		st += " (%.1fx XP)" % mult
	_row(c1, y, "Streak", st, a, Color(1, 0.7, 0.2))
	y += 20
	_row(c1, y, "Best Streak", str(p.best_run_streak), a, Color(1, 0.5, 0.1))
	y += 26
	_row(c1, y, "HP", "%d/%d" % [int(p.hp), int(p.max_hp)], a, Color(1, 0.3, 0.3) if p.hp < p.max_hp * 0.3 else Color(0.3, 1, 0.3))
	y += 20
	_row(c1, y, "Stamina", "%d/%d" % [int(p.stamina), int(p.max_stamina)], a)
	y += 20
	_row(c1, y, "Sanity", "%d/%d" % [int(p.sanity), int(p.max_sanity)], a, Color(0.8, 0.3, 1) if p.sanity < 40 else Color.WHITE)
	y += 20
	_row(c1, y, "Ammo", str(ui.ammo()), a, Color(0.9, 0.7, 0.1))
	y += 20
	_row(c1, y, "Bandages", str(p.bandages), a, Color(0.3, 1, 0.3))
	y += 20
	_row(c1, y, "Almond Water", str(p.almond_water), a, Color(0.3, 0.8, 1))
	y += 20
	if perks.size() > 0:
		y += 6
		UITheme.text(self, "PERKS:", c1, y, 14, Color(0.3, 0.9, 0.5, 0.8 * a))
		y += 18
		for pk in perks:
			UITheme.text(self, "  " + pk.name, c1, y, 13, Color(0.5, 0.8, 0.4, a))
			y += 15
	var portal: Dictionary = ui._portal()
	if not portal.is_empty() or ui.portal_declined:
		y += 4
		if ui.portal_declined or (not portal.is_empty() and not portal.active):
			UITheme.text(self, "Portal: DECLINED (Living Legend)", c1, y, 15, Color(0.5, 0.5, 0.5, a))
		elif portal.guards > 0:
			_row(c1, y, "Portal", "%d guards remain" % portal.guards, a, Color(1, 0.4, 0.2))
		else:
			_row(c1, y, "Portal", "CLEAR - approach to escape", a, Color(0.2, 1, 0.5))
	var key := "Release D-Down" if game.input.active_mode() == "gamepad" else "Release F2"
	UITheme.text(self, "%s to close" % key, r.position.x, r.end.y - 22, 12, Color(0.4, 0.4, 0.4, a), HORIZONTAL_ALIGNMENT_CENTER, pw)


func _draw_controls(w: float, h: float) -> void:
	var a := _a_controls
	var scheme: Dictionary = game.input.scheme()
	var controls: Array = scheme.controls
	var row_h := 24.0
	var pw := 420.0
	var ph := row_h * controls.size() + 64.0
	var r := Rect2((w - pw) * 0.5, (h - ph) * 0.5 + (1.0 - a) * 14.0, pw, ph)
	_panel(r, a)
	UITheme.head(self, String(scheme.name).to_upper(), r.position.x, r.position.y + 10, 24, Color(UITheme.GOLD, a), HORIZONTAL_ALIGNMENT_CENTER, pw)
	UITheme.line_sep(self, r.position.x + 15, r.end.x - 15, r.position.y + 42, Color(0.4, 0.35, 0.2, 0.6 * a))
	var y := r.position.y + 50
	for c in controls:
		UITheme.text(self, c[0], r.position.x + 20, y, 14, Color(1, 0.95, 0.7, a))
		UITheme.text(self, c[1], r.position.x, y, 14, Color(0.65, 0.65, 0.65, a), HORIZONTAL_ALIGNMENT_RIGHT, pw - 20)
		y += row_h


func _draw_tactical(w: float, h: float) -> void:
	var a := _a_map
	var p = game.player
	var diff: int = ui.difficulty
	# Easy: whole map, enemies, items. Normal: local area + enemies. Getting Worse / Hell: local area only.
	var show_enemies := diff <= 2
	var raster := _raster_far if diff == 1 else _raster_near
	draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.85 * a))
	var ms := minf(w, h) - 80.0
	var r := Rect2((w - ms) * 0.5, (h - ms) * 0.5, ms, ms)
	UITheme.panel(self, r.grow(4), Color(0.05, 0.04, 0.02, 0.95 * a), Color(0.4, 0.35, 0.2, 0.8 * a), 6, 2)
	raster.draw(self, r, p.tile_pos, a)
	var center: Vector2 = p.tile_pos
	var k := ms / float(raster.half * 2)

	for chest in game.map.chest_rooms:
		if chest.looted:
			continue
		var cp: Vector2 = r.get_center() + (chest.pos - center) * k
		if r.has_point(cp):
			var pulse := 0.5 + 0.5 * sin(_t * 3.0)
			draw_circle(cp, 12.0 + pulse * 4.0, Color(0.9, 0.7, 0.1, (0.18 + 0.1 * pulse) * a))
			draw_circle(cp, 5.0, Color(1, 0.85, 0.2, 0.95 * a))
	var portal: Dictionary = ui._portal()
	if not portal.is_empty() and portal.active:
		var pp: Vector2 = r.get_center() + (portal.pos - center) * k
		var col := Color(0.2, 1, 0.7, a)
		if r.has_point(pp):
			var pulse2 := 0.5 + 0.5 * sin(_t * 4.0)
			draw_arc(pp, 8.0 + pulse2 * 5.0, 0, TAU, 24, col, 2.5)
			draw_circle(pp, 5.0, col)
			UITheme.text(self, "EXIT", pp.x - 20, pp.y - 26, 13, col, HORIZONTAL_ALIGNMENT_CENTER, 40)
		else:
			var dir := (pp - r.get_center()).normalized()
			var edge := r.get_center() + dir * (ms * 0.5 - 14.0)
			var perp := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([edge + dir * 10.0, edge - dir * 5.0 + perp * 8.0, edge - dir * 5.0 - perp * 8.0]), col)
	if diff <= 2:
		for m in ui._map_markers():
			var mp: Vector2 = r.get_center() + (m.pos - center) * k
			if r.has_point(mp):
				var mc := UITheme.color_of(m.get("color", Color.WHITE))
				draw_circle(mp, 3.0, Color(mc, 0.85 * a))
	if show_enemies and game.enemies and game.enemies.has_method("get_enemies"):
		for e in game.enemies.get_enemies():
			var ep: Vector2 = r.get_center() + (e.tile_pos - center) * k
			if r.has_point(ep):
				var ec: Color = e.color if "color" in e and e.color is Color else Color(1, 0.3, 0.25)
				draw_circle(ep, 6.0, Color(ec, 0.3 * a))
				draw_circle(ep, 3.0, Color(ec, 0.9 * a))
	var pulse3 := 0.7 + 0.3 * sin(_t * 4.0)
	var pc := r.get_center()
	draw_circle(pc, 14.0, Color(0.9, 0.8, 0.2, 0.25 * pulse3 * a))
	draw_circle(pc, 9.0, Color(0.9, 0.8, 0.2, 0.5 * pulse3 * a))
	draw_circle(pc, 5.0, Color(1, 0.95, 0.5, a))
	if diff <= 2:
		draw_line(pc, pc + Vector2(p.fx, p.fy) * 18.0, Color(1, 0.95, 0.7, 0.7 * a), 2.0)
	var cc := Color(0.5, 0.45, 0.2, 0.6 * a)
	UITheme.text(self, "N", r.position.x, r.position.y - 24, 14, cc, HORIZONTAL_ALIGNMENT_CENTER, ms)
	UITheme.text(self, "S", r.position.x, r.end.y + 6, 14, cc, HORIZONTAL_ALIGNMENT_CENTER, ms)
	UITheme.text(self, "W", r.position.x - 20, r.get_center().y - 8, 14, cc)
	UITheme.text(self, "E", r.end.x + 8, r.get_center().y - 8, 14, cc)
	UITheme.head(self, "TACTICAL MAP  |  Day %d  |  %s" % [game.day, UITheme.DIFF_NAMES[diff - 1]], 0, r.position.y - 52, 22,
		Color(0.9, 0.8, 0.2, 0.8 * a), HORIZONTAL_ALIGNMENT_CENTER, w)
	var hint := "Hold LT / Right Click to view"
	UITheme.text(self, hint, 0, r.end.y + 24, 12, Color(0.5, 0.5, 0.5, 0.6 * a), HORIZONTAL_ALIGNMENT_CENTER, w)
