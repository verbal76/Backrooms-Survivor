extends Node2D
## Draws all bullets (and shell casings) in one canvas item. Port of drawBullets() in main.lua
## (smoke puffs, brass body, copper tip, highlight) plus an additive glow/tracer pass.
## Two instances are used: a normal one and an additive one (additive = true) for the glow.

const TILE := 52.0
const Z := 52.0 / 24.0 * 0.85       # charScale * bulletScale

var wp                               # weapons system (owns .bullets / .casings)
var additive := false


func _ready() -> void:
	z_index = 1
	if additive:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m


func _draw() -> void:
	if wp == null:
		return
	if additive:
		_draw_glow()
		return
	for c in wp.casings:
		_draw_casing(c)
	for b in wp.bullets:
		if not b.visible:
			continue
		_draw_bullet(b)


func _draw_bullet(b: Dictionary) -> void:
	var s: Vector2 = b.pos * TILE
	var f: Vector2 = b.vel.normalized()
	var p := Vector2(-f.y, f.x)
	# smoke trail puffs
	for i in range(1, 4):
		draw_circle(s - f * (i * 4.0) * Z, (1.5 - i * 0.3) * Z, Color(0.6, 0.55, 0.45, 0.15))
	var ln := 3.5 * Z
	var wd := 1.2 * Z
	draw_colored_polygon(PackedVector2Array([
		s - f * ln + p * wd, s - f * ln - p * wd,
		s + f * ln * 0.3 - p * wd, s + f * ln * 0.3 + p * wd]), Color(0.75, 0.6, 0.25))
	draw_colored_polygon(PackedVector2Array([
		s + f * ln * 0.3 + p * wd * 0.9, s + f * ln * 0.3 - p * wd * 0.9, s + f * ln * 1.2]),
		Color(0.85, 0.5, 0.2))
	draw_line(s - f * ln * 0.8 + p * wd * 0.5, s + f * ln * 0.8 + p * wd * 0.3, Color(1, 0.95, 0.7, 0.5), 0.6 * Z)


func _draw_glow() -> void:
	for b in wp.bullets:
		if not b.visible:
			continue
		var s: Vector2 = b.pos * TILE
		var f: Vector2 = b.vel.normalized()
		var col: Color = b.color
		var warm := Color(1.0, 0.75, 0.35).lerp(col, 0.25)
		# tracer: fading streak behind the bullet
		var tail: float = clampf(b.vel.length() * 0.035, 0.2, 0.6) * TILE
		var steps := 6
		for i in range(steps):
			var t0 := float(i) / steps
			var t1 := float(i + 1) / steps
			var a := (1.0 - t0) * 0.55
			draw_line(s - f * tail * t0, s - f * tail * t1, Color(warm.r, warm.g, warm.b, a), (3.4 - 2.4 * t0) * Z * 0.8)
		draw_circle(s, 4.5 * Z * 0.8, Color(1.0, 0.7, 0.3, 0.18))
		draw_circle(s, 2.2 * Z * 0.8, Color(1.0, 0.9, 0.6, 0.35))


func _draw_casing(c: Dictionary) -> void:
	var a := clampf(c.life / 0.4, 0.0, 1.0)
	var col: Color = c.color
	draw_set_transform(c.pos, c.rot, Vector2.ONE)
	draw_rect(Rect2(Vector2(-2.2, -1.1) * c.size, Vector2(4.4, 2.2) * c.size), Color(col.r, col.g, col.b, a))
	draw_rect(Rect2(Vector2(-2.2, -1.1) * c.size, Vector2(1.2, 2.2) * c.size), Color(1, 1, 1, 0.35 * a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
