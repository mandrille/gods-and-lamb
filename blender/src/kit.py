r"""Shared builder kit: primitives, booleans, rounding, materials, palette.

Ported from C:\Goliath\Robotin\blender\src\kit.py, which is style-agnostic --
only the colour values and three bevel constants encoded its cosy-industrial
look. Those are what changed. Every call site is the same.

Dropped: the industrial sub-assemblies (bolt_circle, flange, ibeam,
louvre_panel, finned_cylinder, handwheel, gauge, ladder, cable_tray, pipe_run).
Nothing in a cute village is made of those.

Added: soften_top(), because rounding ALL edges of a ground tile makes
neighbouring tiles fail to meet -- see its docstring.

Everything is scale-agnostic; the caller works in metres. 1 tile = 1.0 m.
"""
import math

import bpy
import bmesh
from mathutils import Vector

STATS = {"bool": 0, "obj": 0}


# ------------------------------------------------------------------ materials
def flat(name, rgb, rough=0.42, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m


def pane(name, rgb, alpha, rough=0.06):
    """A transparent sheet.

    Both blend properties are set: `blend_method` is what the glTF exporter has
    historically read to decide alphaMode, `surface_render_method` is what EEVEE
    Next uses, and which one matters depends on the Blender version. The ALPHA
    INPUT is set as well as the base colour alpha, because the exporter takes
    the Principled BSDF Alpha socket, not the fourth channel of the colour.
    """
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, alpha)
    b.inputs["Alpha"].default_value = alpha
    b.inputs["Roughness"].default_value = rough
    if hasattr(m, "blend_method"):
        m.blend_method = "BLEND"
    if hasattr(m, "surface_render_method"):
        m.surface_render_method = "BLENDED"
    return m


