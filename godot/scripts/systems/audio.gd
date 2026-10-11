extends Node
## Audio system (game.audio). Port of music.lua + the sound side of main.lua/enemysounds.lua.
##
## API: play(name, world_px_or_null, volume, pitch), play_music(name), stop_music(),
##      play_slice / play_fade / loop_start / loop_move / loop_stop (extras, see below).
## Buses: Master > Music (lowpass), SFX (reverb + lowpass), Cue (heartbeat/whispers, never scaled by SFX).

const SoundBank = preload("res://scripts/audio/sound_bank.gd")
const MusicDirector = preload("res://scripts/audio/music_director.gd")

# --- tunables (Lua name in comment) ---
const MAX_DIST_TILES := 15.0            # EnemySounds.maxDist
const POS_VOICES := 24
const FLAT_VOICES := 10
const PITCH_JITTER := 0.05
const SAME_SOUND_GAP := 0.035           # seconds, stops SMG-style spam stacking identical voices
const SAME_SOUND_MAX := 6
const HEARTBEAT_BASE := 4.0             # heartbeatBaseVol (amplified, >1)
const HEARTBEAT_MAX := 6.0              # heartbeatMaxVol
const WHISPER_SANITY := 0.10            # whispers below 10% sanity
const WHISPER_MAX_VOL := 0.7
const WHISPER_SPEED := 0.12             # whisperCrossfadeSpeed
const DEFAULT_MUSIC := 0.75             # Options musicVolume
const DEFAULT_SFX := 0.75               # Options sfxVolume
const HALLUCINATION_SOUNDS := ["delirious", "in_the_walls", "gasp_for_air", "demonic_ritual", "demonic_breath"]

var game
var bank
var music
var _tile := 52.0
var _voices: Array = []                 # {p, pos, key, age, dur, fade_left, fade_total, base_db}
var _loops := {}                        # id -> voice dict
var _last_play := {}                    # key -> time
var _clock := 0.0
var _heartbeat: AudioStreamPlayer
var _whisper_m: AudioStreamPlayer
var _whisper_f: AudioStreamPlayer
var _whisper_phase := 0.0
var _whisper_dir := 1.0
var _hallu_t := 8.0
var _opt_t := 0.0
var _danger_t := 0.0
var _muffle := 0.0                      # 0..1 damage muffle, decays
var _lp_sfx: AudioEffectLowPassFilter
var _lp_music: AudioEffectLowPassFilter
var _listener: AudioListener2D
var _in_run := false
var _hb_pitch := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	bank = SoundBank.new()
	bank.scan()
	_setup_buses()
	music = MusicDirector.new()
	music.bank = bank
	music.name = "Music"
	add_child(music)
	for i in POS_VOICES:
		_voices.append(_new_voice(true))
	for i in FLAT_VOICES:
		_voices.append(_new_voice(false))
	_heartbeat = _make_cue("heartbeat")
	_whisper_m = _make_cue("male_whispers")
	_whisper_f = _make_cue("female_whispers")


func setup(g) -> void:
	game = g
	_tile = float(game.get("TILE") if game.get("TILE") != null else 52)
	if game.player:
		_listener = AudioListener2D.new()
		game.player.add_child(_listener)
		_listener.make_current()
		if game.player.has_signal("footstep"):
			game.player.footstep.connect(_on_footstep)
		if game.player.has_signal("damaged"):
			game.player.damaged.connect(_on_player_damaged)
	if game.has_signal("state_changed"):
		game.state_changed.connect(_on_state)
	if game.has_signal("player_died"):
		game.player_died.connect(_on_died)
	_apply_volumes()
	_on_state(String(game.get("state") if game.get("state") != null else "title"))


# ------------------------------------------------------------------ buses

