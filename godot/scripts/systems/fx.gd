extends Node
## Game-juice system (game.fx). Replaces NullFx and keeps every NullFx method.
##
##   shake(amount_px, duration)         trauma-style camera shake (applied to game.camera.offset)
##   hitstop(seconds)                   pass-through to game.hitstop
##   flash(color, seconds)              full-screen colour flash (color.a = peak alpha)
##   float_text(world_px, text, color, size_mult := 1.0)   pop + rise + fade text (Blackcraft)
##   burst(world_px, kind, dir)         kinds: hit spark smoke gib muzzle pickup levelup explosion
##   blood(world_px, size)              persistent blood decals (+ droplets); capped and fading
## Extras: kick(dir_px, amount), zoom_punch(amount), light_flash(world_px, color, radius_tiles, energy, dur),
##         scorch(world_px, size_tiles), streak_flourish(streak).
##
## Visual layers (all cheap, retained custom drawing, no per-particle nodes):
##   decals  : world child under entities, lit (blood/scorch persist on the floor)
##   lit fx  : world child above entities, lit (smoke, gibs, droplets)
##   glow fx : CanvasLayer(1, follows camera) additive sparks/flares/rings + floating text, never dimmed by darkness
##   flash   : CanvasLayer(4) full-screen colour overlay (below the post shader at layer 5)

const FONT := preload("res://assets/fonts/Blackcraft.ttf")
const STAINS := [
	preload("res://assets/third_party/screaming_brain_horror_textures/256x256/Stains/Horror_Stain_01-256x256.png"),
	preload("res://assets/third_party/screaming_brain_horror_textures/256x256/Stains/Horror_Stain_02-256x256.png"),
	preload("res://assets/third_party/screaming_brain_horror_textures/256x256/Stains/Horror_Stain_03-256x256.png"),
]

const MAX_DECALS := 160
const DECAL_FADE_AFTER := 45.0
const DECAL_FADE_TIME := 25.0
const MAX_FLOATS := 24
const MAX_LIGHT_FLASH := 4
const MAX_SHAKE_PX := 28.0
const STREAK_MILESTONES := [5, 10, 15, 20, 25, 30, 40, 50, 75, 100]

## Set to true to have fx add gib + blood on every enemy_killed (only if the enemy system does not).
var auto_kill_fx := false
## 0..1 accessibility multiplier for shake.
var shake_scale := 1.0

var game
var _lit_pool := ParticlePool.new(220)
var _glow_pool := ParticlePool.new(300)
var _decals: Array = []
var _floats: Array = []
var _flash_lights: Array = []

var _decal_node: FxCanvas
var _lit_node: FxCanvas
var _glow_node: FxCanvas
var _text_node: FxCanvas
var _flash_rect: ColorRect
var _flash_col := Color(0, 0, 0, 0)
var _flash_t := 0.0
var _flash_dur := 0.1

var _shake_amp := 0.0
var _shake_t := 0.0
var _shake_dur := 0.01
var _kick := Vector2.ZERO
var _zoom_kick := 0.0
var _base_zoom := Vector2.ONE
var _noise := FastNoiseLite.new()
var _time := 0.0
var _decals_dirty := true
var _fade_timer := 0.0
var _burn_tex: Texture2D


func setup(g) -> void:
	game = g
	_noise.seed = 4242
	_noise.frequency = 1.0
	_burn_tex = TexGen.radial(64, 1.2)
	if game.camera:
		_base_zoom = game.camera.zoom

	_decal_node = FxCanvas.new()
	_decal_node.name = "BloodDecals"
	_decal_node.draw_fn = _draw_decals
	_decal_node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	game.world.add_child(_decal_node)
	game.world.move_child(_decal_node, 0)

	_lit_node = FxCanvas.new()
	_lit_node.name = "FxLit"
	_lit_node.z_index = 40
	_lit_node.draw_fn = _draw_lit
	_lit_node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	game.world.add_child(_lit_node)

	var glow_layer := CanvasLayer.new()
	glow_layer.layer = 1
	glow_layer.follow_viewport_enabled = true
	add_child(glow_layer)
	_glow_node = FxCanvas.new()
	_glow_node.name = "FxGlow"
	_glow_node.draw_fn = _draw_glow
	_glow_node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_node.material = add_mat
	glow_layer.add_child(_glow_node)
	_text_node = FxCanvas.new()
	_text_node.name = "FloatText"
	_text_node.draw_fn = _draw_text
	_text_node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	glow_layer.add_child(_text_node)

	var flash_layer := CanvasLayer.new()
	flash_layer.layer = 4
	add_child(flash_layer)
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.color = Color(0, 0, 0, 0)
	flash_layer.add_child(_flash_rect)

	for i in MAX_LIGHT_FLASH:
		var l := PointLight2D.new()
		l.texture = TexGen.light_radial(128, 1.4)
		l.energy = 0.0
		l.visible = false
		l.shadow_enabled = false
		game.world.add_child(l)
		_flash_lights.append({"light": l, "t": 1.0, "dur": 0.1, "e0": 0.0})

	game.enemy_killed.connect(_on_enemy_killed)
	if game.player.has_signal("leveled_up"):
		game.player.leveled_up.connect(_on_level_up)


