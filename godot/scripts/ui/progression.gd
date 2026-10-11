class_name Progression
extends RefCounted
## Port of progression.lua: meta upgrades, tokens, save slots (characters), run perks.
## Save file: user://backrooms_save.json (+ .bak). Same logical structure as the Lua v3 save:
##   {version:3, characters:[{name, profiles:[{tokens, upgrades:{id:level}, bestDay, bestKills,
##                                              bestStreak, bestTime, totalRuns} x4 difficulties]}]}

const MAX_CHARACTERS := 10
const SAVE_FILE := "user://backrooms_save.json"

## id, name, desc, max level, base cost, cost growth (cost = base + level * growth)
const UPGRADES := [
	{"id": "max_hp", "name": "Constitution", "desc": "+10 Max HP per level", "max": 10, "base": 4, "growth": 3},
	{"id": "max_stamina", "name": "Endurance", "desc": "+8 Max Stamina per level", "max": 10, "base": 4, "growth": 3},
	{"id": "move_speed", "name": "Agility", "desc": "+3% Move Speed per level", "max": 8, "base": 5, "growth": 4},
	{"id": "sanity_resist", "name": "Iron Mind", "desc": "-5% Sanity Drain per level", "max": 10, "base": 5, "growth": 3},
	{"id": "hydration_resist", "name": "Camel Blood", "desc": "-5% Hydration Drain per level", "max": 8, "base": 4, "growth": 3},
	{"id": "start_ammo", "name": "Ammunition Cache", "desc": "+5 Starting Ammo per level", "max": 6, "base": 3, "growth": 2},
	{"id": "start_bombs", "name": "Demolitions Training", "desc": "+1 Starting Bomb per level", "max": 4, "base": 6, "growth": 5},
	{"id": "start_batteries", "name": "Power Hoarder", "desc": "+1 Starting Battery per level", "max": 4, "base": 5, "growth": 3},
	{"id": "lamp_capacity", "name": "Extended Battery", "desc": "+15% Headlamp Battery Life per level", "max": 6, "base": 5, "growth": 4},
	{"id": "damage_boost", "name": "Combat Training", "desc": "+5% Base Damage per level", "max": 8, "base": 6, "growth": 4},
]

const RUN_PERKS := [
	{"id": "tough_skin", "name": "Tough Skin", "desc": "Take 15% less damage from all sources."},
	{"id": "second_wind", "name": "Second Wind", "desc": "+30 Max HP and heal to full."},
	{"id": "quick_feet", "name": "Quick Feet", "desc": "+10% movement speed."},
	{"id": "heavy_hitter", "name": "Heavy Hitter", "desc": "+15% weapon damage."},
	{"id": "clear_mind", "name": "Clear Mind", "desc": "Sanity drains 30% slower."},
	{"id": "deep_reservoir", "name": "Deep Reservoir", "desc": "Hydration drains 30% slower."},
	{"id": "ammo_cache", "name": "Ammo Cache", "desc": "+40 ammo right now."},
	{"id": "trigger_finger", "name": "Trigger Finger", "desc": "Weapons fire 20% faster."},
	{"id": "boom_boom", "name": "Boom Boom", "desc": "+2 bombs right now."},
	{"id": "field_medic", "name": "Field Medic", "desc": "+2 bandages and +2 almond water."},
	{"id": "thick_skull", "name": "Thick Skull", "desc": "Invulnerability after hit lasts 2x longer."},
	{"id": "marathon", "name": "Marathon Runner", "desc": "+30 max stamina and sprint costs 25% less."},
]

var characters: Array = []
var active_idx := -1       # 0-based index into characters; -1 = none


func _init() -> void:
	load_save()


# ---- tokens -----------------------------------------------------------------

## Lua: Progression.calcTokens. difficulty 1..4, run_time seconds.
static func calc_tokens(days: int, kills: int, difficulty: int, run_time: float) -> int:
	var mult: float = [0.5, 1.0, 1.5, 2.0][clampi(difficulty - 1, 0, 3)]
	var kill_bonus := kills / 10
	var time_bonus := int(run_time / 120.0)
	return maxi(1, int(floor((days + kill_bonus + time_bonus) * mult)))


static func get_upgrade(id: String) -> Dictionary:
	for u in UPGRADES:
		if u.id == id:
			return u
	return {}


static func new_profiles() -> Array:
	var out := []
	for i in 4:
		out.append({"tokens": 0, "upgrades": {}, "bestDay": 0, "bestKills": 0, "bestStreak": 0, "bestTime": 0.0, "totalRuns": 0})
	return out


