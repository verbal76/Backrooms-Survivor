extends SceneTree
## Targeted regression tests for defects found in playtesting. Run (headless, ~1 min):
##   godot --headless --path godot -s tools/regression_tests.gd
## Prints PASS/FAIL per test and exits non-zero if any test fails. CI runs it before exporting.

var g
var results: Array = []


func _init() -> void:
	var packed = load("res://scenes/game.tscn")
	g = packed.instantiate()
	root.add_child(g)
	await process_frame
	t_key_name()
	t_touch_layouts()
	await t_save_integrity()
	g.start_run()
	await _frames(10)
	t_draw_order_and_day()
	t_tutorial_matches_code()
	t_controller_prompts_are_pure()
	t_glyph_mapping()
	t_touch_move_and_sprint()
	await t_phone_ui()
	await t_phone_menus()
	await t_enemy_attack_cycle()
	await t_no_flee_or_hover()
	await t_tired_swing_still_hits()
	await t_press_survives_hitstop()
	var failed := 0
	for r in results:
		print(("PASS " if r.ok else "FAIL ") + r.name + ("" if r.ok else "  -> " + r.msg))
		if not r.ok:
			failed += 1
	print("REGRESSION TESTS: %d passed, %d failed" % [results.size() - failed, failed])
	quit(1 if failed > 0 else 0)


func _ok(name: String, cond: bool, msg := "") -> void:
	results.append({"name": name, "ok": cond, "msg": msg})


func _frames(n: int) -> void:
	for i in n:
		_keep_playing()
		await physics_frame


## Kills grant XP; a level-up opens the perk screen (state "perk") which pauses the simulation. Tests must stay in play.
func _keep_playing() -> void:
	if g.state == "perk" or g.state == "portal":
		g.player.pending_perk_choice = false
		g.set_state("playing")


func _clear_enemies() -> void:
	g.enemies.spawning_enabled = false
	for e in g.enemies.get_enemies():
		e.take_damage(100000.0)
	for i in 40:
		_keep_playing()
		await physics_frame
	for e in g.enemies.get_enemies():
		e.queue_free()
	g.enemies.list.clear()


func t_key_name() -> void:
	var n1: String = g.input.key_name(KEY_W)
	var n2: String = g.input.key_name(KEY_W)
	_ok("key_name returns a stable label", n1 == n2 and n1 != "" and n1 != "None", "got '%s'" % n1)
	_ok("key_name(0) is None", g.input.key_name(0) == "None")


func t_touch_layouts() -> void:
	var required := ["attack", "bomb", "weapon_next", "battery", "headlamp", "use_water", "use_bandage", "use_food", "pause"]
	for view in [Vector2(1280, 580), Vector2(1920, 886), Vector2(2400, 1080), Vector2(1280, 800), Vector2(960, 720)]:
		var lay: Dictionary = g.input.touch_layout(view)
		var seen := {}
		var problems: Array[String] = []
		for b in lay.buttons:
			seen[b.action] = true
			if b.pos.x - b.r < 0.0 or b.pos.y - b.r < 0.0 or b.pos.x + b.r > view.x or b.pos.y + b.r > view.y:
				problems.append("%s outside view" % b.action)
		for a in required:
			if not seen.has(a):
				problems.append("missing button " + a)
		for i in lay.buttons.size():
			for j in range(i + 1, lay.buttons.size()):
				var bi: Dictionary = lay.buttons[i]
				var bj: Dictionary = lay.buttons[j]
				if bi.pos.distance_to(bj.pos) < (bi.r + bj.r) * 0.9:
					problems.append("%s overlaps %s" % [bi.action, bj.action])
		_ok("touch layout sane at %dx%d" % [view.x, view.y], problems.is_empty(), ", ".join(problems))


