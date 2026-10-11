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
## Juice pass: gunshot(muzzle_px, dir, weapon), swing(origin_px, angle, reach_px, weapon), melee_hit(px, dir, weapon, killed),
##         wall_hit(px, dir), flesh_hit(px, dir), death_fx(px, kind, dir, big), note_attacker(px), attack_warning(px, windup, big),
##         near_miss(px), slowmo(scale, real_secs), trail(px, color), casing_land(px, color), float_text(..., style).
## Options (read defensively from game.ui.options every 0.5 s): screen_shake 0..1, reduce_flashing bool.
## Budgets: every effect has a hard cap (pools / arrays below) and `_n()` scales emission counts by an
## adaptive quality budget (drops to 0.6 / 0.35 when the frame time climbs; `adaptive = false` pins it).
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

const MAX_DECALS := 200
const MAX_MARKS := 48
const MAX_IND := 5
const MAX_WARN := 6
const MAX_SLASH := 8
const MAX_FIRES := 6
const MAX_FIGS := 2
const MAX_MOTES := 44
const MAX_PILLARS := 3
const LOOK_MAX_PX := 70.0
const LOOK_K := 0.16
# per-enemy-kind gore palette: gib colours, puddle tint, whether the stain texture is greyscaled for tinting
const PAL := {
	"hound": {"a": Color(0.55, 0.04, 0.04), "b": Color(0.35, 0.02, 0.02), "puddle": Color(1.0, 0.85, 0.85, 0.8), "grey": false},
	"crawler": {"a": Color(0.25, 0.62, 0.1), "b": Color(0.12, 0.35, 0.06), "puddle": Color(0.5, 1.2, 0.3, 0.8), "grey": true},
	"wretch": {"a": Color(0.82, 0.7, 0.12), "b": Color(0.5, 0.38, 0.05), "puddle": Color(1.25, 1.0, 0.25, 0.8), "grey": true},
	"shade": {"a": Color(0.32, 0.12, 0.5), "b": Color(0.14, 0.04, 0.25), "puddle": Color(0.7, 0.3, 1.2, 0.85), "grey": true},
	"skin stealer": {"a": Color(0.78, 0.28, 0.1), "b": Color(0.45, 0.1, 0.05), "puddle": Color(1.3, 0.55, 0.25, 0.85), "grey": true},
}
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

## Auto-lower emission counts when frames get slow (set false for deterministic tests).
var adaptive := true
## 0..1 from options.reduce_flashing: damps flashes / flicker / slow-mo.
var calm := false

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
var _grey_stains: Array = []
var _mote_tex: Texture2D
var _grad_tex: Texture2D

# juice-pass state (all arrays are hard-capped, see MAX_*)
var _budget := 1.0
var _ft_ema := 0.016
var _budget_t := 1.0
var _opt_t := 0.0
var _last_us := 0
var _marks: Array = []          # wall impact marks {pos, t, col, r}
var _inds: Array = []           # directional damage indicators {ang, t, dur, col}
var _warns: Array = []          # melee wind-up warnings {pos, t, dur, big}
var _slashes: Array = []        # slash / cone / ring flashes {k, pos, ang, len, w, t, dur, col}
var _fires: Array = []          # lingering fire patches {pos, t, dur, r, acc}
var _figs: Array = []           # low-sanity shadow figures {pos, t, life, vanish, sw}
var _pillars: Array = []        # level-up light pillars {pos, t, dur}
var _motes_pos := PackedVector2Array()
var _motes_vel := PackedVector2Array()
var _motes_t := PackedFloat32Array()
var _motes_life := PackedFloat32Array()
var _mote_acc := 0.0
var _attacker := Vector2.ZERO
var _attacker_t := -9.0
var _combo := {"n": 0, "t": 0.0, "pop": 0.0}
var _look := Vector2.ZERO
var _zoom_dyn := 0.0
var _applied_zoom := Vector2.ONE
var _slow_t := 0.0
var _slow_dur := 0.2
var _slow_min := 0.4
var _slow_cool := 0.0
var _fig_t := 8.0
var _flick_t := 6.0
var _flick_v := 0.0
var _flick_dur := 0.1
var _flick_age := 9.0
var _blood_feet := 0
var _foot_side := 1.0
var _last_blood_t := -9.0
var _last_blood_pos := Vector2.ZERO
var _last_gib_t := -9.0
var _last_gib_pos := Vector2.ZERO
var _last_expl_t := -9.0
var _trail_n := 0
var _decal_anim := 0.0
var _hud_node: FxCanvas
var _fig_node: FxCanvas


func setup(g) -> void:
	game = g
	_noise.seed = 4242
	_noise.frequency = 1.0
	_burn_tex = TexGen.radial(64, 1.2)
	_mote_tex = TexGen.radial(16, 1.3)
	for st in STAINS:      # luminance+alpha copies so a gore colour can tint them (native conversion, no per-pixel script)
		var im: Image = (st as Texture2D).get_image()
		im.convert(Image.FORMAT_LA8)
		_grey_stains.append(ImageTexture.create_from_image(im))
	_motes_pos.resize(MAX_MOTES); _motes_vel.resize(MAX_MOTES); _motes_t.resize(MAX_MOTES); _motes_life.resize(MAX_MOTES)
	for i in MAX_MOTES:
		_motes_life[i] = 0.0
		_motes_t[i] = 1.0
	_last_us = Time.get_ticks_usec()
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
	_fig_node = FxCanvas.new()
	_fig_node.name = "ShadowFigures"
	_fig_node.draw_fn = _draw_figs
	glow_layer.add_child(_fig_node)
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
	_hud_node = FxCanvas.new()
	_hud_node.name = "EdgeIndicators"
	_hud_node.draw_fn = _draw_hud
	flash_layer.add_child(_hud_node)

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
	if game.player.has_signal("damaged"):
		game.player.damaged.connect(_on_player_damaged)
	if game.player.has_signal("footstep"):
		game.player.footstep.connect(_on_footstep)


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
	_marks.clear(); _inds.clear(); _warns.clear(); _slashes.clear(); _fires.clear(); _figs.clear(); _pillars.clear()
	for i in MAX_MOTES:
		_motes_life[i] = 0.0
	_combo = {"n": 0, "t": 0.0, "pop": 0.0}
	_look = Vector2.ZERO
	_zoom_dyn = 0.0
	_slow_t = 0.0
	_slow_cool = 0.0
	_blood_feet = 0
	_fig_t = 10.0
	_flick_v = 0.0
	Engine.time_scale = 1.0
	if game and game.lighting and game.lighting.post:
		game.lighting.post.set_slowmo(0.0)
		game.lighting.post.set_flicker(0.0)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


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
	if calm:
		color.a *= 0.35
	if color.a > _flash_col.a * (_flash_t / _flash_dur if _flash_dur > 0.0 else 0.0) or _flash_t <= 0.0:
		_flash_col = color
		_flash_dur = maxf(seconds, 0.02)
		_flash_t = _flash_dur


func float_text(world_px: Vector2, text: String, color := Color.WHITE, size_mult := 1.0, style := "") -> void:
	# damage numbers scale with the hit; big hits get the shaking "crit" treatment
	if style == "" and text.is_valid_int():
		var v := absi(int(text))
		size_mult *= clampf(0.85 + v / 45.0, 0.85, 1.6)
		if v >= 25:
			style = "crit"
	# nudge away from a recent text at (almost) the same spot so stacked numbers stay readable
	var p := world_px + Vector2(randf_range(-8.0, 8.0), 0.0)
	for f in _floats:
		if f.t < 0.25 and absf(f.pos.y - p.y) < 18.0 and absf(f.pos.x - p.x) < 60.0:
			p.y -= 20.0
	if _floats.size() >= MAX_FLOATS:
		_floats.pop_front()
	var size := int(round(24.0 * size_mult))
	var life := 1.0 + 0.25 * size_mult
	var rise := 48.0
	var wob := 0.0
	var pop := 1.35
	match style:
		"crit":
			pop = 1.75; rise = 62.0
		"heal":
			rise = 40.0; wob = 6.0; life += 0.3
		"info":
			rise = 30.0; life += 0.4
		"small":
			rise = 34.0; life = 0.8
	_floats.append({"pos": p, "text": text, "col": color, "t": 0.0, "life": life, "size": size,
		"w": FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x,
		"style": style, "rise": rise, "wob": wob, "pop": pop, "ph": randf() * TAU})


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


