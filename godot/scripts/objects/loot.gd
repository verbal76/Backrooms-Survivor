class_name Loot
extends RefCounted
## Static data + shared textures for world objects. Numbers are copied from items.lua (Items.LOOT),
## orbs.lua, props.lua and the FS table in main.lua (chest / portal constants).

# ---- Items.LOOT -------------------------------------------------------------
const CHUNK_ITEMS_MIN := 8        # chunkItemsMin
const CHUNK_ITEMS_MAX := 14       # chunkItemsMax
const CHUNK_ORBS_MIN := 3         # chunkOrbsMin
const CHUNK_ORBS_MAX := 6         # chunkOrbsMax
const KILL_ORB_CHANCE := 0.40     # killOrbChance
const ITEM_DESPAWN_DIST := 125.0  # Lua: 60. Raised: the Godot map streams chunks up to ~120 tiles out, so 60 culled fresh items at once
const DIFF_DROP_REDUCTION := 0.20 # difficultyDropReduction
const DIFF_MIN_SCALE := 0.20      # difficultyMinScale
const BAD_LUCK_CHUNKS := 4        # badLuckChunkThreshold
# cumulative drop thresholds (typeBandage ... typeBattery); the remainder = extra almond water
const TYPE_THRESHOLDS := [
	[0.12, "bandage"], [0.24, "almond water"], [0.35, "food"], [0.44, "stamina drink"],
	[0.56, "ammo"], [0.65, "weapon"], [0.74, "bomb"], [0.85, "battery"],
]
const PICKUP_RADIUS := 0.7071     # sqrt(0.5): Lua compares squared distance < 0.5
const ORB_PICKUP_RADIUS := 0.6325 # sqrt(0.4)
const ORB_DESPAWN_DIST := 125.0
const PROP_CLEANUP_DIST := 80.0

# ---- main.lua FS constants ----------------------------------------------------
const CHEST_DETECT_RANGE := 10.0
const CHEST_SWARM_COUNT := 12
const PORTAL_DAY := 30
const PORTAL_HORDE_SIZE := 15
const PORTAL_INTERACT_DIST := 2.0

# ---- orbs.lua -----------------------------------------------------------------
const ORB_DETECT_RANGE := 3.0
const ORB_ESCAPE_RANGE := 50.0
const ORB_BUFF_CHANCE := 0.60

# Kill drop chance per enemy kind (enemies.lua Enemies.types dropChance)
const KILL_DROP_CHANCE := {
	"hound": 0.12, "crawler": 0.2, "wretch": 0.08, "shade": 0.15,
	"skin stealer": 0.3, "skinstealer": 0.3, "skin_stealer": 0.3,
}

# item colours (items.lua assignType)
const COLORS := {
	"bandage": Color(0.3, 1.0, 0.3),
	"almond water": Color(0.3, 0.8, 1.0),
	"food": Color(0.8, 0.6, 0.2),
	"stamina drink": Color(0.3, 0.5, 1.0),
	"ammo": Color(0.9, 0.7, 0.1),
	"bomb": Color(1.0, 0.5, 0.1),
	"battery": Color(0.2, 1.0, 0.6),
}

# weapons.lua Weapons.list order, 0-based here (Lua id - 1). Used for item colour/name/type.
const WEAPONS := [
	{"name": "machete", "type": "melee", "color": Color(0.8, 0.8, 0.9)},
	{"name": "knife", "type": "melee", "color": Color(0.7, 0.7, 0.8)},
	{"name": "pipe", "type": "melee", "color": Color(0.5, 0.5, 0.6)},
	{"name": "axe", "type": "melee", "color": Color(0.6, 0.3, 0.2)},
	{"name": "pistol", "type": "ranged", "color": Color(0.8, 0.8, 0.8)},
	{"name": "shotgun", "type": "ranged", "color": Color(0.6, 0.4, 0.2)},
	{"name": "smg", "type": "ranged", "color": Color(0.4, 0.4, 0.5)},
	{"name": "suppressed pistol", "type": "ranged", "color": Color(0.3, 0.3, 0.35)},
]
const FIRST_DROP_WEAPON := 1   # Lua math.random(2, 8) -> 0-based 1..7

# ---- props.lua ----------------------------------------------------------------
const SPAWN_BODIES := [0, 2]
const SPAWN_FURNITURE := [2, 6]
const SPAWN_CLUTTER := [1, 4]
# name, row, col, solid, scale, category, tilesW, tilesH, extra
const PROP_DEFS := [
	["body_facedown", 0, 0, false, 1.0, "body", 1, 1, 1.0],
	["body_slumped", 0, 1, false, 1.0, "body", 1, 1, 1.0],
	["body_fetal", 0, 2, false, 1.0, "body", 1, 1, 1.0],
	["body_crawling", 0, 3, false, 1.0, "body", 1, 1, 1.0],
	["desk_standard", 1, 0, true, 1.2, "furniture", 2, 1, 1.0],
	["desk_monitor", 1, 1, true, 1.2, "furniture", 2, 1, 1.0],
	["desk_papers", 1, 2, true, 1.2, "furniture", 2, 1, 1.0],
	["desk_overturned", 1, 3, true, 1.2, "furniture", 2, 1, 1.0],
	["chair_office", 2, 0, true, 0.9, "furniture", 1, 1, 1.05],
	["chair_knocked", 2, 1, false, 0.9, "furniture", 1, 1, 1.05],
	["chair_simple", 2, 2, true, 0.9, "furniture", 1, 1, 1.05],
	["chair_broken", 2, 3, false, 0.9, "furniture", 1, 1, 1.05],
	["coffee_machine", 3, 0, true, 1.0, "furniture", 1, 1, 1.10],
	["water_cooler", 3, 1, true, 1.0, "furniture", 1, 2, 1.0],
	["coffee_mugs", 3, 2, true, 1.0, "furniture", 1, 1, 1.0],
	["vending_machine", 3, 3, true, 1.3, "furniture", 1, 2, 1.0],
	["papers_scattered", 4, 0, false, 1.0, "clutter", 1, 1, 1.0],
	["papers_folder", 4, 1, false, 0.8, "clutter", 1, 1, 1.0],
	["cardboard_box", 4, 2, true, 1.0, "clutter", 1, 1, 1.05],
	["debris_pile", 4, 3, false, 1.1, "clutter", 1, 1, 1.10],
	["filing_cabinet", 5, 0, true, 1.0, "furniture", 1, 2, 1.0],
	["bookshelf", 5, 1, true, 1.2, "furniture", 1, 2, 1.0],
	["cabinet_open", 5, 2, true, 1.0, "furniture", 1, 2, 1.0],
	["shelf_toppled", 5, 3, true, 1.2, "furniture", 2, 1, 1.0],
]

static var _glow_tex: Texture2D
static var _add_mat: CanvasItemMaterial


## Soft radial white blob (alpha falls off to 0): used for halos and PointLight2D textures.
static func glow_texture() -> Texture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.width = 128
		t.height = 128
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		_glow_tex = t
	return _glow_tex


## Shared additive + unshaded material for halos (visible in the dark, ignores lights).
static func additive_material() -> CanvasItemMaterial:
	if _add_mat == null:
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_add_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return _add_mat


static func make_halo(color: Color, radius_px: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = glow_texture()
	s.material = additive_material()
	s.modulate = color
	s.scale = Vector2.ONE * (radius_px * 2.0 / 128.0)
	s.show_behind_parent = true
	return s


static func make_light(color: Color, tex_scale: float, energy: float) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = glow_texture()
	l.color = color
	l.energy = energy
	l.texture_scale = tex_scale
	l.shadow_enabled = false
	return l