func t_save_integrity() -> void:
	var P = load("res://scripts/ui/progression.gd")
	var file := "user://backrooms_save.json"
	var keep := {}
	for suffix in ["", ".bak"]:
		if FileAccess.file_exists(file + suffix):
			keep[suffix] = FileAccess.get_file_as_string(file + suffix)
	var good := JSON.stringify({"version": 3, "characters": [{"name": "TESTER", "profiles": [], "tips": ["x"]}]})
	# corrupt main + valid backup -> loads from backup
	FileAccess.open(file, FileAccess.WRITE).store_string("{ this is not json")
	FileAccess.open(file + ".bak", FileAccess.WRITE).store_string(good)
	var p1 = P.new()
	p1.load_save()
	_ok("corrupt save falls back to .bak", p1.characters.size() == 1 and p1.characters[0].name == "TESTER", "characters=%s" % [p1.characters.size()])
	# both corrupt -> no crash, empty
	FileAccess.open(file + ".bak", FileAccess.WRITE).store_string("garbage")
	var p2 = P.new()
	p2.load_save()
	_ok("fully corrupt save loads empty without crashing", p2.characters.size() == 0)
	# crash between "tmp written" and "tmp renamed": a complete .tmp is newer than the save and must win
	var older := JSON.stringify({"version": 3, "characters": [{"name": "OLD", "profiles": [], "tips": []}]})
	var newer := JSON.stringify({"version": 3, "characters": [{"name": "NEW", "profiles": [], "tips": []}]})
	FileAccess.open(file, FileAccess.WRITE).store_string(older)
	FileAccess.open(file + ".tmp", FileAccess.WRITE).store_string(newer)
	var p3 = P.new()
	p3.load_save()
	_ok("complete .tmp (interrupted save) is recovered", p3.characters.size() == 1 and p3.characters[0].name == "NEW")
	# a truncated .tmp must never beat a valid save
	FileAccess.open(file + ".tmp", FileAccess.WRITE).store_string('{"version": 3, "characters": [{"name": "HAL')
	var p4 = P.new()
	p4.load_save()
	_ok("truncated .tmp is ignored", p4.characters.size() == 1 and p4.characters[0].name == "OLD")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file + ".tmp"))
	# restore the real files
	for suffix in ["", ".bak"]:
		if keep.has(suffix):
			FileAccess.open(file + suffix, FileAccess.WRITE).store_string(keep[suffix])
		elif FileAccess.file_exists(file + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file + suffix))
	await process_frame


func t_draw_order_and_day() -> void:
	_ok("player draws above enemies (z_index)", g.player.z_index >= 1)
	_ok("day length comes from run mods (120 s)", is_equal_approx(g.day_seconds, 120.0), "day_seconds=%s" % g.day_seconds)


func t_enemy_attack_cycle() -> void:
	await _clear_enemies()
	g.player.hp = 1000.0
	g.player.max_hp = 1000.0
	g.player.invuln_time = 0.0
	g.player.tile_pos = g.map.find_spawn()
	g.player.position = g.player.tile_pos * 52.0
	var e = g.enemies.spawn("hound", g.player.tile_pos + Vector2(0.9, 0.0), true)
	var hp0: float = g.player.hp
	var t_first := -1.0
	var hits: Array[float] = []
	var last_hp := hp0
	for f in 360:
		_keep_playing()
		await physics_frame
		g.player.invuln_time = 0.0   # isolate attack timing from invulnerability frames
		if g.player.hp < last_hp - 0.01:
			hits.append(f / 60.0)
			last_hp = g.player.hp
	_ok("hound hits from reach, only after a wind-up", hits.size() >= 2 and hits[0] >= e.windup * 0.8,
		"hits=%s windup=%s" % [hits, e.windup])
	if hits.size() >= 2:
		_ok("hound attacks are spaced by recover time", hits[1] - hits[0] >= e.recover * 0.8,
			"gap=%s recover=%s" % [hits[1] - hits[0], e.recover])
	await _clear_enemies()


