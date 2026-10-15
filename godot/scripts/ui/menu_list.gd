class_name MenuList
extends RefCounted
## Vertical menu used by the title, pause and options screens: buttons, sliders, choices, toggles.
## Handles keyboard/gamepad navigation, mouse/touch hover, click and slider dragging, plus the
## animated selection highlight. Items are Dictionaries built with the add_* helpers.

var items: Array = []
var sel := 0
var row_h := 36.0
var half_w := 250.0
var font_size := 22
var slider_w := 170.0
var rects: Array = []
var hl_y := -1.0               # animated highlight centre
var enter_t := 0.0             # seconds since the list was shown (row entrance animation)
var compact := false           # phone short canvas: rows are 14% tighter
var max_rows := 0              # 0 = show every row; otherwise the list scrolls to keep the selection visible
var scroll := 0
var drag_idx := -1
var pop := {}                  # item index -> pressed-flash seconds
var sfx: Callable = Callable()  # called with "move" | "select" | "adjust"
var _cx := 0.0
var _top := 0.0
var _press_y := 0.0            # touch drag-scroll of lists longer than the screen
var _press_x := 0.0
var _press_scroll := 0
var _pending := -1             # row tapped, activated on release unless the finger scrolled the list
var _scrolling := false


# ---- building ---------------------------------------------------------------------------

func clear() -> void:
	items.clear()
	rects.clear()
	sel = 0


func add_button(label: String, activate: Callable, color: Color = Color(-1, 0, 0), id := "") -> Dictionary:
	var it := {"kind": "button", "label": label, "activate": activate, "color": color, "id": id}
	items.append(it)
	return it


func add_slider(label: String, getter: Callable, setter: Callable, vmin := 0.0, vmax := 1.0, step := 0.05) -> Dictionary:
	var it := {"kind": "slider", "label": label, "get": getter, "set": setter, "min": vmin, "max": vmax, "step": step}
	items.append(it)
	return it


## adjust(dir) is called on left/right/click; text() returns the current value string; color() optional.
func add_choice(label: String, text: Callable, adjust: Callable, color: Callable = Callable()) -> Dictionary:
	var it := {"kind": "choice", "label": label, "text": text, "adjust": adjust, "color": color}
	items.append(it)
	return it


func add_toggle(label: String, getter: Callable, toggle: Callable) -> Dictionary:
	var it := {"kind": "toggle", "label": label, "get": getter, "adjust": toggle}
	items.append(it)
	return it


func _rh() -> float:
	return row_h * (0.86 if compact else 1.0)


func _scrolls() -> bool:
	return max_rows > 0 and items.size() > max_rows


func _enabled(it: Dictionary) -> bool:
	return not it.has("enabled") or it.enabled.call()


# ---- input -------------------------------------------------------------------------------

func nav(d: int) -> void:
	if items.is_empty():
		return
	sel = posmod(sel + d, items.size())
	_play("move")


func adjust(dir: int) -> void:
	if items.is_empty():
		return
	var it: Dictionary = items[sel]
	if not _enabled(it):
		return
	match it.kind:
		"slider":
			var v: float = it.get.call()
			it.set.call(clampf(snappedf(v + dir * it.step, 0.001), it.min, it.max))
			_play("adjust")
		"choice", "toggle":
			it.adjust.call(dir)
			_play("adjust")
			pop[sel] = 0.2


func activate() -> void:
	if items.is_empty():
		return
	var it: Dictionary = items[sel]
	if not _enabled(it):
		return
	pop[sel] = 0.2
	match it.kind:
		"button":
			_play("select")
			it.activate.call()
		"choice", "toggle":
			it.adjust.call(1)
			_play("adjust")


func pointer_move(p: Vector2) -> void:
	for i in rects.size():
		if rects[i].has_point(p):
			if sel != i:
				sel = i
				_play("move")
			return


