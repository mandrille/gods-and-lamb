"""Ambient occlusion baked into a vertex colour attribute.

This is the whole contact-shading budget. Godot web export runs GL
Compatibility, which has no SSAO and no SSIL, so creases -- under an eave,
inside a doorway, where two canopy blobs meet -- get no separation at runtime
unless it is baked in here.

It is NOT the ground contact shadow. A DirectionalLight3D casts a real shadow
map in Compatibility, so an object sitting on the ground darkens the ground by
itself. What this adds is the small-scale darkening a shadow map is too coarse
to resolve, and it costs nothing at runtime on any device.

It also cannot know about neighbours: an asset is baked alone and then
instanced, so shading BETWEEN pieces is the engine job (village_builder tints
per instance from grid occupancy). Do not try to solve that here.

The transport to the engine is glTF COLOR_0, which the spec defines as
multiplying into base colour -- exactly the operation wanted, for free. Wiring
a Color Attribute node into each material makes the multiply visible in Blender
AND makes the glTF exporter emit COLOR_0 in its default MATERIAL mode.
"""
import math

import bpy
from mathutils import Vector

ATTR = "AO"

# Rays per vertex. 24 is enough for boxy geometry with few creases; the noise
# it leaves is far below what a flat-shaded face shows. Raise it for foliage.
SAMPLES = 24

# How far a ray looks for an occluder, in metres. Deliberately short: this is
# crease shading, not global illumination. At 2 m a hut roof darkens its own
# walls into mud.
DISTANCE = 0.55

# The darkest AO is allowed to get. Full black kills the palette, and the
# palette is doing the work that lighting cannot do here -- see AGENTS.md.
FLOOR = 0.55


def _hemisphere(n, normal):
    """`n` deterministic directions in the hemisphere around `normal`.

    Deterministic, not random: a build must be reproducible, and a bake that
    jitters between runs turns every diff into noise.

    Fibonacci spiral over the hemisphere, then rotated from +Z onto the normal.
    """
    out = []
    ga = math.pi * (3.0 - math.sqrt(5.0))
    up = Vector((0.0, 0.0, 1.0))
    normal = normal.normalized()
    if abs(normal.z) > 0.9999:
        rot = None if normal.z > 0 else "flip"
    else:
        rot = up.rotation_difference(normal)
    for i in range(n):
        z = (i + 0.5) / n            # 0..1, so never the horizon and never dead on
        r = math.sqrt(max(0.0, 1.0 - z * z))
        a = ga * i
        d = Vector((r * math.cos(a), r * math.sin(a), z))
        if rot == "flip":
            d = Vector((d.x, d.y, -d.z))
        elif rot is not None:
            d = rot @ d
        out.append(d)
    return out


def bake(objects, samples=SAMPLES, distance=DISTANCE, floor=FLOOR,
         epsilon=1e-3):
    """Write per-vertex occlusion into the ATTR colour layer. Returns stats.

    Rays are cast against the whole evaluated scene, so an asset occludes
    itself and is occluded by anything else present -- which is why the bake
    runs on the asset ALONE, with the look-render ground plane removed. Leave a
    60 m ground plane in and every downward-facing vertex reads fully occluded.
    """
    dg = bpy.context.evaluated_depsgraph_get()
    scene = bpy.context.scene
    lo, hi, tot, count = 1.0, 0.0, 0.0, 0

    for ob in objects:
        if getattr(ob, "type", None) != "MESH":
            continue
        me = ob.data
        if not len(me.vertices):
            continue
        attr = me.color_attributes.get(ATTR)
        if attr is None:
            attr = me.color_attributes.new(name=ATTR, type="FLOAT_COLOR",
                                           domain="POINT")
        # Workbench VERTEX mode, and the glTF exporter, both read the ACTIVE
        # colour attribute. A layer written but not made active renders as
        # uniform grey -- indistinguishable from a bake that did nothing.
        # The ACTIVE colour attribute is what the glTF exporter emits as
        # COLOR_0 and what Workbench VERTEX mode draws. Setting it inside a
        # bare try/except was a mistake the first time: when it silently failed
        # there was no way to tell a dead setting from a flat bake. It is a
        # hard failure now, and verify_written() reads the values back.
        try:
            me.color_attributes.active_color = attr
        except (AttributeError, TypeError) as exc:
            raise SystemExit("FAIL: %s - cannot make %r the active colour "
                             "attribute (%s). Without it the exporter emits no "
                             "COLOR_0 and the bake goes nowhere."
                             % (ob.name, ATTR, exc))
        mw = ob.matrix_world
        nm = mw.to_3x3().inverted().transposed()

        for i, v in enumerate(me.vertices):
            world = mw @ v.co
            normal = (nm @ v.normal).normalized()
            origin = world + normal * epsilon
            hits = 0
            for d in _hemisphere(samples, normal):
                hit, _loc, _n, _idx, _obj, _m = scene.ray_cast(
                    dg, origin, d, distance=distance)
                if hit:
                    hits += 1
            open_frac = 1.0 - hits / float(samples)
            val = floor + (1.0 - floor) * open_frac
            attr.data[i].color = (val, val, val, 1.0)
            lo = min(lo, val)
            hi = max(hi, val)
            tot += val
            count += 1

    mean = tot / count if count else 1.0
    return {"verts": count, "min": lo if count else 1.0,
            "max": hi if count else 1.0, "mean": mean}


