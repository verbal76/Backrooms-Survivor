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
	t_map_markers_and_pacing()
	t_targeting_and_facing()
	t_weapon_flip_stable()
	await t_attack_input_and_direction()
	await t_compact_hud()
	await t_action_cluster_and_map()
	t_no_manual_aim_and_tutorial()
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


## Owner playtest: pickups show on the minimap in their own colour; lamp and stamina were fading too fast.
func t_map_markers_and_pacing() -> void:
	var o = g.objects
	var before: int = o.get_map_markers().size()
	var it = o.spawn_drop(g.player.tile_pos + Vector2(3, 0), "almond water")
	var it2 = o.spawn_drop(g.player.tile_pos + Vector2(0, 3), "bandage")
	var marks: Array = o.get_map_markers()
	var found_water := false
	var found_med := false
	for m in marks:
		if m.pos.distance_to(it.tile_pos) < 0.01 and m.color.is_equal_approx(it.color):
			found_water = true
		if m.pos.distance_to(it2.tile_pos) < 0.01 and m.color.is_equal_approx(it2.color):
			found_med = true
	_ok("minimap marks every pickup in its own colour", marks.size() >= before + 2 and found_water and found_med and not it.color.is_equal_approx(it2.color))
	it.collected = true
	var after_collect := 0
	for m in o.get_map_markers():
		if m.pos.distance_to(it.tile_pos) < 0.01:
			after_collect += 1
	_ok("a collected pickup leaves the minimap", after_collect == 0)
	var S: Dictionary = load("res://scripts/player.gd").S
	var lamp = load("res://scripts/systems/lighting.gd")
	var life: float = 100.0 / lamp.BATTERY_DRAIN
	_ok("a full headlamp battery lasts about 5 minutes", life > 290.0 and life < 320.0, "%.0f s" % life)
	_ok("sprint empties full stamina in about 8 s and it refills in about 11 s", absf(100.0 / S.sprint_cost - 8.3) < 0.5 and absf(100.0 / S.stamina_regen - 11.1) < 0.5,
		"%.1f s / %.1f s" % [100.0 / S.sprint_cost, 100.0 / S.stamina_regen])
	o.items.erase(it)
	o.items.erase(it2)
	it.queue_free()
	it2.queue_free()


# ==== Release-candidate pass: automatic targeting, facing authority, attack input, compact HUD, tutorial =============

class Dummy extends RefCounted:
	var tile_pos := Vector2.ZERO
	var dead := false


class TestGrid extends WorldMap:
	var walls := {}
	func is_solid(x: float, y: float) -> bool:
		return walls.has(Vector2i(floori(x), floori(y)))


func _grid_arena() -> Dictionary:
	var saved := {"map": g.map, "pmap": g.player.map, "list": g.enemies.list, "pos": g.player.tile_pos, "angle": g.player.angle,
		"mode": g.ui.options.control_mode, "tg": g.input.target, "fd": g.input.facing_dir}
	var gm := TestGrid.new()
	g.map = gm
	g.player.map = gm
	g.ui.options.control_mode = 3
	g.player.tile_pos = Vector2(10.5, 10.5)
	g.player.position = g.player.tile_pos * 52.0
	g.player.vel = Vector2.ZERO
	g.enemies.list = []
	g.input.target = null
	g.input.facing_dir = Vector2.RIGHT
	g.input._sticks.left.id = -1
	return saved


func _arena_restore(saved: Dictionary) -> void:
	g.map = saved.map
	g.player.map = saved.pmap
	g.enemies.list = saved.list
	g.player.tile_pos = saved.pos
	g.player.position = g.player.tile_pos * 52.0
	g.player.angle = saved.angle
	g.ui.options.control_mode = saved.mode
	g.input.target = saved.tg
	g.input.facing_dir = saved.fd
	g.input.facing_snap = false
	g.player.snap_facing = false


