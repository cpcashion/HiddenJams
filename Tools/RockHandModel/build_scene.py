"""
Builds the 🤘 hand in Blender from the SDF meshes, cleans it up, and either
renders preview angles or exports app assets.

Usage (<work_dir> must contain out/ with the meshes from model_hand.py, and renders/):
    python build_scene.py <work_dir> render <angle_deg> [<angle_deg> ...] [res=N] [samples=N]
    python build_scene.py <work_dir> turntable [frames=N] [res=N] [samples=N]
    python build_scene.py <work_dir> export
"""

import math
import os
import sys

import bpy
import numpy as np

WORK = sys.argv[1]
MODE = sys.argv[2]
OUT = os.path.join(WORK, "out")
RENDERS = os.path.join(WORK, "renders")

# Brand amber from Theme.Colors.gemGold (dark mode, #F59E0B), in linear RGB.
def srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

AMBER = tuple(srgb_to_linear(v) for v in (0xF2, 0x86, 0x0C)) + (1.0,)
NAIL = tuple(srgb_to_linear(v) for v in (0xF9, 0xBE, 0x78)) + (1.0,)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mesh_from_npz(name, path, target_faces):
    data = np.load(path)
    v = data["verts"].astype(np.float64)
    f = data["faces"]
    # Model space is +y up, +z toward the viewer. Blender is Z-up with the
    # front view looking along +Y, so (x, y, z) -> (x, -z, y).
    v = np.stack([v[:, 0], -v[:, 2], v[:, 1]], axis=1)

    me = bpy.data.meshes.new(name)
    me.from_pydata(v.tolist(), [], f.tolist())
    me.validate(clean_customdata=False)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)

    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)

    # Marching cubes leaves faint terracing; a light Laplacian pass removes it
    # without shrinking the silhouette.
    sm = ob.modifiers.new("Smooth", "LAPLACIANSMOOTH")
    sm.lambda_factor = 0.6
    sm.iterations = 6
    sm.use_volume_preserve = True
    bpy.ops.object.modifier_apply(modifier=sm.name)

    dec = ob.modifiers.new("Decimate", "DECIMATE")
    dec.decimate_type = "COLLAPSE"
    dec.ratio = min(1.0, target_faces / max(len(me.polygons), 1))
    bpy.ops.object.modifier_apply(modifier=dec.name)

    bpy.ops.object.shade_smooth()
    ob.select_set(False)
    return ob


