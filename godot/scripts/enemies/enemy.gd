extends Node2D
## One enemy. Port of the enemy table, AI (Enemies:update), wall movement and drawing from enemies.lua / main.lua SEC 16.
## Created and ticked by systems/enemies.gd. Positions are tile units (`tile_pos`); the node sits at tile_pos * TILE px.

const Pathing = preload("res://scripts/enemies/pathing.gd")
const FLASH_SHADER = preload("res://scripts/enemies/flash.gdshader")

const SPRITE_ANGLE_OFFSET := -PI / 2.0     # ENEMY_SPRITE_ANGLE_OFFSET
const SHEET_FRAMES := 16
const FRAME_PX := 128.0
const CHAR_SCALE := 52.0 / 24.0            # charScale = tileSize / 24
const HUNT_MUL := 0.75                     # huntMul / searchMul / wanderMul
const SEARCH_MUL := 0.5
const WANDER_MUL := 0.45
const HIT_FLASH_TIME := 0.15

# ---- identity / stats (public contract: tile_pos, radius, hp, kind, take_damage) ----
var game
var mgr
var kind := "hound"
var type_idx := 0
var tile_pos := Vector2.ZERO
var radius := 0.35
var hp := 10.0
var max_hp := 10.0
var speed := 1.0
var dmg := 5
var xp := 1
var drop_chance := 0.1
var noise_attract := 1.0
var light_fear := 0.0
var scale_mult := 1.0
var tint := Color.WHITE
var portal_guard := false
var invulnerable := false

# ---- AI state (names follow the Lua) ----
var state := "wander"
var alert_level := 0.0
var target := Vector2.ZERO               # targetX/Y (wander goal)
var has_seen := false
var last_seen := Vector2.ZERO
var last_seen_timer := 0.0
var has_heard := false
var last_heard := Vector2.ZERO
var last_heard_timer := 999.0
var wander_timer := 0.0
var stuck_timer := 0.0
var prev_pos := Vector2.ZERO
var slide_pref := 1
var los_timer := 0.0
var cached_los := false
var path_wp := Vector2.INF
var path_timer := 0.0

# ---- juice state ----
var dead := false
var hit_flash := 0.0
var kb_vel := Vector2.ZERO
var stun := 0.0
var facing := 0.0
var attack_pulse := 0.0
# melee attack: wind-up (telegraph) -> strike (damage at the legs/pincers' reach) -> recover
var reach := 1.2
var windup := 0.3
var recover := 0.8
var atk_phase := ""          # "" | "windup" | "recover"
var atk_t := 0.0
var atk_dir := Vector2.RIGHT
var slash_t := 0.0
const SLASH_TIME := 0.22
var alert_pulse := 0.0
var hurt_snd_cd := 0.0
var phrase_timer := 0.0
var phrase_cooldown := 10.0
var breath_timer := 0.0
var walk_phase := 0.0
var death_t := 0.0
var spawn_t := 0.0
var _last_pos := Vector2.ZERO

var _sprite: Sprite2D
var _flash: Sprite2D
var _bar_bg: ColorRect
var _bar_fg: ColorRect
var _base_scale := 1.0
var _shadow_pts := PackedVector2Array()