func t_no_flee_or_hover() -> void:
	await _clear_enemies()
	g.player.hp = 100000.0
	g.player.max_hp = 100000.0
	g.player.invuln_time = 0.0
	g.player.headlamp_on = true
	if g.lighting:
		g.lighting.ambient = 1.0
	g.enemies.spawning_enabled = false
	for i in 4:
		g.enemies.spawn("hound", g.player.tile_pos + Vector2.from_angle(i * 1.5) * 3.5, true)
	var flee := 0
	var idle_out := 0
	var total := 0
	var last := {}
	for f in 600:
		_keep_playing()
		await physics_frame
		g.player.invuln_time = 0.0
		for e in g.enemies.get_enemies():
			total += 1
			if e.state == "flee":
				flee += 1
			var id = e.get_instance_id()
			var moved: float = e.tile_pos.distance_to(last.get(id, e.tile_pos))
			last[id] = e.tile_pos
			if e.state == "hunt" and e.atk_phase == "" and moved < 0.002 and e.tile_pos.distance_to(g.player.tile_pos) > e.reach * 1.2:
				idle_out += 1
	_ok("enemies never flee from the headlamp", flee == 0, "flee frames=%d" % flee)
	_ok("hunting enemies do not hover idle outside reach", total > 0 and float(idle_out) / total < 0.35,
		"idle outside reach %d/%d" % [idle_out, total])
	await _clear_enemies()


func t_tired_swing_still_hits() -> void:
	await _clear_enemies()
	g.weapons.set_weapon(0)   # machete
	g.player.stamina = 3.0
	g.player.invuln_time = 0.0
	g.player.hp = 100000.0
	var e = g.enemies.spawn("crawler", g.player.tile_pos + Vector2(1.0, 0.0), false)
	e.alert_level = 0.0
	g.player.angle = 0.0
	g.weapons.fire_timer = 0.0
	var hp0: float = e.hp
	g.weapons._try_fire(g.player)
	await _frames(5)
	_ok("melee swing with low stamina is weaker, not refused", e.hp < hp0, "hp %s -> %s" % [hp0, e.hp])
	await _clear_enemies()


func t_press_survives_hitstop() -> void:
	_keep_playing()
	g.weapons.bomb.cooldown = 0.0
	var before: int = g.weapons.bomb.count
	g.weapons.bomb.count = maxi(1, before)
	var c0: int = g.weapons.bomb.count
	g.input.press("bomb")
	g.hitstop(0.2)
	await _frames(40)
	_ok("a bomb press during hit-stop is not dropped", g.weapons.bomb.count == c0 - 1, "bombs %d -> %d" % [c0, g.weapons.bomb.count])


## The tutorial quotes game numbers; it must not drift from the code again (it did after the balance pass).
func t_tutorial_matches_code() -> void:
	var T = load("res://scripts/ui/tutorial_data.gd")
	var all := ""
	for pg in T.PAGES:
		all += " ".join(pg.lines) + " "
	for k in T.TIPS:
		all += str(T.TIPS[k].text) + " "
	var S: Dictionary = load("res://scripts/player.gd").S
	_ok("tutorial states the real stamina regen", all.contains("(%d per second)" % int(S.stamina_regen)), "regen %s" % S.stamina_regen)
	_ok("tutorial states the real sprint cost", all.contains("costs %d stamina per second" % int(S.sprint_cost)))
	_ok("tutorial no longer claims enemies flee from light", not all.contains("flee when they stand") and not all.contains("run when your headlamp"))
	var types: Dictionary = g.enemies.TYPES
	var lo := 99.0
	var hi := 0.0
	for k in types:
		lo = minf(lo, float(types[k].windup))
		hi = maxf(hi, float(types[k].windup))
	_ok("tutorial states the real wind-up range", all.contains("%s to %s seconds" % [str(lo), str(hi)]), "range %s-%s" % [lo, hi])


