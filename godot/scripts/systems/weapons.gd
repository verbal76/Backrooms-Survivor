extends Node
## Combat system: port of weapons.lua + bomb.lua + the weapon parts of main.lua
## (fire/melee handling, sanity misses, bullets, weapon sprites, switching, bombs).
##
## Weapon indices are 0-BASED (Lua was 1-based): 0 machete, 1 knife, 2 pipe, 3 axe, 4 pistol,
## 5 shotgun, 6 smg, 7 suppressed pistol. Index 0 is always unlocked.

const BombScript = preload("res://scripts/weapons/bomb.gd")
const BulletLayerScript = preload("res://scripts/weapons/bullet_layer.gd")
const WeaponViewScript = preload("res://scripts/weapons/weapon_view.gd")

const TILE := 52.0

## Weapons.list (Lua keys camelCase -> snake_case). type "melee" | "ranged".
const LIST: Array[Dictionary] = [
	{"name": "machete", "type": "melee", "dmg": 12, "rate": 0.5, "reach": 2.5, "stamina_cost": 7, "noise": 8, "color": Color(0.8, 0.8, 0.9), "desc": "Your trusty blade"},
	{"name": "knife", "type": "melee", "dmg": 6, "rate": 0.3, "reach": 1.2, "stamina_cost": 5, "noise": 5, "color": Color(0.7, 0.7, 0.8), "desc": "Fast, quiet"},
	{"name": "pipe", "type": "melee", "dmg": 12, "rate": 0.6, "reach": 1.8, "stamina_cost": 9, "noise": 15, "color": Color(0.5, 0.5, 0.6), "desc": "Long, loud clang"},
	{"name": "axe", "type": "melee", "dmg": 15, "rate": 0.8, "reach": 3.0, "stamina_cost": 12, "noise": 12, "color": Color(0.6, 0.3, 0.2), "desc": "Heavy damage"},
	{"name": "pistol", "type": "ranged", "dmg": 12, "rate": 0.4, "speed": 12.0, "spread": 0.03, "count": 1, "pierce": false, "spawn_dist": 0.8, "stamina_cost": 5, "noise": 60, "color": Color(0.8, 0.8, 0.8), "desc": "LOUD"},
	{"name": "shotgun", "type": "ranged", "dmg": 20, "rate": 0.9, "speed": 10.0, "spread": 0.1, "count": 5, "pierce": false, "spawn_dist": 0.95, "stamina_cost": 8, "noise": 85, "color": Color(0.6, 0.4, 0.2), "desc": "VERY LOUD"},
	{"name": "smg", "type": "ranged", "dmg": 14, "rate": 0.1, "speed": 14.0, "spread": 0.06, "count": 1, "pierce": false, "spawn_dist": 0.8, "stamina_cost": 3, "noise": 70, "color": Color(0.4, 0.4, 0.5), "desc": "Fast, constant noise"},
	{"name": "suppressed pistol", "type": "ranged", "dmg": 14, "rate": 0.2, "speed": 11.0, "spread": 0.04, "count": 1, "pierce": false, "spawn_dist": 0.95, "stamina_cost": 5, "noise": 15, "color": Color(0.3, 0.3, 0.35), "desc": "Quiet but weak"},
]
const AMMO_PER_PICKUP := 25
const BULLET_LIFE := 2.0
const SANITY_MISS_BELOW := 0.25
# fire sound per weapon name; everything else uses "gunshot"
const FIRE_SOUND := {"shotgun": "Shotgun_sound", "smg": "smg_sound"}
# per-weapon juice: camera shake px, shake time, recoil kick, casing colour
const JUICE := {
	"pistol": {"shake": 2.6, "time": 0.09, "recoil": 0.9, "flash": 6.0},
	"shotgun": {"shake": 7.0, "time": 0.16, "recoil": 1.6, "flash": 9.0},
	"smg": {"shake": 1.8, "time": 0.06, "recoil": 0.55, "flash": 5.5},
	"suppressed pistol": {"shake": 1.0, "time": 0.06, "recoil": 0.6, "flash": 3.0},
}

signal weapon_changed(index: int)
## Short HUD message request (UI agent may connect). Also forwarded to game.ui.add_message if it exists.
signal message(text: String, color: Color)
signal fired(index: int)
signal bomb_used(killed: int)

var game
var list: Array[Dictionary] = LIST
var current := 0
var unlocked: Array[bool] = [true, false, false, false, false, false, false, false]
var ammo := 0
var ammo_per_pickup := AMMO_PER_PICKUP