def emit(name, rgb, strength):
    """Emissive. Use sparingly: GL Compatibility CLAMPS emission, so this is a
    hint of warmth in a window, never a light source. Nothing is lit by it."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1.0)
    b.inputs["Emission Color"].default_value = (*rgb, 1.0)
    b.inputs["Emission Strength"].default_value = strength
    return m


M = {}
SCHEMES = {}          # name -> {body, trim, roof, accent}, see init_materials()


def init_materials():
    """Called once per build, after the factory-settings wipe and before any
    builder runs, or the M[...] lookups fail.

    Vibrant and saturated. There is no ambient occlusion under GL Compatibility
    to separate two touching surfaces, so the palette carries that load: hues
    are spread out and values kept in a narrow band. Two neutrals of different
    brightness read as ONE object under a single key light, which is how the
    parent project lost `plate` against `dark`.
    """
    M.clear()
    M.update({
        # ---- ground
        "grass":      flat("Grass", (0.420, 0.800, 0.170), 0.58),
        "grass_dark": flat("GrassDark", (0.240, 0.580, 0.130), 0.60),
        "dirt":       flat("Dirt", (0.460, 0.270, 0.130), 0.66),
        "dirt_dark":  flat("DirtDark", (0.300, 0.170, 0.085), 0.68),
        "soil":       flat("Soil", (0.330, 0.200, 0.120), 0.74),
        "sand":       flat("Sand", (0.910, 0.760, 0.400), 0.66),
        "stone":      flat("Stone", (0.640, 0.618, 0.575), 0.60),
        "stone_dark": flat("StoneDark", (0.450, 0.430, 0.400), 0.62),
        # Water is OPAQUE. A transparent surface over a modelled bed costs a
        # second draw and an alpha sort on a mobile GPU, for a pond seen from
        # forty degrees. Colour does the job.
        "water":      flat("Water", (0.180, 0.520, 0.820), 0.18),
        "water_deep": flat("WaterDeep", (0.100, 0.340, 0.660), 0.18),
        # ---- built
        "wood":       flat("Wood", (0.620, 0.400, 0.210), 0.58),
        "wood_dark":  flat("WoodDark", (0.380, 0.240, 0.130), 0.60),
        "plaster":    flat("Plaster", (0.930, 0.890, 0.790), 0.66),
        "thatch":     flat("Thatch", (0.800, 0.640, 0.300), 0.72),
        "terracotta": flat("Terracotta", (0.820, 0.360, 0.220), 0.58),
        "slate":      flat("Slate", (0.300, 0.430, 0.620), 0.52),
        "gold":       flat("Gold", (0.900, 0.720, 0.230), 0.34, metal=0.6),
        "iron":       flat("Iron", (0.380, 0.390, 0.420), 0.44, metal=0.5),
        # A door or a window is a HOLE, and a hole is this colour. Cut the
        # opening, floor it with `hollow`, and stop -- at 15 px a modelled
        # handle is noise costing 200 triangles.
        "hollow":     flat("Hollow", (0.090, 0.075, 0.080), 0.90),
        "warmglow":   emit("WarmGlow", (1.00, 0.78, 0.42), 3.0),
        # ---- growing
        "leaf":       flat("Leaf", (0.260, 0.600, 0.230), 0.66),
        "leaf_dark":  flat("LeafDark", (0.150, 0.420, 0.180), 0.66),
        "leaf_light": flat("LeafLight", (0.440, 0.760, 0.290), 0.66),
        "trunk":      flat("Trunk", (0.450, 0.290, 0.170), 0.68),
        "crop":       flat("Crop", (0.560, 0.740, 0.250), 0.64),
        "crop_ripe":  flat("CropRipe", (0.900, 0.740, 0.240), 0.62),
        "pumpkin":    flat("Pumpkin", (0.930, 0.520, 0.130), 0.56),
        "petal_red":  flat("PetalRed", (0.900, 0.250, 0.280), 0.54),
        "petal_pink": flat("PetalPink", (0.960, 0.560, 0.720), 0.54),
        "petal_blue": flat("PetalBlue", (0.420, 0.520, 0.930), 0.54),
        "petal_gold": flat("PetalGold", (0.980, 0.820, 0.260), 0.54),
        # ---- folk
        "skin":       flat("Skin", (0.960, 0.780, 0.620), 0.64),
        "skin_warm":  flat("SkinWarm", (0.780, 0.560, 0.380), 0.64),
        "wool":       flat("Wool", (0.960, 0.940, 0.900), 0.78),
        "hair_dark":  flat("HairDark", (0.200, 0.140, 0.110), 0.70),
        "hair_warm":  flat("HairWarm", (0.640, 0.360, 0.150), 0.70),
        "cloth_red":  flat("ClothRed", (0.820, 0.250, 0.230), 0.70),
        "cloth_blue": flat("ClothBlue", (0.230, 0.430, 0.780), 0.70),
        "cloth_teal": flat("ClothTeal", (0.150, 0.620, 0.590), 0.70),
        "cloth_plum": flat("ClothPlum", (0.560, 0.270, 0.560), 0.70),
    })
    # Colourways, keyed by NAME. In the parent project these were a list
    # selected by `idx % 6`, so adding a seventh silently repainted every
    # existing asset and made an asset colour a function of its position in an
    # unrelated list. Names are additive: a new entry cannot disturb an old one.
    SCHEMES.clear()
    SCHEMES.update({
        "cottage_red":  {"body": "plaster", "trim": "wood", "roof": "terracotta", "accent": "cloth_blue"},
        "cottage_blue": {"body": "plaster", "trim": "wood_dark", "roof": "slate", "accent": "petal_gold"},
        "hut_thatch":   {"body": "wood", "trim": "wood_dark", "roof": "thatch", "accent": "cloth_red"},
        "shrine_gold":  {"body": "stone", "trim": "stone_dark", "roof": "gold", "accent": "cloth_plum"},
        "stall_market": {"body": "wood", "trim": "cloth_red", "roof": "cloth_teal", "accent": "crop_ripe"},
    })


def scheme(key):
    """(body, trim, roof, accent) materials for a colourway NAME."""
    if key not in SCHEMES:
        raise SystemExit("FAIL: no colour scheme '%s' (have: %s)"
                         % (key, ", ".join(SCHEMES)))
    s = SCHEMES[key]
    return (M[s["body"]], M[s["trim"]], M[s["roof"]], M[s["accent"]])


# --------------------------------------------------------------- soft shading
def soften(ob, angle=44.0):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    try:
        bpy.ops.object.shade_auto_smooth(angle=math.radians(angle))
    except (AttributeError, RuntimeError):
        bpy.ops.object.shade_smooth()
    ob.select_set(False)


# Three segments, not the parent project one. Rounded cubes ARE the art
# direction here, and a single-segment bevel reads as a chamfer, not a radius.
# It costs about 2.4x the triangles, which is why terrain and vegetation pass
# segments=2 explicitly -- see SEGMENTS.
BEVEL_SEGMENTS = 3

# Zero, not the parent project 1.0 m. Everything gets rounded, including a
# 10 cm flower. Skipping small assemblies was a triangle economy that only made
# sense when rounding was a finish rather than the point.
BEVEL_MIN_HEIGHT = 0.0

# What each class should pass. Advisory -- builders pass segments= themselves --
# but a builder that disagrees with this table should say why in a comment.
SEGMENTS = {"terrain": 2, "nature": 2, "folk": 3, "building": 3}


def assembly_height(parts):
    """Overall Z extent of a part list, in metres."""
    zs = []
    for ob in parts:
        if ob is None or ob.type != "MESH":
            continue
        for c in ob.bound_box:
            zs.append((ob.matrix_world @ Vector(c)).z)
    return (max(zs) - min(zs)) if zs else 0.0


def soften_all(parts, width=0.06, segments=BEVEL_SEGMENTS, angle=44.0,
               min_height=BEVEL_MIN_HEIGHT):
    """Round and smooth a finished assembly.

    Run this AFTER all booleans in a builder. Bevelling first tears the cut
    edges, which is why box()/cyl() stay sharp and this is a separate pass.

    The width is clamped to a quarter of the smallest dimension of each part, so
    asking for 6 cm on a 1 cm slat gives 2.5 mm rather than a collapsed mesh.
    Parts thinner than that are smooth-shaded and not bevelled.

    Everything is tagged `softened` either way, so the coverage assert measures
    "went through this pass", not "has a bevel".
    """
    do_bevel = assembly_height(parts) >= min_height
    done = 0
    for ob in parts:
        if ob is None or ob.type != "MESH":
            continue
        ob["softened"] = True          # covers bevelled AND deliberately skipped
        if not do_bevel:
            soften(ob, angle)
            continue
        smallest = min(ob.dimensions) if len(ob.dimensions) else 0.0
        w = min(width, smallest * 0.25)
        if w < 0.002 or smallest < width * 0.6:
            soften(ob, angle)          # too thin to bevel - still smooth it
            continue
        bv = ob.modifiers.new("Soften", "BEVEL")
        bv.width = w
        bv.segments = segments
        bv.limit_method = "ANGLE"
        # 50 deg, not 30. A bevel is for genuinely sharp edges - box corners and
        # cylinder rims are 90 deg and still qualify. At 30 deg the facets of a
        # coarse sphere or torus (~36 deg) qualify too, so every round primitive
        # gets bevelled: pure cost, no visual gain. In the parent project it more
        # than DOUBLED some assets - a plant went 1024 -> 2296 tris bevelling
        # foliage spheres.
        bv.angle_limit = math.radians(50)
        bv.harden_normals = False
        bv.use_clamp_overlap = True
        soften(ob, angle)
        done += 1
    return done


def mark_bevel_weight_top(ob, weight=1.0, side=0.0, eps=1e-4):
    """Set edge bevel weight on the top rim, and optionally the vertical edges.

    The selector the Bevel modifier does not have: it limits by angle or by
    weight, and "the edges at the top" is neither -- so the weight is written
    here and the modifier is told to use it.

    `side` scales the vertical edges relative to the top rim, because the Bevel
    modifier multiplies its width by the weight. Use it on the grass CAP of a
    ground tile and not on the dirt body: the cap corners round, so a floor
    reads as separated blocks the way the reference does, while the body stays
    full width and there is nothing to see through. Rounding the body as well
    would open a hole at every point where four tiles meet.

    Returns (top_edges, side_edges).
    """
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    if not bm.verts:
        bm.free()
        return 0, 0
    zmax = max(v.co.z for v in bm.verts)
    zmin = min(v.co.z for v in bm.verts)
    # Blender 4.x moved bevel weight to a generic named attribute. The old
    # bm.edges.layers.bevel_weight is gone in 5.x, so the named layer is tried
    # first and the legacy one only as a fallback.
    lay = bm.edges.layers.float.get("bevel_weight_edge")
    if lay is None:
        try:
            lay = bm.edges.layers.float.new("bevel_weight_edge")
        except (ValueError, TypeError):
            lay = None
    if lay is None:
        legacy = getattr(bm.edges.layers, "bevel_weight", None)
        lay = legacy.verify() if legacy is not None else None
    if lay is None:
        bm.free()
        raise SystemExit("FAIL: %s - no edge bevel-weight layer available on "
                         "this Blender. soften_top cannot mark the top rim."
                         % ob.name)
    n_top = n_side = 0
    for e in bm.edges:
        z0, z1 = e.verts[0].co.z, e.verts[1].co.z
        if abs(z0 - zmax) < eps and abs(z1 - zmax) < eps:
            e[lay] = weight
            n_top += 1
        elif side > 0.0 and abs(z0 - z1) > eps                 and (abs(min(z0, z1) - zmin) < eps or abs(max(z0, z1) - zmax) < eps):
            e[lay] = weight * side
            n_side += 1
        else:
            e[lay] = 0.0
    bm.to_mesh(me)
    bm.free()
    me.update()
    return n_top, n_side


def soften_top(ob, width=0.09, segments=3, angle=44.0, side=0.0):
    """Round the TOP RIM only. For anything that tiles.

    The art direction is rounded cubes, so the obvious build is a box through
    soften_all(). It is wrong for ground: bevelling the vertical edges pulls the
    four SIDE faces inward, so two neighbouring tiles no longer touch and a
    field of grass becomes a grid of separate blocks with the sky showing
    through the cracks between them.

    So the side faces stay flat and full width -- tiles butt together, a cliff
    face is a clean vertical plane -- and only the exposed top edge is softened.
    That still leaves a shallow groove where two tiles meet, which is correct:
    the reference art shows exactly that, individual cube tops reading as a
    subtle grid across the grass.

    Same stack as soften_all -- a live Bevel modifier, weight-limited instead of
    angle-limited, with Weighted Normal added last by weighted_normals_all().
    Baking this with bmesh.ops.bevel instead was the first attempt, and it left
    the mesh outside the standard stack: no WN, so the normals came from
    auto-smooth alone and every large face carried a soft gradient across it.
    """
    n_top, n_side = mark_bevel_weight_top(ob, side=side)
    bv = ob.modifiers.new("SoftenTop", "BEVEL")
    bv.width = width
    bv.segments = segments
    bv.limit_method = "WEIGHT"
    bv.harden_normals = False
    bv.use_clamp_overlap = True
    ob["softened"] = True
    soften(ob, angle)
    return n_top, n_side


def evaluated_tris(ob):
    """Triangles this object ACTUALLY renders.

    ob.data.calc_loop_triangles() counts the base mesh and is blind to unapplied
    modifiers - it understated the parent project by ~4.9x until merging baked
    them. Never report a triangle count that did not come through here.
    """
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    try:
        m = ev.to_mesh()
    except RuntimeError:
        return 0
    m.calc_loop_triangles()
    n = len(m.loop_triangles)
    ev.to_mesh_clear()
    return n


# 60 degrees, and the value is load-bearing. A bevel turns one 90-degree corner
# into shallower edges: above 60 they stay SMOOTH, which is the whole point of
# bevel + weighted normal. An UNBEVELLED box corner is 90 degrees, so it falls
# the other side and stays hard. One threshold separates the two cases.
SHARP_ANGLE = 60.0


def mark_sharp(ob, angle=SHARP_ANGLE):
    """Flag edges sharper than `angle` so Weighted Normal can keep them.

    This is the fix for a mesh with NO bevel. weighted_normals_all force-shades
    every mesh fully smooth, which is correct for bevelled geometry and actively
    wrong without it: parts too thin to bevel are skipped inside assemblies that
    are not, so a merged asset is routinely a MIX. Shading all of it smooth
    melts every unbevelled 90-degree corner and undoes the angle-based shading
    soften() just applied.

    Mark on the FINAL merged geometry, where the bevel is already baked -- by
    then the two cases are simply different angles.
    """
    me = ob.data
    thresh = math.radians(angle)
    bm = bmesh.new()
    bm.from_mesh(me)
    n = 0
    for e in bm.edges:
        if len(e.link_faces) == 2:
            sharp = e.calc_face_angle(0.0) >= thresh
            e.smooth = not sharp
            n += int(sharp)
    bm.to_mesh(me)
    bm.free()
    me.update()
    return n


def weighted_normals_all(objects, mode="FACE_AREA", weight=100, thresh=0.01,
                         keep_sharp=True, face_influence=False, skip_names=(),
                         sharp_angle=SHARP_ANGLE):
    """Add a Weighted Normal modifier to every mesh, last in the stack.

    WN must be last or it does nothing - whatever runs after it recomputes the
    normals it just wrote.

    The catch in Blender 4.1+: shade_auto_smooth() adds a "Smooth by Angle"
    geometry-nodes modifier that is PINNED to the end of the stack.
    modifiers.new() inserts before it, and modifiers.move() reports success
    while silently leaving it last. So auto-smooth and Weighted Normal cannot
    coexist. The fix is to drop Smooth by Angle, shade fully smooth, and let
    Bevel + WN control the normals.

    keep_sharp defaults TRUE with edges marked by angle first, so bevelled edges
    stay smooth and unbevelled corners stay crisp.
    """
    added = 0
    for ob in objects:
        if ob is None or ob.type != "MESH" or ob.name in skip_names:
            continue
        if not len(ob.data.polygons):
            continue
        if any(m.type == "WEIGHTED_NORMAL" for m in ob.modifiers):
            continue
        for m in [m for m in ob.modifiers
                  if m.type == "NODES" and m.name.startswith("Smooth by Angle")]:
            ob.modifiers.remove(m)
        n = len(ob.data.polygons)
        ob.data.polygons.foreach_set("use_smooth", [True] * n)
        mark_sharp(ob, sharp_angle)
        ob.data.update()
        wn = ob.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
        for attr, val in (("mode", mode), ("weight", weight), ("thresh", thresh),
                          ("keep_sharp", keep_sharp),
                          ("use_face_influence", face_influence)):
            try:
                setattr(wn, attr, val)
            except (AttributeError, TypeError):
                pass
        last = len(ob.modifiers) - 1
        idx = list(ob.modifiers).index(wn)
        if idx != last:
            try:
                ob.modifiers.move(idx, last)
            except (AttributeError, RuntimeError, TypeError):
                bpy.context.view_layer.objects.active = ob
                bpy.ops.object.modifier_move_to_index(modifier=wn.name, index=last)
        added += 1
    return added


def weighted_normal_coverage(objects, skip_names=()):
    """(fraction, offenders) - a mesh counts only if WN exists AND is last."""
    meshes = [o for o in objects if o is not None and o.type == "MESH"
              and len(o.data.polygons) and o.name not in skip_names]
    bad = [o.name for o in meshes
           if not o.modifiers or o.modifiers[-1].type != "WEIGHTED_NORMAL"]
    if not meshes:
        return 1.0, []
    return (len(meshes) - len(bad)) / len(meshes), bad


def soften_coverage(objects):
    """Fraction of mesh objects that went through soften_all or soften_top."""
    meshes = [o for o in objects if o is not None and o.type == "MESH"]
    if not meshes:
        return 1.0, []
    missing = [o.name for o in meshes if not o.get("softened")]
    return (len(meshes) - len(missing)) / len(meshes), missing


# -------------------------------------------------------------------- cleanup
# 0.1 mm. Everything is authored in metres and the thinnest deliberate feature
# is a 2 mm bevel, so welding at this distance cannot destroy anything intended
# - but it does collapse the sliver faces an EXACT boolean leaves when a cut
# passes very close to an existing vertex.
WELD_DIST = 1e-4

# A face below this has no usable normal. 1e-9 m2 is a thousandth of a square
# millimetre - nothing intentional is remotely that small.
DEGENERATE_AREA = 1e-9


def clean_mesh(ob, dist=WELD_DIST, triangulate_ngons=True):
    """Repair the debris an EXACT boolean leaves behind.

    Not retopology - remeshing would destroy the silhouette and the bevel
    highlights and cost triangles doing it. What booleans leave is rubbish:
    duplicate verts, zero-area faces and zero-length edges along the seam (no
    usable normal, so they shade as specks and poison the area-weighted normals
    of every face touching them), loose verts, and non-planar ngons, which
    triangulate differently in Blender and in the engine and are therefore the
    classic "it looked fine in Blender" artifact.

    Measured in the parent project before this existed: 1297 ngons, 64
    degenerate faces, 224 duplicate verts, 102 zero-length edges.
    """
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)

    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=dist)
    bmesh.ops.dissolve_degenerate(bm, dist=dist, edges=bm.edges[:])

    # Triangulation and sliver-collapse each CREATE work for the other, so they
    # run to a fixed point rather than once each: splitting a non-planar ngon
    # produces slivers, and collapsing a sliver edge can fuse neighbouring
    # triangles back into an ngon. One pass of each left 4 degenerate faces per
    # column in the parent project; the other order left 30 ngons.
    for _ in range(6):
        work = False
        if triangulate_ngons:
            ngons = [f for f in bm.faces if len(f.verts) > 4]
            if ngons:
                bmesh.ops.triangulate(bm, faces=ngons, quad_method="BEAUTY",
                                      ngon_method="BEAUTY")
                work = True
        degen = [f for f in bm.faces if f.calc_area() < DEGENERATE_AREA]
        if degen:
            edges = {min(f.edges, key=lambda e: e.calc_length()) for f in degen}
            bmesh.ops.collapse(bm, edges=list(edges), uvs=False)
            bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=dist)
            work = True
        if not work:
            break

    # Safety net: collapsing a sliver COULD delete the faces either side and
    # leave a boundary, and a hole leaks light. sides=64 because a capped bore
    # is a 24-gon and the default limit of 4 would silently refuse it.
    holes = [e for e in bm.edges if len(e.link_faces) == 1]
    if holes:
        bmesh.ops.holes_fill(bm, edges=holes, sides=64)
        tris = [f for f in bm.faces if len(f.verts) > 4]
        if tris and triangulate_ngons:
            bmesh.ops.triangulate(bm, faces=tris, quad_method="BEAUTY",
                                  ngon_method="BEAUTY")

    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])

    bm.to_mesh(me)
    bm.free()
    me.update()
    return ob


def mesh_defects(ob, dist=1e-5):
    """Count what clean_mesh removes. Used by the assert, and by nothing else."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    out = {
        "ngons": sum(1 for f in bm.faces if len(f.verts) > 4),
        "degenerate": sum(1 for f in bm.faces if f.calc_area() < DEGENERATE_AREA),
        "zero_edges": sum(1 for e in bm.edges if e.calc_length() < dist),
        "loose": sum(1 for v in bm.verts if not v.link_faces),
        "nonmanifold": sum(1 for e in bm.edges if not e.is_manifold),
    }
    before = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=dist)
    out["doubles"] = before - len(bm.verts)
    bm.free()
    return out