# ---- characters --------------------------------------------------------------

func character_count() -> int:
	return characters.size()


func add_character(char_name: String) -> bool:
	if characters.size() >= MAX_CHARACTERS:
		return false
	characters.append({"name": char_name, "profiles": new_profiles()})
	save()
	return true


func delete_character(idx: int) -> bool:
	if idx < 0 or idx >= characters.size():
		return false
	characters.remove_at(idx)
	if active_idx == idx:
		active_idx = -1
	elif active_idx > idx:
		active_idx -= 1
	save()
	return true


func set_active(idx: int) -> bool:
	if idx >= 0 and idx < characters.size():
		active_idx = idx
		return true
	return false


func active_name() -> String:
	if active_idx >= 0 and active_idx < characters.size():
		return characters[active_idx].name
	return "Subject"


func summary(idx: int) -> Dictionary:
	if idx < 0 or idx >= characters.size():
		return {}
	var ch: Dictionary = characters[idx]
	var s := {"name": ch.name, "totalRuns": 0, "bestDay": 0, "bestDayByDiff": [0, 0, 0, 0],
		"bestKills": 0, "bestStreak": 0, "totalTokens": 0}
	for d in 4:
		var p: Dictionary = ch.profiles[d]
		s.bestDayByDiff[d] = p.get("bestDay", 0)
		s.totalRuns += p.get("totalRuns", 0)
		s.bestDay = maxi(s.bestDay, p.get("bestDay", 0))
		s.bestKills = maxi(s.bestKills, p.get("bestKills", 0))
		s.bestStreak = maxi(s.bestStreak, p.get("bestStreak", 0))
		s.totalTokens += p.get("tokens", 0)
	return s


# ---- profile access (active character, difficulty 1..4) -----------------------------

func profile(difficulty: int) -> Dictionary:
	if active_idx < 0 or active_idx >= characters.size():
		return {"tokens": 0, "upgrades": {}, "bestDay": 0, "bestKills": 0, "bestStreak": 0, "bestTime": 0.0, "totalRuns": 0}
	var profiles: Array = characters[active_idx].profiles
	return profiles[clampi(difficulty - 1, 0, 3)]


func upgrade_level(difficulty: int, id: String) -> int:
	return int(profile(difficulty).upgrades.get(id, 0))


func upgrade_cost(id: String, level: int) -> int:
	var u := get_upgrade(id)
	if u.is_empty():
		return 999
	return int(u.base) + level * int(u.growth)


func can_afford(difficulty: int, id: String) -> bool:
	var p := profile(difficulty)
	var level := int(p.upgrades.get(id, 0))
	var u := get_upgrade(id)
	if u.is_empty() or level >= int(u.max):
		return false
	return int(p.tokens) >= upgrade_cost(id, level)


func buy_upgrade(difficulty: int, id: String) -> bool:
	if not can_afford(difficulty, id):
		return false
	var p := profile(difficulty)
	var level := int(p.upgrades.get(id, 0))
	p.tokens = int(p.tokens) - upgrade_cost(id, level)
	p.upgrades[id] = level + 1
	save()
	return true


## Records a finished run; returns tokens earned. (Lua: addRunResults)
func add_run_results(difficulty: int, days: int, kills: int, best_streak: int, run_time: float) -> int:
	var earned := calc_tokens(days, kills, difficulty, run_time)
	if active_idx < 0:
		return earned
	var p := profile(difficulty)
	p.tokens = int(p.tokens) + earned
	p.totalRuns = int(p.totalRuns) + 1
	p.bestDay = maxi(int(p.bestDay), days)
	p.bestKills = maxi(int(p.bestKills), kills)
	p.bestStreak = maxi(int(p.bestStreak), best_streak)
	p.bestTime = maxf(float(p.bestTime), run_time)
	save()
	return earned


func add_tokens(difficulty: int, n: int) -> void:
	if active_idx < 0:
		return
	var p := profile(difficulty)
	p.tokens = int(p.tokens) + n
	save()


func profile_stats(difficulty: int) -> Dictionary:
	var p := profile(difficulty)
	return {"bestDay": p.bestDay, "bestKills": p.bestKills, "bestStreak": p.bestStreak,
		"bestTime": p.bestTime, "totalRuns": p.totalRuns, "tokens": p.tokens}


# ---- applying upgrades ----------------------------------------------------------------

