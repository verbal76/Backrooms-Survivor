extends Node
## Enemy manager (port of enemies.lua spawning/collision + the spawn loop in main.lua). See godot/ARCHITECTURE.md.
## Public API: get_enemies(), spawn(kind, tile_pos), spawn_chest_swarm(), spawn_portal_horde(), count_portal_guards(),
## set_difficulty(idx), drop_chance(kind), reset_run().

const EnemyScript = preload("res://scripts/enemies/enemy.gd")
const Pathing = preload("res://scripts/enemies/pathing.gd")

## Enemy type table (Enemies.types). `idx` is the Lua typeIdx - 1.
const TYPES := {
	"hound":        {"idx": 0, "reach": 1.0, "windup": 0.30, "recover": 0.7, "hp": 15, "speed": 3.2, "dmg": 12, "radius": 0.35, "scale": 0.4,  "color": Color(0.85, 0.15, 0.1),  "xp": 2, "drop": 0.12, "noise": 2.5, "fear": 0.6},
	"crawler":      {"idx": 1, "reach": 1.7, "windup": 0.5, "recover": 0.9, "hp": 50, "speed": 0.9, "dmg": 20, "radius": 0.5,  "scale": 0.4,  "color": Color(0.2, 0.7, 0.15),   "xp": 4, "drop": 0.2,  "noise": 1.5, "fear": 0.2},
	"wretch":       {"idx": 2, "reach": 0.75, "windup": 0.25, "recover": 0.6, "hp": 10, "speed": 4.0, "dmg": 5,  "radius": 0.25, "scale": 0.65, "color": Color(0.95, 0.85, 0.2),  "xp": 1, "drop": 0.08, "noise": 2.0, "fear": 0.6},
	"shade":        {"idx": 3, "reach": 1.0, "windup": 0.3, "recover": 0.8, "hp": 20, "speed": 2.0, "dmg": 18, "radius": 0.3,  "scale": 0.7,  "color": Color(0.35, 0.15, 0.55), "xp": 3, "drop": 0.15, "noise": 1.0, "fear": 1.0},
	"skin stealer": {"idx": 4, "reach": 1.6, "windup": 0.45, "recover": 1.0, "hp": 80, "speed": 1.5, "dmg": 35, "radius": 0.55, "scale": 1.25, "color": Color(0.9, 0.4, 0.15),   "xp": 8, "drop": 0.3,  "noise": 1.5, "fear": 0.0},
}
const KINDS := ["hound", "crawler", "wretch", "shade", "skin stealer"]
const SHEET_FILES := {
	"hound": "res://assets/enemies/enemy_hound_spritesheet.png",
	"crawler": "res://assets/enemies/enemy_crawler_spritesheet.png",
	"wretch": "res://assets/enemies/enemy_wretch_spritesheet.png",
	"shade": "res://assets/enemies/enemy_shade_spritesheet.png",
	"skin stealer": "res://assets/enemies/enemy_skinstealer_spritesheet.png",
}

const SPAWN_RATE := 3.0            # Enemies.spawnRate
const START_MAX := 32              # Enemies.maxEnemies
const CAP_RADIUS := 26.0           # BALANCE: enemies farther than this don't count against the spawn cap
const DESPAWN_DIST := 35.0        # tiles
const PLAYER_BODY_R := 0.3         # radius passed to checkPlayerCollision
const HEADLAMP_RADIUS := 14.0
const HEADLAMP_CONE := 0.85
const HEADLAMP_DPS := 1.25
const PATH_BUDGET := 4             # BFS path searches per physics frame

# Difficulty tables from main.lua startGame, index 1..4 (Easy, Normal, Getting Worse, Hell).
const DIFF_HP := [1.0, 1.0, 1.15, 1.2]
const DIFF_DMG := [0.65, 0.90, 1.1, 1.15]
const DIFF_SPD := [0.95, 1.0, 1.03, 1.08]
const DIFF_SPAWN := [1.0, 1.3, 1.7, 2.2]
const WAVE_BONUS := [1, 3, 3, 4]   # BALANCE (new): added to the day for spawn mix / rate / cap / hp+dmg scaling
const DIFF_CAP := [60, 80, 100, 120]

