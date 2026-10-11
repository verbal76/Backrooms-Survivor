extends Node
## Environmental traps system (`game.traps`). Uses the CC0 "Animated Traps" pack (Stealtrix) in
## assets/third_party/animated_traps/. Original to the Godot port (the LOVE game has no traps).
## Public API: spawn_trap(kind, tile_pos, dir := Vector2.RIGHT) -> TrapNode, traps (Array of TrapNode),
## trap_near(tile_pos, dist) -> bool, hurt_player / hurt_enemy / ignite_* / root_player helpers used by trap_node.gd.
## Contract: setup(game), tick(dt), reset_run().

const TrapNode = preload("res://scripts/traps/trap_node.gd")

# ---- placement ----------------------------------------------------------------------------------
const KINDS := ["bear", "spike", "pit", "fire", "push"]
const WEIGHTS := {"bear": 3.0, "spike": 3.0, "pit": 2.0, "fire": 2.0, "push": 2.0}
const BASE_PER_CHUNK := 2.0          # traps per 48x48 chunk on day 1, Easy
const PER_DAY := 0.15                # + per day survived (capped by DAY_CAP)
const DAY_CAP := 10
const PER_DIFFICULTY := 0.3          # + per difficulty step above Easy (1..4)
const MAX_PER_CHUNK := 5
const SPAWN_SAFE := 14.0             # tiles around the spawn point with no traps
const PLAYER_SAFE := 9.0             # tiles around the player when a chunk is populated
const MIN_SPACING := 4               # tiles between two traps (square radius)
const PROP_CLEAR := 1.4              # tiles from props / items / orbs
const CHEST_CLEAR := 11.0            # tiles from military chest rooms
const ACTIVE_RADIUS := 25.0          # tiles: only traps this close are visible and simulated
const ACTIVATE_INTERVAL := 0.2

# ---- player safety --------------------------------------------------------------------------------
const MAX_HIT := 20.0                # absolute cap for one trap hit on the player
const MAX_HIT_FRAC := 0.25           # ... and fraction of max HP
const TRAP_IFRAMES := 0.8            # seconds of invulnerability after a trap hit (player.invuln_time)
const DOT_GRACE := 0.15              # invuln left after a burn tick (so burning does not make you immune)

# ---- bear trap ------------------------------------------------------------------------------------
const BEAR_TRIGGER := 0.5            # tiles from centre
const BEAR_REVEAL_NEAR := 2.0        # fully visible inside this distance (tiles) ...
const BEAR_REVEAL_FAR := 5.0         # ... and mostly hidden (alpha BEAR_HIDDEN_ALPHA) beyond this
const BEAR_HIDDEN_ALPHA := 0.28
const BEAR_DMG_PLAYER := 12.0
const BEAR_DMG_ENEMY := 30.0
const BEAR_ROOT_PLAYER := 1.2        # seconds; struggling shortens it
const BEAR_ROOT_ENEMY := 2.5
const BEAR_REARM := 10.0             # seconds closed before it re-arms
const STRUGGLE_MOVE_RATE := 1.5      # extra seconds drained per second while pushing a direction
const STRUGGLE_FLIP := 0.12          # seconds shaved per change of input direction (mashing)
const STRUGGLE_TAP := 0.25           # seconds shaved per "interact" press

# ---- spike trap -----------------------------------------------------------------------------------
const SPIKE_HIDDEN := 2.2
const SPIKE_WARN := 0.8
const SPIKE_UP := 1.0
const SPIKE_RETRACT := 0.3
const SPIKE_DMG_PLAYER := 10.0
const SPIKE_DMG_ENEMY := 14.0
const SPIKE_HALF := 0.55             # tiles (hit box half size)

# ---- pit trap -------------------------------------------------------------------------------------
const PIT_HALF := 0.5
const PIT_DMG_PLAYER := 8.0
const PIT_DMG_ENEMY := 10.0
const PIT_KNOCK_PLAYER := 9.0        # tiles/s initial push (decays, ~1.1 tiles)
const PIT_KNOCK_ENEMY := 6.0         # added to enemy kb_vel
const PIT_REHIT := 1.0               # seconds before the same creature can be hit again

