extends Node2D
## Port of bomb.lua: AOE blast centred on the player. Instant (Lua has no throw/fuse), cannot pass
## through walls, kills lesser enemies, knocks the survivors back. Draws the Lua shockwave
## (ring + core + sparks) and adds a light flash, screen shake and particles.

const TILE := 52.0
const BLAST_TIME := 0.6   # Lua blastTimer

var count := 1                 # Bomb.count (start with 1)
var max_count := 4             # items.lua: max(2, 6 - difficultyIdx); integrator may change it
var base_radius := 3.0         # baseRadius (tiles)
var radius_mult := 1.0         # radiusMult (chaos orbs)
var damage := 50               # damage at the centre, falls off linearly
var knockback := 8.0           # knockback strength (tiles)
var cooldown := 0.0
var cooldown_time := 1.0
var blasting := false
var blast_timer := 0.0
var blast_radius := 0.0

var game
var _light: PointLight2D
var _rng := RandomNumberGenerator.new()


func setup(g, light_tex: Texture2D) -> void:
	game = g
	z_index = 5
	_rng.randomize()
	_light = PointLight2D.new()
	_light.texture = light_tex
	_light.color = Color(1.0, 0.65, 0.3)
	_light.energy = 0.0
	_light.shadow_enabled = false
	add_child(_light)


func get_radius() -> float:
	return base_radius * radius_mult


func can_use() -> bool:
	return count > 0 and cooldown <= 0.0


func reset() -> void:
	count = 1
	radius_mult = 1.0
	cooldown = 0.0
	blasting = false
	blast_timer = 0.0
	_light.energy = 0.0
	queue_redraw()


## Detonate at tile position `pos`. Returns {"hit": int, "killed": int}.
func use(pos: Vector2) -> Dictionary:
	var result := {"hit": 0, "killed": 0}
	if not can_use():
		return result
	count -= 1
	cooldown = cooldown_time
	blasting = true
	blast_timer = BLAST_TIME
	blast_radius = get_radius()
	position = pos * TILE
	var radius := blast_radius
	var center_px := pos * TILE

	var list: Array = []
	if game.enemies and game.enemies.has_method("get_enemies"):
		list = game.enemies.get_enemies().duplicate()
	for e in list:
		if not is_instance_valid(e):
			continue
		var d: Vector2 = e.tile_pos - pos
		var dist := d.length()
		if dist >= radius:
			continue
		if _blocked_by_wall(pos, e.tile_pos):
			continue
		var falloff := 1.0 - dist / radius
		var dmg := floorf(damage * falloff)
		result.hit += 1
		if dmg > 0.0:
			e.take_damage(dmg, Vector2.ZERO)
		var epx: Vector2 = e.tile_pos * TILE if is_instance_valid(e) else center_px
		var dir := d.normalized() if dist > 0.01 else Vector2.RIGHT
		game.fx.burst(epx, "hit", dir)
		game.fx.blood(epx, 1.0 + falloff)
		if not is_instance_valid(e) or e.hp <= 0.0:
			result.killed += 1
			game.fx.burst(epx, "gib", dir)
			game.fx.float_text(epx + Vector2(0, -34), str(int(dmg)), Color(1.0, 0.3, 0.1))
		else:
			game.fx.float_text(epx + Vector2(0, -34), str(int(dmg)), Color(1.0, 0.7, 0.2))
			if dist > 0.1:
				# Lua: immediate position offset kb*0.3 tiles, wall-checked per axis
				var kb := knockback * falloff * 0.3
				var nx: float = e.tile_pos.x + dir.x * kb
				var ny: float = e.tile_pos.y + dir.y * kb
				if not game.map.is_solid(nx, e.tile_pos.y):
					e.tile_pos.x = nx
				if not game.map.is_solid(e.tile_pos.x, ny):
					e.tile_pos.y = ny

	# juice
	game.fx.burst(center_px, "explosion", Vector2.ZERO)
	game.fx.burst(center_px, "smoke", Vector2.ZERO)
	game.fx.burst(center_px, "spark", Vector2.ZERO)
	game.fx.shake(26.0, 0.6)
	game.fx.flash(Color(1.0, 0.8, 0.5, 0.45), 0.25)
	game.hitstop(0.08)
	game.audio.play("Shotgun_sound", center_px, 1.0, 0.55)
	game.audio.play("gunshot", center_px, 1.0, 0.45)
	_light.energy = 2.2
	_light.texture_scale = maxf(0.1, radius * TILE * 2.4 / float(_light.texture.get_width()))
	queue_redraw()
	return result


func _blocked_by_wall(a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var dist := d.length()
	var steps := int(ceilf(dist * 3.0))
	if steps < 1:
		return false
	for i in range(1, steps + 1):
		var p := a + d * (float(i) / steps)
		if game.map.is_solid(p.x, p.y):
			return true
	return false


func update(dt: float) -> void:
	if cooldown > 0.0:
		cooldown -= dt
	if blasting:
		blast_timer -= dt
		var progress := 1.0 - clampf(blast_timer / BLAST_TIME, 0.0, 1.0)
		_light.energy = 2.2 * pow(1.0 - progress, 2.0)
		if blast_timer <= 0.0:
			blasting = false
			_light.energy = 0.0
		queue_redraw()


func _draw() -> void:
	if not blasting:
		return
	var max_r := blast_radius * TILE
	var progress := 1.0 - blast_timer / BLAST_TIME
	var wave_r := max_r * minf(1.0, progress * 1.5)
	var alpha := maxf(0.0, 1.0 - progress)
	draw_circle(Vector2.ZERO, wave_r, Color(1, 0.6, 0.2, alpha * 0.3))
	# inner heat gradient (juice): a few stacked discs
	for i in range(1, 4):
		draw_circle(Vector2.ZERO, wave_r * (1.0 - i * 0.2), Color(1, 0.55 + i * 0.1, 0.2, alpha * 0.12))
	var core_r := wave_r * 0.3 * (1.0 - progress)
	draw_circle(Vector2.ZERO, core_r, Color(1, 0.95, 0.8, alpha * 0.8))
	draw_arc(Vector2.ZERO, wave_r, 0.0, TAU, 64, Color(1, 0.5, 0.1, alpha * 0.7), 3.0)
	draw_arc(Vector2.ZERO, wave_r * 0.92, 0.0, TAU, 64, Color(1, 0.9, 0.6, alpha * 0.35), 1.5)
	if progress < 0.5:
		for i in range(1, 13):
			var sa := i * TAU / 12.0 + progress * 3.0
			var sr := wave_r * (0.5 + _rng.randf() * 0.5)
			draw_circle(Vector2(cos(sa), sin(sa)) * sr, 2.0, Color(1, 0.8, 0.3, alpha))