func blood(world_px: Vector2, size := 1.0, tint := Color(-1, 0, 0, 0), grey := false) -> void:
	# one hit often calls blood() from several places (enemy, weapon, bomb): merge near-simultaneous calls
	if tint.r < 0.0 and _time - _last_blood_t < 0.05 and world_px.distance_squared_to(_last_blood_pos) < 1600.0:
		return
	_last_blood_t = _time
	_last_blood_pos = world_px
	var n := clampi(1 + int(size * 1.6 * _budget), 1, 4)
	for i in n:
		var off := Vector2.from_angle(randf() * TAU) * randf_range(0.0, 16.0 + 14.0 * size)
		var dcol := Color(randf_range(0.7, 1.0), randf_range(0.6, 0.9), randf_range(0.6, 0.9), randf_range(0.55, 0.85))
		if tint.r >= 0.0:
			dcol = Color(tint.r * randf_range(0.85, 1.0), tint.g * randf_range(0.85, 1.0), tint.b * randf_range(0.85, 1.0), tint.a * randf_range(0.7, 1.0))
		_add_decal({"kind": "stain", "pos": world_px + off, "rot": randf() * TAU,
			"sz": TILE_PX() * randf_range(0.45, 0.85) * (0.6 + 0.5 * size), "tex": randi() % STAINS.size(),
			"col": dcol, "grey": grey, "born": _time, "flip": randf() < 0.5})
	for i in _n(3 + int(size * 4)):   # fine spray
		var o := Vector2.from_angle(randf() * TAU) * randf_range(10.0, 40.0 + 30.0 * size)
		_add_decal({"kind": "drop", "pos": world_px + o, "r": randf_range(1.2, 3.5), "col": Color(0.45, 0.02, 0.02, 0.8) if tint.r < 0.0 else Color(tint.r * 0.5, tint.g * 0.5, tint.b * 0.5, 0.85), "born": _time})
	# droplets flying out
	for i in _n(3 + int(size * 3)):
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
	var p: Player = game.player
	var col := Color(1.0, 0.85, 0.25)
	if streak >= 20: col = Color(1.0, 0.45, 0.15)
	if streak >= 50: col = Color(1.0, 0.2, 0.2)
	float_text(p.position + Vector2(0, -90), "%d KILL STREAK!" % streak, col, 1.0 + minf(0.6, streak / 60.0))
	flash(Color(col.r, col.g, col.b, 0.14), 0.18)
	zoom_punch(0.025 + minf(0.03, streak / 100.0))
	shake(5.0 + minf(6.0, streak / 8.0), 0.25)
	burst(p.position, "pickup")
	_glow_pool.emit(p.position, Vector2.ZERO, 0.45, 10.0, 110.0 + minf(streak, 50) * 2.0, Color(col.r, col.g, col.b, 0.8), Color(col.r, col.g, col.b, 0.0), ParticlePool.RING)
	_snd("fx_streak", null, 0.5, 1.0 + minf(0.5, streak / 100.0))
	if streak >= 10:
		burst(p.position, "levelup")
		_pillar(p.position)


# ---- juice-pass API ---------------------------------------------------------

## Scale an emission count by the adaptive quality budget (always at least 1).
func _n(count: int) -> int:
	return maxi(1, int(ceilf(count * _budget)))


func _snd(sound: String, world_px, vol := 0.5, pitch := 1.0) -> void:
	if game.audio:
		game.audio.play(sound, world_px, vol, pitch)


## Slow the whole game for `real_secs` of wall-clock time (near-miss beat). Auto-restores.
func slowmo(scale := 0.35, real_secs := 0.2) -> void:
	if game.state != "playing":
		return
	if calm:
		scale = lerpf(scale, 1.0, 0.5)
		real_secs *= 0.7
	_slow_min = minf(scale, _slow_min if _slow_t > 0.0 else 1.0)
	_slow_dur = maxf(real_secs, 0.05)
	_slow_t = _slow_dur


## Muzzle flash + per-weapon blast shape (called by the weapon system on every shot).
func gunshot(muzzle_px: Vector2, dir: Vector2, weapon: String) -> void:
	_burst_muzzle(muzzle_px, dir)
	match weapon:
		"shotgun":
			_cone_blast(muzzle_px, dir, 0.3, 12)
			kick(-dir, 10.0)
			zoom_punch(0.018)
			_snd("fx_boom", null, 0.28, 1.5)
		"smg":
			kick(-dir, 1.8)
			_glow_pool.emit(muzzle_px, dir * 90.0, 0.06, 7.0, 1.0, Color(1.0, 0.9, 0.55, 0.8), Color(1, 0.5, 0.1, 0.0))
		"suppressed pistol":
			kick(-dir, 1.5)
		_:
			kick(-dir, 4.5)
			_snd("fx_ping", muzzle_px, 0.12, 0.6)


func _cone_blast(p: Vector2, dir: Vector2, half: float, n: int) -> void:
	for i in _n(n):
		var d := dir.rotated(randf_range(-half, half))
		_glow_pool.emit(p, d * randf_range(380.0, 900.0), randf_range(0.08, 0.2), 2.5, 1.0,
			Color(1.0, 0.85, 0.5, 0.9), Color(1.0, 0.35, 0.05, 0.0), ParticlePool.STREAK, 2.5)
	for i in _n(4):
		_lit_pool.emit(p + dir * 10.0, dir.rotated(randf_range(-half, half)) * randf_range(60.0, 190.0), randf_range(0.5, 0.9),
			randf_range(6.0, 11.0), randf_range(24.0, 34.0), Color(0.62, 0.6, 0.56, 0.3), Color(0.35, 0.35, 0.35, 0.0), ParticlePool.DOT, 3.0)
	_add_slash({"k": "cone", "pos": p, "ang": dir.angle(), "len": 150.0, "w": half, "t": 0.0, "dur": 0.09, "col": Color(1.0, 0.8, 0.4, 0.5)})


## Melee swing crescent (additive, sweeps once). Pairs with the weapon sprite's own swoosh.
func swing(origin_px: Vector2, angle: float, reach_px: float, weapon: String) -> void:
	var col := Color(1.0, 1.0, 1.0, 0.55)
	var w := 14.0
	var dur := 0.16
	match weapon:
		"knife":
			col = Color(0.85, 0.95, 1.0, 0.5); w = 8.0; dur = 0.11
		"pipe":
			col = Color(0.8, 0.85, 1.0, 0.45); w = 16.0; dur = 0.17
		"axe":
			col = Color(1.0, 0.7, 0.5, 0.6); w = 22.0; dur = 0.2
	_add_slash({"k": "arc", "pos": origin_px, "ang": angle, "len": reach_px, "w": w, "t": 0.0, "dur": dur, "col": col})
	_snd("fx_slash", origin_px, 0.32, 1.0 if weapon != "axe" else 0.75)


## Melee connect: impact frame (white slash across the target), weapon-flavoured burst + layered sound.
func melee_hit(px: Vector2, dir: Vector2, weapon: String, killed: bool) -> void:
	var ang := dir.angle() + randf_range(-0.5, 0.5) + PI * 0.5
	var heavy := weapon == "axe" or weapon == "pipe"
	_add_slash({"k": "line", "pos": px, "ang": ang, "len": 120.0 if weapon == "axe" else (46.0 if weapon == "knife" else 84.0),
		"w": 5.0 if not heavy else 9.0, "t": 0.0, "dur": 0.12, "col": Color(1.0, 0.95, 0.9, 1.0)})
	if weapon == "knife":
		_add_slash({"k": "line", "pos": px, "ang": ang + 0.5, "len": 40.0, "w": 3.0, "t": 0.0, "dur": 0.1, "col": Color(1, 0.9, 0.9, 0.8)})
	if heavy:
		_glow_pool.emit(px, Vector2.ZERO, 0.22, 8.0, 70.0 if weapon == "axe" else 52.0, Color(1.0, 0.85, 0.7, 0.8), Color(1.0, 0.3, 0.1, 0.0), ParticlePool.RING)
		zoom_punch(0.02 if not killed else 0.035)
		kick(dir, 6.0)
		_snd("fx_bone", px, 0.55, 1.0)
	else:
		kick(dir, 3.0)
		_snd("fx_thud", px, 0.5, randf_range(0.9, 1.15))
	_snd("fx_wet", px, 0.3, randf_range(0.9, 1.2))
	if killed:
		_snd("fx_crunch", px, 0.5, randf_range(0.85, 1.1))
		flash(Color(1, 1, 1, 0.1 if heavy else 0.06), 0.06)


## Bullet found flesh: soft wet layer under the regular hit burst.
func flesh_hit(px: Vector2, dir: Vector2) -> void:
	_snd("fx_thud", px, 0.32, randf_range(0.95, 1.25))
	_glow_pool.emit(px, dir * 40.0, 0.07, 10.0, 1.0, Color(1.0, 0.8, 0.7, 0.7), Color(1, 0.3, 0.2, 0.0))


