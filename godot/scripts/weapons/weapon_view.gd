extends Node2D
## Draws the weapon in the player's hands (rotated to aim, melee swings through an arc), the melee
## swoosh trail and the muzzle flash. Port of drawWeaponInHand + the swing/flash blocks in main.lua.
## Sits at the player's position inside game.world, above the player sprite.

const TILE := 52.0
const Z := 52.0 / 24.0 * 2.0         # charScale * playerScale
const TARGET_LEN := 18.0 * Z         # sprite drawn ~18*z px long
const SWING_ARC := PI * 0.65
# Lua barrelTip table (indexed by 1-based weapon idx 5..8), converted to 0-based names
const BARREL_TIP := {"pistol": 9.2, "shotgun": 12.2, "smg": 9.2, "suppressed pistol": 12.2}

var wp                                # weapons system
var textures := {}                    # weapon name -> Texture2D
var recoil := 0.0                     # 1 -> 0 kick after a shot
var pop := 0.0                        # 1 -> 0 scale pulse after switching weapon
var flash_t := 0.0                    # muzzle flash timer
var flash_size := 6.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 2
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_rng.randomize()


func muzzle_offset_px(wep: Dictionary) -> float:
	var tip: float = BARREL_TIP.get(wep.name, 8.0)
	return (10.0 + tip + 3.0) * Z   # grip (13z - 3z) + barrel + 3, as in the Lua flash


func _draw() -> void:
	if wp == null or wp.game == null or wp.game.player == null:
		return
	var player = wp.game.player
	var wep: Dictionary = wp.get_current()
	var a: float = player.angle
	var melee: bool = wep.type == "melee"
	var wep_angle := a
	var swing_prog := 0.0
	if wp.swinging and melee:
		swing_prog = clampf(wp.swing_timer / (wep.rate * 0.6), 0.0, 1.0)
		var t := 1.0 - swing_prog
		t = 1.0 - (1.0 - t) * (1.0 - t)              # ease-out for a snappier slash
		wep_angle = a - SWING_ARC / 2.0 + t * SWING_ARC
	var wf := Vector2.from_angle(wep_angle)
	var side := Vector2(-sin(a), cos(a))
	var side_off: float = 3.0 if melee else 0.0
	var hand := wf * 13.0 * Z + side * side_off * Z
	hand -= Vector2.from_angle(a) * recoil * 5.0           # recoil kick
	var grip := hand - wf * 3.0 * Z

	# sprite
	var tex: Texture2D = textures.get(wep.name)
	var draw_angle := wep_angle + (recoil * -0.05 if not melee else 0.0)
	if tex:
		var sc := TARGET_LEN / float(tex.get_width()) * (1.0 + pop * 0.25)
		var flip := -1.0 if cos(wep_angle) < 0.0 else 1.0   # never draw the gun upside down
		draw_set_transform(grip, draw_angle, Vector2(sc, sc * flip))
		draw_texture(tex, Vector2(-tex.get_width() * 0.25, -tex.get_height() * 0.5))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_line(grip, grip + wf * TARGET_LEN * 0.75, wep.color, 3.0 * Z)

	# melee swoosh: layered fading arcs following the blade
	if wp.swinging and melee:
		var reach_px: float = wp.get_melee_reach() * TILE
		var fade := 1.0 - (1.0 - swing_prog)
		fade = swing_prog        # strongest at the start of the swing, fading out
		var trail := PI * 0.5
		for k in range(6):
			var r := reach_px * (0.45 + 0.1 * k)
			var alpha := 0.32 * fade * (0.4 + 0.12 * k)
			draw_arc(Vector2.ZERO + side * side_off * Z, r, wep_angle - trail, wep_angle, 20,
				Color(0.9, 0.95, 1.0, alpha), (2.0 + k * 0.6) * Z * 0.5)

	# muzzle flash (starburst + glow) at the barrel tip
	if flash_t > 0.0 and wep.type == "ranged":
		var fm := grip + wf * (wep_tip(wep) - 10.0 * Z)
		var big: float = flash_size * Z
		for i in range(6):
			var ra := wep_angle + i * PI / 3.0 + _rng.randf() * 0.3
			var rl := big * (0.6 + _rng.randf() * 0.4)
			draw_line(fm, fm + Vector2.from_angle(ra) * rl, Color(1, 0.7, 0.2, 0.7), 1.5 * Z)
		draw_circle(fm, 3.0 * Z, Color(1, 0.95, 0.7, 0.9))
		draw_circle(fm, 1.5 * Z, Color(1, 1, 1, 0.6))
		# long forward cone
		var f2 := wf * big * 1.3
		draw_colored_polygon(PackedVector2Array([fm + Vector2(-wf.y, wf.x) * 2.5 * Z, fm + f2, fm - Vector2(-wf.y, wf.x) * 2.5 * Z]),
			Color(1, 0.8, 0.35, 0.45))


func wep_tip(wep: Dictionary) -> float:
	return muzzle_offset_px(wep)
