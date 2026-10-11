extends Node2D
## One trap in the world (bear / spike / pit / fire / push). Visual + state machine; the damage rules and numbers
## live in systems/traps.gd (constants) and are applied through its helpers.
##
## Sheet frame mapping (all frames 32 px wide, scaled x1.625 to the 52 px tile, nearest filtering):
##   Bear_Trap.png        128x32, 4 frames : 0 armed (flat jaws) | 1,2,3 snapping shut
##   Spike Trap.png       448x32, 14 frames: 0-5 hidden holes | 6 glint | 7 rising | 8-11 spiked | 12,13 retracting
##   Pit_Trap_Spikes.png  32x32,  1 frame  : spiked pit tile
##   Fire_Trap.png        448x41, 14 frames: 0 idle vents | 1-7 embers growing (warning) | 8-11 flame burst | 12,13 dying out
##   Push_Trap_Front.png  352x32, 11 frames: 0,1 wind-up | 2-6 piston extends (pushes +y) | 7-10 retract
##   Push_Trap_Right.png  384x32, 12 frames: 0,1 wind-up | 2-6 piston extends (pushes +x) | 7-10 retract | 11 empty

const T = preload("res://scripts/systems/traps.gd")
const DIR := "res://assets/third_party/animated_traps/"
const SHEETS := {
	"bear": ["Bear_Trap.png", 4],
	"spike": ["Spike Trap.png", 14],
	"pit": ["Pit_Trap_Spikes.png", 1],
	"fire": ["Fire_Trap.png", 14],
	"push_v": ["Push_Trap_Front.png", 11],
	"push_h": ["Push_Trap_Right.png", 12],
}

var sys
var game
var kind := ""
var tile_pos := Vector2.ZERO
var dir := Vector2.DOWN
var state := ""
var t := 0.0
var active := false
var seen := false
var sprite: Sprite2D
var light: PointLight2D
var hits := {}                  # creature key -> true (once per phase) / seconds left (pit)
var caught = null               # bear: enemy held
var caught_t := 0.0
var _frame := -1
var _flicker := 0.0


func setup(p_sys, p_game, p_kind: String, p_tile_pos: Vector2, p_dir: Vector2) -> void:
	sys = p_sys
	game = p_game
	kind = p_kind
	tile_pos = p_tile_pos
	dir = p_dir.normalized() if p_dir != Vector2.ZERO else Vector2.RIGHT
	position = tile_pos * game.TILE
	var key := kind
	if kind == "push":
		key = "push_v" if absf(dir.y) > 0.5 else "push_h"
	var info: Array = SHEETS[key]
	sprite = Sprite2D.new()
	sprite.texture = load(DIR + info[0])
	sprite.hframes = info[1]
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var s: float = float(game.TILE) / 32.0
	sprite.scale = Vector2(s, s)
	if kind == "fire":
		sprite.offset = Vector2(0, -4.5)          # 41 px tall frame: floor part is the bottom 32 px
	if key == "push_v":
		sprite.flip_v = dir.y < 0.0
	elif key == "push_h":
		sprite.flip_h = dir.x < 0.0
	add_child(sprite)
	match kind:
		"bear": _goto("armed")
		"spike": _goto("hidden"); t = randf() * T.SPIKE_HIDDEN
		"fire": _goto("idle"); t = randf() * T.FIRE_IDLE
		"push": _goto("idle"); t = randf() * T.PUSH_IDLE
		_: _goto("static")
	_show(0)
	visible = false


func set_active(a: bool) -> void:
	if a == active:
		return
	active = a
	visible = a


func _goto(s: String) -> void:
	state = s
	t = 0.0
	hits.clear()


func _show(f: int) -> void:
	if f != _frame:
		_frame = f
		sprite.frame = f


func _ppos() -> Vector2:
	return game.player.tile_pos


func step(dt: float) -> void:
	t += dt
	if not seen and tile_pos.distance_squared_to(_ppos()) < 64.0:
		seen = true
	match kind:
		"bear": _step_bear(dt)
		"spike": _step_spike()
		"pit": _step_pit(dt)
		"fire": _step_fire(dt)
		"push": _step_push()


