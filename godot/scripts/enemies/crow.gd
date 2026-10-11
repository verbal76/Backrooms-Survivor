extends "res://scripts/enemies/enemy.gd"
## Crow: fast fragile flock harasser. Side-view sheet (7x6 frames of 48 px) drawn in the top-down world as a bird
## seen from the side flying low: the sprite only mirrors by horizontal heading (never rotates) and a ground
## shadow stays on the floor while the body hovers/bobs above it.
##
## Frame map (index = row * 7 + col, art faces right):
##   IDLE      0..6   perched, 7..8 perched (looking about)
##   CROUCH    9..11  settle / hunch;   12,13 flat tucked
##   LAND      14..17 wings flared low (takeoff / landing flutter)
##   PERCH_ALERT 18..20, 21 alert standing
##   PECK      22, 23 beak down (ground peck);  24 wing flare;  25..27 beak up / open
##   CAW_POSE  26, 27 beak-open;  28 tall alert
##   GLIDE     33, 34, 39 low streamlined wings (dive / fast glide)
##   FLAP      35, 36, 37, 38 wings up/down cycle (flight)
##   CAW_TEXT  40 yellow "CAW" word sprite
##   29..31 are tiny items (feather/seed/blue pebble), unused.

const COLS := 7
const ROWS := 6
const IDLE_FRAMES := [0, 1, 2, 3, 4, 5, 6, 7, 8]
const PECK_FRAMES := [21, 22, 23, 22]
const TAKEOFF_FRAMES := [11, 14, 15, 16]
const FLAP_FRAMES := [35, 36, 37, 38]
const GLIDE_FRAMES := [39, 33, 34]
const FLARE_FRAME := 24
const CAW_FRAMES := [26, 27]
const CAW_TEXT_FRAME := 40

const AWAKE_DIST := 20.0       # perched until the player is this close
const SCATTER_DIST := 30.0     # flutter away upward and despawn when the player is further than this
const ORBIT_R := 2.5
const DIVE_SPEED := 11.0       # tiles / s
const DIVE_TIME := 0.5
const HOVER_PX := 15.0         # resting hover height above the shadow

var crow_mode := "perched"     # perched | takeoff | fly | dive | scatter
var awake_dist := AWAKE_DIST
var mode_t := 0.0
var orbit_ang := 0.0
var orbit_dir := 1.0
var flutter := Vector2.ZERO
var flutter_t := 0.0
var dive_t := 0.0
var dive_hit := false
var dive_dir := Vector2.RIGHT
var next_dive_wait := 0.0
var flap_clock := 0.0
var flap_snd := 0.0
var air_h := 0.0               # current height above the shadow (px)
var face_right := true
var peck_t := 0.0
var idle_t := 0.0
var hop_cd := 0.0
var _vel := Vector2.ZERO       # smoothed flight velocity (tiles/s)
var _shadow_base := PackedVector2Array()


func _ready() -> void:
	super._ready()
	# swap the 16-frame rotation sheet setup for the crow's 7x6 grid
	for s in [_sprite, _flash]:
		s.hframes = COLS
		s.vframes = ROWS
	_base_scale = 1.55 * scale_mult
	_shadow_pts.clear()
	var rx: float = game.TILE * radius * 1.35
	for i in 16:
		var a := TAU * i / 16.0
		_shadow_base.append(Vector2(cos(a) * rx, sin(a) * rx * 0.45))
	_bar_bg.position.y = -game.TILE * 1.0
	_bar_fg.position.y = _bar_bg.position.y
	orbit_ang = randf() * TAU
	orbit_dir = 1.0 if randf() < 0.5 else -1.0
	next_dive_wait = randf_range(0.5, 2.0)
	hop_cd = randf_range(0.5, 2.5)
	_set_frame(IDLE_FRAMES[randi() % IDLE_FRAMES.size()])


func _set_frame(f: int) -> void:
	_sprite.frame = f
	_flash.frame = f


func _update_frame() -> void:
	pass   # frames are driven by _animate


# ---------------------------------------------------------------------------------------------
# AI
# ---------------------------------------------------------------------------------------------