func reset_run() -> void:
	_lit_pool.clear()
	_glow_pool.clear()
	_decals.clear()
	_floats.clear()
	_decals_dirty = true
	_shake_amp = 0.0
	_kick = Vector2.ZERO
	_zoom_kick = 0.0
	_flash_col.a = 0.0
	for e in _flash_lights:
		e.t = 1.0
		e.light.visible = false


# ---- public API (NullFx-compatible) ----------------------------------------

func shake(amount: float, duration := 0.25) -> void:
	var cur := _shake_envelope() * _shake_amp
	_shake_amp = minf(MAX_SHAKE_PX, maxf(cur, amount) + minf(cur, amount) * 0.25)
	_shake_dur = maxf(duration, 0.05)
	_shake_t = _shake_dur


func hitstop(seconds: float) -> void:
	if game:
		game.hitstop(seconds)


func flash(color: Color, seconds := 0.15) -> void:
	if color.a > _flash_col.a * (_flash_t / _flash_dur if _flash_dur > 0.0 else 0.0) or _flash_t <= 0.0:
		_flash_col = color
		_flash_dur = maxf(seconds, 0.02)
		_flash_t = _flash_dur


func float_text(world_px: Vector2, text: String, color := Color.WHITE, size_mult := 1.0) -> void:
	# nudge away from a recent text at (almost) the same spot so stacked numbers stay readable
	var p := world_px + Vector2(randf_range(-8.0, 8.0), 0.0)
	for f in _floats:
		if f.t < 0.25 and absf(f.pos.y - p.y) < 18.0 and absf(f.pos.x - p.x) < 60.0:
			p.y -= 20.0
	if _floats.size() >= MAX_FLOATS:
		_floats.pop_front()
	var size := int(round(24.0 * size_mult))
	_floats.append({"pos": p, "text": text, "col": color, "t": 0.0, "life": 1.0 + 0.25 * size_mult,
		"size": size, "w": FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x})


func burst(world_px: Vector2, kind: String, dir := Vector2.ZERO) -> void:
	match kind:
		"hit": _burst_hit(world_px, dir)
		"spark": _burst_spark(world_px, dir)
		"smoke": _burst_smoke(world_px, dir, 5, 1.0)
		"gib": _burst_gib(world_px, dir)
		"muzzle": _burst_muzzle(world_px, dir)
		"pickup": _burst_pickup(world_px)
		"levelup": _burst_levelup(world_px)
		"explosion": _burst_explosion(world_px)


func blood(world_px: Vector2, size := 1.0) -> void:
	var n := clampi(1 + int(size * 1.6), 1, 4)
	for i in n:
		var off := Vector2.from_angle(randf() * TAU) * randf_range(0.0, 16.0 + 14.0 * size)
		_add_decal({"kind": "stain", "pos": world_px + off, "rot": randf() * TAU,
			"sz": TILE_PX() * randf_range(0.45, 0.85) * (0.6 + 0.5 * size), "tex": randi() % STAINS.size(),
			"col": Color(randf_range(0.7, 1.0), randf_range(0.6, 0.9), randf_range(0.6, 0.9), randf_range(0.55, 0.85)),
			"born": _time, "flip": randf() < 0.5})
	for i in 3 + int(size * 4):   # fine spray
		var o := Vector2.from_angle(randf() * TAU) * randf_range(10.0, 40.0 + 30.0 * size)
		_add_decal({"kind": "drop", "pos": world_px + o, "r": randf_range(1.2, 3.5), "col": Color(0.45, 0.02, 0.02, 0.8), "born": _time})
	# droplets flying out
	for i in 3 + int(size * 3):
		_lit_pool.emit(world_px, Vector2.from_angle(randf() * TAU) * randf_range(60.0, 220.0), randf_range(0.25, 0.5),
			randf_range(2.0, 4.0), 1.5, Color(0.5, 0.03, 0.03, 1.0), Color(0.3, 0.0, 0.0, 0.0), ParticlePool.SQUARE, 4.0)


