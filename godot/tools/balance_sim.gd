extends SceneTree
## Headless balance simulation: drives a scripted "competent player" bot through res://scenes/game.tscn.
##
## godot --headless --path godot -s tools/balance_sim.gd -- <difficulty 1-4> <seconds> <seed> [weapons=machete|best] [skill=kite|brawl] [reaction=0.25]
##
## Prints one `RESULT {json}` line per run (per-day stats included). tools/run_balance.py aggregates them.
## The sim ticks game._physics_process manually at 60 Hz (no rendering, no real-time wait).
## This folder is excluded from exports (export_presets.cfg exclude_filter tools/**).

const Pathing = preload("res://scripts/enemies/pathing.gd")
const DT := 1.0 / 60.0
const PERK_RANK := ["tough_skin", "second_wind", "heavy_hitter", "marathon", "quick_feet", "thick_skull",
		"field_medic", "trigger_finger", "ammo_cache", "clear_mind", "deep_reservoir", "boom_boom"]
const DIRS := 16


class BotInput extends GameInput:
	func setup(g) -> void:
		game = g
	func tick(_dt: float) -> void:
		pass
	func end_frame() -> void:
		_just.clear()
	func active_mode() -> String:
		return "keyboard"


var game
var bot: BotInput
var diff := 1
var max_secs := 600.0
var seed_v := 1
var weapon_policy := "machete"
var skill := "kite"
var reaction := 0.25            # seconds before the bot reacts to an enemy wind-up (human-ish)

# bookkeeping
var days: Array = []
var cur: Dictionary = {}
var last_day := 1
var cause := {}                 # kind -> damage total (run)
var last_hit_kind := ""
var heal_found := {"bandage": 0, "almond": 0, "food": 0}
var heal_used := {"bandage": 0, "almond": 0, "food": 0}
var prev_counts := {}
var use_cd := 0.0
var wp_timer := 0.0
var wp := Vector2.INF
var explore_dir := Vector2.RIGHT
var explore_t := 0.0
var stuck_pos := Vector2.ZERO
var stuck_t := 0.0
var unstick_t := 0.0
var unstick_dir := Vector2.ZERO
var windup_seen := {}           # enemy instance id -> seconds in wind-up observed
var perks_taken: Array = []
var finished := false
var rng := RandomNumberGenerator.new()
var done_emitted := false
var tick_count := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	diff = int(args[0]) if args.size() > 0 else 1
	max_secs = float(args[1]) if args.size() > 1 else 600.0
	seed_v = int(args[2]) if args.size() > 2 else 1
	for a in args.slice(3):
		if a.begins_with("weapons="): weapon_policy = a.substr(8)
		elif a.begins_with("skill="): skill = a.substr(6)
		elif a.begins_with("reaction="): reaction = float(a.substr(9))
	seed(seed_v)
	rng.seed = seed_v * 7919 + 13
	var scene: PackedScene = load("res://scenes/game.tscn")
	game = scene.instantiate()
	root.add_child(game)


func _setup() -> void:
	game.set_physics_process(false)
	var last = game.get_child(game.get_child_count() - 1)
	if last.get_script() and str(last.get_script().resource_path).ends_with("splash.gd"):
		last.queue_free()
	# swap in the scripted input
	bot = BotInput.new()
	var old = game.input
	game.systems[game.systems.find(old)] = bot
	game.add_child(bot)
	game.input = bot
	game.ui.input = bot
	old.queue_free()
	game.ui.progression.active_idx = -1          # never touch the save file
	game.ui.difficulty = diff
	if game.objects:
		game.objects.rng.seed = seed_v * 31 + 5
	if game.weapons:
		game.weapons._rng.seed = seed_v * 17 + 3
	game.start_run()
	game.player.noise = 0.0
	game.player.damaged.connect(_on_damaged)
	_new_day(1)
	prev_counts = _counts()


var setup_done := false


func _process(_delta: float) -> bool:
	if not setup_done:
		setup_done = true
		_setup()
		return false
	# run up to ~0.25 s wall time of sim per frame
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 250 and not finished:
		_step()
	if finished:
		if not done_emitted:
			done_emitted = true
			_emit()
		return true
	return false