func _dummy(x: float, y: float) -> Dummy:
	var d := Dummy.new()
	d.tile_pos = Vector2(x, y)
	g.enemies.list.append(d)
	return d


func _wall(x0: int, y0: int, x1: int, y1: int) -> void:
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			g.map.walls[Vector2i(x, y)] = true


## One real input + player step (what game.gd does each frame), minus the rest of the simulation.
func _facing_frame(move_dir := Vector2.ZERO) -> void:
	var inp = g.input
	var lay: Dictionary = inp.touch_layout()
	if move_dir == Vector2.ZERO:
		inp._sticks.left.id = -1
	else:
		var o: Vector2 = lay.move_c
		inp._sticks.left = {"id": 0, "o": o, "p": o + move_dir.normalized() * lay.stick_r}
	inp.move = Vector2.ZERO
	inp.sprint = false
	inp._update_touch(true)
	g.player.snap_facing = inp.facing_snap
	g.player.step(1.0 / 60.0, inp.move, inp.sprint, inp.aim_world, inp.fire, 0.3)


func t_targeting_and_facing() -> void:
	var inp = g.input
	var saved := _grid_arena()
	var bad: Array[String] = []

	# A. the nearest enemy behind a solid wall is not eligible
	_wall(13, 8, 13, 13)
	var behind := _dummy(15.5, 10.5)
	_ok("A: enemy behind a wall is not targeted", inp.pick_target() == null)
	# an enemy in "another room" (wall between, further away but visible one is chosen instead)
	var visible_far := _dummy(10.5, 17.5)
	_ok("A2: a farther enemy with a clear line is chosen over a nearer one behind the wall", inp.pick_target() == visible_far)

	# B. an enemy emerging from behind a corner is acquired immediately
	g.enemies.list = []
	g.map.walls.clear()
	_wall(12, 11, 14, 14)                      # block below the line, corner at (12,11)
	var corner := _dummy(13.5, 12.5)           # tucked behind the block
	var hidden_first: bool = inp.pick_target() == null
	corner.tile_pos = Vector2(13.5, 9.5)       # steps out into the open
	_ok("B: enemy rounding a corner becomes eligible at once", hidden_first and inp.pick_target() == corner)

	# C. two visible enemies: the nearest wins
	g.enemies.list = []
	g.map.walls.clear()
	var far := _dummy(16.5, 10.5)
	var near := _dummy(10.5, 13.5)
	_ok("C: nearest of two visible enemies is targeted", inp.pick_target() == near)

	# D. the target moves behind a wall: released (the other visible one takes over, then none)
	inp.target = near
	_wall(10, 11, 10, 12)
	_ok("D: a target that goes behind a wall is released, the nearest remaining eligible enemy is acquired", inp.pick_target() == far)
	_wall(13, 8, 13, 13)
	_ok("D2: nothing eligible -> no target", inp.pick_target() == null)

	# range limit and dead enemies
	g.map.walls.clear()
	g.enemies.list = []
	var outside := _dummy(10.5 + inp.AUTO_TARGET_RANGE + 2.0, 10.5)
	var corpse := _dummy(12.5, 10.5)
	corpse.dead = true
	_ok("targets beyond range or already dead are ignored", inp.pick_target() == null)

	# E. move left while the target is on the right: movement left, body + weapon right
	g.enemies.list = []
	var tr := _dummy(14.5, 10.5)
	var x0: float = g.player.tile_pos.x
	for i in 30:
		_facing_frame(Vector2.LEFT)
	_ok("E: moving left while the target is right: moves left, body faces right",
		g.player.tile_pos.x < x0 - 0.5 and absf(wrapf(g.player.angle, -PI, PI)) < 0.01 and inp.facing_dir.x > 0.99,
		"x %.2f -> %.2f angle %.3f" % [x0, g.player.tile_pos.x, g.player.angle])
	var view = g.weapons._view
	_ok("E2: the weapon is drawn along the same angle as the body", view != null and absf(wrapf(g.player.angle - inp.aim_angle, -PI, PI)) < 0.01)

	# F. standing still: the visible target keeps the facing
	g.player.tile_pos = Vector2(10.5, 10.5)
	g.player.vel = Vector2.ZERO
	g.enemies.list = []
	var up := _dummy(10.5, 6.5)
	for i in 10:
		_facing_frame()
	_ok("F: stationary with a visible target: faces it", absf(wrapf(g.player.angle - (-PI / 2.0), -PI, PI)) < 0.01,
		"angle %.3f target %s fd %s" % [g.player.angle, inp.target, inp.facing_dir])

	# G. no target while moving: face the movement direction
	g.enemies.list = []
	for i in 6:
		_facing_frame(Vector2.DOWN)
	_ok("G: no target, moving down: faces down", absf(wrapf(g.player.angle - PI / 2.0, -PI, PI)) < 0.01, "angle %.3f" % g.player.angle)

	# H. no target, standing still: last facing is kept
	g.player.tile_pos = Vector2(10.5, 10.5)
	g.player.vel = Vector2.ZERO
	for i in 10:
		_facing_frame()
	_ok("H: no target, stationary: keeps the last facing", absf(wrapf(g.player.angle - PI / 2.0, -PI, PI)) < 0.01)

	# the movement direction never overrides an active target (retreat while facing the enemy)
	g.enemies.list = []
	var ahead := _dummy(14.5, 10.5)
	var flips := 0
	var prev_dir: Vector2 = inp.facing_dir
	for i in 40:
		_facing_frame(Vector2.LEFT if (i / 10) % 2 == 0 else Vector2.UP)
		if inp.facing_dir.dot(prev_dir) < 0.9:
			flips += 1
		prev_dir = inp.facing_dir
	_ok("movement never steers the facing while a target is visible (no flip-flop)", flips <= 1, "flips %d" % flips)

	# target switch hysteresis: two enemies at almost the same distance do not make the facing flicker
	g.enemies.list = []
	var ea := _dummy(14.5, 10.5)
	var eb := _dummy(10.5, 14.45)
	g.player.tile_pos = Vector2(10.5, 10.5)
	var switches := 0
	var last = null
	for i in 40:
		eb.tile_pos.y = 14.45 + (0.04 if i % 2 == 0 else -0.04)       # distances 3.95..4.04 vs 4.0 (jitter)
		_facing_frame()
		if inp.target != last:
			switches += 1
			last = inp.target
	_ok("two nearly equidistant enemies do not make the target flicker", switches <= 2, "switches %d" % switches)

	# the same line-of-sight test on the REAL level geometry: DDA agrees with a very fine sampling
	_arena_restore(saved)
	var wm = g.map
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var origin: Vector2 = wm.find_spawn()
	var mism := 0
	var tunneled := 0
	var total := 0
	for i in 2500:
		var a := origin + Vector2(rng.randf_range(-10.0, 10.0), rng.randf_range(-10.0, 10.0))
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.0, 9.0)
		if wm.is_solid(a.x, a.y) or wm.is_solid(b.x, b.y):
			continue
		total += 1
		var dda: bool = inp.has_clear_los(a, b)
		var dense := true
		var n := int(a.distance_to(b) / 0.02)
		var run := 0
		var max_run := 0
		for k in range(1, n):
			var q := a.lerp(b, float(k) / n)
			var qt := Vector2i(floori(q.x), floori(q.y))
			if wm.is_solid(q.x, q.y) and qt != Vector2i(floori(b.x), floori(b.y)) and qt != Vector2i(floori(a.x), floori(a.y)):
				run += 1
				max_run = maxi(max_run, run)
			else:
				run = 0
		dense = max_run < 3
		if dda != dense:
			mism += 1
			if dda and not dense:
				tunneled += 1
	_ok("line of sight on the real level matches fine sampling (no tunnelling through walls)", total > 100 and tunneled == 0 and mism <= int(total * 0.03) + 1,
		"pairs %d mismatches %d tunnelled %d" % [total, mism, tunneled])
	g.ui.options.control_mode = saved.mode


