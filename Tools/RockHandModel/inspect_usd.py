import sys
from pxr import Usd, UsdGeom, UsdShade, Gf
stage = Usd.Stage.Open(sys.argv[1])
print("upAxis:", UsdGeom.GetStageUpAxis(stage), "| metersPerUnit:", UsdGeom.GetStageMetersPerUnit(stage))
print("defaultPrim:", stage.GetDefaultPrim().GetPath() if stage.GetDefaultPrim() else None)
cache = UsdGeom.BBoxCache(Usd.TimeCode.Default(), [UsdGeom.Tokens.default_, UsdGeom.Tokens.render])
for prim in stage.Traverse():
    line = f"  {prim.GetPath()}  <{prim.GetTypeName()}>"
    if prim.IsA(UsdGeom.Mesh):
        m = UsdGeom.Mesh(prim)
        n = UsdGeom.PrimvarsAPI(prim).GetPrimvar("normals")
        interp = n.GetInterpolation() if n and n.IsDefined() else (m.GetNormalsInterpolation() if m.GetNormalsAttr().HasValue() else "none")
        mat = UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()[0]
        line += f" pts={len(m.GetPointsAttr().Get())} faces={len(m.GetFaceVertexCountsAttr().Get())} normals={interp} material={mat.GetPath() if mat else None}"
    print(line)
box = cache.ComputeWorldBound(stage.GetPseudoRoot()).ComputeAlignedRange()
mn, mx = box.GetMin(), box.GetMax()
print(f"world bounds  x[{mn[0]:+.3f},{mx[0]:+.3f}]  y[{mn[1]:+.3f},{mx[1]:+.3f}]  z[{mn[2]:+.3f},{mx[2]:+.3f}]")
# Orientation check: the thumb sticks out of the PALM side. In model space the
# palm faces +z, reaching ~+0.42; the back of the hand only reaches ~-0.17.
front, back = mx[2], -mn[2]
print("palm faces", "+Z (toward SceneKit's default camera) ✓" if front > back else "-Z ✗", f"(front {front:.2f} vs back {back:.2f})")
print("tallest axis:", "Y ✓" if (mx[1]-mn[1]) > max(mx[0]-mn[0], mx[2]-mn[2]) else "not Y ✗")
