class_name ChunkView
extends Node2D
## Draws one map chunk (floor, walls, void) and registers light occluders for its walls.
##
## Rendering is built to be cheap on phones: floor and wall tiles are drawn as horizontal *runs* (one draw
## command per run, textured with a repeating, world-aligned texture so chunks join seamlessly), then one
## stretched 48x48 "shade map" (linear filtered) adds baseboard shadow, wall depth and dirt tint, then a few
## edge lines and water-stain decals. Everything is retained (no per-frame redraw).
##
## Textures: the Lua used world_assets/carpet-tile.jpg (grey chequer) + wood_grain.jpg. For a Backrooms read
## we use the SBS yellowish carpet (Floor_04) for floors and the beige woven wallpaper (Wall_03) for walls,
## both tinted warm; the originals stay in assets/textures/ for reference.

const TILE := 52
const TEX_TILES := 4                       # texture covers 4x4 tiles = 208 px; 48*52 is a multiple of 208
const TEX_PX := TILE * TEX_TILES
const FLOOR_SRC := preload("res://assets/third_party/screaming_brain_horror_textures/256x256/Floor/Horror_Floor_04-256x256.png")
const WALL_SRC := preload("res://assets/third_party/screaming_brain_horror_textures/256x256/Wall/Horror_Wall_03-256x256.png")
const STAIN_A := preload("res://assets/third_party/screaming_brain_horror_textures/256x256/Stains/Horror_Stain_04-256x256.png")
const STAIN_B := preload("res://assets/third_party/screaming_brain_horror_textures/256x256/Stains/Horror_Stain_05-256x256.png")

const FLOOR_TINT := Color(1.0, 0.88, 0.52)
const WALL_TINT := Color(1.0, 0.92, 0.68)
const EDGE_DARK := Color(0.05, 0.03, 0.0, 0.7)
const EDGE_LIGHT := Color(1.0, 0.95, 0.72, 0.30)

static var _floor_tex: ImageTexture
static var _wall_tex: ImageTexture
static var _noise: FastNoiseLite
static var _noise2: FastNoiseLite

var _map: WorldMap
var _cx: int
var _cy: int
var _shade: ImageTexture


static func _prepare() -> void:
	if _floor_tex:
		return
	var f := FLOOR_SRC.get_image()
	f.convert(Image.FORMAT_RGBA8)
	f.resize(TEX_PX, TEX_PX, Image.INTERPOLATE_LANCZOS)
	_floor_tex = ImageTexture.create_from_image(f)
	var w := WALL_SRC.get_image()
	w.convert(Image.FORMAT_RGBA8)
	w.resize(TEX_PX, TEX_PX, Image.INTERPOLATE_LANCZOS)
	_wall_tex = ImageTexture.create_from_image(w)
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.11
	_noise.seed = 1337
	_noise2 = FastNoiseLite.new()
	_noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise2.frequency = 0.45
	_noise2.seed = 77


func setup(map: WorldMap, cx: int, cy: int) -> void:
	_prepare()
	_map = map
	_cx = cx
	_cy = cy
	position = Vector2(cx, cy) * WorldMap.CHUNK * TILE
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_shade = _build_shade()
	_build_occluders()
	queue_redraw()


func _t(tx: int, ty: int) -> int:
	return _map.get_tile(_cx * WorldMap.CHUNK + tx, _cy * WorldMap.CHUNK + ty)