func setup(p_game, p_mgr, p_kind: String, t: Dictionary, p_tile_pos: Vector2, wave: int, hp_mult: float, spd_mult: float, dmg_mult: float) -> void:
	game = p_game
	mgr = p_mgr
	kind = p_kind
	type_idx = t.idx
	tile_pos = p_tile_pos
	prev_pos = p_tile_pos
	_last_pos = p_tile_pos
	target = p_tile_pos
	radius = t.radius
	reach = t.get("reach", t.radius + 0.7)
	windup = t.get("windup", 0.3)
	recover = t.get("recover", 0.8)
	scale_mult = t.scale
	tint = t.color
	xp = t.xp
	drop_chance = t.drop
	noise_attract = t.noise
	light_fear = t.fear
	# difficulty scaling by day (the Lua "baby-stepped" values)
	max_hp = floorf(t.hp * (1.0 + wave * 0.05) * hp_mult)
	hp = max_hp
	speed = t.speed * (1.0 + wave * 0.01) * spd_mult
	dmg = int(floorf(t.dmg * (1.0 + wave * 0.035) * dmg_mult))
	slide_pref = 1 if randf() > 0.5 else -1
	los_timer = randf() * 0.2
	phrase_timer = randf() * 10.0
	phrase_cooldown = 5.0 + randf() * 15.0
	breath_timer = randf() * 4.0
	facing = randf() * TAU
	position = tile_pos * game.TILE


func _ready() -> void:
	var sc: float = (radius / 0.35) * CHAR_SCALE * scale_mult
	_base_scale = (game.TILE * sc * 2.2) / FRAME_PX
	var tex: Texture2D = mgr.get_sheet(kind)
	_sprite = Sprite2D.new()
	_sprite.texture = tex
	_sprite.hframes = SHEET_FRAMES
	_sprite.scale = Vector2.ONE * _base_scale
	add_child(_sprite)
	_flash = Sprite2D.new()
	_flash.texture = tex
	_flash.hframes = SHEET_FRAMES
	_flash.scale = _sprite.scale
	var mat := ShaderMaterial.new()
	mat.shader = FLASH_SHADER
	_flash.material = mat
	_flash.modulate.a = 0.0
	add_child(_flash)
	# ground shadow
	var rx: float = game.TILE * radius * 1.05
	var ry := rx * 0.5
	for i in 16:
		var a := TAU * i / 16.0
		_shadow_pts.append(Vector2(cos(a) * rx, sin(a) * ry + game.TILE * radius * 0.55))
	# hp bar (shown when damaged)
	var bw: float = 24.0 * sc
	var by: float = -game.TILE * radius * 1.6 - 6.0
	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(0, 0, 0, 0.8)
	_bar_bg.position = Vector2(-bw * 0.5, by)
	_bar_bg.size = Vector2(bw, 4)
	_bar_bg.visible = false
	add_child(_bar_bg)
	_bar_fg = ColorRect.new()
	_bar_fg.position = _bar_bg.position
	_bar_fg.size = Vector2(bw, 4)
	_bar_fg.visible = false
	add_child(_bar_fg)
	_sprite.scale = Vector2.ZERO   # pop in
	_flash.scale = Vector2.ZERO
	_update_frame()


# ---------------------------------------------------------------------------------------------
# Public contract
# ---------------------------------------------------------------------------------------------

func take_damage(amount: float, knockback_dir := Vector2.ZERO) -> void:
	if dead or invulnerable:
		return
	hp -= amount
	hit_flash = HIT_FLASH_TIME
	# being shot makes the enemy aware of you
	alert_level = maxf(alert_level, 40.0)
	if game and game.player:
		has_seen = true
		last_seen = game.player.tile_pos
		last_seen_timer = 0.0
	if knockback_dir != Vector2.ZERO:
		var kb: float = clampf(5.0 / (radius * 2.5), 2.5, 9.0)
		kb_vel += knockback_dir.normalized() * kb
		stun = 0.12
	var px := position
	game.fx.float_text(px + Vector2(randf_range(-8, 8), -game.TILE * radius - 14.0), str(int(ceilf(amount))),
		Color(1.0, 0.85, 0.25) if amount >= 10.0 else Color(1, 1, 1))
	game.fx.burst(px, "hit", knockback_dir)
	game.fx.blood(px, clampf(amount / 12.0, 0.3, 1.2))
	if hp <= 0.0:
		_die(knockback_dir)
	elif hurt_snd_cd <= 0.0:
		hurt_snd_cd = 0.2
		_play_hurt_sound()