# perk / orb modifiers (Lua dmgMod, rateMod, speedMod, countMod, spreadMod)
var dmg_mod := 0
var rate_mod := 1.0
var speed_mod := 1.0
var count_mod := 0
var spread_mod := 1.0

var fire_timer := 0.0
var _tired := false
const TIRED_DMG := 0.6      # BALANCE: damage of a swing made below the stamina cost
const TIRED_RATE := 1.35    # BALANCE: and its recovery time multiplier
var swing_timer := 0.0
var swinging := false
var bullets: Array[Dictionary] = []
var casings: Array[Dictionary] = []
var bomb: Node2D

var _view: Node2D
var _layer: Node2D
var _glow: Node2D
var _light: PointLight2D
var _light_tex: Texture2D
var _flash_light := 0.0
var _flash_peak := 1.0
var _no_ammo_msg := 0.0
var _miss_msg := 0.0
var _rng := RandomNumberGenerator.new()


func setup(g) -> void:
	game = g
	_rng.randomize()
	_light_tex = _make_light_texture()

	_layer = Node2D.new()
	_layer.set_script(BulletLayerScript)
	_layer.wp = self
	game.world.add_child(_layer)
	_glow = Node2D.new()
	_glow.set_script(BulletLayerScript)
	_glow.wp = self
	_glow.additive = true
	game.world.add_child(_glow)

	_view = Node2D.new()
	_view.set_script(WeaponViewScript)
	_view.wp = self
	for w in LIST:
		var path := "res://assets/weapons/%s.png" % String(w.name).replace(" ", "_")
		if ResourceLoader.exists(path):
			_view.textures[w.name] = load(path)
	game.world.add_child(_view)

	_light = PointLight2D.new()
	_light.texture = _light_tex
	_light.energy = 0.0
	_light.color = Color(1.0, 0.8, 0.45)
	_light.shadow_enabled = false
	game.world.add_child(_light)

	bomb = Node2D.new()
	bomb.set_script(BombScript)
	game.world.add_child(bomb)
	bomb.setup(game, _light_tex)


func reset_run() -> void:
	current = 0
	unlocked = [true, false, false, false, false, false, false, false]
	ammo = 0
	dmg_mod = 0
	rate_mod = 1.0
	speed_mod = 1.0
	count_mod = 0
	spread_mod = 1.0
	fire_timer = 0.0
	swing_timer = 0.0
	swinging = false
	bullets.clear()
	casings.clear()
	_flash_light = 0.0
	_no_ammo_msg = 0.0
	_miss_msg = 0.0
	if _view:
		_view.recoil = 0.0
		_view.flash_t = 0.0
		_view.pop = 0.0
	if bomb:
		bomb.reset()
	_redraw()


# ---- public API (contract) ----------------------------------------------

func get_current() -> Dictionary:
	return LIST[current]


func is_unlocked(idx: int) -> bool:
	return idx >= 0 and idx < unlocked.size() and unlocked[idx]


func unlock(index: int) -> void:
	if index >= 0 and index < LIST.size():
		unlocked[index] = true


func unlock_by_name(weapon_name: String) -> bool:
	for i in LIST.size():
		if LIST[i].name == weapon_name:
			unlocked[i] = true
			return true
	return false


func get_unlocked_list() -> Array[int]:
	var r: Array[int] = []
	for i in unlocked.size():
		if unlocked[i]:
			r.append(i)
	return r


## Random weapon index (excluding the machete) the player has not unlocked yet, or -1 if none.
func get_random_locked_weapon() -> int:
	var locked: Array[int] = []
	for i in range(1, LIST.size()):
		if not unlocked[i]:
			locked.append(i)
	if locked.is_empty():
		return -1
	return locked[_rng.randi() % locked.size()]


func add_ammo(n: int = -1) -> void:
	ammo += ammo_per_pickup if n < 0 else n


func add_bomb(n: int = 1) -> bool:
	## items.lua: refuse (false) when already at the cap.
	if bomb.count >= bomb.max_count:
		return false
	bomb.count = mini(bomb.max_count, bomb.count + n)
	return true


func get_melee_damage(mult: float) -> int:
	return int(floorf((LIST[current].dmg + dmg_mod) * mult))


func get_melee_reach() -> float:
	return LIST[current].get("reach", 1.0)


## dir: +1 next, -1 previous. Cycles through unlocked weapons only.
func cycle(dir: int) -> void:
	var ul := get_unlocked_list()
	if ul.size() <= 1:
		return
	var p := ul.find(current)
	if p < 0:
		p = 0
	p = posmod(p + (1 if dir >= 0 else -1), ul.size())
	set_weapon(ul[p])


