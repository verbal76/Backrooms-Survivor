extends UIScreen
## Intro story scroll (drawStoryScreen). Any key / button / click skips to the save-slot select.

const HOLD_SECONDS := 5.0
const SPEED := 55.0
const LINE_H := 36.0
const LINES := [
	"", "",
	"ASYNC RESEARCH LABORATORIES", "PROJECT: THRESHOLD", "CLASSIFICATION: LEVEL 5 - RESTRICTED", "",
	"Date: [REDACTED]", "Subject: Incident Report #4031-B", "",
	"You are a data collection specialist assigned to",
	"Async Research Lab's experimental spatial anomaly",
	"division. Your team has been studying unstable",
	"regions where physical reality appears to break",
	"down, areas the research team calls 'no-clip zones.'", "",
	"The Backrooms are a vast network of liminal spaces",
	"that exist behind the thin membrane of reality.",
	"Approximately 600 million square miles of empty,",
	"yellowed rooms, damp carpet, and buzzing",
	"fluorescent lights stretching on forever.", "",
	"The spaces feel familiar. Hallways you have walked",
	"before. Offices where someone should be sitting.",
	"But no one is here. No one has been here for a",
	"very long time. The absence of people is so total",
	"it feels like a presence of its own.", "",
	"There is a smell. Wet carpet. Old insulation.",
	"Something rotting just beyond the next corner.",
	"The hum of the lights is constant, maddening.",
	"Researchers believe the monotonous yellow hue",
	"of the walls accelerates psychological decay.", "",
	"Your team was testing a generated no-clip doorway",
	"in Lab 7-C, a controlled portal designed to allow",
	"brief excursions into the Backrooms for data",
	"collection. You stepped through as you had done",
	"twelve times before.", "",
	"But this time the door malfunctioned.", "",
	"The portal collapsed behind you. The steady green",
	"light of the lab flickered, turned red, and",
	"vanished. You heard your team shouting on the",
	"other side, their voices growing distant, then",
	"gone entirely.", "",
	"You are alone.", "",
	"The Backrooms are not empty. Things live here.",
	"Entities that have never seen daylight. Things",
	"that hunt by sound. Things that fear light.",
	"Things with no face and too many arms.", "",
	"Your headlamp battery will not last forever.",
	"Your sanity will erode in the darkness.",
	"Dehydration will set in. Hunger. Exhaustion.", "",
	"But there is hope.", "",
	"Async's emergency protocols include exit portals",
	"hidden deep within the Backrooms. Find one.",
	"Survive long enough to reach it.", "",
	"No one is coming for you.",
	"There is no saving. There is no loading.",
	"Only survival.", "", "",
	"[ Press A or ENTER to continue ]", "", "",
]

var _scroll := 0.0
var _boost := 0.0


func _on_open(_arg) -> void:
	_scroll = 0.0
	_boost = 0.0


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var skip := false
	if event is InputEventKey and event.pressed and not event.echo:
		skip = true
	elif event is InputEventJoypadButton and event.pressed:
		skip = true
	elif event is InputEventMouseButton and event.pressed:
		skip = true
	elif event is InputEventScreenTouch and event.pressed:
		skip = true
	if skip and age > 0.15:
		ui.show_screen("charselect")


func frame(delta: float) -> void:
	super.frame(delta)
	if age > HOLD_SECONDS:
		_scroll += SPEED * delta
	if _scroll > LINES.size() * LINE_H + size.y * 0.3:
		ui.show_screen("charselect")


func _draw() -> void:
	var w := size.x
	var h := size.y
	fill(Color(0, 0, 0))
	var top_safe := 70.0
	var base_y := top_safe - 2.0 * LINE_H - _scroll
	var t: float = ui.clock
	var green := Color(0.1, 0.8, 0.1)
	for i in LINES.size():
		var line: String = LINES[i]
		var y := base_y + i * LINE_H
		if line == "" or y < -LINE_H or y > h + LINE_H:
			continue
		if "[" in line and i > LINES.size() - 6:
			if sin(t * 3.0) > 0.0:
				UITheme.head(self, line, 0, y, 28, Color(0.1, 0.95, 0.1), HORIZONTAL_ALIGNMENT_CENTER, w)
			continue
		var sz := UITheme.fit(line, 28, w - 80.0, UITheme.title_font())
		# phosphor glow
		UITheme.text(self, line, 40 - 1, y, sz, Color(0.1, 0.9, 0.1, 0.12), HORIZONTAL_ALIGNMENT_CENTER, w - 80, UITheme.title_font(), false)
		UITheme.text(self, line, 40 + 1, y, sz, Color(0.1, 0.9, 0.1, 0.12), HORIZONTAL_ALIGNMENT_CENTER, w - 80, UITheme.title_font(), false)
		UITheme.text(self, line, 40, y, sz, green, HORIZONTAL_ALIGNMENT_CENTER, w - 80, UITheme.title_font(), false)
	# fades top/bottom
	for i in 8:
		var a := 1.0 - float(i) / 8.0
		draw_rect(Rect2(0, 40 + i * 3, w, 3), Color(0, 0, 0, a))
		draw_rect(Rect2(0, h - 30 - i * 3 - 3, w, 3), Color(0, 0, 0, a))
	draw_rect(Rect2(0, 0, w, 40), Color(0, 0, 0))
	draw_rect(Rect2(0, h - 30, w, 30), Color(0, 0, 0))
	UITheme.head(self, "ASYNC RESEARCH LABS // INCIDENT REPORT", 0, 8, 22, Color(0.1, 0.5, 0.1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, w)
	UITheme.text(self, "ANY KEY TO SKIP", 0, h - 22, 12, Color(0.1, 0.4, 0.1, 0.5 + 0.3 * sin(t * 3.0)), HORIZONTAL_ALIGNMENT_CENTER, w)
	UITheme.scanlines(self, size, Color(0, 0.05, 0, 0.35), 3.0)
	# rolling CRT bar + flicker
	var roll := fposmod(t * 70.0, h + 120.0) - 60.0
	draw_rect(Rect2(0, roll, w, 40), Color(0.1, 0.8, 0.1, 0.03))
	UITheme.vignette(self, size, 0.7)
	var fade_in := 1.0 - clampf(age / 0.6, 0.0, 1.0)
	if fade_in > 0.0:
		fill(Color(0, 0, 0, fade_in))
