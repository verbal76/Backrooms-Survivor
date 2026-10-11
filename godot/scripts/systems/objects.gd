extends Node
## World objects system (`game.objects`): pickups, chaos orbs, props, military chests, exit portal, bombs.
## Port of items.lua, orbs.lua, props.lua, bomb.lua and the related parts of main.lua
## (SEC 11 drops, SEC 15 drawing, per-chunk spawning, chest + portal logic).
## See godot/ARCHITECTURE.md for the system contract; extra API is listed in the report / below.
##
## Public API (besides setup/tick/reset_run):
##   spawn_drop(tile_pos, kind := "", from_enemy := false)  kind "" = roll, "orb" = chaos orb, or an item kind
##   spawn_orb(tile_pos, is_buff := -1)                     -1 = random 60/40
##   use_bomb() -> bool, bomb_count, bomb_max(), bomb_radius_mult, get_bomb_radius()
##   items / orbs / props : Array of nodes (tile_pos, kind...) for minimap / HUD
##   chests() -> Array[{pos, looted}], portal -> {pos, active} (empty when not spawned)
##   active_effects : Array of {text, remaining, duration, is_good} (orb timed buffs, for the HUD)
##   portal_decline() : UI calls this when the player picks STAY (portal off, "living legend")
##   signals: message(text, color), orb_effect(text, color, is_good), chest_opened(tile_pos), portal_spawned(tile_pos)

signal message(text: String, color: Color)
signal orb_effect(text: String, color: Color, is_good: bool)
signal chest_opened(tile_pos: Vector2)
signal portal_spawned(tile_pos: Vector2)

# bomb.lua
const BOMB_BASE_RADIUS := 3.0
const BOMB_DAMAGE := 50
const BOMB_KNOCKBACK := 8.0
const BOMB_COOLDOWN := 1.0
const BOMB_NOISE := 90.0
const AMMO_PER_PICKUP := 25
const STAMINA_DRINK := 30.0
const CHEST_SPREAD := 2.5
const PORTAL_MSG_INTERVAL := 3.0
const CHUNK := 48

const MSG_GOOD := Color(0.3, 1.0, 0.3)
const MSG_BAD := Color(1.0, 0.3, 0.3)

var game
var rng := RandomNumberGenerator.new()
var root: Node2D
var difficulty := 2             # 1 easy .. 4 nightmare; read from game.difficulty if the integrator adds it
var drop_scale := 0.8
var chunks_since_weapon := 0

var items: Array = []           # WorldItem nodes
var orbs: Array = []            # WorldOrb nodes
var props: Array = []           # WorldProp nodes
var active_effects: Array = []
var portal := {}                # {pos, active, node}
var living_legend := false
var handle_consumables := true  # set false if another system reacts to use_water/use_bandage/use_food

var bomb_count := 1
var bomb_radius_mult := 1.0
var bomb_cooldown := 0.0

var _populated := {}
var _solid_tiles: Dictionary = {}       # Vector2i -> true (tiles we turned into walls)
var _chest_nodes := {}                  # room index -> ChestMarker
var _guards: Array = []
var _slow_t := 0.0
var _chest_t := 0.0
var _portal_msg_cd := 0.0
var _portal_armed := true
var _live_collect := 0


func setup(g) -> void:
	game = g
	rng.randomize()
	root = Node2D.new()
	root.name = "Objects"
	game.world.add_child(root)
	if game.player and game.player.get_parent() == game.world:
		game.world.move_child(root, game.player.get_index())   # pickups draw under the player
	game.enemy_killed.connect(_on_enemy_killed)
	game.chunk_spawned.connect(_on_chunk_spawned)
	_refresh_difficulty()


func _refresh_difficulty() -> void:
	var d = game.get("difficulty")
	if d is int:
		difficulty = clampi(d, 1, 4)
	drop_scale = maxf(Loot.DIFF_MIN_SCALE, 1.0 - (difficulty - 1) * Loot.DIFF_DROP_REDUCTION)


# =====================================================================================
#  run lifecycle
# =====================================================================================

func reset_run() -> void:
	_refresh_difficulty()
	for n in items + orbs + props:
		if is_instance_valid(n):
			n.queue_free()
	items.clear()
	orbs.clear()
	props.clear()
	for k in _chest_nodes:
		if is_instance_valid(_chest_nodes[k]):
			_chest_nodes[k].queue_free()
	_chest_nodes.clear()
	if portal.has("node") and is_instance_valid(portal.node):
		portal.node.queue_free()
	portal = {}
	_guards.clear()
	# give back the tiles our solid props took (the map outlives a run)
	for t in _solid_tiles:
		game.map.set_tile(t.x, t.y, WorldMap.FLOOR)
	_solid_tiles.clear()
	for room in game.map.chest_rooms:
		room.looted = false
	active_effects.clear()   # weapons/enemies/player systems reset their own modifiers on reset_run
	living_legend = false
	bomb_count = 1
	bomb_radius_mult = 1.0
	bomb_cooldown = 0.0
	chunks_since_weapon = 0
	_portal_armed = true
	_portal_msg_cd = 0.0
	_populated.clear()
	# the map persists between runs: re-populate every chunk that already exists
	for key in game.map.chunks:
		_populate_chunk(key.x, key.y)


func tick(dt: float) -> void:
	var p: Player = game.player
	_tick_items(dt, p)
	_tick_orbs(dt, p)
	_tick_effects(dt)
	if bomb_cooldown > 0.0:
		bomb_cooldown -= dt
	if game.input:
		if game.input.just("bomb"):
			use_bomb()
		if handle_consumables:
			_handle_consumables(p)
	_chest_t += dt
	if _chest_t >= 0.2:
		_chest_t = 0.0
		_tick_chests(p)
	_tick_portal(dt, p)
	_slow_t += dt
	if _slow_t >= 0.5:
		_slow_t = 0.0
		_cull(p)


