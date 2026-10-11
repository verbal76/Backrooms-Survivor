extends Node
## Port of music.lua: random track selection avoiding the last 4, 4 s crossfade, a new track every
## 40-90 s (or when the current one ends). Added: mood (calm/intense) follows `danger` (0..1), and
## an explicit track can be requested (menu music, play_music("Vertigo")).

const FADE_DURATION := 4.0        # Music.fadeDuration
const SWITCH_MIN := 40.0          # 40 + random()*50
const SWITCH_RANGE := 50.0
const HISTORY := 4
const MOOD_MIN_GAP := 15.0        # don't flip mood more often than this
const INTENSE := ["hypertension", "deafness", "operating_room", "broken_circuit"]
const CALM := ["dark_house", "darker_house", "vertigo", "filthy_lab"]

var bank
var bus := "Music"
var danger := 0.0
var mood := "calm"
var enabled := false              # random-rotation mode (in a run)

var _cur: AudioStreamPlayer
var _next: AudioStreamPlayer
var _fading := false
var _fade_t := 0.0
var _fade_out_only := false
var _history: Array = []
var _switch_t := 0.0
var _switch_interval := 60.0
var _since_mood := 0.0
var current_name := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cur = _make_player()
	_next = _make_player()


func _make_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = -80.0
	add_child(p)
	return p


static func _db(lin: float) -> float:
	return -80.0 if lin <= 0.0001 else linear_to_db(lin)


func is_playing() -> bool:
	return _cur != null and _cur.playing


## Start rotation (a run): crossfade to a random track suited to the current mood.
func start_rotation() -> void:
	enabled = true
	_play_stream(_pick_for_mood(), false)


## Play a specific track by name (music tracks or any sound such as the UI menu loop), crossfading.
func play_track(track_name: String, loop := false) -> bool:
	enabled = false
	var key := ""
	var pool: Dictionary = bank.music
	var keys: Array = bank.resolve(track_name, pool)
	if keys.is_empty():
		pool = bank.sounds
		keys = bank.resolve(track_name, pool)
	if keys.is_empty():
		return false
	key = keys[randi() % keys.size()]
	var s: AudioStream = bank.get_loop_stream(key, pool) if loop or pool == bank.sounds else bank.get_stream(key, pool)
	if s == null:
		return false
	_start(s, key)
	return true


func stop(fade := 1.5) -> void:
	enabled = false
	if _cur.playing and fade > 0.0:
		_fade_out_only = true
		_begin_fade(fade)
	else:
		_cur.stop()
		_next.stop()
		_fading = false
		current_name = ""


func _pick_for_mood() -> String:
	var group: Array = INTENSE if mood == "intense" else CALM
	var avail: Array = []
	for k in group:
		if bank.music.has(k) and not _history.has(k):
			avail.append(k)
	if avail.is_empty():
		_history.clear()
		for k in bank.music:
			avail.append(k)
		if avail.is_empty():
			return ""
	return avail[randi() % avail.size()]


func _play_stream(key: String, _loop: bool) -> void:
	if key == "":
		return
	var s: AudioStream = bank.get_stream(key, bank.music)
	if s == null:
		return
	_history.append(key)
	if _history.size() > HISTORY:
		_history.pop_front()
	_switch_t = 0.0
	_switch_interval = SWITCH_MIN + randf() * SWITCH_RANGE
	_start(s, key)


var _fade_len := FADE_DURATION

func _start(s: AudioStream, key: String) -> void:
	current_name = key
	if _fading:  # finish the previous fade instantly
		_finish_fade()
	_fade_out_only = false
	if _cur.playing:
		_next.stream = s
		_next.volume_db = -80.0
		_next.play()
		_begin_fade(FADE_DURATION)
	else:
		_cur.stream = s
		_cur.volume_db = 0.0
		_cur.play()


func _begin_fade(len: float) -> void:
	_fading = true
	_fade_t = 0.0
	_fade_len = maxf(0.05, len)


func _finish_fade() -> void:
	_cur.stop()
	if not _fade_out_only:
		var t := _cur
		_cur = _next
		_next = t
		_cur.volume_db = 0.0
	_next.stop()
	_next.volume_db = -80.0
	_fading = false
	_fade_out_only = false


func _process(dt: float) -> void:
	if _cur == null:
		return
	if _fading:
		_fade_t += dt
		var p := minf(1.0, _fade_t / _fade_len)
		_cur.volume_db = _db(1.0 - p)
		if not _fade_out_only:
			_next.volume_db = _db(p)
		if p >= 1.0:
			_finish_fade()
	if not enabled:
		return
	_since_mood += dt
	_switch_t += dt
	var want := mood
	if danger > 0.55:
		want = "intense"
	elif danger < 0.25:
		want = "calm"
	if not _fading and want != mood and _since_mood >= MOOD_MIN_GAP:
		mood = want
		_since_mood = 0.0
		_play_stream(_pick_for_mood(), false)
	elif not _fading and (_switch_t >= _switch_interval or not _cur.playing):
		_play_stream(_pick_for_mood(), false)
