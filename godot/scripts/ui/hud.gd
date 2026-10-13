extends Control
## In-game HUD (drawHud / drawMessages / minimap / crosshair / sanity + low-health screen effects).
## Pure screen-space drawing on a CanvasLayer; reads everything from game.player and the optional systems.

const BAR_W := 236.0
const BAR_H := 20.0
const BAR_GAP := 5.0
const FS := 14
const MINI_SIZE := 124.0
const PHONE_MINI_SIZE := 140.0

var ui
var game
var _t := 0.0
var _mode := "keyboard"
var _disp := {}                # smoothed bar values
var _ghost := {}               # damage trail
var _pop := {"kill": 0.0, "level": 0.0, "streak": 0.0, "weapon": 0.0, "dmg": 0.0}
var _shake := 0.0
var _mini := MapRaster.new()
var _last_kills := 0
var _fire_kick := 0.0
var _rng := RandomNumberGenerator.new()


func bind(p_ui, p_game) -> void:
	ui = p_ui
	game = p_game
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini.setup(20, 0.15)
	visible = false


func reset() -> void:
	_disp.clear()
	_ghost.clear()
	for k in _pop:
		_pop[k] = 0.0
	_shake = 0.0


func pop_kill() -> void:
	_pop.kill = 0.35


func pop_level() -> void:
	_pop.level = 1.0


func pop_streak() -> void:
	_pop.streak = 1.0


func pop_weapon() -> void:
	_pop.weapon = 0.4


func pop_damage() -> void:
	_pop.dmg = 0.5
	_shake = 0.35


func frame(delta: float) -> void:
	_t += delta
	for k in _pop:
		_pop[k] = maxf(0.0, _pop[k] - delta * (0.6 if k == "level" or k == "streak" else 1.0))
	_shake = maxf(0.0, _shake - delta)
	if game.state == "playing" and game.input and game.input.fire:
		_fire_kick = 1.0
	_fire_kick = maxf(0.0, _fire_kick - delta * 6.0)
	if game.state in ["playing", "paused", "perk", "portal"]:
		_mini.refresh(game.map, game.player.tile_pos, _t)
	queue_redraw()


# ---- helpers ---------------------------------------------------------------------------------------

func _sm(key: String, target: float, speed := 10.0) -> float:
	var cur: float = _disp.get(key, target)
	cur = lerpf(cur, target, clampf(get_process_delta_time() * speed, 0.0, 1.0))
	if absf(cur - target) < 0.0005:
		cur = target
	_disp[key] = cur
	# ghost trail follows down slowly
	var gh: float = _ghost.get(key, target)
	if target >= gh:
		gh = target
	else:
		gh = move_toward(gh, target, get_process_delta_time() * 0.25)
	_ghost[key] = gh
	return cur


func _bar(x: float, y: float, key: String, pct: float, col: Color, label: String, value: String = "", alert := false) -> void:
	var v := _sm(key, clampf(pct, 0.0, 1.0))
	var r := Rect2(x, y, BAR_W, BAR_H)
	UITheme.bar(self, r, v, col, _ghost[key])
	if alert:
		var pa := 0.35 + 0.35 * sin(_t * 9.0)
		UITheme.panel(self, r.grow(1), Color(0, 0, 0, 0), Color(1, 0.2, 0.2, pa), 4, 2)
	var ty := y + (BAR_H - UITheme.text_h(FS)) * 0.5 - 1
	UITheme.text(self, label, x + 6, ty, FS, Color.WHITE)
	if value != "":
		UITheme.text(self, value, x, ty, FS, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_RIGHT, BAR_W - 6)