func _step() -> void:
	tick_count += 1
	if game.state == "perk":
		_pick_perk()
	elif game.state == "portal":
		game.ui.dismiss_portal_prompt()
	if game.state == "playing":
		_bot(DT)
		_help_items(DT)
	game._physics_process(DT)
	_track(DT)
	if tick_count % 1200 == 0:
		printerr("t=%.0f day=%d kills=%d hp=%.0f enemies=%d wall=%dms" % [game.run_time, game.day, game.kills, game.player.hp, game.enemies.list.size(), Time.get_ticks_msec()])
	if game.state == "dead" or game.run_time >= max_secs:
		finished = true


# ---------------------------------------------------------------------------------------------
# bookkeeping
# ---------------------------------------------------------------------------------------------

func _new_day(d: int) -> void:
	cur = {"day": d, "kills0": game.kills, "dmg": {}, "hp_min": game.player.hp, "hp_sum": 0.0, "st_sum": 0.0, "n": 0,
			"enemies_sum": 0.0, "hits": 0, "heal_used0": heal_used.duplicate(), "heal_found0": heal_found.duplicate(),
			"star_ticks": 0}


func _close_day() -> void:
	var p = game.player
	var n := maxi(1, int(cur.n))
	days.append({
		"day": cur.day, "kills": game.kills - cur.kills0, "dmg": cur.dmg, "hits": cur.hits,
		"hp_min": snappedf(cur.hp_min, 0.1), "hp_avg": snappedf(cur.hp_sum / n, 0.1), "hp_end": snappedf(p.hp, 0.1), "max_hp": p.max_hp,
		"stam_avg": snappedf(cur.st_sum / n, 0.1), "stam_empty_pct": snappedf(100.0 * cur.star_ticks / n, 0.1),
		"sanity_end": snappedf(p.sanity, 0.1), "hydr_end": snappedf(p.hydration, 0.1),
		"enemies_avg": snappedf(cur.enemies_sum / n, 0.1), "level": p.level,
		"heal_found": {"bandage": heal_found.bandage - cur.heal_found0.bandage, "almond": heal_found.almond - cur.heal_found0.almond, "food": heal_found.food - cur.heal_found0.food},
		"heal_used": {"bandage": heal_used.bandage - cur.heal_used0.bandage, "almond": heal_used.almond - cur.heal_used0.almond, "food": heal_used.food - cur.heal_used0.food},
		"bandages_held": p.bandages, "almond_held": p.almond_water, "batteries_held": p.batteries,
	})


func _counts() -> Dictionary:
	var p = game.player
	return {"bandage": p.bandages, "almond": p.almond_water, "food": p.food}


func _track(_dt: float) -> void:
	var p = game.player
	if game.state != "playing" and game.state != "dead":
		return
	var d: int = game.day
	if d != last_day:
		_close_day()
		last_day = d
		_new_day(d)
	cur.n += 1
	cur.hp_sum += p.hp
	cur.st_sum += p.stamina
	cur.hp_min = minf(cur.hp_min, p.hp)
	cur.enemies_sum += game.enemies.list.size()
	if p.stamina < 12.0:
		cur.star_ticks += 1
	var now := _counts()
	for k in now:
		var dn: int = now[k] - prev_counts[k]
		if dn > 0:
			heal_found[k] += dn
	prev_counts = now


func _on_damaged(amount: float) -> void:
	var p = game.player
	var best := "other"
	var bd := 3.2
	for e in game.enemies.list:
		if not is_instance_valid(e):
			continue
		var dd: float = e.tile_pos.distance_to(p.tile_pos)
		if dd < bd:
			bd = dd
			best = e.kind
	cause[best] = cause.get(best, 0.0) + amount
	cur.dmg[best] = cur.dmg.get(best, 0.0) + amount
	cur.hits += 1
	last_hit_kind = best


func _emit() -> void:
	if cur.n > 0:
		_close_day()
	var p = game.player
	var res := {
		"diff": diff, "seed": seed_v, "weapons": weapon_policy, "skill": skill,
		"died": game.state == "dead", "time": snappedf(game.run_time, 0.1), "day": game.day, "kills": game.kills,
		"level": p.level, "max_hp": p.max_hp, "cause": last_hit_kind, "dmg_by": cause, "perks": perks_taken,
		"heal_found": heal_found, "heal_used": heal_used, "weapons_unlocked": game.weapons.get_unlocked_list(),
		"days": days,
	}
	print("RESULT ", JSON.stringify(res))


