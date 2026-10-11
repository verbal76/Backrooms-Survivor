class_name ChunkView
extends Node2D
## Draws one map chunk (floor, walls, void) and registers light occluders for its walls.

const TILE := 52
const FLOOR_TEX := preload("res://assets/third_party/screaming_brain_horror_textures/256x256/Floor/Horror_Floor_03-256x256.png")
const WALL_TEX := preload("res://assets/third_party/screaming_brain_horror_textures/256x256/Wall/Horror_Wall_04-256x256.png")

var _map: WorldMap
var _cx: int
var _cy: int


func setup(map: WorldMap, cx: int, cy: int) -> void:
	_map = map
	_cx = cx
	_cy = cy
	position = Vector2(cx, cy) * WorldMap.CHUNK * TILE
	_build_occluders()
	queue_redraw()


func _draw() -> void:
	var n := WorldMap.CHUNK
	for ty in n:
		for tx in n:
			var v := _map.get_tile(_cx * n + tx, _cy * n + ty)
			var r := Rect2(tx * TILE, ty * TILE, TILE, TILE)
			match v:
				WorldMap.FLOOR:
					draw_texture_rect(FLOOR_TEX, r, false)
				WorldMap.WALL:
					draw_texture_rect(WALL_TEX, r, false)
				_:
					draw_rect(r, Color.BLACK)


func _build_occluders() -> void:
	var n := WorldMap.CHUNK
	for ty in n:
		var run_start := -1
		for tx in range(n + 1):
			var is_wall := tx < n and _map.get_tile(_cx * n + tx, _cy * n + ty) == WorldMap.WALL
			if is_wall and run_start < 0:
				run_start = tx
			elif not is_wall and run_start >= 0:
				_add_occluder(Rect2(run_start * TILE, ty * TILE, (tx - run_start) * TILE, TILE))
				run_start = -1


func _add_occluder(r: Rect2) -> void:
	var o := LightOccluder2D.new()
	var p := OccluderPolygon2D.new()
	p.polygon = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	o.occluder = p
	add_child(o)