func _draw() -> void:
	if game == null or game.player == null:
		return
	var w0 := size.x
	var h0 := size.y
	var p = game.player
	var mode: String = game.input.active_mode() if game.input else "keyboard"
	_mode = mode
	_draw_screen_fx(w0, h0, p)               # full-screen effects ignore the UI scale
	# everything below is laid out in a canvas of (size / s) px and magnified by s (Options > UI Scale)
	var s: float = ui.hud_scale()
	var w := w0 / s
	var h := h0 / s
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	var lefty_phone: bool = ui.is_phone_ui() and mode == "touch" and game.input.opts().touch_left_handed
	_draw_left_panel(p, mode, (w - 6.0 - (BAR_W + 16.0)) - 6.0 if lefty_phone else 0.0)
	if mode != "touch":
		_draw_bottom_left(h, p)       # on touch the counts live on the buttons
	_draw_right_panel(w, p, -(w - 196.0) + 8.0 if lefty_phone else 0.0)
	_draw_effects(w)
	_draw_minimap(w, h, p, mode)
	_draw_banners(w, h, p)
	_draw_messages(w, h)
	if mode != "touch":
		var m := "CONTROLLER" if mode == "gamepad" else mode.to_upper()
		UITheme.text(self, m, 12, h - 20, 12, Color(0.6, 0.6, 0.6, 0.45))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if mode == "keyboard" and game.state == "playing":
		_draw_crosshair()
	if ui.intro_t > 0.0:
		_draw_intro(w0, h0)


func _draw_left_panel(p, _m: String, ox := 0.0) -> void:
	var x := 14.0 + ox
	var y := 14.0
	var rows := 6
	var ph := rows * (BAR_H + BAR_GAP) + 34.0
	UITheme.panel(self, Rect2(x - 8, y - 8, BAR_W + 16, ph), Color(0, 0, 0, 0.62), Color(0.9, 0.8, 0.2, 0.18), 6, 1)
	var sx := 0.0
	if _shake > 0.0:
		sx = sin(_shake * 90.0) * 4.0 * (_shake / 0.35)
	var hp: float = p.hp / maxf(p.max_hp, 1.0)
	_bar(x + sx, y, "hp", hp, Color(1.0 - hp * 0.8, 0.15 + hp * 0.75, 0.1), "HP", "%d / %d" % [int(p.hp), int(p.max_hp)], hp < 0.3)
	y += BAR_H + BAR_GAP
	_bar(x, y, "st", p.stamina / maxf(p.max_stamina, 1.0), Color(0.2, 0.4, 0.9), "STAMINA", "%d" % int(p.stamina), (p.stamina < 8.0 and p.sprinting) or (game.input != null and game.input.refused_t > 0.0))
	y += BAR_H + BAR_GAP
	var sn: float = p.sanity / maxf(p.max_sanity, 1.0)
	_bar(x, y, "sn", sn, Color(0.6, 0.2, 0.8), "SANITY", "%d" % int(p.sanity), sn < 0.25)
	y += BAR_H + BAR_GAP
	var hy: float = p.hydration / maxf(p.max_hydration, 1.0)
	_bar(x, y, "hy", hy, Color(0.2, 0.7, 0.9), "H2O", "%d" % int(p.hydration), hy <= 0.0)
	y += BAR_H + BAR_GAP
	var bat: Dictionary = ui._battery()
	var bp: float = bat.pct
	var bcol := Color(0.2, 1, 0.3) if bp > 0.3 else Color(1, bp * 3.0, 0.3)
	_bar(x, y, "bt", bp, bcol, "LAMP %s" % ("ON" if bat.on else "OFF"), "%d%%" % int(bp * 100.0), bp <= 0.0 and bat.on)
	y += BAR_H + BAR_GAP
	# XP bar with level label
	var xp_pct: float = float(p.xp) / maxf(float(p.xp_need), 1.0)
	var xv := _sm("xp", xp_pct, 8.0)
	var r := Rect2(x, y, BAR_W, BAR_H)
	UITheme.bar(self, r, xv, Color(0.9, 0.7, 0.1))
	if _pop.level > 0.0:
		UITheme.panel(self, r.grow(2.0 * _pop.level), Color(1, 0.9, 0.3, 0.4 * _pop.level), Color(1, 0.9, 0.3, _pop.level), 5, 2)
	UITheme.text(self, "LV %d" % p.level, x, y + (BAR_H - UITheme.text_h(FS)) * 0.5 - 1, FS, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, BAR_W)
	y += BAR_H + BAR_GAP + 3.0
	# quick items: key / button names follow the (rebindable) bindings of the active scheme; 0 left = dimmed
	var inp: GameInput = game.input
	var keys := ["", "", ""]
	var acts := ["use_water", "use_bandage", "use_food"]
	if _mode == "keyboard":
		for i in 3:
			keys[i] = "[%s] " % inp.key_name(inp.key_of(acts[i]))
	elif _mode == "gamepad":
		for i in 3:
			keys[i] = "[%s] " % inp.pad_short(inp.pad_of(acts[i]))
	var qs := [["%sH2O %d" % [keys[0], p.almond_water], p.almond_water, Color(0.3, 0.8, 1)],
		["%sMED %d" % [keys[1], p.bandages], p.bandages, Color(0.3, 1, 0.3)],
		["%sFOOD %d" % [keys[2], p.food], p.food, Color(0.95, 0.75, 0.3)]]
	var qtotal := 0.0
	for q in qs:
		qtotal += UITheme.text_w(q[0], FS)
	var qfs := FS
	var qgap := 12.0
	if qtotal + qgap * 2.0 > BAR_W:
		qfs = UITheme.MIN_FS
		qgap = 8.0
	var qx := x
	for q in qs:
		var qc: Color = q[2] if q[1] > 0 else Color(0.45, 0.45, 0.45)
		qx += UITheme.text(self, q[0], qx, y, qfs, qc) + qgap


