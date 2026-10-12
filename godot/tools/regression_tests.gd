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
