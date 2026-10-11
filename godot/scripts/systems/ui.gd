extends Node
## UI system (port of the screens / HUD / key handling in main.lua + options.lua + progression.lua).
##
## Public API (for other systems / the integrator):
##   game.ui.add_message(text, color := Color.WHITE, life := 3.0)   centre-screen message log (Lua addMessage)
##   game.ui.options          GameOptions   music_volume, sfx_volume, brightness, headlamp_brightness, aim_assist...
##   game.ui.progression      Progression   tokens / upgrades / saves
##   game.ui.difficulty       int 1..4 (Easy, Normal, Getting Worse, Hell)
##   game.ui.run_mods         Dictionary    per-run numbers other systems must honour (see _build_run_mods)
##   game.ui.player_name      String
##   game.ui.aim_assist_enabled   bool
##   game.ui.show_portal_prompt() / game.set_state("portal")   opens the escape/stay prompt
##   game.ui.portal_cooldown  float > 0 while a dismissed prompt must not reopen
##   signals: portal_choice(escape: bool), perk_chosen(id), run_started
## Same dictionary is also published as game.get_meta("run_mods") and the difficulty as game.get_meta("difficulty").
## Optional hooks the UI reads if present (all null-guarded): see _bomb_count(), _battery(), _portal(),
## _map_markers() and _effects() below.

