class_name BombBlast
extends Node2D
## Expanding shockwave drawn like Bomb:draw (ring + core + sparks), lives 0.6 s then frees itself.

const LIFE := 0.6
var radius_px := 156.0
var t := 0.0
var _sparks: Array[float] = []
var _light: PointLight2D


func _ready() -> void:
	z_index = 20
	for i in 14:
		_sparks.append(randf_range(0.5, 1.0))
	_light = Loot.make_light(Color(1.0, 0.7, 0.3), radius_px / 40.0, 2.2)
	add_child(_light)


func _process(delta: float) -> void:
	t += delta
	if t >= LIFE:
		queue_free()
		return
	_light.energy = 2.2 * (1.0 - t / LIFE)
	queue_redraw()


func _draw() -> void:
	var prog := t / LIFE
	var wave_r := radius_px * minf(1.0, prog * 1.5)
	var a := maxf(0.0, 1.0 - prog)
	draw_circle(Vector2.ZERO, wave_r, Color(1, 0.6, 0.2, a * 0.3))
	draw_circle(Vector2.ZERO, wave_r * 0.3 * (1.0 - prog) + 4.0, Color(1, 0.95, 0.8, a * 0.8))
	draw_arc(Vector2.ZERO, wave_r, 0, TAU, 48, Color(1, 0.5, 0.1, a * 0.7), 4.0)
	draw_arc(Vector2.ZERO, wave_r * 0.82, 0, TAU, 48, Color(1, 0.85, 0.5, a * 0.35), 2.0)
	if prog < 0.6:
		for i in _sparks.size():
			var sa := i * TAU / _sparks.size() + prog * 3.0
			var sr := wave_r * _sparks[i]
			draw_circle(Vector2(cos(sa), sin(sa)) * sr, 3.0, Color(1, 0.8, 0.3, a))