func pointer_down(p: Vector2) -> bool:
	for i in rects.size():
		var r: Rect2 = rects[i]
		if not r.grow(2).has_point(p):
			continue
		sel = i
		var it: Dictionary = items[i]
		if not _enabled(it):
			return true
		_press_y = p.y
		_press_x = p.x
		_press_scroll = scroll
		_scrolling = false
		if _scrolls() and it.kind != "slider":
			_pending = i                      # long list: a drag scrolls it, a tap activates on release
			return true
		match it.kind:
			"slider":
				var sx := _cx - 16.0
				if p.x >= sx - 12.0 and p.x <= sx + slider_w + 12.0:
					drag_idx = i
					_set_from_x(i, p.x)
				else:
					pointer_move(p)
			"button":
				activate()
			_:
				adjust(1 if p.x >= _cx else -1)
		return true
	return false


func pointer_drag(p: Vector2) -> void:
	if drag_idx >= 0:
		_set_from_x(drag_idx, p.x)
		return
	if _scrolls() and (_pending >= 0 or _scrolling):
		var dy := p.y - _press_y
		if absf(dy) > 10.0 or _scrolling:
			_scrolling = true
			_pending = -1
			var vis := shown_rows()
			scroll = clampi(_press_scroll - int(round(dy / _rh())), 0, maxi(0, items.size() - vis))
			sel = clampi(sel, scroll, scroll + vis - 1)


func pointer_up() -> void:
	drag_idx = -1
	if _pending >= 0 and not _scrolling and _pending < items.size():
		var i := _pending
		_pending = -1
		sel = i
		var it: Dictionary = items[i]
		if it.kind == "button":
			activate()
		else:
			adjust(1 if _press_x >= _cx else -1)
	_pending = -1
	_scrolling = false


func _set_from_x(i: int, x: float) -> void:
	var it: Dictionary = items[i]
	var t := clampf((x - (_cx - 16.0)) / slider_w, 0.0, 1.0)
	var v := snappedf(lerpf(it.min, it.max, t), it.step)
	it.set.call(clampf(v, it.min, it.max))


func _play(what: String) -> void:
	if sfx.is_valid():
		sfx.call(what)


# ---- drawing ----------------------------------------------------------------------------------

func shown_rows() -> int:
	return items.size() if max_rows <= 0 else mini(max_rows, items.size())


func total_height() -> float:
	return shown_rows() * _rh()


## How many rows fit into `avail` px (never fewer than 3).
func rows_for(avail: float) -> int:
	return clampi(int(avail / _rh()), 3, maxi(3, items.size()))