func _draw_bottom_left(h: float, p) -> void:
	var r := Rect2(10, h - 52, 168, 34)
	UITheme.panel(self, r, Color(0, 0, 0, 0.62), Color(0.9, 0.8, 0.2, 0.18), 6, 1)
	UITheme.text(self, "AMMO: %d" % ui.ammo(), r.position.x + 10, r.position.y + 8, 15, Color(0.9, 0.7, 0.1) if ui.ammo() > 0 else Color(0.5, 0.45, 0.35))
	UITheme.text(self, "BAT: %d" % p.batteries, r.position.x + 98, r.position.y + 8, 15, Color(0.2, 1, 0.6) if p.batteries > 0 else Color(0.4, 0.5, 0.45))


func _draw_right_panel(w: float, p, ox := 0.0) -> void:
	var pw := 176.0
	var x := w - pw - 12.0 + ox
	var y := 12.0
	var r := Rect2(x - 8, y - 4, pw + 12, 112)
	UITheme.panel(self, r, Color(0, 0, 0, 0.62), Color(0.9, 0.8, 0.2, 0.18), 6, 1)
	UITheme.text(self, "Day %d  %s" % [game.day, UITheme.fmt_time(game.run_time)], x, y, 15, Color(0.9, 0.8, 0.2))
	var wep: Dictionary = ui.weapon_info()
	var wcol := UITheme.color_of(wep.get("color", Color.WHITE))
	var why: String = ui.attack_state()
	if why != "":
		wcol = wcol.lerp(Color(0.4, 0.4, 0.4), 0.7)          # can't attack right now: dim the weapon
	var wpop: float = _pop.weapon
	var wfs := 15 + int(wpop * 12.0)
	UITheme.text(self, String(wep.get("name", "?")).to_upper(), x, y + 20 - wpop * 4.0, wfs, wcol)
	if why == "stamina":
		UITheme.text(self, "NO STAMINA", x, y + 40, FS, Color(1, 0.5, 0.2, 0.7 + 0.3 * sin(_t * 12.0)))
	elif why == "ammo":
		UITheme.text(self, "NO AMMO", x, y + 40, FS, Color(1, 0.3, 0.2, 0.7 + 0.3 * sin(_t * 12.0)))
	elif wep.get("type", "melee") == "ranged":
		UITheme.text(self, "AMMO: %d" % ui.ammo(), x, y + 40, FS, Color(0.9, 0.7, 0.1))
	else:
		UITheme.text(self, "MELEE", x, y + 40, FS, Color(0.6, 0.6, 0.6))
	var kp: float = _pop.kill
	UITheme.text(self, "Kills %d" % game.kills, x, y + 56 - kp * 3.0, FS + int(kp * 8.0), Color(0.75, 0.75, 0.75).lerp(Color.WHITE, kp * 2.0))
	if p.current_streak >= 3:
		var mult: float = p.get_streak_multiplier()
		var txt := "x%d" % p.current_streak
		if mult > 1.0:
			txt += " %.1fx" % mult
		var col := Color(1, 0.7, 0.2, 0.9)
		if p.streak_display_timer > 0.0:
			var fl := sin(_t * 10.0) * 0.3 + 0.7
			col = Color(1, 0.5 * fl, 0.1)
		UITheme.text(self, txt, x + 96, y + 56, FS + (3 if p.streak_display_timer > 0.0 else 0), col)
	# noise meter
	var nz := clampf(p.noise / 100.0, 0.0, 1.0)
	UITheme.panel(self, Rect2(x, y + 78, 78, 9), Color(0.15, 0.15, 0.15, 0.9), Color(0, 0, 0, 0.5), 3, 1)
	if nz > 0.0:
		UITheme.panel(self, Rect2(x, y + 78, maxf(3.0, 78 * nz), 9), Color(nz, 1.0 - nz * 0.8, 0.1), Color(0, 0, 0, 0), 3)
	UITheme.text(self, "NOISE", x + 84, y + 74, 12, Color(0.7, 0.7, 0.7))
	UITheme.text(self, "BOMB x%d" % ui._bomb_count(), x, y + 92, FS, Color(1, 0.5, 0.1) if ui._bomb_count() > 0 else Color(0.5, 0.4, 0.35))
	UITheme.text(self, UITheme.DIFF_NAMES[ui.difficulty - 1], x + 80, y + 92, FS, UITheme.DIFF_COLORS[ui.difficulty - 1])