# ------------------------------------------------------------------- assembly
def merge_group(root, name=None, keep_empties=True):
    """Collapse every mesh under `root` into ONE object.

    An asset is authored as many primitives because booleans need them separate.
    The engine wants one mesh, one draw call - and for terrain, MultiMesh
    REQUIRES it. So once the geometry is final, join it.

    Order matters: join() keeps only the ACTIVE object modifiers and discards
    the rest, so modifiers are baked first with convert(). Triangle count is
    therefore unchanged by merging - the same geometry in one container.

    The merged mesh is re-parented to `root` DIRECTLY, preserving world
    position. join() leaves it under whatever intermediate empty the active mesh
    belonged to, and that nesting is a trap: deleting an intermediate empty
    later makes Blender keep the child LOCAL transform, silently teleporting the
    mesh 2.7 m in the parent project.
    """
    meshes = [o for o in root.children_recursive if o.type == "MESH"]
    if not meshes:
        return None
    others = [o for o in root.children_recursive if o.type != "MESH"]
    # Measured BEFORE the join, because join() keeps only the active object
    # properties. The merged mesh is "softened" only if EVERY part went through
    # the pass - stamping it True unconditionally made the rounding assert
    # unable to fail for anything merged, and a whole depot of sharp-cornered
    # racking sailed through it in the parent project.
    all_soft = all(bool(o.get("softened")) for o in meshes)

    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.convert(target="MESH")      # bake Bevel before joining
    if len(meshes) > 1:
        bpy.ops.object.join()
    merged = bpy.context.object
    merged.select_set(False)
    if name:
        merged.name = name
    merged["softened"] = all_soft
    # After convert() has baked the bevel and join() has fused the parts - so it
    # catches boolean debris AND the doubles the join itself creates where two
    # parts met exactly.
    clean_mesh(merged)

    if merged.parent is not root:
        mw = merged.matrix_world.copy()
        merged.parent = root
        merged.matrix_world = mw

    if keep_empties:
        for e in others:
            if e.name in bpy.data.objects and e.parent is not merged:
                mw = e.matrix_world.copy()
                e.parent = merged
                e.matrix_world = mw
    return merged


