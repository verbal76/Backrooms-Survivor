extends Node
## Lighting + post-processing. Port of main.lua SEC 12 (headlamp, battery, getLightAtWorld) with real
## Godot 2D lights: CanvasModulate ambient, a shadow-casting headlamp cone (PointLight2D using a texture
## generated from the Lua falloff), a small ambient light around the player, a pooled set of flickering
## fluorescent ceiling lights, and the full-screen post shader (see fx/post_fx.gd).
##
## Public API (game.lighting):
##   light_level_at_player() -> float          0..1, CPU port of getLightAtWorld (drives sanity)
##   get_light_at_world(tile_pos) -> float
##   beam_closeness(tile_pos) -> float         0 if outside the headlamp beam/radius, else 1 - dist/RADIUS
##   battery / battery_max / battery_pct()     headlamp battery (Lua headlampBattery)
##   set_battery_max(v), replace_battery() -> bool, toggle_headlamp()
##   headlamp_brightness (options.headlampBrightness 0.1..1), brightness (options.brightness 0..1),
##   ambient (difficulty ambient: Easy .3, Normal .2, Worse .1, Hell .05)
##   add_point_light(parent, color, radius_tiles, energy, shadows) -> PointLight2D   (orb glows etc.)
##   post: PostFx   (post.pulse(), post.aberrate(), post.enabled)

const FIXTURE_CELL := 9              # one ceiling fixture candidate per 9x9 tiles
const FIXTURE_POOL := 8

# main.lua constants
const HEADLAMP_RADIUS := 14.0
const HEADLAMP_CONE := 0.85
const HEADLAMP_FORWARD_OFFSET := 0.18
const BATTERY_DRAIN := 0.55
const BATTERY_RECHARGE := 0.85
const DIFFICULTY_AMBIENT := [0.3, 0.2, 0.1, 0.05]

var game
var headlamp_brightness := 1.0
var brightness := 1.0
var ambient := 0.2
var battery := 100.0
var battery_max := 100.0

var post: PostFx
var lamp: PointLight2D
var glow: PointLight2D
var modulate_node: CanvasModulate

var _time := 0.0
var _fixture_timer := 0.0
var _fixture_lights: Array = []      # {light, key, fade, target, bad}
var _fixture_by_key := {}
var _heart_phase := 0.0


func setup(g) -> void:
	game = g
	modulate_node = CanvasModulate.new()
	add_child(modulate_node)

	lamp = PointLight2D.new()
	lamp.name = "Headlamp"
	lamp.texture = TexGen.light_headlamp(HEADLAMP_RADIUS, HEADLAMP_CONE, 256)
	lamp.texture_scale = HEADLAMP_RADIUS * game.TILE / 128.0
	lamp.color = Color(1.0, 0.96, 0.80)
	lamp.energy = 0.9
	lamp.shadow_enabled = true
	lamp.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	lamp.shadow_filter_smooth = 2.0
	lamp.shadow_color = Color(0, 0, 0, 1)
	lamp.range_z_min = -100
	lamp.range_z_max = 100
	lamp.z_index = 0
	game.player.add_child(lamp)
	game.player.lamp = lamp          # player.step() positions it at HEADLAMP_FORWARD

	glow = PointLight2D.new()
	glow.name = "PlayerGlow"
	glow.texture = TexGen.light_radial(128, 1.5)
	glow.texture_scale = 4.5 * game.TILE / 64.0
	glow.color = Color(1.0, 0.92, 0.72)
	glow.energy = 0.22
	glow.shadow_enabled = false
	game.player.add_child(glow)

	post = PostFx.new()
	post.camera = game.camera
	add_child(post)

	for i in FIXTURE_POOL:
		var l := PointLight2D.new()
		l.texture = TexGen.light_radial(128, 1.3)
		l.texture_scale = 4.6 * game.TILE / 64.0
		l.color = Color(1.0, 0.93, 0.70)
		l.energy = 0.0
		l.shadow_enabled = false
		l.visible = false
		game.world.add_child(l)
		_fixture_lights.append({"light": l, "key": Vector2i(-99999, 0), "fade": 0.0, "target": 0.0, "bad": false, "used": false})

	if game.player.has_signal("damaged"):
		game.player.damaged.connect(_on_player_damaged)
	reset_run()