func tick(dt: float, _light: float) -> void:
	if dead:
		_death_tick(dt)
		return
	var pl = game.player
	var pp: Vector2 = pl.tile_pos
	var to_p := pp - tile_pos
	var dist := to_p.length()
	hurt_snd_cd = maxf(0.0, hurt_snd_cd - dt)
	mode_t += dt
	flutter_t -= dt
	orbit_ang += orbit_dir * 0.9 * dt
	if flutter_t <= 0.0:
		flutter_t = randf_range(0.12, 0.35)
		flutter = Vector2.from_angle(randf() * TAU) * randf_range(0.0, 1.0)

	# mode transitions
	if crow_mode != "scatter" and dist > SCATTER_DIST:
		_set_mode("scatter")
	elif crow_mode == "perched" and (dist < awake_dist or hp < max_hp):
		_set_mode("takeoff")
	elif crow_mode == "takeoff" and mode_t > 0.3:
		_set_mode("fly")
	state = "hunt" if crow_mode in ["fly", "dive"] else "wander"

	var mv := Vector2.ZERO          # tiles moved this frame (desired)
	match crow_mode:
		"perched":
			_perched_tick(dt)
		"takeoff":
			mv = _fly_toward(_orbit_point(pp), dt, 0.5)
		"fly":
			_attack_tick(dt, to_p, dist, true)
			if atk_phase == "":
				mv = _fly_toward(_orbit_point(pp) + flutter * 0.9, dt, 1.0)
			elif atk_phase == "windup":
				mv = _fly_toward(_orbit_point(pp) + flutter * 0.2, dt, 0.35)
			elif atk_phase == "recover":
				# flap away from the player, up and out to the ring
				var away := (tile_pos - pp).normalized() if dist > 0.05 else Vector2.RIGHT
				mv = _fly_dir(away.rotated(orbit_dir * 0.5), dt, 1.1)
		"dive":
			mv = _dive_tick(dt, pp)
		"scatter":
			var away2 := (tile_pos - pp).normalized() if dist > 0.05 else Vector2.RIGHT
			mv = _fly_dir(away2, dt, 1.2)
			if mode_t > 1.4:
				mgr.list.erase(self)
				queue_free()
				return

	if kb_vel.length_squared() > 0.01:
		_try_move(kb_vel * dt)
		kb_vel *= exp(-10.0 * dt)
	else:
		kb_vel = Vector2.ZERO
	_animate(dt, to_p, mv)


func _set_mode(m: String) -> void:
	crow_mode = m
	mode_t = 0.0
	if m == "takeoff":
		game.audio.play("fx_flap", position, 0.4, 1.0)


func _orbit_point(pp: Vector2) -> Vector2:
	return pp + Vector2.from_angle(orbit_ang) * ORBIT_R


## Accelerate toward a world tile point (flying: ignores props, collides with walls; BFS around walls without LOS).
func _fly_toward(dest: Vector2, dt: float, gain: float) -> Vector2:
	var d := dest - tile_pos
	var l := d.length()
	var dir := d / l if l > 0.001 else Vector2.ZERO
	if l > 1.2 and not Pathing.has_los(game.map, tile_pos, dest):
		dir = _steer_toward(dest, 0.3)
	var spd := speed * gain * clampf(l / 1.2, 0.25, 1.0)
	return _fly_dir(dir, dt, gain, spd)


func _fly_dir(dir: Vector2, dt: float, _gain: float, spd := -1.0) -> Vector2:
	if spd < 0.0:
		spd = speed
	var want := dir * spd
	if stun > 0.0:
		stun -= dt
		want *= 0.3
	_vel = _vel.lerp(want, clampf(dt * 6.0, 0.0, 1.0))
	var step := _vel * dt
	if step != Vector2.ZERO:
		_try_move(step)
	return step


func _perched_tick(dt: float) -> void:
	idle_t += dt
	hop_cd -= dt
	_vel = _vel.lerp(Vector2.ZERO, clampf(dt * 8.0, 0.0, 1.0))
	if peck_t > 0.0:
		peck_t -= dt
	elif hop_cd <= 0.0:
		hop_cd = randf_range(1.0, 3.5)
		if randf() < 0.5:
			peck_t = randf_range(0.6, 1.2)
		else:
			var hop := Vector2.from_angle(randf() * TAU) * 0.35
			_try_move(hop)
			face_right = hop.x >= 0.0
			air_h = 6.0