# ---------------------------------------------------------------------------------------------
# Death
# ---------------------------------------------------------------------------------------------

func _die(dir: Vector2) -> void:
	if dead:
		return
	dead = true
	death_t = 0.0
	hit_flash = HIT_FLASH_TIME
	mgr.on_enemy_dead(self)
	var big := kind == "skin stealer" or kind == "crawler"
	game.fx.burst(position, "gib", dir)
	game.fx.blood(position, 1.6 if big else 1.0)
	game.fx.shake(6.0 if big else 3.0, 0.2)
	game.hitstop(0.09 if kind == "skin stealer" else 0.045)
	_play_death_sound()
	if is_instance_valid(_bar_bg):
		_bar_bg.visible = false
		_bar_fg.visible = false
	if dir != Vector2.ZERO:
		kb_vel += dir.normalized() * 4.0
	game.report_kill(tile_pos, kind, xp)


func _death_tick(dt: float) -> void:
	death_t += dt
	var k := clampf(death_t / 0.4, 0.0, 1.0)
	if kb_vel.length_squared() > 0.01:
		_try_move(kb_vel * dt)
		kb_vel *= exp(-9.0 * dt)
	position = tile_pos * game.TILE
	var s := _base_scale * (1.0 + 0.25 * sin(k * PI) - 0.85 * k * k)
	_sprite.scale = Vector2.ONE * maxf(s, 0.01)
	_flash.scale = _sprite.scale
	_sprite.rotation += dt * 6.0
	_flash.rotation = _sprite.rotation
	_sprite.modulate.a = 1.0 - k
	_flash.modulate.a = (1.0 - k) * (1.0 - k)
	if k >= 1.0:
		queue_free()


# ---------------------------------------------------------------------------------------------
# AI (Enemies:update). `ctx` = manager; player data comes from game.player.
# ---------------------------------------------------------------------------------------------

