extends CanvasLayer
## Studio splash shown over the game on launch: logo fades in, holds, fades out. Any tap/key skips.
## Replace assets/branding/studio_logo.png to change the emblem (no code change needed).

const LOGO := preload("res://assets/branding/studio_logo.png")
const FADE_IN := 0.5
const HOLD := 1.4
const FADE_OUT := 0.6

var _bg: ColorRect
var _logo: TextureRect
var _t := 0.0


func _ready() -> void:
	layer = 100
	_bg = ColorRect.new()
	_bg.color = Color.BLACK
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_logo = TextureRect.new()
	_logo.texture = LOGO
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_logo.anchor_left = 0.12
	_logo.anchor_right = 0.88
	_logo.anchor_top = 0.2
	_logo.anchor_bottom = 0.8
	_logo.offset_left = 0
	_logo.offset_right = 0
	_logo.offset_top = 0
	_logo.offset_bottom = 0
	_logo.modulate.a = 0.0
	add_child(_logo)
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_t += delta
	var total := FADE_IN + HOLD + FADE_OUT
	if _t < FADE_IN:
		_logo.modulate.a = _t / FADE_IN
	elif _t < FADE_IN + HOLD:
		_logo.modulate.a = 1.0
	else:
		var k := (_t - FADE_IN - HOLD) / FADE_OUT
		_logo.modulate.a = 1.0 - k
		_bg.modulate.a = 1.0 - k
	if _t >= total:
		queue_free()


func _input(event: InputEvent) -> void:
	if (event is InputEventKey and event.pressed) or (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventMouseButton and event.pressed):
		if _t < FADE_IN + HOLD:
			_t = FADE_IN + HOLD   # jump to fade-out
		get_viewport().set_input_as_handled()