## Quality preset hook (Quality.apply): shadow softness, ceiling-light count, post-FX level.
func set_quality(p: Dictionary) -> void:
	if lamp == null:
		return
	match int(p.shadow):
		0:
			lamp.shadow_filter = Light2D.SHADOW_FILTER_NONE
		1:
			lamp.shadow_filter = Light2D.SHADOW_FILTER_PCF5
			lamp.shadow_filter_smooth = 1.0
		_:
			lamp.shadow_filter = Light2D.SHADOW_FILTER_PCF5
			lamp.shadow_filter_smooth = 2.0
	var limit := clampi(int(p.fixtures), 0, _fixture_lights.size())
	for i in _fixture_lights.size():
		var e: Dictionary = _fixture_lights[i]
		e["off"] = i >= limit
		if e.off:
			e.target = 0.0
			e.used = false
			_fixture_by_key.erase(e.key)
	if post:
		post.set_quality(int(p.post))


func reset_run() -> void:
	battery_max = 100.0
	battery = battery_max
	if game and game.player:
		game.player.headlamp_on = true


# ---- battery / input ------------------------------------------------------

func battery_pct() -> float:
	return clampf(battery / maxf(battery_max, 0.001), 0.0, 1.0)


func set_battery_max(v: float) -> void:
	var pct := battery_pct()
	battery_max = v
	battery = battery_max * pct


func toggle_headlamp() -> void:
	var p: Player = game.player
	if battery > 0.0:
		p.headlamp_on = not p.headlamp_on
		_say("HEADLAMP ON" if p.headlamp_on else "HEADLAMP OFF", Color(1, 0.95, 0.7))
	else:
		_say("NO BATTERY", Color(1, 0.3, 0.3))


func replace_battery() -> bool:
	var p: Player = game.player
	if p.batteries > 0:
		p.batteries -= 1
		battery = battery_max
		p.headlamp_on = true
		_say("BATTERY REPLACED (%d left)" % p.batteries, Color(0.2, 1, 0.6))
		if game.fx:
			game.fx.burst(p.position, "pickup", Vector2.ZERO)
		return true
	_say("NO BATTERIES", Color(1, 0.3, 0.3))
	return false


func _say(text: String, color: Color) -> void:
	if game.fx:
		game.fx.float_text(game.player.position + Vector2(0, -56), text, color)


func tick(dt: float) -> void:
	var p: Player = game.player
	if p.headlamp_on:
		battery -= BATTERY_DRAIN * dt
		if battery <= 0.0:
			battery = 0.0
			p.headlamp_on = false
			_say("HEADLAMP DEAD", Color(1, 0.3, 0.3))
	else:
		battery = minf(battery_max, battery + BATTERY_RECHARGE * dt)
	if game.input:
		if game.input.just("headlamp"):
			toggle_headlamp()
		if game.input.just("battery"):
			replace_battery()


# ---- light queries (CPU, port of getLightAtWorld) --------------------------

func _ambient_level() -> float:
	return ambient + brightness * 0.08


func _lamp_origin() -> Vector2:
	var p: Player = game.player
	return p.tile_pos + Vector2.from_angle(p.angle) * HEADLAMP_FORWARD_OFFSET


func _battery_factor() -> float:
	var f := battery_pct()
	var p: Player = game.player
	var sanity_pct: float = p.sanity / maxf(p.max_sanity, 0.001)
	if sanity_pct <= 0.25 and sanity_pct > 0.0:
		var speed := 6.0 + (1.0 - sanity_pct / 0.25) * 10.0
		f *= sin(game.run_time * speed) * 0.4 + 0.6
	return f