var game
var list: Array = []               # living enemies (Enemy nodes)
var corpses: Array = []            # dying enemies playing their death animation
var difficulty_idx := 1            # main.lua default: Easy
var hp_mult := 1.0
var dmg_mult := 1.0
var spd_mult := 1.0
var spawn_scale := 1.5
var diff_cap := 90
var max_enemies := START_MAX
var spawn_timer := 0.0
var spawning_enabled := true
var _paths_left := PATH_BUDGET
var _sheets := {}
var _hash := {}


func setup(p_game) -> void:
	game = p_game
	set_difficulty(difficulty_idx)


func set_difficulty(idx: int) -> void:
	difficulty_idx = clampi(idx, 1, 4)
	var i := difficulty_idx - 1
	hp_mult = DIFF_HP[i]
	dmg_mult = DIFF_DMG[i]
	spd_mult = DIFF_SPD[i]
	spawn_scale = DIFF_SPAWN[i]
	diff_cap = DIFF_CAP[i]


func reset_run() -> void:
	for e in list:
		if is_instance_valid(e):
			e.queue_free()
	list.clear()
	for c in corpses:
		if is_instance_valid(c):
			c.queue_free()
	corpses.clear()
	spawn_timer = 0.0
	max_enemies = START_MAX


# ---------------------------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------------------------

func get_enemies() -> Array:
	return list


## Chance (0..1) an enemy of this kind drops loot on death (for the objects system; not rolled here).
func drop_chance(kind: String) -> float:
	return TYPES[kind].drop if TYPES.has(kind) else 0.0


## Spawn one enemy. `kind` is a name ("hound", "skin stealer", ...) or a 1-based Lua type index.
func spawn(kind, tile_pos: Vector2, hunting := false, wave := -1):
	var name: String = KINDS[clampi(int(kind) - 1, 0, 4)] if (kind is int or kind is float) else String(kind)
	if not TYPES.has(name):
		push_warning("enemies: unknown kind '%s'" % name)
		return null
	var e = EnemyScript.new()
	e.setup(game, self, name, TYPES[name], tile_pos, game.day if wave < 0 else wave, hp_mult, spd_mult, dmg_mult)
	if hunting:
		e.state = "hunt"
		e.alert_level = 100.0
		e.has_seen = true
		e.last_seen = game.player.tile_pos
	game.world.add_child(e)
	list.append(e)
	return e


## Burst-spawn a hostile pack around a military chest room (60% hounds, 40% wretches).
func spawn_chest_swarm(center: Vector2, count := 8) -> int:
	var n := 0
	for i in count:
		if list.size() >= max_enemies + 10:
			break
		for t in 20:
			var p := center + Vector2.from_angle(randf() * TAU) * (3.0 + randf() * 5.0)
			if not game.map.is_solid(p.x, p.y):
				spawn("hound" if randf() < 0.6 else "wretch", p, true)
				n += 1
				break
	return n


## Late-game horde guarding the exit portal (all five types; flagged portal_guard).
func spawn_portal_horde(center: Vector2, count := 15) -> int:
	var n := 0
	for i in count:
		if list.size() >= max_enemies + 20:
			break
		for t in 25:
			var p := center + Vector2.from_angle(randf() * TAU) * (2.0 + randf() * 6.0)
			if not game.map.is_solid(p.x, p.y):
				var roll := randf()
				var k := "hound"
				if roll >= 0.75: k = "skin stealer"
				elif roll >= 0.55: k = "shade"
				elif roll >= 0.35: k = "wretch"
				elif roll >= 0.20: k = "crawler"
				var e = spawn(k, p, true, maxi(game.day, 30))
				e.portal_guard = true
				e.drop_chance *= 0.5
				n += 1
				break
	return n