## Applies permanent upgrades to the player. `mods` receives values the player script has no field for:
## sanity_drain / hydration_drain / lamp_capacity (multipliers) and start_ammo / start_bombs (additive).
func apply_to_run(difficulty: int, player, mods: Dictionary) -> void:
	for u in UPGRADES:
		var lv := upgrade_level(difficulty, u.id)
		if lv <= 0:
			continue
		match u.id:
			"max_hp":
				player.max_hp += lv * 10.0
				player.hp = player.max_hp
			"max_stamina":
				player.max_stamina += lv * 8.0
				player.stamina = player.max_stamina
			"move_speed":
				player.speed_mult += lv * 0.03
			"sanity_resist":
				mods.sanity_drain *= (1.0 - lv * 0.05)
			"hydration_resist":
				mods.hydration_drain *= (1.0 - lv * 0.05)
			"start_ammo":
				mods.start_ammo += lv * 5
			"start_bombs":
				mods.start_bombs += lv
			"start_batteries":
				player.batteries += lv
			"lamp_capacity":
				mods.lamp_capacity *= (1.0 + lv * 0.15)
			"damage_boost":
				player.dmg_mult += lv * 0.05


## Applies a run perk (Lua RUN_PERKS[i].apply). add_bombs is a Callable(n:int).
static func apply_perk(id: String, player, mods: Dictionary, weapons, add_bombs: Callable) -> void:
	match id:
		"tough_skin": player.dmg_taken_mult *= 0.85
		"second_wind":
			player.max_hp += 30.0
			player.hp = player.max_hp
		"quick_feet": player.speed_mult += 0.10
		"heavy_hitter": player.dmg_mult += 0.15
		"clear_mind": mods.sanity_drain *= 0.70
		"deep_reservoir": mods.hydration_drain *= 0.70
		"ammo_cache":
			if weapons != null and "ammo" in weapons:
				weapons.ammo += 40
		"trigger_finger":
			mods.rate_mod *= 0.80
			if weapons != null and "rate_mod" in weapons:   # BALANCE fix: the perk never reached the weapon system
				weapons.rate_mod *= 0.80
		"boom_boom": add_bombs.call(2)
		"field_medic":
			player.bandages += 2
			player.almond_water += 2
		"thick_skull": player.invuln_time_mult *= 2.0
		"marathon":
			player.max_stamina += 30.0
			player.stamina = player.max_stamina
			mods.sprint_cost *= 0.75


## Roll 2 random perks not in exclude_ids. Empty array if fewer than 2 remain.
static func roll_perk_choice(exclude_ids: Array) -> Array:
	var pool: Array = []
	for p in RUN_PERKS:
		if not exclude_ids.has(p.id):
			pool.append(p)
	if pool.size() < 2:
		return []
	pool.shuffle()
	return [pool[0], pool[1]]


# ---- save / load ----------------------------------------------------------------------------

func save() -> bool:
	var data := JSON.stringify({"version": 3, "characters": characters}, "\t")
	var tmp := SAVE_FILE + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Save failed (tmp write)")
		return false
	f.store_string(data)
	f.close()
	if FileAccess.file_exists(SAVE_FILE):
		DirAccess.copy_absolute(SAVE_FILE, SAVE_FILE + ".bak")
	var d := DirAccess.open("user://")
	if d == null:
		return false
	if d.file_exists(SAVE_FILE.get_file()):
		d.remove(SAVE_FILE.get_file())
	if d.rename(tmp.get_file(), SAVE_FILE.get_file()) != OK:
		var f2 := FileAccess.open(SAVE_FILE, FileAccess.WRITE)
		if f2 == null:
			return false
		f2.store_string(data)
	return true


func _try_read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else null


func load_save() -> void:
	var result: Variant = _try_read(SAVE_FILE)
	if result == null:
		result = _try_read(SAVE_FILE + ".bak")
		if result == null:
			return
	characters.clear()
	for ch in result.get("characters", []):
		if not (ch is Dictionary) or not ch.has("name"):
			continue
		var c := {"name": str(ch.name), "profiles": new_profiles()}
		var src_profiles: Array = ch.get("profiles", [])
		for d in mini(4, src_profiles.size()):
			var src: Dictionary = src_profiles[d]
			var dst: Dictionary = c.profiles[d]
			dst.tokens = int(src.get("tokens", 0))
			dst.upgrades = {}
			for k in src.get("upgrades", {}):
				dst.upgrades[k] = int(src.upgrades[k])
			dst.bestDay = int(src.get("bestDay", 0))
			dst.bestKills = int(src.get("bestKills", 0))
			dst.bestStreak = int(src.get("bestStreak", 0))
			dst.bestTime = float(src.get("bestTime", 0.0))
			dst.totalRuns = int(src.get("totalRuns", 0))
		characters.append(c)