## Valve requirement: while a controller is the active input, no keyboard/mouse wording or glyphs may appear.
func t_controller_prompts_are_pure() -> void:
	var banned := ["enter", "esc", "click", "mouse", "space", "tab", "shift", "ctrl", "wasd", "arrow", "f1", "f2", "keyboard", "wheel", "cursor"]
	var T = load("res://scripts/ui/tutorial_data.gd")
	var bad: Array[String] = []
	for entry in g.input.ACTIONS:
		var a: String = entry.id
		var txt: String = g.input.prompt(a, "gamepad").to_lower()
		for b in banned:
			if txt.contains(b):
				bad.append("%s -> %s" % [a, txt])
	for a in ["accept", "back", "menu", "move", "aim"]:
		var txt2: String = g.input.prompt(a, "gamepad").to_lower()
		for b in banned:
			if txt2.contains(b):
				bad.append("%s -> %s" % [a, txt2])
	# every tutorial line that is shown on a pad (no [kb]/[touch] prefix) must be keyboard-free after fill()
	for pg in T.PAGES:
		for line in pg.lines:
			if line.begins_with("[kb]") or line.begins_with("[touch]"):
				continue
			var t: String = g.input.fill(line, "gamepad").to_lower()
			for b in ["click", "mouse", "keyboard", "[enter]", "[esc]", "wasd", "wheel"]:
				if t.contains(b):
					bad.append("page '%s': %s" % [pg.title, line.substr(0, 60)])
	for k in T.TIPS:
		var tt: String = g.input.fill(str(T.TIPS[k].text), "gamepad").to_lower()
		for b in ["click", "mouse", "keyboard", "[enter]", "[esc]", "wasd", "wheel"]:
			if tt.contains(b):
				bad.append("tip %s" % k)
	_ok("no keyboard/mouse wording in gamepad prompts, tutorial pages or tips", bad.is_empty(), "; ".join(bad.slice(0, 6)))


func t_glyph_mapping() -> void:
	var prev_enabled: bool = Glyphs.enabled
	var prev_family: String = Glyphs.family
	var problems: Array[String] = []
	var cases := {"Xbox Series Controller": "xbox", "PS5 Controller": "ps5", "DualShock 4": "ps4", "Nintendo Switch Pro Controller": "switch", "Steam Deck": "xbox", "": "xbox"}
	for k in cases:
		if Glyphs.family_for(k) != cases[k]:
			problems.append("%s -> %s" % [k, Glyphs.family_for(k)])
	Glyphs.enabled = true
	Glyphs.family = "xbox"
	var seg: Array = Glyphs.segments("Sprint with [A] now [Menu] pauses")
	if seg.size() != 5 or not seg[1].has("glyph") or seg[3].get("text", "") != "Menu":
		problems.append("segments: %s" % [seg])
	Glyphs.enabled = false
	if not Glyphs.segments("Sprint with [A]").is_empty():
		problems.append("segments active while disabled")
	for fam in ["xbox", "ps5", "ps4", "switch"]:
		if not Glyphs.has_token("A", fam):
			problems.append("%s lacks A glyph" % fam)
	# manual prompt style: old saves without the key load as Auto; the choice survives a round trip and forces the family
	var go := GameOptions.new()
	go.apply_dict({"music_volume": 0.5})
	if go.prompt_style != 0:
		problems.append("old options.json must default prompt_style to Auto")
	go.prompt_style = 2
	var go2 := GameOptions.new()
	go2.apply_dict(go.to_dict())
	if go2.prompt_style != 2:
		problems.append("prompt_style lost in round trip")
	Glyphs.sync(true, "Xbox Controller", GameOptions.PROMPT_FAMILIES[2])
	if Glyphs.family != "ps5":
		problems.append("PlayStation override ignored")
	Glyphs.enabled = prev_enabled
	Glyphs.family = prev_family
	_ok("glyph family mapping, token segmentation and fallback", problems.is_empty(), "; ".join(problems))


# ---- touch movement + sprint toggle (owner playtest, Build 13) -----------------------------------------------

class OpenMap extends WorldMap:
	func is_solid(_x: float, _y: float) -> bool:
		return false


func _tap(index: int, pos: Vector2, pressed := true, canceled := false) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	ev.canceled = canceled
	g.input._handle_touch(ev)


func _stick_to(dist: float, dir := Vector2.RIGHT) -> void:
	var o: Vector2 = g.input.touch_layout().move_c
	g.input._sticks.left = {"id": 0, "o": o, "p": o + dir.normalized() * dist}


