class_name TipSystem
extends Control
## First-run guided tutorial: context-triggered tip cards. Each tip is shown once per character (remembered in
## the save via Progression.mark_tip_seen), is skippable (dismiss / turn all tips off) and never pauses the game.
## ui.gd calls reset_run() and tick(dt) (playing only). Input.gd calls try_tap(pos) for mouse / touch dismissal.
## Text comes from TutorialData and is filled with the active control scheme's wording.

const CHECK_INTERVAL := 0.25
const GAP := 1.4                       # seconds between two tips
const MIN_SHOW := 3.0                  # a tip stays at least this long before it can be replaced

var ui
var game
var current := ""
var queue: Array = []
var card_rect := Rect2()
var skip_rect := Rect2()

var _t := 0.0                          # seconds since the tip appeared
var _life := 8.0
var _gap := 0.0
var _check := 0.0
var _run_t := 0.0
var _alpha := 0.0
var _flags := {}                       # event flags raised by signals
var _wired := false
var _text := ""
var _title := ""
var _col := Color.WHITE


func bind(p_ui, p_game) -> void:
	ui = p_ui
	game = p_game
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _wire() -> void:
	if _wired:
		return
	_wired = true
	game.player.leveled_up.connect(func(_l): _flags["level_up"] = true)
	if game.objects:
		if game.objects.has_signal("chest_opened"):
			game.objects.chest_opened.connect(func(_p): _flags["chest_open"] = true)
		if game.objects.has_signal("portal_spawned"):
			game.objects.portal_spawned.connect(func(_p): _flags["portal"] = true)


func reset_run() -> void:
	_wire()
	current = ""
	queue.clear()
	_flags.clear()
	_t = 0.0
	_gap = 0.0
	_check = 0.0
	_run_t = 0.0
	_alpha = 0.0
	card_rect = Rect2()


func enabled() -> bool:
	return ui != null and ui.options.tips_enabled


func _seen(id: String) -> bool:
	return ui.progression.tip_seen(id)


func _want(id: String) -> void:
	if _seen(id) or id == current or id in queue:
		return
	queue.append(id)


# ---- per-frame --------------------------------------------------------------------------

## Physics-rate tick while the game is playing.
func tick(dt: float) -> void:
	if not enabled():
		if current != "":
			current = ""
		queue.clear()
		return
	if ui.intro_t > 0.0:
		return
	_run_t += dt
	_gap = maxf(0.0, _gap - dt)
	if current != "":
		_t += dt
		var inp: GameInput = game.input
		if _t > 0.4 and (inp.just("interact") or inp.just("pad_start")):
			dismiss()
		elif inp.just("tip_skip_all"):
			disable_all()
		elif _t > _life:
			dismiss()
	_check -= dt
	if _check <= 0.0:
		_check = CHECK_INTERVAL
		_scan()
	if (current == "" or _t > MIN_SHOW) and _gap <= 0.0 and not queue.is_empty():
		var nxt := _next_in_queue()
		if current == "" or _priority(nxt) < _priority(current):
			_show(nxt)


func _priority(id: String) -> int:
	var i := TutorialData.TIP_PRIORITY.find(id)
	return i if i >= 0 else 99


func _next_in_queue() -> String:
	var best: String = queue[0]
	for id in queue:
		if _priority(id) < _priority(best):
			best = id
	return best


func _show(id: String) -> void:
	queue.erase(id)
	current = id
	_t = 0.0
	var d: Dictionary = TutorialData.TIPS[id]
	_title = d.title
	_col = d.color
	_text = game.input.fill(d.text)
	_life = clampf(4.0 + _text.length() * 0.055, 7.0, 15.0)
	ui.progression.mark_tip_seen(id)
	if id == "chest_open":
		ui.progression.mark_tip_seen("chest")


func dismiss() -> void:
	if current == "":
		return
	current = ""
	_gap = GAP


func disable_all() -> void:
	ui.options.tips_enabled = false
	ui.options.save()
	current = ""
	queue.clear()
	ui.add_message("Tips turned off (Options > Tips to turn them back on)", Color(0.8, 0.8, 0.6), 4.0)


## Mouse / touch: tap on the card dismisses it, tap on "TIPS OFF" disables all tips. Returns true if consumed.
func try_tap(pos: Vector2) -> bool:
	if current == "" or _alpha < 0.5 or not card_rect.has_point(pos):
		return false
	if skip_rect.has_point(pos):
		disable_all()
	else:
		dismiss()
	return true


# ---- triggers ---------------------------------------------------------------------------

