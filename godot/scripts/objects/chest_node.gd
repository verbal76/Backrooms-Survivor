class_name ChestMarker
extends Node2D
## Military chest in the middle of a chest room: crate + golden pulsing glow (drawChestMarkers in main.lua).
## open() plays a lid-pop animation when the player trips the proximity trigger.

var tile_pos := Vector2.ZERO
var tile_px := 52.0
var opened := false
var t := 0.0
var _open_t := 0.0
var _halo: Sprite2D
var _light: PointLight2D


func setup(p_pos: Vector2, p_tile: float) -> void:
	tile_pos = p_pos
	tile_px = p_tile
	position = p_pos * p_tile
	z_index = 0
	_halo = Loot.make_halo(Color(1, 0.8, 0.2, 0.3), p_tile * 2.5)
	add_child(_halo)
	_light = Loot.make_light(Color(1.0, 0.8, 0.3), 3.0, 0.7)
	add_child(_light)


func open() -> void:
	opened = true
	_open_t = 0.0


func _process(delta: float) -> void:
	t += delta
	if opened:
		_open_t += delta
		var k := clampf(1.0 - _open_t / 1.5, 0.0, 1.0)
		_halo.modulate.a = 0.6 * k
		_light.energy = 1.8 * k
		if _open_t > 1.5:
			_light.visible = false
	else:
		var pulse := sin(t * 2.0) * 0.12 + 0.28
		_halo.modulate.a = pulse * 1.2
		_light.energy = 0.55 + pulse
	queue_redraw()


func _draw() -> void:
	var w := 34.0
	var h := 22.0
	var body := Color(0.28, 0.33, 0.2)
	var dark := Color(0.16, 0.2, 0.12)
	draw_set_transform(Vector2(0, 12), 0.0, Vector2(1, 0.4))
	draw_circle(Vector2.ZERO, w * 0.7, Color(0, 0, 0, 0.5))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(-w / 2, -h / 2 + 4, w, h), body)
	draw_rect(Rect2(-w / 2, -h / 2 + 4, w, 4), dark)
	draw_rect(Rect2(-w / 2, -h / 2 + 4, w, h), Color(0.08, 0.1, 0.05), false, 1.5)
	draw_rect(Rect2(-w / 2 + 6, -h / 2 + 4, 3, h), Color(0.45, 0.45, 0.4))
	draw_rect(Rect2(w / 2 - 9, -h / 2 + 4, 3, h), Color(0.45, 0.45, 0.4))
	var lift := 0.0 if not opened else minf(_open_t * 4.0, 1.0)
	var lid_h := 8.0 * (1.0 - lift * 0.9)
	var lid_y := -h / 2 + 4 - lid_h - lift * 10.0
	draw_rect(Rect2(-w / 2, lid_y, w, lid_h), Color(0.34, 0.4, 0.24))
	draw_rect(Rect2(-w / 2, lid_y, w, lid_h), Color(0.08, 0.1, 0.05), false, 1.5)
	if opened:
		draw_rect(Rect2(-w / 2 + 3, -h / 2 + 4, w - 6, 4), Color(1, 0.85, 0.3, 0.8 * maxf(0.0, 1.0 - _open_t / 1.5)))
	else:
		draw_rect(Rect2(-3, -h / 2 + 2, 6, 5), Color(0.9, 0.75, 0.2))
		draw_circle(Vector2(0, 3), 3.0, Color(0.85, 0.85, 0.7, 0.8))
