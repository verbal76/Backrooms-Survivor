class_name WorldOrb
extends Node2D
## Chaos orb: scan -> chase -> return state machine from orbs.lua, drawn like drawOrbs() in main.lua
## (green = mostly buff, yellow = mostly nerf) with a PointLight2D so it lights its surroundings.

const K := 1.6
const MAGNET_RANGE := 1.5       # extra pull close to the player so orbs are easy to collect
const MAGNET_SPEED := 6.5

var tile_pos := Vector2.ZERO
var home := Vector2.ZERO
var state := "scan"
var detect_range: float = Loot.ORB_DETECT_RANGE
var chase_speed := 0.0
var escape_range: float = Loot.ORB_ESCAPE_RANGE
var pulse := 0.0
var particle_angle := 0.0
var is_buff := true
var tile_px := 52.0
var age := 0.0
var collected := false
var light: PointLight2D
var _halo: Sprite2D
var _trail: Array[Vector2] = []


func setup(p_pos: Vector2, p_buff: bool, p_tile: float) -> void:
	tile_pos = p_pos
	home = p_pos
	is_buff = p_buff
	tile_px = p_tile
	position = tile_pos * tile_px
	pulse = randf() * 3.0
	var c := _glow_color()
	_halo = Loot.make_halo(Color(c.r, c.g, c.b, 0.3), 34.0)
	add_child(_halo)
	light = Loot.make_light(c, 3.2, 0.8)
	add_child(light)


func _glow_color() -> Color:
	return Color(0.1, 0.9, 0.35) if is_buff else Color(0.95, 0.75, 0.15)


## Port of Orbs:update for one orb. player_speed = player base speed (tiles/s).
func step(dt: float, player_tile: Vector2, player_speed: float) -> void:
	pulse += dt
	age += dt
	particle_angle += dt * 2.0
	var d := player_tile - tile_pos
	var dist := d.length()
	match state:
		"scan":
			if dist < detect_range:
				state = "chase"
				chase_speed = player_speed * 0.9
		"chase":
			if dist > 0.3:
				var spd := chase_speed
				if dist < MAGNET_RANGE:
					spd = maxf(spd, MAGNET_SPEED * (1.0 - dist / MAGNET_RANGE * 0.5))
				tile_pos += d / dist * spd * dt
			if (tile_pos - home).length_squared() > escape_range * escape_range:
				state = "return"
		"return":
			var h := home - tile_pos
			var hd := h.length()
			if hd > 0.2:
				tile_pos += h / hd * 1.5 * dt
			else:
				tile_pos = home
				state = "scan"
	position = tile_pos * tile_px
	_trail.push_front(position)
	if _trail.size() > 6:
		_trail.pop_back()
	queue_redraw()


func _draw() -> void:
	var sc := clampf(age * 3.0, 0.0, 1.0)
	sc = 1.0 + 2.7 * pow(sc - 1.0, 3.0) + 1.7 * pow(sc - 1.0, 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(sc, sc))
	var p := sin(pulse * 3.0) * 0.3 + 0.7
	var ch := state == "chase"
	var glow := _glow_color()
	var core := Color(0.03, 0.08, 0.04) if is_buff else Color(0.08, 0.06, 0.02)
	var part := Color(0.3, 1, 0.5) if is_buff else Color(1, 0.85, 0.3)
	var eye := Color(0.3, 1, 0.4) if is_buff else Color(1, 0.9, 0.3)
	var spec := Color(0.7, 1, 0.8) if is_buff else Color(1, 0.95, 0.7)
	# motion trail while chasing
	if ch:
		for i in range(1, _trail.size()):
			draw_circle(_trail[i] - position, (8.0 - i) * K * 0.8, Color(glow.r, glow.g, glow.b, 0.10 * (1.0 - i / 6.0)))
	draw_circle(Vector2.ZERO, (16.0 if ch else 13.0) * K, Color(glow.r * 0.6, glow.g * 0.6, glow.b * 0.6, 0.18 * p))
	draw_circle(Vector2.ZERO, (8.0 + p) * K, core)
	draw_arc(Vector2.ZERO, (8.0 + p) * K, 0, TAU, 24, Color(glow.r, glow.g, glow.b, 0.55), 1.2)
	for j in 4:
		var pa := particle_angle + j * PI / 2.0
		var pr := (9.0 + p * 2.0) * K
		draw_circle(Vector2(cos(pa), sin(pa)) * pr, 2.0 * K, Color(part.r, part.g, part.b, 0.7))
		var ta := pa - 0.3
		draw_circle(Vector2(cos(ta), sin(ta)) * pr, 1.2 * K, Color(part.r * 0.7, part.g * 0.7, part.b * 0.7, 0.3))
	if ch:
		draw_circle(Vector2(-3, -1) * K, 2.0 * K, eye)
		draw_circle(Vector2(3, -1) * K, 2.0 * K, eye)
		draw_circle(Vector2.ZERO, 5.0 * K, Color(glow.r, glow.g, glow.b, 0.3 * p))
	else:
		var f := ThemeDB.fallback_font
		var sym := "+" if is_buff else "?"
		var sc2 := Color(0.3, 0.8, 0.5) if is_buff else Color(0.8, 0.7, 0.2)
		draw_string(f, Vector2(-5.0, 6.0) * K * 0.9, sym, HORIZONTAL_ALIGNMENT_CENTER, 10.0 * K * 0.9, int(14 * K * 0.8), sc2)
	draw_circle(Vector2(-2, -3) * K, 2.5 * K, Color(spec.r, spec.g, spec.b, 0.25 * p))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if light:
		light.energy = 0.65 + 0.25 * p + (0.25 if ch else 0.0)