def merge_many(objects, name):
    """Join a flat list of unrelated meshes."""
    meshes = [o for o in objects if o is not None and o.type == "MESH"]
    if not meshes:
        return None
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.convert(target="MESH")
    if len(meshes) > 1:
        bpy.ops.object.join()
    merged = bpy.context.object
    merged.select_set(False)
    merged.name = name
    merged["softened"] = True
    clean_mesh(merged)
    return merged


def purge(objects):
    """Delete scaffolding objects, refusing to orphan anything.

    bpy.data.objects.remove() on a parent does NOT reparent its children -
    Blender drops the parent transform and keeps the child LOCAL one, so the
    child teleports. Deleting an empty that still owned a merged mesh is what
    moved a pipe run 2.7 m across a room in the parent project without a single
    error. Refuse rather than repeat it.
    """
    for ob in objects:
        try:
            name = ob.name
        except ReferenceError:
            continue                       # already consumed by join()
        if name not in bpy.data.objects:
            continue
        if ob.children:
            raise SystemExit("FAIL: refusing to delete %s - it still has %d "
                             "child(ren) (%s); they would teleport"
                             % (name, len(ob.children),
                                ", ".join(c.name for c in ob.children[:3])))
        bpy.data.objects.remove(ob, do_unlink=True)


def group(name, objs, location, rot_z=0.0, scale=1.0):
    """Build at the origin, then place via an empty parent - keeps every
    boolean in a sane local space."""
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0, 0, 0))
    root = bpy.context.object
    root.name = name
    for ob in objs:
        ob.parent = root
        ob.matrix_parent_inverse = root.matrix_world.inverted()
    root.location = location
    root.rotation_euler = (0, 0, math.radians(rot_z))
    root.scale = (scale, scale, scale)
    return root


