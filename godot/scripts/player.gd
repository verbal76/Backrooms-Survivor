class_name Player
extends Node2D
## Port of player.lua: movement, survival stats, XP/levels, streaks, inventory.
## Positions are in TILE units (tile_pos); the node itself sits at tile_pos * TILE pixels.
## Numbers are copied from Player.STATS in player.lua - change them there first when balancing.

const TILE := 52
const FRAMES := 16
const SPRITE_ANGLE_OFFSET := -PI / 2.0
const BODY_R := 0.25
const HEADLAMP_FORWARD := 0.18
const PERK_EVERY_N_LEVELS := 2

# Player.STATS
const S := {
	"hp": 100.0, "invuln_time": 1.0,
	"stamina": 100.0, "stamina_regen": 7.0, "sprint_cost": 16.0,
	"sanity": 100.0, "sanity_drain": 0.25, "sanity_light_min": 0.2, "sanity_regen_mult": 4.0,
	"hydration": 100.0, "hydration_drain": 0.5, "hydration_sprint": 1.5,
	"base_speed": 3.5, "sprint_mult": 1.6, "accel": 18.0, "decel": 14.0,
	"dmg_mult": 1.0,
	"base_noise": 2.0, "move_noise": 12.0, "sprint_noise": 25.0, "noise_decay": 30.0,
	"almond_water": 3, "bandages": 2, "food": 0, "batteries": 2,
	"start_xp_need": 10, "xp_scaling": 1.5,
	"lvl_hp_bonus": 10.0, "lvl_hp_heal": 20.0, "lvl_stamina_bonus": 5.0, "lvl_sanity_restore": 20.0,
	"dehydration_dps": 1.0, "almond_hydra": 40.0, "almond_sanity": 15.0, "almond_hp": 10.0,
	"bandage_hp": 30.0, "food_stamina": 40.0, "food_sanity": 10.0,
}
const STREAK_THRESHOLDS := [[5, 1.2], [10, 1.5], [20, 2.0], [50, 3.0]]
const STREAK_MILESTONES := [5, 10, 15, 20, 25, 30, 40, 50, 75, 100]

signal leveled_up(level: int)
signal damaged(amount: float)
signal died

var map: WorldMap
var tile_pos := Vector2.ZERO
var vel := Vector2.ZERO
var angle := 0.0
var fx := 1.0          # facing vector (cos/sin of angle)
var fy := 0.0

var hp: float = S.hp
var max_hp: float = S.hp
var stamina: float = S.stamina
var max_stamina: float = S.stamina
var sanity: float = S.sanity
var max_sanity: float = S.sanity
var hydration: float = S.hydration
var max_hydration: float = S.hydration

var base_speed: float = S.base_speed
var speed_mult := 1.0
var sprint_mult: float = S.sprint_mult
var sprinting := false
var moving := false
var dmg_mult: float = S.dmg_mult           # outgoing damage multiplier
var dmg_taken_mult := 1.0                  # perk: Tough Skin
var invuln_time_mult := 1.0                # perk: Thick Skull
var invuln_time := 0.0
var dmg_flash := 0.0

var noise := 0.0                           # 0..100, enemies hear this
var xp := 0
var level := 1
var xp_need: int = S.start_xp_need
var almond_water: int = S.almond_water
var bandages: int = S.bandages
var food: int = S.food
var batteries: int = S.batteries
var headlamp_on := true
# per-run multipliers from game.ui.run_mods (difficulty, perks, meta upgrades)
var sanity_drain_mult := 1.0
var hydration_drain_mult := 1.0
var sprint_cost_mult := 1.0

var current_streak := 0
var best_run_streak := 0
var streak_display_timer := 0.0
var pending_perk_choice := false
var active_run_perks: Array = []
var footstep_timer := 0.0
const FOOTSTEP_INTERVAL := 0.35
signal footstep(sprinting: bool)

var _sprite: Sprite2D
var lamp: PointLight2D


func _ready() -> void:
	z_index = 1   # draw above enemies/props (big enemies used to cover the player); weapons are z 2
	_sprite = Sprite2D.new()
	_sprite.texture = preload("res://assets/sprites/player_spritesheet.png")
	_sprite.hframes = FRAMES
	_sprite.scale = Vector2.ONE * (TILE * 1.2 * 2.0 / 128.0)
	add_child(_sprite)


