extends Node2D
## Core loop: infinite map, player, camera, headlamp. Everything under res://scenes and
## res://scripts is patchable over the air in dev builds.

const Patcher = preload("res://scripts/patcher.gd")
const TILE := 52

var map: WorldMap
var player: Player
var camera: Camera2D
var _views := {}
var _hud: Label
# touch: left half of the screen = move stick, right half = aim stick
var _touch_move := {"id": -1, "origin": Vector2.ZERO, "pos": Vector2.ZERO}
var _touch_aim := {"id": -1, "origin": Vector2.ZERO, "pos": Vector2.ZERO}
var _aim_dir := Vector2.ZERO
var _sticks: Control
const STICK_R := 90.0


func _ready() -> void:
	map = WorldMap.new()
	map.ensure_chunk(0, 0)

	var dark := CanvasModulate.new()
	dark.color = Color(0.035, 0.035, 0.05)
	add_child(dark)

	player = Player.new()
	player.map = map
	player.tile_pos = map.find_spawn()
	player.position = player.tile_pos * TILE
	add_child(player)

	player.lamp = PointLight2D.new()
	player.lamp.texture = _radial_texture()
	player.lamp.texture_scale = 3.2
	player.lamp.energy = 1.5
	player.lamp.color = Color(1.0, 0.92, 0.7)
	player.lamp.shadow_enabled = true
	player.add_child(player.lamp)

	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 12.0
	player.add_child(camera)

	var layer := CanvasLayer.new()  # HUD ignores the darkening CanvasModulate
	_hud = Label.new()
	_hud.position = Vector2(12, 8)
	layer.add_child(_hud)
	_sticks = Control.new()
	_sticks.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sticks.draw.connect(_draw_sticks)
	layer.add_child(_sticks)
	add_child(layer)
	_stream_chunks()


func _physics_process(delta: float) -> void:
	var dir := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
		- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
		- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	var sprint := Input.is_physical_key_pressed(KEY_SHIFT)
	var aim := get_global_mouse_position()
	if _touch_move.id >= 0:
		var v: Vector2 = (_touch_move.pos - _touch_move.origin) / STICK_R
		dir = v.limit_length(1.0)
		sprint = v.length() > 1.0
	if _touch_aim.id >= 0:
		var a: Vector2 = _touch_aim.pos - _touch_aim.origin
		if a.length() > 12.0:
			_aim_dir = a.normalized()
	if _touch_aim.id >= 0 or _aim_dir != Vector2.ZERO and _touch_move.id >= 0:
		aim = player.position + _aim_dir * 200.0
	player.step(delta, dir, sprint, aim)
	_stream_chunks()
	_hud.text = "BACKROOMS SURVIVOR  build %s  %s\nHP %d   STA %d" % [
		Patcher.read_info().get("build", 0), Patcher.read_info().get("sha", ""),
		int(player.hp), int(player.stamina)]


func _stream_chunks() -> void:
	map.ensure_around(player.tile_pos, 32)
	for c in map.drain_new_chunks():
		var view := ChunkView.new()
		add_child(view)
		view.setup(map, c.x, c.y)
		_views[c] = view


func _radial_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color.WHITE, Color.BLACK])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex


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
