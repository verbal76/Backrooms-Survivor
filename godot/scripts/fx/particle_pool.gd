class_name ParticlePool
extends RefCounted
## Fixed-capacity struct-of-arrays particle simulation + drawing for one canvas item.
## Shapes: DOT (soft round texture), SQUARE (flat chunk), STREAK (line along velocity), RING (expanding arc).

enum { DOT, SQUARE, STREAK, RING }

var cap: int
var count := 0
var pos := PackedVector2Array()
var vel := PackedVector2Array()
var acc := PackedVector2Array()
var life := PackedFloat32Array()
var max_life := PackedFloat32Array()
var s0 := PackedFloat32Array()
var s1 := PackedFloat32Array()
var drag := PackedFloat32Array()
var shape := PackedByteArray()
var c0 := PackedColorArray()
var c1 := PackedColorArray()
var _dot: Texture2D


func _init(capacity: int) -> void:
	cap = capacity
	pos.resize(cap); vel.resize(cap); acc.resize(cap)
	life.resize(cap); max_life.resize(cap); s0.resize(cap); s1.resize(cap); drag.resize(cap)
	shape.resize(cap); c0.resize(cap); c1.resize(cap)
	_dot = TexGen.radial(64, 1.4)


func clear() -> void:
	count = 0


func emit(p: Vector2, v: Vector2, lifetime: float, size_a: float, size_b: float, col_a: Color, col_b: Color,
		shp := DOT, drg := 0.0, accel := Vector2.ZERO) -> void:
	var i := count
	if count >= cap:
		i = randi() % cap          # overwrite a random one when saturated
	else:
		count += 1
	pos[i] = p; vel[i] = v; acc[i] = accel
	life[i] = lifetime; max_life[i] = lifetime
	s0[i] = size_a; s1[i] = size_b; drag[i] = drg
	shape[i] = shp; c0[i] = col_a; c1[i] = col_b


func update(dt: float) -> void:
	var i := 0
	while i < count:
		life[i] -= dt
		if life[i] <= 0.0:
			count -= 1
			if i != count:   # swap-remove
				pos[i] = pos[count]; vel[i] = vel[count]; acc[i] = acc[count]
				life[i] = life[count]; max_life[i] = max_life[count]
				s0[i] = s0[count]; s1[i] = s1[count]; drag[i] = drag[count]
				shape[i] = shape[count]; c0[i] = c0[count]; c1[i] = c1[count]
			continue
		vel[i] += acc[i] * dt
		vel[i] *= maxf(0.0, 1.0 - drag[i] * dt)
		pos[i] += vel[i] * dt
		i += 1


func draw(ci: CanvasItem) -> void:
	for i in count:
		var t := 1.0 - life[i] / max_life[i]
		var col := c0[i].lerp(c1[i], t)
		var s := lerpf(s0[i], s1[i], t)
		match shape[i]:
			DOT:
				ci.draw_texture_rect(_dot, Rect2(pos[i].x - s, pos[i].y - s, s * 2.0, s * 2.0), false, col)
			SQUARE:
				ci.draw_rect(Rect2(pos[i].x - s * 0.5, pos[i].y - s * 0.5, s, s), col)
			STREAK:
				var v := vel[i]
				var tail := pos[i] - v * 0.035
				ci.draw_line(tail, pos[i], col, maxf(1.0, s))
			RING:
				ci.draw_arc(pos[i], s, 0.0, TAU, 28, col, maxf(1.5, 5.0 * (1.0 - t)))