func cycle_next() -> void:
	cycle(1)


func cycle_prev() -> void:
	cycle(-1)


func set_weapon(idx: int) -> void:
	if not is_unlocked(idx) or idx == current:
		return
	current = idx
	if _view:
		_view.pop = 1.0
	weapon_changed.emit(current)
	_msg(String(LIST[current].name).to_upper(), LIST[current].color)


func use_bomb() -> bool:
	if not bomb.can_use():
		return false
	var p = game.player
	var res: Dictionary = bomb.use(p.tile_pos)
	p.noise = minf(100.0, p.noise + 90.0)
	_msg("BOMB! (%d left)" % bomb.count, Color(1, 0.5, 0.1))
	bomb_used.emit(res.killed)
	return true


# ---- per-frame ---------------------------------------------------------

func tick(dt: float) -> void:
	var p = game.player
	var inp = game.input

	if inp:
		if inp.just("weapon_next"):
			cycle(1)
		if inp.just("weapon_prev"):
			cycle(-1)
		if inp.fire:
			_try_fire(p)
		if inp.just("bomb"):
			if not use_bomb() and bomb.count <= 0:
				_msg("NO BOMBS", Color(0.8, 0.3, 0.2))

	# Weapons:update
	fire_timer = maxf(fire_timer - dt, -dt)
	if swing_timer > 0.0:
		swing_timer -= dt
		if swing_timer <= 0.0:
			swinging = false
	if _no_ammo_msg > 0.0: _no_ammo_msg -= dt
	if _miss_msg > 0.0: _miss_msg -= dt
	bomb.update(dt)

	_update_bullets(dt)
	_update_casings(dt)
	_update_view(dt, p)
	_redraw()


func _try_fire(p) -> void:
	var wep: Dictionary = LIST[current]
	var is_melee: bool = wep.type == "melee"
	# BALANCE: a melee swing is never refused for lack of stamina; below the cost it is a weaker "tired" swing
	_tired = false
	if fire_timer > 0.0:
		return
	if p.stamina < wep.stamina_cost:
		if is_melee and p.stamina >= 1.0:
			_tired = true
		else:
			return
	if not is_melee and ammo <= 0:
		if _no_ammo_msg <= 0.0:
			_msg("NO AMMO", Color(1, 0.3, 0.3))
			_no_ammo_msg = 1.0
		fire_timer = 0.25   # don't spam the check every frame
		return

	# sanity < 25%: chance the attack is a dud (hands shaking), worse as sanity drops
	var miss := false
	var sanity_pct: float = p.sanity / p.max_sanity if p.max_sanity > 0.0 else 1.0
	if sanity_pct < SANITY_MISS_BELOW:
		var chance := (1.0 - sanity_pct / SANITY_MISS_BELOW) * 0.5
		if _rng.randf() < chance:
			miss = true
			if _miss_msg <= 0.0:
				_msg("HANDS SHAKING...", Color(0.6, 0.2, 0.8))
				_miss_msg = 2.0

	fire_timer = maxf(fire_timer, -get_physics_process_delta_time()) + wep.rate * rate_mod * (TIRED_RATE if _tired else 1.0)
	if game.input != null:
		game.input.consume_fire()        # this press has been served: the input buffer must not trigger a second attack
	p.stamina = maxf(0.0, p.stamina - wep.stamina_cost)
	p.noise = minf(100.0, p.noise + wep.noise * (0.5 if miss else 1.0))
	fired.emit(current)
	var angle: float = p.angle
	var origin_px: Vector2 = p.tile_pos * TILE

	if is_melee:
		swinging = true
		swing_timer = wep.rate * 0.6
		game.audio.play("swing_sound", origin_px, 0.6, _rng.randf_range(0.92, 1.08))
		game.fx.swing(origin_px, angle, float(wep.reach) * TILE, wep.name)
		if not miss:
			_melee_hit(p, wep, angle)
	else:
		ammo -= 1
		var vol := clampf(wep.noise / 85.0, 0.15, 1.0)
		game.audio.play(FIRE_SOUND.get(wep.name, "gunshot"), origin_px, vol, _rng.randf_range(0.95, 1.05))
		_shoot(p, wep, angle, miss)


