"""Framing and rendering. The camera solves its own distance; nothing guesses.

Ported from the parent project _setshot.py, minus the room: assets here are
shot on open ground, so the "is the camera inside the walls" test is gone and
the lens loop only has to satisfy "is everything actually in the frame".

Workbench is the engine, deliberately. It is about a second a frame against
40-70 for Cycles, and it lights the subject with its own studio rig -- so a
shot cannot come back as a brightly lit backdrop with the subject in darkness
in front of it, which is what EEVEE produced in the parent project at
luma_std 0.09 with every frame-wide metric reading green.
"""
import math
import os

import bpy
from mathutils import Vector

# Widest first is wrong: a long lens is the nicer picture, so the list is tried
# from the tightest and stops at the first that frames the subject.
LENSES = (35.0, 28.0, 24.0, 20.0, 18.0, 16.0)


def world_bounds(objects):
    """(lo, hi) Vectors over the bound boxes of a list of objects."""
    lo = Vector((1e18, 1e18, 1e18))
    hi = Vector((-1e18, -1e18, -1e18))
    for ob in objects:
        if getattr(ob, "type", None) != "MESH":
            continue
        for c in ob.bound_box:
            w = ob.matrix_world @ Vector(c)
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
    return lo, hi


def solve_camera(sc, cam, corners, centre, direction, fill):
    """Fit the distance by BISECTION on the projected deviation from centre.

    With the aim point pinned to `centre` and the view direction fixed, the
    camera basis never changes -- only how far back it sits. Each corner
    sideways offset u, up offset v and depth offset f along the view axis are
    therefore CONSTANTS, and its projected deviation from the frame centre is

        span = |u| / ((d + f) * tan(hfov/2))

    which is strictly decreasing in d. A strictly monotone function is the one
    thing a solver cannot oscillate on, so this bisects rather than iterating.

    Four other fits were tried in the parent project and each failed by
    shipping a bad picture rather than an error: fitting the projected EXTENT
    reported a satisfied 0.95 for a subject shoved into a corner with most of
    it off-frame; correcting the aim as well made two corrections interact and
    diverged to a camera twenty million metres away.

    Blender angle_x/angle_y already account for sensor_fit and the render
    aspect, which is why the resolution must be set BEFORE this is called.

    Returns (distance, span, (x0, x1, y0, y1)).
    """
    from bpy_extras.object_utils import world_to_camera_view

    r = max((c - centre).length for c in corners)

    def place(d):
        cam.location = centre + direction * d
        cam.rotation_euler = (centre - cam.location).to_track_quat(
            "-Z", "Y").to_euler()
        bpy.context.view_layer.update()

    def project():
        us = [world_to_camera_view(sc, cam, c) for c in corners]
        # A point behind the lens comes back with nonsense x/y, which reads as
        # an enormous extent and shoves the camera away.
        if any(p.z <= 0.05 for p in us):
            return None
        return (min(p.x for p in us), max(p.x for p in us),
                min(p.y for p in us), max(p.y for p in us))

    # The basis, read once at a distance certainly clear of everything.
    place(max(r * 4.0, 1.0))
    basis = cam.matrix_world.to_3x3()
    right, up = basis.col[0].normalized(), basis.col[1].normalized()
    fwd = -basis.col[2].normalized()
    th = math.tan(cam.data.angle_x / 2.0)
    tv = math.tan(cam.data.angle_y / 2.0)

    pts = [((c - centre).dot(right), (c - centre).dot(up), (c - centre).dot(fwd))
           for c in corners]

    def span_at(d):
        worst = 0.0
        for u, v, f in pts:
            w = d + f
            if w <= 0.05:
                return 1e9
            worst = max(worst, abs(u) / (w * th), abs(v) / (w * tv))
        return worst

    # Bracket, then bisect. lo starts just clear of the nearest corner so no
    # point is ever behind the lens inside the bracket.
    lo = max(0.05, -min(f for _u, _v, f in pts) + 0.05)
    hi = max(lo * 2.0, r * 8.0 + 1.0)
    for _ in range(60):
        if span_at(hi) <= fill:
            break
        hi *= 1.6
    for _ in range(80):
        mid = (lo + hi) / 2.0
        if span_at(mid) > fill:
            lo = mid
        else:
            hi = mid
    d = hi

    place(d)
    box = project()
    # Belt to the braces: back off until nothing overflows. This only ever
    # INCREASES d, so it terminates and cannot oscillate.
    for _ in range(8):
        if box is None:
            d *= 1.35
        else:
            over = max(0.0, -box[0], box[1] - 1.0, -box[2], box[3] - 1.0)
            if over <= 0.004:
                break
            d *= 1.0 + 1.5 * over + 0.02
        place(d)
        box = project()

    span = max(box[1] - box[0], box[3] - box[2]) if box else 99.0
    return d, span, box