## One simulation step. aim_world is a world-space pixel position to face.
func step(dt: float, input_dir: Vector2, want_sprint: bool, aim_world: Vector2, is_firing := false, light_level := 0.05) -> void:
	sprinting = want_sprint and stamina > 0.0
	var max_speed := base_speed * speed_mult * (sprint_mult if sprinting else 1.0)
	var d := input_dir
	if d.length() > 1.0:
		d = d.normalized()
	var has_input := d.length() > 0.05
	var rate: float = S.accel if has_input else S.decel
	vel = vel.lerp(d * max_speed, minf(1.0, rate * dt))
	if absf(vel.x) < 0.01: vel.x = 0.0
	if absf(vel.y) < 0.01: vel.y = 0.0
	moving = vel != Vector2.ZERO
	if moving:
		_try_move(vel * dt)

	if sprinting and moving:
		stamina -= S.sprint_cost * sprint_cost_mult * dt
	else:
		stamina = minf(max_stamina, stamina + S.stamina_regen * dt)
	stamina = maxf(0.0, stamina)

	# sanity drains faster in the dark, recovers in light
	var drain: float = S.sanity_drain * sanity_drain_mult * (1.0 + (1.0 - light_level) * 2.0)
	if hydration <= 0.0:
		drain *= 2.0
	sanity -= drain * dt
	if light_level > S.sanity_light_min:
		sanity += (light_level - S.sanity_light_min) * S.sanity_regen_mult * dt
	sanity = clampf(sanity, 0.0, max_sanity)

	if hydration <= 0.0 and hp > 1.0:   # BALANCE: dehydration now hurts (never lethal on its own)
		hp = maxf(1.0, hp - S.dehydration_dps * dt)
	hydration = maxf(0.0, hydration - S.hydration_drain * hydration_drain_mult * (S.hydration_sprint if sprinting else 1.0) * dt)

	# noise: what enemies track
	var add: float = S.base_noise * dt
	if moving:
		add += (S.sprint_noise if sprinting else S.move_noise) * dt
	if is_firing:
		add += 40.0 * dt
	noise = maxf(0.0, minf(100.0, noise + add) - S.noise_decay * dt)

	if moving:
		footstep_timer += dt
		if footstep_timer >= FOOTSTEP_INTERVAL:
			footstep_timer -= FOOTSTEP_INTERVAL
			footstep.emit(sprinting)
	else:
		footstep_timer = 0.0

	if invuln_time > 0.0: invuln_time -= dt
	if dmg_flash > 0.0: dmg_flash -= dt
	if streak_display_timer > 0.0: streak_display_timer -= dt

	aim_at(aim_world, dt)
	position = tile_pos * TILE
	var norm := fposmod(angle + SPRITE_ANGLE_OFFSET, TAU)
	_sprite.frame = int(floor(norm / TAU * FRAMES + 0.5)) % FRAMES
	_sprite.visible = not (invuln_time > 0.0 and int(invuln_time * 10.0) % 2 == 0)
	if lamp:
		lamp.visible = headlamp_on
		lamp.position = Vector2.from_angle(angle) * HEADLAMP_FORWARD * TILE


func aim_at(world_px: Vector2, dt: float) -> void:
	var to := world_px / TILE - tile_pos
	if to != Vector2.ZERO:
		var diff := wrapf(to.angle() - angle, -PI, PI)
		angle += diff * minf(1.0, 20.0 * dt)
		fx = cos(angle)
		fy = sin(angle)


func _try_move(delta: Vector2) -> void:
	if delta.x != 0.0:
		var nx := tile_pos.x + delta.x
		var ex := nx + (BODY_R if delta.x > 0.0 else -BODY_R)
		if not (map.is_solid(ex, tile_pos.y - BODY_R) or map.is_solid(ex, tile_pos.y) or map.is_solid(ex, tile_pos.y + BODY_R)):
			tile_pos.x = nx
		else:
			vel.x = 0.0
	if delta.y != 0.0:
		var ny := tile_pos.y + delta.y
		var ey := ny + (BODY_R if delta.y > 0.0 else -BODY_R)
		if not (map.is_solid(tile_pos.x - BODY_R, ey) or map.is_solid(tile_pos.x, ey) or map.is_solid(tile_pos.x + BODY_R, ey)):
			tile_pos.y = ny
		else:
			vel.y = 0.0


## Returns true if this hit killed the player. Ignored during invulnerability.
func take_damage(amount: float) -> bool:
	if invuln_time > 0.0:
		return false
	var final := floorf(amount * dmg_taken_mult)
	hp -= final
	dmg_flash = 0.3
	invuln_time = 0.5 * invuln_time_mult
	current_streak = 0
	damaged.emit(final)
	if hp <= 0.0:
		hp = 0.0
		died.emit()
		return true
	return false


func get_streak_multiplier() -> float:
	if current_streak < 5:
		return 1.0
	if current_streak <= STREAK_THRESHOLDS[0][0]:
		return 1.0 + (STREAK_THRESHOLDS[0][1] - 1.0) * (float(current_streak) / STREAK_THRESHOLDS[0][0])
	for i in range(1, STREAK_THRESHOLDS.size()):
		if current_streak <= STREAK_THRESHOLDS[i][0]:
			var prev = STREAK_THRESHOLDS[i - 1]
			var cur = STREAK_THRESHOLDS[i]
			var t := float(current_streak - prev[0]) / float(cur[0] - prev[0])
			return prev[1] + (cur[1] - prev[1]) * t
	return STREAK_THRESHOLDS[-1][1]


func record_kill() -> void:
	current_streak += 1
	best_run_streak = maxi(best_run_streak, current_streak)
	if current_streak in STREAK_MILESTONES:
		streak_display_timer = 2.0


## Adds XP (with streak bonus). Returns true on level-up.
func add_xp(amount: int) -> bool:
	xp += int(floorf(amount * get_streak_multiplier()))
	if xp >= xp_need:
		xp -= xp_need
		level += 1
		xp_need = int(floorf(xp_need * S.xp_scaling))
		max_hp += S.lvl_hp_bonus
		hp = minf(hp + S.lvl_hp_heal, max_hp)
		max_stamina += S.lvl_stamina_bonus
		sanity = minf(max_sanity, sanity + S.lvl_sanity_restore)
		pending_perk_choice = level % PERK_EVERY_N_LEVELS == 0
		leveled_up.emit(level)
		return true
	return false


func use_almond_water() -> bool:
	if almond_water <= 0: return false
	almond_water -= 1
	hydration = minf(max_hydration, hydration + S.almond_hydra)
	sanity = minf(max_sanity, sanity + S.almond_sanity)
	hp = minf(max_hp, hp + S.almond_hp)
	return true


func use_bandage() -> bool:
	if bandages <= 0: return false
	bandages -= 1
	hp = minf(max_hp, hp + S.bandage_hp)
	return true


func use_food() -> bool:
	if food <= 0: return false
	food -= 1
	stamina = minf(max_stamina, stamina + S.food_stamina)
	sanity = minf(max_sanity, sanity + S.food_sanity)
	return true