func tick(dt: float, light: float) -> void:
	if dead:
		_death_tick(dt)
		return
	var pl = game.player
	var pp: Vector2 = pl.tile_pos
	var player_moving: bool = pl.moving
	var player_noise: float = pl.noise
	var to_p := pp - tile_pos
	var dist := to_p.length()
	hurt_snd_cd = maxf(0.0, hurt_snd_cd - dt)

	# throttled LOS (every 0.08 s)
	los_timer += dt
	if los_timer >= 0.08:
		cached_los = dist < 14.0 and Pathing.has_los(game.map, tile_pos, pp)
		los_timer = 0.0
	var can_see := cached_los

	# hearing
	var noise_reach: float = player_noise * noise_attract * 0.7
	if dist < noise_reach and player_moving:
		alert_level = minf(100.0, alert_level + (noise_reach - dist) * dt * 15.0)
		last_heard = pp
		has_heard = true
		last_heard_timer = 0.0
	else:
		last_heard_timer += dt

	# sight
	if can_see:
		if dist < 10.0:
			alert_level = minf(100.0, alert_level + (10.0 - dist) * dt * 25.0)
		last_seen = pp
		has_seen = true
		last_seen_timer = 0.0
	else:
		last_seen_timer += dt

	# alert decay / forgetting
	var seen_ago := last_seen_timer
	var heard_ago := last_heard_timer
	if alert_level > 35.0:
		var rate := 3.0 if (seen_ago < 1.25 or heard_ago < 1.25) else 9.0
		alert_level = maxf(0.0, alert_level - rate * dt)
		if seen_ago > 6.0 and heard_ago > 6.0:
			alert_level = minf(alert_level, 34.5)
	elif alert_level > 10.0:
		var rate2 := 5.0 if (seen_ago < 2.0 or heard_ago < 2.0) else 12.0
		alert_level = maxf(0.0, alert_level - rate2 * dt)
	else:
		alert_level = maxf(0.0, alert_level - 4.0 * dt)

	# state selection
	var old_state := state
	if light_fear > 0.0 and light > 0.7:
		state = "flee"
	elif alert_level > 35.0:
		state = "hunt"
	elif alert_level > 10.0:
		state = "search"
	else:
		state = "wander"
	if state == "hunt" and old_state != "hunt":
		alert_pulse = 0.35
		if randf() < 0.5 and dist < 15.0:
			_play_phrase(dist)

	_attack_tick(dt, to_p, dist, can_see)

	var mv := Vector2.ZERO
	var spd := speed * dt
	path_timer -= dt

	match state:
		"hunt":
			if dist > 0.1:
				if can_see:
					# keep the player at leg's length instead of walking onto them
					if dist > reach * 0.8:
						mv = to_p / dist * spd * HUNT_MUL
					last_seen = pp
				elif player_moving and has_heard:
					mv = _steer_toward(last_heard, 0.3) * spd * 0.85 * HUNT_MUL
				elif has_seen and last_seen_timer < 6.0:
					var sv := _steer_toward(last_seen, 0.3)
					if sv == Vector2.ZERO:
						alert_level -= 6.0 * dt
					mv = sv * spd * 0.7 * HUNT_MUL
				else:
					alert_level -= 8.0 * dt
		"search":
			var tgt := target
			if has_heard:
				tgt = last_heard
			elif has_seen:
				tgt = last_seen
			mv = _steer_toward(tgt, 0.5) * spd * 0.5 * SEARCH_MUL
		"flee":
			if dist > 0.1:
				mv = -to_p / dist * spd
		_:
			wander_timer -= dt
			if wander_timer <= 0.0:
				var wa := randf() * TAU
				target = tile_pos + Vector2(cos(wa), sin(wa)) * 3.0
				wander_timer = 2.0 + randf() * 3.0
			var td := target - tile_pos
			var tl := td.length()
			if tl > 0.2:
				mv = td / tl * spd * 0.4 * WANDER_MUL

	# anti-stuck: barely moved for 1.2 s while hunting/searching -> flip slide side, sidestep
	if state == "hunt" or state == "search":
		if tile_pos.distance_to(prev_pos) < 0.02:
			stuck_timer += dt
			if stuck_timer > 1.2:
				slide_pref *= -1
				path_wp = Vector2.INF
				path_timer = 0.0
				var perp := Vector2(-mv.y, mv.x)
				if perp.length() > 0.0001:
					mv = perp.normalized() * spd * slide_pref
				stuck_timer = 0.0
		else:
			stuck_timer = 0.0
	prev_pos = tile_pos

	# stun after being hit slows the walk, knockback slides the body
	if stun > 0.0:
		stun -= dt
		mv *= 0.3
	if atk_phase == "windup":
		mv = Vector2.ZERO
	if mv != Vector2.ZERO:
		_try_move(mv)
	if kb_vel.length_squared() > 0.01:
		_try_move(kb_vel * dt)
		kb_vel *= exp(-10.0 * dt)
	else:
		kb_vel = Vector2.ZERO

	_ambient_sounds(dt, dist)
	_animate(dt, to_p, mv)


## Direction (unit vector) toward `dest`; goes through BFS waypoints when walls are in the way.
func _steer_toward(dest: Vector2, arrive_dist: float) -> Vector2:
	var d := dest - tile_pos
	var l := d.length()
	if l <= arrive_dist:
		return Vector2.ZERO
	if l < 1.2 or Pathing.has_los(game.map, tile_pos, dest):
		path_wp = Vector2.INF
		return d / l
	if (path_wp == Vector2.INF or path_timer <= 0.0) and mgr.take_path_budget():
		path_wp = Pathing.next_waypoint(game.map, tile_pos, dest)
		path_timer = 0.5
	if path_wp != Vector2.INF:
		var w := path_wp - tile_pos
		var wl := w.length()
		if wl < 0.25:
			path_timer = 0.0
		elif wl > 0.0:
			return w / wl
	return d / l