func draw(ci: CanvasItem, cx: float, top: float, dt: float, t: float) -> void:
	_cx = cx
	_top = top
	enter_t += dt
	rects.clear()
	for k in pop.keys():
		pop[k] -= dt
		if pop[k] <= 0.0:
			pop.erase(k)
	var vis := shown_rows()
	if sel < scroll:
		scroll = sel
	if sel >= scroll + vis:
		scroll = sel - vis + 1
	scroll = clampi(scroll, 0, maxi(0, items.size() - vis))
	var target := top + (sel - scroll) * _rh() + _rh() * 0.5 - 2
	hl_y = target if hl_y < 0.0 else lerpf(hl_y, target, minf(1.0, dt * 22.0))

	# animated selection bar sits behind the rows
	if not items.is_empty():
		var pulse := 0.5 + 0.5 * sin(t * 4.0)
		var br := Rect2(cx - half_w, hl_y - _rh() * 0.5 + 2, half_w * 2, _rh() - 4)
		UITheme.panel(ci, br, Color(0.4, 0.35, 0.15, 0.42 + pulse * 0.08), Color(1, 0.9, 0.3, 0.35 + pulse * 0.2), 5, 1)
		# chevrons
		var cxl := br.position.x + 10 + sin(t * 6.0) * 2.0
		var cxr := br.end.x - 10 - sin(t * 6.0) * 2.0
		var cy := br.position.y + br.size.y * 0.5
		ci.draw_colored_polygon(PackedVector2Array([Vector2(cxl, cy - 6), Vector2(cxl + 7, cy), Vector2(cxl, cy + 6)]), UITheme.GOLD_BRIGHT)
		ci.draw_colored_polygon(PackedVector2Array([Vector2(cxr, cy - 6), Vector2(cxr - 7, cy), Vector2(cxr, cy + 6)]), UITheme.GOLD_BRIGHT)

	for i in items.size():
		if i < scroll or i >= scroll + vis:
			rects.append(Rect2(-9999, -9999, 1, 1))       # keep rects[] aligned with items[]
			continue
		var it: Dictionary = items[i]
		var delay := (i - scroll) * 0.04
		var a := clampf((enter_t - delay) / 0.22, 0.0, 1.0)
		var slide := (1.0 - a) * 24.0
		var y := top + (i - scroll) * _rh() - 1 + 0.0
		var row := Rect2(cx - half_w, y, half_w * 2, _rh() - 4)
		rects.append(row)
		var is_sel := i == sel
		var enabled := _enabled(it)
		var pf: float = pop.get(i, 0.0)
		var lift := -pf * 10.0 if pf > 0.0 else 0.0
		var base: Color = UITheme.GOLD_BRIGHT if is_sel else Color(0.7, 0.7, 0.7)
		if not enabled:
			base = Color(0.4, 0.4, 0.4)
		base.a = a
		var ty := y + (_rh() - 4 - UITheme.text_h(font_size, UITheme.title_font())) * 0.5 + lift
		var ox := slide + (pf * 3.0)
		match it.kind:
			"button":
				var c: Color = base
				if it.color.r >= 0.0:
					c = it.color if is_sel else it.color.darkened(0.35)
					c.a = a
				if not enabled:
					c = Color(0.4, 0.4, 0.4, a)
				var label := String(it.label)
				if it.has("label_fn"):
					label = it.label_fn.call()
				UITheme.head(ci, label, cx - half_w + ox, ty, font_size, c, HORIZONTAL_ALIGNMENT_CENTER, half_w * 2)
			"slider":
				UITheme.head(ci, it.label, cx - half_w + 12 + ox, ty, font_size, base, HORIZONTAL_ALIGNMENT_RIGHT, half_w - 12 - 36 + 12)
				var v: float = it.get.call()
				var sr := Rect2(cx - 16 + ox, y, slider_w, _rh() - 4)
				UITheme.slider(ci, sr, v, is_sel, it.min, it.max)
				var pct := int(round(inverse_lerp(it.min, it.max, v) * 100.0))
				var vtxt := "%d%%" % pct
				if it.has("fmt"):
					vtxt = it.fmt.call(v)
				UITheme.text(ci, vtxt, cx - 16 + slider_w + 18 + ox, y + (_rh() - 4 - 14) * 0.5 - 1, 14, Color(1, 1, 1, a))
			"choice", "toggle":
				UITheme.head(ci, it.label, cx - half_w + 12 + ox, ty, font_size, base, HORIZONTAL_ALIGNMENT_RIGHT, half_w - 12 - 36 + 12)
				var txt := ""
				var vc: Color = base
				if it.kind == "toggle":
					var on: bool = it.get.call()
					txt = "ON" if on else "OFF"
					vc = Color(0.3, 1, 0.3, a) if on else Color(1, 0.3, 0.3, a)
				else:
					txt = it.text.call()
					if it.color is Callable and it.color.is_valid():
						vc = it.color.call()
						vc.a = a
				if not enabled:
					vc = Color(0.55, 0.55, 0.55, a)
				var shown := txt if it.kind == "toggle" else "<  %s  >" % txt
				UITheme.head(ci, shown, cx - 16 + ox, ty, font_size, vc)
	if scroll > 0:
		UITheme.text(ci, "^  more", cx - half_w, top - 18.0, 12, UITheme.GOLD_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER, half_w * 2)
	if scroll + vis < items.size():
		UITheme.text(ci, "v  more", cx - half_w, top + vis * _rh(), 12, UITheme.GOLD_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER, half_w * 2)