## Directional camera nudge in screen px (weapon recoil, hits). Decays quickly.
func kick(dir: Vector2, amount := 4.0) -> void:
	_kick += dir.normalized() * amount * shake_scale
	_kick = _kick.limit_length(MAX_SHAKE_PX)


## Brief camera zoom punch (0.03 = 3% zoom in).
func zoom_punch(amount := 0.03) -> void:
	_zoom_kick = maxf(_zoom_kick, amount)


## Short-lived additive point light (muzzle flash, explosion glow).
func light_flash(world_px: Vector2, color: Color, radius_tiles := 4.0, energy := 1.0, dur := 0.12) -> void:
	var pick: Dictionary = _flash_lights[0]
	for e in _flash_lights:
		if e.t >= 1.0:
			pick = e
			break
		if e.t > pick.t:
			pick = e
	var l: PointLight2D = pick.light
	l.position = world_px
	l.color = color
	l.texture_scale = radius_tiles * TILE_PX() / 64.0
	l.visible = true
	pick.t = 0.0
	pick.dur = dur
	pick.e0 = energy
	l.energy = energy


func scorch(world_px: Vector2, size_tiles := 2.0) -> void:
	_add_decal({"kind": "burn", "pos": world_px, "sz": size_tiles * TILE_PX(), "col": Color(0, 0, 0, 0.6), "born": _time})


func streak_flourish(streak: int) -> void:
	var p = game.player
	var col := Color(1.0, 0.85, 0.25)
	if streak >= 20: col = Color(1.0, 0.45, 0.15)
	if streak >= 50: col = Color(1.0, 0.2, 0.2)
	float_text(p.position + Vector2(0, -90), "%d KILL STREAK!" % streak, col, 1.0 + minf(0.6, streak / 60.0))
	flash(Color(col.r, col.g, col.b, 0.14), 0.18)
	zoom_punch(0.025 + minf(0.03, streak / 100.0))
	shake(5.0 + minf(6.0, streak / 8.0), 0.25)
	burst(p.position, "pickup")
	if streak >= 10:
		burst(p.position, "levelup")


# ---- signal hooks -----------------------------------------------------------

func _on_enemy_killed(tile_pos: Vector2, _kind: String, _xp: int) -> void:
	var px := tile_pos * TILE_PX()
	if auto_kill_fx:
		burst(px, "gib")
	var s: int = game.player.current_streak
	if s in STREAK_MILESTONES:
		streak_flourish(s)


func _on_level_up(_level: int) -> void:
	var p = game.player
	burst(p.position, "levelup")
	flash(Color(1.0, 0.85, 0.3, 0.30), 0.35)
	zoom_punch(0.05)
	shake(6.0, 0.3)


# ---- bursts -----------------------------------------------------------------

func TILE_PX() -> float:
	return float(game.TILE)


func _dirv(dir: Vector2, spread: float) -> Vector2:
	if dir == Vector2.ZERO:
		return Vector2.from_angle(randf() * TAU)
	return dir.normalized().rotated(randf_range(-spread, spread))


func _burst_hit(p: Vector2, dir: Vector2) -> void:
	for i in 5:
		var d := _dirv(dir, 0.9)
		_glow_pool.emit(p, d * randf_range(260.0, 480.0), randf_range(0.14, 0.26), 2.0, 1.0,
			Color(1.0, 0.85, 0.6, 1.0), Color(1.0, 0.2, 0.05, 0.0), ParticlePool.STREAK, 4.0)
	for i in 5:
		var d2 := _dirv(dir, 0.8)
		_lit_pool.emit(p, d2 * randf_range(120.0, 320.0), randf_range(0.3, 0.6), randf_range(2.5, 4.5), 1.5,
			Color(0.55, 0.03, 0.03, 1.0), Color(0.3, 0.0, 0.0, 0.0), ParticlePool.SQUARE, 3.5)
	_glow_pool.emit(p, Vector2.ZERO, 0.09, 16.0, 3.0, Color(1.0, 0.9, 0.75, 0.9), Color(1, 0.4, 0.2, 0.0))


