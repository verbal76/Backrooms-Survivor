class_name PostFx
extends CanvasLayer
## Full-screen post-process (grain, vignette, desat, contrast, exposure, haze, dust, sanity VCR
## distortion, chromatic aberration, low-HP red vignette). Port of shaders.lua + render.lua cfg.
## Sits on layer 5: above the lit world and fx, below the flash overlay's neighbours and all UI (>= 10).

const SHADER := preload("res://assets/shaders/post_fx.gdshader")

# Render.cfg
const GRAIN := 0.020
const VIGNETTE := 0.20
const DESAT := 0.08
const CONTRAST := 1.05
const EXPOSURE := 1.12
const HAZE_ALPHA := 0.025
const HAZE_PARALLAX := 0.14
const HAZE_STRENGTH := 0.10
const DUST_INTENSITY := 0.55

var rect: ColorRect
var mat: ShaderMaterial
var enabled := true : set = _set_enabled
var camera: Camera2D                 # set by the lighting system; needed to place shockwaves in screen space
var _pulse := 0.0
var _aber := 0.0
var _time := 0.0
var _slowmo := 0.0
var _flicker := 0.0
var _shocks: Array = [{"pos": Vector2.ZERO, "t": 9.0, "dur": 0.7, "amp": 1.0}, {"pos": Vector2.ZERO, "t": 9.0, "dur": 0.7, "amp": 1.0}]
var _shock_next := 0


func _init() -> void:
	layer = 5
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	rect.material = mat
	add_child(rect)


func _set_enabled(v: bool) -> void:
	enabled = v
	visible = v


## Damage pulse: red edge flash + chromatic kick that decays over ~0.6 s.
func pulse(amount := 1.0) -> void:
	_pulse = maxf(_pulse, amount)


## Short chromatic aberration burst (explosions, big hits, glitches).
func aberrate(amount := 1.0) -> void:
	_aber = maxf(_aber, amount)


## Refractive shockwave ring expanding from a world-px position (bomb, big slam). Two can overlap.
func shockwave(world_px: Vector2, amp := 1.0, dur := 0.7) -> void:
	var s: Dictionary = _shocks[_shock_next]
	_shock_next = 1 - _shock_next
	s.pos = world_px
	s.t = 0.0
	s.dur = dur
	s.amp = amp


## Slow-mo look (desaturate + contrast) for near-miss / parry beats. Set every frame by fx while active.
func set_slowmo(v: float) -> void:
	_slowmo = v


## 0..1 light stutter dip (low-sanity flicker, power surge). Set by fx each frame.
func set_flicker(v: float) -> void:
	_flicker = v


func _shock_vec(i: int, vp: Vector2) -> Vector4:
	var s: Dictionary = _shocks[i]
	if s.t >= s.dur or camera == null:
		return Vector4(0.5, 0.5, 0.0, 0.0)
	var u: float = s.t / s.dur
	var uv: Vector2 = (s.pos - camera.get_screen_center_position()) * camera.zoom / vp + Vector2(0.5, 0.5)
	return Vector4(uv.x, uv.y, 0.04 + u * 0.75, (1.0 - u) * (1.0 - u) * s.amp)


## Called every frame by the lighting system.
##  sanity_pct, hp_pct: 0..1; cam_px: camera world position in px (haze parallax).
func update_state(dt: float, sanity_pct: float, hp_pct: float, cam_px: Vector2, heartbeat_env: float) -> void:
	_time += dt
	_pulse = maxf(0.0, _pulse - dt / 0.6)
	_aber = maxf(0.0, _aber - dt / 0.5)
	var vcr := 0.0
	if sanity_pct < 0.25:
		vcr = 1.0 - sanity_pct / 0.25
	var tint := 0.0
	if sanity_pct < 0.4:
		tint = (0.4 - sanity_pct) / 0.4
	var danger := 0.0
	if hp_pct < 0.35:
		danger = 1.0 - hp_pct / 0.35
	mat.set_shader_parameter("time", _time)
	mat.set_shader_parameter("cam_px", cam_px)
	mat.set_shader_parameter("sanity_fx", vcr)
	mat.set_shader_parameter("sanity_tint", tint)
	mat.set_shader_parameter("hp_danger", danger)
	mat.set_shader_parameter("heartbeat", heartbeat_env)
	mat.set_shader_parameter("hit_pulse", _pulse * _pulse)
	mat.set_shader_parameter("aberration", _aber)
	mat.set_shader_parameter("slowmo", _slowmo)
	mat.set_shader_parameter("flicker", _flicker)
	var vp := get_viewport().get_visible_rect().size
	for i in 2:
		_shocks[i].t += dt
		mat.set_shader_parameter("shock" if i == 0 else "shock2", _shock_vec(i, vp))