# ---------------------------------------------------------------------------------------------
# Wall movement (Enemies:tryMoveEnemy)
# ---------------------------------------------------------------------------------------------

func _wall(x: float, y: float) -> bool:
	return game.map.is_solid(x, y)


func _can_move(dx: float, dy: float) -> bool:
	var r := radius
	if dx != 0.0:
		var nx := tile_pos.x + dx
		var edge_x := nx + r if dx > 0.0 else nx - r
		if _wall(edge_x, tile_pos.y - r) or _wall(edge_x, tile_pos.y) or _wall(edge_x, tile_pos.y + r):
			return false
	if dy != 0.0:
		var ny := tile_pos.y + dy
		var edge_y := ny + r if dy > 0.0 else ny - r
		if _wall(tile_pos.x - r, edge_y) or _wall(tile_pos.x, edge_y) or _wall(tile_pos.x + r, edge_y):
			return false
	return true


func _try_move(m: Vector2) -> void:
	var mx := m.x
	var my := m.y
	if mx != 0.0 or my != 0.0:
		if _can_move(mx, my):
			tile_pos += m
			return
	var moved := false
	if mx != 0.0 and _can_move(mx, 0.0):
		tile_pos.x += mx
		moved = true
	if my != 0.0 and _can_move(0.0, my):
		tile_pos.y += my
		moved = true
	if moved:
		return
	var sp := m.length()
	if sp < 0.0001:
		return
	var a := m / sp
	var perp1 := Vector2(-a.y, a.x)
	var perp2 := Vector2(a.y, -a.x)
	var step := sp * 0.65
	var s1 := (perp1 if slide_pref == 1 else perp2) * step
	if _can_move(s1.x, s1.y):
		tile_pos += s1
		return
	var s2 := (perp2 if slide_pref == 1 else perp1) * step
	if _can_move(s2.x, s2.y):
		tile_pos += s2
		return
	var ang := atan2(a.y, a.x)
	for off in [0.0, 0.35, -0.35, 0.8, -0.8, 1.25, -1.25, PI / 2.0, -PI / 2.0, PI]:
		var aa: float = ang + off * slide_pref
		var v := Vector2(cos(aa), sin(aa)) * sp
		if _can_move(v.x, v.y):
			tile_pos += v
			return


## Safety net: pop the body out of a wall if something shoved it in.
func unstick() -> void:
	if not _wall(tile_pos.x, tile_pos.y):
		return
	var base := Vector2(floorf(tile_pos.x), floorf(tile_pos.y))
	for r in range(1, 5):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := base + Vector2(dx + 0.5, dy + 0.5)
				if not _wall(c.x, c.y):
					tile_pos = c
					return


# ---------------------------------------------------------------------------------------------
# Contact with the player (Enemies:checkPlayerCollision) - called by the manager.
# ---------------------------------------------------------------------------------------------

func touch_player(pl_pos: Vector2) -> void:
	var d := pl_pos - tile_pos
	var dist := d.length()
	# touching an enemy alerts it, and a body overlapping the player is shoved back to leg's length
	alert_level = 100.0
	has_seen = true
	last_seen = pl_pos
	last_seen_timer = 0.0
	if dist > 0.01:
		var dir := -d / dist
		kb_vel += dir * (reach * 0.8 - dist + 0.3) * 8.0


## Melee attack state machine (Lua only had overlap damage: a big spider had to stand on you).
func _attack_tick(dt: float, to_p: Vector2, dist: float, can_see: bool) -> void:
	slash_t = maxf(0.0, slash_t - dt)
	if atk_phase == "windup":
		atk_t -= dt
		if to_p.length() > 0.01:
			atk_dir = to_p.normalized()
		if atk_t <= 0.0:
			_strike(to_p, dist)
			atk_phase = "recover"
			atk_t = recover
	elif atk_phase == "recover":
		atk_t -= dt
		if atk_t <= 0.0:
			atk_phase = ""
	elif (state == "hunt" or dist < reach * 0.6) and can_see and dist <= reach and game.state == "playing":
		atk_phase = "windup"
		atk_t = windup
		atk_dir = to_p.normalized() if dist > 0.01 else Vector2.RIGHT
		alert_pulse = 0.2
	queue_redraw()


