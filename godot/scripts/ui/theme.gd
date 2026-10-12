class_name UITheme
extends RefCounted
## Shared look for every UI screen: fonts, palette and tiny draw helpers.
## All coordinates are canvas pixels (the project stretches 960x720 with "expand").

const GOLD := Color(0.9, 0.8, 0.2)
const GOLD_BRIGHT := Color(1.0, 0.9, 0.3)
const HINT := Color(0.82, 0.79, 0.58)
const GOLD_DIM := Color(0.5, 0.45, 0.2)
const TEXT := Color(0.8, 0.8, 0.8)
const TEXT_DIM := Color(0.6, 0.6, 0.6)
const TEXT_FAINT := Color(0.42, 0.42, 0.42)
const PANEL := Color(0.04, 0.035, 0.02, 0.92)
const SEL_FILL := Color(0.4, 0.35, 0.15, 0.5)
const RED := Color(1.0, 0.3, 0.25)
const GREEN := Color(0.3, 1.0, 0.3)
const CYAN := Color(0.3, 0.8, 1.0)
const TERM := Color(0.1, 0.8, 0.1)         # green terminal text (story / char select)
const TERM_BRIGHT := Color(0.2, 1.0, 0.2)
const TERM_DIM := Color(0.0, 0.45, 0.0)
const DIFF_COLORS := [Color(0.3, 1, 0.3), Color(1, 0.9, 0.3), Color(1, 0.5, 0.2), Color(1, 0.2, 0.2)]
const DIFF_NAMES := ["Easy", "Normal", "Getting Worse", "Hell"]

## Smallest text drawn anywhere, in canvas px. At 1280x800 (stretch ~1.11) 12 canvas px is ~13 real px, which is
## the floor for the Deck's 7" panel (Steam Deck Verified asks for >= 9 px, we stay clearly above it).
const MIN_FS := 12
## Options > High Contrast: brighter + bolder text (set by ui.gd).
static var high_contrast := false

static var _title: Font
static var _body: Font
static var _boxes := {}


static func title_font() -> Font:
	if _title == null:
		var f := FontFile.new()
		var data := FileAccess.get_file_as_bytes("res://assets/fonts/Blackcraft.ttf")
		if data.size() > 0:
			f.data = data
			f.fallbacks = [ThemeDB.fallback_font]
			f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
			_title = f
		else:
			_title = ThemeDB.fallback_font
	return _title


static func body_font() -> Font:
	if _body == null:
		_body = ThemeDB.fallback_font
	return _body


static func fmt_time(sec: float) -> String:
	return "%d:%02d" % [int(sec / 60.0), int(sec) % 60]


static func color_of(v, fallback := Color.WHITE) -> Color:
	if v is Color:
		return v
	if v is Array and v.size() >= 3:
		return Color(v[0], v[1], v[2], v[3] if v.size() > 3 else 1.0)
	return fallback


## Draw text with its TOP at y. Returns the width used. If width > 0 the text is aligned inside [x, x+width].
static func text(ci: CanvasItem, s: String, x: float, y: float, size: int, col: Color,
		align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, font: Font = null, shadow := true) -> float:
	if font == null:
		font = body_font()
	size = maxi(size, MIN_FS)
	col = legible(col, size)
	var base := y + font.get_ascent(size)
	var segs := Glyphs.segments(s)
	if not segs.is_empty():
		return _text_glyphs(ci, segs, x, y, size, col, align, width, font, shadow)
	if shadow:
		if high_contrast:
			ci.draw_string_outline(font, Vector2(x, base), s, align, width, size, 4, Color(0, 0, 0, minf(1.0, col.a)))
		else:
			ci.draw_string(font, Vector2(x + 1.0, base + 1.0), s, align, width, size, Color(0, 0, 0, col.a * 0.8))
	ci.draw_string(font, Vector2(x, base), s, align, width, size, col)
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Small or faint text gets a little extra brightness so it stays readable on a 7" handheld screen.
static func legible(col: Color, size: int) -> Color:
	if high_contrast:
		return Color(col.r, col.g, col.b, col.a).lerp(Color(1, 1, 1, col.a), 0.35) if col.a > 0.0 else col
	if size <= 15:
		var lum := col.r * 0.3 + col.g * 0.59 + col.b * 0.11
		if lum < 0.65:
			var k := 0.14
			return Color(col.r + (1.0 - col.r) * k, col.g + (1.0 - col.g) * k, col.b + (1.0 - col.b) * k, maxf(col.a, minf(0.85, col.a + 0.15)))
	return col