# =====================================================================================
#  per-chunk spawning (items.lua spawnOnMap + main.lua "freshly generated chunks")
# =====================================================================================

func _on_chunk_spawned(cx: int, cy: int) -> void:
	_populate_chunk(cx, cy)


func _populate_chunk(cx: int, cy: int) -> void:
	var key := Vector2i(cx, cy)
	if _populated.has(key):
		return
	_populated[key] = true
	var pt: Vector2 = game.player.tile_pos
	var in_player_chunk := floori(pt.x / CHUNK) == cx and floori(pt.y / CHUNK) == cy

	# props first: solid ones claim tiles (so items/orbs never land inside them).
	# Never in the player's chunk: it could trap the player at spawn (same safety as the Lua).
	if not in_player_chunk:
		_spawn_props(cx, cy)

	var count := floori(rng.randi_range(Loot.CHUNK_ITEMS_MIN, Loot.CHUNK_ITEMS_MAX) * drop_scale)
	for i in count:
		var pos = random_open_in_chunk(cx, cy)
		if pos != null:
			_make_item(_roll_kind(), pos)
	# bad luck protection: force a weapon if too many chunks passed without one
	chunks_since_weapon += 1
	if chunks_since_weapon >= Loot.BAD_LUCK_CHUNKS:
		var wp = random_open_in_chunk(cx, cy)
		if wp != null:
			_make_item("weapon", wp, rng.randi_range(Loot.FIRST_DROP_WEAPON, Loot.WEAPONS.size() - 1))
			chunks_since_weapon = 0
	for i in rng.randi_range(Loot.CHUNK_ORBS_MIN, Loot.CHUNK_ORBS_MAX):
		var op = random_open_in_chunk(cx, cy)
		if op != null:
			spawn_orb(op)


## Map:randomOpenInChunk: random floor tile centre in the chunk (null if none found in 50 tries).
func random_open_in_chunk(cx: int, cy: int):
	if not game.map.chunks.has(Vector2i(cx, cy)):
		return null
	for _i in 50:
		var lx := rng.randi_range(2, CHUNK - 3)
		var ly := rng.randi_range(2, CHUNK - 3)
		var x := cx * CHUNK + lx
		var y := cy * CHUNK + ly
		if game.map.get_tile(x, y) == WorldMap.FLOOR:
			return Vector2(x + 0.5, y + 0.5)
	return null


func _spawn_props(cx: int, cy: int) -> void:
	var furn: Array = []
	var body: Array = []
	var clut: Array = []
	for d in Loot.PROP_DEFS:
		match d[5]:
			"furniture": furn.append(d)
			"body": body.append(d)
			"clutter": clut.append(d)
	for i in rng.randi_range(Loot.SPAWN_FURNITURE[0], Loot.SPAWN_FURNITURE[1]):
		_place_prop(furn[rng.randi() % furn.size()], cx, cy, float(rng.randi_range(0, 3)) * PI / 2.0)
	for i in rng.randi_range(Loot.SPAWN_BODIES[0], Loot.SPAWN_BODIES[1]):
		_place_prop(body[rng.randi() % body.size()], cx, cy, rng.randf() * 0.4 - 0.2, true)
	for i in rng.randi_range(Loot.SPAWN_CLUTTER[0], Loot.SPAWN_CLUTTER[1]):
		_place_prop(clut[rng.randi() % clut.size()], cx, cy, rng.randf() * TAU)


func _place_prop(def: Array, cx: int, cy: int, rot: float, bodyish := false) -> void:
	var pos = random_open_in_chunk(cx, cy)
	if pos == null:
		return
	var tile := Vector2i(floori(pos.x), floori(pos.y))
	if def[3] and not _can_block(tile):
		return     # would pinch a corridor (or sits on the portal): skip rather than trap the player
	var n := WorldProp.new()
	root.add_child(n)
	n.setup(def, pos, rot, game.TILE, bodyish and rng.randf() < 0.6, rng.randf() * TAU, 0.5 + rng.randf() * 1.5)
	if def[3]:
		game.map.set_tile(tile.x, tile.y, WorldMap.WALL)   # Map:markSolid
		_solid_tiles[tile] = true
		n.solid_tile = tile
	props.append(n)


