class_name WorldItem
extends Node2D
## A pickup lying on the floor. Port of the item table entries in items.lua and drawItems()
## in main.lua (icons are the Lua shapes, scaled up), plus pop-in, bob, halo and launch arcs.

const K := 1.7                  # Lua draw units -> pixels
const POP_TIME := 0.35

var kind := "bandage"
var tile_pos := Vector2.ZERO    # logical position (tiles); the node sits at tile_pos * TILE
var color := Color.WHITE
var weapon_id := -1             # 0-based index into the weapon list (kind == "weapon")
var tile_px := 52.0
var pulse := 0.0                # Lua pulseTimer
var age := 0.0
var collected := false
var _halo: Sprite2D
var _fly_t := 1.0
var _fly_from := Vector2.ZERO
var _fly_to := Vector2.ZERO
var _fly_dur := 0.5
var _hop := 0.0                 # arc height (px) of a launched item


func setup(p_kind: String, p_pos: Vector2, p_color: Color, p_tile: float, p_weapon := -1) -> void:
	kind = p_kind
	tile_pos = p_pos
	color = p_color
	weapon_id = p_weapon
	tile_px = p_tile
	position = tile_pos * tile_px
	pulse = randf() * 3.0
	_halo = Loot.make_halo(Color(color.r, color.g, color.b, 0.0), 26.0)
	add_child(_halo)


## Fly from `from_tile` to the current tile_pos in an arc (chest loot, enemy drops).
func launch(from_tile: Vector2, dur := 0.5, hop := 26.0) -> void:
	_fly_from = from_tile * tile_px
	_fly_to = tile_pos * tile_px
	_fly_dur = dur
	_fly_t = 0.0
	_hop = hop
	position = _fly_from


func _process(delta: float) -> void:
	pulse += delta
	age += delta
	if _fly_t < 1.0:
		_fly_t = minf(1.0, _fly_t + delta / _fly_dur)
		var e := 1.0 - pow(1.0 - _fly_t, 2.0)
		position = _fly_from.lerp(_fly_to, e) + Vector2(0, -sin(_fly_t * PI) * _hop)
	elif not collected:
		position = tile_pos * tile_px
	if _halo:
		var p := sin(pulse * 3.0) * 0.3 + 0.7
		var a := 0.22 * p * clampf(age * 3.0, 0.0, 1.0)
		_halo.modulate = Color(color.r, color.g, color.b, a)
	queue_redraw()


func _pop_scale() -> float:
	var t := clampf(age / POP_TIME, 0.0, 1.0)
	# ease-out-back: overshoots then settles (pickup "pop")
	var c1 := 1.9
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)