func _burst_spark(p: Vector2, dir: Vector2) -> void:
	for i in 8:
		var d := _dirv(dir, 1.0)
		_glow_pool.emit(p, d * randf_range(200.0, 520.0), randf_range(0.15, 0.35), 2.0, 1.0,
			Color(1.0, 0.95, 0.6, 1.0), Color(1.0, 0.5, 0.1, 0.0), ParticlePool.STREAK, 3.5)
	_glow_pool.emit(p, Vector2.ZERO, 0.08, 12.0, 2.0, Color(1.0, 0.95, 0.7, 0.8), Color(1, 0.6, 0.2, 0.0))


func _burst_smoke(p: Vector2, dir: Vector2, n: int, scale: float) -> void:
	for i in n:
		var d := _dirv(dir, 1.2)
		_lit_pool.emit(p + Vector2.from_angle(randf() * TAU) * randf_range(0, 6 * scale), d * randf_range(15.0, 70.0) * scale,
			randf_range(0.8, 1.4) * scale, randf_range(8.0, 14.0) * scale, randf_range(30.0, 50.0) * scale,
			Color(0.55, 0.55, 0.52, 0.32), Color(0.3, 0.3, 0.3, 0.0), ParticlePool.DOT, 1.8)


func _burst_gib(p: Vector2, dir: Vector2) -> void:
	for i in 12:
		var d := _dirv(dir, 1.6)
		var col := Color(randf_range(0.35, 0.6), randf_range(0.02, 0.08), randf_range(0.02, 0.06), 1.0)
		_lit_pool.emit(p, d * randf_range(100.0, 440.0), randf_range(0.45, 0.9), randf_range(3.0, 7.0), randf_range(2.0, 4.0),
			col, Color(col.r * 0.6, 0.0, 0.0, 0.0), ParticlePool.SQUARE, 3.2)
	blood(p, 1.4)
	_glow_pool.emit(p, Vector2.ZERO, 0.1, 18.0, 4.0, Color(1.0, 0.4, 0.3, 0.5), Color(1, 0.1, 0.1, 0.0))


func _burst_muzzle(p: Vector2, dir: Vector2) -> void:
	_glow_pool.emit(p, Vector2.ZERO, 0.07, 24.0, 5.0, Color(1.0, 0.92, 0.6, 1.0), Color(1.0, 0.5, 0.15, 0.0))
	for i in 4:
		var d := _dirv(dir, 0.28)
		_glow_pool.emit(p, d * randf_range(500.0, 850.0), randf_range(0.07, 0.14), 2.0, 1.0,
			Color(1.0, 0.95, 0.7, 1.0), Color(1.0, 0.5, 0.1, 0.0), ParticlePool.STREAK, 2.0)
	_lit_pool.emit(p, _dirv(dir, 0.5) * 30.0, 0.6, 5.0, 16.0, Color(0.6, 0.6, 0.58, 0.18), Color(0.4, 0.4, 0.4, 0.0), ParticlePool.DOT, 2.0)
	light_flash(p, Color(1.0, 0.85, 0.5), 3.5, 0.8, 0.07)


func _burst_pickup(p: Vector2) -> void:
	for i in 10:
		var d := Vector2.from_angle(randf() * TAU)
		_glow_pool.emit(p + d * 6.0, d * randf_range(30.0, 90.0), randf_range(0.5, 0.85), randf_range(5.0, 8.0), 1.0,
			Color(1.0, 0.95, 0.55, 0.9), Color(0.5, 1.0, 0.7, 0.0), ParticlePool.DOT, 2.0, Vector2(0, -60))
	_glow_pool.emit(p, Vector2.ZERO, 0.35, 6.0, 32.0, Color(1.0, 0.9, 0.4, 0.7), Color(1.0, 0.8, 0.2, 0.0), ParticlePool.RING)