func _touch_frame(dt := 1.0 / 60.0) -> void:
	var inp = g.input
	inp.move = Vector2.ZERO
	inp.sprint = false
	inp._update_touch(true)
	g.player.step(dt, inp.move, inp.sprint, g.player.tile_pos * g.TILE)


func _settle(frames := 150) -> float:
	for i in frames:
		_touch_frame()
	return g.player.vel.length()


func t_touch_move_and_sprint() -> void:
	var inp = g.input
	var p = g.player
	var saved_map = p.map
	var saved := {"pos": p.tile_pos, "stamina": p.stamina, "vel": p.vel}
	p.map = OpenMap.new()
	_keep_playing()
	inp.reset_run()
	var lay: Dictionary = inp.touch_layout()
	var maxr: float = lay.stick_r
	var dz: float = maxf(8.0, maxr * inp.TOUCH_DEADZONE)
	var walk: float = p.base_speed * p.speed_mult
	var bad: Array[String] = []

	# 1. ONE walking speed at every valid stick distance, in every direction; nothing below the dead zone
	var speeds := {}
	for dist in [dz + 2.0, maxr * 0.5, maxr, maxr * 1.7]:
		p.vel = Vector2.ZERO
		_stick_to(dist)
		speeds[dist] = _settle()
	for dist in speeds:
		if absf(speeds[dist] - walk) > 0.01:
			bad.append("dist %.0f -> %.3f (want %.3f)" % [dist, speeds[dist], walk])
	p.vel = Vector2.ZERO
	_stick_to(maxr, Vector2(1, 1))
	var diag := _settle()
	if absf(diag - walk) > 0.01:
		bad.append("diagonal %.3f (want %.3f)" % [diag, walk])
	p.vel = Vector2.ZERO
	_stick_to(dz - 2.0)
	if _settle() > 0.01:
		bad.append("moved inside the dead zone")
	_ok("touch stick: one walking speed at every distance and diagonal, none inside the dead zone", bad.is_empty(), "; ".join(bad))
	bad.clear()

	# 2. pushing the stick to the edge no longer sprints
	p.vel = Vector2.ZERO
	_stick_to(maxr * 1.7)
	_settle(20)
	_ok("edge of the stick does not sprint", not p.sprinting and not inp.sprint)

	# 3. SPRINT button toggles on, uses the existing multiplier once, toggles off
	var sb: Vector2 = Vector2.ZERO
	for b in lay.buttons:
		if b.action == "sprint":
			sb = b.pos
	p.stamina = 100.0
	p.vel = Vector2.ZERO
	_tap(5, sb)
	_tap(5, sb, false)
	_ok("first tap switches sprint on", inp._sprint_latched)
	var sp := _settle()
	_ok("sprint uses the existing multiplier and does not stack", absf(sp - walk * p.sprint_mult) < 0.02 and p.sprinting, "%.3f vs %.3f" % [sp, walk * p.sprint_mult])
	_tap(5, sb)
	_tap(5, sb, false)
	_touch_frame()
	_ok("second tap switches sprint off immediately", not inp._sprint_latched and not p.sprinting)
	_ok("walking speed returns after sprint off", absf(_settle() - walk) < 0.02)

	# 4. toggle on while standing still: no drain, stays lit, takes effect when moving
	_release_stick_and_stop()
	p.stamina = 100.0
	_tap(5, sb)
	_tap(5, sb, false)
	for i in 60:
		_touch_frame()
	_ok("sprint ON while stationary costs no stamina and stays on", inp._sprint_latched and not p.sprinting and p.stamina >= 99.9, "stamina %.2f" % p.stamina)
	_stick_to(maxr)
	_touch_frame()
	_ok("moving then sprints", p.sprinting)

	# 5. drain at the existing rate; exhaustion switches it off and it stays off while stamina recovers
	p.stamina = 100.0
	for i in 60:
		_touch_frame()
	var spent: float = 100.0 - p.stamina
	var want: float = p.S.sprint_cost * p.sprint_cost_mult
	_ok("sprint drains stamina at the existing rate", absf(spent - want) < 0.6, "spent %.2f/s want %.2f" % [spent, want])
	p.stamina = 3.0
	var frames_on := 0
	while inp._sprint_latched and frames_on < 300:
		_touch_frame()
		frames_on += 1
	_ok("exhausting stamina switches the sprint toggle off", not inp._sprint_latched and not p.sprinting and p.stamina < 0.5 and frames_on < 60,
		"stamina %.2f latched %s after %d frames" % [p.stamina, inp._sprint_latched, frames_on])
	for i in 30:
		_touch_frame()
	_ok("walking continues at normal speed after exhaustion", absf(p.vel.length() - walk) < 0.02)
	for i in 600:
		_touch_frame()
	_ok("sprint does not resume by itself when stamina recovers", p.stamina > 20.0 and not inp._sprint_latched and not p.sprinting, "stamina %.1f" % p.stamina)
	p.stamina = 0.0
	_tap(5, sb)
	_tap(5, sb, false)
	_ok("sprint cannot be switched on without stamina", not inp._sprint_latched and not inp.touch_enabled("sprint"))
	p.stamina = 100.0
	_tap(5, sb)
	_tap(5, sb, false)
	_ok("sprint can be switched on again once recovered", inp._sprint_latched)

	# 6. another finger on the stick: tapping SPRINT must not disturb it; release and cancel stop movement
	inp._sprint_latched = false
	_stick_to(maxr * 0.6)
	_tap(7, sb)
	_tap(7, sb, false)
	_touch_frame()
	_ok("sprint tap while another finger steers keeps the stick and toggles", inp._sprint_latched and inp._sticks.left.id == 0 and inp.move.length() > 0.99)
	_tap(0, Vector2.ZERO, false)
	_touch_frame()
	_ok("finger release stops movement input", inp._sticks.left.id == -1 and inp.move == Vector2.ZERO)
	_stick_to(maxr)
	_tap(0, Vector2.ZERO, false, true)
	_touch_frame()
	_ok("touch cancel stops movement input", inp._sticks.left.id == -1 and inp.move == Vector2.ZERO)
	inp.reset_run()
	_ok("a new run starts with sprint off", not inp._sprint_latched)

	p.map = saved_map
	p.tile_pos = saved.pos
	p.stamina = saved.stamina
	p.vel = saved.vel


