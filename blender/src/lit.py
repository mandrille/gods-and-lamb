r"""The GAME light rig, rendered in EEVEE. The other half of `shot.py`.

`shot.py` is Workbench: a fixed studio rig that lights whatever is in shot from
wherever the camera is, with no sky and no real shadow. That is exactly right
for the cheap `-- look` shape loop and nothing here changes it. But it means a
Workbench render cannot answer "does this art work under the light the game
actually has", because Workbench's light is not that light and never will be.

This module is that second question. Its whole job is to PREDICT GODOT, so
every choice is constrained by what Godot's GL Compatibility renderer can do
on a web export:

- ONE `SUN`, warm, soft-shadowed  ->  `DirectionalLight3D`
- a four-stop gradient sky, cool  ->  `ProceduralSkyMaterial` on a `Sky`
- `view_transform = "Standard"`   ->  Compatibility does no tonemapping
- NO raytracing, NO fast GI, NO volumetrics. Compatibility has no SSR, no
  SSIL, no screen-space AO and no volumetric fog. Turning any of them on would
  make this render prettier and make it a LIE, which is worse than useless:
  the entire point of the picture is that it tells you what ships.

The contact shading that replaces the effects we do not have is the vertex
colour AO -- see aobake.py. `bake_isolated()` here is what finally wires it in.

Camera framing is `shot.solve_camera()`, unchanged and not reimplemented. Read
its docstring before you are tempted: four other fits were tried and one of
them put the camera twenty million metres from the subject.
"""
import math
import os
import time

import bpy
from mathutils import Vector

import aobake
import shot

# ------------------------------------------------------------------- the rig
#
# Sun energy is pi, and that is not a tuning number: Godot's Compatibility
# renderer computes diffuse as `albedo * NdotL * light_energy`, while Blender
# computes `albedo * NdotL * energy / pi`. So energy = pi in Blender is
# light_energy = 1.0 in Godot, exactly. Change this only if the Godot side
# changes with it, or the render stops predicting anything.
SUN_ENERGY = math.pi

# Warm, but only just. A strongly tinted key drags every hue toward orange and
# the palette is doing the separation work here (AGENTS.md sec. 5), so the light
# must not start mixing the hues back together.
SUN_COLOUR = (1.00, 0.945, 0.855)

# The direction the light TRAVELS, world space. Elevation ~46 deg, arriving
# from the -X/-Y quadrant -- which is where every look camera sits, so the key
# comes over the camera's shoulder and slightly to the right on all three of
# the island angles. Fixed in world space, NOT camera-relative: the game's sun
# does not follow the player's camera and neither does this one.
SUN_DIR = (0.55, 0.42, -0.72)

# Angular diameter of the sun disc, degrees. The real sun is 0.53; this is
# ~7x that because a soft shadow edge is the look, and it maps to
# DirectionalLight3D.light_angular_distance in Godot.
SUN_ANGLE_DEG = 3.6

# Sky gradient, LINEAR values (Blender node colours are linear; Godot's
# ProceduralSkyMaterial takes sRGB, so these are not the numbers to paste over
# there -- run them through kit.linear_to_srgb). Four stops, matching Godot's
# sky_top / sky_horizon / ground_horizon / ground_bottom, at a Fac where 1.0 is
# the zenith.
#
# The lower hemisphere is BLUE, not ground. The island floats and the play
# camera looks DOWN at it, so most of the frame is below the horizon -- which
# means the "ground" half of a physical sky is not scenery here, it is the
# backdrop, and it is most of the picture. The first version put a neutral grey
# bounce down there on the physical argument and the island came back sitting
# on a sheet of dishwater.
#
# The horizon haze is a soft peak rather than Godot's hard sky/ground seam, for
# the same reason: a crisp horizon line behind a floating island reads as a bug.
SKY_STOPS = (
    (0.00, (0.016, 0.062, 0.170)),   # nadir: deep blue
    (0.35, (0.060, 0.185, 0.395)),   # below the horizon
    (0.50, (0.205, 0.425, 0.700)),   # horizon haze, the light band
    (0.62, (0.100, 0.310, 0.635)),
    (1.00, (0.035, 0.170, 0.495)),   # zenith blue
)

# Two strengths, not one, because GODOT HAS TWO. `background_energy_multiplier`
# scales the sky you SEE and `ambient_light_energy` scales the fill it THROWS,
# and they are independent knobs over there. Blender ties them together on a
# single Background node, so a Light Path "Is Camera Ray" switch separates them
# back out -- camera rays get BG, the light probe gets AMBIENT.
#
# Do not merge these back into one number to simplify the node tree. Tied
# together, the only sky bright enough to be a nice background is also bright
# enough to flatten every shadow in the scene, which is precisely the washed-out
# first render this pair was added to fix.
SKY_BG_STRENGTH = 1.05
SKY_AMBIENT_STRENGTH = 0.36

