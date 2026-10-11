extends RefCounted
## Tiny procedural SFX generator for the juice layer (impacts, stingers, chimes, heartbeat thump).
## Everything is rendered once into a mono 16-bit AudioStreamWAV (22.05 kHz) and cached, so playing
## one costs the same as any other sample. Names are "fx_<kind>_<variant>"; the variant number only
## changes the noise seed and a small pitch offset, which gives the pitch-varied layered feel for free.
## Registered in SoundBank under the keys listed in NAMES (the bank resolves "fx_thud" to a random variant).

const RATE := 22050
## kind -> variant count
const NAMES := {
	"fx_thud": 3, "fx_bone": 2, "fx_slash": 3, "fx_crunch": 3, "fx_ping": 3, "fx_tink": 2,
	"fx_boom": 1, "fx_level": 1, "fx_streak": 1, "fx_pickup": 2, "fx_thump": 2, "fx_warn": 1,
	"fx_miss": 2, "fx_hurt": 2, "fx_zap": 1, "fx_wet": 2,
	"fx_caw": 3, "fx_flap": 2,
}

static var _cache := {}


static func has(key: String) -> bool:
	var parts := _split(key)
	return NAMES.has(parts[0])


static func _split(key: String) -> Array:
	var i := key.rfind("_")
	if i > 3 and key.substr(i + 1).is_valid_int():
		return [key.substr(0, i), int(key.substr(i + 1))]
	return [key, 1]


static func make(key: String) -> AudioStream:
	if _cache.has(key):
		return _cache[key]
	var parts := _split(key)
	var kind: String = parts[0]
	var variant: int = parts[1]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) & 0x7fffffff
	var pv := 1.0 + (variant - 2) * 0.09          # per-variant pitch offset
	var d: PackedFloat32Array
	match kind:
		"fx_thud":   d = _thud(rng, pv, 0.16, 150.0, 55.0, 0.5)
		"fx_bone":   d = _thud(rng, pv, 0.2, 210.0, 80.0, 0.9)
		"fx_slash":  d = _slash(rng, pv)
		"fx_crunch": d = _crunch(rng, pv)
		"fx_ping":   d = _ping(rng, pv)
		"fx_tink":   d = _tink(rng, pv)
		"fx_boom":   d = _boom(rng)
		"fx_level":  d = _chime([523.25, 659.25, 783.99, 1046.5], 0.11, 0.9, 1.0)
		"fx_streak": d = _chime([392.0, 587.33], 0.07, 0.45, 0.8)
		"fx_pickup": d = _chirp(rng, 650.0 * pv, 1500.0 * pv, 0.13)
		"fx_thump":  d = _thud(rng, pv, 0.22, 78.0, 42.0, 0.05)
		"fx_warn":   d = _warn()
		"fx_miss":   d = _miss(rng, pv)
		"fx_hurt":   d = _hurt(rng, pv)
		"fx_zap":    d = _zap(rng)
		"fx_wet":    d = _wet(rng, pv)
		"fx_caw":    d = _caw(rng, pv)
		"fx_flap":   d = _flap(rng, pv)
		_:           d = PackedFloat32Array([0.0])
	var s := _to_wav(d)
	_cache[key] = s
	return s