func t_weapon_flip_stable() -> void:
	var View = load("res://scripts/weapons/weapon_view.gd")
	var bad := 0
	for facing_deg in [-90.0, 90.0, -80.0, 100.0, -100.0, 80.0, 0.0, 180.0]:
		var a: float = deg_to_rad(facing_deg)
		var side: float = View.flip_side(a, 1.0 if cos(a) >= 0.0 else -1.0)
		# a melee swing sweeps +-45 degrees around the facing: the side must not change anywhere in it
		for k in range(-45, 46, 3):
			var s2: float = View.flip_side(a, side)
			if s2 != side:
				bad += 1
	var side_up: float = View.flip_side(-PI / 2.0, 1.0)      # exactly up: inside the dead band keeps the previous side
	_ok("weapon side is chosen from the facing: no mid-swing flip, no flicker at vertical", bad == 0 and side_up == 1.0 and View.flip_side(-PI / 2.0, -1.0) == -1.0)


func _tap_attack(index := 9, hold_frames := 0) -> void:
	var lay: Dictionary = g.input.touch_layout()
	var pos := Vector2.ZERO
	for b in lay.buttons:
		if b.action == "attack":
			pos = b.pos
	_tap(index, pos)
	if hold_frames == 0:
		_tap(index, pos, false)          # press and release with no frame in between (a very short tap)