func ray_blocked(a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var dist := d.length()
	if dist < 0.5:
		return false
	var end_inside: bool = game.map.is_solid(b.x, b.y)
	var steps := ceili(dist * 2.2)
	var hit := -1
	for i in range(1, steps + 1):
		var s := a + d * (float(i) / steps)
		if game.map.is_solid(s.x, s.y):
			hit = i
			break
	if hit < 0:
		return false
	if end_inside:
		if hit >= steps - 2:
			return false
		var h := a + d * (float(hit) / steps)
		if (b - h).length_squared() <= 0.07:
			return false
	return true


func get_light_at_world(pos: Vector2) -> float:
	var p: Player = game.player
	var origin := _lamp_origin()
	var d := pos - origin
	var dist := d.length()
	var headlamp := 0.0
	var bf := _battery_factor()
	if p.headlamp_on and bf > 0.0 and dist < HEADLAMP_RADIUS:
		if not ray_blocked(origin, pos):
			var ad := absf(wrapf(d.angle() - p.angle, -PI, PI))
			var cf := 1.0
			if ad > HEADLAMP_CONE:
				cf = maxf(0.0, 1.0 - (ad - HEADLAMP_CONE)) * 0.35
			var df := 1.0 - dist / HEADLAMP_RADIUS
			headlamp = pow(df, 1.3) * cf * headlamp_brightness * bf
			if dist < 3.0:
				headlamp = maxf(headlamp, 0.7 * headlamp_brightness * bf * (1.0 - dist / 3.0))
	var level := maxf(_ambient_level(), headlamp)
	# glow lights (orbs etc.) created by add_point_light()
	for n in get_tree().get_nodes_in_group("glow_light"):
		if not is_instance_valid(n) or not n.visible:
			continue
		var r: float = n.get_meta("radius_tiles", 5.0)
		var lp: Vector2 = n.global_position / game.TILE
		var od := (pos - lp).length()
		if od < r and not ray_blocked(lp, pos):
			level += pow(1.0 - od / r, 1.5) * n.energy * 0.55 * (n.get_meta("strength", 1.0))
	return minf(1.0, level)


func light_level_at_player() -> float:
	return get_light_at_world(game.player.tile_pos)


## 0 when `tile_pos` is outside the headlamp beam; otherwise 1 - dist/RADIUS (what Lua uses for beam damage).
func beam_closeness(tile_pos: Vector2) -> float:
	var p: Player = game.player
	if not p.headlamp_on or battery <= 0.0:
		return 0.0
	var d := tile_pos - p.tile_pos
	var dist := d.length()
	if dist >= HEADLAMP_RADIUS or dist <= 0.1:
		return 0.0
	if absf(wrapf(d.angle() - p.angle, -PI, PI)) >= HEADLAMP_CONE:
		return 0.0
	return 1.0 - dist / HEADLAMP_RADIUS


## Create a soft coloured light (orb glow, lamps, explosions). Added to the "glow_light" group so it
## counts for light_level_at_player(). Remember to queue_free it with its owner.
func add_point_light(parent: Node, color: Color, radius_tiles := 5.0, energy := 0.55, shadows := false) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = TexGen.light_radial(128, 1.5)
	l.texture_scale = radius_tiles * game.TILE / 64.0
	l.color = color
	l.energy = energy
	l.shadow_enabled = shadows
	l.set_meta("radius_tiles", radius_tiles)
	l.add_to_group("glow_light")
	parent.add_child(l)
	return l


# ---- per-frame visuals -----------------------------------------------------

func _process(delta: float) -> void:
	if game == null:
		return
	_time += delta
	var p: Player = game.player
	var amb := _ambient_level()
	modulate_node.color = Color(amb, amb * 0.97, amb * 0.88)

	var on: bool = p.headlamp_on and battery > 0.0
	lamp.visible = on
	if on:
		lamp.rotation = p.angle
		var e := headlamp_brightness * _battery_factor()
		var pct := battery_pct()
		if pct < 0.2:   # dying battery stutters
			var s := sin(_time * 31.0) * sin(_time * 17.3 + 1.7)
			if s > 0.55 - pct * 1.4:
				e *= 0.25 + 0.4 * absf(sin(_time * 53.0))
		lamp.energy = 0.95 * clampf(e, 0.0, 1.5)
	glow.energy = 0.2 + (0.0 if on else 0.08)

	_fixture_timer -= delta
	if _fixture_timer <= 0.0:
		_fixture_timer = 0.2
		_assign_fixtures()
	_update_fixture_flicker(delta)

	var sanity_pct: float = p.sanity / maxf(p.max_sanity, 0.001)
	var hp_pct: float = p.hp / maxf(p.max_hp, 0.001)
	post.update_state(delta, sanity_pct, hp_pct, game.camera.get_screen_center_position(), _heartbeat(delta, hp_pct, sanity_pct))


func _heartbeat(dt: float, hp_pct: float, sanity_pct: float) -> float:
	var stress := maxf(clampf(1.0 - hp_pct / 0.4, 0.0, 1.0), clampf(1.0 - sanity_pct / 0.3, 0.0, 1.0) * 0.8)
	if stress <= 0.0:
		return 0.0
	var prev_phase := _heart_phase
	_heart_phase = fmod(_heart_phase + dt * (1.1 + stress * 1.5), 1.0)
	if _heart_phase < prev_phase and stress > 0.3 and game.audio and game.audio.has_method("heartbeat_thump"):
		game.audio.heartbeat_thump(stress)         # audible lub-dub locked to the screen pulse
	var ph := _heart_phase
	var beat := exp(-ph * 14.0) + 0.6 * exp(-maxf(0.0, ph - 0.28) * 14.0) * (1.0 if ph >= 0.28 else 0.0)
	return clampf(beat, 0.0, 1.0) * stress


func _on_player_damaged(amount: float) -> void:
	post.pulse(clampf(0.5 + amount / 40.0, 0.5, 1.0))


# ---- fluorescent ceiling fixtures ------------------------------------------

static func _hash(x: int, y: int, salt := 0) -> float:
	var h := (x * 374761393 + y * 668265263 + salt * 2246822519) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


## Deterministic fixture tile for a cell, or Vector2i(-1,-1) if none / not on floor.
func fixture_at_cell(cx: int, cy: int) -> Vector2i:
	if _hash(cx, cy, 1) < 0.35:
		return Vector2i(-1, -1)
	var tx := cx * FIXTURE_CELL + 1 + int(_hash(cx, cy, 2) * (FIXTURE_CELL - 2))
	var ty := cy * FIXTURE_CELL + 1 + int(_hash(cx, cy, 3) * (FIXTURE_CELL - 2))
	if game.map.get_tile(tx, ty) != WorldMap.FLOOR:
		return Vector2i(-1, -1)
	return Vector2i(tx, ty)


func _assign_fixtures() -> void:
	var ppos: Vector2 = game.player.tile_pos
	var pc := Vector2i(floori(ppos.x / FIXTURE_CELL), floori(ppos.y / FIXTURE_CELL))
	var want := {}
	for cy in range(pc.y - 2, pc.y + 3):
		for cx in range(pc.x - 2, pc.x + 3):
			var f := fixture_at_cell(cx, cy)
			if f.x < 0:
				continue
			var d := (Vector2(f) + Vector2(0.5, 0.5) - ppos).length()
			if d < 15.0:
				want[f] = d
	# release lights whose fixture is no longer wanted
	for e in _fixture_lights:
		if e.used and not want.has(e.key):
			e.target = 0.0
			e.used = false
			_fixture_by_key.erase(e.key)
	# nearest first
	var keys := want.keys()
	keys.sort_custom(func(a, b): return want[a] < want[b])
	for k in keys:
		if _fixture_by_key.has(k):
			continue
		for e in _fixture_lights:
			if not e.used and e.fade <= 0.01 and not e.get("off", false):
				e.used = true
				e.key = k
				e.target = 1.0
				e.bad = _hash(k.x, k.y, 9) < 0.18
				e.light.position = (Vector2(k) + Vector2(0.5, 0.5)) * game.TILE
				_fixture_by_key[k] = e
				break


func _update_fixture_flicker(dt: float) -> void:
	for e in _fixture_lights:
		e.fade = move_toward(e.fade, e.target, dt * 1.5)
		var l: PointLight2D = e.light
		l.visible = e.fade > 0.01
		if not l.visible:
			continue
		var f := 1.0
		if e.bad:   # dying tube: stutter + dropouts
			var t: float = _time * 9.0 + e.key.x * 3.1
			f = 0.55 + 0.45 * sin(t) * sin(t * 2.3 + 1.0)
			if sin(_time * 1.7 + e.key.y) > 0.93:
				f *= 0.15
		else:
			f = 0.94 + 0.06 * sin(_time * 100.0 + e.key.x)   # faint mains hum shimmer
		l.energy = 0.26 * e.fade * f


## Hooks used by the enemy system (shade fading, flee, beam burn).
func light_at_tile(pos: Vector2) -> float:
	return get_light_at_world(pos)


func headlamp_active() -> bool:
	return game.player.headlamp_on and battery > 0.0