const TitleScreen = preload("res://scripts/ui/title_screen.gd")
const StoryScreen = preload("res://scripts/ui/story_screen.gd")
const CharSelectScreen = preload("res://scripts/ui/charselect_screen.gd")
const NameEntryScreen = preload("res://scripts/ui/nameentry_screen.gd")
const ShopScreen = preload("res://scripts/ui/shop_screen.gd")
const OptionsScreen = preload("res://scripts/ui/options_screen.gd")
const PauseScreen = preload("res://scripts/ui/pause_screen.gd")
const PerkScreen = preload("res://scripts/ui/perk_screen.gd")
const DeathScreen = preload("res://scripts/ui/death_screen.gd")
const PortalScreen = preload("res://scripts/ui/portal_screen.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const Overlays = preload("res://scripts/ui/overlays.gd")

signal portal_choice(escape: bool)
signal perk_chosen(id: String)
signal run_started

# Lua startGame() difficulty tables (index = difficulty - 1)
const DIFF_ENEMY_HP := [1.0, 1.0, 1.35, 1.8]
const DIFF_ENEMY_DMG := [0.70, 1.20, 1.4, 2.0]
const DIFF_ENEMY_SPD := [1.0, 1.0, 1.10, 1.20]
const DIFF_SANITY := [1.0, 1.0, 1.5, 2.0]
const DIFF_HYDRATION := [0.9, 1.0, 1.3, 1.7]
const DIFF_SPAWN := [1.5, 2.0, 2.5, 3.0]
const DIFF_MAX_ENEMIES := [90, 100, 110, 130]
const DIFF_AMBIENT := [0.3, 0.2, 0.1, 0.05]
const DAY_LENGTH := 120.0           # Lua dayLength (seconds); game.gd currently uses 300
const INTRO_TIME := 3.0

var game
var input: GameInput
var options := GameOptions.new()
var progression: Progression
var difficulty := 1:
	set(v):
		difficulty = clampi(v, 1, 4)
		options.difficulty = difficulty
var player_name := ""
var run_mods := {}
var tokens_earned := 0
var victory_tokens := 0
var perk_choices: Array = []
var portal_cooldown := 0.0
var portal_declined := false
var intro_t := 0.0
var screen_name := ""
var screens := {}
var messages: Array = []
var handle_item_hotkeys := true      # set false if another system consumes use_water/bandage/food
var aim_assist_enabled: bool:
	get:
		return options.aim_assist and difficulty < 3

var hud: Control
var overlays: Control
var menu_layer: CanvasLayer
var hud_layer: CanvasLayer
var fade: ColorRect
var clock := 0.0
var shop_return := "title"
var _death_recorded := false
var _prev_state := "title"
var _last_weapon := -1
var _last_lamp := true
var _fade_tween: Tween


func setup(g) -> void:
	game = g
	input = g.input
	options.load_from_disk()
	progression = Progression.new()
	difficulty = options.difficulty
	options.apply_window()
	_build_run_mods()
	game.set_meta("run_mods", run_mods)
	game.set_meta("difficulty", difficulty)

	hud_layer = CanvasLayer.new()
	hud_layer.layer = 20
	add_child(hud_layer)
	hud = Hud.new()
	hud.bind(self, game)
	hud_layer.add_child(hud)
	overlays = Overlays.new()
	overlays.bind(self, game)
	hud_layer.add_child(overlays)

	menu_layer = CanvasLayer.new()
	menu_layer.layer = 30
	add_child(menu_layer)
	var defs := {
		"story": StoryScreen, "charselect": CharSelectScreen, "nameentry": NameEntryScreen, "title": TitleScreen,
		"shop": ShopScreen, "options": OptionsScreen, "pause": PauseScreen, "perk": PerkScreen,
		"death": DeathScreen, "portal": PortalScreen,
	}
	for k in defs:
		var s: UIScreen = defs[k].new()
		s.name = k.capitalize()
		s.bind(self, game)
		menu_layer.add_child(s)
		screens[k] = s

	var fl := CanvasLayer.new()
	fl.layer = 45
	add_child(fl)
	fade = ColorRect.new()
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fl.add_child(fade)

	game.state_changed.connect(_on_state_changed)
	game.player.leveled_up.connect(_on_level_up)
	game.enemy_killed.connect(_on_enemy_killed)
	game.player.damaged.connect(_on_player_damaged)
	get_viewport().size_changed.connect(_on_resized)

	player_name = ""
	game.set_state("title")
	_on_state_changed("title")
	show_screen("story")
	_ui_music(true)


func _process(delta: float) -> void:
	clock += delta
	if game == null:
		return
	if portal_cooldown > 0.0:
		portal_cooldown -= delta
	# messages age in real time so they still fade while a menu is open
	for m in messages:
		m.age += delta
	while messages.size() > 0 and messages[0].age > messages[0].life:
		messages.pop_front()
	var active: UIScreen = screens.get(screen_name)
	if active and active.visible:
		active.frame(delta)
	var playing: bool = game.state in ["playing", "paused", "perk", "portal"]
	hud.visible = playing
	overlays.visible = playing
	if playing:
		hud.frame(delta)
		overlays.frame(delta)
	_update_cursor()


func _update_cursor() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var want := Input.MOUSE_MODE_VISIBLE
	if game.state == "playing" and input and input.active_mode() == "keyboard":
		want = Input.MOUSE_MODE_HIDDEN
	if Input.mouse_mode != want:
		Input.mouse_mode = want


func _on_resized() -> void:
	for s in screens.values():
		s.queue_redraw()


# ---- tick hooks (called by game.gd) ----------------------------------------------------------------

func reset_run() -> void:
	messages.clear()
	_death_recorded = false
	portal_declined = false
	portal_cooldown = 0.0
	tokens_earned = 0
	victory_tokens = 0
	perk_choices = []
	intro_t = INTRO_TIME
	_build_run_mods()
	var p = game.player
	progression.apply_to_run(difficulty, p, run_mods)
	var w = game.weapons
	if w and "ammo" in w:
		w.ammo += run_mods.start_ammo
	if run_mods.start_bombs > 0:
		_add_bombs(run_mods.start_bombs)
	_last_weapon = -1
	_last_lamp = true
	hud.reset()
	add_message("%s has entered the Backrooms" % _name(), Color(0.9, 0.8, 0.2))
	run_started.emit()


## Runs every physics frame while state == "playing".
func tick(dt: float) -> void:
	if intro_t > 0.0:
		intro_t -= dt
	if input.just("pause"):
		game.set_state("paused")
		return
	if input.just("options"):
		game.set_state("paused")
		show_screen("options", "pause")
		return
	if handle_item_hotkeys:
		_item_hotkeys()
	_watch_changes()


## Runs every physics frame while state != "playing".
func tick_menu(dt: float) -> void:
	var s: UIScreen = screens.get(screen_name)
	if s and s.visible and s.age >= s.input_delay:
		s.handle_input(input, dt)


func _item_hotkeys() -> void:
	var p = game.player
	if input.just("use_water"):
		if p.use_almond_water():
			add_message("Drank Almond Water", Color(0.3, 0.8, 1))
			game.fx.float_text(p.position + Vector2(0, -60), "+H2O", Color(0.3, 0.8, 1))
		else:
			add_message("NO ALMOND WATER", Color(1, 0.3, 0.3))
	if input.just("use_bandage"):
		if p.use_bandage():
			add_message("Used Bandage", Color(0.3, 1, 0.3))
			game.fx.float_text(p.position + Vector2(0, -60), "+HP", Color(0.3, 1, 0.3))
			game.fx.burst(p.position, "pickup", Vector2.ZERO)
		else:
			add_message("NO BANDAGES", Color(1, 0.3, 0.3))
	if input.just("use_food"):
		if p.use_food():
			add_message("Ate Food", Color(0.9, 0.7, 0.3))
			game.fx.float_text(p.position + Vector2(0, -60), "+STAMINA", Color(0.9, 0.7, 0.3))
		else:
			add_message("NO FOOD", Color(1, 0.3, 0.3))


func _watch_changes() -> void:
	var w = game.weapons
	if w and "current" in w:
		var cur: int = w.current
		if _last_weapon >= 0 and cur != _last_weapon:
			var info := weapon_info()
			add_message(String(info.get("name", "?")).to_upper(), UITheme.color_of(info.get("color", Color.WHITE)))
			hud.pop_weapon()
		_last_weapon = cur
	var lamp: bool = game.player.headlamp_on
	if lamp != _last_lamp:
		add_message("HEADLAMP ON" if lamp else "HEADLAMP OFF", Color(1, 0.95, 0.7))
		_last_lamp = lamp


# ---- state machine -----------------------------------------------------------------------------------

func _on_state_changed(s: String) -> void:
	var prev := _prev_state
	_prev_state = s
	match s:
		"title":
			if screen_name not in ["story", "charselect", "nameentry", "title", "shop", "options"]:
				show_screen("title")
		"playing":
			_hide_all()
			if prev == "title" or prev == "dead":
				_flash_fade(0.6, 0.5)
		"paused":
			show_screen("pause")
		"perk":
			var excl: Array = []
			for pk in game.player.active_run_perks:
				excl.append(pk.id)
			perk_choices = Progression.roll_perk_choice(excl)
			if perk_choices.size() < 2:
				game.player.pending_perk_choice = false
				game.set_state.call_deferred("playing")
			else:
				show_screen("perk")
		"dead":
			_record_death()
			show_screen("death")
		"portal":
			show_screen("portal", "prompt")


func _record_death() -> void:
	if _death_recorded:
		return
	_death_recorded = true
	var p = game.player
	tokens_earned = progression.add_run_results(difficulty, game.day, game.kills, p.best_run_streak, game.run_time)
	add_message("%s died" % _name(), Color(1, 0.2, 0.2))


func show_screen(name: String, arg = null) -> void:
	if screens.has(screen_name) and screen_name != name:
		screens[screen_name].close()
	screen_name = name
	var s: UIScreen = screens[name]
	s.open(arg)
	_flash_fade(0.85, 0.28)


func _hide_all() -> void:
	for s in screens.values():
		s.close()
	screen_name = ""


func _flash_fade(from_alpha: float, secs: float) -> void:
	if _fade_tween:
		_fade_tween.kill()
	fade.color = Color(0, 0, 0, from_alpha)
	_fade_tween = create_tween()
	_fade_tween.tween_property(fade, "color:a", 0.0, secs)


## Used by Lua-equivalent actions on the title / death / pause screens.
func _ui_music(on: bool) -> void:
	var a = game.audio
	if on and a.has_method("play_ui_music"):
		a.play_ui_music()
	elif not on and a.has_method("stop_ui_music"):
		a.stop_ui_music()


func start_game() -> void:
	_ui_music(false)
	options.save()
	progression.save()
	_hide_all()
	game.start_run()


func back_to_title() -> void:
	_ui_music(true)
	options.save()
	game.set_state("title")
	show_screen("title")


func show_portal_prompt() -> void:
	if game.state == "playing" and portal_cooldown <= 0.0:
		game.set_state("portal")


func resolve_portal(escape: bool) -> void:
	portal_choice.emit(escape)
	if escape:
		var base := progression.add_run_results(difficulty, game.day, game.kills, game.player.best_run_streak, game.run_time)
		victory_tokens = base * 2
		progression.add_tokens(difficulty, base)       # Lua: 2x total tokens for escaping
		show_screen("portal", "victory")
	else:
		portal_declined = true
		_portal_deactivate()
		add_message("LIVING LEGEND MODE!", Color(1, 0.8, 0.2))
		add_message("No more exits. Survive forever.", Color(0.7, 0.6, 0.5))
		game.set_state("playing")


func dismiss_portal_prompt() -> void:
	portal_cooldown = 4.0
	game.set_state("playing")


func choose_perk(i: int) -> void:
	if perk_choices.size() < 2:
		return
	var perk: Dictionary = perk_choices[clampi(i, 0, 1)]
	Progression.apply_perk(perk.id, game.player, run_mods, game.weapons, _add_bombs)
	game.player.active_run_perks.append({"id": perk.id, "name": perk.name})
	game.player.pending_perk_choice = false
	add_message("PERK: %s" % String(perk.name).to_upper(), Color(0.3, 1, 0.5))
	game.fx.flash(Color(0.3, 1.0, 0.5, 0.25), 0.25)
	game.fx.float_text(game.player.position + Vector2(0, -70), String(perk.name).to_upper(), Color(0.3, 1, 0.5))
	perk_chosen.emit(perk.id)
	perk_choices = []
	game.set_state("playing")


# ---- run configuration ---------------------------------------------------------------------------------

func _build_run_mods() -> void:
	var i := difficulty - 1
	var d := {
		"difficulty": difficulty,
		"enemy_hp": DIFF_ENEMY_HP[i], "enemy_dmg": DIFF_ENEMY_DMG[i], "enemy_spd": DIFF_ENEMY_SPD[i],
		"spawn_mult": DIFF_SPAWN[i], "max_enemies": DIFF_MAX_ENEMIES[i], "ambient": DIFF_AMBIENT[i],
		"day_length": DAY_LENGTH,
		"sanity_drain": DIFF_SANITY[i], "hydration_drain": DIFF_HYDRATION[i], "sprint_cost": 1.0,
		"rate_mod": 1.0, "lamp_capacity": 1.0, "start_ammo": 0, "start_bombs": 0,
		"max_bombs": maxi(2, 6 - difficulty), "max_batteries": maxi(0, 4 - difficulty),
		"aim_assist": aim_assist_enabled,
	}
	run_mods.clear()
	run_mods.merge(d)
	if game:
		game.set_meta("difficulty", difficulty)


func _name() -> String:
	return player_name if player_name != "" else progression.active_name()


# ---- helpers other screens use ------------------------------------------------------------------------

func add_message(text: String, color := Color.WHITE, life := 3.0) -> void:
	messages.append({"text": text, "color": color, "life": life, "age": 0.0})
	if messages.size() > 24:
		messages.pop_front()


func weapon_info() -> Dictionary:
	var w = game.weapons
	if w and w.has_method("get_current"):
		var cur = w.get_current()
		if cur is Dictionary:
			return cur
	return {"name": "machete", "type": "melee", "color": Color(0.8, 0.8, 0.9)}


func ammo() -> int:
	var w = game.weapons
	if w and "ammo" in w:
		return int(w.ammo)
	return 0


func _find_prop(prop: String):
	for n in [game.weapons, game.objects, game.lighting, game]:
		if n != null and prop in n:
			return n
	return null


## Bomb count: exposed as `bomb_count` on game.weapons / game.objects (+ optional add_bombs(n)).
func _bomb_count() -> int:
	var n = _find_prop("bomb_count")
	return int(n.bomb_count) if n else 0


func _add_bombs(count: int) -> void:
	for n in [game.weapons, game.objects, game]:
		if n != null and n.has_method("add_bombs"):
			n.add_bombs(count)
			return
	var holder = _find_prop("bomb_count")
	if holder:
		holder.bomb_count += count


## Headlamp battery as {pct: 0..1, on: bool}. Lighting exposes `battery` and `battery_max`.
func _battery() -> Dictionary:
	var l = game.lighting
	var pct := 1.0
	if l and "battery" in l:
		var mx := 100.0
		if "battery_max" in l:
			mx = float(l.battery_max)
		pct = clampf(float(l.battery) / maxf(mx, 0.01), 0.0, 1.0)
	return {"pct": pct, "on": game.player.headlamp_on}


## Portal as {pos: Vector2 (tiles), active: bool, guards: int} or {} (objects.get_portal() or map.portal).
func _portal() -> Dictionary:
	var src = null
	if game.objects and game.objects.has_method("get_portal"):
		src = game.objects.get_portal()
	elif game.map and "portal" in game.map:
		src = game.map.portal
	if src is Dictionary and not src.is_empty():
		var d := {"pos": src.get("pos", src.get("tile_pos", Vector2.ZERO)), "active": src.get("active", true), "guards": 0}
		if game.objects and game.objects.has_method("portal_guards_left"):
			d.guards = game.objects.portal_guards_left()
		return d
	return {}


func _portal_deactivate() -> void:
	if game.objects and game.objects.has_method("deactivate_portal"):
		game.objects.deactivate_portal()
	elif game.map and "portal" in game.map and game.map.portal is Dictionary:
		game.map.portal["active"] = false
	game.set_meta("portal_active", false)


## Extra minimap markers from the objects system: Array of {pos: Vector2 tiles, color: Color, kind: String}.
func _map_markers() -> Array:
	if game.objects and game.objects.has_method("get_map_markers"):
		return game.objects.get_map_markers()
	return []


## Active chaos-orb effects: Array of {text, remaining, good}.
func _effects() -> Array:
	if game.objects and "active_effects" in game.objects:
		return game.objects.active_effects
	return []


# ---- signal handlers ------------------------------------------------------------------------------------

func _on_level_up(level: int) -> void:
	add_message("%s leveled up! (Lv.%d)" % [_name(), level], Color(1, 0.8, 0.2))
	hud.pop_level()


func _on_enemy_killed(_pos: Vector2, _kind: String, _xp: int) -> void:
	var p = game.player
	if p.streak_display_timer > 0.0:
		add_message("%d KILL STREAK!" % p.current_streak, Color(1, 0.5, 0.1))
		hud.pop_streak()
	hud.pop_kill()


func _on_player_damaged(_amount: float) -> void:
	hud.pop_damage()