static func _to_wav(d: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(d.size() * 2)
	var peak := 0.0001
	for v in d:
		peak = maxf(peak, absf(v))
	var g := 0.92 / maxf(peak, 0.92)           # only normalise down, never up
	for i in d.size():
		bytes.encode_s16(i * 2, int(clampf(d[i] * g, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


static func _buf(sec: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(sec * RATE))
	return a


## Pitch-swept sine body with a noise click on top (flesh / bone / heartbeat).
static func _thud(rng: RandomNumberGenerator, pv: float, sec: float, f0: float, f1: float, click: float) -> PackedFloat32Array:
	var a := _buf(sec)
	var ph := 0.0
	var lp := 0.0
	var n := a.size()
	for i in n:
		var t := float(i) / n
		var f := lerpf(f0, f1, 1.0 - pow(1.0 - t, 3.0)) * pv
		ph += TAU * f / RATE
		var env := exp(-t * 6.0) * minf(1.0, float(i) / 40.0)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.3
		a[i] = sin(ph) * env * 0.9 + lp * click * exp(-t * 28.0)
	return a


static func _slash(rng: RandomNumberGenerator, pv: float) -> PackedFloat32Array:
	var a := _buf(0.2)
	var n := a.size()
	var lp := 0.0
	var bp := 0.0
	for i in n:
		var t := float(i) / n
		var env := sin(clampf(t * 1.6, 0.0, 1.0) * PI * 0.5) * exp(-t * 4.5)
		var k := lerpf(0.55, 0.12, t) * pv
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * k
		bp += (lp - bp) * 0.5
		a[i] = (lp - bp) * 2.4 * env
	# metallic "shing" at the start
	for i in int(n * 0.35):
		var t2 := float(i) / n
		a[i] += sin(TAU * 2900.0 * pv * i / RATE) * exp(-t2 * 38.0) * 0.28
	return a


static func _crunch(rng: RandomNumberGenerator, pv: float) -> PackedFloat32Array:
	var a := _thud(rng, pv, 0.34, 120.0, 34.0, 0.0)
	var lp := 0.0
	for i in int(0.09 * RATE):
		var t := float(i) / (0.09 * RATE)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.55
		a[i] += lp * exp(-t * 7.0) * 0.8
	# wet squelch tail
	for i in range(int(0.04 * RATE), int(0.18 * RATE)):
		var t3 := float(i) / RATE
		a[i] += sin(TAU * (240.0 - t3 * 600.0) * t3) * exp(-(t3 - 0.04) * 22.0) * 0.18
	return a


static func _ping(rng: RandomNumberGenerator, pv: float) -> PackedFloat32Array:
	var a := _buf(0.2)
	var n := a.size()
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		ph += TAU * lerpf(2300.0, 1500.0, t) * pv / RATE
		a[i] = sin(ph) * exp(-t * 14.0) * 0.5 + (rng.randf_range(-1.0, 1.0)) * exp(-t * 90.0) * 0.5
	return a


static func _tink(_rng: RandomNumberGenerator, pv: float) -> PackedFloat32Array:
	var a := _buf(0.26)
	var n := a.size()
	for bounce in 3:
		var off := int(n * [0.0, 0.3, 0.52][bounce])
		var amp: float = [0.5, 0.28, 0.14][bounce]
		for i in range(0, int(n * 0.22)):
			if off + i >= n:
				break
			var t := float(i) / (n * 0.22)
			a[off + i] += (sin(TAU * 3400.0 * pv * i / RATE) + 0.5 * sin(TAU * 5200.0 * pv * i / RATE)) * exp(-t * 9.0) * amp
	return a


static func _boom(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var a := _buf(1.0)
	var n := a.size()
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / n
		ph += TAU * lerpf(95.0, 26.0, 1.0 - pow(1.0 - t, 2.5)) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * lerpf(0.35, 0.04, t)
		a[i] = sin(ph) * exp(-t * 4.0) * 0.85 + lp * exp(-t * 5.0) * 0.9
	return a


static func _chime(notes: Array, step: float, tail: float, vol: float) -> PackedFloat32Array:
	var a := _buf(step * notes.size() + tail)
	for k in notes.size():
		var f: float = notes[k]
		var off := int(k * step * RATE)
		for i in range(0, a.size() - off):
			var t := float(i) / RATE
			if t > tail:
				break
			var env := exp(-t * 4.5) * minf(1.0, t * 300.0)
			a[off + i] += (sin(TAU * f * t) + 0.35 * sin(TAU * f * 2.0 * t) + 0.15 * sin(TAU * f * 3.01 * t)) * env * 0.3 * vol
	return a


static func _chirp(rng: RandomNumberGenerator, f0: float, f1: float, sec: float) -> PackedFloat32Array:
	var a := _buf(sec + 0.1)
	var ph := 0.0
	for i in a.size():
		var t := float(i) / RATE
		var u := clampf(t / sec, 0.0, 1.0)
		ph += TAU * lerpf(f0, f1, u * u) / RATE
		a[i] = sin(ph) * exp(-t * 14.0) * 0.5 + rng.randf_range(-1.0, 1.0) * exp(-t * 120.0) * 0.1
	return a


## Soft rising tremolo drone: the enemy wind-up "something is about to strike" cue.
static func _warn() -> PackedFloat32Array:
	var a := _buf(0.32)
	var n := a.size()
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		ph += TAU * lerpf(110.0, 190.0, t) / RATE
		var env := sin(t * PI) * (0.65 + 0.35 * sin(t * 60.0))
		a[i] = (sin(ph) + 0.4 * sin(ph * 2.01)) * env * 0.5
	return a


## Near-miss: descending air whoosh with a low drop.
static func _miss(rng: RandomNumberGenerator, pv: float) -> PackedFloat32Array:
	var a := _buf(0.3)
	var n := a.size()
	var lp := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		lp += (rng.randf_range(-1.0, 1.0) - lp) * lerpf(0.5, 0.06, t)
		ph += TAU * lerpf(220.0, 60.0, t) * pv / RATE
		a[i] = (lp * 1.6 + sin(ph) * 0.5) * sin(clampf(t * 3.0, 0.0, 1.0) * PI * 0.5) * exp(-t * 3.5) * 0.7
	return a


static func _hurt(rng: RandomNumberGenerator, pv: float) -> PackedFloat32Array:
	var a := _thud(rng, pv, 0.28, 180.0, 50.0, 0.7)
	for i in a.size():
		var t := float(i) / RATE
		a[i] += sin(TAU * 420.0 * t) * exp(-t * 30.0) * 0.18
	return a


static func _zap(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var a := _buf(0.25)
	var n := a.size()
	for i in n:
		var t := float(i) / n
		var buzz := 1.0 if sin(TAU * 140.0 * i / RATE) > 0.0 else -1.0
		a[i] = (buzz * 0.4 + rng.randf_range(-1.0, 1.0) * 0.5) * exp(-t * 9.0) * (0.5 + 0.5 * sin(t * 90.0))
	return a


static func _wet(rng: RandomNumberGenerator, pv: float) -> PackedFloat32Array:
	var a := _buf(0.16)
	var n := a.size()
	var lp := 0.0
	for i in n:
		var t := float(i) / n
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.2
		a[i] = (lp * 1.5 + sin(TAU * (160.0 + 380.0 * t) * pv * i / RATE) * 0.3) * exp(-t * 9.0) * 0.8
	return a


## Crow caw: raspy descending buzz (sawtooth through a vocal-ish low-pass, 60 Hz amplitude roughness), 1-2 syllables.
static func _caw(rng: RandomNumberGenerator, pv: float) -> PackedFloat32Array:
	var a := _buf(0.36)
	var n := a.size()
	var ph := 0.0
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / n
		var syl := fposmod(t * 1.8, 1.0)                       # two syllables
		var env := sin(clampf(syl * 1.15, 0.0, 1.0) * PI) * (1.0 - t * 0.35)
		var f := lerpf(720.0, 430.0, syl) * pv
		ph += f / RATE
		var saw := 2.0 * fposmod(ph, 1.0) - 1.0
		lp += (saw - lp) * 0.32
		lp2 += (lp - lp2) * 0.5
		var rough := 0.65 + 0.35 * sin(TAU * 62.0 * i / RATE)
		a[i] = (lp2 * 1.5 + rng.randf_range(-1.0, 1.0) * 0.12) * env * rough
	return a


## One wing beat: short low noise whump.
static func _flap(rng: RandomNumberGenerator, pv: float) -> PackedFloat32Array:
	var a := _buf(0.13)
	var n := a.size()
	var lp := 0.0
	for i in n:
		var t := float(i) / n
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.12 * pv
		a[i] = lp * 2.2 * sin(t * PI) * exp(-t * 3.0) * 0.6
	return a
