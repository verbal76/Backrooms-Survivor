"""
BACKROOMS SURVIVOR - 3D Model to Top-Down Spritesheet Renderer
================================================================
This Blender Python script imports a 3D model (.fbx, .obj, .glb, .gltf, .blend)
and renders it from above at multiple rotation angles to create a spritesheet
compatible with LÖVE2D.

WHAT IT DOES:
  1. Imports the 3D model
  2. Centers and scales it to fill the frame
  3. Sets up a top-down orthographic camera looking straight down
  4. Renders the model at 16 rotation angles (every 22.5 degrees)
  5. Composites all frames into a single horizontal spritesheet PNG
  6. Outputs: named PNG file (16 frames side by side, or 1 frame for props)

FRAME LAYOUT:
  Frame 0 = facing right (angle 0)
  Frame 1 = facing 22.5 degrees
  ...
  Frame 15 = facing 337.5 degrees

  The game uses player.angle (radians) to pick the right frame.

USAGE:
  Called by RENDER_SPRITESHEET.bat - you don't need to run this directly.
  But if you want to: blender --background --python render_spritesheet.py -- model.fbx

TUNING (edit these values):
"""

import bpy
import bmesh
import math
import os
import sys
from mathutils import Vector

# ════════════════════════════════════════════════════════
#  SETTINGS - change these to adjust output
# ════════════════════════════════════════════════════════

FRAME_SIZE = 128          # pixel size of each frame (128x128)
NUM_ANGLES = 16           # number of rotation angles (16 = every 22.5°, 8 = every 45°)
RENDER_SCALE = 100        # render quality percentage (100 = full, 50 = half for speed)
TRANSPARENT_BG = True     # transparent background (True) or black (False)
CAMERA_DISTANCE = 5       # how far above the model the camera sits
MODEL_SCALE_MULT = 0.85   # how much of the frame the model fills (0.85 = 85%)
LIGHT_INTENSITY = 3.0     # overhead light brightness
AMBIENT_LIGHT = 0.3       # ambient/fill light level (0-1)
OUTPUT_DIR = ""            # set by command line, defaults to same folder as model
OUTPUT_NAME = ""           # set by command line, defaults to player_spritesheet.png

# ════════════════════════════════════════════════════════
#  GET MODEL PATH FROM COMMAND LINE
# ════════════════════════════════════════════════════════

argv = sys.argv
model_path = None

# Everything after "--" is our custom args
if "--" in argv:
    custom_args = argv[argv.index("--") + 1:]
    if len(custom_args) >= 1:
        model_path = os.path.abspath(custom_args[0])
    if len(custom_args) >= 2:
        try:
            FRAME_SIZE = int(custom_args[1])
        except ValueError:
            pass
    if len(custom_args) >= 3:
        try:
            NUM_ANGLES = int(custom_args[2])
        except ValueError:
            pass
    if len(custom_args) >= 4:
        OUTPUT_DIR = os.path.abspath(custom_args[3])
    if len(custom_args) >= 5:
        OUTPUT_NAME = custom_args[4]

if not model_path:
    print("\n[ERROR] No model file specified!")
    print("Usage: blender --background --python render_spritesheet.py -- <model_file> [frame_size] [num_angles]")
    print("Example: blender --background --python render_spritesheet.py -- character.fbx 128 16")
    sys.exit(1)

if not os.path.exists(model_path):
    print(f"\n[ERROR] File not found: {model_path}")
    sys.exit(1)

if not OUTPUT_DIR:
    OUTPUT_DIR = os.path.dirname(model_path)

# Create output directory if needed
os.makedirs(OUTPUT_DIR, exist_ok=True)

model_name = os.path.splitext(os.path.basename(model_path))[0]

print(f"\n{'='*60}")
print(f"  Rendering spritesheet from: {os.path.basename(model_path)}")
print(f"  Frame size: {FRAME_SIZE}x{FRAME_SIZE}")
print(f"  Angles: {NUM_ANGLES}")
print(f"  Output: {OUTPUT_DIR}")
print(f"{'='*60}\n")