# ---- fire trap ------------------------------------------------------------------------------------
const FIRE_IDLE := 2.4
const FIRE_WARN := 1.0
const FIRE_BURST := 1.1
const FIRE_FADE := 0.5
const FIRE_RADIUS := 0.85
const FIRE_HIT_PLAYER := 6.0
const FIRE_HIT_ENEMY := 8.0
const BURN_TIME := 2.0
const BURN_TICK := 0.5
const BURN_PLAYER_TICK := 3.0        # per tick -> 4 ticks = 12 over the burn
const BURN_ENEMY_TICK := 5.0
const FIRE_LIGHT := Color(1.0, 0.5, 0.15)

# ---- push trap ------------------------------------------------------------------------------------
const PUSH_IDLE := 2.0
const PUSH_WARN := 0.6
const PUSH_STRIKE := 0.5
const PUSH_RETRACT := 0.45
const PUSH_DMG_PLAYER := 4.0
const PUSH_DMG_ENEMY := 6.0
const PUSH_KNOCK_PLAYER := 10.0
const PUSH_KNOCK_ENEMY := 9.0

var game
var root: Node2D
var traps: Array = []
var enemy_snapshot: Array = []       # living enemies this tick (refreshed once per tick)

var player_push := Vector2.ZERO      # tiles/s, decays; applied after player.step
var root_t := 0.0                    # player rooted for this many more seconds
var root_pos := Vector2.ZERO
var _flip_dir := Vector2.ZERO
var player_burn_t := 0.0
var _player_burn_tick := 0.0
var _burn_fx := 0.0
var enemy_burn: Dictionary = {}      # instance id -> {e, t, tick}
var _populated := {}
var _spawn := Vector2.ZERO
var _occupied := {}                  # Vector2i -> true (trap tiles)
var _act_t := 0.0
var player_hits := 0                 # total trap hits on the player this run (tests)


func setup(g) -> void:
	game = g
	root = Node2D.new()
	root.name = "Traps"
	game.world.add_child(root)
	var ref: Node = game.player
	if game.objects and "root" in game.objects and game.objects.root:
		ref = game.objects.root
	if ref and ref.get_parent() == game.world:
		game.world.move_child(root, ref.get_index())    # traps draw under pickups and the player
	_spawn = game.map.find_spawn()
	game.chunk_spawned.connect(_on_chunk_spawned)


func reset_run() -> void:
	for t in traps:
		if is_instance_valid(t):
			t.queue_free()
	traps.clear()
	_occupied.clear()
	_populated.clear()
	enemy_burn.clear()
	player_push = Vector2.ZERO
	root_t = 0.0
	player_burn_t = 0.0
	player_hits = 0
	_spawn = game.map.find_spawn()
	for key in game.map.chunks:      # the map outlives a run: re-populate existing chunks
		_populate_chunk(key.x, key.y)


# =====================================================================================
#  placement
# =====================================================================================

func _on_chunk_spawned(cx: int, cy: int) -> void:
	_populate_chunk(cx, cy)


func _density() -> float:
	var diff := clampi(int(game.difficulty), 1, 4)
	return BASE_PER_CHUNK + minf(float(game.day - 1), float(DAY_CAP)) * PER_DAY + float(diff - 1) * PER_DIFFICULTY


func _populate_chunk(cx: int, cy: int) -> void:
	var key := Vector2i(cx, cy)
	if _populated.has(key):
		return
	_populated[key] = true
	var r := RandomNumberGenerator.new()
	r.seed = game.map._chunk_seed(cx, cy) * 31 + 7919          # deterministic per chunk
	var d := _density()
	var n := mini(MAX_PER_CHUNK, int(d) + (1 if r.randf() < d - floorf(d) else 0))
	var C := WorldMap.CHUNK
	for i in n:
		for attempt in 40:
			var x := cx * C + r.randi_range(3, C - 4)
			var y := cy * C + r.randi_range(3, C - 4)
			var kind := _roll_kind(r)
			var dir := Vector2.DOWN if r.randf() < 0.5 else Vector2.UP      # push traps use dir
			if r.randf() < 0.5:
				dir = Vector2.RIGHT if r.randf() < 0.5 else Vector2.LEFT
			if _tile_ok(x, y, kind, dir):
				spawn_trap(kind, Vector2(x + 0.5, y + 0.5), dir)
				break