func _draw_effects(w: float) -> void:
	var fx: Array = ui._effects()
	if fx.is_empty():
		return
	var ex := w - 188.0
	var ey := 134.0
	if ui.is_phone_ui() and _mode == "touch":
		var mr: Rect2 = _phone_rects(w).mini
		ex = mr.end.x - 176.0                          # under the minimap, right-aligned to it
		ey = mr.end.y + 8.0
	UITheme.panel(self, Rect2(ex, ey, 176, fx.size() * 18 + 8), Color(0, 0, 0, 0.62), Color(0, 0, 0, 0), 5)
	for i in fx.size():
		var e = fx[i]
		var good: bool = e.get("good", e.get("is_good", true))
		var c := Color(0.3, 1, 0.3) if good else Color(1, 0.3, 0.3)
		var rem: float = float(e.get("remaining", 0.0))
		var pct := minf(1.0, rem / 30.0)
		var y := ey + 6 + i * 18
		draw_rect(Rect2(ex + 4, y, 100, 12), c * 0.3)
		draw_rect(Rect2(ex + 4, y, 100 * pct, 12), Color(c, 0.7))
		UITheme.text(self, str(e.get("text", "")), ex + 8, y - 2, 12, Color.WHITE)
		UITheme.text(self, "%ds" % int(rem), ex + 110, y - 2, 12, Color(0.7, 0.7, 0.7))
		if rem < 5.0 and sin(_t * 8.0) > 0.0:
			draw_rect(Rect2(ex + 4, y, 100, 12), Color(1, 1, 0, 0.3))


## Phone HUD geometry in HUD canvas units (before the UI scale): stats panel, info panel and the minimap between them.
## Left-handed play mirrors the two panels (the mirrored button cluster would otherwise sit under the stats panel).
## `pause` = the touch pause button (x centre, radius) in the same units, so the minimap never covers it.
## One source of truth for the drawing code and for the overlap test in tools/regression_tests.gd.
static func phone_rects(w: float, left_handed := false, pause_x := -1.0, pause_r := 0.0) -> Dictionary:
	var left_h := 6.0 * (BAR_H + BAR_GAP) + 34.0
	var stats := Rect2(6.0, 6.0, BAR_W + 16.0, left_h)
	var info := Rect2(w - 196.0, 8.0, 188.0, 112.0)
	if left_handed:
		stats.position.x = w - 6.0 - stats.size.x
		info.position.x = 8.0
	var span_l := (info.end.x if left_handed else stats.end.x) + 8.0
	var span_r := (stats.position.x if left_handed else info.position.x) - 8.0
	var x0 := span_l
	var x1 := span_r
	if pause_x >= 0.0:
		var left_free := (pause_x - pause_r - 6.0) - span_l
		var right_free := span_r - (pause_x + pause_r + 6.0)
		if right_free >= left_free:
			x0 = pause_x + pause_r + 6.0
		else:
			x1 = pause_x - pause_r - 6.0
	var ms := clampf(x1 - x0 - 6.0, 90.0, PHONE_MINI_SIZE)
	var mini := Rect2(Vector2(x0 + 3.0 + maxf(0.0, (x1 - x0 - 6.0 - ms) * 0.5), 12.0), Vector2(ms, ms))
	return {"stats": stats, "mini": mini.grow(3.0), "info": info, "mini_size": ms}


