class_name WorldMap
extends RefCounted
## Port of map.lua: infinite chunk-based Backrooms generator. Same layout rules and
## the same LCG random numbers, so a chunk looks like the LÖVE version for a given seed.

const CHUNK := 48
const FLOOR := 0
const WALL := 1
const VOID := 2

var chunks := {}          # Vector2i -> PackedByteArray (CHUNK*CHUNK)
var chest_rooms := []     # {pos: Vector2, looted: bool}
var seed_base := 0
var new_chunks: Array[Vector2i] = []   # queue of freshly generated chunks (views, item spawns)


func _init(p_seed: int = -1) -> void:
	seed_base = randi_range(1, 999999) if p_seed < 0 else p_seed


# ---- seeded LCG, identical maths to Map:makeRng ----
class Rng:
	var s: int
	func _init(p_seed: int) -> void:
		s = p_seed
	func _step() -> void:
		s = posmod(s * 1103515245 + 12345, 2147483648)
	func f() -> float:
		_step()
		return float(s) / 2147483648.0
	func range_i(a: int, b: int) -> int:
		_step()
		return a + (int(s / 65536) % (b - a + 1))


func _chunk_seed(cx: int, cy: int) -> int:
	return seed_base + cx * 73856093 + cy * 19349669


func ensure_around(tile: Vector2, radius_tiles: int = 32) -> void:
	var cx := floori(tile.x / CHUNK)
	var cy := floori(tile.y / CHUNK)
	var rc := maxi(1, ceili(float(radius_tiles) / CHUNK) + 1)
	for yy in range(cy - rc, cy + rc + 1):
		for xx in range(cx - rc, cx + rc + 1):
			ensure_chunk(xx, yy)


func drain_new_chunks() -> Array[Vector2i]:
	var list := new_chunks
	new_chunks = []
	return list


func ensure_chunk(cx: int, cy: int) -> bool:
	var key := Vector2i(cx, cy)
	if chunks.has(key):
		return false
	chunks[key] = _generate(cx, cy)
	new_chunks.append(key)
	return true


func get_tile(x: int, y: int) -> int:
	var cx := floori(float(x) / CHUNK)
	var cy := floori(float(y) / CHUNK)
	var c = chunks.get(Vector2i(cx, cy))
	if c == null:
		return WALL
	return c[(y - cy * CHUNK) * CHUNK + (x - cx * CHUNK)]


func set_tile(x: int, y: int, v: int) -> void:
	var cx := floori(float(x) / CHUNK)
	var cy := floori(float(y) / CHUNK)
	var c = chunks.get(Vector2i(cx, cy))
	if c != null:
		c[(y - cy * CHUNK) * CHUNK + (x - cx * CHUNK)] = v


func is_solid(x: float, y: float) -> bool:
	return get_tile(floori(x), floori(y)) != FLOOR


func find_spawn() -> Vector2:
	ensure_chunk(0, 0)
	var mid := CHUNK / 2
	for r in range(0, CHUNK - 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) == r or absi(dy) == r:
					if get_tile(mid + dx, mid + dy) == FLOOR:
						return Vector2(mid + dx + 0.5, mid + dy + 0.5)
	return Vector2(mid + 0.5, mid + 0.5)