func _roll_kind(r: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in KINDS:
		total += WEIGHTS[k]
	var v := r.randf() * total
	for k in KINDS:
		v -= WEIGHTS[k]
		if v <= 0.0:
			return k
	return "bear"


## A trap tile needs a fully open 3x3 (so never in a doorway / 1-wide corridor) and, for pushers, open
## tiles ahead and behind. Keeps clear of the spawn, props, items, chest rooms and other traps.
func _tile_ok(x: int, y: int, kind: String, dir: Vector2) -> bool:
	var m: WorldMap = game.map
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if m.get_tile(x + dx, y + dy) != WorldMap.FLOOR:
				return false
	if kind == "push":
		var ax := x + int(dir.x) * 2
		var ay := y + int(dir.y) * 2
		if m.get_tile(ax, ay) != WorldMap.FLOOR:
			return false
	var c := Vector2(x + 0.5, y + 0.5)
	if c.distance_to(_spawn) < SPAWN_SAFE or c.distance_to(game.player.tile_pos) < PLAYER_SAFE:
		return false
	for dy in range(-MIN_SPACING, MIN_SPACING + 1):
		for dx in range(-MIN_SPACING, MIN_SPACING + 1):
			if _occupied.has(Vector2i(x + dx, y + dy)):
				return false
	if game.objects:
		for arr in [game.objects.props, game.objects.items, game.objects.orbs]:
			for o in arr:
				if is_instance_valid(o) and o.tile_pos.distance_to(c) < PROP_CLEAR:
					return false
		var portal: Dictionary = game.objects.portal
		if not portal.is_empty() and Vector2(portal.pos).distance_to(c) < 10.0:
			return false
	for room in m.chest_rooms:
		if Vector2(room.pos).distance_to(c) < CHEST_CLEAR:
			return false
	return true


func spawn_trap(kind: String, tile_pos: Vector2, dir := Vector2.RIGHT) -> Node2D:
	var t := TrapNode.new()
	root.add_child(t)
	t.setup(self, game, kind, tile_pos, dir)
	t.set_active(tile_pos.distance_squared_to(game.player.tile_pos) < ACTIVE_RADIUS * ACTIVE_RADIUS)
	traps.append(t)
	_occupied[Vector2i(floori(tile_pos.x), floori(tile_pos.y))] = true
	return t


# =====================================================================================
#  tick
# =====================================================================================

func tick(dt: float) -> void:
	var p: Player = game.player
	enemy_snapshot.clear()
	if game.enemies:
		for e in game.enemies.get_enemies():
			if is_instance_valid(e) and not e.dead:
				enemy_snapshot.append(e)
	_act_t -= dt
	if _act_t <= 0.0:
		_act_t = ACTIVATE_INTERVAL
		var r2 := ACTIVE_RADIUS * ACTIVE_RADIUS
		for t in traps:
			t.set_active(t.tile_pos.distance_squared_to(p.tile_pos) < r2)
	for t in traps:
		if t.active:
			t.step(dt)
	_tick_player(dt, p)
	_tick_burning(dt)


func _tick_player(dt: float, p: Player) -> void:
	if root_t > 0.0:
		# rooted: undo this frame's movement (player.step already ran), let the player struggle free
		p.tile_pos = root_pos
		p.position = root_pos * game.TILE
		p.vel = Vector2.ZERO
		player_push = Vector2.ZERO
		var drain := 1.0
		var mv: Vector2 = game.input.move if game.input else Vector2.ZERO
		if mv.length() > 0.3:
			drain += STRUGGLE_MOVE_RATE
			if _flip_dir != Vector2.ZERO and mv.normalized().dot(_flip_dir) < 0.2:
				root_t -= STRUGGLE_FLIP
			_flip_dir = mv.normalized()
		if game.input and game.input.just("interact"):
			root_t -= STRUGGLE_TAP
		root_t -= dt * drain
		if root_t <= 0.0:
			root_t = 0.0
			game.fx.float_text(p.position + Vector2(0, -50), "FREE", Color(0.8, 1.0, 0.8))
			play("fx_tink", p.position, 0.6, 1.3)
	elif player_push.length_squared() > 0.04:
		p._try_move(player_push * dt)
		p.position = p.tile_pos * game.TILE
		player_push *= exp(-8.0 * dt)
	else:
		player_push = Vector2.ZERO
	if player_burn_t > 0.0:
		player_burn_t -= dt
		_player_burn_tick -= dt
		_burn_fx -= dt
		if _burn_fx <= 0.0:
			_burn_fx = 0.12
			game.fx.burst(p.position + Vector2(randf_range(-8, 8), randf_range(-10, 4)), "spark", Vector2.UP)
		if _player_burn_tick <= 0.0:
			_player_burn_tick = BURN_TICK
			if hurt_player(BURN_PLAYER_TICK, p.position, true) and p.invuln_time > DOT_GRACE:
				p.invuln_time = DOT_GRACE


func _tick_burning(dt: float) -> void:
	for id in enemy_burn.keys():
		var b: Dictionary = enemy_burn[id]
		var e = b.e
		if not is_instance_valid(e) or e.dead:
			enemy_burn.erase(id)
			continue
		b.t -= dt
		b.tick -= dt
		if b.tick <= 0.0:
			b.tick = BURN_TICK
			game.fx.burst(e.position, "spark", Vector2.UP)
			e.take_damage(BURN_ENEMY_TICK, Vector2.ZERO)
		if b.t <= 0.0:
			enemy_burn.erase(id)


# =====================================================================================
#  helpers used by traps
# =====================================================================================

## Damage the player (capped, never instant death). Returns false when ignored (i-frames / dead).
func hurt_player(amount: float, from_px: Vector2, dot := false) -> bool:
	var p: Player = game.player
	if p.invuln_time > 0.0 or p.hp <= 0.0:
		return false
	var dmg := minf(amount, minf(MAX_HIT, p.max_hp * MAX_HIT_FRAC))
	var hp0 := p.hp
	game.damage_player(dmg, from_px)
	if p.hp < hp0:
		player_hits += 1
		game.fx.float_text(p.position + Vector2(0, -44), "-%d" % int(hp0 - p.hp), Color(1.0, 0.55, 0.2))
		if not dot:
			p.invuln_time = maxf(p.invuln_time, TRAP_IFRAMES)
		return true
	return false


func hurt_enemy(e, amount: float, dir: Vector2) -> void:
	if e.dead or e.invulnerable:
		return
	e.take_damage(amount, dir)


func root_player(seconds: float, at: Vector2) -> void:
	root_t = seconds
	root_pos = at
	_flip_dir = Vector2.ZERO
	game.player.vel = Vector2.ZERO


func push_player(v: Vector2) -> void:
	player_push = v


func ignite_player() -> void:
	player_burn_t = BURN_TIME
	_player_burn_tick = BURN_TICK


func ignite_enemy(e) -> void:
	enemy_burn[e.get_instance_id()] = {"e": e, "t": BURN_TIME, "tick": BURN_TICK}


func play(sound: String, px: Vector2, vol := 0.7, pitch := 1.0) -> void:
	if game.audio:
		game.audio.play(sound, px, vol, pitch)


## True when a loaded trap is within `dist` tiles of `pos` - used by the one-time tip.
func trap_near(pos: Vector2, dist: float) -> bool:
	var d2 := dist * dist
	for t in traps:
		if t.active and t.tile_pos.distance_squared_to(pos) < d2:
			return true
	return false