func _release_attack(index := 9) -> void:
	var lay: Dictionary = g.input.touch_layout()
	var pos := Vector2.ZERO
	for b in lay.buttons:
		if b.action == "attack":
			pos = b.pos
	_tap(index, pos, false)


var _fired_count := 0


func _count_fired(_i: int) -> void:
	_fired_count += 1


func _ready_player() -> void:
	g.player.hp = 1000.0
	g.player.max_hp = 1000.0
	g.player.invuln_time = 0.0
	g.player.stamina = g.player.max_stamina
	g.player.sanity = g.player.max_sanity


func t_attack_input_and_direction() -> void:
	var saved := _grid_arena()
	g.ui.options.tips_enabled = false         # a tip card on screen swallows (dismisses on) taps: keep it out of this test
	g.ui.tips.dismiss()
	var inp = g.input
	var wp = g.weapons
	wp.fired.connect(_count_fired)
	wp.set_weapon(0)
	g.weapons.fire_timer = 0.0
	g.set_state("playing")
	_ready_player()
	var rate: float = wp.LIST[0].rate

	# K. rapid distinct taps, each shorter than a frame: every one registers
	_fired_count = 0
	for i in 4:
		_ready_player()
		_tap_attack()
		await _frames(int(rate * 60.0) + 8)
	_ok("K: four quick taps (press + release inside one frame) = four attacks", _fired_count == 4, "attacks %d" % _fired_count)

	# a second tap inside the cooldown (legal after < FIRE_BUFFER): executes exactly once when allowed
	_fired_count = 0
	_ready_player()
	wp.fire_timer = 0.10
	_tap_attack()
	await _frames(14)
	_ok("K2: a tap just before the weapon is ready attacks once, as soon as it is legal", _fired_count == 1, "attacks %d" % _fired_count)
	await _frames(40)
	# a tap far too early is NOT remembered (bounded buffer): no automatic attack later
	_fired_count = 0
	_ready_player()
	wp.fire_timer = 0.45
	_tap_attack()
	await _frames(60)
	_ok("K3: a tap long before the cooldown ends is not queued (no unintended automatic attack)", _fired_count == 0, "attacks %d" % _fired_count)

	# N. holding attack never beats the cooldown; releasing stops it
	await _frames(30)
	_fired_count = 0
	wp.fire_timer = 0.0
	_ready_player()
	_tap_attack(9, 1)                  # press, keep holding
	for f in 120:
		_ready_player()
		await _frames(1)
	var held: int = _fired_count
	_release_attack()
	await _frames(40)
	var after_release: int = _fired_count - held
	_ok("N: holding ATTACK 2 s attacks no faster than the weapon cooldown, and stops on release",
		held >= 3 and held <= int(2.0 / rate) + 1 and after_release == 0, "held %d (max %d) after release %d" % [held, int(2.0 / rate) + 1, after_release])

	# L / M. attack while moving, and while a sprint toggle is on with another finger on the stick
	g.player.tile_pos = Vector2(10.5, 10.5)
	g.player.position = g.player.tile_pos * 52.0
	g.player.vel = Vector2.ZERO
	var lay: Dictionary = inp.touch_layout()
	var o: Vector2 = lay.move_c
	inp._sticks.left = {"id": 0, "o": o, "p": o + Vector2.LEFT * lay.stick_r}
	var sprint_btn := Vector2.ZERO
	for b in lay.buttons:
		if b.action == "sprint":
			sprint_btn = b.pos
	_tap(5, sprint_btn)
	_tap(5, sprint_btn, false)
	var latched_after_tap: bool = inp._sprint_latched
	_fired_count = 0
	wp.fire_timer = 0.0
	var x0: float = g.player.tile_pos.x
	_ready_player()
	_tap_attack(7)
	await _frames(30)
	_release_attack(7)
	_ok("L: attacking while moving: the attack is not dropped and the movement goes on", _fired_count >= 1 and g.player.tile_pos.x < x0 - 0.3 and inp._sticks.left.id == 0,
		"attacks %d dx %.2f" % [_fired_count, g.player.tile_pos.x - x0])
	_ok("M: movement, sprint and attack work together (sprint stays on, still moving, attacked)",
		inp._sprint_latched and g.player.sprinting and _fired_count >= 1, "after tap %s latched %s sprinting %s stamina %.1f" % [latched_after_tap, inp._sprint_latched, g.player.sprinting, g.player.stamina])
	inp._sticks.left.id = -1
	inp._sprint_latched = false

	# I. melee strikes where the visible weapon points: target on the right, player walking left, a decoy on the left
	g.player.tile_pos = Vector2(10.5, 10.5)
	g.player.position = g.player.tile_pos * 52.0
	g.player.vel = Vector2.ZERO
	g.enemies.list = []
	g.enemies.spawning_enabled = false
	var right_e = g.enemies.spawn("shade", Vector2(11.7, 10.5), false)
	var left_e = g.enemies.spawn("shade", Vector2(8.6, 10.5), false)
	for e in [right_e, left_e]:
		e.hp = 100000.0
		e.max_hp = 100000.0
		e.speed = 0.0
	var hp_r: float = right_e.hp
	var hp_l: float = left_e.hp
	inp._sticks.left = {"id": 0, "o": o, "p": o + Vector2.LEFT * lay.stick_r}
	wp.fire_timer = 0.0
	for f in 24:
		_ready_player()
		right_e.tile_pos = Vector2(g.player.tile_pos.x + 1.2, 10.5)       # keep both enemies at fixed offsets from the player
		left_e.tile_pos = Vector2(g.player.tile_pos.x - 1.9, 10.5)
		if f == 4:
			_tap_attack(7)
		await _frames(1)
	_release_attack(7)
	inp._sticks.left.id = -1
	_ok("I: melee hits the enemy in the facing direction (right) while moving left, not the one behind",
		right_e.hp < hp_r and left_e.hp == hp_l, "right %.0f/%.0f left %.0f/%.0f" % [right_e.hp, hp_r, left_e.hp, hp_l])
	_ok("I2: body angle, weapon angle and swing direction are the same value",
		absf(wrapf(g.player.angle - inp.facing_dir.angle(), -PI, PI)) < 0.02 and inp.facing_dir.x > 0.95)
	for e in [right_e, left_e]:
		g.enemies.list.erase(e)
		e.queue_free()

	# J. ranged weapons shoot along the same facing; weapon mechanics (ammo, cooldown) are unchanged
	g.enemies.list = []
	var tgt = g.enemies.spawn("shade", Vector2(10.5, 5.5), false)
	tgt.hp = 100000.0
	tgt.max_hp = 100000.0
	tgt.speed = 0.0
	wp.unlocked[4] = true
	wp.set_weapon(4)
	wp.ammo = 30
	wp.bullets.clear()
	wp.fire_timer = 0.0
	g.player.tile_pos = Vector2(10.5, 10.5)
	g.player.position = g.player.tile_pos * 52.0
	inp._sticks.left = {"id": 0, "o": o, "p": o + Vector2.RIGHT * lay.stick_r}      # walking right, target is straight up
	var ammo0: int = wp.ammo
	var bullet_dir := Vector2.ZERO
	for f in 20:
		_ready_player()
		tgt.tile_pos = Vector2(g.player.tile_pos.x, 5.5)
		if f == 5:
			_tap_attack(7)
		await _frames(1)
		if bullet_dir == Vector2.ZERO and not wp.bullets.is_empty():
			bullet_dir = (wp.bullets[0].vel as Vector2).normalized()
	_release_attack(7)
	inp._sticks.left.id = -1
	_ok("J: a ranged weapon fires along the facing (up) while walking right; one shot, one ammo",
		bullet_dir.y < -0.97 and absf(bullet_dir.x) < 0.25 and wp.ammo == ammo0 - 1, "dir %s ammo %d -> %d" % [bullet_dir, ammo0, wp.ammo])
	g.enemies.list.erase(tgt)
	tgt.queue_free()
	wp.set_weapon(0)
	wp.unlocked[4] = false
	wp.fired.disconnect(_count_fired)
	_arena_restore(saved)


