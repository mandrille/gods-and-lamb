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


def _base_colour(mat):
    """The Principled base colour, linear, or white if there is no BSDF."""
    if not mat or not mat.use_nodes or not mat.node_tree:
        return (1.0, 1.0, 1.0)
    bsdf = next((n for n in mat.node_tree.nodes
                 if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        return (1.0, 1.0, 1.0)
    base = bsdf.inputs["Base Color"]
    if base.is_linked:
        raise SystemExit("FAIL: %s already has a linked Base Color, so its "
                         "albedo is not a constant this can fold. Run the fold "
                         "BEFORE wire_vertex_colour()." % mat.name)
    v = base.default_value
    return (v[0], v[1], v[2])


def _encode(albedo_linear, ao_stored):
    """One channel of a folded vertex colour, in the space Godot will read.

    NOT a plain multiply, and the difference is visible rather than academic.
    Godot's Compatibility renderer does not treat COLOR_0 and `albedo_color`
    alike: the material factor is used as linear, while the vertex colour goes
    through an sRGB->linear conversion on the way into the shader. Measured on
    the villager, a plain multiply came back at mean rgb 0.176 0.093 0.056
    against the unfolded asset's 0.280 0.243 0.170 -- far too dark and too
    saturated, which is the signature of a gamma applied once too often.

    So the fold has to hand Godot a value that survives that conversion. The
    unfolded pipeline renders `albedo x srgb_to_linear(AO)`; this stores the
    inverse-transformed product so the folded mesh renders the same thing.

    Written as one function with the arithmetic in it, rather than as a
    correction factor applied somewhere else, because the next person to touch
    this needs to see WHICH transform is being undone.
    """
    import kit
    want = albedo_linear * kit.srgb(ao_stored, ao_stored,
                                              ao_stored)[0]
    return min(1.0, max(0.0, kit.linear_to_srgb(want, want, want)[0]))


def fold_to_vertex_colour(objects, layer=ATTR, name="Folded"):
    """Collapse every material slot into ONE, carrying albedo in COLOR_0.

    WHY THIS EXISTS, measured rather than assumed. Every asset in this project
    is one mesh with a material per flat colour, which on the 27 static assets
    costs essentially nothing -- the 353-prop, 7338-tile Vale draws in 1.05 ms.
    On a SKINNED mesh it costs 8x, because GL Compatibility runs a skinning
    update per surface per frame:

        villager    8 surfaces   516 tris    0.132 ms/frame each
        folded      1 surface    516 tris    0.0148 ms/frame each

    That single line was 88.8% of the entire cost of a follower, and it is
    dispatch overhead rather than vertex work -- which is why the triangle cap
    is the wrong lever here and why cutting the MATERIAL count without cutting
    the SURFACE count buys nothing at all (measured: 49.6 ms vs 52.8 ms).

    The transport already exists: the AO bake writes COLOR_0 and the glTF spec
    defines it as multiplying into base colour, so multiplying the albedo into
    the same channel and leaving one white material behind is the same product
    arriving by a cheaper road.

    POINT domain, so this is only lossless if no vertex is shared between two
    materials. That holds here because parts are join()ed rather than welded,
    but it is CHECKED rather than trusted -- a silent failure would tint a
    seam and nothing downstream would notice.
    """
    import bpy
    out = []
    for ob in objects:
        if getattr(ob, "type", None) != "MESH":
            continue
        me = ob.data
        mats = [s.material for s in ob.material_slots]
        if len(mats) <= 1:
            continue
        attr = me.color_attributes.get(layer)
        if attr is None:
            raise SystemExit("FAIL: %s has no %r attribute. The fold multiplies "
                             "albedo INTO the bake, so bake() must run first."
                             % (ob.name, layer))
        if attr.domain != "POINT":
            raise SystemExit("FAIL: %s has %r on the %s domain; this fold "
                             "assumes POINT." % (ob.name, layer, attr.domain))

        # One material per vertex, or the fold is lossy. Report the worst case
        # with a count, because "some seam is wrong" is not actionable.
        vmat = [-1] * len(me.vertices)
        clashes = 0
        for poly in me.polygons:
            for vi in poly.vertices:
                if vmat[vi] == -1:
                    vmat[vi] = poly.material_index
                elif vmat[vi] != poly.material_index:
                    clashes += 1
        if clashes:
            raise SystemExit(
                "FAIL: %s has %d vertex/material clashes -- a vertex is shared "
                "between two materials, so a POINT-domain fold would average "
                "two albedos into one seam. Move %r to the CORNER domain."
                % (ob.name, clashes, layer))

        albedo = [_base_colour(m) for m in mats]
        for i in range(len(me.vertices)):
            mi = vmat[i]
            if mi < 0 or mi >= len(albedo):
                continue
            ao = attr.data[i].color
            a = albedo[mi]
            attr.data[i].color = tuple(_encode(a[c], ao[c]) for c in (0, 1, 2))                                  + (1.0,)

        # Roughness and metallic are NOT per-vertex, so one value has to win.
        # Report the spread rather than picking quietly: a folded asset whose
        # materials disagreed about roughness has genuinely lost something, and
        # the build should say so out loud.
        roughs, metals = [], []
        for m in mats:
            if m and m.use_nodes and m.node_tree:
                b = next((n for n in m.node_tree.nodes
                          if n.type == "BSDF_PRINCIPLED"), None)
                if b is not None:
                    roughs.append(round(b.inputs["Roughness"].default_value, 4))
                    metals.append(round(b.inputs["Metallic"].default_value, 4))
        # Weight by how much of the mesh actually wears each material, not by
        # how many slots mention it. The mode over slots picked 0.70 because
        # five materials happened to say so, while most of the villager's
        # VERTICES were on the smoother ones -- and the folded asset came back
        # a flat 11% darker than the original with no hue shift, which is what
        # a specular change looks like when a gamma error would have skewed the
        # channels apart.
        weight = [0] * len(mats)
        for mi in vmat:
            if 0 <= mi < len(weight):
                weight[mi] += 1
        total_w = float(sum(weight)) or 1.0
        rough = (sum(r * w for r, w in zip(roughs, weight)) / total_w
                 if roughs else 0.42)
        metal = (sum(m * w for m, w in zip(metals, weight)) / total_w
                 if metals else 0.0)
        if len(set(roughs)) > 1 or len(set(metals)) > 1:
            print("  fold %s: roughness %s -> %.3f (vertex-weighted), "
                  "metallic %s -> %.3f"
                  % (ob.name, sorted(set(roughs)), rough,
                     sorted(set(metals)), metal))

        folded = bpy.data.materials.new("%s_%s" % (ob.name, name))
        folded.use_nodes = True
        b = folded.node_tree.nodes["Principled BSDF"]
        # WHITE. The colour now lives in COLOR_0; a tinted base would multiply
        # it a second time.
        b.inputs["Base Color"].default_value = (1.0, 1.0, 1.0, 1.0)
        b.inputs["Roughness"].default_value = rough
        b.inputs["Metallic"].default_value = metal

        ob.data.materials.clear()
        ob.data.materials.append(folded)
        for poly in me.polygons:
            poly.material_index = 0
        out.append((ob.name, len(mats), 1))
    return out


def wire_all(layer=ATTR, report=True):
    """Wire every material in the file. Returns how many were changed.

    Reports the ones it SKIPPED as well as the ones it wired. wire_vertex_colour
    declines silently on a material whose Base Color is already linked, and a
    silent decline is indistinguishable from success from here -- the asset
    still exports, still has COLOR_0 on the mesh, and simply never multiplies
    it, which is a look bug three steps downstream of its cause.
    """
    wired, skipped = [], []
    for m in bpy.data.materials:
        (wired if wire_vertex_colour(m, layer) else skipped).append(m.name)
    if report and skipped:
        print("  wired %d material(s); SKIPPED %d: %s"
              % (len(wired), len(skipped), ", ".join(sorted(skipped))))
    return len(wired)
