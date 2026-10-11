class_name ExitPortal
extends Node2D
## Exit portal (drawPortal in main.lua): pulsing cyan/green rings, orbiting particles, label, strong light.

var tile_pos := Vector2.ZERO
var tile_px := 52.0
var t := 0.0
var guards_left := 0
var _light: PointLight2D
var _halo: Sprite2D
var _emb: CPUParticles2D


func setup(p_pos: Vector2, p_tile: float) -> void:
	tile_pos = p_pos
	tile_px = p_tile
	position = p_pos * p_tile
	_halo = Loot.make_halo(Color(0.1, 0.9, 0.6, 0.35), p_tile * 3.5)
	add_child(_halo)
	_light = Loot.make_light(Color(0.2, 1.0, 0.8), 7.0, 1.0)
	add_child(_light)
	_emb = CPUParticles2D.new()
	_emb.amount = 40
	_emb.lifetime = 1.8
	_emb.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_emb.emission_sphere_radius = p_tile * 1.2
	_emb.direction = Vector2(0, -1)
	_emb.spread = 40.0
	_emb.gravity = Vector2.ZERO
	_emb.initial_velocity_min = 10.0
	_emb.initial_velocity_max = 40.0
	_emb.scale_amount_min = 1.5
	_emb.scale_amount_max = 3.5
	_emb.color = Color(0.3, 1, 0.8, 0.8)
	_emb.material = Loot.additive_material()
	add_child(_emb)


func _process(delta: float) -> void:
	t += delta
	var pulse := sin(t * 3.0) * 0.15 + 0.85
	_halo.modulate.a = 0.3 * pulse
	_light.energy = 0.8 + 0.4 * pulse
	queue_redraw()


func _draw() -> void:
	var pulse := sin(t * 3.0) * 0.15 + 0.85
	var ts := tile_px
	draw_circle(Vector2.ZERO, ts * 2.0, Color(0.1, 0.8, 0.9, 0.3 * pulse))
	draw_circle(Vector2.ZERO, ts * 1.0, Color(0.2, 1, 0.7, 0.7 * pulse))
	draw_circle(Vector2.ZERO, ts * 0.45, Color(0.85, 1, 0.95, 0.9 * pulse))
	for i in 3:
		var a0 := t * (1.2 + i * 0.5) * (1.0 if i % 2 == 0 else -1.0) + i
		draw_arc(Vector2.ZERO, ts * (1.2 + i * 0.35), a0, a0 + 3.2, 24, Color(0.3, 1, 0.85, 0.55), 2.5)
	for i in 8:
		var angle := t * 2.0 + (i / 8.0) * TAU
		var dist := ts * (1.5 + sin(t * 4.0 + i) * 0.4)
		draw_circle(Vector2(cos(angle), sin(angle)) * dist, 3.5, Color(0.3, 1, 0.8, 0.7))
	var f := ThemeDB.fallback_font
	var txt := "%d HOSTILES REMAIN" % guards_left if guards_left > 0 else "EXIT PORTAL"
	var c := Color(1, 0.3, 0.2, pulse) if guards_left > 0 else Color(0.2, 1, 0.5, pulse)
	draw_string(f, Vector2(-100, -ts * 3.6), txt, HORIZONTAL_ALIGNMENT_CENTER, 200, 16, c)