func count_portal_guards() -> int:
	var c := 0
	for e in list:
		if e.portal_guard:
			c += 1
	return c


# ---------------------------------------------------------------------------------------------
# Hooks used by Enemy nodes
# ---------------------------------------------------------------------------------------------

func get_sheet(kind: String) -> Texture2D:
	if not _sheets.has(kind):
		_sheets[kind] = load(SHEET_FILES[kind])
	return _sheets[kind]


func take_path_budget() -> bool:
	if _paths_left <= 0:
		return false
	_paths_left -= 1
	return true


func on_enemy_dead(e) -> void:
	list.erase(e)
	corpses.append(e)


## Light level at a tile. Uses the lighting system's `light_at_tile(Vector2)` when it has one; otherwise
## a fallback (the Lua map:getLightLevel is a constant 0.05 for AI, a headlamp estimate for drawing).
func light_at(tile: Vector2, visual := false) -> float:
	if game.lighting and game.lighting.has_method("light_at_tile"):
		return game.lighting.light_at_tile(tile)
	if not visual:
		return 0.05
	var pl = game.player
	var d: Vector2 = tile - pl.tile_pos
	var dist := d.length()
	var l := 0.18 + clampf(1.0 - dist / 5.0, 0.0, 1.0) * 0.5
	if pl.headlamp_on and dist < HEADLAMP_RADIUS and dist > 0.1:
		if absf(angle_difference(pl.angle, d.angle())) < HEADLAMP_CONE:
			l = maxf(l, 1.0 - dist / HEADLAMP_RADIUS * 0.6)
	return minf(l, 1.0)


# ---------------------------------------------------------------------------------------------
# Tick
# ---------------------------------------------------------------------------------------------

func tick(dt: float) -> void:
	var pl = game.player
	if pl == null:
		return
	_paths_left = PATH_BUDGET
	var ppos: Vector2 = pl.tile_pos
	var wave: int = game.day + WAVE_BONUS[difficulty_idx - 1]   # BALANCE: harder modes start further up the ramp

	# spawning (main.lua): rate speeds up per day, cap grows per day
	max_enemies = mini(diff_cap, 30 + wave * 2)
	if spawning_enabled:
		spawn_timer += dt
		var rate := maxf(0.90, SPAWN_RATE - wave * 0.07) / spawn_scale
		if spawn_timer >= rate:
			spawn_timer = 0.0
			_spawn_random(ppos, wave)

	# despawn far-away enemies (frees cap for nearby spawns); portal guards stay
	var i := list.size() - 1
	while i >= 0:
		var e = list[i]
		if not is_instance_valid(e):
			list.remove_at(i)
		elif not e.portal_guard and e.tile_pos.distance_squared_to(ppos) > DESPAWN_DIST * DESPAWN_DIST:
			list.remove_at(i)
			e.queue_free()
		i -= 1

	# AI + animation. Iterate over a copy: a death during the tick edits `list`.
	for e in list.duplicate():
		if is_instance_valid(e):
			e.tick(dt, light_at(e.tile_pos))
	var j := corpses.size() - 1
	while j >= 0:
		var c = corpses[j]
		if is_instance_valid(c):
			c.tick(dt, 0.0)
		else:
			corpses.remove_at(j)
		j -= 1

	_separate(ppos, dt)
	_player_contact(ppos)
	_headlamp_damage(dt, pl)
	for e in list:
		e.unstick()


