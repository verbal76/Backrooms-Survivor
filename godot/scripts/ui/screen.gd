class_name UIScreen
extends Control
## Base class for full-screen UI pages. A page draws itself with _draw(), reads edge presses from
## ui.input in handle_input(), and gets pointer events (mouse + emulated touch) via on_pointer_*.

var ui                          # systems/ui.gd
var game
var age := 0.0                  # seconds since shown
var input_delay := 0.18         # menu input is ignored this long after opening (avoids carry-over presses)
var dt := 0.016
var pointer := Vector2(-1000, -1000)
var _pointer_down := false
var ui_scale := 1.0             # effective UI scale of this page (Options > UI Scale, capped so the page still fits)
var design_min := Vector2(800, 520)   # smallest canvas size (px) the page lays out in without clipping (phone-ready pages set 640 x 340)
var _lay_key := Vector3.ZERO


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


## Fit the page to the canvas at the player's UI scale. The page lays out in a canvas of (vp / scale) px and is
## drawn magnified by `scale`, so every _draw()/handle_input() keeps using `size` untouched.
func apply_layout(user_scale: float, vp: Vector2) -> void:
	var s := clampf(minf(user_scale, minf(vp.x / design_min.x, vp.y / design_min.y)), 0.5, 2.2)
	if absf(s - 1.0) < 0.001:
		s = 1.0
	var key := Vector3(s, vp.x, vp.y)
	if key == _lay_key:
		return
	_lay_key = key
	ui_scale = s
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = vp.x / s
	offset_bottom = vp.y / s
	pivot_offset = Vector2.ZERO
	scale = Vector2(s, s)
	queue_redraw()


func bind(p_ui, p_game) -> void:
	ui = p_ui
	game = p_game
	_on_bound()


func _on_bound() -> void:
	pass


## Called when the page becomes the active one.
func open(_arg = null) -> void:
	age = 0.0
	visible = true
	_on_open(_arg)
	queue_redraw()


func close() -> void:
	visible = false
	_pointer_down = false


func _on_open(_arg) -> void:
	pass


## Called once per frame by ui while this page is active (menu states).
func handle_input(_inp: GameInput, _delta: float) -> void:
	pass


func frame(delta: float) -> void:
	dt = delta
	age += delta
	if visible:
		queue_redraw()


func on_pointer_move(_p: Vector2) -> void:
	pass


func on_pointer_down(_p: Vector2) -> void:
	pass


func on_pointer_up(_p: Vector2) -> void:
	pass


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pointer = event.position
		if _pointer_down:
			on_pointer_move(event.position)
			on_pointer_drag(event.position)
		else:
			on_pointer_move(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pointer = event.position
		if event.pressed:
			_pointer_down = true
			on_pointer_move(event.position)
			on_pointer_down(event.position)
		else:
			_pointer_down = false
			on_pointer_up(event.position)
		accept_event()


func on_pointer_drag(_p: Vector2) -> void:
	pass


# ---- shared drawing helpers -----------------------------------------------------------------------

func fill(col: Color) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), col)


## Static-noise speckle like the Lua title / intro (cheap: ~count rects, reseeded 12x per second).
func noise(count: int, tint: Color, alpha := 1.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_msec() / 80)
	for i in count:
		var c := Color(rng.randf() * tint.r, rng.randf() * tint.g, rng.randf() * tint.b, alpha)
		draw_rect(Rect2(rng.randf() * size.x, rng.randf() * size.y, 2, 2), c)


func button_rect(r: Rect2, label: String, hot: bool, size_px := 18, col := UITheme.GOLD_BRIGHT) -> void:
	UITheme.panel(self, r, Color(0.3, 0.26, 0.1, 0.8) if hot else Color(0.1, 0.09, 0.05, 0.8),
		Color(col.r, col.g, col.b, 0.9 if hot else 0.35), 6, 1)
	UITheme.head(self, label, r.position.x, r.position.y + (r.size.y - UITheme.text_h(size_px, UITheme.title_font())) * 0.5,
		size_px, col if hot else Color(0.75, 0.75, 0.75), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