# ---------------------------------------------------------------------------------------------
# perk choice
# ---------------------------------------------------------------------------------------------

func _pick_perk() -> void:
	var ch: Array = game.ui.perk_choices
	if ch.size() < 2:
		return
	var r0 := PERK_RANK.find(ch[0].id)
	var r1 := PERK_RANK.find(ch[1].id)
	if r0 < 0: r0 = 99
	if r1 < 0: r1 = 99
	var idx := 0 if r0 <= r1 else 1
	perks_taken.append(ch[idx].id)
	game.ui.choose_perk(idx)


# ---------------------------------------------------------------------------------------------
# the bot
# ---------------------------------------------------------------------------------------------

func _help_items(dt: float) -> void:
	# item nodes finish their pop/launch animation in _process (real time); advance them in sim time
	for it in game.objects.items:
		if is_instance_valid(it) and (it._fly_t < 1.0 or it.age < 0.6):
			it.age += dt
			if it._fly_t < 1.0:
				it._fly_t = minf(1.0, it._fly_t + dt / it._fly_dur)


func _free_dir(pos: Vector2, dir: Vector2, dist: float) -> bool:
	var m = game.map
	var side := Vector2(-dir.y, dir.x) * 0.28
	var s := 0.35
	while s <= dist:
		var q := pos + dir * s
		if m.is_solid(q.x, q.y) or m.is_solid(q.x + side.x, q.y + side.y) or m.is_solid(q.x - side.x, q.y - side.y):
			return false
		s += 0.35
	return true