# ---- helpers ------------------------------------------------------------------------------

## Player and living enemies whose position satisfies `pred(rel)` (rel = tile_pos - trap centre).
func _victims(half_along: Vector2, half_perp: float) -> Array:
	# zone in trap-local axes: along dir in [half_along.x, half_along.y], across within +-half_perp
	var out: Array = []
	var side := Vector2(-dir.y, dir.x)
	var pl: Player = game.player
	if pl.hp > 0.0:
		var r := pl.tile_pos - tile_pos
		var a := r.dot(dir)
		if a >= half_along.x and a <= half_along.y and absf(r.dot(side)) <= half_perp:
			out.append(pl)
	for e in sys.enemy_snapshot:
		var r2: Vector2 = e.tile_pos - tile_pos
		var a2 := r2.dot(dir)
		if a2 >= half_along.x and a2 <= half_along.y and absf(r2.dot(side)) <= half_perp:
			out.append(e)
	return out


func _key(v) -> int:
	return 0 if v == game.player else v.get_instance_id()


func _kb_dir(v) -> Vector2:
	var d: Vector2 = v.tile_pos - tile_pos
	if d.length() < 0.05:
		d = -game.player.vel if v == game.player and game.player.vel.length() > 0.1 else Vector2.from_angle(randf() * TAU)
	return d.normalized()


func _near_player(d: float) -> bool:
	return tile_pos.distance_squared_to(_ppos()) < d * d


# ---- bear trap ----------------------------------------------------------------------------

func _step_bear(dt: float) -> void:
	if caught != null:
		if not is_instance_valid(caught) or caught.dead or caught_t <= 0.0:
			caught = null
		else:
			caught_t -= dt
			caught.tile_pos = tile_pos
			caught.position = position
			caught.kb_vel = Vector2.ZERO
			caught.stun = maxf(caught.stun, 0.2)
	match state:
		"armed":
			var d := tile_pos.distance_to(_ppos())
			var k := clampf((d - T.BEAR_REVEAL_NEAR) / (T.BEAR_REVEAL_FAR - T.BEAR_REVEAL_NEAR), 0.0, 1.0)
			sprite.modulate.a = lerpf(1.0, T.BEAR_HIDDEN_ALPHA, k)
			_show(0)
			if d < T.BEAR_TRIGGER and game.player.hp > 0.0:
				_snap(game.player)
				return
			for e in sys.enemy_snapshot:
				if e.tile_pos.distance_squared_to(tile_pos) < T.BEAR_TRIGGER * T.BEAR_TRIGGER * 0.8:
					_snap(e)
					return
		"snap":
			_show(1 + mini(2, int(t / 0.06)))
			if t >= 0.18:
				_goto("closed")
		"closed":
			_show(3)
			if t >= T.BEAR_REARM and caught == null:
				_goto("reopen")
		"reopen":
			_show(2 - mini(2, int(t / 0.1)))
			sprite.modulate.a = 0.9
			if t >= 0.3:
				_goto("armed")


func _snap(v) -> void:
	sprite.modulate.a = 1.0
	_goto("snap")
	var px := position
	sys.play("fx_crunch", px, 0.9, 0.8)
	sys.play("fx_tink", px, 0.8, 0.7)
	game.fx.burst(px, "spark", Vector2.UP)
	if v == game.player:
		sys.root_player(T.BEAR_ROOT_PLAYER, tile_pos)
		game.fx.shake(7.0, 0.25)
		game.fx.float_text(px + Vector2(0, -64), "SNAP!", Color(1, 0.85, 0.3), 1.2)
		sys.hurt_player(T.BEAR_DMG_PLAYER, px)
	else:
		caught = v
		caught_t = T.BEAR_ROOT_ENEMY
		v.tile_pos = tile_pos
		sys.hurt_enemy(v, T.BEAR_DMG_ENEMY, Vector2.ZERO)
		if _near_player(8.0):
			game.fx.shake(3.0, 0.15)