func _release_stick_and_stop() -> void:
	g.input._sticks.left.id = -1
	g.player.vel = Vector2.ZERO


# ---- Android phone UI: ~2x readable, nothing overlapping or clipped (owner screenshots, Build 13) -------------------

const PHONE_VIEWS := [Vector2i(1280, 580), Vector2i(1920, 886), Vector2i(2400, 1080), Vector2i(2160, 1080), Vector2i(1920, 1080)]


func _rect_hits_circle(r: Rect2, c: Vector2, rad: float) -> bool:
	var nx := clampf(c.x, r.position.x, r.end.x)
	var ny := clampf(c.y, r.position.y, r.end.y)
	return Vector2(nx, ny).distance_to(c) < rad


## Rects (viewport px) of every touch control: buttons and the two stick areas.
func _touch_circles(lay: Dictionary) -> Array:
	var out: Array = []
	for b in lay.buttons:
		out.append([b.action, b.pos, b.r])
	out.append(["move stick", lay.move_c, lay.stick_r])
	out.append(["aim stick", lay.aim_c, lay.stick_r])
	return out


func t_phone_ui() -> void:
	var ui = g.ui
	var saved_scale: float = ui.options.ui_scale
	var saved_lh: bool = ui.options.touch_left_handed
	var saved_mode: int = ui.options.control_mode
	var saved_win: Vector2i = root.size
	ui.options.ui_scale = 1.0
	ui.options.control_mode = 3
	var bad: Array[String] = []
	var Hud = load("res://scripts/ui/hud.gd")

	# desktop is untouched: no phone flag -> the old scale formula
	ui.debug_phone = false
	root.size = Vector2i(1280, 800)
	await process_frame
	var vp0: Vector2 = ui.get_viewport().get_visible_rect().size
	_ok("desktop / Steam Deck UI scale is unchanged", absf(ui.hud_scale() - clampf(minf(1.0, vp0.y / 460.0), 0.8, 1.6)) < 0.001 and ui.phone_boost() == 1.0,
		"hud %.3f boost %.2f" % [ui.hud_scale(), ui.phone_boost()])

	ui.debug_phone = true
	for lh in [false, true]:
		ui.options.touch_left_handed = lh
		for view in PHONE_VIEWS:
			root.size = view
			await process_frame
			await process_frame
			var vp: Vector2 = ui.get_viewport().get_visible_rect().size
			var s: float = ui.hud_scale()
			var tag := "%dx%d%s" % [view.x, view.y, " lefty" if lh else ""]
			if s < 1.8 or s > 2.2:
				bad.append("%s hud scale %.2f" % [tag, s])
			var lay: Dictionary = g.input.touch_layout()
			var px := -1.0
			var pr := 0.0
			for b in lay.buttons:
				if b.action == "pause":
					px = b.pos.x / s
					pr = b.r / s
			var rects: Dictionary = Hud.phone_rects(vp.x / s, lh, px, pr)
			rects.erase("mini_size")
			if (rects.mini as Rect2).size.x * s < 150.0:
				bad.append("%s minimap too small (%.0f px)" % [tag, (rects.mini as Rect2).size.x * s])
			for name in rects:
				var r: Rect2 = rects[name]
				var rp := Rect2(r.position * s, r.size * s)
				if rp.position.x < -0.5 or rp.position.y < -0.5 or rp.end.x > vp.x + 0.5 or rp.end.y > vp.y + 0.5:
					bad.append("%s HUD %s outside the screen" % [tag, name])
				for c in _touch_circles(lay):
					if _rect_hits_circle(rp, c[1], c[2]):
						bad.append("%s HUD %s overlaps %s" % [tag, name, c[0]])
			var names := rects.keys()
			for i in names.size():
				for j in range(i + 1, names.size()):
					if (rects[names[i]] as Rect2).intersects(rects[names[j]]):
						bad.append("%s HUD %s overlaps %s" % [tag, names[i], names[j]])
	_ok("phone HUD is ~2x, inside the screen and clear of every touch control (5 sizes, both hands)", bad.is_empty(), "; ".join(bad.slice(0, 6)))
	ui.options.touch_left_handed = saved_lh

	# level-up page: both cards fully visible, not overlapping, big enough
	bad.clear()
	for view in PHONE_VIEWS:
		root.size = view
		await process_frame
		ui.perk_choices = Progression.roll_perk_choice([])
		g.set_state("perk")
		await _frames_raw(40)
		var pg = ui.screens["perk"]
		var sz: Vector2 = pg.size
		var tag2 := "%dx%d" % [view.x, view.y]
		if pg.ui_scale < 1.8:
			bad.append("%s page scale %.2f" % [tag2, pg.ui_scale])
		for i in 2:
			var r: Rect2 = pg._rects[i]
			if r.position.x < 0.0 or r.position.y < 0.0 or r.end.x > sz.x or r.end.y > sz.y - 20.0:
				bad.append("%s card %d outside (%s in %s)" % [tag2, i, r, sz])
			if r.size.x * pg.ui_scale < 1.7 * 280.0 or r.size.y * pg.ui_scale < 1.4 * 150.0:
				bad.append("%s card %d too small" % [tag2, i])
		if (pg._rects[0] as Rect2).intersects(pg._rects[1]):
			bad.append("%s cards overlap" % tag2)
		g.set_state("playing")
		await _frames_raw(5)
	_ok("level-up cards: ~2x bigger, both fully visible, no overlap (5 sizes)", bad.is_empty(), "; ".join(bad.slice(0, 5)))

	# tutorial tip card: inside the screen, clear of both thumb clusters
	bad.clear()
	ui.options.tips_enabled = true
	for view in PHONE_VIEWS:
		root.size = view
		await process_frame
		ui.tips._show("stamina_low")
		ui.tips._alpha = 1.0
		await _frames_raw(6)
		var s3: float = ui.hud_scale()
		var cr: Rect2 = ui.tips.card_rect
		var crp := Rect2(cr.position * s3, cr.size * s3)
		var vp3: Vector2 = ui.get_viewport().get_visible_rect().size
		var tag3 := "%dx%d" % [view.x, view.y]
		if crp.position.x < 0.0 or crp.position.y < 0.0 or crp.end.x > vp3.x or crp.end.y > vp3.y:
			bad.append("%s tip outside %s" % [tag3, crp])
		for c in _touch_circles(g.input.touch_layout()):
			if _rect_hits_circle(crp, c[1], c[2]):
				bad.append("%s tip overlaps %s" % [tag3, c[0]])
		ui.tips.dismiss()
	_ok("tip card sits between the thumb clusters, inside the screen (5 sizes)", bad.is_empty(), "; ".join(bad.slice(0, 5)))

	ui.debug_phone = false
	ui.options.ui_scale = saved_scale
	ui.options.control_mode = saved_mode
	root.size = saved_win
	await process_frame


