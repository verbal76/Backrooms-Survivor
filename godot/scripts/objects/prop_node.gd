class_name WorldProp
extends Node2D
## Environmental prop (desk, body, clutter). Port of props.lua draw logic: sprite fitted into its tile
## footprint, rotated like the Lua, bodies get a blood trail (SBS CC0 stain textures instead of a line).

const SHEET := "res://assets/objects/props_sheet.png"
const CHAIR := "res://assets/objects/chair_office.png"
const STAINS := [
	"res://assets/third_party/screaming_brain_horror_textures/256x256/Stains/Horror_Stain_01-256x256.png",
	"res://assets/third_party/screaming_brain_horror_textures/256x256/Stains/Horror_Stain_03-256x256.png",
]

static var _sheet: Texture2D
static var _chair: Texture2D
static var _stain_tex: Array = []
static var _loaded := false

var def_name := ""
var solid := false
var tile_pos := Vector2.ZERO
var solid_tile := Vector2i.ZERO
var category := ""


static func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null


func setup(def: Array, p_pos: Vector2, rot: float, tile_px: float, blood := false, blood_angle := 0.0, blood_len := 1.0) -> void:
	def_name = def[0]
	solid = def[3]
	category = def[5]
	tile_pos = p_pos
	position = p_pos * tile_px
	z_index = 0
	if not _loaded:
		_loaded = true
		_sheet = _load_tex(SHEET)
		_chair = _load_tex(CHAIR)
		for p in STAINS:
			_stain_tex.append(_load_tex(p))

	if blood and not _stain_tex.is_empty() and _stain_tex[0] != null:
		var st := Sprite2D.new()
		st.texture = _stain_tex[randi() % _stain_tex.size()]
		var d := Vector2.from_angle(blood_angle)
		st.position = d * blood_len * tile_px * 0.22
		st.rotation = blood_angle + randf_range(-0.4, 0.4)
		st.scale = Vector2.ONE * (blood_len * tile_px * 0.0025 + 0.12)
		st.modulate = Color(0.75, 0.35, 0.3, 0.8)
		st.show_behind_parent = true
		add_child(st)
	# soft contact shadow
	var tw: float = def[6]
	var th: float = def[7]
	var sh := Sprite2D.new()
	sh.texture = Loot.glow_texture()
	sh.modulate = Color(0, 0, 0, 0.5 if solid else 0.28)
	sh.scale = Vector2(tw, 1.0) * tile_px * 0.016 * (1.0 if solid else 0.7)
	sh.position = Vector2(0, tile_px * 0.12)
	sh.show_behind_parent = true
	add_child(sh)

	var tex: Texture2D = null
	var s := 1.0
	if def_name == "chair_office" and _chair != null:
		tex = _chair
		s = minf(tw * tile_px / 640.0, th * tile_px / 640.0) * float(def[4]) * float(def[8])
	elif _sheet != null:
		var at := AtlasTexture.new()
		at.atlas = _sheet
		at.region = Rect2(int(def[2]) * 32, int(def[1]) * 32, 32, 32)
		tex = at
		s = minf(tw * tile_px / 32.0, th * tile_px / 32.0) * float(def[4]) * float(def[8])
	if tex != null:
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.scale = Vector2.ONE * s
		spr.rotation = rot
		add_child(spr)