func _burst_levelup(p: Vector2) -> void:
	for i in 30:
		var d := Vector2.from_angle(randf() * TAU)
		_glow_pool.emit(p, d * randf_range(180.0, 520.0), randf_range(0.6, 1.1), 2.5, 1.0,
			Color(1.0, 0.88, 0.35, 1.0), Color(1.0, 0.55, 0.1, 0.0), ParticlePool.STREAK, 2.4)
	_glow_pool.emit(p, Vector2.ZERO, 0.5, 10.0, 130.0, Color(1.0, 0.9, 0.4, 0.9), Color(1.0, 0.7, 0.2, 0.0), ParticlePool.RING)
	_glow_pool.emit(p, Vector2.ZERO, 0.8, 10.0, 200.0, Color(1.0, 0.95, 0.6, 0.6), Color(1.0, 0.8, 0.3, 0.0), ParticlePool.RING)
	light_flash(p, Color(1.0, 0.85, 0.4), 7.0, 1.3, 0.5)


func _burst_explosion(p: Vector2) -> void:
	light_flash(p, Color(1.0, 0.65, 0.3), 9.0, 2.0, 0.35)
	for i in 22:
		var d := Vector2.from_angle(randf() * TAU)
		_glow_pool.emit(p + d * 8.0, d * randf_range(80.0, 420.0), randf_range(0.3, 0.65), randf_range(14.0, 22.0), 4.0,
			Color(1.0, randf_range(0.5, 0.85), 0.2, 0.85), Color(0.7, 0.1, 0.0, 0.0), ParticlePool.DOT, 3.2)
	for i in 14:
		var d2 := Vector2.from_angle(randf() * TAU)
		_glow_pool.emit(p, d2 * randf_range(300.0, 800.0), randf_range(0.3, 0.6), 2.5, 1.0,
			Color(1.0, 0.9, 0.55, 1.0), Color(1.0, 0.4, 0.1, 0.0), ParticlePool.STREAK, 2.5)
	_glow_pool.emit(p, Vector2.ZERO, 0.35, 10.0, 170.0, Color(1.0, 0.8, 0.5, 0.9), Color(1.0, 0.4, 0.1, 0.0), ParticlePool.RING)
	_burst_smoke(p, Vector2.ZERO, 10, 1.8)
	scorch(p, 2.4)
	shake(14.0, 0.45)
	hitstop(0.05)
	flash(Color(1.0, 0.8, 0.5, 0.32), 0.18)
	if game.lighting and game.lighting.post:
		game.lighting.post.aberrate(0.9)


# ---- decals -----------------------------------------------------------------

func _add_decal(d: Dictionary) -> void:
	var tp: Vector2 = d.pos / TILE_PX()
	if game.map.is_solid(tp.x, tp.y):
		return          # never paint walls
	_decals.append(d)
	while _decals.size() > MAX_DECALS:
		_decals.pop_front()
	_decals_dirty = true


func _decal_alpha(d: Dictionary) -> float:
	var age: float = _time - d.born
	if age < DECAL_FADE_AFTER:
		return 1.0
	return clampf(1.0 - (age - DECAL_FADE_AFTER) / DECAL_FADE_TIME, 0.0, 1.0) * 0.8 + 0.2 * 0.0


func _draw_decals(ci: CanvasItem) -> void:
	for d in _decals:
		var a := _decal_alpha(d)
		if a <= 0.0:
			continue
		match d.kind:
			"stain":
				var sz: float = d.sz
				ci.draw_set_transform(d.pos, d.rot, Vector2(-1.0 if d.flip else 1.0, 1.0))
				var c: Color = d.col
				ci.draw_texture_rect(STAINS[d.tex], Rect2(-sz * 0.5, -sz * 0.5, sz, sz), false, Color(c.r, c.g, c.b, c.a * a))
			"burn":
				var sz2: float = d.sz
				ci.draw_set_transform(d.pos, 0.0, Vector2.ONE)
				var c2: Color = d.col
				ci.draw_texture_rect(_burn_tex, Rect2(-sz2 * 0.5, -sz2 * 0.5, sz2, sz2), false, Color(c2.r, c2.g, c2.b, c2.a * a))
			"drop":
				ci.draw_set_transform(d.pos, 0.0, Vector2.ONE)
				var c3: Color = d.col
				ci.draw_circle(Vector2.ZERO, d.r, Color(c3.r, c3.g, c3.b, c3.a * a))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---- drawing ----------------------------------------------------------------

func _draw_lit(ci: CanvasItem) -> void:
	_lit_pool.draw(ci)


