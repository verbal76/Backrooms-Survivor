class_name MapRaster
extends RefCounted
## Renders the tiles around the player into a tiny one-pixel-per-tile L8 texture (cached) for the
## minimap / tactical map. Drawn with nearest filtering and a sub-tile offset so it scrolls smoothly.
## Reads WorldMap chunk arrays directly (bulk slice copies), so refreshes are cheap.

const FLOOR_V := 255
const WALL_V := 56
const VOID_V := 17
## Tint applied when drawing (floor colour of the Lua map; walls/void are darker shades of it).
const TINT := Color(0.45, 0.38, 0.2)

var tex: ImageTexture
var half := 20                 # tiles from the centre to each edge
var interval := 0.15           # min seconds between refreshes
var _img: Image
var _origin := Vector2i.ZERO   # tile coordinate of pixel (0, 0)
var _last_tile := Vector2i(-999999, -999999)
var _last_time := -10.0
var _cache := {}               # chunk key -> mapped PackedByteArray
var _void_row := PackedByteArray()


func setup(p_half: int, p_interval := 0.15) -> void:
	half = p_half
	interval = p_interval
	var n := half * 2 + 1
	_img = Image.create(n, n, false, Image.FORMAT_L8)
	tex = ImageTexture.create_from_image(_img)
	_void_row.resize(n)
	_void_row.fill(VOID_V)
	_last_tile = Vector2i(-999999, -999999)


func _mapped(map: WorldMap, key: Vector2i, now: float) -> Variant:
	var hit = _cache.get(key)
	if hit != null and now - hit.t < 4.0:      # per-chunk expiry: walls can be destroyed
		return hit.data
	if not map.chunks.has(key):
		return null
	var src: PackedByteArray = map.chunks[key]
	var out := PackedByteArray()
	out.resize(src.size())
	for i in src.size():
		out[i] = FLOOR_V if src[i] == WorldMap.FLOOR else WALL_V
	_cache[key] = {"data": out, "t": now + randf() * 2.0}
	return out


func refresh(map: WorldMap, center: Vector2, now: float, force := false) -> void:
	var ct := Vector2i(floori(center.x), floori(center.y))
	if not force and ct == _last_tile and now - _last_time < 1.0:
		return
	if not force and now - _last_time < interval:
		return
	_last_tile = ct
	_last_time = now
	var n := half * 2 + 1
	_origin = Vector2i(ct.x - half, ct.y - half)
	var cs: int = WorldMap.CHUNK
	var data := PackedByteArray()
	for py in n:
		var ty := _origin.y + py
		var cy := floori(float(ty) / cs)
		var tx := _origin.x
		var end_x := _origin.x + n
		while tx < end_x:
			var cx := floori(float(tx) / cs)
			var seg_end := mini((cx + 1) * cs, end_x)
			var seg := seg_end - tx
			var mapped = _mapped(map, Vector2i(cx, cy), now)
			if mapped == null:
				data.append_array(_void_row.slice(0, seg))
			else:
				var start: int = (ty - cy * cs) * cs + (tx - cx * cs)
				data.append_array(mapped.slice(start, start + seg))
			tx = seg_end
	_img.set_data(n, n, false, Image.FORMAT_L8, data)
	tex.update(_img)


## Draw the map into dst; the player (at `center`) ends up in the middle of dst.
func draw(ci: CanvasItem, dst: Rect2, center: Vector2, alpha := 1.0) -> void:
	var off := center - (Vector2(_origin) + Vector2(half, half))
	off = off.clamp(Vector2.ZERO, Vector2.ONE)
	var src := Rect2(off, Vector2(half * 2, half * 2))
	ci.draw_texture_rect_region(tex, dst, src, Color(TINT.r, TINT.g, TINT.b, alpha))


## Pixels per tile when the map is drawn into a square of side `side`.
func scale_for(side: float) -> float:
	return side / float(half * 2)