def bounds(objs):
    """World-space bbox SIZE of a part list."""
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for ob in objs:
        for c in ob.bound_box:
            w = ob.matrix_world @ Vector(c)
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
    return tuple(round(hi[i] - lo[i], 3) for i in range(3))


def bounds_lohi(parts):
    """World-space VERTEX bounds over a part list, or (None, None).

    Vertex bounds rather than bound_box, and never part origins: for a merged
    asset the whole solid has one origin, wherever its first part happened to
    be. In the parent project that put an arch origin 1.16 m off-centre and
    centre-alignment dressed a stretch of blank wall instead of the gates.
    """
    lo = [1e18, 1e18, 1e18]
    hi = [-1e18, -1e18, -1e18]
    found = False
    for p_ in parts:
        if getattr(p_, "type", None) != "MESH":
            continue
        for v in p_.data.vertices:
            w = p_.matrix_world @ v.co
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
            found = True
    return (lo, hi) if found else (None, None)


# ----------------------------------------------------------------- primitives
def box(name, center, size, mat=None, rot=None):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    ob = bpy.context.object
    ob.name = name
    ob.scale = size
    if rot:
        ob.rotation_euler = [math.radians(r) for r in rot]
    bpy.ops.object.transform_apply(location=False, rotation=bool(rot), scale=True)
    if mat:
        ob.data.materials.append(mat)
    STATS["obj"] += 1
    return ob