def verify_written(objects, expect_min=0.999):
    """Read the bake back off the mesh. Returns (ok, report lines).

    A bake is invisible in a Workbench preview when the values are mild, and
    indistinguishable from a bake that did nothing at all. Reading the numbers
    back off the attribute is the only thing that tells the two apart, so the
    check is on the data and not on a picture.

    `expect_min` is the value below which real occlusion must have been found:
    if the darkest vertex in the whole asset is still essentially unoccluded,
    either the geometry is convex (fine, and worth saying) or the bake did
    nothing (not fine).
    """
    lines = []
    ok = True
    for ob in objects:
        if getattr(ob, "type", None) != "MESH":
            continue
        me = ob.data
        attr = me.color_attributes.get(ATTR)
        if attr is None:
            lines.append("%s: NO %s attribute" % (ob.name, ATTR))
            ok = False
            continue
        active = getattr(me.color_attributes, "active_color", None)
        active_name = getattr(active, "name", None)
        vals = [attr.data[i].color[0] for i in range(len(attr.data))]
        lo, hi = min(vals), max(vals)
        lines.append("%s: %s domain=%s type=%s n=%d range %.3f..%.3f active=%r"
                     % (ob.name, ATTR, attr.domain, attr.data_type, len(vals),
                        lo, hi, active_name))
        if active_name != ATTR:
            lines.append("  FAIL: %r is not the active colour attribute; the "
                         "glTF exporter will not emit it as COLOR_0." % ATTR)
            ok = False
        if lo >= expect_min:
            lines.append("  NOTE: nothing occluded anything. Correct for a "
                         "convex shape, and meaningless as a test of the bake.")
    return ok, lines


def ensure_neutral(objects, layer=ATTR):
    """Give every mesh with no ATTR layer a flat white one. Returns the count.

    Once wire_all() has run, EVERY material multiplies by the ATTR colour --
    including on meshes that were never baked. A Vertex Color node pointing at
    a layer the mesh does not have does not fall back to white, it evaluates to
    BLACK, and the multiply annihilates the albedo. A lit hut on a ground plane
    came back with the hut correct and the ground a black void: frame luma
    0.255 against 0.582, which reads exactly like a lighting bug and is a
    missing attribute.

    Run it over the whole scene immediately before rendering. This is the guard
    version of "remember to bake the ground too": a mesh that misses the bake
    renders unshaded instead of invisible, and verify_written() on the meshes
    that WERE baked still catches a bake that did nothing.
    """
    n = 0
    for ob in objects:
        if getattr(ob, "type", None) != "MESH" or not len(ob.data.vertices):
            continue
        me = ob.data
        if me.color_attributes.get(layer) is not None:
            continue
        attr = me.color_attributes.new(name=layer, type="FLOAT_COLOR",
                                       domain="POINT")
        for i in range(len(attr.data)):
            attr.data[i].color = (1.0, 1.0, 1.0, 1.0)
        me.color_attributes.active_color = attr
        n += 1
    return n


def wire_vertex_colour(mat, layer=ATTR):
    """Multiply the ATTR colour into a material base colour.

    Two jobs at once. It makes the bake visible in Blender, and it makes the
    glTF exporter emit COLOR_0 in its default MATERIAL mode -- the exporter
    only exports a colour attribute a material actually reads. glTF then
    defines COLOR_0 as multiplying into base colour, and Godot glTF import
    turns that into vertex_color_use_as_albedo, so the same multiply survives
    all the way to the Compatibility renderer with nothing to configure.

    Idempotent: a material already wired is left alone.
    """
    if not mat.use_nodes or not mat.node_tree:
        return False
    nt = mat.node_tree
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        return False
    base = bsdf.inputs["Base Color"]
    if base.is_linked:
        return False                       # already wired, or hand-authored

    col = nt.nodes.new("ShaderNodeVertexColor")
    col.layer_name = layer
    col.location = (bsdf.location.x - 520, bsdf.location.y - 120)

    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.location = (bsdf.location.x - 300, bsdf.location.y - 60)
    # Factor 1.0: the AO is already scaled by `floor`, so attenuating it twice
    # would make the bake quietly weaker than the number it reports.
    mix.inputs["Factor"].default_value = 1.0

    rgba = list(base.default_value)
    # Blender 4.x Mix node exposes several same-named sockets for its data
    # types; index into the RGBA pair rather than trusting a name lookup.
    sockets = [s for s in mix.inputs if s.type == "RGBA"]
    sockets[0].default_value = (rgba[0], rgba[1], rgba[2], 1.0)
    nt.links.new(col.outputs["Color"], sockets[1])
    out = next(s for s in mix.outputs if s.type == "RGBA")
    nt.links.new(out, base)
    return True


def wire_all(layer=ATTR):
    """Wire every material in the file. Returns how many were changed."""
    return sum(1 for m in bpy.data.materials if wire_vertex_colour(m, layer))