## Bullet hit a wall: chips, ping, dark scuff mark that lingers a few seconds.
func wall_hit(px: Vector2, dir: Vector2) -> void:
	for i in _n(3):
		_lit_pool.emit(px, _dirv(dir, 0.9) * randf_range(60.0, 200.0), randf_range(0.3, 0.55), randf_range(2.0, 3.5), 1.0,
			Color(0.5, 0.47, 0.4, 1.0), Color(0.3, 0.28, 0.25, 0.0), ParticlePool.SQUARE, 4.0)
	_snd("fx_ping", px, 0.2, randf_range(0.9, 1.2))
	if _marks.size() >= MAX_MARKS:
		_marks.pop_front()
	_marks.append({"pos": px + dir * 2.0, "t": _time, "r": randf_range(2.0, 3.2)})


## Brass lands and stays on the floor for a while.
func casing_land(px: Vector2, col: Color) -> void:
	_add_decal({"kind": "casing", "pos": px, "rot": randf() * TAU, "col": col, "born": _time, "hold": 20.0})
	_snd("fx_tink", px, 0.1, randf_range(0.9, 1.3))


## Per-enemy-type death: coloured gibs, lingering puddle, ichor spray, kind-specific flourish.
func death_fx(px: Vector2, kind: String, dir: Vector2, big: bool) -> void:
	_last_gib_t = _time
	_last_gib_pos = px
	var pal: Dictionary = PAL.get(kind, PAL.hound)
	var ca: Color = pal.a
	var cb: Color = pal.b
	var n := _n(11 + (7 if big else 0))
	for i in n:
		var d := _dirv(dir, 1.6)
		var col: Color = ca.lerp(cb, randf())
		_lit_pool.emit(px, d * randf_range(90.0, 460.0), randf_range(0.5, 1.0), randf_range(3.0, 8.0 if big else 6.0), randf_range(1.5, 3.5),
			col, Color(col.r * 0.6, col.g * 0.6, col.b * 0.6, 0.0), ParticlePool.SQUARE, 3.0)
	for i in _n(6):
		_lit_pool.emit(px, Vector2.from_angle(randf() * TAU) * randf_range(40.0, 160.0), randf_range(0.3, 0.6), randf_range(3.0, 5.0), 1.5,
			Color(ca.r, ca.g, ca.b, 0.9), Color(cb.r, cb.g, cb.b, 0.0), ParticlePool.DOT, 4.0)
	var ptint: Color = pal.puddle
	blood(px, 1.5 if big else 1.0, ptint if kind != "hound" else Color(-1, 0, 0, 0), pal.grey)
	# the puddle that lingers (grows in over ~0.7 s, holds for 90 s)
	for i in (2 if big else 1):
		_add_decal({"kind": "puddle", "pos": px + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 10.0), "rot": randf() * TAU,
			"sz": TILE_PX() * randf_range(1.0, 1.35) * (1.5 if big else 1.0), "tex": randi() % STAINS.size(),
			"col": ptint, "grey": pal.grey, "born": _time, "flip": randf() < 0.5, "hold": 90.0, "grow": 0.7})
	_glow_pool.emit(px, Vector2.ZERO, 0.12, 20.0 if not big else 32.0, 5.0, Color(ca.r * 1.5, ca.g * 1.5, ca.b * 1.5, 0.55), Color(ca.r, ca.g, ca.b, 0.0))
	match kind:
		"shade":   # ink dissolves into wisps that drift up
			for i in _n(9):
				_glow_pool.emit(px + Vector2.from_angle(randf() * TAU) * randf_range(0, 18.0), Vector2(randf_range(-20, 20), randf_range(-70, -25)),
					randf_range(0.8, 1.4), randf_range(7.0, 11.0), 2.0, Color(0.55, 0.25, 0.9, 0.5), Color(0.3, 0.1, 0.6, 0.0), ParticlePool.DOT, 1.5)
		"skin stealer":
			_glow_pool.emit(px, Vector2.ZERO, 0.4, 10.0, 120.0, Color(1.0, 0.6, 0.3, 0.7), Color(1.0, 0.3, 0.1, 0.0), ParticlePool.RING)
			zoom_punch(0.03)
			_snd("fx_boom", px, 0.35, 1.6)
		"crawler":
			_burst_smoke(px, Vector2.ZERO, 3, 0.8)
	_snd("fx_crunch", px, 0.45 if big else 0.32, randf_range(0.85, 1.15) * (0.8 if big else 1.0))


## Called right before an attack damages the player so the damage handler knows where it came from.
func note_attacker(px: Vector2) -> void:
	_attacker = px
	_attacker_t = _time


## Melee wind-up telegraph: converging ring on the attacker, edge chevron towards it, warning hum.
func attack_warning(px: Vector2, windup: float, big := false) -> void:
	if _warns.size() >= MAX_WARN:
		_warns.pop_front()
	_warns.append({"pos": px, "t": 0.0, "dur": maxf(windup, 0.1) + 0.04, "big": big})
	var r0 := 70.0 if big else 46.0
	_glow_pool.emit(px, Vector2.ZERO, maxf(windup, 0.1), r0, 8.0, Color(1.0, 0.3, 0.12, 0.0), Color(1.0, 0.35, 0.15, 0.85), ParticlePool.RING)
	var d: float = px.distance_to(game.player.position) / TILE_PX()
	if d < 10.0:
		_snd("fx_warn", px, 0.25 if not big else 0.4, 1.0 if not big else 0.8)


## The player evaded an attack that was swung at them: slow-mo beat + callout.
func near_miss(_px: Vector2) -> void:
	if _time - _slow_cool < 1.4:
		return
	_slow_cool = _time
	slowmo(0.3, 0.22)
	float_text(game.player.position + Vector2(0, -62), "DODGE", Color(0.5, 0.9, 1.0), 0.9, "info")
	_glow_pool.emit(game.player.position, Vector2.ZERO, 0.3, 10.0, 90.0, Color(0.5, 0.9, 1.0, 0.7), Color(0.3, 0.6, 1.0, 0.0), ParticlePool.RING)
	if game.lighting and game.lighting.post:
		game.lighting.post.aberrate(0.6)
	_snd("fx_miss", null, 0.4, 1.0)


## Pickup being pulled toward the player: glow trail particles (rate-limited per frame).
func trail(px: Vector2, col: Color) -> void:
	if _trail_n >= 5 or randf() > _budget:
		return
	_trail_n += 1
	_glow_pool.emit(px + Vector2(randf_range(-3, 3), randf_range(-3, 3)), Vector2(randf_range(-12, 12), randf_range(-12, 12)), randf_range(0.25, 0.45),
		4.5, 0.5, Color(col.r, col.g, col.b, 0.8), Color(col.r, col.g, col.b, 0.0), ParticlePool.DOT, 3.0)


## Lingering fire for `dur` s inside a radius (bomb aftermath). Visual only.
func fire_patch(px: Vector2, radius_px: float, dur := 2.6) -> void:
	if _fires.size() >= MAX_FIRES:
		_fires.pop_front()
	_fires.append({"pos": px, "t": 0.0, "dur": dur, "r": radius_px, "acc": 0.0})


func _add_slash(d: Dictionary) -> void:
	if _slashes.size() >= MAX_SLASH:
		_slashes.pop_front()
	_slashes.append(d)


func _pillar(px: Vector2) -> void:
	if _pillars.size() >= MAX_PILLARS:
		_pillars.pop_front()
	_pillars.append({"pos": px, "t": 0.0, "dur": 0.85})


# ---- signal hooks -----------------------------------------------------------

func _on_enemy_killed(tile_pos: Vector2, _kind: String, xp: int) -> void:
	var px := tile_pos * TILE_PX()
	if auto_kill_fx:
		burst(px, "gib")
	var s: int = game.player.current_streak
	if xp > 0:
		float_text(px + Vector2(14, -8), "+%d" % xp, Color(0.55, 0.8, 1.0), 0.7, "small")
	if s >= 3:                                  # combo counter pops beside the player and bumps on every kill
		_combo.n = s
		_combo.t = 2.0
		_combo.pop = 1.0
	if s in STREAK_MILESTONES:
		streak_flourish(s)


