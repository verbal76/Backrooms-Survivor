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
	add_child(layer)
	_stream_chunks()


func _physics_process(delta: float) -> void:
	var dir := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
		- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
		- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	var sprint := Input.is_physical_key_pressed(KEY_SHIFT)
	player.step(delta, dir, sprint, get_global_mouse_position())
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