## A solid prop may only go where all 8 neighbours are open floor and no other solid prop touches it,
## so props can never close a corridor. Also keeps the portal area clear.
func _can_block(t: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if game.map.get_tile(t.x + dx, t.y + dy) != WorldMap.FLOOR:
				return false
			if (dx != 0 or dy != 0) and _solid_tiles.has(Vector2i(t.x + dx, t.y + dy)):
				return false
	if portal.has("pos") and (Vector2(t) + Vector2(0.5, 0.5)).distance_to(portal.pos) < 4.0:
		return false
	var pt: Vector2 = game.player.tile_pos
	if Vector2(t).distance_to(pt) < 3.0:
		return false
	return true


# =====================================================================================
#  items (items.lua)
# =====================================================================================

func _roll_kind() -> String:
	var roll := rng.randf()
	for e in Loot.TYPE_THRESHOLDS:
		if roll < e[0]:
			return e[1]
	return "almond water"   # remaining 15%: fallback


func _kind_color(kind: String, weapon_id := -1) -> Color:
	if kind == "weapon" and weapon_id >= 0 and weapon_id < Loot.WEAPONS.size():
		return Loot.WEAPONS[weapon_id].color
	return Loot.COLORS.get(kind, Color.WHITE)


func _make_item(kind: String, pos: Vector2, weapon_id := -1) -> WorldItem:
	if kind == "weapon" and weapon_id < 0:
		weapon_id = rng.randi_range(Loot.FIRST_DROP_WEAPON, Loot.WEAPONS.size() - 1)
		chunks_since_weapon = 0   # a natural weapon drop resets the drought counter
	var it := WorldItem.new()
	root.add_child(it)
	it.setup(kind, pos, _kind_color(kind, weapon_id), game.TILE, weapon_id)
	items.append(it)
	return it


## Items:spawnDrop. kind "" rolls the drop table, "orb" makes a chaos orb. from_enemy applies the
## difficulty drop reduction like the Lua. Returns the node (or null if the difficulty roll skipped it).
func spawn_drop(tile_pos: Vector2, kind := "", from_enemy := false):
	if from_enemy and rng.randf() > drop_scale:
		return null
	if kind == "orb":
		return spawn_orb(tile_pos)
	var k := kind if kind != "" else _roll_kind()
	var it := _make_item(k, tile_pos)
	if from_enemy:
		var target := tile_pos + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.3, 0.8)
		if game.map.get_tile(floori(target.x), floori(target.y)) == WorldMap.FLOOR:
			it.tile_pos = target
		it.launch(tile_pos, 0.35, 18.0)
	return it


func spawn_orb(tile_pos: Vector2, buff := -1) -> WorldOrb:
	var o := WorldOrb.new()
	root.add_child(o)
	var is_buff := rng.randf() < Loot.ORB_BUFF_CHANCE if buff < 0 else buff == 1
	o.setup(tile_pos, is_buff, game.TILE)
	orbs.append(o)
	return o


func _tick_items(dt: float, p: Player) -> void:
	var i := items.size() - 1
	while i >= 0:
		var it: WorldItem = items[i]
		if not is_instance_valid(it):
			items.remove_at(i)
		elif it._fly_t >= 1.0:
			var d := p.tile_pos - it.tile_pos
			var dist := d.length()
			# light magnet: pickups slide the last stretch toward the player
			if dist < 1.5 and it.age > 0.5 and dist > 0.05:
				it.tile_pos += d / dist * (2.0 + (1.5 - dist) * 5.0) * dt
				dist = (p.tile_pos - it.tile_pos).length()
			if dist < Loot.PICKUP_RADIUS:
				_collect_item(it, p)
				items.remove_at(i)
		i -= 1


func _tick_orbs(dt: float, p: Player) -> void:
	var i := orbs.size() - 1
	while i >= 0:
		var o: WorldOrb = orbs[i]
		if not is_instance_valid(o):
			orbs.remove_at(i)
		elif not o.collected and (p.tile_pos - o.tile_pos).length_squared() < 900.0:   # far orbs idle (detect range is 3)
			o.step(dt, p.tile_pos, p.base_speed)
			if (p.tile_pos - o.tile_pos).length() < Loot.ORB_PICKUP_RADIUS and o.age > 0.15:
				_collect_orb(o, p)
				orbs.remove_at(i)
		i -= 1


func _collect_item(it: WorldItem, p: Player) -> void:
	var msg := _apply_item(it, p)
	var wp: Vector2 = it.position
	game.fx.burst(wp, "pickup")
	if it.kind == "weapon":
		game.audio.play("pickup_weapon", wp)
	elif it.kind == "bomb" or it.kind == "ammo":
		game.audio.play("pickup_heavy", wp)
	else:
		game.audio.play("pickup", wp)
	if not msg.is_empty():
		game.fx.float_text(wp + Vector2(0, -26), msg.text, msg.color)
		message.emit(msg.text, msg.color)
	it.collected = true
	it.set_process(false)
	var tw := it.create_tween().set_parallel(true)
	tw.tween_property(it, "position", p.position + Vector2(0, -8), 0.14).set_ease(Tween.EASE_IN)
	tw.tween_property(it, "scale", Vector2(0.2, 0.2), 0.14)
	tw.tween_property(it, "modulate:a", 0.0, 0.14)
	tw.chain().tween_callback(it.queue_free)


## Items:applyItem. Returns {text, color} (or {} when nothing to show).
func _apply_item(it: WorldItem, p: Player) -> Dictionary:
	var w = game.weapons
	match it.kind:
		"bandage":
			p.bandages += 1
			return {"text": "+1 Bandage", "color": Color(0.3, 1, 0.3)}
		"almond water":
			p.almond_water += 1
			return {"text": "+1 Almond Water", "color": Color(0.3, 0.8, 1)}
		"food":
			p.stamina = minf(p.max_stamina, p.stamina + Player.S.food_stamina)
			p.sanity = minf(p.max_sanity, p.sanity + Player.S.food_sanity)
			return {"text": "+%d Stamina +%d Sanity" % [Player.S.food_stamina, Player.S.food_sanity], "color": Color(0.8, 0.6, 0.2)}
		"stamina drink":
			p.stamina = minf(p.max_stamina, p.stamina + STAMINA_DRINK)
			return {"text": "+30 Stamina", "color": Color(0.3, 0.5, 1)}
		"ammo":
			var total = null
			if w and w.has_method("add_ammo"):
				w.add_ammo(AMMO_PER_PICKUP)
				total = w.get("ammo")
			var t := "+%d Ammo" % AMMO_PER_PICKUP
			if total != null:
				t += " (%s)" % str(total)
			return {"text": t, "color": Color(0.9, 0.7, 0.1)}
		"weapon":
			var id := it.weapon_id
			if id < 0 or id >= Loot.WEAPONS.size():
				return {}
			var info: Dictionary = Loot.WEAPONS[id]
			var was := _is_unlocked(id)
			if w and w.has_method("unlock"):
				w.unlock(id)
			var ammo_msg := ""
			if info.type == "ranged":
				if w and w.has_method("add_ammo"):
					w.add_ammo(AMMO_PER_PICKUP)
				ammo_msg = " +%d Ammo" % AMMO_PER_PICKUP
			if not was:
				return {"text": "NEW: %s!%s" % [String(info.name).to_upper(), ammo_msg], "color": info.color}
			return {"text": "Got %s%s" % [info.name, ammo_msg], "color": info.color}
		"bomb":
			var mx := bomb_max()
			if bomb_count < mx:
				bomb_count += 1
				return {"text": "+1 Bomb! (%d/%d)" % [bomb_count, mx], "color": Color(1, 0.5, 0.1)}
			return {"text": "BOMBS FULL (%d/%d)" % [mx, mx], "color": Color(0.6, 0.4, 0.2)}
		"battery":
			var mb := maxi(0, 4 - difficulty)
			if p.batteries < mb:
				p.batteries += 1
				return {"text": "+1 Battery (%d/%d)" % [p.batteries, mb], "color": Color(0.2, 1, 0.6)}
			return {"text": "BATTERIES FULL (%d/%d)" % [mb, mb], "color": Color(0.2, 0.6, 0.4)}
	return {}