def cyl(name, center, r, h, mat=None, axis="Z", verts=20, rot=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h,
                                        location=center)
    ob = bpy.context.object
    ob.name = name
    if axis == "Y":
        ob.rotation_euler = (math.radians(90), 0, 0)
    elif axis == "X":
        ob.rotation_euler = (0, math.radians(90), 0)
    if rot:
        ob.rotation_euler = [math.radians(v) for v in rot]
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    if mat:
        ob.data.materials.append(mat)
    STATS["obj"] += 1
    return ob


def torus(name, center, major, minor, mat=None, plane="XY", verts=20, rings=8):
    bpy.ops.mesh.primitive_torus_add(location=center, major_radius=major,
                                     minor_radius=minor, major_segments=verts,
                                     minor_segments=rings)
    ob = bpy.context.object
    ob.name = name
    if plane == "XZ":
        ob.rotation_euler = (math.radians(90), 0, 0)
    elif plane == "YZ":
        ob.rotation_euler = (0, math.radians(90), 0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    if mat:
        ob.data.materials.append(mat)
    STATS["obj"] += 1
    return ob


def sphere(name, center, r, mat=None, squash=1.0, segs=16):
    """Expensive, and rarely what this art direction wants. A tree canopy is two
    or three chamfered BOXES, not a subdivided sphere - it costs a fifth as much
    and matches the village. Reach for this only for something genuinely round.
    """
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=center, segments=segs,
                                         ring_count=max(6, segs // 2))
    ob = bpy.context.object
    ob.name = name
    ob.scale = (1, 1, squash)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if mat:
        ob.data.materials.append(mat)
    STATS["obj"] += 1
    return ob


def cone(name, center, r1, r2, h, mat=None, verts=24):
    """Takes NO rotation. A cone on anything tilted is a party hat - rotate the
    object afterwards, or build it from a box."""
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2,
                                    depth=h, location=center)
    ob = bpy.context.object
    ob.name = name
    if mat:
        ob.data.materials.append(mat)
    STATS["obj"] += 1
    return ob


# -------------------------------------------------------------------- booleans
def join(objs):
    """Merge cutters so a whole hole pattern costs one boolean, not N."""
    objs = [o for o in objs if o is not None]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    return bpy.context.object


def boolean(target, cutter, op="DIFFERENCE"):
    """EXACT solver: FAST mangles the coplanar faces that plates and grills are
    made of. Applies immediately and removes the cutter.

    UNION silently repaints - it takes the material of whichever operand owns
    the face, so unify material slots before unioning or a part comes back
    wearing its neighbour colour.
    """
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = target
    target.select_set(True)
    mod = target.modifiers.new("Bool", "BOOLEAN")
    mod.operation = op
    mod.object = cutter
    mod.solver = "EXACT"
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)
    target.select_set(False)
    # Clean at the CUT, not only at the merge - it stops debris from one boolean
    # feeding into the next, and it reaches geometry that is never merged.
    clean_mesh(target)
    STATS["bool"] += 1
    return target