## Heading text in the Blackcraft face.
static func head(ci: CanvasItem, s: String, x: float, y: float, size: int, col: Color,
		align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> float:
	return text(ci, s, x, y, size, col, align, width, title_font())


static func text_w(s: String, size: int, font: Font = null) -> float:
	if font == null:
		font = body_font()
	size = maxi(size, MIN_FS)
	var segs := Glyphs.segments(s)
	if not segs.is_empty():
		return _segs_w(segs, size, font)
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Largest font size <= size so that the string fits max_w.
static func fit(s: String, size: int, max_w: float, font: Font = null) -> int:
	if font == null:
		font = body_font()
	var w := text_w(s, size, font)
	if w <= max_w or w <= 0.0:
		return size
	return maxi(MIN_FS, int(floor(size * max_w / w)))


static func text_h(size: int, font: Font = null) -> float:
	if font == null:
		font = body_font()
	size = maxi(size, MIN_FS)
	return font.get_height(size)


static func wrapped(ci: CanvasItem, s: String, x: float, y: float, width: float, size: int, col: Color,
		align: int = HORIZONTAL_ALIGNMENT_CENTER, font: Font = null) -> void:
	if font == null:
		font = body_font()
	size = maxi(size, MIN_FS)
	col = legible(col, size)
	if not Glyphs.segments(s).is_empty():
		_wrapped_glyphs(ci, s, x, y, width, size, col, align, font)
		return
	var base := y + font.get_ascent(size)
	if high_contrast:
		ci.draw_multiline_string_outline(font, Vector2(x, base), s, align, width, size, -1, 4, Color(0, 0, 0, col.a))
	else:
		ci.draw_multiline_string(font, Vector2(x + 1, base + 1), s, align, width, size, -1, Color(0, 0, 0, col.a * 0.8))
	ci.draw_multiline_string(font, Vector2(x, base), s, align, width, size, -1, col)


static func box(fill: Color, border: Color, radius := 4, bw := 0) -> StyleBoxFlat:
	var key := [fill, border, radius, bw]
	if _boxes.has(key):
		return _boxes[key]
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	_boxes[key] = sb
	return sb


static func panel(ci: CanvasItem, r: Rect2, fill: Color, border := Color(0, 0, 0, 0), radius := 4, bw := 0) -> void:
	ci.draw_style_box(box(fill, border, radius, bw), r)


## Horizontal fill bar. pct 0..1. ghost (optional) draws a pale "recent damage" trail.
static func bar(ci: CanvasItem, r: Rect2, pct: float, col: Color, ghost := -1.0, back := Color(0.12, 0.12, 0.12, 0.9)) -> void:
	pct = clampf(pct, 0.0, 1.0)
	panel(ci, r, back, Color(0, 0, 0, 0.6), 3, 1)
	if ghost > pct:
		panel(ci, Rect2(r.position, Vector2(maxf(3.0, r.size.x * ghost), r.size.y)), Color(1, 1, 1, 0.35), Color(0, 0, 0, 0), 3)
	if pct > 0.0:
		panel(ci, Rect2(r.position, Vector2(maxf(3.0, r.size.x * pct), r.size.y)), col, Color(0, 0, 0, 0), 3)
		# glossy top highlight
		ci.draw_rect(Rect2(r.position.x + 2, r.position.y + 1, maxf(0.0, r.size.x * pct - 4), maxf(1.0, r.size.y * 0.3)),
			Color(1, 1, 1, 0.14))


static func slider(ci: CanvasItem, r: Rect2, value: float, sel: bool, vmin := 0.0, vmax := 1.0) -> void:
	var t := inverse_lerp(vmin, vmax, value)
	var bar_r := Rect2(r.position.x, r.position.y + r.size.y * 0.5 - 6, r.size.x, 12)
	panel(ci, bar_r, Color(0.15, 0.15, 0.15), Color(0, 0, 0, 0.5), 5, 1)
	var fill := Color(0.9, 0.8, 0.2) if sel else Color(0.5, 0.45, 0.2)
	if t > 0.0:
		panel(ci, Rect2(bar_r.position, Vector2(maxf(4.0, bar_r.size.x * t), bar_r.size.y)), fill, Color(0, 0, 0, 0), 5)
	var kp := Vector2(bar_r.position.x + bar_r.size.x * t, bar_r.position.y + 6)
	ci.draw_circle(kp, 9.0 if sel else 7.0, Color(0, 0, 0, 0.5))
	ci.draw_circle(kp, 7.5 if sel else 6.0, Color(1, 1, 1, 1.0 if sel else 0.65))
	ci.draw_arc(kp, 7.5 if sel else 6.0, 0, TAU, 20, Color(0.3, 0.3, 0.3), 1.0)


static func line_sep(ci: CanvasItem, x1: float, x2: float, y: float, col := Color(0.5, 0.45, 0.2, 0.7)) -> void:
	ci.draw_line(Vector2(x1, y), Vector2(x2, y), col, 1.0)
	ci.draw_rect(Rect2((x1 + x2) * 0.5 - 2, y - 1, 4, 3), col)


static func scanlines(ci: CanvasItem, size: Vector2, col: Color, step := 3.0) -> void:
	var y := 0.0
	while y < size.y:
		ci.draw_rect(Rect2(0, y, size.x, 1), col)
		y += step


static var _vig: GradientTexture2D


## Darkened screen edges. strength 0..1 (alpha at the corners); col tints it.
static func vignette(ci: CanvasItem, size: Vector2, strength: float, col := Color(0, 0, 0)) -> void:
	if _vig == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1)])
		_vig = GradientTexture2D.new()
		_vig.gradient = g
		_vig.fill = GradientTexture2D.FILL_RADIAL
		_vig.fill_from = Vector2(0.5, 0.5)
		_vig.fill_to = Vector2(1.0, 0.5)
		_vig.width = 128
		_vig.height = 128
	ci.draw_texture_rect(_vig, Rect2(Vector2.ZERO, size), false, Color(col.r, col.g, col.b, clampf(strength, 0.0, 1.0)))


