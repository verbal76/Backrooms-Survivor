extends Node2D
## Placeholder game scene: a dark room with a headlamp light and shadow-casting walls.
## It proves the lighting setup and the OTA patch flow. The real game gets ported
## into this scene tree (and everything under res://scenes + res://scripts is patchable).

const Patcher = preload("res://scripts/patcher.gd")
const TILE := 32
const ROOM := Rect2(0, 0, 960, 720)

var _lamp: PointLight2D
var _walls: Array[Rect2] = [
	Rect2(160, 128, 224, 32),
	Rect2(544, 256, 32, 288),
	Rect2(224, 480, 256, 32),
]


func _ready() -> void:
	var dark := CanvasModulate.new()
	dark.color = Color(0.05, 0.05, 0.07)
	add_child(dark)

	_lamp = PointLight2D.new()
	_lamp.texture = _radial_texture()
	_lamp.texture_scale = 2.2
	_lamp.energy = 1.4
	_lamp.color = Color(1.0, 0.92, 0.7)
	_lamp.shadow_enabled = true
	_lamp.position = ROOM.size / 2.0
	add_child(_lamp)

	for wall in _walls:
		var occluder := LightOccluder2D.new()
		var poly := OccluderPolygon2D.new()
		poly.polygon = PackedVector2Array([
			wall.position, Vector2(wall.end.x, wall.position.y),
			wall.end, Vector2(wall.position.x, wall.end.y)])
		occluder.occluder = poly
		add_child(occluder)

	var label := Label.new()
	label.position = Vector2(12, 8)
	label.text = "BACKROOMS SURVIVOR - Godot port (pipeline demo)\nbuild %s  %s" % [
		Patcher.read_info().get("build", 0), Patcher.read_info().get("sha", "")]
	var layer := CanvasLayer.new()  # HUD ignores the darkening CanvasModulate
	layer.add_child(label)
	add_child(layer)


func _process(_delta: float) -> void:
	# Mouse on desktop; touch is emulated as mouse on Android.
	_lamp.global_position = get_global_mouse_position()


func _draw() -> void:
	for y in range(0, int(ROOM.size.y), TILE):
		for x in range(0, int(ROOM.size.x), TILE):
			var shade := 0.34 if ((x / TILE + y / TILE) % 2 == 0) else 0.30
			draw_rect(Rect2(x, y, TILE, TILE), Color(shade, shade * 0.93, shade * 0.62))
	for wall in _walls:
		draw_rect(wall, Color(0.45, 0.42, 0.36))


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