# ════════════════════════════════════════════════════════
#  STEP 1: CLEAN THE SCENE
# ════════════════════════════════════════════════════════

print("[1/7] Cleaning scene...")
bpy.ops.wm.read_homefile(use_empty=True)

# Remove all default objects
for obj in bpy.data.objects:
    bpy.data.objects.remove(obj, do_unlink=True)

# ════════════════════════════════════════════════════════
#  STEP 2: IMPORT THE 3D MODEL
# ════════════════════════════════════════════════════════

print(f"[2/7] Importing model...")
ext = os.path.splitext(model_path)[1].lower()

try:
    if ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=model_path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=model_path)
    elif ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=model_path)
    elif ext == ".dae":
        bpy.ops.wm.collada_import(filepath=model_path)
    elif ext == ".stl":
        bpy.ops.wm.stl_import(filepath=model_path)
    elif ext == ".blend":
        # Link all objects from the blend file
        with bpy.data.libraries.load(model_path, link=False) as (data_from, data_to):
            data_to.objects = data_from.objects
        for obj in data_to.objects:
            if obj is not None:
                bpy.context.collection.objects.link(obj)
    else:
        print(f"[ERROR] Unsupported format: {ext}")
        print("Supported: .fbx, .obj, .glb, .gltf, .dae, .stl, .blend")
        sys.exit(1)
except Exception as e:
    print(f"[ERROR] Failed to import: {e}")
    sys.exit(1)

# Collect all mesh objects
mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
all_objects = [obj for obj in bpy.context.scene.objects if obj.type in ('MESH', 'ARMATURE', 'EMPTY')]

if not mesh_objects:
    print("[ERROR] No mesh objects found in the file!")
    sys.exit(1)

print(f"      Found {len(mesh_objects)} mesh object(s)")

# ════════════════════════════════════════════════════════
#  STEP 3: CENTER AND SCALE THE MODEL
# ════════════════════════════════════════════════════════

print("[3/7] Centering and scaling model...")

# Calculate combined bounding box of all mesh objects
min_co = Vector((float('inf'), float('inf'), float('inf')))
max_co = Vector((float('-inf'), float('-inf'), float('-inf')))

for obj in mesh_objects:
    # Get world-space bounding box corners
    for corner in obj.bound_box:
        world_corner = obj.matrix_world @ Vector(corner)
        min_co.x = min(min_co.x, world_corner.x)
        min_co.y = min(min_co.y, world_corner.y)
        min_co.z = min(min_co.z, world_corner.z)
        max_co.x = max(max_co.x, world_corner.x)
        max_co.y = max(max_co.y, world_corner.y)
        max_co.z = max(max_co.z, world_corner.z)

center = (min_co + max_co) / 2
dimensions = max_co - min_co
max_dim = max(dimensions.x, dimensions.y, dimensions.z)

if max_dim == 0:
    print("[ERROR] Model has zero size!")
    sys.exit(1)

# Create a parent empty to move/scale everything together
parent = bpy.data.objects.new("ModelParent", None)
bpy.context.collection.objects.link(parent)

for obj in all_objects:
    if obj.parent is None:
        obj.parent = parent

# Center the model at origin
parent.location = -center

# Scale to fit camera view (we want it to fill ~85% of the frame)
target_size = 2.0 * MODEL_SCALE_MULT  # orthographic camera sees ~2 units
scale_factor = target_size / max_dim
parent.scale = (scale_factor, scale_factor, scale_factor)

# Apply transforms
bpy.context.view_layer.update()

print(f"      Model dimensions: {dimensions.x:.2f} x {dimensions.y:.2f} x {dimensions.z:.2f}")
print(f"      Scale factor: {scale_factor:.4f}")

# ════════════════════════════════════════════════════════
#  STEP 4: SET UP CAMERA (top-down orthographic)
# ════════════════════════════════════════════════════════

print("[4/7] Setting up top-down camera...")