# ------------------------------------------------------------- cute assemblies
def blob(name, center, size, mat=None, tilt=(0.0, 0.0, 0.0)):
    """A chamfered mass at a slight angle - the building block of foliage,
    rocks, and anything that should not read as machined.

    Two or three of these in different greens is a tree canopy, for a fifth of
    the cost of a sphere.
    """
    return box(name, center, size, mat, rot=tilt)


def roof_pitch(width, height, overhang=0.12):
    """(run, rise, pitch_degrees, slope_length) for a gable of this size.

    One place computes it so the roof slabs and the gable-end cutters cannot
    disagree. They did, once, and the wall poked through its own roof.
    """
    run = width * 0.5 + overhang
    pitch = math.degrees(math.atan2(height, run))
    return run, height, pitch, math.hypot(run, height)


def gable_cutters(name, center, width, depth, height, overhang=0.12,
                  thickness=0.10, pad=0.60):
    """Two boxes filling the space ABOVE each roof slope. Returns both.

    Cut a tall wall box with these and what is left is the pentagon a gabled
    house actually is. Without it the wall stops at the eaves, the gable ends
    are open triangles, and you see straight through the building -- which is
    how the first hut rendered.

    The cutter lower face is placed on the slope UNDERSIDE, not its centreline,
    so the roof seats on the wall instead of sinking half its thickness in.
    """
    cx, cy, cz = center
    run, rise, pitch, slope = roof_pitch(width, height, overhang)
    rad = math.radians(pitch)
    out = []
    for sign, side in ((-1, "L"), (1, "R")):
        # The slab local +Z after a rot of (0, sign*pitch, 0): R_y maps
        # (0,0,1) to (sin t, 0, cos t).
        nx, nz = math.sin(sign * rad), math.cos(rad)
        off = pad * 0.5 - thickness * 0.5
        out.append(box("%s_Cut%s" % (name, side),
                       (cx + sign * run * 0.5 + nx * off, cy,
                        cz + rise * 0.5 + nz * off),
                       (slope * 1.6, depth * 3.0, pad),
                       None, rot=(0.0, sign * pitch, 0.0)))
    return out


def gable_roof(name, center, width, depth, height, mat, overhang=0.12,
               thickness=0.10):
    """Two sloped slabs meeting at a ridge. Returns both.

    The roof is the silhouette - at phone size a building is a roof and a colour
    - so this is where the triangle budget goes. `center` is the point the two
    slopes spring FROM (the eaves line), not the ridge.
    """
    cx, cy, cz = center
    run, rise, pitch, slope = roof_pitch(width, height, overhang)
    out = []
    for sign, side in ((-1, "L"), (1, "R")):
        # Rotated about Y. The sign is +sign, and getting it wrong is not
        # subtle: R_y maps +X toward +Z for a NEGATIVE angle, so -sign*pitch
        # tilts the right-hand slab UP as it goes right. Both slopes then fly
        # outward and upward and meet nowhere -- which is exactly how the first
        # hut rendered, a pair of wings over an open box.
        ob = box("%s_Slope%s" % (name, side),
                 (cx + sign * run * 0.5, cy, cz + rise * 0.5),
                 (slope, depth + overhang * 2.0, thickness),
                 mat, rot=(0.0, sign * pitch, 0.0))
        out.append(ob)
    return out