func _strike(to_p: Vector2, dist: float) -> void:
	slash_t = SLASH_TIME
	attack_pulse = 0.3
	kb_vel += atk_dir * 3.0                       # lunge forward a step
	var pl = game.player
	var d_now: float = (pl.tile_pos - tile_pos).length()
	if d_now <= reach + 0.3 and Pathing.has_los(game.map, tile_pos, pl.tile_pos) and pl.invuln_time <= 0.0:
		game.damage_player(float(dmg), position)
		game.fx.burst(pl.position, "hit", atk_dir)
		_play_attack_sound()
	else:
		game.fx.burst(position + atk_dir * reach * game.TILE, "smoke", atk_dir)   # swing and miss


# ---------------------------------------------------------------------------------------------
# Visuals
# ---------------------------------------------------------------------------------------------

func _animate(dt: float, to_p: Vector2, mv: Vector2) -> void:
	position = tile_pos * game.TILE
	var moved := (tile_pos - _last_pos).length()
	_last_pos = tile_pos
	spawn_t = minf(spawn_t + dt, 0.3)
	hit_flash = maxf(0.0, hit_flash - dt)
	attack_pulse = maxf(0.0, attack_pulse - dt)
	alert_pulse = maxf(0.0, alert_pulse - dt)

	# facing: toward the player, or toward the wander goal while wandering (as in drawEnemies)
	var want := facing
	if state == "wander":
		var td := target - tile_pos
		if td.length() > 0.1:
			want = td.angle()
	elif to_p.length() > 0.001:
		want = to_p.angle()
	facing = lerp_angle(facing, want, clampf(dt * 14.0, 0.0, 1.0))
	_update_frame()

	walk_phase += moved * 9.0 / maxf(radius, 0.25)
	var bob := 1.0 + sin(walk_phase) * 0.035 * clampf(moved / maxf(dt * speed, 0.001), 0.0, 1.5)
	var pop := 1.0 + 0.30 * (hit_flash / HIT_FLASH_TIME) + 0.22 * (attack_pulse / 0.3) + 0.15 * (alert_pulse / 0.35)
	var spawn_k := ease(spawn_t / 0.3, 0.3)
	var s := _base_scale * bob * pop * spawn_k
	_sprite.scale = Vector2.ONE * s
	_flash.scale = _sprite.scale
	_flash.modulate.a = clampf(hit_flash / HIT_FLASH_TIME, 0.0, 1.0) * 0.85
	_sprite.rotation = sin(walk_phase * 0.5) * 0.05
	# telegraph: rear back during the wind-up, snap forward on the strike
	var lunge := Vector2.ZERO
	if atk_phase == "windup":
		lunge = -atk_dir * game.TILE * radius * 0.35 * (1.0 - atk_t / maxf(windup, 0.01))
	elif slash_t > 0.0:
		lunge = atk_dir * game.TILE * radius * 0.6 * (slash_t / SLASH_TIME)
	_sprite.position = lunge
	_flash.position = lunge
	_sprite.self_modulate = Color(1.0, 0.55, 0.5) if atk_phase == "windup" else Color.WHITE
	_flash.rotation = _sprite.rotation

	# shades fade out in darkness (harder to spot), min alpha 0.08
	var a := 1.0
	if kind == "shade":
		a = clampf(mgr.light_at(tile_pos), 0.08, 1.0)
	_sprite.modulate.a = a * spawn_k

	if hp < max_hp:
		var f := clampf(hp / max_hp, 0.0, 1.0)
		_bar_bg.visible = true
		_bar_fg.visible = true
		_bar_fg.size.x = _bar_bg.size.x * f
		_bar_fg.color = Color(1.0 - f, f, 0.0)
	queue_redraw()