cam_data = bpy.data.cameras.new("TopDownCam")
cam_data.type = 'ORTHO'
cam_data.ortho_scale = 2.2  # slightly larger than model to add padding
cam_data.clip_start = 0.1
cam_data.clip_end = 100

cam_obj = bpy.data.objects.new("TopDownCam", cam_data)
bpy.context.collection.objects.link(cam_obj)
bpy.context.scene.camera = cam_obj

# Position camera directly above, looking straight down
cam_obj.location = (0, 0, CAMERA_DISTANCE)
cam_obj.rotation_euler = (0, 0, 0)  # looking down -Z

# ════════════════════════════════════════════════════════
#  STEP 5: SET UP LIGHTING
# ════════════════════════════════════════════════════════

print("[5/7] Setting up lighting...")

# Main top-down light (simulates overhead fluorescent, like the Backrooms)
light_data = bpy.data.lights.new("OverheadLight", type='SUN')
light_data.energy = LIGHT_INTENSITY
light_data.color = (1.0, 0.95, 0.85)  # slightly warm, like old fluorescents
light_obj = bpy.data.objects.new("OverheadLight", light_data)
bpy.context.collection.objects.link(light_obj)
light_obj.location = (0, 0, 10)
light_obj.rotation_euler = (0, 0, 0)  # pointing straight down

# Fill light from slightly to the side (softens shadows)
fill_data = bpy.data.lights.new("FillLight", type='SUN')
fill_data.energy = LIGHT_INTENSITY * 0.4
fill_data.color = (0.9, 0.9, 1.0)  # slightly cool fill
fill_obj = bpy.data.objects.new("FillLight", fill_data)
bpy.context.collection.objects.link(fill_obj)
fill_obj.location = (3, 3, 8)
fill_obj.rotation_euler = (math.radians(20), math.radians(20), 0)

# World ambient
world = bpy.data.worlds.new("BackroomsWorld")
bpy.context.scene.world = world
try:
    world.use_nodes = True
except:
    pass  # deprecated in Blender 5.0, nodes enabled by default
bg_node = world.node_tree.nodes.get("Background")
if bg_node:
    bg_node.inputs[0].default_value = (AMBIENT_LIGHT, AMBIENT_LIGHT * 0.95, AMBIENT_LIGHT * 0.85, 1.0)
    bg_node.inputs[1].default_value = 1.0

# ════════════════════════════════════════════════════════
#  STEP 6: CONFIGURE RENDER SETTINGS
# ════════════════════════════════════════════════════════

print("[6/7] Configuring render...")

scene = bpy.context.scene

# Set render engine (name changed across Blender versions)
engine_set = False
for engine_name in ['BLENDER_EEVEE', 'BLENDER_EEVEE_NEXT', 'BLENDER_WORKBENCH']:
    try:
        scene.render.engine = engine_name
        engine_set = True
        print(f"      Render engine: {engine_name}")
        break
    except:
        continue

if not engine_set:
    print("[ERROR] Could not set any render engine!")
    sys.exit(1)

scene.render.resolution_x = FRAME_SIZE
scene.render.resolution_y = FRAME_SIZE
scene.render.resolution_percentage = RENDER_SCALE
scene.render.film_transparent = TRANSPARENT_BG
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA' if TRANSPARENT_BG else 'RGB'

# EEVEE settings (property names vary by Blender version, skip if missing)
try:
    if hasattr(scene, 'eevee'):
        if hasattr(scene.eevee, 'taa_render_samples'):
            scene.eevee.taa_render_samples = 32
        if hasattr(scene.eevee, 'use_gtao'):
            scene.eevee.use_gtao = True
except Exception as e:
    print(f"      [WARN] Could not set EEVEE quality options: {e}")

# ════════════════════════════════════════════════════════
#  STEP 7: RENDER ALL ROTATION ANGLES
# ════════════════════════════════════════════════════════

print(f"[7/7] Rendering {NUM_ANGLES} angles...")