# ---- spike trap ---------------------------------------------------------------------------

func _step_spike() -> void:
	match state:
		"hidden":
			_show(0)
			sprite.modulate = Color.WHITE
			if t >= T.SPIKE_HIDDEN:
				_goto("warn")
				sys.play("fx_tink", position, 0.6, 1.5)
		"warn":
			_show(5 + int(t * 10.0) % 2)
			var pulse := 0.5 + 0.5 * sin(t * 28.0)
			sprite.modulate = Color(1.0, 1.0 - 0.45 * pulse, 1.0 - 0.45 * pulse)
			if t >= T.SPIKE_WARN:
				_goto("up")
				sprite.modulate = Color.WHITE
				sys.play("fx_slash", position, 0.8, 1.2)
				game.fx.burst(position, "spark", Vector2.UP)
				if _near_player(5.0):
					game.fx.shake(3.0, 0.12)
		"up":
			_show(7 if t < 0.06 else 8 + int(t * 12.0) % 4)
			var half := T.SPIKE_HALF
			for v in _victims(Vector2(-half, half), half):
				var k := _key(v)
				if hits.has(k):
					continue
				if v == game.player:
					if sys.hurt_player(T.SPIKE_DMG_PLAYER, position):
						hits[k] = true
						game.fx.shake(6.0, 0.2)
				else:
					hits[k] = true
					sys.hurt_enemy(v, T.SPIKE_DMG_ENEMY, _kb_dir(v) * 0.5)
			if t >= T.SPIKE_UP:
				_goto("retract")
		"retract":
			_show(12 + mini(1, int(t / (T.SPIKE_RETRACT * 0.5))))
			if t >= T.SPIKE_RETRACT:
				_goto("hidden")


# ---- pit trap -----------------------------------------------------------------------------

func _step_pit(dt: float) -> void:
	for k in hits.keys():
		hits[k] -= dt
		if hits[k] <= 0.0:
			hits.erase(k)
	for v in _victims(Vector2(-T.PIT_HALF, T.PIT_HALF), T.PIT_HALF):
		var k := _key(v)
		if hits.has(k):
			continue
		var d := _kb_dir(v)
		if v == game.player:
			if sys.hurt_player(T.PIT_DMG_PLAYER, position):
				hits[k] = T.PIT_REHIT
				sys.push_player(d * T.PIT_KNOCK_PLAYER)
				sys.play("fx_crunch", position, 0.8, 1.1)
				game.fx.shake(6.0, 0.2)
				game.fx.burst(position, "hit", d)
				game.fx.float_text(position + Vector2(0, -60), "SPIKES!", Color(1, 0.5, 0.4), 1.1)
		else:
			hits[k] = T.PIT_REHIT
			sys.hurt_enemy(v, T.PIT_DMG_ENEMY, d)
			v.kb_vel += d * T.PIT_KNOCK_ENEMY
			sys.play("fx_crunch", position, 0.6, 1.1)


# ---- fire trap ----------------------------------------------------------------------------

func _set_light(energy: float) -> void:
	if energy <= 0.02:
		if light:
			light.visible = false
		return
	if light == null:
		if game.lighting and game.lighting.has_method("add_point_light"):
			light = game.lighting.add_point_light(self, T.FIRE_LIGHT, 3.6, energy)
		else:
			return
	light.visible = true
	light.energy = energy


