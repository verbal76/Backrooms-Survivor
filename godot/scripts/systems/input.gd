class_name GameInput
extends Node
## Default input provider: keyboard + mouse + touch sticks. The input agent extends this with
## gamepad, touch buttons and UI navigation (port of input.lua).
##
## Public API read by every other system:
##   move: Vector2 (-1..1), aim_world: Vector2 (world px), fire: bool, alt_fire: bool, sprint: bool
##   just(action) -> bool: true for one frame after an edge press of a named action.
##   Action names: use_water, use_bandage, use_food, bomb, weapon_next, weapon_prev, headlamp,
##   battery, pause, interact, ui_left, ui_right, ui_up, ui_down, ui_accept, ui_back, status_hud
var game
var move := Vector2.ZERO
var aim_world := Vector2.ZERO
var fire := false
var alt_fire := false
var sprint := false
var aim_active := true

var _just := {}
var _touch_move := {"id": -1, "origin": Vector2.ZERO, "pos": Vector2.ZERO}
var _touch_aim := {"id": -1, "origin": Vector2.ZERO, "pos": Vector2.ZERO}
var _aim_dir := Vector2.ZERO
var _sticks: Control
const STICK_R := 90.0


func setup(g) -> void:
	game = g
	var layer := CanvasLayer.new()
	layer.layer = 50
	_sticks = Control.new()
	_sticks.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sticks.draw.connect(_draw_sticks)
	layer.add_child(_sticks)
	add_child(layer)


func just(action: String) -> bool:
	return _just.has(action)


func press(action: String) -> void:
	_just[action] = true


func tick(_dt: float) -> void:
	move = Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
		- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
		- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	sprint = Input.is_physical_key_pressed(KEY_SHIFT)
	fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_physical_key_pressed(KEY_SPACE)
	alt_fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	aim_world = game.get_global_mouse_position()
	if _touch_move.id >= 0:
		var v: Vector2 = (_touch_move.pos - _touch_move.origin) / STICK_R
		move = v.limit_length(1.0)
		sprint = v.length() > 1.0
	if _touch_aim.id >= 0:
		var a: Vector2 = _touch_aim.pos - _touch_aim.origin
		if a.length() > 12.0:
			_aim_dir = a.normalized()
			fire = true
		aim_world = game.player.position + _aim_dir * 200.0
	elif _aim_dir != Vector2.ZERO and _touch_move.id >= 0:
		aim_world = game.player.position + _aim_dir * 200.0


## Called by game.gd at the end of every frame.
func end_frame() -> void:
	_just.clear()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE: press("pause")
			KEY_E: press("interact")
			KEY_Q: press("weapon_prev")
			KEY_TAB: press("weapon_next")
			KEY_F: press("headlamp")
			KEY_G: press("bomb")


func _input(event: InputEvent) -> void:
	var half := get_viewport().get_visible_rect().size.x / 2.0
	if event is InputEventScreenTouch:
		var stick: Dictionary = _touch_move if event.position.x < half else _touch_aim
		if event.pressed and stick.id < 0:
			stick.id = event.index
			stick.origin = event.position
			stick.pos = event.position
		elif not event.pressed and stick.id == event.index:
			stick.id = -1
		_sticks.queue_redraw()
	elif event is InputEventScreenDrag:
		for stick in [_touch_move, _touch_aim]:
			if stick.id == event.index:
				stick.pos = event.position
		_sticks.queue_redraw()


func _draw_sticks() -> void:
	for stick in [_touch_move, _touch_aim]:
		if stick.id >= 0:
			_sticks.draw_arc(stick.origin, STICK_R, 0.0, TAU, 40, Color(1, 1, 1, 0.35), 3.0)
			_sticks.draw_circle(stick.origin + (stick.pos - stick.origin).limit_length(STICK_R), 34.0, Color(1, 1, 1, 0.35))