# Anti-aliasing / shadow sampling. 32 is the knee: 16 leaves visible stipple on
# the soft shadow edge, 64 costs nearly double for no difference I could see.
SAMPLES = 32


def _eevee_engine():
    """The EEVEE identifier for THIS Blender. Never hardcode it -- it is
    BLENDER_EEVEE_NEXT on some 4.x and BLENDER_EEVEE again on 5.x (gotcha #8).
    """
    ids = [i.identifier for i in
           bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    for i in ids:
        if "EEVEE" in i:
            return i
    raise SystemExit("FAIL: no EEVEE engine in this Blender (have: %s)"
                     % ", ".join(ids))


def build_sky(name="LitSky"):
    """A four-stop vertical gradient world. Returns the World.

    The gradient is driven by the Z of `Geometry.Incoming`, which points from
    the shading point back TOWARD the camera -- so a ray heading for the zenith
    arrives with Incoming.Z = -1, not +1. Hence the inverted Map Range. This
    was measured, not assumed: a probe render with a red-to-blue ramp came back
    with blue at the BOTTOM of the frame on the obvious wiring.
    """
    w = bpy.data.worlds.new(name)
    if w.node_tree is None:                      # 5.x makes it on demand
        w.use_nodes = True
    nt = w.node_tree
    bg = next(n for n in nt.nodes if n.type == "BACKGROUND")

    geo = nt.nodes.new("ShaderNodeNewGeometry")
    geo.location = (bg.location.x - 900, bg.location.y)
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    sep.location = (bg.location.x - 700, bg.location.y)
    nt.links.new(geo.outputs["Incoming"], sep.inputs[0])

    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.location = (bg.location.x - 520, bg.location.y)
    mr.inputs["From Min"].default_value = 1.0    # inverted: see the docstring
    mr.inputs["From Max"].default_value = -1.0
    nt.links.new(sep.outputs["Z"], mr.inputs["Value"])

    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.location = (bg.location.x - 320, bg.location.y)
    cr = ramp.color_ramp
    # A new ramp ships with two elements; reuse them and add the rest, because
    # elements.remove() refuses to leave fewer than one and the index shuffles.
    cr.elements[0].position, cr.elements[0].color = SKY_STOPS[0][0], (*SKY_STOPS[0][1], 1.0)
    cr.elements[1].position, cr.elements[1].color = SKY_STOPS[-1][0], (*SKY_STOPS[-1][1], 1.0)
    for pos, rgb in SKY_STOPS[1:-1]:
        el = cr.elements.new(pos)
        el.color = (*rgb, 1.0)
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])

    # Background brightness and ambient fill, split -- see SKY_BG_STRENGTH.
    lp = nt.nodes.new("ShaderNodeLightPath")
    lp.location = (bg.location.x - 520, bg.location.y - 320)
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "FLOAT"
    mix.location = (bg.location.x - 200, bg.location.y - 240)
    nt.links.new(lp.outputs["Is Camera Ray"], mix.inputs["Factor"])
    # Blender 4.x+ Mix exposes same-named sockets per data type; index into the
    # VALUE pair rather than trusting a name lookup (same trap as aobake).
    fl = [s for s in mix.inputs if s.type == "VALUE" and s.name != "Factor"]
    fl[0].default_value = SKY_AMBIENT_STRENGTH     # probe rays
    fl[1].default_value = SKY_BG_STRENGTH          # camera rays
    out = next(s for s in mix.outputs if s.type == "VALUE")
    nt.links.new(out, bg.inputs["Strength"])
    return w


