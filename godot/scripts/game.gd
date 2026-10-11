extends Node2D
## Game root. Owns the world, player, run state, and loads the pluggable systems.
## See godot/ARCHITECTURE.md for the contract every system follows.

const Patcher = preload("res://scripts/patcher.gd")
const TILE := 52
const DAY_SECONDS := 300.0   # 5 minutes = 1 day

## Systems are optional scripts at these paths. If a file exists it is instanced, given
## `setup(game)`, and ticked while state == "playing". Later entries tick later.
const SYSTEM_PATHS := {
	"input": "res://scripts/systems/input.gd",
	"audio": "res://scripts/systems/audio.gd",
	"fx": "res://scripts/systems/fx.gd",
	"lighting": "res://scripts/systems/lighting.gd",
	"weapons": "res://scripts/systems/weapons.gd",
	"enemies": "res://scripts/systems/enemies.gd",
	"objects": "res://scripts/systems/objects.gd",
	"ui": "res://scripts/systems/ui.gd",
}
const SYSTEM_ORDER := ["input", "audio", "fx", "lighting", "weapons", "enemies", "objects", "ui"]

signal state_changed(new_state: String)
signal enemy_killed(tile_pos: Vector2, kind: String, xp: int)
signal player_died
signal chunk_spawned(cx: int, cy: int)

var map: WorldMap
var player: Player
var camera: Camera2D
var world: Node2D            # parent for all lit world entities (enemies, items, bullets...)
var input: GameInput
var audio: Node = NullAudio.new()
var fx: Node = NullFx.new()
var lighting: Node
var weapons: Node
var enemies: Node
var objects: Node
var ui: Node
var systems: Array[Node] = []

## "title" | "playing" | "paused" | "perk" | "dead" | "portal"
var state := "title"
var run_time := 0.0          # seconds survived this run (pauses with the game)
var day := 1
var kills := 0
var _views := {}
var _hitstop := 0.0


func _ready() -> void:
	map = WorldMap.new()
	map.ensure_chunk(0, 0)

	world = Node2D.new()
	add_child(world)

	player = Player.new()
	player.map = map
	player.tile_pos = map.find_spawn()
	player.position = player.tile_pos * TILE
	world.add_child(player)
	player.died.connect(_on_player_died)

	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 12.0
	player.add_child(camera)

	for key in SYSTEM_ORDER:
		var path: String = SYSTEM_PATHS[key]
		if not ResourceLoader.exists(path):
			continue
		var node: Node = load(path).new()
		node.name = key.capitalize()
		add_child(node)
		set(key, node)
		systems.append(node)
	for node in systems:
		if node.has_method("setup"):
			node.setup(self)

	if ui == null:        # no menu system yet: start straight away
		set_state("playing")
	_stream_chunks()


func _physics_process(delta: float) -> void:
	if _hitstop > 0.0:
		_hitstop -= delta
		return
	if input:
		input.tick(delta)
	# non-playing states are driven by the ui system (menus, pause, perk pick, death)
	if state == "playing":
		run_time += delta
		day = 1 + int(run_time / DAY_SECONDS)
		var light: float = lighting.light_level_at_player() if lighting and lighting.has_method("light_level_at_player") else 0.3
		var in_aim := input.aim_world if input else get_global_mouse_position()
		player.step(delta, input.move if input else Vector2.ZERO, input.sprint if input else false,
			in_aim, input.fire if input else false, light)
		_stream_chunks()
		for node in systems:
			if node != input and node.has_method("tick"):
				node.tick(delta)
	elif ui and ui.has_method("tick_menu"):
		ui.tick_menu(delta)
	if input:
		input.end_frame()


func set_state(s: String) -> void:
	if s == state:
		return
	state = s
	state_changed.emit(s)


## Start (or restart) a run. Systems implement reset_run() to clear their entities.
func start_run() -> void:
	run_time = 0.0
	day = 1
	kills = 0
	var fresh := Player.new()
	for prop in ["hp", "max_hp", "stamina", "max_stamina", "sanity", "max_sanity", "hydration", "max_hydration",
			"speed_mult", "dmg_mult", "dmg_taken_mult", "invuln_time_mult", "invuln_time", "noise", "xp", "level",
			"xp_need", "almond_water", "bandages", "food", "batteries", "headlamp_on", "current_streak",
			"best_run_streak", "pending_perk_choice", "active_run_perks"]:
		player.set(prop, fresh.get(prop))
	fresh.free()
	player.vel = Vector2.ZERO
	player.tile_pos = map.find_spawn()
	for node in systems:
		if node.has_method("reset_run"):
			node.reset_run()
	set_state("playing")


# ---- API used by systems -------------------------------------------------

## Damage the player. from_px is the world-pixel position of the attacker (for knockback/juice).
func damage_player(amount: float, from_px := Vector2.ZERO) -> bool:
	var died := player.take_damage(amount)
	if player.dmg_flash > 0.0 and player.invuln_time > 0.0:
		fx.shake(8.0, 0.25)
		fx.flash(Color(0.8, 0.0, 0.0, 0.35), 0.2)
		fx.blood(player.position, 0.6)
	return died


## Systems call this when an enemy dies; it grants XP/streak and notifies listeners (item drops, UI).
func report_kill(tile_pos: Vector2, kind: String, xp: int) -> void:
	kills += 1
	player.record_kill()
	if player.add_xp(xp):
		fx.float_text(player.position + Vector2(0, -70), "LEVEL UP!", Color(1.0, 0.85, 0.2))
		if player.pending_perk_choice:
			set_state("perk")
	enemy_killed.emit(tile_pos, kind, xp)


func hitstop(seconds: float) -> void:
	_hitstop = maxf(_hitstop, seconds)


func _on_player_died() -> void:
	player_died.emit()
	set_state("dead")


func _stream_chunks() -> void:
	map.ensure_around(player.tile_pos, 32)
	for c in map.drain_new_chunks():
		var view := ChunkView.new()
		world.add_child(view)
		world.move_child(view, 0)
		view.setup(map, c.x, c.y)
		chunk_spawned.emit(c.x, c.y)
		_views[c] = view
