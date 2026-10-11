extends RefCounted
## Index of every sound/music file under res://assets/audio and name resolution.
## Names are normalised (lowercase, non-alphanumerics -> "_", extension and folder dropped), so
## "Demonic Breath 001", "demonic_breath_001.wav" and "sounds/Demonic Breath 001.ogg" are the same.
## A name that is not an exact file but a prefix (on "_" boundaries) resolves to a random member
## of that group, e.g. "hell_beast_attack" or "death".

const SOUND_DIR := "res://assets/audio/sounds"
const MUSIC_DIR := "res://assets/audio/music"

## Lua names that do not match a file (main.lua looked for "gunshot_sound" but the file is gunshot.mp3).
const ALIASES := {
	"gunshot_sound": "gunshot", "pistol": "gunshot", "pistol_sound": "gunshot", "gun": "gunshot",
	"shotgun": "shotgun_sound", "smg": "smg_sound", "swing": "swing_sound", "melee": "swing_sound",
	"footsteps": "footsteps_in_a_hallway", "footstep": "footsteps_in_a_hallway",
	"whispers_male": "male_whispers", "whispers_female": "female_whispers",
	"male_whisper": "male_whispers", "female_whisper": "female_whispers",
	"attack": "hell_beast_attack", "enemy_attack": "hell_beast_attack",
	"hurt": "death", "enemy_hurt": "death", "hit": "death", "hell_beast_dies": "death_hell_beast_dies",
	"phrase": "demonic_phrase", "breath": "demonic_breath",
	"menu": "ui_horror_vol2_hush_cut_60", "ui": "ui_horror_vol2_hush_cut_60",
}

var sounds := {}   # key -> res path
var music := {}    # key -> res path
var _cache := {}   # path -> AudioStream


static func norm(s: String) -> String:
	var n := s.get_file().to_lower()
	for ext in [".wav", ".mp3", ".ogg", ".import"]:
		if n.ends_with(ext):
			n = n.substr(0, n.length() - ext.length())
	var out := ""
	var last_us := true
	for c in n:
		var ok: bool = (c >= "a" and c <= "z") or (c >= "0" and c <= "9")
		if ok:
			out += c
			last_us = false
		elif not last_us:
			out += "_"
			last_us = true
	return out.rstrip("_")


func scan() -> void:
	_scan_dir(SOUND_DIR, sounds)
	_scan_dir(MUSIC_DIR, music)


func _scan_dir(dir: String, into: Dictionary) -> void:
	# exported builds list "x.ogg.import"/"x.ogg.remap" instead of the raw file
	for f in DirAccess.get_files_at(dir):
		var base := f
		for suf in [".import", ".remap"]:
			if base.ends_with(suf):
				base = base.substr(0, base.length() - suf.length())
		if base.get_extension() in ["ogg", "wav", "mp3"]:
			into[norm(base)] = dir + "/" + base


## All keys a name stands for (1 for an exact file, N for a group, 0 for unknown).
func resolve(sound_name: String, pool: Dictionary = sounds) -> Array:
	var k := norm(sound_name)
	if ALIASES.has(k) and not pool.has(k):
		k = ALIASES[k]
	if pool.has(k):
		return [k]
	var group := []
	for key in pool:
		if String(key).begins_with(k + "_"):
			group.append(key)
	group.sort()
	return group


func pick(sound_name: String, pool: Dictionary = sounds) -> String:
	var keys := resolve(sound_name, pool)
	if keys.is_empty():
		return ""
	return keys[randi() % keys.size()]


func get_stream(key: String, pool: Dictionary = sounds) -> AudioStream:
	var path: String = pool.get(key, "")
	if path == "":
		return null
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


## A private copy of the stream with looping switched on (heartbeat, whispers, menu music).
func get_loop_stream(key: String, pool: Dictionary = sounds) -> AudioStream:
	var s := get_stream(key, pool)
	if s == null:
		return null
	var c: AudioStream = s.duplicate()
	if "loop" in c:
		c.loop = true
	return c