def ensure_rig(sc):
    """Put the game rig on the scene, once. Returns (sun object, world).

    Idempotent by name so `-- scene` can call it before each of three renders
    without stacking three suns on top of each other -- which would silently
    triple the key and look like a palette that had gone chalky.
    """
    sc.render.engine = _eevee_engine()
    # Standard, never AgX (gotcha #5). AgX desaturates, and on this palette the
    # saturation IS the art direction -- see the lamb-look brief.
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = 0.0
    sc.view_settings.gamma = 1.0
    sc.render.film_transparent = False           # the sky IS the background

    ee = sc.eevee
    ee.taa_render_samples = SAMPLES
    ee.use_shadows = True
    # Everything Godot's GL Compatibility renderer does not have. Each of these
    # would improve the picture and destroy its only value.
    ee.use_raytracing = False                    # no SSR, no screen-space GI
    ee.use_fast_gi = False                       # EEVEE's horizon-scan AO

    if sc.world is None or sc.world.name.split(".")[0] != "LitSky":
        sc.world = build_sky()
    # Volumetrics need a volume shader to do anything and we never make one, so
    # this is checked rather than assumed: a stray volume on the world would fog
    # the scene, read as a deliberate lighting choice, and be unshippable.
    w = sc.world
    wout = w.node_tree and next((n for n in w.node_tree.nodes
                                 if n.type == "OUTPUT_WORLD"), None)
    if wout is not None and wout.inputs["Volume"].is_linked:
        raise SystemExit("FAIL: world %r has a volume shader. Godot web has no "
                         "volumetrics; this render would be a lie." % w.name)

    sun = bpy.data.objects.get("LitSun")
    if sun is None:
        d = bpy.data.lights.new("LitSun", type="SUN")
        sun = bpy.data.objects.new("LitSun", d)
        sc.collection.objects.link(sun)
    d = sun.data
    d.energy = SUN_ENERGY
    d.color = SUN_COLOUR
    d.angle = math.radians(SUN_ANGLE_DEG)
    d.use_shadow = True
    d.use_shadow_jitter = True
    # The cascade range is a shadow-map budget, not a distance limit: 200 m of
    # cascade over a 12 m island spends the whole texture on empty air and the
    # contact edge under a hut goes to mush.
    d.shadow_cascade_max_distance = 40.0
    d.shadow_filter_radius = 1.6
    # A SUN's location is irrelevant; only its rotation is. Aim -Z down SUN_DIR.
    sun.location = (0.0, 0.0, 20.0)
    sun.rotation_euler = Vector(SUN_DIR).normalized().to_track_quat(
        "-Z", "Y").to_euler()
    return sun, sc.world


# --------------------------------------------------------------- the AO bake
def bake_isolated(objects, verbose=True):
    """Bake vertex AO once per unique MESH, each one alone, then wire it in.

    Two things this has to get right that a naive pass does not.

    ONE: rays are cast against the whole evaluated scene, so a bake run in
    place measures the neighbours. That is wrong twice over -- the asset ships
    as a `.glb` and is instanced into arbitrary neighbourhoods, and shading
    BETWEEN pieces is the engine's job (village_builder tints per instance from
    grid occupancy). So every object except the one being baked is hidden.

    TWO: the island instances share mesh data, so N objects can be one mesh.
    Baking per object would recompute the same attribute N times and keep
    whichever instance happened to go last -- one tile's neighbourhood, applied
    to all ninety. One bake per unique mesh datablock is both correct and Nx
    cheaper.

    Callers must pass MERGED geometry (gotcha #61). Before the merge a wall is
    eight corners and a crease under an eave gets no sample at all.
    """
    meshes = {}
    for ob in objects:
        if getattr(ob, "type", None) == "MESH" and len(ob.data.vertices):
            meshes.setdefault(ob.data.name, ob)
    if not meshes:
        return {"meshes": 0, "verts": 0, "min": 1.0, "mean": 1.0, "max": 1.0}

    was = {ob.name: ob.hide_viewport for ob in bpy.data.objects}
    for ob in bpy.data.objects:
        ob.hide_viewport = True

    t0 = time.time()
    total, lo, hi, wsum = 0, 1.0, 0.0, 0.0
    reps = []
    try:
        for name in sorted(meshes):
            rep = meshes[name]
            rep.hide_viewport = False
            bpy.context.view_layer.update()
            st = aobake.bake([rep])
            rep.hide_viewport = True
            reps.append(rep)
            total += st["verts"]
            lo = min(lo, st["min"])
            hi = max(hi, st["max"])
            wsum += st["mean"] * st["verts"]
    finally:
        for ob in bpy.data.objects:
            ob.hide_viewport = was.get(ob.name, False)
        bpy.context.view_layer.update()

    ok, lines = aobake.verify_written(reps)
    if verbose:
        for line in lines:
            print("  " + line)
    if not ok:
        raise SystemExit("FAIL: the AO bake did not survive on the mesh. See "
                         "the lines above.")

    wired = aobake.wire_all()
    stats = {"meshes": len(meshes), "verts": total, "min": lo,
             "max": hi, "mean": (wsum / total) if total else 1.0,
             "wired": wired, "secs": time.time() - t0}
    if verbose:
        print("ao bake: %d mesh(es), %d verts, min %.3f mean %.3f max %.3f, "
              "%d material(s) wired, %.1f s"
              % (stats["meshes"], stats["verts"], stats["min"], stats["mean"],
                 stats["max"], wired, stats["secs"]))
    return stats


