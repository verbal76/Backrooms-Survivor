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
var _pulse := 0.0
var _aber := 0.0
var _time := 0.0


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