func _draw() -> void:
	var s := _pop_scale()
	var bob := sin(pulse * 2.5) * 2.2 - 3.0
	var p := sin(pulse * 3.0) * 0.3 + 0.7
	# ground shadow stays put while the item bobs
	draw_set_transform(Vector2(0, 8), 0.0, Vector2(s, 0.45 * s))
	draw_circle(Vector2.ZERO, 9.0, Color(0, 0, 0, 0.45))
	draw_set_transform(Vector2(0, bob), 0.0, Vector2(s, s))
	# dark backing + colour disc (Lua: r7 black, r5 coloured * pulse)
	draw_circle(Vector2.ZERO, 7.0 * K, Color(0, 0, 0, 0.6))
	draw_circle(Vector2.ZERO, 5.0 * K, Color(color.r * p, color.g * p, color.b * p))
	_draw_icon()
	if sin(pulse * 4.0) > 0.3:
		draw_arc(Vector2.ZERO, 6.0 * K, 0.0, TAU, 28, Color(1, 1, 1, 0.4), 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _v(x: float, y: float) -> Vector2:
	return Vector2(x, y) * K


func _line(a: Vector2, b: Vector2, c: Color, w: float) -> void:
	draw_line(a * K, b * K, c, w * K * 0.8, true)


func _poly(pts: Array, c: Color) -> void:
	var arr := PackedVector2Array()
	for q in pts:
		arr.append((q as Vector2) * K)
	draw_colored_polygon(arr, c)


func _draw_icon() -> void:
	match kind:
		"bomb":
			draw_arc(Vector2.ZERO, 4.0 * K, 0, TAU, 20, Color(1, 0.3, 0.1), 1.6)
			_line(Vector2(0, -5), Vector2(2, -8), Color(1, 0.8, 0.3), 1.2)
			draw_circle(_v(2, -8.4), 1.3 * K, Color(1, 0.9, 0.4, 0.5 + 0.5 * sin(pulse * 14.0)))
		"ammo":
			draw_rect(Rect2(_v(-2, -3), Vector2(4, 6) * K), Color(0.9, 0.7, 0.1))
			draw_rect(Rect2(_v(-1, -4), Vector2(2, 2) * K), Color(1, 0.9, 0.3))
			draw_rect(Rect2(_v(-3.5, -1.5), Vector2(1.4, 4.5) * K), Color(0.7, 0.5, 0.1))
			draw_rect(Rect2(_v(2.1, -1.5), Vector2(1.4, 4.5) * K), Color(0.7, 0.5, 0.1))
		"battery":
			draw_rect(Rect2(_v(-3, -4), Vector2(6, 8) * K), Color(0.2, 1, 0.6))
			draw_rect(Rect2(_v(-1, -6), Vector2(2, 2) * K), Color(0.1, 0.7, 0.4))
			draw_rect(Rect2(_v(-1, -2), Vector2(2, 4) * K), Color(1, 1, 0.8, 0.5))
		"bandage":
			draw_rect(Rect2(_v(-3.5, -2), Vector2(7, 4) * K), Color(0.95, 0.97, 0.9))
			_line(Vector2(0, -1.4), Vector2(0, 1.4), Color(0.2, 0.75, 0.25), 1.8)
			_line(Vector2(-1.4, 0), Vector2(1.4, 0), Color(0.2, 0.75, 0.25), 1.8)
		"almond water":
			draw_rect(Rect2(_v(-2, -2), Vector2(4, 6) * K), Color(0.75, 0.93, 1.0, 0.95))
			draw_rect(Rect2(_v(-1, -4.5), Vector2(2, 2.5) * K), Color(0.55, 0.8, 0.95))
			draw_rect(Rect2(_v(-1.2, 0.2), Vector2(2.4, 3.2) * K), Color(0.3, 0.6, 1.0))
		"food":
			draw_rect(Rect2(_v(-3, -2.5), Vector2(6, 5) * K), Color(0.85, 0.55, 0.15))
			draw_rect(Rect2(_v(-3, -2.5), Vector2(6, 1.2) * K), Color(0.95, 0.8, 0.45))
			_line(Vector2(-2, 1.2), Vector2(2, 1.2), Color(0.5, 0.3, 0.08), 1.0)
		"stamina drink":
			draw_rect(Rect2(_v(-2.5, -3.5), Vector2(5, 7) * K), Color(0.25, 0.45, 0.95))
			_poly([Vector2(0.8, -3), Vector2(-1.4, 0.4), Vector2(0, 0.4), Vector2(-0.8, 3), Vector2(1.6, -0.6), Vector2(0.1, -0.6)], Color(1, 0.95, 0.3))
		"weapon":
			_draw_weapon()


func _draw_weapon() -> void:
	match weapon_id:
		0: # machete
			_line(Vector2(3, 3), Vector2(1, 1), Color(0.25, 0.15, 0.08), 2.0)
			_line(Vector2(1, 1), Vector2(-5, -5), Color(0.75, 0.78, 0.82), 1.8)
			_line(Vector2(1, -0.5), Vector2(1, 2), Color(0.5, 0.5, 0.45), 1.5)
		1: # knife
			_line(Vector2(2, 3), Vector2(1, 1), Color(0.2, 0.2, 0.18), 2.0)
			_line(Vector2(0, -0.5), Vector2(2, 0.5), Color(0.5, 0.5, 0.48), 1.2)
			_poly([Vector2(-0.8, 0), Vector2(0.8, 0), Vector2(0, -5)], Color(0.7, 0.72, 0.78))
		2: # pipe
			_line(Vector2(-1, -6), Vector2(1, 6), Color(0.45, 0.45, 0.48), 2.5)
			_line(Vector2(0, -5), Vector2(0, 5), Color(0.6, 0.6, 0.65, 0.4), 0.6)
		3: # axe
			_line(Vector2(0, -6), Vector2(0, 5), Color(0.4, 0.25, 0.12), 1.8)
			_poly([Vector2(-3, -5), Vector2(3, -5), Vector2(2, -2), Vector2(-2, -2)], Color(0.55, 0.55, 0.58))
			_line(Vector2(-3, -5), Vector2(3, -5), Color(0.8, 0.82, 0.85), 0.9)
		4: # pistol
			_poly([Vector2(-4, -1.5), Vector2(3, -1.5), Vector2(3, 1), Vector2(-4, 1)], Color(0.3, 0.3, 0.32))
			_line(Vector2(3, 0), Vector2(5, 0), Color(0.25, 0.25, 0.27), 1.5)
			_poly([Vector2(-1, 1), Vector2(-1.5, 4), Vector2(1, 3.5), Vector2(1, 1)], Color(0.22, 0.22, 0.2))
		5: # shotgun
			_poly([Vector2(-2, -1.2), Vector2(2, -1.2), Vector2(2, 1), Vector2(-2, 1)], Color(0.3, 0.3, 0.32))
			_line(Vector2(2, 0), Vector2(7, 0), Color(0.25, 0.25, 0.27), 1.8)
			_line(Vector2(-2, 0.5), Vector2(-5, 1.5), Color(0.4, 0.25, 0.12), 2.0)
			_line(Vector2(4, 0.5), Vector2(5.5, 0.5), Color(0.35, 0.22, 0.1), 2.0)
		6: # smg
			_poly([Vector2(-3, -1.5), Vector2(4, -1.5), Vector2(4, 1.2), Vector2(-3, 1.2)], Color(0.32, 0.32, 0.36))
			_line(Vector2(4, 0), Vector2(6, 0), Color(0.25, 0.25, 0.28), 1.8)
			_poly([Vector2(0, 1.2), Vector2(0, 4), Vector2(1.5, 4), Vector2(1.5, 1.2)], Color(0.28, 0.28, 0.3))
		7: # suppressed pistol
			_poly([Vector2(-2, -1), Vector2(2, -1), Vector2(2, 0.8), Vector2(-2, 0.8)], Color(0.22, 0.22, 0.24))
			_line(Vector2(2, 0), Vector2(7, 0), Color(0.18, 0.18, 0.2), 2.0)
			_poly([Vector2(-1, 0.8), Vector2(-1.5, 3.5), Vector2(0.5, 3), Vector2(0.5, 0.8)], Color(0.2, 0.2, 0.18))
		_:
			_line(Vector2(0, -6), Vector2(0, 6), color, 2.0)