func _step_fire(dt: float) -> void:
	match state:
		"idle":
			_show(0)
			_set_light(0.0)
			if t >= T.FIRE_IDLE:
				_goto("warn")
				sys.play("fx_warn", position, 0.7, 1.4)
		"warn":
			var prog := clampf(t / T.FIRE_WARN, 0.0, 1.0)
			_show(1 + mini(6, int(prog * 7.0)))
			_flicker = 0.5 + 0.5 * sin(t * 30.0 + sin(t * 11.0) * 3.0)
			_set_light((0.12 + 0.35 * prog) * (0.6 + 0.4 * _flicker))
			if t >= T.FIRE_WARN:
				_goto("burst")
				sys.play("fx_boom", position, 0.45, 1.6)
				game.fx.burst(position, "explosion", Vector2.UP)
				game.fx.light_flash(position, T.FIRE_LIGHT, 4.0, 0.9, 0.2)
				game.fx.fire_patch(position, T.FIRE_RADIUS * game.TILE, T.FIRE_BURST + 0.4)
				if _near_player(6.0):
					game.fx.shake(5.0, 0.2)
					game.fx.flash(Color(1.0, 0.45, 0.1, 0.2), 0.2)
		"burst":
			_show(8 if t < 0.08 else (9 if t < 0.16 else 10 + int(t * 14.0) % 2))
			_set_light(0.9 + 0.25 * sin(t * 40.0))
			for v in _victims(Vector2(-T.FIRE_RADIUS, T.FIRE_RADIUS), T.FIRE_RADIUS):
				if v.tile_pos.distance_squared_to(tile_pos) > T.FIRE_RADIUS * T.FIRE_RADIUS:
					continue
				var k := _key(v)
				if hits.has(k):
					continue
				hits[k] = true
				if v == game.player:
					sys.hurt_player(T.FIRE_HIT_PLAYER, position)
					sys.ignite_player()
					game.fx.float_text(position + Vector2(0, -64), "BURNING!", Color(1, 0.55, 0.15), 1.1)
				else:
					sys.hurt_enemy(v, T.FIRE_HIT_ENEMY, Vector2.ZERO)
					sys.ignite_enemy(v)
			if int(t * 20.0) != int((t - dt) * 20.0):
				game.fx.burst(position + Vector2(randf_range(-14, 14), randf_range(-10, 6)), "spark", Vector2.UP)
			if t >= T.FIRE_BURST:
				_goto("fade")
		"fade":
			_show(12 + mini(1, int(t / (T.FIRE_FADE * 0.5))))
			_set_light(0.5 * (1.0 - t / T.FIRE_FADE))
			if t >= T.FIRE_FADE:
				_goto("idle")


# ---- push trap ----------------------------------------------------------------------------

func _step_push() -> void:
	match state:
		"idle":
			_show(0)
			sprite.position = Vector2.ZERO
			if t >= T.PUSH_IDLE:
				_goto("warn")
				sys.play("fx_warn", position, 0.6, 1.0)
		"warn":
			_show(int(t * 12.0) % 2)
			var pulse := 0.5 + 0.5 * sin(t * 30.0)
			sprite.modulate = Color(1.0, 1.0 - 0.4 * pulse, 1.0 - 0.4 * pulse)
			sprite.position = Vector2(sin(t * 70.0) * 1.2, 0.0)
			if t >= T.PUSH_WARN:
				_goto("strike")
				sprite.modulate = Color.WHITE
				sprite.position = Vector2.ZERO
				sys.play("fx_thump", position, 0.9, 1.1)
				if _near_player(6.0):
					game.fx.shake(3.5, 0.15)
		"strike":
			_show(2 + mini(4, int(t / 0.05)))
			for v in _victims(Vector2(-0.6, 1.0), 0.62):
				var k := _key(v)
				if hits.has(k):
					continue
				if v == game.player:
					if sys.hurt_player(T.PUSH_DMG_PLAYER, position):
						hits[k] = true
						sys.push_player(dir * T.PUSH_KNOCK_PLAYER)
						game.fx.shake(5.0, 0.18)
				else:
					hits[k] = true
					sys.hurt_enemy(v, T.PUSH_DMG_ENEMY, dir)
					v.kb_vel += dir * T.PUSH_KNOCK_ENEMY
			if t >= T.PUSH_STRIKE:
				_goto("retract")
		"retract":
			_show(7 + mini(3, int(t / (T.PUSH_RETRACT / 4.0))))
			if t >= T.PUSH_RETRACT:
				_goto("idle")