func _setup_buses() -> void:
	for b in ["Music", "SFX", "Cue"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")
	var sfx := AudioServer.get_bus_index("SFX")
	if AudioServer.get_bus_effect_count(sfx) == 0:
		var rev := AudioEffectReverb.new()
		rev.room_size = 0.4
		rev.damping = 0.6
		rev.wet = 0.12
		rev.dry = 1.0
		rev.spread = 0.8
		AudioServer.add_bus_effect(sfx, rev)
		_lp_sfx = AudioEffectLowPassFilter.new()
		_lp_sfx.cutoff_hz = 20500.0
		AudioServer.add_bus_effect(sfx, _lp_sfx)
	else:
		_lp_sfx = AudioServer.get_bus_effect(sfx, 1) as AudioEffectLowPassFilter
	var mus := AudioServer.get_bus_index("Music")
	if AudioServer.get_bus_effect_count(mus) == 0:
		_lp_music = AudioEffectLowPassFilter.new()
		_lp_music.cutoff_hz = 20500.0
		AudioServer.add_bus_effect(mus, _lp_music)
	else:
		_lp_music = AudioServer.get_bus_effect(mus, 0) as AudioEffectLowPassFilter


func _opt(keys: Array, default: float) -> float:
	var o = null
	if game and game.get("ui") != null:
		o = game.ui.get("options")
	if o == null:
		return default
	for k in keys:
		var v = null
		if o is Dictionary:
			v = o.get(k)
		elif o is Object:
			v = o.get(k)
		if v != null and (v is float or v is int):
			return clampf(float(v), 0.0, 1.0)
	return default


func _apply_volumes() -> void:
	var master := _opt(["master_volume", "masterVolume", "master"], 1.0)
	var mus := _opt(["music_volume", "musicVolume", "music"], DEFAULT_MUSIC)
	var sfx := _opt(["sfx_volume", "sfxVolume", "sfx"], DEFAULT_SFX)
	_set_bus("Master", master)
	_set_bus("Music", mus)
	_set_bus("SFX", sfx)
	_set_bus("Cue", 1.0)


func _set_bus(b: String, lin: float) -> void:
	var i := AudioServer.get_bus_index(b)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, -80.0 if lin <= 0.001 else linear_to_db(lin))


# ------------------------------------------------------------------ voices

func _new_voice(positional: bool) -> Dictionary:
	var p: Node
	if positional:
		var p2 := AudioStreamPlayer2D.new()
		p2.bus = "SFX"
		p2.max_distance = MAX_DIST_TILES * 52.0
		p2.attenuation = 2.0              # Lua: ((1 - d/maxDist))^2
		p2.panning_strength = 1.0
		p = p2
	else:
		var pf := AudioStreamPlayer.new()
		pf.bus = "SFX"
		p = pf
	add_child(p)
	return {"p": p, "pos": positional, "key": "", "age": 0.0, "dur": 0.0,
		"fade_left": 0.0, "fade_total": 0.0, "base_db": 0.0, "busy": false}


