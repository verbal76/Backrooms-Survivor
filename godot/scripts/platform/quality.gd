extends RefCounted
## Quality presets (Options > Quality: Low / Medium / High). One table drives every cost knob so the
## trade-offs are easy to retune after profiling on a real Steam Deck.
## `const Quality = preload("res://scripts/platform/quality.gd")` (no class_name, OTA friendly).
##
##   particles   multiplier on effect emission counts and on the particle pool capacity
##   motes       dust motes around the headlamp beam (max 44)
##   decals      blood / scorch decals kept on the floor
##   fixtures    ceiling-light point lights alive at once (max 8)
##   shadow      headlamp shadow filter: 0 = hard (cheapest), 1 = PCF5 smooth 1, 2 = PCF5 smooth 2
##   post        0 = post-FX pass off, 1 = on without grain / aberration / warp, 2 = everything
##   stream      chunk generation / draw radius around the player, in tiles
##   figs        low-sanity shadow figures (max 2)

const PRESETS := [
	{"name": "Low", "particles": 0.40, "motes": 0, "decals": 70, "fixtures": 3, "shadow": 0, "post": 0, "stream": 22, "figs": 1},
	{"name": "Medium", "particles": 0.70, "motes": 22, "decals": 130, "fixtures": 5, "shadow": 1, "post": 1, "stream": 26, "figs": 2},
	{"name": "High", "particles": 1.00, "motes": 44, "decals": 200, "fixtures": 8, "shadow": 2, "post": 2, "stream": 32, "figs": 2},
]

static var level := 2


static func preset(lvl: int) -> Dictionary:
	return PRESETS[clampi(lvl, 0, PRESETS.size() - 1)]


static func current() -> Dictionary:
	return preset(level)


## Push the preset into every system that has a matching `set_quality(preset)` hook. Safe to call at any time.
static func apply(game, lvl: int) -> void:
	level = clampi(lvl, 0, PRESETS.size() - 1)
	if game == null:
		return
	var p := preset(level)
	for key in ["fx", "lighting"]:
		var sys = game.get(key)
		if sys != null and sys.has_method("set_quality"):
			sys.set_quality(p)
	if "stream_radius" in game:
		game.stream_radius = int(p.stream)