func bomb_max() -> int:
	return maxi(2, 6 - difficulty)


func _is_unlocked(id: int) -> bool:
	var w = game.weapons
	if w == null:
		return false
	var u = w.get("unlocked")
	if u is Array:
		return id < u.size() and bool(u[id])
	if u is Dictionary:
		return bool(u.get(id, false))
	return false


func _random_locked_weapon() -> int:
	var locked: Array[int] = []
	for id in range(Loot.FIRST_DROP_WEAPON, Loot.WEAPONS.size()):
		if not _is_unlocked(id):
			locked.append(id)
	return -1 if locked.is_empty() else locked[rng.randi() % locked.size()]


# =====================================================================================
#  orbs: pickup -> chaos effect (orbs.lua)
# =====================================================================================

func _collect_orb(o: WorldOrb, p: Player) -> void:
	var eff := roll_effect(o.is_buff)
	var wp: Vector2 = o.position
	var good: bool = eff.is_good
	game.fx.burst(wp, "pickup")
	game.fx.burst(wp, "levelup" if good else "smoke")
	game.audio.play("orb_good" if good else "orb_bad", wp)
	game.fx.flash(Color(0.2, 1.0, 0.4, 0.25) if good else Color(0.9, 0.2, 0.1, 0.3), 0.18)
	game.fx.shake(3.0 if good else 7.0, 0.2)
	game.fx.float_text(p.position + Vector2(0, -56), "CHAOS: " + eff.text, eff.color)
	message.emit("CHAOS: " + eff.text, eff.color)
	orb_effect.emit(eff.text, eff.color, good)
	o.collected = true
	o.set_process(false)
	var tw := o.create_tween().set_parallel(true)
	tw.tween_property(o, "position", p.position, 0.16).set_ease(Tween.EASE_IN)
	tw.tween_property(o, "scale", Vector2(0.1, 0.1), 0.16)
	tw.tween_property(o, "modulate:a", 0.0, 0.16)
	tw.chain().tween_callback(o.queue_free)


func _has(obj, prop: String) -> bool:
	return obj != null and prop in obj


func _addm(obj, prop: String, delta: float) -> void:
	if _has(obj, prop):
		obj.set(prop, float(obj.get(prop)) + delta)


func _mulm(obj, prop: String, mult: float) -> void:
	if _has(obj, prop):
		obj.set(prop, float(obj.get(prop)) * mult)