func _update_frame() -> void:
	var norm := fposmod(facing + SPRITE_ANGLE_OFFSET, TAU)
	var idx := int(floorf(norm / TAU * SHEET_FRAMES + 0.5)) % SHEET_FRAMES
	_sprite.frame = idx
	_flash.frame = idx


func _draw() -> void:
	if slash_t > 0.0 and not dead:
		# two claw swipes sweeping across the front of the body out to the attack reach
		var k := slash_t / SLASH_TIME
		var ang := atk_dir.angle()
		var rr: float = reach * game.TILE
		for side in [-1.0, 1.0]:
			var a0: float = ang + side * (0.55 - 0.9 * (1.0 - k))
			draw_arc(Vector2.ZERO, rr * (0.55 + 0.45 * (1.0 - k)), a0 - 0.35, a0 + 0.35, 10, Color(1, 0.85, 0.8, 0.9 * k), 3.0 + 3.0 * k)
	if atk_phase == "windup":
		# faint reach ring so the strike zone is readable
		draw_arc(Vector2.ZERO, reach * game.TILE, atk_dir.angle() - 0.6, atk_dir.angle() + 0.6, 12, Color(1, 0.2, 0.1, 0.35), 2.0)
	if _shadow_pts.size() > 2:
		var al := 0.35
		if dead:
			al = 0.35 * (1.0 - clampf(death_t / 0.4, 0.0, 1.0))
		draw_colored_polygon(_shadow_pts, Color(0, 0, 0, al))


# ---------------------------------------------------------------------------------------------
# Sounds (enemysounds.lua): same file basenames, attenuation formula from the Lua.
# ---------------------------------------------------------------------------------------------

func _vol_at(dist: float, mult := 1.0) -> float:
	var v := (1.0 - dist / 15.0) * 0.7 * mult
	return clampf(v * v, 0.05, 1.0)


func _ambient_sounds(dt: float, dist: float) -> void:
	if dist >= 15.0:
		return
	# breath: looped in the Lua; approximated with periodic one-shots
	breath_timer -= dt
	if breath_timer <= 0.0:
		breath_timer = 4.5 + randf() * 3.0
		game.audio.play("Demonic Breath %03d" % randi_range(1, 2), position, _vol_at(dist, 0.6), randf_range(0.85, 1.1))
	phrase_timer += dt
	if phrase_timer >= phrase_cooldown and (state == "hunt" or state == "search") and dist < 8.0:
		phrase_timer = 0.0
		phrase_cooldown = 8.0 + randf() * 20.0
		_play_phrase(dist)


func _play_phrase(dist: float) -> void:
	game.audio.play("Demonic Phrase %03d" % randi_range(1, 16), position, _vol_at(dist), randf_range(0.9, 1.05))


func _play_attack_sound() -> void:
	var d: float = tile_pos.distance_to(game.player.tile_pos)
	game.audio.play("Hell Beast Attack %03d" % randi_range(1, 11), position, clampf(_vol_at(d, 0.8), 0.1, 1.0))


func _play_hurt_sound() -> void:
	var d: float = tile_pos.distance_to(game.player.tile_pos)
	if d < 15.0:
		game.audio.play("death_Hell Beast Dies %03d" % randi_range(1, 8), position, _vol_at(d), randf_range(0.95, 1.2))


func _play_death_sound() -> void:
	var d: float = tile_pos.distance_to(game.player.tile_pos)
	if d < 15.0:
		game.audio.play("death_Hell Beast Dies %03d" % randi_range(1, 8), position, maxf(_vol_at(d), 0.3), randf_range(0.75, 1.0))