func _scan() -> void:
	var p = game.player
	if _run_t > 0.8:
		_want("welcome")
	if _run_t > 16.0:
		_want("stats")
	if _flags.has("level_up"):
		_flags.erase("level_up")
		_want("level_up")
	if _flags.has("chest_open"):
		_flags.erase("chest_open")
		_want("chest_open")
	if _flags.has("portal"):
		_flags.erase("portal")
		_want("portal")
	var ppos: Vector2 = p.tile_pos
	# enemies
	if game.enemies and game.enemies.has_method("get_enemies"):
		var near := 0
		for e in game.enemies.get_enemies():
			var d: float = e.tile_pos.distance_to(ppos)
			if d < 14.0:
				_want("enemy")
			if d < 6.0:
				near += 1
			if e.get("state") == "flee" and d < 14.0:
				_want("light_enemy")
		if near >= 4 and ui._bomb_count() > 0:
			_want("bomb")
	# pickups
	if game.objects:
		if "items" in game.objects:
			for it in game.objects.items:
				if is_instance_valid(it) and not it.collected and it.tile_pos.distance_to(ppos) < 7.0:
					_want("item")
					break
		if "orbs" in game.objects:
			for o in game.objects.orbs:
				if is_instance_valid(o) and not o.collected and o.tile_pos.distance_to(ppos) < 9.0:
					_want("orb")
					break
	# survival stats
	var sp: float = p.sanity / maxf(p.max_sanity, 1.0)
	if sp < 0.6:
		_want("sanity")
	if sp < 0.25:
		_want("sanity_low")
	var hp_: float = p.hydration / maxf(p.max_hydration, 1.0)
	if hp_ < 0.3:
		_want("hydration")
	if p.hydration <= 0.0:
		_want("hydration_zero")
	if p.hp / maxf(p.max_hp, 1.0) < 0.4:
		_want("hp_low")
	if p.stamina < 15.0 and _run_t > 20.0:
		_want("stamina_low")
	var bat: Dictionary = ui._battery()
	if bat.on and bat.pct < 0.25 and bat.pct > 0.0:
		_want("battery_low")
	if bat.pct <= 0.0:
		_want("battery_dead")
	# weapons
	var w = game.weapons
	if w and "unlocked" in w:
		var n := 0
		for u in w.unlocked:
			if u:
				n += 1
		if n >= 2:
			_want("weapons")
	if ui.weapon_info().get("type", "melee") == "ranged":
		_want("ranged")
	if p.current_streak >= 5:
		_want("streak")
	if game.day >= 2:
		_want("day")
	if game.traps and game.traps.has_method("trap_near") and (game.traps.trap_near(ppos, 9.0) or game.traps.player_hits > 0):
		_want("trap")
	# world
	for room in game.map.chest_rooms:
		if not room.looted and Vector2(room.pos).distance_to(ppos) < 26.0:
			_want("chest")
			break
	if game.objects and "portal" in game.objects and not game.objects.portal.is_empty():
		_want("portal")


# ---- drawing ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if ui == null or game == null:
		return
	var show: bool = current != "" and game.state == "playing" and enabled()
	_alpha = move_toward(_alpha, 1.0 if show else 0.0, delta * 5.0)
	visible = _alpha > 0.01
	if visible:
		queue_redraw()


func _draw() -> void:
	if _alpha <= 0.01:
		return
	var w := size.x
	var h := size.y
	var id := current
	if id == "":
		return
	var mode: String = game.input.active_mode()
	var ins := Vector4.ZERO
	if mode == "touch":
		ins = game.input.safe_insets()
	var cw := minf(640.0, w - 40.0 - ins.x - ins.z)
	var pad := 14.0
	var fs := 16
	var tw := cw - pad * 2.0
	var body := UITheme.body_font()
	var th := body.get_multiline_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, tw, fs).y
	var ch := 40.0 + th + 38.0
	var bottom := h - 18.0 - ins.w
	var x := (w - cw) * 0.5
	var y := bottom - ch + (1.0 - _alpha) * 16.0
	card_rect = Rect2(x, y, cw, ch)
	var a := _alpha
	UITheme.panel(self, card_rect.grow(3), Color(0, 0, 0, 0.35 * a), Color(0, 0, 0, 0), 10)
	UITheme.panel(self, card_rect, Color(0.03, 0.026, 0.014, 0.94 * a), Color(_col.r, _col.g, _col.b, 0.8 * a), 8, 2)
	draw_rect(Rect2(x + 2, y + 2, 5, ch - 4), Color(_col.r, _col.g, _col.b, 0.9 * a))
	UITheme.head(self, _title, x + pad + 6, y + 8, 22, Color(_col.r, _col.g, _col.b, a))
	UITheme.text(self, "TIP", x, y + 12, 12, Color(0.6, 0.6, 0.6, 0.8 * a), HORIZONTAL_ALIGNMENT_RIGHT, cw - pad)
	UITheme.wrapped(self, _text, x + pad + 6, y + 38, tw - 6, fs, Color(0.88, 0.88, 0.88, a), HORIZONTAL_ALIGNMENT_LEFT)
	# footer
	var fy := y + ch - 26.0
	var hint := "ENTER: got it    BACKSPACE: tips off"
	if mode == "gamepad":
		hint = "START: got it"
	elif mode == "touch":
		hint = "TAP: got it"
	UITheme.text(self, hint, x + pad + 6, fy, 12, Color(0.55, 0.55, 0.5, a))
	if mode != "keyboard":
		skip_rect = Rect2(x + cw - 120.0, fy - 6.0, 112.0, 26.0)
		UITheme.panel(self, skip_rect, Color(0.12, 0.1, 0.05, 0.9 * a), Color(0.7, 0.3, 0.2, 0.6 * a), 5, 1)
		UITheme.text(self, "TIPS OFF", skip_rect.position.x, skip_rect.position.y + 5, 12, Color(1, 0.6, 0.5, a), HORIZONTAL_ALIGNMENT_CENTER, skip_rect.size.x)
	else:
		skip_rect = Rect2(x + cw - 120.0, fy - 6.0, 112.0, 26.0)
		UITheme.text(self, "[click] dismiss", skip_rect.position.x, skip_rect.position.y + 5, 12, Color(0.45, 0.45, 0.4, a), HORIZONTAL_ALIGNMENT_RIGHT, skip_rect.size.x)
		skip_rect = Rect2()
	# time bar
	var frac := clampf(1.0 - _t / _life, 0.0, 1.0)
	draw_rect(Rect2(x + 8, y + ch - 4, (cw - 16) * frac, 2), Color(_col.r, _col.g, _col.b, 0.5 * a))