## Orbs.rollEffect: green orbs are 80% buff / 20% nerf, yellow the reverse. Applies the effect and
## returns {text, color, is_good}. Timed effects are tracked in active_effects and reverted on expiry.
## Enemy/weapon targets use these (optional) properties; missing ones fall back to a player effect:
##   weapons.rate_mod / speed_mod / count_mod / dmg_mod / spread_mod, enemies.hp_mult / spd_mult / dmg_mult
func roll_effect(is_buff: bool) -> Dictionary:
	var p: Player = game.player
	var w = game.weapons
	var e = game.enemies
	var want_good := (rng.randf() < 0.80) == is_buff
	var target := rng.randi_range(1, 3)
	if target == 2 and not (_has(e, "hp_mult") or _has(e, "spd_mult") or _has(e, "dmg_mult")):
		target = 1
	if target == 3 and not (_has(w, "rate_mod") or _has(w, "dmg_mod")):
		target = 1
	var text := ""
	var color := Color.WHITE
	var good := want_good
	var duration := 15.0 + rng.randf() * 25.0
	var up := Color(0.3, 1, 0.3)
	var down := Color(1, 0.3, 0.3)

	if target == 1:
		var stat := rng.randi_range(1, 7)
		if stat == 1:
			var val := _pick(want_good, 10, 50, -30, -5)
			p.hp = maxf(1.0, minf(p.hp + val, p.max_hp + 50.0))
			if val > 0:
				p.max_hp += floorf(val * 0.2)
			text = ("HP +%d" % val) if val >= 0 else ("HP %d" % val)
			color = up if val >= 0 else down
		elif stat == 2:
			var val := _pick(want_good, 10, 40, -20, -5)
			p.stamina = maxf(1.0, minf(p.stamina + val, p.max_stamina + 40.0))
			if val > 0:
				p.max_stamina += floorf(val * 0.2)
			text = ("Stamina +%d" % val) if val >= 0 else ("Stamina %d" % val)
			color = Color(0.3, 0.7, 1) if val >= 0 else down
		elif stat == 3:
			var val := (1.1 + rng.randf() * 0.6) if want_good else (0.5 + rng.randf() * 0.3)
			p.speed_mult = maxf(0.3, minf(p.speed_mult * val, 3.0))
			var pct := floori(val * 100.0) - 100
			text = _pct_text("Speed", pct) + "  (%ds)" % int(duration)
			color = up if pct >= 0 else down
			good = pct >= 0
			_add_effect({"target": "player_speed", "mult": val, "text": "SPD"}, duration, good)
		elif stat == 4:
			var val := (1.2 + rng.randf() * 0.8) if want_good else (0.5 + rng.randf() * 0.3)
			p.dmg_mult = maxf(0.2, minf(p.dmg_mult * val, 4.0))
			var pct := floori(val * 100.0) - 100
			text = _pct_text("Your Dmg", pct) + "  (%ds)" % int(duration)
			color = up if pct >= 0 else down
			good = pct >= 0
			_add_effect({"target": "player_dmg", "mult": val, "text": "DMG"}, duration, good)
		elif stat == 5:
			var val := _pick(want_good, 10, 40, -30, -5)
			p.hp = maxf(1.0, minf(p.hp + val, p.max_hp))
			text = ("HP +%d" % val) if val >= 0 else ("HP %d" % val)
			color = up if val >= 0 else down
		elif stat == 6:
			var val := _pick(want_good, 25, 60, -20, -5)
			p.sanity = maxf(0.0, minf(p.sanity + val, p.max_sanity))
			text = ("Sanity +%d" % val) if val >= 0 else ("Sanity %d" % val)
			color = Color(0.6, 0.3, 1) if val >= 0 else down
		else:
			var val := _pick(want_good, 10, 35, -25, -5)
			p.hydration = maxf(0.0, minf(p.hydration + val, p.max_hydration))
			text = ("Hydration +%d" % val) if val >= 0 else ("Hydration %d" % val)
			color = Color(0.3, 0.7, 1) if val >= 0 else down
	elif target == 2:
		var stat := rng.randi_range(1, 3)
		var prop := ["hp_mult", "spd_mult", "dmg_mult"][stat - 1] as String
		var label := ["Foe HP", "Foe Speed", "Foe Dmg"][stat - 1] as String
		var short := ["FoeHP", "FoeSpd", "FoeDmg"][stat - 1] as String
		var lo_good := [0.4, 0.5, 0.4][stat - 1] as float
		var span_good := [0.3, 0.3, 0.3][stat - 1] as float
		var lo_bad := [1.3, 1.2, 1.2][stat - 1] as float
		var span_bad := [0.9, 0.7, 0.8][stat - 1] as float
		var cmin := [0.3, 0.3, 0.2][stat - 1] as float
		var cmax := [5.0, 3.0, 4.0][stat - 1] as float
		var val := (lo_good + rng.randf() * span_good) if want_good else (lo_bad + rng.randf() * span_bad)
		if _has(e, prop):
			e.set(prop, maxf(cmin, minf(float(e.get(prop)) * val, cmax)))
		var pct := floori(val * 100.0) - 100
		text = _pct_text(label, pct) + "  (%ds)" % int(duration)
		color = down if pct >= 0 else up
		good = pct < 0
		_add_effect({"target": "enemy_" + prop, "mult": val, "text": short, "prop": prop}, duration, good)
	else:
		var stat := rng.randi_range(1, 6)
		if stat == 1:
			var val := (float(rng.randi_range(-3, -1)) * 0.05) if want_good else (float(rng.randi_range(1, 4)) * 0.05)
			_set_clamped(w, "rate_mod", val, 0.3, 2.0)
			text = ("Fire Rate ++" if val <= 0 else "Fire Rate --") + "  (%ds)" % int(duration)
			good = val <= 0
			color = up if good else down
			_add_effect({"target": "wep_rate_mod", "delta": val, "text": "FRate", "prop": "rate_mod"}, duration, good)
		elif stat == 2:
			var val := (0.1 + rng.randf() * 0.5) if want_good else (-0.2 - rng.randf() * 0.3)
			_set_clamped(w, "speed_mod", val, 0.5, 2.0)
			text = ("Proj Speed ++" if val >= 0 else "Proj Speed --") + "  (%ds)" % int(duration)
			good = val >= 0
			color = up if good else down
			_add_effect({"target": "wep_speed_mod", "delta": val, "text": "PSpd", "prop": "speed_mod"}, duration, good)
		elif stat == 3:
			var val := float(rng.randi_range(1, 3)) if want_good else -1.0
			_set_clamped(w, "count_mod", val, -2.0, 6.0)
			text = (("Projectiles +%d" % int(val)) if val >= 0 else ("Projectiles %d" % int(val))) + "  (%ds)" % int(duration)
			good = val >= 0
			color = up if good else down
			_add_effect({"target": "wep_count_mod", "delta": val, "text": "Proj#", "prop": "count_mod"}, duration, good)
		elif stat == 4:
			var val := float(rng.randi_range(1, 5)) if want_good else float(rng.randi_range(-3, -1))
			_set_clamped(w, "dmg_mod", val, -5.0, 15.0)
			text = (("Wep Dmg +%d" % int(val)) if val >= 0 else ("Wep Dmg %d" % int(val))) + "  (%ds)" % int(duration)
			good = val >= 0
			color = up if good else down
			_add_effect({"target": "wep_dmg_mod", "delta": val, "text": "WDmg", "prop": "dmg_mod"}, duration, good)
		elif stat == 5:
			var val := (-0.1 - rng.randf() * 0.4) if want_good else (0.1 + rng.randf() * 0.7)
			_set_clamped(w, "spread_mod", val, 0.2, 3.0)
			text = ("Accuracy ++" if val <= 0 else "Accuracy --") + "  (%ds)" % int(duration)
			good = val <= 0
			color = up if good else down
			_add_effect({"target": "wep_spread_mod", "delta": val, "text": "Acc", "prop": "spread_mod"}, duration, good)
		else:
			var val := (1.2 + rng.randf() * 0.8) if want_good else (0.5 + rng.randf() * 0.3)
			bomb_radius_mult = maxf(0.3, minf(bomb_radius_mult * val, 4.0))
			var pct := floori(val * 100.0) - 100
			text = _pct_text("Bomb Range", pct) + "  (%ds)" % int(duration)
			color = Color(1, 0.6, 0.2) if pct >= 0 else down
			good = pct >= 0
			_add_effect({"target": "bomb_radius", "mult": val, "text": "Bomb"}, duration, good)
	return {"text": text, "color": color, "is_good": good}