## Android phone HUD: the minimap and effect list live in the top strip between the pause button and the info panel
## (the corners below are taken by the sticks and buttons). Returns the minimap rect origin.
func _phone_rects(w: float) -> Dictionary:
	var lay: Dictionary = game.input.touch_layout()
	var s: float = ui.hud_scale()
	var px := -1.0
	var pr := 0.0
	for b in lay.buttons:
		if b.action == "pause":
			px = b.pos.x / s
			pr = b.r / s
	return phone_rects(w, game.input.opts().touch_left_handed, px, pr)


func _draw_minimap(w: float, h: float, p, mode: String) -> void:
	var phone: bool = ui.is_phone_ui() and mode == "touch"
	var s := MINI_SIZE
	var mk := 1.0                                      # marker size factor: chests, portal, enemies and the player must read on a phone
	var pos := Vector2(w - s - 14.0, h - s - 14.0)
	if phone:
		var mr: Rect2 = _phone_rects(w).mini.grow(-3.0)
		s = mr.size.x
		pos = mr.position
		mk = 1.5
	elif mode == "touch":
		pos = Vector2(14.0, 232.0)
		if game.input.opts().touch_left_handed:
			pos = Vector2(w - s - 14.0, 150.0)     # the mirrored button cluster occupies the left edge
	var r := Rect2(pos, Vector2(s, s))
	UITheme.panel(self, r.grow(3), Color(0, 0, 0, 0.8), Color(0.4, 0.35, 0.2, 0.8), 5, 1)
	_mini.draw(self, r, game.player.tile_pos, 0.95)
	var center: Vector2 = p.tile_pos
	var scale_px := s / float(_mini.half * 2)
	var clip_r := r
	# chest rooms (golden glow)
	for chest in game.map.chest_rooms:
		if chest.looted:
			continue
		var cp := _to_mini(r, center, chest.pos, scale_px)
		if clip_r.has_point(cp):
			var pulse := 0.5 + 0.5 * sin(_t * 3.0)
			draw_circle(cp, (7.0 + pulse * 2.0) * mk, Color(0.9, 0.7, 0.1, 0.18 + 0.12 * pulse))
			draw_circle(cp, 3.0 * mk, Color(1, 0.85, 0.2, 0.95))
	# portal marker
	var portal: Dictionary = ui._portal()
	if not portal.is_empty() and portal.active:
		var pp := _to_mini(r, center, portal.pos, scale_px)
		var col := Color(0.2, 1, 0.7)
		if clip_r.has_point(pp):
			var pulse2 := 0.5 + 0.5 * sin(_t * 4.0)
			draw_arc(pp, (5.0 + pulse2 * 3.0) * mk, 0, TAU, 20, Color(col, 0.8), 2.0)
			draw_circle(pp, 3.0 * mk, col)
		else:
			var dir := (pp - r.get_center()).normalized()
			var edge := r.get_center() + dir * (s * 0.5 - 6.0)
			var perp := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([edge + dir * 6.0, edge - dir * 3.0 + perp * 5.0, edge - dir * 3.0 - perp * 5.0]), col)
	# extra markers from the objects system and enemies (easy/normal only)
	for m in ui._map_markers():
		var mp := _to_mini(r, center, m.pos, scale_px)
		if clip_r.has_point(mp):
			var dot := Rect2(mp - Vector2(1.6, 1.6) * mk, Vector2(3.2, 3.2) * mk)
			draw_rect(dot.grow(0.9 * mk), Color(0, 0, 0, 0.75))               # dark rim so a dot reads on any floor
			draw_rect(dot, UITheme.color_of(m.get("color", Color.WHITE)))
	if ui.difficulty <= 2 and game.enemies and game.enemies.has_method("get_enemies"):
		for e in game.enemies.get_enemies():
			var ep := _to_mini(r, center, e.tile_pos, scale_px)
			if clip_r.has_point(ep):
				var ec: Color = e.color if "color" in e and e.color is Color else Color(1, 0.3, 0.25)
				draw_rect(Rect2(ep - Vector2(1, 1) * mk, Vector2(2.5, 2.5) * mk), ec)
	# player marker + facing
	var pc := r.get_center()
	draw_line(pc, pc + Vector2(p.fx, p.fy) * 9.0 * mk, Color(1, 0.95, 0.7, 0.8), 1.5 * mk)
	draw_circle(pc, 3.0 * mk, Color(0.9, 0.8, 0.2))