def material(name, color, roughness, coat, coat_roughness, subsurface=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Coat Weight"].default_value = coat
    bsdf.inputs["Coat Roughness"].default_value = coat_roughness
    if subsurface:
        bsdf.inputs["Subsurface Weight"].default_value = subsurface
        bsdf.inputs["Subsurface Radius"].default_value = (1.0, 0.35, 0.15)
        bsdf.inputs["Subsurface Scale"].default_value = 0.03
    return mat


def build():
    reset()
    hand = mesh_from_npz("Hand", os.path.join(OUT, "hand.npz"), 32000)
    nails = mesh_from_npz("Nails", os.path.join(OUT, "nails.npz"), 4500)

    # Centre vertically so the app can spin it about its middle. Keep the
    # horizontal origin on the palm axis (x = y = 0): spinning about the palm
    # looks natural, whereas the bounding-box centre is dragged sideways by
    # the thumb and makes the hand wobble as it turns.
    zs = [v.co.z for ob in (hand, nails) for v in ob.data.vertices]
    zc = (min(zs) + max(zs)) / 2
    for ob in (hand, nails):
        for v in ob.data.vertices:
            v.co.z -= zc
        ob.data.update()

    hand.data.materials.append(material("HandMaterial", AMBER, 0.34, 1.0, 0.05))
    nails.data.materials.append(material("NailMaterial", NAIL, 0.22, 0.6, 0.05))

    # Parent everything to an empty at the hand's visual centre so it spins
    # around its own middle rather than the wrist.
    root = bpy.data.objects.new("RockHand", None)
    bpy.context.collection.objects.link(root)
    for ob in (hand, nails):
        ob.parent = root
    return root, hand, nails


def setup_render(root):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 64
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 520
    scene.render.resolution_y = 520
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"

    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    env = nt.nodes.new("ShaderNodeTexEnvironment")
    studio = os.path.join(bpy.utils.resource_path("LOCAL"), "datafiles", "studiolights", "world", "studio.exr")
    env.image = bpy.data.images.load(studio)
    nt.links.new(env.outputs["Color"], nt.nodes["Background"].inputs["Color"])
    nt.nodes["Background"].inputs["Strength"].default_value = 0.9

    # Key light: large soft area light above-front-left for a clean highlight.
    key = bpy.data.lights.new("Key", "AREA")
    key.energy = 260
    key.size = 1.6
    key_ob = bpy.data.objects.new("Key", key)
    key_ob.location = (-1.4, -2.0, 2.2)
    scene.collection.objects.link(key_ob)
    _aim(key_ob, (0, 0, 0.1))

    rim = bpy.data.lights.new("Rim", "AREA")
    rim.energy = 180
    rim.size = 1.0
    rim_ob = bpy.data.objects.new("Rim", rim)
    rim_ob.location = (1.8, 1.6, 1.4)
    scene.collection.objects.link(rim_ob)
    _aim(rim_ob, (0, 0, 0.1))

    cam = bpy.data.cameras.new("Camera")
    cam.lens = 85
    cam_ob = bpy.data.objects.new("Camera", cam)
    cam_ob.location = (0, -5.6, 0.12)
    scene.collection.objects.link(cam_ob)
    _aim(cam_ob, (0, 0, 0.08))
    scene.camera = cam_ob


def _aim(ob, target):
    from mathutils import Vector
    direction = Vector(target) - ob.location
    ob.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def render_angles(root, angles):
    scene = bpy.context.scene
    for deg in angles:
        root.rotation_euler = (0, 0, math.radians(deg))
        scene.render.filepath = os.path.join(RENDERS, f"angle_{deg:06.2f}.png")
        bpy.ops.render.render(write_still=True)
        print("rendered", deg)


root, hand, nails = build()
print("hand faces:", len(hand.data.polygons), "nail faces:", len(nails.data.polygons))

if MODE in ("render", "turntable"):
    setup_render(root)
    opts = dict(arg.split("=") for arg in sys.argv[3:] if "=" in arg)
    angles = [float(arg) for arg in sys.argv[3:] if "=" not in arg]
    sc = bpy.context.scene
    sc.render.resolution_x = sc.render.resolution_y = int(opts.get("res", 520))
    sc.cycles.samples = int(opts.get("samples", 64))
    if MODE == "turntable":
        frames = int(opts.get("frames", 24))
        angles = [i * 360.0 / frames for i in range(frames)]
    render_angles(root, angles)


def health(ob):
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    non_manifold = sum(1 for e in bm.edges if not e.is_manifold)
    boundary = sum(1 for e in bm.edges if e.is_boundary)
    print(f"{ob.name}: {len(bm.verts)} verts, {len(bm.faces)} faces, "
          f"non-manifold edges={non_manifold}, open boundary edges={boundary}")
    bm.free()


if MODE == "export":
    for ob in (hand, nails):
        health(ob)
    bpy.ops.wm.usd_export(
        filepath=os.path.join(OUT, "RockHand.usdz"),
        export_materials=True,
        generate_preview_surface=True,
        export_normals=True,
        export_uvmaps=False,
        export_mesh_colors=False,
        convert_orientation=True,
        export_global_forward_selection="NEGATIVE_Z",
        export_global_up_selection="Y",
        evaluation_mode="RENDER",
    )
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT, "RockHand.glb"),
        export_format="GLB",
        export_yup=True,
        export_apply=True,
    )
    print("exported")