## O. HUD: the panels are much smaller than before and never clip, overlap each other or the touch controls.
func t_compact_hud() -> void:
	var Hud = load("res://scripts/ui/hud.gd")
	var old_stats := 252.0 * 184.0            # Build 14 stats panel (236 + 16) x (6 rows * 25 + 34)
	var old_info := 188.0 * 112.0
	var ns: float = (Hud.BAR_W + 12.0) * Hud.stats_panel_height(true)
	var ni: float = (Hud.INFO_W + 8.0) * Hud.info_panel_height(true)
	var ns2: float = (Hud.BAR_W + 12.0) * Hud.stats_panel_height(false)
	var ni2: float = (Hud.INFO_W + 8.0) * Hud.info_panel_height(false)
	_ok("O: stats panel is >= 35% smaller (touch %.0f%%, keyboard/pad %.0f%%)" % [100.0 * (1.0 - ns / old_stats), 100.0 * (1.0 - ns2 / old_stats)],
		ns <= old_stats * 0.65 and ns2 <= old_stats * 0.65)
	_ok("O2: combat panel is >= 30% smaller (touch %.0f%%, keyboard/pad %.0f%%)" % [100.0 * (1.0 - ni / old_info), 100.0 * (1.0 - ni2 / old_info)],
		ni <= old_info * 0.70 and ni2 <= old_info * 0.65)
	# desktop / Deck resolutions, keyboard and pad layouts (minimap bottom-right, AMMO box bottom-left)
	var ui = g.ui
	var saved_win: Vector2i = root.size
	var saved_scale: float = ui.options.ui_scale
	ui.debug_phone = false
	ui.options.ui_scale = 1.0
	var bad: Array[String] = []
	for view in [Vector2i(1280, 800), Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(1024, 768)]:
		root.size = view
		await process_frame
		var vp: Vector2 = ui.get_viewport().get_visible_rect().size
		var s: float = ui.hud_scale()
		var w: float = vp.x / s
		var h: float = vp.y / s
		var rects := {
			"stats": Rect2(8.0, 6.0, Hud.BAR_W + 12.0, Hud.stats_panel_height(false)),
			"info": Rect2(w - Hud.INFO_W - 14.0, 6.0, Hud.INFO_W + 8.0, Hud.info_panel_height(false)),
			"minimap": Rect2(w - Hud.MINI_SIZE - 14.0, h - Hud.MINI_SIZE - 14.0, Hud.MINI_SIZE, Hud.MINI_SIZE),
			"ammo": Rect2(10.0, h - 52.0, 168.0, 34.0)}
		var names := rects.keys()
		for i in names.size():
			var r: Rect2 = rects[names[i]]
			if r.position.x < 0.0 or r.position.y < 0.0 or r.end.x > w or r.end.y > h:
				bad.append("%dx%d %s outside" % [view.x, view.y, names[i]])
			for j in range(i + 1, names.size()):
				if r.intersects(rects[names[j]]):
					bad.append("%dx%d %s overlaps %s" % [view.x, view.y, names[i], names[j]])
	_ok("O3: keyboard / gamepad HUD at Windows and Steam Deck (1280x800) resolutions: no clipping or overlap", bad.is_empty(), "; ".join(bad.slice(0, 4)))
	root.size = saved_win
	ui.options.ui_scale = saved_scale
	await process_frame