func _to_mini(r: Rect2, center: Vector2, tile: Vector2, scale_px: float) -> Vector2:
	return r.get_center() + (tile - center) * scale_px


func _draw_banners(w: float, h: float, p) -> void:
	if p.streak_display_timer > 0.0 and p.current_streak >= 5:
		var pop: float = 1.0 + 0.5 * _pop.streak
		var fs := int(34 * pop)
		var a := clampf(p.streak_display_timer / 0.5, 0.0, 1.0)
		UITheme.head(self, "%d KILL STREAK" % p.current_streak, 0, h * 0.2, fs, Color(1, 0.55, 0.15, a), HORIZONTAL_ALIGNMENT_CENTER, w)
		UITheme.text(self, "%.1fx XP" % p.get_streak_multiplier(), 0, h * 0.2 + fs + 2, 16, Color(1, 0.8, 0.4, a), HORIZONTAL_ALIGNMENT_CENTER, w)


func _draw_messages(w: float, h: float) -> void:
	var y := h * 0.5 - 20.0
	var n: int = ui.messages.size()
	var shown := 0
	var i := n - 1
	while i >= 0 and shown < 6:
		var m: Dictionary = ui.messages[i]
		var fade := clampf((m.life - m.age) / 1.0, 0.0, 1.0)
		var enter := clampf(m.age / 0.15, 0.0, 1.0)
		var col: Color = m.color
		col.a = fade
		var fs := 18 + int((1.0 - enter) * 10.0)
		UITheme.text(self, m.text, 0, y - (1.0 - enter) * 8.0, fs, col, HORIZONTAL_ALIGNMENT_CENTER, w)
		y -= 22.0
		shown += 1
		i -= 1


func _draw_crosshair() -> void:
	var mp := get_viewport().get_mouse_position()
	var spread := 4.0 + _fire_kick * 5.0
	var col := Color(1, 0.3, 0.2, 0.85)
	draw_line(mp + Vector2(-10 - _fire_kick * 4, 0), mp + Vector2(-spread, 0), col, 2.0)
	draw_line(mp + Vector2(spread, 0), mp + Vector2(10 + _fire_kick * 4, 0), col, 2.0)
	draw_line(mp + Vector2(0, -10 - _fire_kick * 4), mp + Vector2(0, -spread), col, 2.0)
	draw_line(mp + Vector2(0, spread), mp + Vector2(0, 10 + _fire_kick * 4), col, 2.0)
	draw_arc(mp, 3.0, 0, TAU, 12, col, 1.5)


func _draw_intro(w: float, h: float) -> void:
	var tl: float = ui.intro_t
	var a := clampf(tl / 3.0, 0.0, 1.0)
	draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, pow(a, 1.4)))
	_rng.seed = int(_t * 20.0)
	for i in int(300 * a):
		draw_rect(Rect2(_rng.randf() * w, _rng.randf() * h, 2, 2), Color(_rng.randf() * 0.3, 0, 0, a))
	var nm: String = ui.player_name if ui.player_name != "" else "Subject"
	if tl > 1.5:
		var shake := sin(_t * 1.5) * 3.0
		UITheme.head(self, "NOCLIP DETECTED", shake, h * 0.5 - 30, 36, Color(0.8, 0.8, 0.2, a), HORIZONTAL_ALIGNMENT_CENTER, w)
	elif tl > 0.4:
		UITheme.head(self, "%s HAS ENTERED THE BACKROOMS" % nm.to_upper(), 0, h * 0.5 - 30, 36, Color(0.8, 0.7, 0.1, minf(1.0, a * 2.0)),
			HORIZONTAL_ALIGNMENT_CENTER, w)
	UITheme.text(self, "%s MODE  |  Subject: %s" % [String(UITheme.DIFF_NAMES[ui.difficulty - 1]).to_upper(), nm], 0, h * 0.5 + 20, 16,
		Color(0.5, 0.45, 0.2, a * 0.7), HORIZONTAL_ALIGNMENT_CENTER, w)


