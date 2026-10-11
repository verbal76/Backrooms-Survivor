extends RefCounted
## Cheap tile BFS used by enemies that lose line of sight in the maze. Not in the Lua (which only has local
## wall-sliding steering); this makes hunters actually navigate around walls and through doors.

const NEIGHBORS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


## Grid line-of-sight (same sampling as enemies.lua hasLOS).
static func has_los(map: WorldMap, a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var steps := int(ceilf(d.length() * 2.5))
	if steps < 1:
		return true
	for i in range(1, steps + 1):
		var p := a + d * (float(i) / steps)
		if map.is_solid(p.x, p.y):
			return false
	return true


## Returns the tile-unit point the enemy should walk toward to reach `to` (or Vector2.INF when no route).
static func next_waypoint(map: WorldMap, from: Vector2, to: Vector2, max_nodes := 900) -> Vector2:
	var start := Vector2i(floori(from.x), floori(from.y))
	var goal := Vector2i(floori(to.x), floori(to.y))
	if start == goal:
		return to
	var parent := {start: start}
	var queue: Array[Vector2i] = [start]
	var head := 0
	var best := start
	var best_d := absi(start.x - goal.x) + absi(start.y - goal.y)
	var found := false
	while head < queue.size() and queue.size() < max_nodes:
		var cur: Vector2i = queue[head]
		head += 1
		if cur == goal:
			found = true
			break
		for n in NEIGHBORS:
			var nx: Vector2i = cur + n
			if parent.has(nx) or map.get_tile(nx.x, nx.y) != WorldMap.FLOOR:
				continue
			parent[nx] = cur
			queue.append(nx)
			var dd := absi(nx.x - goal.x) + absi(nx.y - goal.y)
			if dd < best_d:
				best_d = dd
				best = nx
	var end := goal if found else best
	if end == start:
		return Vector2.INF
	# rebuild path start -> end
	var path: Array[Vector2i] = []
	var c := end
	while c != start:
		path.append(c)
		c = parent[c]
	path.reverse()
	# string-pull: furthest of the first few nodes still visible from `from`
	var pick := Vector2(path[0].x + 0.5, path[0].y + 0.5)
	for i in range(mini(path.size(), 10)):
		var p := Vector2(path[i].x + 0.5, path[i].y + 0.5)
		if has_los(map, from, p):
			pick = p
		else:
			break
	return pick