## Telegraph (CAW + wing flare) -> dive -> flap away. Uses the shared enemy attack phases.
func _attack_tick(dt: float, to_p: Vector2, dist: float, _can_see: bool) -> void:
	slash_t = maxf(0.0, slash_t - dt)
	if atk_phase == "windup":
		atk_t -= dt
		if dist > 0.01:
			atk_dir = to_p / dist
		if atk_t <= 0.0:
			atk_phase = ""
			dive_dir = atk_dir
			dive_t = DIVE_TIME
			dive_hit = false
			_set_mode("dive")
	elif atk_phase == "recover":
		atk_t -= dt
		if atk_t <= 0.0:
			atk_phase = ""
			next_dive_wait = randf_range(1.0, 2.0)
	else:
		next_dive_wait -= dt
		# one crow of the flock at a time, every 2-3 s
		if next_dive_wait <= 0.0 and dist < 7.0 and dist > 1.2 and game.state == "playing" \
				and game.run_time >= mgr.crow_dive_at and Pathing.has_los(game.map, tile_pos, game.player.tile_pos):
			mgr.crow_dive_at = game.run_time + randf_range(2.0, 3.0)
			atk_phase = "windup"
			atk_t = windup
			atk_dir = to_p / dist
			alert_pulse = 0.3
			game.fx.attack_warning(position, windup)
			game.fx.float_text(position + Vector2(0, -game.TILE * 0.9), "CAW!", Color(1.0, 0.9, 0.15), 1.0)
			_play_caw(0.9)
	queue_redraw()


func _dive_tick(dt: float, pp: Vector2) -> Vector2:
	dive_t -= dt
	var before := tile_pos
	_try_move(dive_dir * DIVE_SPEED * dt)
	var moved := tile_pos - before
	if not dive_hit and tile_pos.distance_to(pp) <= reach:
		dive_hit = true
		_strike(pp - tile_pos, tile_pos.distance_to(pp))
	if dive_t <= 0.0 or moved.length() < DIVE_SPEED * dt * 0.3:   # out of time or hit a wall
		_vel = dive_dir * speed
		_set_mode("fly")
		atk_phase = "recover"
		atk_t = recover
	return moved


## One-shot dive damage (called when the dive passes through the player's reach).
func _strike(_to_p: Vector2, _dist: float) -> void:
	slash_t = SLASH_TIME
	attack_pulse = 0.3
	var pl = game.player
	if pl.invuln_time <= 0.0:
		game.fx.note_attacker(position)
		game.damage_player(float(dmg), position)
		game.fx.burst(pl.position, "hit", dive_dir)
		_play_attack_sound()
	else:
		game.fx.burst(position, "smoke", dive_dir)


## Contact is handled by the dive only (no standing-on-you damage); don't get shoved around either.
func touch_player(_pl_pos: Vector2) -> void:
	pass


# ---------------------------------------------------------------------------------------------
# Visuals
# ---------------------------------------------------------------------------------------------

