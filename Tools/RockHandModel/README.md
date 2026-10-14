# Rock-hand 3D model

Source for `HiddenJams/Resources/RockHand.usdz`, the 🤘 that spins on the paywall.

The hand is original work, generated procedurally, with no third-party mesh or
artwork. `model_hand.py` defines it as a signed distance field — a rounded slab
for the palm, tapered capsules for the fingers and thumb — and meshes it with
marching cubes. Each finger blends softly into the palm but is hard-joined to its
neighbours, so the fingers stay distinct instead of melting into a mitten.
`build_scene.py` smooths and decimates the mesh in Blender, assigns materials,
renders previews and exports the USDZ.

Current export: ~36k triangles, 1.7 MB, watertight (no open or non-manifold edges).

## Regenerate

Needs Python 3.11, which is what Blender's `bpy` module is built for.

```bash
python3.11 -m venv .venv
.venv/bin/pip install bpy scikit-image
mkdir -p work/out work/renders

.venv/bin/python model_hand.py work/out        # ~1 min: SDF -> hand + nail meshes
.venv/bin/python build_scene.py work export    # -> work/out/RockHand.usdz (+ .glb)
cp work/out/RockHand.usdz ../../HiddenJams/Resources/
```

Preview renders (Cycles on CPU, written to `work/renders/`):

```bash
.venv/bin/python build_scene.py work render 0 45 90 180
.venv/bin/python build_scene.py work turntable frames=36 res=400 samples=40
```

Inspect an export with Pixar's USD tools, kept in their own venv apart from
Blender's bundled USD libraries:

```bash
python3 -m venv .venv-usd && .venv-usd/bin/pip install usd-core
.venv-usd/bin/python inspect_usd.py work/out/RockHand.usdz
```

It reports the up axis, the parts and their materials, and checks that the palm
faces +Z (toward SceneKit's default camera).

## Tweaking

- **Pose and proportions:** the point and radius tables near the top of
  `model_hand.py` (`INDEX_PTS`, `THUMB_PTS`, …). Model space is +y up, +z toward
  the viewer: a right hand, palm forward.
- **Colours:** `RockHandScene.skinColor` and `nailColor` in
  `HiddenJams/Views/Components/RockHand3DView.swift`. The app overrides the
  exported materials, so changing colour needs no re-export.
- **Spin speed, tilt and lighting:** also in `RockHand3DView.swift`.

The export must keep two parts whose names contain "Hand" and "Nails" — the app
assigns materials by name — and `RockHand3DTests` will fail if the model stops
loading.