func _shoot(p, wep: Dictionary, angle: float, dud: bool) -> void:
	var count: int = maxi(1, wep.count + count_mod)
	var speed: float = wep.speed * speed_mod
	var spawn_dist: float = wep.get("spawn_dist", 0.4)
	var dir := Vector2.from_angle(angle)
	var dmg := int(floorf((wep.dmg + dmg_mod) * p.dmg_mult))
	var j: Dictionary = JUICE.get(wep.name, {"shake": 2.0, "time": 0.08, "recoil": 0.8, "flash": 6.0})
	var muzzle_px: float = _view.muzzle_offset_px(wep)
	var muzzle: Vector2 = p.position + dir * muzzle_px

	if not dud:
		for i in count:
			var spread: float = wep.spread * spread_mod
			var ba := angle + (_rng.randf() * spread * 2.0 - spread)
			bullets.append({
				"pos": p.tile_pos + dir * spawn_dist, "start": p.tile_pos,
				"vel": Vector2.from_angle(ba) * speed, "dmg": dmg, "pierce": wep.pierce,
				"life": BULLET_LIFE, "color": wep.color, "hit": [],
				"reveal": maxf(spawn_dist, muzzle_px / TILE - 0.1), "visible": false,
			})

	# juice
	game.fx.gunshot(muzzle, dir, wep.name)
	game.fx.shake(j.shake * (1.0 if not dud else 0.6), j.time)
	_view.recoil = j.recoil
	_view.flash_t = 0.06
	_view.flash_size = j.flash
	if wep.name != "suppressed pistol":
		_flash_light = 1.0
		_light.position = muzzle
		_light.texture_scale = (4.5 if wep.name == "shotgun" else 3.2) * TILE * 2.0 / float(_light_tex.get_width())
		_flash_peak = 1.6 if wep.name == "shotgun" else 1.1
		_light.energy = _flash_peak
	_eject_casing(p, wep, dir)


func _eject_casing(p, wep: Dictionary, dir: Vector2) -> void:
	var side := Vector2(-dir.y, dir.x)
	for i in 1:
		var col := Color(0.8, 0.15, 0.1) if wep.name == "shotgun" else Color(0.85, 0.7, 0.3)
		casings.append({
			"pos": p.position + dir * 30.0 + side * 6.0,
			"vel": side * _rng.randf_range(70.0, 130.0) + dir * _rng.randf_range(-20.0, 30.0),
			"rot": _rng.randf() * TAU, "spin": _rng.randf_range(-18.0, 18.0),
			"life": 1.6, "color": col, "size": 1.5 if wep.name == "shotgun" else 1.0,
		})
	if casings.size() > 60:
		casings = casings.slice(casings.size() - 60)


func _melee_hit(p, wep: Dictionary, angle: float) -> void:
	var reach: float = wep.reach
	var dmg := get_melee_damage(p.dmg_mult * (TIRED_DMG if _tired else 1.0))
	var hits := 0
	var kills := 0
	for e in _enemy_list():
		if _invulnerable(e):
			continue
		var d: Vector2 = e.tile_pos - p.tile_pos
		var dist := d.length()
		if dist >= reach + maxf(float(e.radius), 0.0):
			continue
		if absf(wrapf(d.angle() - angle, -PI, PI)) >= PI / 3.0:     # +-60 deg cone
			continue
		if not _has_los(p.tile_pos, e.tile_pos):
			continue
		hits += 1
		var dir := d.normalized() if dist > 0.001 else Vector2.from_angle(angle)
		var epx: Vector2 = e.tile_pos * TILE
		e.take_damage(float(dmg), dir)
		var dead: bool = not is_instance_valid(e) or e.hp <= 0.0
		game.fx.burst(epx, "hit", dir)
		game.fx.blood(epx, 1.0 if dead else 0.6)
		game.fx.melee_hit(epx, dir, wep.name, dead)
		if dead:
			kills += 1
			game.fx.burst(epx, "gib", dir)
		game.fx.float_text(epx + Vector2(0, -34), str(dmg), Color(1.0, 0.3, 0.2) if dead else Color(1.0, 0.92, 0.6))
	if hits > 0:
		game.hitstop(0.06 if kills > 0 else 0.04)
		game.fx.shake((3.0 + wep.dmg * 0.2) * (1.6 if kills > 0 else 1.0), 0.14)


func _enemy_list() -> Array:
	if game.enemies and game.enemies.has_method("get_enemies"):
		return game.enemies.get_enemies().duplicate()
	return []


func _invulnerable(e) -> bool:
	return "invulnerable" in e and e.invulnerable