## P. Manual aim is gone from controls, menus and every help text; the tutorial describes automatic targeting.
func t_action_cluster_and_map() -> void:
	var inp = g.input
	var ui = g.ui
	var saved_lh: bool = ui.options.touch_left_handed
	var bad: Array[String] = []
	for lh in [false, true]:
		ui.options.touch_left_handed = lh
		for view in [Vector2(1280, 580), Vector2(1589, 720), Vector2(1920, 886), Vector2(2400, 1080), Vector2(960, 720)]:
			var lay: Dictionary = inp.touch_layout(view)
			var atk := {}
			var map := {}
			for b in lay.buttons:
				if b.action == "attack":
					atk = b
				elif b.action == "map":
					map = b
			if map.is_empty():
				bad.append("no MAP button %dx%d" % [view.x, view.y])
				continue
			for i in lay.buttons.size():
				var bi: Dictionary = lay.buttons[i]
				if bi.pos.x - bi.r < 0.0 or bi.pos.x + bi.r > view.x or bi.pos.y - bi.r < 0.0 or bi.pos.y + bi.r > view.y:
					bad.append("%s outside %dx%d" % [bi.action, view.x, view.y])
				for j in range(i + 1, lay.buttons.size()):
					var bj: Dictionary = lay.buttons[j]
					if bi.action in ["use_water", "use_bandage", "use_food", "sprint", "pause"] and bj.action in ["use_water", "use_bandage", "use_food", "sprint", "pause"]:
						continue
					var gap: float = bi.pos.distance_to(bj.pos) - bi.r - bj.r
					if gap < 8.0:
						bad.append("%s/%s gap %.0f at %dx%d%s" % [bi.action, bj.action, gap, view.x, view.y, " lefty" if lh else ""])
			var side := signf(atk.pos.x - map.pos.x)
			if (side > 0.0) == lh:
				bad.append("MAP is not on the inner side of ATTACK (lefty %s)" % lh)
			var mgap: float = map.pos.distance_to(atk.pos) - map.r - atk.r
			if mgap < 40.0 * inp.touch_scale() * 0.5:
				bad.append("MAP too close to ATTACK (%.0f)" % mgap)
	ui.options.touch_left_handed = saved_lh
	_ok("action cluster: arc around ATTACK, every button apart, MAP on the inner side and well clear of ATTACK", bad.is_empty(), ", ".join(bad))

	# MAP toggles the minimap; hidden by default
	_ok("minimap is hidden by default on touch", GameOptions.new().minimap_on == false)
	ui.options.minimap_on = false
	g.set_state("playing")
	_ready_player()
	ui.options.tips_enabled = false
	ui.tips.dismiss()
	var lay2: Dictionary = inp.touch_layout()
	var mp := Vector2.ZERO
	for b in lay2.buttons:
		if b.action == "map":
			mp = b.pos
	_tap(9, mp)
	_tap(9, mp, false)
	await _frames(2)
	_ok("tapping MAP shows the minimap", ui.options.minimap_on)
	_tap(9, mp)
	_tap(9, mp, false)
	await _frames(2)
	_ok("tapping MAP again hides it", not ui.options.minimap_on)
	_ok("MAP tap does not attack or move", not inp.fire and inp.move == Vector2.ZERO)

	# the stat panel may use the cutout side (bars hug the left edge)
	var keep_ins: Vector4 = inp.debug_insets
	inp.debug_insets = Vector4(120, 0, 0, 0)
	ui._apply_safe_area()
	_ok("HUD left inset is capped so the stat bars sit at the left edge", ui.hud.offset_left <= 20.0, "offset %.0f" % ui.hud.offset_left)
	inp.debug_insets = keep_ins
	ui._apply_safe_area()


