extends SceneTree
## Shared smoke test (runs in CI on the authoritative source before any platform export, and locally):
##   godot --headless --path godot -s tools/smoke_test.gd
## Exits non-zero if the real game scene cannot load, start a run, run for a while with enemies and combat,
## or if any required system is missing. Platform-specific code paths are covered by their own checks.

const REQUIRED_SYSTEMS := ["input", "audio", "fx", "lighting", "weapons", "enemies", "objects", "traps", "ui"]


func _init() -> void:
	var failures: Array[String] = []
	var packed = load("res://scenes/game.tscn")
	if packed == null:
		_fail(["game.tscn failed to load"])
		return
	var g = packed.instantiate()
	root.add_child(g)
	await process_frame
	for key in REQUIRED_SYSTEMS:
		if g.get(key) == null or not is_instance_valid(g.get(key)):
			failures.append("system missing: " + key)
	if g.state != "title" and g.state != "playing":
		failures.append("unexpected initial state: " + g.state)
	g.start_run()
	for i in 20:
		await physics_frame
	if g.state != "playing":
		failures.append("run did not start (state=%s)" % g.state)
	# combat + enemy + damage pipeline
	if g.enemies:
		for k in ["hound", "crawler", "wretch", "shade", "skin stealer", "crow"]:
			g.enemies.spawn(k, g.player.tile_pos + Vector2(3, 0.5), true)
	var hp0: float = g.player.hp
	for i in 600:
		await physics_frame
	if g.enemies and g.enemies.get_enemies().is_empty():
		failures.append("enemies vanished")
	if g.player.hp >= hp0 and g.state == "playing":
		failures.append("enemies never damaged the player in 10 s")
	# map streaming
	if g.map.chunks.size() < 9:
		failures.append("map did not stream chunks")
	# build provenance must be readable
	var info: Dictionary = preload("res://scripts/patcher.gd").read_info()
	for k in ["build", "sha"]:
		if not info.has(k):
			failures.append("build_info.json missing key: " + k)
	if failures.is_empty():
		print("SMOKE TEST PASSED (systems=%d chunks=%d hp %.0f -> %.0f)" % [g.systems.size(), g.map.chunks.size(), hp0, g.player.hp])
		quit(0)
	else:
		_fail(failures)


func _fail(failures: Array) -> void:
	for f in failures:
		printerr("SMOKE TEST FAILURE: ", f)
	quit(1)