def sync_viewport_colours():
    """Copy each material Principled base colour into its viewport colour.

    Workbench shades from `material.diffuse_color`, NOT from the Principled
    node that kit.flat() and kit.emit() write -- they set the node input and
    nothing else. So a Workbench render of a fully coloured scene comes back
    uniform grey, which looks like a lighting problem and is actually a
    completely different colour channel. It cost the first render in this
    project: a green-and-brown grass tile arrived as a white box.

    Done here, at render time, rather than in kit.flat(): this is a display
    property and it changes nothing about how the asset renders in the engine
    or exports.
    """
    n = 0
    for mat in bpy.data.materials:
        if not mat.use_nodes or not mat.node_tree:
            continue
        bsdf = next((nd for nd in mat.node_tree.nodes
                     if nd.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None:
            continue
        rgba = list(bsdf.inputs["Base Color"].default_value)
        strength = bsdf.inputs.get("Emission Strength")
        if strength is not None and strength.default_value > 0.5:
            # An emitter base colour is not what it looks like -- take the
            # colour it actually throws, or a lit window reads as a dead lump.
            rgba = list(bsdf.inputs["Emission Color"].default_value)
        mat.diffuse_color = (rgba[0], rgba[1], rgba[2], 1.0)
        n += 1
    return n


def use_workbench(sc, direction=None, color_type="MATERIAL"):
    """Viewport shading, headless, lit from where the CAMERA is.

    `scene.display.light_direction` is the whole of it. Leaving it alone is why
    the parent project roof kit first came back as a black silhouette:
    Workbench keys from above by default, every surface of a ceiling faces
    down, and none of them caught a photon. Pointing the light along the view
    vector lights whatever is actually in shot, with a lateral and a small
    upward term mixed in so it still has form rather than reading like a
    headlight.

    Attribute by attribute inside a try, because these properties move between
    Blender versions and a look render is not worth failing a build over. That
    leniency has a cost -- a setting that quietly stops existing goes unnoticed
    -- so the values that matter are read back and reported by render().
    """
    sc.render.engine = "BLENDER_WORKBENCH"
    # Standard, never AgX. AgX desaturates, and this palette is the point.
    sc.view_settings.view_transform = "Standard"
    if direction is not None:
        d = Vector(direction).normalized()
        lat = Vector((-d.y, d.x, 0.0))
        lat = lat.normalized() if lat.length > 1e-6 else Vector((1.0, 0.0, 0.0))
        try:
            sc.display.light_direction = (d * 0.80 + lat * 0.40
                                          + Vector((0.0, 0.0, 0.25))).normalized()
            sc.display.shading.use_world_space_lighting = True
        except (AttributeError, TypeError):
            pass
    for holder, attr, value in ((sc.display, "render_aa", "8"),
                                (sc.display.shading, "light", "STUDIO"),
                                (sc.display.shading, "color_type", color_type),
                                (sc.display.shading, "show_cavity", True),
                                (sc.display.shading, "cavity_type", "BOTH"),
                                (sc.display.shading, "show_shadows", True),
                                (sc.display.shading, "shadow_intensity", 0.22),
                                (sc.display.shading, "studiolight_intensity", 2.1),
                                (sc.display.shading, "studio_light", "outdoor.sl"),
                                (sc.display.shading, "show_object_outline", False)):
        try:
            setattr(holder, attr, value)
        except (AttributeError, TypeError):
            pass


def photometrics(path):
    """(mean luma, sd, fraction below 0.18) of a written PNG.

    A render that succeeds and is empty looks identical in a log to one that
    worked. This is how the difference gets noticed.
    """
    img = bpy.data.images.load(path)
    try:
        px = list(img.pixels)
    finally:
        bpy.data.images.remove(img)
    n = len(px) // 4
    if not n:
        return 0.0, 0.0, 1.0
    tot = 0.0
    sq = 0.0
    dark = 0
    for i in range(n):
        j = i * 4
        y = 0.2126 * px[j] + 0.7152 * px[j + 1] + 0.0722 * px[j + 2]
        tot += y
        sq += y * y
        if y < 0.18:
            dark += 1
    mean = tot / n
    var = max(0.0, sq / n - mean * mean)
    return mean, math.sqrt(var), dark / n


def render(path, subjects, res=(1400, 1000), fill=0.90, dirv=(-0.85, -1.0, 0.42),
           min_span=0.30, color_type="MATERIAL"):
    """Frame a list of objects and render them. Returns a metrics dict.

    Does NOT gate -- `-- look` is the cheap answer to a shape question and a
    dim render is still an answer. The hard gate lives in assetbuild.judge().
    What this does do is MEASURE and report, so a blank frame is visible in the
    log rather than discovered by eye three assets later.
    """
    sc = bpy.context.scene
    lo, hi = world_bounds(subjects)
    centre = (lo + hi) / 2
    # Frame EVERY PIECE box, not the eight corners of the union. An L-shaped
    # layout bounding box is mostly empty air, so framing the box put a subject
    # at 40% of the frame while the solver reported a satisfied 88% fill.
    corners = [ob.matrix_world @ Vector(c) for ob in subjects
               if getattr(ob, "type", None) == "MESH" for c in ob.bound_box]
    if not corners:
        raise SystemExit("FAIL: nothing to render at %s - the subject list has "
                         "no mesh objects." % os.path.basename(path))
    direction = Vector(dirv).normalized()

    # Resolution FIRST, before a single projection is computed.
    # world_to_camera_view normalises by the render aspect, so solving the
    # camera and then setting the resolution frames the shot for whatever
    # aspect the previous view happened to leave behind.
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100

    cam_d = bpy.data.cameras.new("ShotCam")
    cam = bpy.data.objects.new("ShotCam", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam
    use_workbench(sc, direction, color_type)
    sync_viewport_colours()

    chosen, d, span, box, tried = None, 0.0, 0.0, None, []
    for lens in LENSES:
        cam_d.lens = lens
        d, span, box = solve_camera(sc, cam, corners, centre, direction, fill)
        # "Everything is actually in the frame" is the criterion, not a span
        # number. A projected extent of 0.95 is equally consistent with a
        # subject centred and filling the frame, or one shoved into a corner
        # with most of it off the edge.
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
            % (os.path.basename(path), LENSES[-1], (hi - lo).length / 2,
               "\n  ".join(tried)))

    os.makedirs(os.path.dirname(path), exist_ok=True)
    sc.render.filepath = path
    sc.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)

    bpy.data.objects.remove(cam, do_unlink=True)
    bpy.data.cameras.remove(cam_d)

    mean, sd, darkfrac = photometrics(path)
    out = {"lens": chosen, "distance": d, "span": span,
           "luma": mean, "luma_sd": sd, "dark": darkfrac}
    print("  shot %-28s %2.0fmm  %5.2f m  fill %.2f  luma %.3f sd %.3f  dark %.0f%%%s"
          % (os.path.basename(path), chosen, d, span, mean, sd, darkfrac * 100,
             "   ** BLANK **" if sd < 0.02 else ""))
    return out