func _draw_glow(ci: CanvasItem) -> void:
	_glow_pool.draw(ci)


func _draw_text(ci: CanvasItem) -> void:
	for f in _floats:
		var t: float = f.t
		var life: float = f.life
		var u := t / life
		var pop := 1.0
		if t < 0.18:
			pop = lerpf(0.3, 1.35, t / 0.18)
		elif t < 0.3:
			pop = lerpf(1.35, 1.0, (t - 0.18) / 0.12)
		var rise := (1.0 - pow(1.0 - u, 2.0)) * 48.0
		var alpha := 1.0 if u < 0.6 else clampf(1.0 - (u - 0.6) / 0.4, 0.0, 1.0)
		var col: Color = f.col
		var pos: Vector2 = f.pos + Vector2(0, -rise)
		ci.draw_set_transform(pos, 0.0, Vector2(pop, pop))
		var off := Vector2(-f.w * 0.5, f.size * 0.35)
		ci.draw_string_outline(FONT, off, f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, f.size, 6, Color(0, 0, 0, alpha * 0.9))
		ci.draw_string(FONT, off, f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, f.size, Color(col.r, col.g, col.b, col.a * alpha))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---- per-frame update (real time: shake and particles keep going during hitstop) ----

func _shake_envelope() -> float:
	if _shake_t <= 0.0:
		return 0.0
	var u := _shake_t / _shake_dur
	return u * u


func _process(delta: float) -> void:
	if game == null:
		return
	var dt := delta
	if game.state == "paused" or game.state == "perk":
		dt = 0.0
	_time += dt

	var had_fx := _lit_pool.count + _glow_pool.count + _floats.size()
	_lit_pool.update(dt)
	_glow_pool.update(dt)
	for f in _floats:
		f.t += dt
	while not _floats.is_empty() and _floats[0].t >= _floats[0].life:
		_floats.pop_front()
	# also drop any expired text that is not first
	for i in range(_floats.size() - 1, -1, -1):
		if _floats[i].t >= _floats[i].life:
			_floats.remove_at(i)
	if had_fx > 0 or _lit_pool.count + _glow_pool.count + _floats.size() > 0:
		_lit_node.queue_redraw()
		_glow_node.queue_redraw()
		_text_node.queue_redraw()

	# decals: redraw when changed, and slowly while fading
	_fade_timer -= dt
	if _fade_timer <= 0.0:
		_fade_timer = 0.5
		if not _decals.is_empty() and _time - _decals[0].born > DECAL_FADE_AFTER:
			_decals_dirty = true
			while not _decals.is_empty() and _decal_alpha(_decals[0]) <= 0.0:
				_decals.pop_front()
	if _decals_dirty:
		_decals_dirty = false
		_decal_node.queue_redraw()

	# flash overlay
	if _flash_t > 0.0:
		_flash_t -= delta
		var u := clampf(_flash_t / _flash_dur, 0.0, 1.0)
		_flash_rect.color = Color(_flash_col.r, _flash_col.g, _flash_col.b, _flash_col.a * u * u)
	elif _flash_rect.color.a != 0.0:
		_flash_rect.color = Color(0, 0, 0, 0)

	# light flashes
	for e in _flash_lights:
		if e.t < 1.0:
			e.t += delta / e.dur
			var l: PointLight2D = e.light
			if e.t >= 1.0:
				l.visible = false
				l.energy = 0.0
			else:
				l.energy = e.e0 * (1.0 - e.t) * (1.0 - e.t)

	# camera: shake + kick + zoom punch
	if game.camera:
		var off := Vector2.ZERO
		if _shake_t > 0.0:
			_shake_t -= delta
			var env := _shake_envelope()
			var t := _time * 60.0
			off = Vector2(_noise.get_noise_1d(t), _noise.get_noise_1d(t + 1000.0)) * _shake_amp * env * 1.6 * shake_scale
			if _shake_t <= 0.0:
				_shake_amp = 0.0
		_kick = _kick.lerp(Vector2.ZERO, minf(1.0, 14.0 * delta))
		game.camera.offset = (off + _kick).limit_length(MAX_SHAKE_PX * 1.5)
		_zoom_kick = lerpf(_zoom_kick, 0.0, minf(1.0, 9.0 * delta))
		game.camera.zoom = _base_zoom * (1.0 + _zoom_kick)