func _on_level_up(level: int) -> void:
	var p: Player = game.player
	burst(p.position, "levelup")
	_pillar(p.position)
	flash(Color(1.0, 0.85, 0.3, 0.30), 0.35)
	zoom_punch(0.05)
	shake(6.0, 0.3)
	float_text(p.position + Vector2(0, -96), "LEVEL %d" % level, Color(1.0, 0.9, 0.35), 1.4, "crit")
	_snd("fx_level", null, 0.6, 1.0)
	if game.audio and game.audio.has_method("duck"):
		game.audio.duck(0.5)


func _on_player_damaged(amount: float) -> void:
	var p: Player = game.player
	var from := Vector2.ZERO
	var has_dir := _time - _attacker_t < 0.15
	if has_dir:
		from = _attacker
	var away := Vector2.ZERO
	if has_dir:
		away = (p.position - from).normalized()
		_add_indicator((from - p.position).angle(), amount)
	var heavy := clampf(amount / 30.0, 0.3, 1.5)
	kick(away if has_dir else Vector2.from_angle(randf() * TAU), 8.0 * heavy)
	zoom_punch(0.02 + 0.02 * heavy)
	light_flash(p.position, Color(1.0, 0.1, 0.05), 5.0, 0.8 * heavy, 0.18)
	if game.lighting and game.lighting.post:
		game.lighting.post.aberrate(clampf(0.5 + amount / 30.0, 0.5, 1.0))
	for i in _n(7):         # blood spatter thrown away from the attacker
		var d := _dirv(away, 1.0) if has_dir else Vector2.from_angle(randf() * TAU)
		_lit_pool.emit(p.position, d * randf_range(80.0, 260.0), randf_range(0.3, 0.6), randf_range(2.5, 4.5), 1.5,
			Color(0.55, 0.03, 0.03, 1.0), Color(0.3, 0.0, 0.0, 0.0), ParticlePool.SQUARE, 3.5)
	if _combo.n >= 5:
		float_text(p.position + Vector2(0, -80), "COMBO LOST", Color(0.7, 0.7, 0.75), 0.8, "info")
	_combo.n = 0
	_combo.t = 0.0


func _on_footstep(sprinting: bool) -> void:
	var p: Player = game.player
	var foot := p.position + Vector2(0, 14.0)
	var back := -p.vel.normalized() if p.vel.length() > 0.01 else Vector2.ZERO
	for i in _n(4 if sprinting else 2):
		_lit_pool.emit(foot + back * 6.0 + Vector2(randf_range(-5, 5), randf_range(-3, 3)), back * randf_range(10.0, 35.0) + Vector2(randf_range(-12, 12), randf_range(-12, 12)),
			randf_range(0.4, 0.8), randf_range(2.5, 4.0), randf_range(6.0, 10.0), Color(0.62, 0.58, 0.48, 0.2 if not sprinting else 0.3), Color(0.5, 0.47, 0.4, 0.0), ParticlePool.DOT, 2.5)
	# stepping in blood: tracked prints for a few steps + a ripple ring
	var in_blood := false
	var fp := p.position
	for i in range(_decals.size() - 1, maxi(-1, _decals.size() - 90), -1):
		var d: Dictionary = _decals[i]
		if d.kind == "stain" or d.kind == "puddle":
			var r: float = float(d.sz) * 0.3
			if (d.pos as Vector2).distance_squared_to(fp) < r * r:
				in_blood = true
				break
	if in_blood:
		_blood_feet = 6
		_lit_pool.emit(foot, Vector2.ZERO, 0.45, 4.0, 18.0, Color(0.7, 0.2, 0.2, 0.35), Color(0.5, 0.05, 0.05, 0.0), ParticlePool.RING)
		_snd("fx_wet", foot, 0.1, randf_range(1.1, 1.5))
	if _blood_feet > 0 and p.vel.length() > 0.01:
		_foot_side = -_foot_side
		var fwd := p.vel.normalized()
		var side := Vector2(-fwd.y, fwd.x) * 5.0 * _foot_side
		_add_decal({"kind": "foot", "pos": foot + side, "rot": fwd.angle(), "col": Color(0.4, 0.02, 0.02, 0.55 * (_blood_feet / 6.0)),
			"born": _time, "hold": 25.0})
		_blood_feet -= 1


func _add_indicator(ang: float, amount: float) -> void:
	if _inds.size() >= MAX_IND:
		_inds.pop_front()
	_inds.append({"ang": ang, "t": 0.0, "dur": 0.9 + clampf(amount / 60.0, 0.0, 0.5), "w": clampf(0.3 + amount / 80.0, 0.3, 0.7)})


# ---- bursts -----------------------------------------------------------------

func TILE_PX() -> float:
	return float(game.TILE)


func _dirv(dir: Vector2, spread: float) -> Vector2:
	if dir == Vector2.ZERO:
		return Vector2.from_angle(randf() * TAU)
	return dir.normalized().rotated(randf_range(-spread, spread))


func _burst_hit(p: Vector2, dir: Vector2) -> void:
	for i in _n(5):
		var d := _dirv(dir, 0.9)
		_glow_pool.emit(p, d * randf_range(260.0, 480.0), randf_range(0.14, 0.26), 2.0, 1.0,
			Color(1.0, 0.85, 0.6, 1.0), Color(1.0, 0.2, 0.05, 0.0), ParticlePool.STREAK, 4.0)
	for i in _n(5):
		var d2 := _dirv(dir, 0.8)
		_lit_pool.emit(p, d2 * randf_range(120.0, 320.0), randf_range(0.3, 0.6), randf_range(2.5, 4.5), 1.5,
			Color(0.55, 0.03, 0.03, 1.0), Color(0.3, 0.0, 0.0, 0.0), ParticlePool.SQUARE, 3.5)
	_glow_pool.emit(p, Vector2.ZERO, 0.09, 16.0, 3.0, Color(1.0, 0.9, 0.75, 0.9), Color(1, 0.4, 0.2, 0.0))
	_snd("fx_thud", p, 0.28, randf_range(0.9, 1.2))


func _burst_spark(p: Vector2, dir: Vector2) -> void:
	for i in _n(8):
		var d := _dirv(dir, 1.0)
		_glow_pool.emit(p, d * randf_range(200.0, 520.0), randf_range(0.15, 0.35), 2.0, 1.0,
			Color(1.0, 0.95, 0.6, 1.0), Color(1.0, 0.5, 0.1, 0.0), ParticlePool.STREAK, 3.5)
	_glow_pool.emit(p, Vector2.ZERO, 0.08, 12.0, 2.0, Color(1.0, 0.95, 0.7, 0.8), Color(1, 0.6, 0.2, 0.0))


func _burst_smoke(p: Vector2, dir: Vector2, n: int, scale: float) -> void:
	for i in _n(n):
		var d := _dirv(dir, 1.2)
		_lit_pool.emit(p + Vector2.from_angle(randf() * TAU) * randf_range(0, 6 * scale), d * randf_range(15.0, 70.0) * scale,
			randf_range(0.8, 1.4) * scale, randf_range(8.0, 14.0) * scale, randf_range(30.0, 50.0) * scale,
			Color(0.55, 0.55, 0.52, 0.32), Color(0.3, 0.3, 0.3, 0.0), ParticlePool.DOT, 1.8)


func _burst_gib(p: Vector2, dir: Vector2) -> void:
	# the enemy already ran death_fx for this kill (weapons also report it): do not stack a second gib burst
	if _time - _last_gib_t < 0.12 and p.distance_squared_to(_last_gib_pos) < 3600.0:
		return
	for i in _n(12):
		var d := _dirv(dir, 1.6)
		var col := Color(randf_range(0.35, 0.6), randf_range(0.02, 0.08), randf_range(0.02, 0.06), 1.0)
		_lit_pool.emit(p, d * randf_range(100.0, 440.0), randf_range(0.45, 0.9), randf_range(3.0, 7.0), randf_range(2.0, 4.0),
			col, Color(col.r * 0.6, 0.0, 0.0, 0.0), ParticlePool.SQUARE, 3.2)
	blood(p, 1.4)
	_glow_pool.emit(p, Vector2.ZERO, 0.1, 18.0, 4.0, Color(1.0, 0.4, 0.3, 0.5), Color(1, 0.1, 0.1, 0.0))


func _burst_muzzle(p: Vector2, dir: Vector2) -> void:
	_glow_pool.emit(p, Vector2.ZERO, 0.07, 24.0, 5.0, Color(1.0, 0.92, 0.6, 1.0), Color(1.0, 0.5, 0.15, 0.0))
	for i in _n(4):
		var d := _dirv(dir, 0.28)
		_glow_pool.emit(p, d * randf_range(500.0, 850.0), randf_range(0.07, 0.14), 2.0, 1.0,
			Color(1.0, 0.95, 0.7, 1.0), Color(1.0, 0.5, 0.1, 0.0), ParticlePool.STREAK, 2.0)
	_lit_pool.emit(p, _dirv(dir, 0.5) * 30.0, 0.6, 5.0, 16.0, Color(0.6, 0.6, 0.58, 0.18), Color(0.4, 0.4, 0.4, 0.0), ParticlePool.DOT, 2.0)
	light_flash(p, Color(1.0, 0.85, 0.5), 3.5, 0.8 if not calm else 0.4, 0.07)