# ----------------------------------------------------------------- rendering
def ground(size=240.0):
    """A grass plane for a single-asset lit shot. Returns the object.

    Not the same scaffolding as the Workbench `_ground`, and deliberately so.
    That one is a neutral grey card at 60 m, which is the right choice when the
    question is a SHAPE: grey adds no hue of its own and the plane edge is out
    of the way. Here the question is the LIGHT, and the two things a lit render
    has to show -- what colour the sun's shadow actually is, and whether an
    asset separates from the ground it will stand on -- both need the ground to
    be the ground. It reaches the horizon so the sky's lower half never shows
    up as a grey band behind the subject.

    kit.M["grass"], never a local colour: a ground built out of a one-off
    material is a ground nobody can retune with the rest of the palette.
    """
    import kit
    return kit.box("LIT_Ground", (0, 0, -0.06), (size, size, 0.12),
                   kit.M["grass"])


def render(path, subjects, res=(1200, 800), fill=0.90,
           dirv=(-0.85, -1.0, 0.42), min_span=0.30):
    """Frame `subjects` and render them under the game rig. Metrics dict.

    Deliberately a near-clone of `shot.render()` rather than a flag on it. The
    two paths share the camera solve, the bounds and the photometrics -- the
    parts that were expensive to get right -- and differ in the engine, the
    lighting and the default resolution, which is all of what this module is
    for. Folding them together would put an `if lit:` through the middle of the
    cheap loop that everything else depends on.

    Resolution defaults lower than Workbench's 1400x1000 on purpose: EEVEE is
    the slow path and the numbers are in AGENTS.md.
    """
    sc = bpy.context.scene
    lo, hi = shot.world_bounds(subjects)
    centre = (lo + hi) / 2
    corners = [ob.matrix_world @ Vector(c) for ob in subjects
               if getattr(ob, "type", None) == "MESH" for c in ob.bound_box]
    if not corners:
        raise SystemExit("FAIL: nothing to render at %s - the subject list has "
                         "no mesh objects." % os.path.basename(path))
    direction = Vector(dirv).normalized()

    # Resolution BEFORE the solve. world_to_camera_view normalises by the
    # render aspect, so solving first frames the shot for whatever aspect the
    # previous render left behind.
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100

    ensure_rig(sc)
    # Anything in the scene that missed the bake -- a ground plane, a prop
    # added afterwards -- would otherwise multiply its albedo by a black vertex
    # colour and vanish. See aobake.ensure_neutral().
    filled = aobake.ensure_neutral(sc.objects)
    if filled:
        print("  ao neutral fill: %d mesh(es) had no bake" % filled)

    cam_d = bpy.data.cameras.new("LitCam")
    cam = bpy.data.objects.new("LitCam", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam

    chosen, d, span, box, tried = None, 0.0, 0.0, None, []
    for lens in shot.LENSES:
        cam_d.lens = lens
        d, span, box = shot.solve_camera(sc, cam, corners, centre, direction,
                                         fill)
        framed = (box is not None and box[0] > -0.01 and box[1] < 1.01
                  and box[2] > -0.01 and box[3] < 1.01 and span > min_span)
        tried.append("%.0fmm at %.2f m fill %.2f%s"
                     % (lens, d, span, "" if framed else " NOT FRAMED"))
        if framed:
            chosen = lens
            break
    if chosen is None:
        raise SystemExit(
            "FAIL: %s cannot be framed on any lens down to %.0f mm "
            "(subject radius %.2f m).\n  %s"
            % (os.path.basename(path), shot.LENSES[-1], (hi - lo).length / 2,
               "\n  ".join(tried)))

    os.makedirs(os.path.dirname(path), exist_ok=True)
    sc.render.filepath = path
    sc.render.image_settings.file_format = "PNG"
    t0 = time.time()
    bpy.ops.render.render(write_still=True)
    secs = time.time() - t0

    bpy.data.objects.remove(cam, do_unlink=True)
    bpy.data.cameras.remove(cam_d)

    # Kept from the Workbench path, and it matters MORE here: a rig with the
    # sun aimed at nothing renders a plausible sky over a black subject, and in
    # a log that is indistinguishable from a render that worked.
    mean, sd, darkfrac = shot.photometrics(path)
    out = {"lens": chosen, "distance": d, "span": span, "luma": mean,
           "luma_sd": sd, "dark": darkfrac, "secs": secs}
    print("  lit  %-28s %2.0fmm  %5.2f m  fill %.2f  luma %.3f sd %.3f  "
          "dark %.0f%%  %5.1f s%s"
          % (os.path.basename(path), chosen, d, span, mean, sd, darkfrac * 100,
             secs, "   ** BLANK **" if sd < 0.02 else ""))
    return out