## Best walkable direction close to `want` (unit vector); Vector2.ZERO if boxed in.
func _steer(pos: Vector2, want: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var best_score := -9.0
	for i in DIRS:
		var d := Vector2.from_angle(TAU * i / DIRS)
		if not _free_dir(pos, d, 1.4):
			continue
		var sc := d.dot(want)
		if _free_dir(pos, d, 3.0):
			sc += 0.15
		if sc > best_score:
			best_score = sc
			best = d
	return best


func _use(action: String) -> void:
	bot.press(action)
	use_cd = 0.4


func _bot(dt: float) -> void:
	var g = game
	var p = g.player
	bot.move = Vector2.ZERO
	bot.fire = false
	bot.sprint = false
	use_cd = maxf(0.0, use_cd - dt)
	var pos: Vector2 = p.tile_pos

	# ---- consumables
	if use_cd <= 0.0:
		if p.hp < p.max_hp * 0.7 and p.hp <= p.max_hp - 30.0 and p.bandages > 0:
			heal_used.bandage += 1
			_use("use_bandage")
		elif p.hp < p.max_hp * 0.5 and p.almond_water > 0:
			heal_used.almond += 1
			_use("use_water")
		elif p.hydration < 35.0 and p.almond_water > 0:
			heal_used.almond += 1
			_use("use_water")
		elif p.food > 0 and p.stamina < 20.0:
			heal_used.food += 1
			_use("use_food")
		elif g.lighting.battery < 6.0 and p.batteries > 0:
			_use("battery")

	_choose_weapon()
	var wep: Dictionary = g.weapons.get_current()
	var melee: bool = wep.type == "melee"
	var wreach: float = float(wep.get("reach", 8.0)) if melee else 9.0

	# ---- gather threats
	var threats: Array = []
	var nearest = null
	var nd := 999.0
	for e in g.enemies.list:
		if not is_instance_valid(e) or e.dead:
			continue
		var d: float = e.tile_pos.distance_to(pos)
		if d < 12.0 and (e.state == "hunt" or d < 5.0):
			threats.append(e)
			if d - e.radius < nd:
				nd = d - e.radius
				nearest = e

	# bomb when swarmed
	if g.weapons.bomb.count > 0 and use_cd <= 0.0:
		var close := 0
		for e in threats:
			if e.tile_pos.distance_to(pos) < 3.2:
				close += 1
		if close >= 4 or (close >= 2 and p.hp < p.max_hp * 0.35):
			_use("bomb")

	if nearest != null:
		_fight(p, pos, threats, nearest, melee, wreach, dt)
	else:
		_roam(p, pos, dt)
	_unstick(pos, dt)


func _choose_weapon() -> void:
	var w = game.weapons
	var want := 0
	if weapon_policy == "best":
		if w.ammo > 0:
			for idx in [5, 6, 4, 7]:
				if w.is_unlocked(idx):
					want = idx
					break
		if want == 0:
			for idx in [3, 0]:
				if w.is_unlocked(idx):
					want = idx
					break
	if w.current != want and w.is_unlocked(want):
		w.set_weapon(want)


func _fight(p, pos: Vector2, threats: Array, nearest, melee: bool, wreach: float, dt: float) -> void:
	var inp := bot
	var nd: float = nearest.tile_pos.distance_to(pos)
	inp.aim_world = nearest.tile_pos * game.TILE
	var in_reach: bool = nd - nearest.radius < wreach - 0.15
	if in_reach:
		inp.fire = true
	var flee := Vector2.ZERO
	var danger := false
	var urgent := false
	for e in threats:
		var d: float = e.tile_pos.distance_to(pos)
		var safe: float = e.reach + 0.55
		if e.atk_phase == "windup":
			var k: int = e.get_instance_id()
			windup_seen[k] = windup_seen.get(k, 0.0) + dt
			if windup_seen[k] >= reaction and d <= e.reach + 0.35:
				danger = true
				urgent = true
				flee += (pos - e.tile_pos).normalized() * 3.0
		else:
			windup_seen.erase(e.get_instance_id())
			if d < safe:
				danger = true
				flee += (pos - e.tile_pos).normalized() * (safe - d + 0.5)
	if skill == "brawl":
		# stands and trades; walks into melee reach of the target
		if melee and not in_reach:
			bot.move = _steer(pos, (nearest.tile_pos - pos).normalized())
		return
	if danger and flee != Vector2.ZERO:
		var dir := _steer(pos, flee.normalized())
		inp.move = dir
		if urgent and p.stamina > 30.0 and dir != Vector2.ZERO:
			inp.sprint = true
	elif melee and not in_reach and nd < 7.0 and nearest.state != "hunt":
		inp.move = _steer(pos, (nearest.tile_pos - pos).normalized()) * 0.6


func _need_weight(kind: String, p) -> float:
	match kind:
		"bandage": return 3.0 if p.bandages < 6 else 1.0
		"almond water": return 3.0 if p.almond_water < 6 else 1.0
		"food": return 2.0 if p.food < 3 else 1.0
		"stamina drink": return 2.0
		"ammo": return 2.5 if weapon_policy == "best" else 0.4
		"weapon": return 3.0
		"battery": return 2.0 if p.batteries < 3 else 0.8
		"bomb": return 1.5
	return 1.0


func _roam(p, pos: Vector2, dt: float) -> void:
	var target := Vector2.INF
	var best := 0.0
	for it in game.objects.items:
		if not is_instance_valid(it) or it.collected:
			continue
		var d: float = it.tile_pos.distance_to(pos)
		if d > 16.0:
			continue
		var sc := _need_weight(it.kind, p) / (1.0 + d * 0.25)
		if sc > best:
			best = sc
			target = it.tile_pos
	if target == Vector2.INF:
		explore_t -= dt
		if explore_t <= 0.0 or not _free_dir(pos, explore_dir, 1.5):
			explore_t = 4.0 + rng.randf() * 4.0
			explore_dir = Vector2.from_angle(rng.randf() * TAU)
		target = pos + explore_dir * 14.0
	wp_timer -= dt
	if wp_timer <= 0.0 or wp == Vector2.INF:
		wp = Pathing.next_waypoint(game.map, pos, target)
		wp_timer = 0.35
	var dest: Vector2 = wp if wp != Vector2.INF else target
	var to := dest - pos
	if to.length() > 0.1:
		var dir := _steer(pos, to.normalized())
		bot.move = dir
		bot.aim_world = (pos + (dir if dir != Vector2.ZERO else to.normalized())) * game.TILE


func _unstick(pos: Vector2, dt: float) -> void:
	if unstick_t > 0.0:
		unstick_t -= dt
		bot.move = unstick_dir
		return
	stuck_t += dt
	if stuck_t >= 2.0:
		if pos.distance_to(stuck_pos) < 0.4 and bot.move != Vector2.ZERO and not bot.fire:
			unstick_t = 1.2
			unstick_dir = Vector2.from_angle(rng.randf() * TAU)
			explore_t = 0.0
		stuck_pos = pos
		stuck_t = 0.0