func _pick(want_good: bool, gmin: int, gmax: int, bmin: int, bmax: int) -> int:
	return rng.randi_range(gmin, gmax) if want_good else rng.randi_range(bmin, bmax)


func _pct_text(label: String, pct: int) -> String:
	return ("%s +%d%%" % [label, pct]) if pct >= 0 else ("%s %d%%" % [label, pct])


func _set_clamped(obj, prop: String, delta: float, lo: float, hi: float) -> void:
	if _has(obj, prop):
		obj.set(prop, maxf(lo, minf(float(obj.get(prop)) + delta, hi)))


func _add_effect(d: Dictionary, duration: float, good: bool) -> void:
	d["remaining"] = duration
	d["duration"] = duration
	d["is_good"] = good
	active_effects.append(d)


func _tick_effects(dt: float) -> void:
	var i := 0
	while i < active_effects.size():
		var eff: Dictionary = active_effects[i]
		eff.remaining -= dt
		if eff.remaining <= 0.0:
			_revert_effect(eff)
			active_effects.remove_at(i)
		else:
			i += 1


func _revert_effect(eff: Dictionary) -> void:
	var p: Player = game.player
	match String(eff.target):
		"player_speed": p.speed_mult /= float(eff.mult)
		"player_dmg": p.dmg_mult /= float(eff.mult)
		"bomb_radius": bomb_radius_mult /= float(eff.mult)
		"enemy_hp_mult", "enemy_spd_mult", "enemy_dmg_mult":
			_mulm(game.enemies, eff.prop, 1.0 / float(eff.mult))
		_:
			if eff.has("prop"):
				_addm(game.weapons, eff.prop, -float(eff.delta))


# =====================================================================================
#  consumables (main.lua: useHealth / useBandage; food added from player.use_food)
# =====================================================================================

func _handle_consumables(p: Player) -> void:
	var inp = game.input
	if inp.just("use_water") and p.use_almond_water():
		_consumed("Drank Almond Water", Color(0.3, 0.8, 1), "drink")
	if inp.just("use_bandage") and p.use_bandage():
		_consumed("Used Bandage", Color(0.3, 1, 0.3), "bandage")
	if inp.just("use_food") and p.use_food():
		_consumed("Ate Food", Color(0.8, 0.6, 0.2), "eat")


func _consumed(text: String, color: Color, sound: String) -> void:
	var p: Player = game.player
	game.audio.play(sound, p.position)
	game.fx.float_text(p.position + Vector2(0, -50), text, color)
	game.fx.burst(p.position, "pickup")
	message.emit(text, color)


# =====================================================================================
#  bomb (bomb.lua)
# =====================================================================================

func get_bomb_radius() -> float:
	return BOMB_BASE_RADIUS * bomb_radius_mult


func can_use_bomb() -> bool:
	return bomb_count > 0 and bomb_cooldown <= 0.0


## Bomb:use centred on the player. Damages through game.enemies.get_enemies() / take_damage.
func use_bomb() -> bool:
	if not can_use_bomb():
		return false
	var p: Player = game.player
	bomb_count -= 1
	bomb_cooldown = BOMB_COOLDOWN
	var radius := get_bomb_radius()
	var center := p.tile_pos
	if game.enemies and game.enemies.has_method("get_enemies"):
		for e in game.enemies.get_enemies().duplicate():
			if not is_instance_valid(e):
				continue
			var d: Vector2 = e.tile_pos - center
			var dist := d.length()
			if dist >= radius or _blocked_by_wall(center, e.tile_pos):
				continue
			var falloff := 1.0 - dist / radius
			e.take_damage(floorf(BOMB_DAMAGE * falloff), Vector2.ZERO)
			if is_instance_valid(e) and float(e.hp) > 0.0 and dist > 0.1:
				# knockback: immediate offset away from the blast, wall-checked per axis (Lua)
				var push := d / dist * BOMB_KNOCKBACK * falloff * 0.3
				var np: Vector2 = e.tile_pos
				if not game.map.is_solid(np.x + push.x, np.y):
					np.x += push.x
				if not game.map.is_solid(np.x, np.y + push.y):
					np.y += push.y
				e.tile_pos = np
	p.noise = minf(100.0, p.noise + BOMB_NOISE)
	var blast := BombBlast.new()
	blast.radius_px = radius * game.TILE
	blast.position = p.position
	game.world.add_child(blast)
	game.fx.burst(p.position, "explosion")
	game.fx.shake(14.0, 0.45)
	game.fx.flash(Color(1.0, 0.75, 0.35, 0.4), 0.18)
	game.hitstop(0.06)
	game.audio.play("explosion", p.position)
	var t := "BOMB! (%d left)" % bomb_count
	message.emit(t, Color(1, 0.5, 0.1))
	game.fx.float_text(p.position + Vector2(0, -60), t, Color(1, 0.5, 0.1))
	return true