func _frames_raw(n: int) -> void:
	for i in n:
		await process_frame


## Pause / options / how-to pages on a phone: magnified ~2x, every visible menu row and button inside the page.
func t_phone_menus() -> void:
	var ui = g.ui
	var saved_scale: float = ui.options.ui_scale
	var saved_win: Vector2i = root.size
	ui.options.ui_scale = 1.0
	ui.debug_phone = true
	var bad: Array[String] = []
	for view in PHONE_VIEWS:
		root.size = view
		await process_frame
		var tag := "%dx%d" % [view.x, view.y]
		g.set_state("paused")
		await _frames_raw(40)
		var pg = ui.screens["pause"]
		if pg.ui_scale < 1.8:
			bad.append("%s pause scale %.2f" % [tag, pg.ui_scale])
		for r in pg.menu.rects:
			if r.position.x < -5000.0:
				continue                          # row scrolled out of the window
			if r.position.y < 0.0 or r.end.y > pg.size.y - 18.0 or r.position.x < 0.0 or r.end.x > pg.size.x:
				bad.append("%s pause row %s outside %s" % [tag, r, pg.size])
		ui.show_screen("options", "pause")
		var op = ui.screens["options"]
		for sec in ["main", "display", "gamepad", "touch"]:
			op._open_section(sec)
			await _frames_raw(40)
			var m: MenuList = op._menu_for(sec)
			if op.ui_scale < 1.8:
				bad.append("%s options scale %.2f" % [tag, op.ui_scale])
			var vis := 0
			for r in m.rects:
				if r.position.x < -5000.0:
					continue
				vis += 1
				if r.position.y < 0.0 or r.end.y > op.size.y - 14.0 or r.end.x > op.size.x:
					bad.append("%s options/%s row %s outside %s" % [tag, sec, r, op.size])
			if vis < 3:
				bad.append("%s options/%s only %d rows visible" % [tag, sec, vis])
		ui.show_screen("howto", "pause")
		await _frames_raw(40)
		var hp = ui.screens["howto"]
		if hp.ui_scale < 1.8:
			bad.append("%s how-to scale %.2f" % [tag, hp.ui_scale])
		for rr in [hp._back_rect, hp._prev_rect, hp._next_rect]:
			if (rr as Rect2).end.y > hp.size.y or (rr as Rect2).position.x < 0.0 or (rr as Rect2).end.x > hp.size.x:
				bad.append("%s how-to button %s outside %s" % [tag, rr, hp.size])
		g.set_state("playing")
		await _frames_raw(5)
	_ok("pause, options and how-to pages: ~2x, rows and buttons inside the screen (5 sizes)", bad.is_empty(), "; ".join(bad.slice(0, 5)))
	ui.debug_phone = false
	ui.options.ui_scale = saved_scale
	root.size = saved_win
	await process_frame