func t_no_manual_aim_and_tutorial() -> void:
	var T = load("res://scripts/ui/tutorial_data.gd")
	var inp = g.input
	var banned := ["right stick", "right joystick", "aim assist", "aim with", "drag the right", "right side drag", "aim stick", "aim by hand"]
	var bad: Array[String] = []
	var howto = g.ui.screens["howto"]
	for m in ["touch", "gamepad"]:
		var text := ""
		for pg in T.PAGES:
			text += " ".join(howto._visible_lines(pg.lines, m)) + " "
		for k in T.TIPS:
			text += inp.fill(str(T.TIPS[k].text), m) + " "
		for row in inp.controls_list(m):
			text += " ".join(row) + " "
		var low := text.to_lower()
		for b in banned:
			if low.contains(b):
				bad.append("%s mentions '%s'" % [m, b])
		if not low.contains("automatically faces the nearest enemy") and not low.contains("auto-target"):
			bad.append("%s lacks the automatic targeting text" % m)
		if not low.contains("walls block targeting"):
			bad.append("%s does not say walls block targeting" % m)
		if not low.contains("even backward or sideways while attacking"):
			bad.append("%s does not explain moving while attacking" % m)
		if not low.contains("no manual aiming is needed"):
			bad.append("%s does not say no manual aiming is needed" % m)
	var kb := ""
	for pg in T.PAGES:
		kb += " ".join(howto._visible_lines(pg.lines, "keyboard")) + " "
	if not kb.to_lower().contains("aim with the mouse"):
		bad.append("keyboard help lost the mouse-aim line")
	_ok("P: tutorial, tips and control lists describe automatic targeting; no manual-aim wording on touch or pad", bad.is_empty(), "; ".join(bad.slice(0, 4)))

	# the right AIM stick is gone from the touch layout and from input; empty right-half touches do nothing
	var lay: Dictionary = inp.touch_layout()
	var vp: Vector2 = g.ui.get_viewport().get_visible_rect().size
	g.ui.options.control_mode = 3
	g.set_state("playing")
	_tap(3, Vector2(vp.x * 0.85, vp.y * 0.2))
	var right_stick_made: bool = inp._sticks.size() != 1 or inp._sticks.left.id == 3
	_tap(3, Vector2(vp.x * 0.85, vp.y * 0.2), false)
	_ok("P2: no right aim joystick (layout, input state and touch zones)", not lay.has("aim_c") and not right_stick_made)
	var labels := ""
	for key in ["pause", "title"]:
		var scr = g.ui.screens[key]
		for it in scr.menu.items:
			labels += String(it.get("label", "")) + "|"
	for it in g.ui.screens["options"].pad_menu.items:
		labels += String(it.get("label", "")) + "|"
	_ok("P3: no 'Aim Assist' option remains in the title, pause or controller menus", not labels.to_lower().contains("aim"), labels)