func _burst_pickup(p: Vector2) -> void:
	for i in _n(10):
		var d := Vector2.from_angle(randf() * TAU)
		_glow_pool.emit(p + d * 6.0, d * randf_range(30.0, 90.0), randf_range(0.5, 0.85), randf_range(5.0, 8.0), 1.0,
			Color(1.0, 0.95, 0.55, 0.9), Color(0.5, 1.0, 0.7, 0.0), ParticlePool.DOT, 2.0, Vector2(0, -60))
	_glow_pool.emit(p, Vector2.ZERO, 0.35, 6.0, 32.0, Color(1.0, 0.9, 0.4, 0.7), Color(1.0, 0.8, 0.2, 0.0), ParticlePool.RING)
	_snd("fx_pickup", p, 0.3, randf_range(0.9, 1.2))


func _burst_levelup(p: Vector2) -> void:
	for i in _n(30):
		var d := Vector2.from_angle(randf() * TAU)
		_glow_pool.emit(p, d * randf_range(180.0, 520.0), randf_range(0.6, 1.1), 2.5, 1.0,
			Color(1.0, 0.88, 0.35, 1.0), Color(1.0, 0.55, 0.1, 0.0), ParticlePool.STREAK, 2.4)
	for i in _n(14):     # rising sparkle column
		_glow_pool.emit(p + Vector2(randf_range(-18, 18), randf_range(0, 14)), Vector2(randf_range(-10, 10), randf_range(-140, -60)), randf_range(0.7, 1.2),
			randf_range(3.0, 5.0), 1.0, Color(1.0, 0.95, 0.6, 0.9), Color(1.0, 0.7, 0.2, 0.0), ParticlePool.DOT, 0.8)
	_glow_pool.emit(p, Vector2.ZERO, 0.5, 10.0, 130.0, Color(1.0, 0.9, 0.4, 0.9), Color(1.0, 0.7, 0.2, 0.0), ParticlePool.RING)
	_glow_pool.emit(p, Vector2.ZERO, 0.8, 10.0, 200.0, Color(1.0, 0.95, 0.6, 0.6), Color(1.0, 0.8, 0.3, 0.0), ParticlePool.RING)
	light_flash(p, Color(1.0, 0.85, 0.4), 7.0, 1.3, 0.5)


func _burst_explosion(p: Vector2) -> void:
	if _time - _last_expl_t < 0.2:
		return          # bomb.gd and objects.gd may both announce one blast
	_last_expl_t = _time
	light_flash(p, Color(1.0, 0.65, 0.3), 9.0, 2.0, 0.35)
	for i in _n(22):
		var d := Vector2.from_angle(randf() * TAU)
		_glow_pool.emit(p + d * 8.0, d * randf_range(80.0, 420.0), randf_range(0.3, 0.65), randf_range(14.0, 22.0), 4.0,
			Color(1.0, randf_range(0.5, 0.85), 0.2, 0.85), Color(0.7, 0.1, 0.0, 0.0), ParticlePool.DOT, 3.2)
	for i in _n(14):
		var d2 := Vector2.from_angle(randf() * TAU)
		_glow_pool.emit(p, d2 * randf_range(300.0, 800.0), randf_range(0.3, 0.6), 2.5, 1.0,
			Color(1.0, 0.9, 0.55, 1.0), Color(1.0, 0.4, 0.1, 0.0), ParticlePool.STREAK, 2.5)
	for i in _n(12):     # debris chunks
		var d3 := Vector2.from_angle(randf() * TAU)
		_lit_pool.emit(p, d3 * randf_range(150.0, 520.0), randf_range(0.6, 1.1), randf_range(3.0, 6.0), 2.0,
			Color(0.35, 0.3, 0.25, 1.0), Color(0.15, 0.13, 0.1, 0.0), ParticlePool.SQUARE, 2.8)
	_glow_pool.emit(p, Vector2.ZERO, 0.35, 10.0, 170.0, Color(1.0, 0.8, 0.5, 0.9), Color(1.0, 0.4, 0.1, 0.0), ParticlePool.RING)
	_glow_pool.emit(p, Vector2.ZERO, 0.55, 10.0, 300.0, Color(1.0, 0.7, 0.4, 0.45), Color(1.0, 0.3, 0.1, 0.0), ParticlePool.RING)
	_burst_smoke(p, Vector2.ZERO, 10, 1.8)
	scorch(p, 2.4)
	for k in 3:          # lingering fires around the crater
		fire_patch(p + Vector2.from_angle(randf() * TAU) * randf_range(20.0, 70.0), 26.0, randf_range(2.2, 3.2))
	shake(14.0, 0.45)
	hitstop(0.05)
	flash(Color(1.0, 0.8, 0.5, 0.32), 0.18)
	zoom_punch(0.05)
	if game.lighting and game.lighting.post:
		game.lighting.post.aberrate(0.9)
		game.lighting.post.shockwave(p, 1.0, 0.75)
	_snd("fx_boom", null, 0.9, 1.0)
	if game.audio and game.audio.has_method("duck"):
		game.audio.duck(0.7)


# ---- decals -----------------------------------------------------------------

func _add_decal(d: Dictionary) -> void:
	var tp: Vector2 = d.pos / TILE_PX()
	if game.map.is_solid(tp.x, tp.y):
		return          # never paint walls
	_decals.append(d)
	while _decals.size() > MAX_DECALS:
		_decals.pop_front()
	_decals_dirty = true
	if d.has("grow"):
		_decal_anim = maxf(_decal_anim, float(d.grow) + 0.05)


func _decal_alpha(d: Dictionary) -> float:
	var age: float = _time - d.born
	var hold: float = d.get("hold", DECAL_FADE_AFTER)
	if age < hold:
		return 1.0
	return clampf(1.0 - (age - hold) / DECAL_FADE_TIME, 0.0, 1.0) * 0.8


func _draw_decals(ci: CanvasItem) -> void:
	for d in _decals:
		var a := _decal_alpha(d)
		if a <= 0.0:
			continue
		match d.kind:
			"stain", "puddle":
				var sz: float = d.sz
				if d.has("grow"):
					var gk: float = clampf((_time - d.born) / float(d.grow), 0.0, 1.0)
					sz *= 0.25 + 0.75 * sqrt(gk)
				ci.draw_set_transform(d.pos, d.rot, Vector2(-1.0 if d.flip else 1.0, 1.0))
				var c: Color = d.col
				var tex: Texture2D = _grey_stains[d.tex] if d.get("grey", false) and not _grey_stains.is_empty() else STAINS[d.tex]
				ci.draw_texture_rect(tex, Rect2(-sz * 0.5, -sz * 0.5, sz, sz), false, Color(c.r, c.g, c.b, c.a * a))
			"burn":
				var sz2: float = d.sz
				ci.draw_set_transform(d.pos, 0.0, Vector2.ONE)
				var c2: Color = d.col
				ci.draw_texture_rect(_burn_tex, Rect2(-sz2 * 0.5, -sz2 * 0.5, sz2, sz2), false, Color(c2.r, c2.g, c2.b, c2.a * a))
			"drop":
				ci.draw_set_transform(d.pos, 0.0, Vector2.ONE)
				var c3: Color = d.col
				ci.draw_circle(Vector2.ZERO, d.r, Color(c3.r, c3.g, c3.b, c3.a * a))
			"foot":
				ci.draw_set_transform(d.pos, d.rot, Vector2(1.0, 0.55))
				var c4: Color = d.col
				ci.draw_circle(Vector2.ZERO, 4.5, Color(c4.r, c4.g, c4.b, c4.a * a))
				ci.draw_circle(Vector2(5.0, 0.0), 2.6, Color(c4.r, c4.g, c4.b, c4.a * a * 0.8))
			"casing":
				ci.draw_set_transform(d.pos, d.rot, Vector2.ONE)
				var c5: Color = d.col
				ci.draw_rect(Rect2(-2.2, -1.1, 4.4, 2.2), Color(c5.r, c5.g, c5.b, a))
				ci.draw_rect(Rect2(-2.2, -1.1, 1.2, 2.2), Color(1, 1, 1, 0.3 * a))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---- drawing ----------------------------------------------------------------