func _animate(dt: float, _to_p: Vector2, mv: Vector2) -> void:
	position = tile_pos * game.TILE
	_last_pos = tile_pos
	spawn_t = minf(spawn_t + dt, 0.3)
	hit_flash = maxf(0.0, hit_flash - dt)
	attack_pulse = maxf(0.0, attack_pulse - dt)
	squash = maxf(0.0, squash - dt * 7.0)
	alert_pulse = maxf(0.0, alert_pulse - dt)

	var speed_now := _vel.length() if crow_mode != "perched" else 0.0
	if crow_mode == "dive":
		speed_now = DIVE_SPEED
	var fast := clampf(speed_now / maxf(speed, 0.1), 0.0, 2.6)

	# facing by horizontal heading only
	if absf(mv.x) > 0.0005 and absf(_vel.x) > 0.15 or crow_mode == "dive":
		face_right = (dive_dir.x if crow_mode == "dive" else _vel.x) >= 0.0
	elif atk_phase == "windup":
		face_right = atk_dir.x >= 0.0
	_sprite.flip_h = not face_right
	_flash.flip_h = _sprite.flip_h

	# target height + frame per mode
	var hover := HOVER_PX
	var frame := 0
	match crow_mode:
		"perched":
			hover = 0.0
			if peck_t > 0.0:
				frame = PECK_FRAMES[int(idle_t * 7.0) % PECK_FRAMES.size()]
			else:
				frame = IDLE_FRAMES[int(idle_t * 0.8 + float(get_instance_id() % 9)) % IDLE_FRAMES.size()]
		"takeoff":
			hover = HOVER_PX * 0.7
			frame = TAKEOFF_FRAMES[mini(int(mode_t / 0.3 * TAKEOFF_FRAMES.size()), TAKEOFF_FRAMES.size() - 1)]
		"scatter":
			hover = HOVER_PX + 70.0 * clampf(mode_t / 1.2, 0.0, 1.0)
			frame = _flap_frame(dt, 2.0)
		"dive":
			hover = HOVER_PX * 0.55
			frame = GLIDE_FRAMES[0]
		_:
			if atk_phase == "windup":
				# telegraph: rise, flare wings, open beak
				hover = HOVER_PX + 7.0 * clampf(1.0 - atk_t / maxf(windup, 0.01), 0.0, 1.0)
				var k := 1.0 - atk_t / maxf(windup, 0.01)
				frame = CAW_FRAMES[int(mode_t * 12.0) % 2] if k < 0.6 else FLARE_FRAME
			else:
				hover = HOVER_PX + sin(mode_t * 6.0 + float(get_instance_id() % 7)) * 3.5
				frame = _flap_frame(dt, 0.8 + fast)
				if atk_phase == "recover":
					hover += 6.0
	air_h = lerpf(air_h, hover, clampf(dt * 10.0, 0.0, 1.0))
	_set_frame(frame)

	# flap whump sound, quicker when fast
	if crow_mode in ["fly", "scatter", "takeoff"]:
		flap_snd -= dt
		if flap_snd <= 0.0:
			flap_snd = 0.45 / (0.8 + fast)
			var d: float = tile_pos.distance_to(game.player.tile_pos)
			if d < 12.0:
				game.audio.play("fx_flap", position, 0.18 * (1.0 - d / 12.0) + 0.04, randf_range(0.9, 1.15))

	var pop := 1.0 + 0.3 * (hit_flash / HIT_FLASH_TIME) + 0.15 * (attack_pulse / 0.3) + 0.2 * (alert_pulse / 0.35)
	var s := _base_scale * pop * ease(spawn_t / 0.3, 0.3)
	var sq := squash * squash * 0.2
	_sprite.scale = Vector2(s * (1.0 + sq), s * (1.0 - sq))
	_flash.scale = _sprite.scale
	_flash.modulate.a = clampf(hit_flash / HIT_FLASH_TIME, 0.0, 1.0) * 0.85
	# sprite sits on its feet at (0, -air_h) so the shadow stays on the floor; frame is bottom-weighted
	var off := Vector2(0.0, -air_h - 14.0 * _base_scale * 0.5)
	if atk_phase == "windup":
		off += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 1.2     # agitated shake
	_sprite.position = off
	_flash.position = off
	_sprite.rotation = 0.0
	_flash.rotation = 0.0
	_sprite.self_modulate = Color(1.0, 0.7, 0.65) if atk_phase == "windup" else Color.WHITE
	_sprite.modulate.a = ease(spawn_t / 0.3, 0.3)

	if hp < max_hp:
		var f := clampf(hp / max_hp, 0.0, 1.0)
		_bar_bg.visible = true
		_bar_fg.visible = true
		_bar_bg.position.y = -game.TILE * 0.95 - air_h
		_bar_fg.position = _bar_bg.position
		_bar_fg.size.x = _bar_bg.size.x * f
		_bar_fg.color = Color(1.0 - f, f, 0.0)
	queue_redraw()


func _flap_frame(dt: float, rate: float) -> int:
	flap_clock += dt * 11.0 * rate
	return FLAP_FRAMES[int(flap_clock) % FLAP_FRAMES.size()]