func _has_los(a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var steps := int(ceilf(d.length() * 4.0))
	for i in range(1, steps):
		var q := a + d * (float(i) / steps)
		if game.map.is_solid(q.x, q.y):
			return false
	return true


# ---- bullets -----------------------------------------------------------

func _update_bullets(dt: float) -> void:
	if bullets.is_empty():
		return
	var enemies := _enemy_list()
	var dmg_taken := {}            # enemy instance id -> [enemy, total dmg, killed]
	var keep: Array[Dictionary] = []
	for b in bullets:
		b.life -= dt
		var travel: Vector2 = b.vel * dt
		var n := maxi(1, int(ceilf(travel.length() / 0.25)))
		var step := travel / n
		var dead := false
		for s in n:
			var prev: Vector2 = b.pos
			b.pos += step
			if game.map.is_solid(b.pos.x, b.pos.y):
				_impact(prev, b.vel.normalized())
				dead = true
				break
			for e in enemies:
				if not is_instance_valid(e) or _invulnerable(e):
					continue
				var id: int = e.get_instance_id()
				if id in b.hit:
					continue
				var d: Vector2 = b.pos - e.tile_pos
				var hit_r: float = maxf(float(e.radius), 0.3) + 0.15
				if d.length_squared() < hit_r * hit_r:
					_bullet_hit(b, e, dmg_taken)
					b.hit.append(id)
					if not b.pierce:
						dead = true
					break
			if dead:
				break
		if b.life <= 0.0:
			dead = true
		if not dead:
			if not b.visible and (b.pos - b.start).length() >= b.reveal:
				b.visible = true
			keep.append(b)
	bullets = keep
	for id in dmg_taken:
		var info: Array = dmg_taken[id]
		var e = info[0]
		var pos: Vector2 = info[3]
		game.fx.float_text(pos + Vector2(0, -34), str(info[1]), Color(1.0, 0.3, 0.2) if info[2] else Color(1.0, 0.92, 0.6))


func _bullet_hit(b: Dictionary, e, acc: Dictionary) -> void:
	var dir: Vector2 = b.vel.normalized()
	var epx: Vector2 = e.tile_pos * TILE
	e.take_damage(float(b.dmg), dir * 0.5)
	var dead: bool = not is_instance_valid(e) or e.hp <= 0.0
	game.fx.burst(b.pos * TILE, "hit", dir)
	game.fx.flesh_hit(b.pos * TILE, dir)
	game.fx.blood(b.pos * TILE, 0.5 if not dead else 1.0)
	if dead:
		game.fx.burst(epx, "gib", dir)
		game.fx.shake(2.5, 0.1)
	var id: int = e.get_instance_id() if is_instance_valid(e) else -b.dmg
	if acc.has(id):
		acc[id][1] += b.dmg
		acc[id][2] = acc[id][2] or dead
	else:
		acc[id] = [e, b.dmg, dead, epx]


func _impact(pos: Vector2, dir: Vector2) -> void:
	game.fx.wall_hit(pos * TILE, -dir)
	game.fx.burst(pos * TILE, "spark", -dir)
	if _rng.randf() < 0.5:
		game.fx.burst(pos * TILE, "smoke", -dir)


func _update_casings(dt: float) -> void:
	var i := 0
	while i < casings.size():
		var c := casings[i]
		c.life -= dt
		c.pos += c.vel * dt
		c.vel *= maxf(0.0, 1.0 - 5.0 * dt)
		c.rot += c.spin * dt
		c.spin *= maxf(0.0, 1.0 - 4.0 * dt)
		if c.life <= 0.0:
			if _rng.randf() < 0.5:
				game.fx.casing_land(c.pos, c.color)
			casings.remove_at(i)
		else:
			i += 1


func _update_view(dt: float, p) -> void:
	_view.position = p.position
	_view.recoil = maxf(0.0, _view.recoil - dt * 9.0)
	_view.pop = maxf(0.0, _view.pop - dt * 7.0)
	_view.flash_t = maxf(0.0, _view.flash_t - dt)
	_view.queue_redraw()
	if _flash_light > 0.0:
		_flash_light = maxf(0.0, _flash_light - dt * 14.0)
		_light.energy = _flash_peak * _flash_light * _flash_light


func _redraw() -> void:
	if _layer:
		_layer.queue_redraw()
		_glow.queue_redraw()


func _msg(text: String, color: Color) -> void:
	message.emit(text, color)
	if game and game.ui and game.ui.has_method("add_message"):
		game.ui.add_message(text, color)


func _make_light_texture() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 256
	t.height = 256
	return t