func _draw_lit(ci: CanvasItem) -> void:
	for m in _marks:      # bullet scuffs on walls
		var a: float = clampf(1.0 - (_time - m.t) / 7.0, 0.0, 1.0)
		if a <= 0.0:
			continue
		ci.draw_circle(m.pos, float(m.r) * 1.7, Color(0.05, 0.04, 0.03, 0.35 * a))
		ci.draw_circle(m.pos, float(m.r) * 0.8, Color(0.0, 0.0, 0.0, 0.7 * a))
	_lit_pool.draw(ci)


func _draw_glow(ci: CanvasItem) -> void:
	_glow_pool.draw(ci)
	for s in _slashes:
		_draw_slash(ci, s)
	for pl in _pillars:
		var u: float = pl.t / pl.dur
		var a := (1.0 - u) * minf(1.0, pl.t * 8.0) * 0.5
		var h := 120.0 + 260.0 * (1.0 - (1.0 - u) * (1.0 - u))
		var w := 26.0 * (1.0 - u * 0.6)
		var pp: Vector2 = pl.pos
		ci.draw_polygon(PackedVector2Array([pp + Vector2(-w, 0), pp + Vector2(w, 0), pp + Vector2(w * 0.4, -h), pp + Vector2(-w * 0.4, -h)]),
			PackedColorArray([Color(1.0, 0.85, 0.4, a), Color(1.0, 0.85, 0.4, a), Color(1.0, 0.9, 0.5, 0.0), Color(1.0, 0.9, 0.5, 0.0)]))
	_draw_motes(ci)
	# figure eyes glow in the dark (drawn here, additive)
	for f in _figs:
		var fa: float = _fig_alpha(f)
		if fa > 0.02:
			var fp: Vector2 = f.pos + Vector2(0, -58)
			for ex in [-4.0, 4.0]:
				ci.draw_circle(fp + Vector2(ex, 0), 2.2, Color(0.95, 0.9, 1.0, 0.9 * fa))
				ci.draw_circle(fp + Vector2(ex, 0), 6.0, Color(0.7, 0.3, 1.0, 0.25 * fa))


func _draw_slash(ci: CanvasItem, s: Dictionary) -> void:
	var u: float = s.t / s.dur
	var a: float = 1.0 - u
	var c: Color = s.col
	var pos: Vector2 = s.pos
	match s.k:
		"line":      # impact frame: pure white for the first frames, then the tint fades out; a thin tapered blade
			var l: float = float(s.len) * (0.55 + 0.45 * minf(1.0, u * 5.0))
			var dirv := Vector2.from_angle(s.ang)
			var w: float = float(s.w) * (1.0 - u * 0.7)
			var col := Color(1, 1, 1, 1.0) if u < 0.25 else Color(c.r, c.g, c.b, c.a * a)
			var nrm := Vector2(-dirv.y, dirv.x) * w * 0.5
			ci.draw_colored_polygon(PackedVector2Array([pos - dirv * l * 0.5, pos + nrm, pos + dirv * l * 0.5, pos - nrm]), col)
		"cone":      # shotgun blast wedge
			var half: float = s.w
			var ln: float = float(s.len) * (0.6 + 0.4 * minf(1.0, u * 4.0))
			ci.draw_colored_polygon(PackedVector2Array([pos, pos + Vector2.from_angle(s.ang - half) * ln, pos + Vector2.from_angle(s.ang + half) * ln]),
				Color(c.r, c.g, c.b, c.a * a * a))
		"arc":       # swing crescent: head sweeps through ~150 degrees, tail fades
			var head := lerpf(-1.25, 1.25, 1.0 - (1.0 - minf(1.0, u * 1.6)) * (1.0 - minf(1.0, u * 1.6)))
			var tail := maxf(-1.25, head - 1.1)
			var r: float = s.len * (0.9 + 0.1 * u)
			var w2: float = s.w
			var pts := PackedVector2Array()
			var cols := PackedColorArray()
			var segs := 10
			for i in segs + 1:
				var k := float(i) / segs
				var an: float = float(s.ang) + lerpf(tail, head, k)
				var rr := r + w2 * 0.5 * k
				pts.append(pos + Vector2.from_angle(an) * rr)
				cols.append(Color(c.r, c.g, c.b, c.a * k * a))
			for i in range(segs, -1, -1):
				var k2 := float(i) / segs
				var an2: float = float(s.ang) + lerpf(tail, head, k2)
				var rr2 := r - w2 * 0.5 * k2
				pts.append(pos + Vector2.from_angle(an2) * rr2)
				cols.append(Color(c.r, c.g, c.b, 0.0))
			ci.draw_polygon(pts, cols)


func _draw_motes(ci: CanvasItem) -> void:
	var pl: Player = game.player
	if not pl.headlamp_on:
		return
	var face := Vector2.from_angle(pl.angle)
	var reach := 9.5 * TILE_PX()
	for i in MAX_MOTES:
		if _motes_t[i] >= _motes_life[i]:
			continue
		var u := _motes_t[i] / _motes_life[i]
		var rel: Vector2 = _motes_pos[i] - pl.position
		var dist := rel.length()
		if dist < 8.0 or dist > reach:
			continue
		var cone := clampf((rel / dist).dot(face) - 0.5, 0.0, 0.35) / 0.35
		var a := sin(u * PI) * cone * (1.0 - dist / reach) * 0.85
		if a <= 0.02:
			continue
		var sz := 1.6 + 1.2 * fposmod(float(i) * 0.37, 1.0)
		ci.draw_texture_rect(_mote_tex, Rect2(_motes_pos[i].x - sz, _motes_pos[i].y - sz, sz * 2.0, sz * 2.0), false, Color(1.0, 0.96, 0.8, a))


func _fig_alpha(f: Dictionary) -> float:
	var a: float = clampf(f.t / 0.8, 0.0, 1.0) * clampf((f.life - f.t) / 0.8, 0.0, 1.0)
	if f.dying:
		a *= clampf(f.vanish / 0.12, 0.0, 1.0)
	# subtle flicker so it never reads as a solid prop
	return a * (0.75 + 0.25 * sin(_time * 23.0 + f.sw))


func _draw_figs(ci: CanvasItem) -> void:
	for f in _figs:
		var a := _fig_alpha(f)
		if a <= 0.02:
			continue
		var p: Vector2 = f.pos
		var sway := sin(_time * 1.3 + f.sw) * 2.0
		var col := Color(0.0, 0.0, 0.02, 0.78 * a)
		ci.draw_circle(p + Vector2(sway, -58), 8.0, col)                       # head
		ci.draw_colored_polygon(PackedVector2Array([                           # torso + legs
			p + Vector2(sway - 10, -48), p + Vector2(sway + 10, -48), p + Vector2(sway + 8, -18), p + Vector2(sway + 9, 10),
			p + Vector2(sway + 2, 10), p + Vector2(sway, -14), p + Vector2(sway - 2, 10), p + Vector2(sway - 9, 10), p + Vector2(sway - 8, -18)]), col)
		ci.draw_line(p + Vector2(sway - 10, -46), p + Vector2(sway - 14, -12), col, 4.0)   # arms
		ci.draw_line(p + Vector2(sway + 10, -46), p + Vector2(sway + 14, -12), col, 4.0)