func _generate(cx: int, cy: int) -> PackedByteArray:
	var t := PackedByteArray()
	t.resize(CHUNK * CHUNK)
	t.fill(WALL)
	var rng := Rng.new(_chunk_seed(cx, cy))

	var carve_rect := func(x0: int, y0: int, w: int, h: int) -> void:
		for y in range(y0, y0 + h):
			for x in range(x0, x0 + w):
				if x >= 0 and x < CHUNK and y >= 0 and y < CHUNK:
					t[y * CHUNK + x] = FLOOR

	var mid := CHUNK / 2
	var hall_w := 3
	var row_rng := Rng.new(seed_base + cy * 19349669 + 999983)
	var ya := clampi(int(CHUNK * 0.30) + row_rng.range_i(-3, 3), 5, CHUNK - 16)
	var yb := clampi(int(CHUNK * 0.68) + row_rng.range_i(-3, 3), ya + 14, CHUNK - 5)
	var hx0 := 2
	var hx1 := CHUNK - 3
	carve_rect.call(hx0, ya, hx1 - hx0, hall_w)
	carve_rect.call(hx0, yb, hx1 - hx0, hall_w)

	# vertical cross-connectors
	var cross_count := 2 + int(rng.f() * 2)
	var used_x: Array[int] = []
	for i in cross_count:
		var x2 := clampi(8 + int(rng.f() * (CHUNK - 16)), 5, CHUNK - 6)
		var too_close := false
		for ux in used_x:
			if absi(x2 - ux) < 6:
				too_close = true
				break
		if not too_close:
			used_x.append(x2)
			carve_rect.call(x2, ya + hall_w, 2, yb - (ya + hall_w))

	# rooms in three rows
	var rooms := []
	var row_defs := [[2, ya - 2, ya], [ya + hall_w + 1, yb - 2, ya], [yb + hall_w + 1, CHUNK - 3, yb]]
	var zones_x := 4
	for rd in row_defs:
		var ry_min: int = rd[0]
		var ry_max: int = rd[1]
		var hall_y: int = rd[2]
		var avail_h := ry_max - ry_min
		if avail_h >= 6:
			var zone_w := (CHUNK - 4) / zones_x
			var cols := [0, 1, 2, 3]
			for i in range(4, 1, -1):
				var j := 1 + int(rng.f() * i)
				var tmp = cols[i - 1]
				cols[i - 1] = cols[j - 1]
				cols[j - 1] = tmp
			var rooms_in_row := 2 + int(rng.f() * 2)
			for c in range(mini(rooms_in_row, zones_x)):
				var zox := 2 + int(cols[c]) * zone_w
				var rw := 6 + int(rng.f() * 5)
				var rh := clampi(4 + int(rng.f() * 4), 4, avail_h - 1)
				var mx := maxi(0, zone_w - rw - 1)
				var rx := clampi(zox + int(rng.f() * (mx + 1)), 2, CHUNK - rw - 2)
				var ry := clampi(ry_min + int(rng.f() * (avail_h - rh)), 2, CHUNK - rh - 2)
				carve_rect.call(rx, ry, rw, rh)
				var rcx := rx + rw / 2
				var rcy := ry + rh / 2
				rooms.append({"cx": rcx, "cy": rcy, "rw": rw, "rh": rh})
				var sy0 := mini(rcy, hall_y)
				var sy1 := maxi(rcy, hall_y)
				carve_rect.call(rcx - 1, sy0, 2, sy1 - sy0 + hall_w)

	# chest room = biggest room
	if rooms.size() > 0:
		var best = rooms[0]
		for r in rooms:
			if r.rw * r.rh > best.rw * best.rh:
				best = r
		chest_rooms.append({"pos": Vector2(cx * CHUNK + best.cx, cy * CHUNK + best.cy), "looted": false})

	# edge seam openings (deterministic per shared edge)
	var openings := func(dir: String) -> Array[int]:
		var ax: int
		var ay: int
		var tag: int
		match dir:
			"W": ax = cx - 1; ay = cy; tag = 1
			"E": ax = cx; ay = cy; tag = 1
			"N": ax = cx; ay = cy - 1; tag = 2
			_: ax = cx; ay = cy; tag = 2
		var r := Rng.new(seed_base + ax * 83492791 + ay * 29765729 + tag * 911)
		var count := 1 + int(r.f() * 2)
		var pos: Array[int] = []
		for i in count:
			pos.append(4 + int(r.f() * (CHUNK - 10)))
		return pos

	for y in openings.call("W"):
		var near := ya if absi(clampi(y, 2, CHUNK - 4) - ya) < absi(clampi(y, 2, CHUNK - 4) - yb) else yb
		carve_rect.call(0, near, 3, hall_w)
	for y in openings.call("E"):
		var near2 := ya if absi(clampi(y, 2, CHUNK - 4) - ya) < absi(clampi(y, 2, CHUNK - 4) - yb) else yb
		carve_rect.call(CHUNK - 3, near2, 3, hall_w)
	for x in openings.call("N"):
		carve_rect.call(clampi(x, 2, CHUNK - 4), 0, 2, ya + hall_w)
	for x in openings.call("S"):
		carve_rect.call(clampi(x, 2, CHUNK - 4), yb, 2, CHUNK - yb)

	# origin spawn pad
	if cx == 0 and cy == 0:
		carve_rect.call(mid - 2, mid - 2, 5, 5)
		var nh := ya if absi(mid - ya) < absi(mid - yb) else yb
		carve_rect.call(mid - 1, mini(mid, nh), 2, absi(nh - mid) + hall_w)

	# keep a 1-tile wall border, everything else becomes void
	var src := t.duplicate()
	for y in CHUNK:
		for x in CHUNK:
			if src[y * CHUNK + x] != WALL:
				continue
			var adj := false
			if x > 0 and src[y * CHUNK + x - 1] == FLOOR: adj = true
			if x < CHUNK - 1 and src[y * CHUNK + x + 1] == FLOOR: adj = true
			if y > 0 and src[(y - 1) * CHUNK + x] == FLOOR: adj = true
			if y < CHUNK - 1 and src[(y + 1) * CHUNK + x] == FLOOR: adj = true
			if not adj:
				t[y * CHUNK + x] = VOID
	return t