## Port of Enemies:spawn - random ring around the player, weights by day, clear 3x3 spot.
func _spawn_random(ppos: Vector2, wave: int) -> void:
	# BALANCE: the cap only counts enemies near the player. Counting far-away idle wanderers let the cap fill
	# up with harmless monsters so nothing new spawned close by (kills/day collapsed to ~10 by day 5).
	var near := 0
	for e in list:
		if e.tile_pos.distance_squared_to(ppos) < CAP_RADIUS * CAP_RADIUS:
			near += 1
	if near >= max_enemies:
		return
	for tries in 30:
		var p := ppos + Vector2.from_angle(randf() * TAU) * (10.0 + randf() * 8.0)
		var roll := randf()
		var idx: int
		if wave < 5:
			idx = 0 if roll < 0.40 else (2 if roll < 0.80 else 3)
		elif wave < 11:
			if roll < 0.25: idx = 0
			elif roll < 0.40: idx = 1
			elif roll < 0.65: idx = 2
			elif roll < 0.85: idx = 3
			else: idx = 4
		elif wave < 21:
			if roll < 0.20: idx = 0
			elif roll < 0.35: idx = 1
			elif roll < 0.50: idx = 2
			elif roll < 0.70: idx = 3
			else: idx = 4
		else:
			idx = randi_range(0, 4)
		var t: Dictionary = TYPES[KINDS[idx]]
		var r: float = t.radius + 0.12
		if _clear_at(p, r):
			spawn(KINDS[idx], p, false, wave)
			return


func _clear_at(p: Vector2, r: float) -> bool:
	var m = game.map
	for o in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r),
			Vector2(r, r), Vector2(-r, r), Vector2(r, -r), Vector2(-r, -r)]:
		if m.is_solid(p.x + o.x, p.y + o.y):
			return false
	return true


## Gentle push so a pack doesn't stack on one pixel (not in the Lua).
func _separate(ppos: Vector2, dt: float) -> void:
	_hash.clear()
	for e in list:
		if e.tile_pos.distance_squared_to(ppos) > 400.0:
			continue
		var k := Vector2i(floori(e.tile_pos.x), floori(e.tile_pos.y))
		if _hash.has(k):
			_hash[k].append(e)
		else:
			_hash[k] = [e]
	for k in _hash:
		for e in _hash[k]:
			for ox in range(-1, 2):
				for oy in range(-1, 2):
					var cell = _hash.get(Vector2i(k.x + ox, k.y + oy))
					if cell == null:
						continue
					for o in cell:
						if o == e:
							continue
						var d: Vector2 = e.tile_pos - o.tile_pos
						var min_d: float = (e.radius + o.radius) * 0.9
						var l2 := d.length_squared()
						if l2 < min_d * min_d:
							var l := sqrt(l2)
							var push: Vector2 = (d / l if l > 0.001 else Vector2.from_angle(randf() * TAU)) * (min_d - l) * minf(dt * 8.0, 1.0)
							var np: Vector2 = e.tile_pos + push
							if not game.map.is_solid(np.x, np.y):
								e.tile_pos = np


## Enemies:checkPlayerCollision - overlap + LOS -> contact damage.
func _player_contact(ppos: Vector2) -> void:
	for e in list.duplicate():
		if not is_instance_valid(e) or e.dead:
			continue
		if e.tile_pos.distance_to(ppos) < e.radius + PLAYER_BODY_R:
			if Pathing.has_los(game.map, e.tile_pos, ppos):
				e.touch_player(ppos)


## Headlamp beam burns light-fearing enemies (main.lua "HEADLAMP LIGHT DAMAGE", 1.25 hp/s).
func _headlamp_damage(dt: float, pl) -> void:
	if not pl.headlamp_on:
		return
	if game.lighting and game.lighting.has_method("headlamp_active") and not game.lighting.headlamp_active():
		return
	for e in list.duplicate():
		if e.light_fear <= 0.0 or e.dead:
			continue
		var d: Vector2 = e.tile_pos - pl.tile_pos
		var dist := d.length()
		if dist < HEADLAMP_RADIUS and dist > 0.1 and absf(angle_difference(pl.angle, d.angle())) < HEADLAMP_CONE:
			var closeness := 1.0 - dist / HEADLAMP_RADIUS
			e.hp -= HEADLAMP_DPS * e.light_fear * closeness * dt
			e.hit_flash = maxf(e.hit_flash, 0.05)
			if e.hp <= 0.0:
				e._die(d.normalized())