# Create temp directory for individual frames
temp_dir = os.path.join(OUTPUT_DIR, "_spritesheet_temp")
os.makedirs(temp_dir, exist_ok=True)

angle_step = 360.0 / NUM_ANGLES

for i in range(NUM_ANGLES):
    angle_deg = i * angle_step
    angle_rad = math.radians(angle_deg)

    # Rotate the model parent around Z axis
    # Frame 0 = facing right (game angle 0), so model's "front" points +X at frame 0
    parent.rotation_euler = (0, 0, -angle_rad)
    bpy.context.view_layer.update()

    # Render this frame
    frame_path = os.path.join(temp_dir, f"frame_{i:03d}.png")
    scene.render.filepath = frame_path
    try:
        bpy.ops.render.render(write_still=True)
    except Exception as e:
        print(f"\n[ERROR] Render failed on frame {i}: {e}")
        print("  Try switching to CYCLES by editing RENDER_ENGINE in the .py script")
        sys.exit(1)

    if not os.path.exists(frame_path):
        print(f"\n[ERROR] Frame {i} was not saved to: {frame_path}")
        print("  Blender may not have permission to write to this folder.")
        print("  Try moving the model file to your Desktop and re-running.")
        sys.exit(1)

    progress = (i + 1) / NUM_ANGLES * 100
    print(f"      Frame {i+1}/{NUM_ANGLES} ({angle_deg:.1f}) - {progress:.0f}%")

# ════════════════════════════════════════════════════════
#  STEP 8: COMPOSITE INTO SPRITESHEET
# ════════════════════════════════════════════════════════

print("\n[COMPOSITING] Building spritesheet...")

# Load all frame images and combine into horizontal strip
import struct
import zlib

# Simple PNG compositing using Blender's image API
sheet_width = FRAME_SIZE * NUM_ANGLES
sheet_height = FRAME_SIZE

# Create new image for the spritesheet
sheet = bpy.data.images.new("spritesheet", width=sheet_width, height=sheet_height, alpha=True)

# Initialize with transparent black
pixels = [0.0] * (sheet_width * sheet_height * 4)

for i in range(NUM_ANGLES):
    frame_path = os.path.join(temp_dir, f"frame_{i:03d}.png")
    if not os.path.exists(frame_path):
        print(f"  [WARN] Missing frame: {frame_path}")
        continue

    # Load the frame image
    frame_img = bpy.data.images.load(frame_path)
    frame_pixels = list(frame_img.pixels)

    # Copy into spritesheet at the right position
    x_offset = i * FRAME_SIZE
    for y in range(FRAME_SIZE):
        for x in range(FRAME_SIZE):
            src_idx = (y * FRAME_SIZE + x) * 4
            dst_idx = (y * sheet_width + (x_offset + x)) * 4
            pixels[dst_idx] = frame_pixels[src_idx]
            pixels[dst_idx + 1] = frame_pixels[src_idx + 1]
            pixels[dst_idx + 2] = frame_pixels[src_idx + 2]
            pixels[dst_idx + 3] = frame_pixels[src_idx + 3]

    # Clean up
    bpy.data.images.remove(frame_img)

# Set pixels and save
sheet.pixels = pixels
if not OUTPUT_NAME:
    OUTPUT_NAME = "player_spritesheet.png"
output_path = os.path.join(OUTPUT_DIR, OUTPUT_NAME)
sheet.filepath_raw = output_path
sheet.file_format = 'PNG'
sheet.save()

# Also save individual frames as a backup (useful for debugging)
# Keep the temp dir but note its location

print(f"\n{'='*60}")
print(f"  DONE!")
print(f"  Spritesheet: {output_path}")
print(f"  Size: {sheet_width} x {sheet_height} pixels")
print(f"  Frames: {NUM_ANGLES} x {FRAME_SIZE}px each")
print(f"  Individual frames in: {temp_dir}")
print(f"{'='*60}")
print(f"\n  Copy {OUTPUT_NAME} to your game folder.")
print(f"  The game will automatically detect and use it.\n")
