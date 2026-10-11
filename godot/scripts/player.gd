class_name Player
extends Node2D
## Port of player.lua movement + stats. Position is in tile units; the node itself is
## placed at tile * TILE pixels. The 16-frame rotation sheet is the original art.

const TILE := 52
const FRAMES := 16
const SPRITE_ANGLE_OFFSET := -PI / 2.0
const BODY_R := 0.25
const HEADLAMP_FORWARD := 0.18

var map: WorldMap
var tile_pos := Vector2.ZERO
var vel := Vector2.ZERO
var angle := 0.0
var sprinting := false
var moving := false

var hp := 100.0
var stamina := 100.0
var max_stamina := 100.0
var base_speed := 3.5
var sprint_mult := 1.6
var accel := 18.0
var decel := 14.0

var _sprite: Sprite2D
var lamp: PointLight2D


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = preload("res://assets/sprites/player_spritesheet.png")
	_sprite.hframes = FRAMES
	_sprite.scale = Vector2.ONE * (TILE * 1.2 * 2.0 / 128.0)
	add_child(_sprite)


func step(dt: float, input_dir: Vector2, want_sprint: bool, aim_world: Vector2) -> void:
	sprinting = want_sprint and stamina > 0.0
	var max_speed := base_speed * (sprint_mult if sprinting else 1.0)
	var d := input_dir
	if d.length() > 1.0:
		d = d.normalized()
	var has_input := d.length() > 0.05
	var rate := accel if has_input else decel
	vel = vel.lerp(d * max_speed, minf(1.0, rate * dt))
	if vel.length() < 0.01:
		vel = Vector2.ZERO
	moving = vel != Vector2.ZERO
	if moving:
		_try_move(vel * dt)

	if sprinting and moving:
		stamina -= 20.0 * dt
	else:
		stamina = minf(max_stamina, stamina + 4.0 * dt)
	stamina = maxf(0.0, stamina)

	# aim (smooth, like Player:aimAt)
	var to := aim_world / TILE - tile_pos
	if to != Vector2.ZERO:
		var diff := wrapf(to.angle() - angle, -PI, PI)
		angle += diff * minf(1.0, 20.0 * dt)

	position = tile_pos * TILE
	var norm := fposmod(angle + SPRITE_ANGLE_OFFSET, TAU)
	_sprite.frame = int(floor(norm / TAU * FRAMES + 0.5)) % FRAMES
	if lamp:
		lamp.position = Vector2.from_angle(angle) * HEADLAMP_FORWARD * TILE


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