func _draw_screen_fx(w: float, h: float, p) -> void:
	# damage flash: thin red edges (the full-screen flash comes from game.fx)
	if p.dmg_flash > 0.0:
		var a := clampf(p.dmg_flash * 1.6, 0.0, 0.5)
		var e := 46.0
		draw_rect(Rect2(0, 0, w, e), Color(0.8, 0, 0, a))
		draw_rect(Rect2(0, h - e, w, e), Color(0.8, 0, 0, a))
		draw_rect(Rect2(0, 0, e, h), Color(0.8, 0, 0, a))
		draw_rect(Rect2(w - e, 0, e, h), Color(0.8, 0, 0, a))
	# low health: pulsing blood vignette
	var hp: float = p.hp / maxf(p.max_hp, 1.0)
	if hp < 0.3 and game.state == "playing":
		var rate := 2.0 + (0.3 - hp) * 14.0
		var beat := pow(maxf(0.0, sin(_t * rate)), 6.0)
		UITheme.vignette(self, Vector2(w, h), (0.18 + 0.4 * beat) * (1.0 - hp / 0.3 * 0.5), Color(0.6, 0, 0))
	# sanity < 40: purple frame (Lua)
	if p.sanity < 40.0:
		var inten: float = (40.0 - p.sanity) / 40.0
		var c := Color(0.15, 0, 0.2, inten * 0.4)
		draw_rect(Rect2(0, 0, w, 40), c)
		draw_rect(Rect2(0, h - 40, w, 40), c)
		draw_rect(Rect2(0, 0, 40, h), c)
		draw_rect(Rect2(w - 40, 0, 40, h), c)
	# VCR tracking distortion below 25% sanity (Lua)
	var spct: float = p.sanity / maxf(p.max_sanity, 1.0)
	if spct < 0.25:
		var inten2 := 1.0 - spct / 0.25
		var band_count := int(3 + inten2 * 8)
		for i in band_count:
			var seed_v := i * 137.5 + _t * (0.3 + inten2 * 0.7)
			var by := (sin(seed_v * 0.7) * 0.5 + 0.5) * h
			var bh := 2.0 + randf() * (3.0 + inten2 * 6.0)
			var ba := 0.08 + inten2 * 0.18
			if sin(seed_v * 3.7) > 0.0:
				draw_rect(Rect2(0, by, w, bh), Color(1, 1, 1, ba))
			else:
				draw_rect(Rect2(0, by, w, bh), Color(0, 0, 0, ba * 1.5))
		var roll_speed := 0.4 + inten2 * 0.8
		var roll_y := fposmod(_t * roll_speed * h, h * 1.4) - h * 0.2
		var roll_h := 30.0 + inten2 * 50.0
		var ra := 0.06 + inten2 * 0.15
		draw_rect(Rect2(0, roll_y, w, roll_h), Color(0.1, 0, 0.15, ra))
		draw_rect(Rect2(0, roll_y, w, 2), Color(1, 1, 1, ra * 0.6))
		draw_rect(Rect2(0, roll_y + roll_h - 1, w, 2), Color(1, 1, 1, ra * 0.6))
		if inten2 > 0.3:
			var sa := (inten2 - 0.3) * 0.08
			var sy := 0.0
			while sy < h:
				draw_rect(Rect2(0, sy, w, 2), Color(0, 0, 0, sa))
				sy += 4.0
		if inten2 > 0.5:
			var fa := (inten2 - 0.5) * 0.12
			var fo := sin(_t * 7.0) * (2.0 + inten2 * 4.0)
			draw_rect(Rect2(fo, 0, 2, h), Color(1, 0, 0, fa))
			draw_rect(Rect2(w - 2 + fo, 0, 2, h), Color(0, 1, 1, fa))
		for i in int(inten2 * 120):
			var b := randf() * 0.3
			draw_rect(Rect2(randf() * w, randf() * h, 2, 2), Color(b, b, b, 0.15 + inten2 * 0.2))