func _make_cue(key: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Cue"
	p.volume_db = -80.0
	var s: AudioStream = bank.get_loop_stream(key)
	if s:
		p.stream = s
	add_child(p)
	return p


func _acquire(positional: bool) -> Dictionary:
	var oldest: Dictionary = {}
	for v in _voices:
		if v.pos != positional:
			continue
		if not v.p.playing:
			return v
		if oldest.is_empty() or v.age > oldest.age:
			oldest = v
	return oldest  # steal the oldest


func _start_voice(key: String, world_px, volume: float, pitch: float, jitter: float,
		start := 0.0, dur := 0.0, fade := 0.0) -> Dictionary:
	var stream: AudioStream = bank.get_stream(key)
	if stream == null:
		return {}
	# per-sound rate limit and concurrency cap
	if _clock - float(_last_play.get(key, -10.0)) < SAME_SOUND_GAP:
		return {}
	var same := 0
	for v in _voices:
		if v.key == key and v.p.playing:
			same += 1
	if same >= SAME_SOUND_MAX:
		return {}
	_last_play[key] = _clock
	var positional: bool = world_px is Vector2
	var v := _acquire(positional)
	if v.is_empty():
		return {}
	var p = v.p
	p.stream = stream
	p.pitch_scale = clampf(pitch * (1.0 + randf_range(-jitter, jitter)), 0.1, 4.0)
	v.base_db = -80.0 if volume <= 0.001 else linear_to_db(volume)
	p.volume_db = v.base_db
	if positional:
		p.global_position = world_px
	v.key = key
	v.age = 0.0
	v.dur = dur
	v.fade_left = fade
	v.fade_total = fade
	p.play(start)
	return v


## Fire-and-forget one-shot. world_px: Vector2 in world pixels (null = non-positional, e.g. UI/player).
## volume: linear, pitch: multiplier (about +-5% random variation is added).
func play(sound_name: String, world_px = null, volume := 1.0, pitch := 1.0) -> void:
	if bank == null:
		return
	var key: String = bank.pick(sound_name)
	if key == "":
		return
	_start_voice(key, world_px, volume, pitch, PITCH_JITTER)


## Plays only [start, start+dur) of a sound with a short fade out (used for footsteps).
func play_slice(sound_name: String, start: float, dur: float, world_px = null, volume := 1.0, pitch := 1.0) -> void:
	var key: String = bank.pick(sound_name)
	if key != "":
		_start_voice(key, world_px, volume, pitch, PITCH_JITTER, start, dur, minf(0.06, dur * 0.4))


## One-shot that fades to silence over `fade` seconds (EnemySounds killing-blow hurt sound).
func play_fade(sound_name: String, world_px, volume: float, fade: float, pitch := 1.0) -> void:
	var key: String = bank.pick(sound_name)
	if key != "":
		_start_voice(key, world_px, volume, pitch, PITCH_JITTER, 0.0, 0.0, fade)


## Looping positional sound tracked by id (enemy breath). Returns false if unknown/no voice.
func loop_start(id, sound_name: String, world_px, volume := 1.0) -> bool:
	if _loops.has(id):
		return true
	var key: String = bank.pick(sound_name)
	if key == "":
		return false
	var v := _acquire(world_px is Vector2)
	if v.is_empty() or v.p.playing and v.age < 0.5:
		return false
	var s: AudioStream = bank.get_loop_stream(key)
	v.p.stream = s
	v.p.pitch_scale = 1.0 + randf_range(-0.04, 0.04)
	v.base_db = -80.0 if volume <= 0.001 else linear_to_db(volume)
	v.p.volume_db = v.base_db
	if world_px is Vector2:
		v.p.global_position = world_px
	v.key = "loop:" + key
	v.age = 0.0
	v.dur = 0.0
	v.fade_left = 0.0
	v.fade_total = 0.0
	v.p.play()
	_loops[id] = v
	return true


func loop_move(id, world_px, volume := -1.0) -> void:
	var v = _loops.get(id)
	if v == null or not v.p.playing or not String(v.key).begins_with("loop:"):
		_loops.erase(id)
		return
	if world_px is Vector2 and v.pos:
		v.p.global_position = world_px
	if volume >= 0.0:
		v.base_db = -80.0 if volume <= 0.001 else linear_to_db(volume)
		v.p.volume_db = v.base_db


func loop_stop(id, fade := 0.5) -> void:
	var v = _loops.get(id)
	_loops.erase(id)
	if v == null:
		return
	if fade > 0.0:
		v.key = "fading"
		v.fade_left = fade
		v.fade_total = fade
	else:
		v.p.stop()


func play_music(track_name: String) -> void:
	if music:
		if not music.play_track(track_name):
			push_warning("audio: unknown track '%s'" % track_name)


func stop_music() -> void:
	if music:
		music.stop()


func stop_all_sfx() -> void:
	_loops.clear()
	for v in _voices:
		v.p.stop()
		v.key = ""


# ------------------------------------------------------------------ game hooks

func reset_run() -> void:
	stop_all_sfx()
	_whisper_phase = 0.0
	_whisper_dir = 1.0
	_hallu_t = randf_range(8.0, 16.0)
	_muffle = 0.0
	_start_run_audio()


func _start_run_audio() -> void:
	_in_run = true
	if _heartbeat.stream and not _heartbeat.playing:
		_heartbeat.volume_db = linear_to_db(HEARTBEAT_BASE)
		_heartbeat.play()
	_heartbeat.stream_paused = false
	if music and (music.current_name == "" or not music.enabled):
		music.start_rotation()


func _stop_cues() -> void:
	for p in [_heartbeat, _whisper_m, _whisper_f]:
		p.stop()


func _on_state(s: String) -> void:
	match s:
		"playing":
			if not _in_run:
				_start_run_audio()
			for p in [_heartbeat, _whisper_m, _whisper_f]:
				p.stream_paused = false
		"paused", "perk", "portal":
			for p in [_heartbeat, _whisper_m, _whisper_f]:
				p.stream_paused = true
		"title", "dead":
			_in_run = false
			_stop_cues()
			for v in _loops.values():
				v.p.stop()
			_loops.clear()
			if music:
				music.play_track("ui", true)  # menu music, as the Lua does on title/death


func _on_died() -> void:
	_in_run = false
	_stop_cues()
	_muffle = 1.0


func _on_player_damaged(amount: float) -> void:
	_muffle = clampf(maxf(_muffle, 0.35 + amount / 40.0), 0.0, 1.0)


func _on_footstep(sprinting: bool) -> void:
	# footsteps-in-a-hallway.mp3 is a 10.9 s recording of steps; cut a random short slice each time.
	var len_s := 10.0
	var st: AudioStream = bank.get_stream("footsteps_in_a_hallway")
	if st:
		len_s = st.get_length()
	var start := randf() * maxf(0.1, len_s - 0.5)
	var vol := 0.55 if sprinting else 0.32
	var pitch := 1.12 if sprinting else 0.96
	play_slice("footsteps_in_a_hallway", start, 0.26 if sprinting else 0.32, null, vol, pitch)


# ------------------------------------------------------------------ per frame

func _process(dt: float) -> void:
	_clock += dt
	for v in _voices:
		if not v.p.playing:
			if v.key != "" and not (v.key.begins_with("loop:")):
				v.key = ""
			continue
		v.age += dt
		var ratio := 1.0
		if v.dur > 0.0:
			if v.age >= v.dur:
				v.p.stop()
				v.key = ""
				continue
			if v.fade_total > 0.0 and v.age > v.dur - v.fade_total:
				ratio = (v.dur - v.age) / v.fade_total
		elif v.key == "fading":
			v.fade_left -= dt
			ratio = v.fade_left / v.fade_total
		elif v.fade_total > 0.0:
			ratio = 1.0 - v.age / v.fade_total
		if ratio <= 0.0:
			v.p.stop()
			v.key = ""
			continue
		if ratio < 1.0:
			v.p.volume_db = v.base_db + _db_ratio(ratio)
	# muffle recovery & low hp lowpass
	_muffle = maxf(0.0, _muffle - dt / 1.6)
	var hp_k := 0.0
	if game and game.player and _in_run:
		hp_k = clampf(1.0 - (game.player.hp / maxf(1.0, game.player.max_hp)) / 0.3, 0.0, 1.0) * 0.5
	var k := maxf(_muffle, hp_k)
	var paused: bool = game != null and String(game.get("state")) in ["paused", "perk"]
	if _lp_sfx:
		_lp_sfx.cutoff_hz = lerpf(20500.0, 1100.0, k * k)
	if _lp_music:
		_lp_music.cutoff_hz = 900.0 if paused else lerpf(20500.0, 2500.0, k * k)
	_opt_t -= dt
	if _opt_t <= 0.0:
		_opt_t = 0.25
		_apply_volumes()


static func _db_ratio(r: float) -> float:
	return -80.0 if r <= 0.001 else linear_to_db(r)


func tick(dt: float) -> void:
	if game == null or game.player == null:
		return
	var p = game.player
	_update_danger(dt)
	_update_heartbeat(p)
	_update_whispers(p, dt)
	_update_hallucinations(p, dt)


func _update_danger(dt: float) -> void:
	_danger_t -= dt
	if _danger_t > 0.0:
		return
	_danger_t = 0.25
	var p = game.player
	var near := 0.0
	if game.enemies and game.enemies.has_method("get_enemies"):
		for e in game.enemies.get_enemies():
			var d: float = e.tile_pos.distance_to(p.tile_pos)
			if d < 12.0:
				near += 1.0 - d / 12.0
	var low_hp: float = 1.0 - p.hp / maxf(1.0, p.max_hp)
	var target := clampf(near * 0.5 + low_hp * 0.5, 0.0, 1.0)
	music.danger = lerpf(music.danger, target, 0.25)


## Lua: volume = base + (max-base) * (1 - stamina%), amplified. Extended: also rises as hp / sanity fall
## (whichever stat is lowest drives it) and the rate speeds up with hp.
func _update_heartbeat(p) -> void:
	if _heartbeat.stream == null:
		return
	var sta: float = 1.0 - p.stamina / maxf(1.0, p.max_stamina)
	var hp: float = 1.0 - p.hp / maxf(1.0, p.max_hp)
	var san: float = 1.0 - p.sanity / maxf(1.0, p.max_sanity)
	var k := clampf(maxf(sta, maxf(hp, san * 0.8)), 0.0, 1.0)
	_heartbeat.volume_db = linear_to_db(lerpf(HEARTBEAT_BASE, HEARTBEAT_MAX, k))
	_hb_pitch = lerpf(_hb_pitch, 1.0 + 0.35 * clampf(maxf(hp, san * 0.6), 0.0, 1.0), 0.05)
	_heartbeat.pitch_scale = _hb_pitch
	if not _heartbeat.playing and not _heartbeat.stream_paused:
		_heartbeat.play()


func _update_whispers(p, dt: float) -> void:
	var pct: float = p.sanity / maxf(1.0, p.max_sanity)
	if pct < WHISPER_SANITY:
		var intensity := 1.0 - pct / WHISPER_SANITY
		var maxv := WHISPER_MAX_VOL * intensity
		_whisper_phase += _whisper_dir * WHISPER_SPEED * dt
		if _whisper_phase >= 1.0:
			_whisper_phase = 1.0
			_whisper_dir = -1.0
		elif _whisper_phase <= 0.0:
			_whisper_phase = 0.0
			_whisper_dir = 1.0
		var t := (sin(_whisper_phase * PI - PI / 2.0) + 1.0) / 2.0
		_set_cue(_whisper_m, maxv * (1.0 - t))
		_set_cue(_whisper_f, maxv * t)
	else:
		_whisper_m.stop()
		_whisper_f.stop()


func _set_cue(pl: AudioStreamPlayer, vol: float) -> void:
	if pl.stream == null:
		return
	pl.volume_db = -80.0 if vol <= 0.001 else linear_to_db(vol)
	if not pl.playing:
		pl.play()


## Added (Lua has only the whispers): at low sanity, sourceless creepy sounds from around the player.
func _update_hallucinations(p, dt: float) -> void:
	var pct: float = p.sanity / maxf(1.0, p.max_sanity)
	if pct >= 0.4:
		_hallu_t = maxf(_hallu_t, 6.0)
		return
	_hallu_t -= dt
	if _hallu_t > 0.0:
		return
	var sev := 1.0 - pct / 0.4
	_hallu_t = lerpf(22.0, 6.0, sev) * randf_range(0.7, 1.3)
	var name_: String = HALLUCINATION_SOUNDS[randi() % HALLUCINATION_SOUNDS.size()]
	var ang := randf() * TAU
	var dist := randf_range(5.0, 11.0) * _tile
	var pos: Vector2 = p.position + Vector2.from_angle(ang) * dist
	play(name_, pos, lerpf(0.25, 0.6, sev), randf_range(0.85, 1.05))