func _draw() -> void:
	# soft ground shadow that stays on the floor and shrinks/fades with height
	if _shadow_base.size() > 2:
		var k := 1.0 / (1.0 + air_h / 70.0)
		var al := 0.32 * k
		var pts := PackedVector2Array()
		for p in _shadow_base:
			pts.append(p * (0.7 + 0.3 * k) + Vector2(0.0, game.TILE * radius * 0.5))
		if dead:
			al *= 1.0 - clampf(death_t / 0.4, 0.0, 1.0)
		draw_colored_polygon(pts, Color(0, 0, 0, al))
		var pts2 := PackedVector2Array()
		for p in _shadow_base:
			pts2.append(p * (0.4 + 0.2 * k) + Vector2(0.0, game.TILE * radius * 0.5))
		draw_colored_polygon(pts2, Color(0, 0, 0, al * 0.7))
	if atk_phase == "windup":
		var a := atk_dir.angle()
		var rr: float = 2.2 * game.TILE
		draw_line(Vector2.ZERO, atk_dir * rr, Color(1.0, 0.25, 0.1, 0.35), 2.0)
		draw_arc(Vector2.ZERO, rr, a - 0.08, a + 0.08, 4, Color(1.0, 0.25, 0.1, 0.5), 3.0)
	elif crow_mode == "dive":
		var tail: Vector2 = -dive_dir * game.TILE * 1.4
		draw_line(Vector2(0, -air_h * 0.6), tail + Vector2(0, -air_h * 0.6), Color(0.85, 0.85, 1.0, 0.25), 3.0)


# ---------------------------------------------------------------------------------------------
# Death / sounds
# ---------------------------------------------------------------------------------------------

func _die(dir: Vector2) -> void:
	if dead:
		return
	super._die(dir)
	for i in 9:
		var f := Feather.new()
		f.position = position + Vector2(randf_range(-6, 6), -air_h - 6.0 + randf_range(-6, 6))
		f.vel = Vector2.from_angle(randf() * TAU) * randf_range(30.0, 130.0) + (dir * 60.0 if dir != Vector2.ZERO else Vector2.ZERO)
		f.ground_y = position.y + game.TILE * radius * 0.5
		game.world.add_child(f)


func _death_tick(dt: float) -> void:
	death_t += dt
	var k := clampf(death_t / 0.4, 0.0, 1.0)
	if kb_vel.length_squared() > 0.01:
		_try_move(kb_vel * dt)
		kb_vel *= exp(-9.0 * dt)
	position = tile_pos * game.TILE
	air_h = maxf(0.0, air_h - dt * 160.0)            # drops to the floor
	_sprite.position = Vector2(0.0, -air_h - 7.0)
	_flash.position = _sprite.position
	_set_frame(13 if death_t > 0.12 else 12)         # tucked flat on the floor
	_sprite.modulate.a = 1.0 - k * k
	_flash.modulate.a = (1.0 - k) * (1.0 - k)
	queue_redraw()
	if k >= 1.0:
		queue_free()


func _play_caw(vol := 0.8) -> void:
	var d: float = tile_pos.distance_to(game.player.tile_pos)
	if d < 18.0:
		game.audio.play("fx_caw", position, clampf(vol * (1.0 - d / 18.0) + 0.1, 0.1, 1.0), randf_range(0.9, 1.25))


func _play_attack_sound() -> void:
	game.audio.play("fx_slash", position, 0.5, 1.4)


func _play_hurt_sound() -> void:
	_play_caw(0.5)


func _play_death_sound() -> void:
	var d: float = tile_pos.distance_to(game.player.tile_pos)
	if d < 18.0:
		game.audio.play("fx_caw", position, clampf(0.9 * (1.0 - d / 18.0) + 0.15, 0.15, 1.0), randf_range(0.7, 0.9))


func _ambient_sounds(_dt: float, _dist: float) -> void:
	pass


## Small drifting feather: dark elongated leaf that tumbles to the floor and fades.
class Feather extends Node2D:
	var vel := Vector2.ZERO
	var ground_y := 0.0
	var t := 0.0
	var spin := randf_range(-6.0, 6.0)
	var life := randf_range(0.9, 1.5)
	var z := 0.0

	func _process(delta: float) -> void:
		t += delta
		vel *= exp(-3.0 * delta)
		vel.y += 70.0 * delta * (1.0 if t > 0.25 else 0.3)       # float down slowly
		position += vel * delta
		if position.y > ground_y:
			position.y = ground_y
			vel = Vector2.ZERO
			spin *= 0.9
		rotation += spin * delta
		modulate.a = clampf((life - t) / 0.4, 0.0, 1.0)
		if t >= life:
			queue_free()

	func _draw() -> void:
		var pts := PackedVector2Array([Vector2(-6, 0), Vector2(-1, -2.2), Vector2(5, 0), Vector2(-1, 2.2)])
		draw_colored_polygon(pts, Color(0.1, 0.1, 0.14))
		draw_line(Vector2(-6, 0), Vector2(5, 0), Color(0.35, 0.35, 0.45), 1.0)