func _blocked_by_wall(a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var steps := ceili(d.length() * 3.0)
	for i in range(1, steps + 1):
		var q := a + d * (float(i) / steps)
		if game.map.is_solid(q.x, q.y):
			return true
	return false


# =====================================================================================
#  kill drops (main.lua processKill)
# =====================================================================================

func _on_enemy_killed(tile_pos: Vector2, kind: String, _xp: int) -> void:
	var chance: float = Loot.KILL_DROP_CHANCE.get(kind.to_lower(), 0.1)
	if rng.randf() < chance:
		if rng.randf() < Loot.KILL_ORB_CHANCE * drop_scale:
			spawn_orb(tile_pos)
		else:
			spawn_drop(tile_pos, "", true)


# =====================================================================================
#  military chests (main.lua V3, map.lua chest rooms, Items:spawnChestLoot)
# =====================================================================================

func chests() -> Array:
	return game.map.chest_rooms


func _tick_chests(p: Player) -> void:
	var rooms: Array = game.map.chest_rooms
	for i in rooms.size():
		var room = rooms[i]
		var center: Vector2 = Vector2(room.pos) + Vector2(0.5, 0.5)
		if not _chest_nodes.has(i):
			var m := ChestMarker.new()
			root.add_child(m)
			m.setup(center, game.TILE)
			if room.looted:
				m.opened = true
				m._open_t = 99.0
			_chest_nodes[i] = m
		if room.looted:
			continue
		if p.tile_pos.distance_to(center) < Loot.CHEST_DETECT_RANGE:
			_open_chest(i, room, center)


func _open_chest(i: int, room, center: Vector2) -> void:
	room.looted = true
	var marker: ChestMarker = _chest_nodes[i]
	marker.open()
	_spawn_chest_loot(center)
	_spawn_swarm(center, Loot.CHEST_SWARM_COUNT)
	var wp: Vector2 = center * game.TILE
	game.fx.burst(wp, "pickup")
	game.fx.burst(wp, "spark")
	game.fx.shake(10.0, 0.5)
	game.fx.flash(Color(1.0, 0.85, 0.3, 0.3), 0.2)
	game.audio.play("chest_open", wp)
	game.fx.float_text(wp + Vector2(0, -50), "MILITARY CHEST FOUND!", Color(0.2, 0.8, 1))
	message.emit("MILITARY CHEST FOUND!", Color(0.2, 0.8, 1))
	message.emit("HOSTILES INCOMING!", Color(1, 0.3, 0.2))
	chest_opened.emit(center)


## Items:spawnChestLoot: a guaranteed locked weapon (or ammo+bomb if all unlocked) + support items.
func _spawn_chest_loot(center: Vector2) -> void:
	var list: Array = []
	var wid := _random_locked_weapon()
	if wid >= 0:
		list.append(["weapon", wid])
	else:
		list.append(["ammo", -1])
		list.append(["ammo", -1])
		list.append(["bomb", -1])
	for k in ["ammo", "ammo", "bandage", "bandage", "almond water", "almond water", "battery", "bomb"]:
		list.append([k, -1])
	for e in list:
		var target := center
		for _t in 12:
			var c := center + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * CHEST_SPREAD
			if game.map.get_tile(floori(c.x), floori(c.y)) == WorldMap.FLOOR:
				target = c
				break
		var it := _make_item(e[0], target, e[1])
		it.launch(center, 0.55, 40.0)
		it.age = -0.1 * rng.randf()   # slight pop stagger


func _spawn_swarm(center: Vector2, count: int) -> void:
	var en = game.enemies
	if en == null:
		return
	if en.has_method("spawn_chest_swarm"):
		en.spawn_chest_swarm(center, count)
		return
	if not en.has_method("spawn"):
		return
	for i in count:
		for _t in 20:
			var pos := center + Vector2.from_angle(rng.randf() * TAU) * (3.0 + rng.randf() * 5.0)
			if not game.map.is_solid(pos.x, pos.y):
				en.spawn("hound" if rng.randf() < 0.6 else "wretch", pos)   # Lua: 60% hounds, 40% wretches
				break


# =====================================================================================
#  exit portal (main.lua V4, Map:spawnPortal)
# =====================================================================================

func _tick_portal(dt: float, p: Player) -> void:
	if _portal_msg_cd > 0.0:
		_portal_msg_cd -= dt
	if portal.is_empty():
		if game.day >= Loot.PORTAL_DAY and not living_legend:
			_spawn_portal(p)
		return
	if not portal.active:
		return
	var d: float = p.tile_pos.distance_to(portal.pos)
	if d > Loot.PORTAL_INTERACT_DIST + 1.0:
		_portal_armed = true    # must walk away once before the prompt can re-trigger after a dismiss
	if portal.node:
		portal.node.guards_left = count_portal_guards()
	if d < Loot.PORTAL_INTERACT_DIST and _portal_armed:
		var left := count_portal_guards()
		if left <= 0:
			_portal_armed = false
			game.audio.play("portal_open", portal.pos * game.TILE)
			game.set_state("portal")   # UI shows the escape/stay prompt
		elif _portal_msg_cd <= 0.0 and left <= 5:
			game.fx.float_text(p.position + Vector2(0, -56), "%d hostiles remain!" % left, Color(1, 0.5, 0.2))
			message.emit("%d hostiles remain!" % left, Color(1, 0.5, 0.2))
			_portal_msg_cd = PORTAL_MSG_INTERVAL


func _spawn_portal(p: Player) -> void:
	var pos = find_portal_spot(p.tile_pos)
	if pos == null:
		return
	var node := ExitPortal.new()
	root.add_child(node)
	node.setup(pos, game.TILE)
	portal = {"pos": pos, "active": true, "node": node}
	_spawn_portal_horde(pos, Loot.PORTAL_HORDE_SIZE)
	for i in 6:
		var op: Vector2 = pos + Vector2(rng.randf() - 0.5, rng.randf() - 0.5) * 6.0
		if game.map.get_tile(floori(op.x), floori(op.y)) == WorldMap.FLOOR:
			spawn_orb(op)
	for i in 4:
		var ip: Vector2 = pos + Vector2(rng.randf() - 0.5, rng.randf() - 0.5) * 5.0
		if game.map.get_tile(floori(ip.x), floori(ip.y)) == WorldMap.FLOOR:
			_make_item(_roll_kind(), ip).launch(pos, 0.5, 30.0)
	game.fx.shake(8.0, 0.6)
	game.fx.flash(Color(0.2, 1.0, 0.6, 0.3), 0.3)
	game.audio.play("portal_open", pos * game.TILE)
	game.fx.float_text(p.position + Vector2(0, -70), "AN EXIT HAS APPEARED!", Color(0.2, 1, 0.5))
	message.emit("AN EXIT HAS APPEARED!", Color(0.2, 1, 0.5))
	message.emit("Clear the horde to escape!", Color(0.9, 0.8, 0.2))
	portal_spawned.emit(pos)


## Map:spawnPortal: a 3x3 open area 25-40 tiles from `near`. Generates the target chunk if needed.
func find_portal_spot(near: Vector2):
	for _t in 200:
		var a := rng.randf() * TAU
		var dist := 25.0 + rng.randf() * 15.0
		var tx := floori(near.x + cos(a) * dist)
		var ty := floori(near.y + sin(a) * dist)
		game.map.ensure_chunk(floori(float(tx) / CHUNK), floori(float(ty) / CHUNK))
		var clear := true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if game.map.get_tile(tx + dx, ty + dy) != WorldMap.FLOOR:
					clear = false
		if clear:
			return Vector2(tx + 0.5, ty + 0.5)
	return null


func _spawn_portal_horde(pos: Vector2, count: int) -> void:
	var en = game.enemies
	if en == null:
		return
	if en.has_method("spawn_portal_horde"):
		en.spawn_portal_horde(pos, count)
		return
	if not en.has_method("spawn"):
		return
	for i in count:
		for _t in 25:
			var q := pos + Vector2.from_angle(rng.randf() * TAU) * (2.0 + rng.randf() * 6.0)
			if not game.map.is_solid(q.x, q.y):
				var roll := rng.randf()
				var kind := "hound" if roll < 0.20 else "crawler" if roll < 0.35 else "wretch" if roll < 0.55 else "shade" if roll < 0.75 else "skin stealer"
				var n = en.spawn(kind, q)
				if n is Node:
					_guards.append(n)
				break


func count_portal_guards() -> int:
	var en = game.enemies
	if en and en.has_method("count_portal_guards"):
		return en.count_portal_guards()
	var n := 0
	for g in _guards:
		if is_instance_valid(g) and not g.is_queued_for_deletion() and not (_has(g, "hp") and float(g.hp) <= 0.0):
			n += 1
	return n


## UI: the player chose STAY on the portal prompt (Lua "LIVING LEGEND MODE").
func portal_decline() -> void:
	if portal.is_empty():
		return
	portal.active = false
	living_legend = true
	if portal.node:
		portal.node.queue_free()
		portal.node = null
	message.emit("LIVING LEGEND MODE!", Color(1, 0.8, 0.2))
	message.emit("No more exits. Survive forever.", Color(0.7, 0.6, 0.5))


# =====================================================================================
#  housekeeping
# =====================================================================================

func _cull(p: Player) -> void:
	var pt := p.tile_pos
	var dsq := Loot.ITEM_DESPAWN_DIST * Loot.ITEM_DESPAWN_DIST
	var i := items.size() - 1
	while i >= 0:
		var it = items[i]
		if not is_instance_valid(it):
			items.remove_at(i)
		elif (pt - it.tile_pos).length_squared() > dsq:
			it.queue_free()
			items.remove_at(i)
		else:
			it.set_process((pt - it.tile_pos).length_squared() < 30.0 * 30.0)   # only animate nearby pickups
		i -= 1
	dsq = Loot.ORB_DESPAWN_DIST * Loot.ORB_DESPAWN_DIST
	i = orbs.size() - 1
	while i >= 0:
		var o = orbs[i]
		if not is_instance_valid(o):
			orbs.remove_at(i)
		else:
			if (pt - o.tile_pos).length_squared() > dsq:
				o.queue_free()
				orbs.remove_at(i)
			else:
				o.light.visible = (pt - o.tile_pos).length_squared() < 18.0 * 18.0
		i -= 1
	# props: the sprite stays (solid ones keep their collision tile) but is hidden when far away
	var vis := Loot.PROP_CLEANUP_DIST * Loot.PROP_CLEANUP_DIST
	for n in props:
		if is_instance_valid(n):
			n.visible = (pt - n.tile_pos).length_squared() < vis
	for k in _chest_nodes:
		var m = _chest_nodes[k]
		if is_instance_valid(m):
			m.visible = (pt - m.tile_pos).length_squared() < vis