func _draw() -> void:
	var n := WorldMap.CHUNK
	# ---- floor + wall runs (textured, world aligned) ----
	for kind in [WorldMap.FLOOR, WorldMap.WALL]:
		var tex := _floor_tex if kind == WorldMap.FLOOR else _wall_tex
		var tint := FLOOR_TINT if kind == WorldMap.FLOOR else WALL_TINT
		for ty in n:
			var run := -1
			for tx in range(n + 1):
				var m: bool = tx < n and _t(tx, ty) == kind
				if m and run < 0:
					run = tx
				elif not m and run >= 0:
					var dst := Rect2(run * TILE, ty * TILE, (tx - run) * TILE, TILE)
					var src := Rect2((run * TILE) % TEX_PX, (ty * TILE) % TEX_PX, dst.size.x, TILE)
					draw_texture_rect_region(tex, dst, src, tint)
					run = -1

	# ---- shade map: baseboard shadow, wall depth, dirt (smooth, 1 px per tile) ----
	draw_texture_rect(_shade, Rect2(0, 0, n * TILE, n * TILE), false)

	# ---- water stains on the carpet ----
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(_cx, _cy)) ^ 0x51ED
	for i in 4:
		var tx := rng.randi_range(2, n - 3)
		var ty := rng.randi_range(2, n - 3)
		var sz := rng.randf_range(1.4, 3.2) * TILE
		var a := rng.randf_range(0.10, 0.22)
		var tex_s := STAIN_A if rng.randf() < 0.5 else STAIN_B
		var rot := rng.randf() * TAU
		if _t(tx, ty) == WorldMap.FLOOR and _t(tx + 1, ty) == WorldMap.FLOOR and _t(tx, ty + 1) == WorldMap.FLOOR:
			draw_set_transform(Vector2(tx + 0.5, ty + 0.5) * TILE, rot, Vector2.ONE)
			draw_texture_rect(tex_s, Rect2(-sz * 0.5, -sz * 0.5, sz, sz), false, Color(0.55, 0.42, 0.2, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# ---- wall edge lines where a wall meets floor (merged into runs) ----
	for ty in n:
		_edge_runs_h(ty, -1)
		_edge_runs_h(ty, 1)
	for tx in n:
		_edge_runs_v(tx, -1)
		_edge_runs_v(tx, 1)


## Horizontal edge on the top (dir=-1) or bottom (dir=+1) of wall tiles in row ty whose neighbour is floor.
func _edge_runs_h(ty: int, dir: int) -> void:
	var n := WorldMap.CHUNK
	var run := -1
	for tx in range(n + 1):
		var m: bool = tx < n and _t(tx, ty) == WorldMap.WALL and _t(tx, ty + dir) == WorldMap.FLOOR
		if m and run < 0:
			run = tx
		elif not m and run >= 0:
			var w := (tx - run) * TILE
			var x := run * TILE
			var y_edge := ty * TILE if dir < 0 else (ty + 1) * TILE
			if dir < 0:
				draw_rect(Rect2(x, y_edge, w, 3), EDGE_DARK)
				draw_rect(Rect2(x, y_edge + 3, w, 2), EDGE_LIGHT)
			else:
				draw_rect(Rect2(x, y_edge - 3, w, 3), EDGE_DARK)
				draw_rect(Rect2(x, y_edge - 5, w, 2), EDGE_LIGHT)
			run = -1


func _edge_runs_v(tx: int, dir: int) -> void:
	var n := WorldMap.CHUNK
	var run := -1
	for ty in range(n + 1):
		var m: bool = ty < n and _t(tx, ty) == WorldMap.WALL and _t(tx + dir, ty) == WorldMap.FLOOR
		if m and run < 0:
			run = ty
		elif not m and run >= 0:
			var h := (ty - run) * TILE
			var y := run * TILE
			var x_edge := tx * TILE if dir < 0 else (tx + 1) * TILE
			if dir < 0:
				draw_rect(Rect2(x_edge, y, 3, h), EDGE_DARK)
				draw_rect(Rect2(x_edge + 3, y, 2, h), EDGE_LIGHT)
			else:
				draw_rect(Rect2(x_edge - 3, y, 3, h), EDGE_DARK)
				draw_rect(Rect2(x_edge - 5, y, 2, h), EDGE_LIGHT)
			run = -1


## One pixel per tile; drawn stretched with linear filtering so values become smooth gradients.
func _build_shade() -> ImageTexture:
	var n := WorldMap.CHUNK
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for ty in n:
		for tx in n:
			var wx := _cx * n + tx
			var wy := _cy * n + ty
			var t := _t(tx, ty)
			var shadow := 0.0
			var tint := Color(0, 0, 0, 0)
			if t == WorldMap.WALL:
				# thick wall masses read darker towards the middle; boundary tiles stay brighter
				var floors := 0
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if _t(tx + d.x, ty + d.y) == WorldMap.FLOOR:
						floors += 1
				shadow = 0.50 if floors == 0 else 0.10
			elif t == WorldMap.FLOOR:
				# baseboard shadow: floor next to walls is darker (gradient to the floor centre)
				var adj := 0
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if _t(tx + d.x, ty + d.y) != WorldMap.FLOOR:
						adj += 1
				var diag := 0
				for d in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
					if _t(tx + d.x, ty + d.y) != WorldMap.FLOOR:
						diag += 1
				shadow = minf(0.42, adj * 0.14 + diag * 0.03)
				# dirt / wear: low-frequency blotches + per-tile jitter
				var nv := _noise.get_noise_2d(wx, wy)
				var jit := (_noise2.get_noise_2d(wx, wy)) * 0.5
				var v := nv + jit * 0.5
				if v > 0.12:
					tint = Color(1.0, 0.92, 0.55, minf(0.14, (v - 0.12) * 0.35))
				elif v < -0.05:
					tint = Color(0.22, 0.14, 0.04, minf(0.30, (-0.05 - v) * 0.8))
			# composite shadow (black) and tint into one straight-alpha pixel
			var a_t := tint.a
			var a := 1.0 - (1.0 - shadow) * (1.0 - a_t)
			var col := Color(0, 0, 0, a)
			if a > 0.001 and a_t > 0.0:
				var wgt := a_t * (1.0 - shadow) / a
				col = Color(tint.r * wgt, tint.g * wgt, tint.b * wgt, a)
			img.set_pixel(tx, ty, col)
	return ImageTexture.create_from_image(img)


func _build_occluders() -> void:
	## Wall runs per row. Wall tiles with no floor in their 8-neighbourhood are interior and skipped
	## (light can never reach them), which cuts the occluder count a lot in thick wall masses.
	## Horizontal runs that repeat on consecutive rows are merged into one taller rectangle (1-tile-wide vertical
	## walls used to cost one occluder per row), which roughly halves the occluder count the light has to cull.
	var n := WorldMap.CHUNK
	var active := {}                      # Vector2i(x0, x1) -> first row of the open rectangle
	for ty in range(n + 1):
		var next_active := {}
		if ty < n:
			var run_start := -1
			for tx in range(n + 1):
				var is_wall: bool = tx < n and _t(tx, ty) == WorldMap.WALL and _touches_floor(tx, ty)
				if is_wall and run_start < 0:
					run_start = tx
				elif not is_wall and run_start >= 0:
					var key := Vector2i(run_start, tx)
					next_active[key] = active.get(key, ty)
					run_start = -1
		for key in active:
			if not next_active.has(key):
				_add_occluder(Rect2(key.x * TILE, active[key] * TILE, (key.y - key.x) * TILE, (ty - active[key]) * TILE))
		active = next_active


func _touches_floor(tx: int, ty: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if (dx != 0 or dy != 0) and _t(tx + dx, ty + dy) == WorldMap.FLOOR:
				return true
	return false


func _add_occluder(r: Rect2) -> void:
	var o := LightOccluder2D.new()
	var p := OccluderPolygon2D.new()
	p.polygon = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	o.occluder = p
	add_child(o)