func _draw_text(ci: CanvasItem) -> void:
	for f in _floats:
		var t: float = f.t
		var life: float = f.life
		var u := t / life
		var popmax: float = f.pop
		var pop := 1.0
		if t < 0.18:
			pop = lerpf(0.3, popmax, t / 0.18)
		elif t < 0.3:
			pop = lerpf(popmax, 1.0, (t - 0.18) / 0.12)
		var rise := (1.0 - pow(1.0 - u, 2.0)) * float(f.rise)
		var alpha := 1.0 if u < 0.6 else clampf(1.0 - (u - 0.6) / 0.4, 0.0, 1.0)
		var col: Color = f.col
		var pos: Vector2 = f.pos + Vector2(0, -rise)
		if f.wob > 0.0:
			pos.x += sin(t * 6.0 + f.ph) * float(f.wob)
		if f.style == "crit" and t < 0.35:      # impact jitter
			pos += Vector2(sin(t * 90.0 + f.ph), cos(t * 77.0)) * 3.0 * (1.0 - t / 0.35)
		ci.draw_set_transform(pos, 0.0, Vector2(pop, pop))
		var off := Vector2(-f.w * 0.5, f.size * 0.35)
		ci.draw_string_outline(FONT, off, f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, f.size, 6, Color(0, 0, 0, alpha * 0.9))
		ci.draw_string(FONT, off, f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, f.size, Color(col.r, col.g, col.b, col.a * alpha))
	# combo counter: bumps on every kill, drains away over 2 s
	if _combo.n >= 3 and _combo.t > 0.0:
		var pl: Player = game.player
		var n: int = _combo.n
		var ccol := Color(1, 1, 1).lerp(Color(1.0, 0.85, 0.25), clampf((n - 3) / 7.0, 0.0, 1.0)).lerp(Color(1.0, 0.25, 0.15), clampf((n - 15) / 25.0, 0.0, 1.0))
		var sz := int(26 + minf(n, 30) * 0.6)
		var txt := "x%d" % n
		var bump := 1.0 + float(_combo.pop) * 0.55
		var fade := clampf(_combo.t / 0.5, 0.0, 1.0)
		var base: Vector2 = pl.position + Vector2(44, -44)
		ci.draw_set_transform(base, -0.08, Vector2(bump, bump))
		ci.draw_string_outline(FONT, Vector2(0, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 6, Color(0, 0, 0, 0.9 * fade))
		ci.draw_string(FONT, Vector2(0, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(ccol.r, ccol.g, ccol.b, fade))
		ci.draw_set_transform(base + Vector2(0, 8), 0.0, Vector2.ONE)
		ci.draw_rect(Rect2(0, 0, 46.0 * clampf(_combo.t / 2.0, 0.0, 1.0), 3.0), Color(ccol.r, ccol.g, ccol.b, 0.8 * fade))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Screen-space overlay: directional damage wedges and melee wind-up chevrons at the screen edge.
func _draw_hud(ci: CanvasItem) -> void:
	if _inds.is_empty() and _warns.is_empty():
		return
	var vp := _hud_node.get_viewport_rect().size
	var c := vp * 0.5
	var r := minf(vp.x, vp.y) * 0.5 - 22.0
	for ind in _inds:
		var u: float = ind.t / ind.dur
		var a := (1.0 - u) * (1.0 - u)
		var ang: float = ind.ang
		var w: float = ind.w
		ci.draw_arc(c, r, ang - w, ang + w, 18, Color(0.85, 0.02, 0.02, 0.85 * a), 30.0)
		ci.draw_arc(c, r - 22.0, ang - w * 0.7, ang + w * 0.7, 14, Color(0.9, 0.1, 0.05, 0.4 * a), 16.0)
		var tip := c + Vector2.from_angle(ang) * (r - 44.0)
		var dv := Vector2.from_angle(ang)
		var nv := Vector2(-dv.y, dv.x)
		ci.draw_colored_polygon(PackedVector2Array([tip + dv * 22.0, tip - dv * 6.0 + nv * 20.0, tip - dv * 6.0 - nv * 20.0]), Color(1.0, 0.15, 0.1, 0.9 * a))
	var ppos: Vector2 = game.player.position
	for wn in _warns:
		var u2: float = wn.t / wn.dur
		var dv2: Vector2 = (wn.pos - ppos)
		if dv2.length_squared() < 4.0:
			continue
		dv2 = dv2.normalized()
		var nv2 := Vector2(-dv2.y, dv2.x)
		var pulse := 0.55 + 0.45 * sin(wn.t * 30.0)
		var sz := (16.0 if not wn.big else 24.0) * (0.7 + 0.6 * u2)
		var tip2 := c + dv2 * (r - 6.0)
		var col := Color(1.0, 0.55 - 0.3 * u2, 0.1, (0.35 + 0.65 * u2) * pulse)
		ci.draw_line(tip2 - dv2 * sz * 1.4 + nv2 * sz, tip2, col, 4.0)
		ci.draw_line(tip2 - dv2 * sz * 1.4 - nv2 * sz, tip2, col, 4.0)
		ci.draw_line(tip2 - dv2 * sz * 2.4 + nv2 * sz * 0.6, tip2 - dv2 * sz, Color(col.r, col.g, col.b, col.a * 0.5), 3.0)
		ci.draw_line(tip2 - dv2 * sz * 2.4 - nv2 * sz * 0.6, tip2 - dv2 * sz, Color(col.r, col.g, col.b, col.a * 0.5), 3.0)


# ---- per-frame update (real time: shake and particles keep going during hitstop) ----

func _shake_envelope() -> float:
	if _shake_t <= 0.0:
		return 0.0
	var u := _shake_t / _shake_dur
	return u * u


func _opt_float(o, key: String, default: float) -> float:
	var v = o.get(key)
	if v is float or v is int:
		return clampf(float(v), 0.0, 1.0)
	return default


func _update_options() -> void:
	var ui = game.get("ui")
	if ui == null:
		return
	var o = ui.get("options")
	if o == null:
		return
	shake_scale = _opt_float(o, "screen_shake", 1.0)
	var rf = o.get("reduce_flashing")
	calm = rf is bool and rf


func _update_budget(rdt: float) -> void:
	if game.state != "playing":
		return
	_ft_ema = lerpf(_ft_ema, rdt, 0.04)
	_budget_t -= rdt
	if _budget_t > 0.0:
		return
	_budget_t = 0.75
	var target := 1.0
	if adaptive:
		if _ft_ema > 0.034:
			target = 0.35
		elif _ft_ema > 0.025:
			target = 0.6
	_budget = move_toward(_budget, target, 0.25)


func _update_slowmo(rdt: float) -> void:
	var post: PostFx = game.lighting.post if game.lighting else null
	if _slow_t > 0.0 and game.state == "playing":
		_slow_t -= rdt
		var u := clampf(_slow_t / _slow_dur, 0.0, 1.0)
		var k := sin(u * PI)                         # ease in and out
		var sc := lerpf(1.0, _slow_min, minf(1.0, k * 2.5))
		Engine.time_scale = sc
		if post:
			post.set_slowmo((1.0 - sc) / maxf(1.0 - _slow_min, 0.01))
		if _slow_t <= 0.0:
			Engine.time_scale = 1.0
			_slow_min = 1.0
			if post:
				post.set_slowmo(0.0)
	elif Engine.time_scale != 1.0:
		Engine.time_scale = 1.0
		_slow_t = 0.0
		_slow_min = 1.0
		if post:
			post.set_slowmo(0.0)


func _tick_motes(dt: float) -> void:
	var pl: Player = game.player
	var on: bool = pl.headlamp_on and game.state == "playing" and _budget > 0.5
	for i in MAX_MOTES:
		if _motes_t[i] < _motes_life[i]:
			_motes_t[i] += dt
			var v := _motes_vel[i]
			# slow brownian drift
			v += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 18.0 * dt
			v *= maxf(0.0, 1.0 - 0.8 * dt)
			_motes_vel[i] = v
			_motes_pos[i] += v * dt
	if not on:
		return
	_mote_acc += dt * 9.0 * _budget
	while _mote_acc >= 1.0:
		_mote_acc -= 1.0
		for i in MAX_MOTES:
			if _motes_t[i] >= _motes_life[i]:
				var ang: float = pl.angle + randf_range(-0.8, 0.8)
				_motes_pos[i] = pl.position + Vector2.from_angle(ang) * randf_range(1.5, 9.0) * TILE_PX()
				_motes_vel[i] = Vector2(randf_range(-10.0, 10.0), randf_range(-14.0, 4.0))
				_motes_life[i] = randf_range(3.5, 7.0)
				_motes_t[i] = 0.0
				break


func _tick_fires(dt: float) -> void:
	var i := _fires.size() - 1
	while i >= 0:
		var f: Dictionary = _fires[i]
		f.t += dt
		if f.t >= f.dur:
			_fires.remove_at(i)
		else:
			var life: float = 1.0 - f.t / f.dur
			f.acc += dt * 16.0 * life * _budget
			while f.acc >= 1.0:
				f.acc -= 1.0
				var fp: Vector2 = f.pos + Vector2.from_angle(randf() * TAU) * randf() * float(f.r)
				_glow_pool.emit(fp, Vector2(randf_range(-10, 10), -randf_range(20.0, 60.0)), randf_range(0.35, 0.7), randf_range(5.0, 9.0), 1.5,
					Color(1.0, randf_range(0.45, 0.75), 0.1, 0.8 * life), Color(0.8, 0.15, 0.0, 0.0), ParticlePool.DOT, 1.0)
				if randf() < 0.25:
					_lit_pool.emit(fp, Vector2(randf_range(-8, 8), -randf_range(25.0, 55.0)), randf_range(0.9, 1.5), 6.0, 20.0,
						Color(0.3, 0.3, 0.3, 0.25 * life), Color(0.15, 0.15, 0.15, 0.0), ParticlePool.DOT, 0.8)
		i -= 1


func _tick_sanity(dt: float, rdt: float) -> void:
	var pl: Player = game.player
	var pct: float = pl.sanity / maxf(pl.max_sanity, 0.001)
	var post: PostFx = game.lighting.post if game.lighting else null
	# shadow figures lurking at the edge of the headlamp
	var sev := clampf(1.0 - pct / 0.35, 0.0, 1.0)
	if sev > 0.0 and _budget > 0.5 and game.state == "playing":
		_fig_t -= dt
		if _fig_t <= 0.0 and _figs.size() < MAX_FIGS:
			_fig_t = lerpf(14.0, 4.0, sev) * randf_range(0.7, 1.4)
			_spawn_figure(pl)
	var i := _figs.size() - 1
	while i >= 0:
		var f: Dictionary = _figs[i]
		f.t += dt
		if f.dying:
			f.vanish -= dt
		else:
			var to: Vector2 = f.pos - pl.position
			var looked: bool = absf(angle_difference(pl.angle, to.angle())) < 0.32 and f.t > 0.7
			if looked or to.length() < 2.4 * TILE_PX():
				f.vanish = 0.12
				f.dying = true
				if post:
					post.aberrate(0.55)
				_snd("fx_zap", f.pos, 0.18, randf_range(0.8, 1.1))
			else:
				f.pos -= to.normalized() * 7.0 * dt          # creeps slowly closer
		if f.t >= f.life or (f.dying and f.vanish <= 0.0):
			_figs.remove_at(i)
		i -= 1
	# light stutter (power sag) that grows as sanity falls; skipped in reduce-flashing mode
	var fl := 0.0
	if not calm and pct < 0.3:
		_flick_t -= dt
		if _flick_t <= 0.0:
			var s2 := clampf(1.0 - pct / 0.3, 0.0, 1.0)
			_flick_t = lerpf(9.0, 2.0, s2) * randf_range(0.5, 1.4)
			_flick_dur = randf_range(0.06, 0.18)
			_flick_age = 0.0
			if randf() < s2 * 0.5 and post:
				post.aberrate(0.5)
		_flick_age += dt
		if _flick_age < _flick_dur:
			var ph := _flick_age / _flick_dur
			fl = (1.0 if int(ph * 5.0) % 2 == 0 else 0.35) * (1.0 - ph)
	if post:
		post.set_flicker(fl)


func _spawn_figure(pl: Player) -> void:
	for tries in 8:
		var off := (randf_range(1.15, 2.3)) * (1.0 if randf() < 0.5 else -1.0)
		var ang: float = pl.angle + off
		var d := randf_range(6.0, 8.5)
		var tp: Vector2 = pl.tile_pos + Vector2.from_angle(ang) * d
		if game.map.is_solid(tp.x, tp.y) or game.map.is_solid(tp.x + 0.5, tp.y) or game.map.is_solid(tp.x, tp.y + 0.5):
			continue
		_figs.append({"pos": tp * TILE_PX(), "t": 0.0, "life": randf_range(2.2, 3.8), "vanish": 0.0, "dying": false, "sw": randf() * TAU})
		return


func _process(delta: float) -> void:
	if game == null:
		return
	var now := Time.get_ticks_usec()
	var rdt := clampf(float(now - _last_us) * 1.0e-6, 0.0, 0.1)
	_last_us = now
	_opt_t -= rdt
	if _opt_t <= 0.0:
		_opt_t = 0.5
		_update_options()
	_update_budget(rdt)
	_update_slowmo(rdt)
	_trail_n = 0
	var dt := delta
	if game.state == "paused" or game.state == "perk":
		dt = 0.0
	_time += dt

	var had_fx := _lit_pool.count + _glow_pool.count + _floats.size()
	_lit_pool.update(dt)
	_glow_pool.update(dt)
	for f in _floats:
		f.t += dt
	# drop expired text (iterate backwards so removals are safe)
	for i in range(_floats.size() - 1, -1, -1):
		if _floats[i].t >= _floats[i].life:
			_floats.remove_at(i)

	if game.state == "playing" or dt > 0.0:
		_tick_motes(dt)
		_tick_fires(dt)
		_tick_sanity(dt, rdt)
		_update_marks_lists(dt)
	if _combo.t > 0.0:
		_combo.t -= dt
		_combo.pop = maxf(0.0, _combo.pop - dt * 5.0)
		if _combo.t <= 0.0:
			_combo.n = 0

	if had_fx > 0 or _lit_pool.count + _glow_pool.count + _floats.size() > 0 or not _marks.is_empty() or _combo.t > 0.0:
		_lit_node.queue_redraw()
		_text_node.queue_redraw()
	if _glow_pool.count > 0 or had_fx > 0 or not _slashes.is_empty() or not _pillars.is_empty() or not _figs.is_empty() or game.player.headlamp_on:
		_glow_node.queue_redraw()    # (headlamp motes keep this one live while the lamp is on)
	if not _figs.is_empty():
		_fig_node.queue_redraw()
	if not _inds.is_empty() or not _warns.is_empty():
		_hud_node.queue_redraw()

	# decals: redraw when changed, and slowly while fading
	_fade_timer -= dt
	if _fade_timer <= 0.0:
		_fade_timer = 0.5
		var fading := false
		for di in range(_decals.size() - 1, -1, -1):
			var dd: Dictionary = _decals[di]
			if _time - dd.born > float(dd.get("hold", DECAL_FADE_AFTER)):
				fading = true
				if _decal_alpha(dd) <= 0.0:
					_decals.remove_at(di)
		if fading:
			_decals_dirty = true
	if _decal_anim > 0.0:
		_decal_anim -= dt
		_decals_dirty = true
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

	_update_camera(delta, rdt)


## Slashes / indicators / warnings are small capped lists advanced here.
func _update_marks_lists(dt: float) -> void:
	for i in range(_slashes.size() - 1, -1, -1):
		var s: Dictionary = _slashes[i]
		s.t += dt
		if s.t >= s.dur:
			_slashes.remove_at(i)
	for i in range(_pillars.size() - 1, -1, -1):
		var pl: Dictionary = _pillars[i]
		pl.t += dt
		if pl.t >= pl.dur:
			_pillars.remove_at(i)
	for i in range(_inds.size() - 1, -1, -1):
		var d: Dictionary = _inds[i]
		d.t += dt
		if d.t >= d.dur:
			_inds.remove_at(i)
	for i in range(_warns.size() - 1, -1, -1):
		var w: Dictionary = _warns[i]
		w.t += dt
		if w.t >= w.dur:
			_warns.remove_at(i)


func _update_camera(delta: float, rdt: float) -> void:
	if game.camera == null:
		return
	var cam: Camera2D = game.camera
	var off := Vector2.ZERO
	if _shake_t > 0.0:
		_shake_t -= delta
		var env := _shake_envelope()
		var t := _time * 60.0
		off = Vector2(_noise.get_noise_1d(t), _noise.get_noise_1d(t + 1000.0)) * _shake_amp * env * 1.6 * shake_scale
		if _shake_t <= 0.0:
			_shake_amp = 0.0
	_kick = _kick.lerp(Vector2.ZERO, minf(1.0, 14.0 * delta))

	# look-ahead: the camera leans toward where the player is aiming (smoothed in real time)
	var pl: Player = game.player
	var want_look := Vector2.ZERO
	if game.state == "playing" and game.input:
		var to: Vector2 = game.input.aim_world - pl.position
		want_look = to.limit_length(LOOK_MAX_PX / LOOK_K) * LOOK_K
	_look = _look.lerp(want_look, 1.0 - exp(-3.5 * rdt))
	cam.offset = (off + _kick).limit_length(MAX_SHAKE_PX * 1.5) + _look

	# zoom: punches decay, sprinting pulls back a little, low HP leans in with the heartbeat
	var hp_pct: float = pl.hp / maxf(pl.max_hp, 0.001)
	var target := 0.0
	if game.state == "playing":
		if pl.sprinting and pl.moving:
			target -= 0.03
		if hp_pct < 0.35:
			target += 0.025 * (1.0 - hp_pct / 0.35)
	_zoom_dyn = lerpf(_zoom_dyn, target, 1.0 - exp(-2.5 * rdt))
	_zoom_kick = lerpf(_zoom_kick, 0.0, minf(1.0, 9.0 * delta))
	if (cam.zoom - _applied_zoom).length() > 0.0005:      # somebody else changed the zoom (touch layout etc.): adopt it as the base
		_base_zoom = cam.zoom
	_applied_zoom = _base_zoom * (1.0 + _zoom_kick + _zoom_dyn)
	cam.zoom = _applied_zoom