# ---- controller glyph rendering (see glyphs.gd): only reached while a controller is the active input ----

static func _seg_w(seg: Dictionary, size: int, font: Font) -> float:
	if seg.has("glyph"):
		return float(Glyphs.glyph_px(size)) + 2.0
	return font.get_string_size(seg.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


static func _segs_w(segs: Array, size: int, font: Font) -> float:
	var w := 0.0
	for seg in segs:
		w += _seg_w(seg, size, font)
	return w


static func _text_glyphs(ci: CanvasItem, segs: Array, x: float, y: float, size: int, col: Color, align: int,
		width: float, font: Font, shadow: bool) -> float:
	var total := _segs_w(segs, size, font)
	var cx := x
	if width > 0.0:
		if align == HORIZONTAL_ALIGNMENT_CENTER:
			cx = x + (width - total) * 0.5
		elif align == HORIZONTAL_ALIGNMENT_RIGHT:
			cx = x + width - total
	var base := y + font.get_ascent(size)
	var gpx := Glyphs.glyph_px(size)
	for seg in segs:
		if seg.has("glyph"):
			var tex: Texture2D = Glyphs.texture(seg.glyph, gpx)
			if tex:
				ci.draw_texture_rect(tex, Rect2(cx + 1.0, y + (font.get_height(size) - gpx) * 0.5, gpx, gpx), false)
			cx += gpx + 2.0
		else:
			var t: String = seg.text
			if shadow:
				if high_contrast:
					ci.draw_string_outline(font, Vector2(cx, base), t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, minf(1.0, col.a)))
				else:
					ci.draw_string(font, Vector2(cx + 1.0, base + 1.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, col.a * 0.8))
			ci.draw_string(font, Vector2(cx, base), t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
			cx += font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	return total


## Word-wrapped paragraph with inline glyphs (left or centre aligned). Mirrors draw_multiline_string line breaking.
static func _wrapped_glyphs(ci: CanvasItem, s: String, x: float, y: float, width: float, size: int, col: Color,
		align: int, font: Font) -> void:
	var lines: Array = []   # each: Array of segments
	for para in s.split("\n"):
		var cur: Array = []
		var cur_w := 0.0
		for seg in Glyphs.segments(para) if not Glyphs.segments(para).is_empty() else [{"text": para}]:
			var items: Array = []
			if seg.has("glyph"):
				items.append(seg)
			else:
				var words: PackedStringArray = seg.text.split(" ", true)
				for i in words.size():
					var wtxt: String = words[i] + (" " if i < words.size() - 1 else "")
					if wtxt != "":
						items.append({"text": wtxt})
			for it in items:
				var iw := _seg_w(it, size, font)
				if cur_w + iw > width and not cur.is_empty():
					lines.append(cur)
					cur = []
					cur_w = 0.0
				cur.append(it)
				cur_w += iw
		lines.append(cur)
	var lh := font.get_height(size)
	for i in lines.size():
		var line: Array = lines[i]
		# trim trailing spaces so centring is exact
		if not line.is_empty() and line[-1].has("text"):
			line[-1] = {"text": String(line[-1].text).rstrip(" ")}
		var lw := _segs_w(line, size, font)
		var lx := x
		if align == HORIZONTAL_ALIGNMENT_CENTER:
			lx = x + (width - lw) * 0.5
		elif align == HORIZONTAL_ALIGNMENT_RIGHT:
			lx = x + width - lw
		_text_glyphs(ci, line, lx, y + i * lh, size, col, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font, true)
