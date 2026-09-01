"""Gods and Lamb: the single entry point.

    blender --background --factory-startup --python build.py -- <target> [args]

Targets:
    look <asset_id> [k=v ...]     three Workbench angles into out/look/   (cheap)
    rig <asset_id>                skeleton + skin + walk cycle, out/rig/  (folk only)
    lit <asset_id> [k=v ...]      the same three under the GAME light rig, out/lit/
    measure <asset_id> [k=v ...]  the real AABB per axis                  (cheapest)
    list                          every asset the registry can see
    vocab                         regenerate src/vocab.py from the tree

Every path resolves from this file, so the project can be moved without edits.
--factory-startup matters: it guarantees no user addon or preference changes
the result. Builds must be reproducible from a clean Blender.
"""
import os
import sys
import traceback

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "src")
ASSETS = os.path.join(ROOT, "assets")
OUT = os.path.join(ROOT, "out")
# assets/_kit holds shared ASSET helpers -- geometry that defines what a tile
# or a plant IS, as opposed to the machinery in src/. It is on the path rather
# than in src/ because it is art: changing it restyles the world.
KIT = os.path.join(ROOT, "assets", "_kit")
for _p in (SRC, KIT):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import timing                                                     # noqa: E402
timing.unbuffer()


def _die_loudly(exc_type, exc, tb):
    """Blender exits 0 on an uncaught Python exception, and it CATCHES
    SystemExit -- so on its own neither a crash nor a raise reaches the shell
    as a failure. Without this hook every gate in the project is decorative.

    os._exit, not sys.exit, for the same reason: sys.exit raises SystemExit,
    which is exactly what Blender swallows.
    """
    if exc_type is SystemExit:
        msg = str(exc)
        failed = bool(msg) and msg not in ("0", "None")
        if failed:
            print(msg)
        sys.stdout.flush()
        os._exit(1 if failed else 0)
    traceback.print_exception(exc_type, exc, tb)
    sys.stdout.flush()
    os._exit(1)


sys.excepthook = _die_loudly


def _args():
    """Everything after a bare -- on the command line."""
    argv = sys.argv
    return argv[argv.index("--") + 1:] if "--" in argv else []


def _kwargs(rest):
    """k=v pairs off the command line, floats where they look like floats."""
    kw = {}
    for tok in rest:
        if "=" not in tok:
            continue
        k, v = tok.split("=", 1)
        try:
            kw[k] = float(v) if ("." in v or v.lstrip("-").isdigit()) else v
        except ValueError:
            kw[k] = v
    return kw


def _fresh_scene():
    """Factory-empty scene with the palette loaded.

    init_materials() runs AFTER the wipe and BEFORE any builder, or every
    M[...] lookup fails. It is called twice on purpose: once so the module
    globals exist for anything imported at module scope, and once after the
    reset that would otherwise have discarded them.
    """
    import bpy
    import kit
    kit.init_materials()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    kit.init_materials()
    return bpy.context.scene


def _ground(kit_mod):
    """A plane under the subject.

    Not decoration: without it a subject floats in a void, Workbench cavity
    shading has nothing to catch, and the eye has no scale reference. Built
    here rather than in a builder because it is scaffolding, not art -- this is
    the one place a material is constructed outside the palette.
    """
    mat = kit_mod.flat("LookGround", (0.42, 0.44, 0.46), 0.70)
    return kit_mod.box("LOOK_Ground", (0, 0, -0.06), (60.0, 60.0, 0.12), mat)


def _build_subject(entry, tag, kw):
    """Build the asset and finish it exactly as the sweep will.

    weighted_normals_all() is the final geometry pass and it runs HERE, not in
    the builder: WN must be last in every modifier stack, so it can only be
    added once nothing else will be. A builder that added its own would be
    overtaken by the next modifier and silently do nothing.

    It also means `look` and `measure` see the shading and the triangle count
    that ship, rather than a builder-only halfway state.
    """
    import kit
    parts = entry["build"](tag, **kw)
    if not parts:
        raise SystemExit("FAIL: %s built nothing." % entry["decl"]["variant"])
    meshes = [p for p in parts if getattr(p, "type", None) == "MESH"]
    frac, missing = kit.soften_coverage(meshes)
    if missing:
        raise SystemExit("FAIL: %s left %d mesh(es) out of the rounding pass: "
                         "%s. Everything goes through soften_all or soften_top."
                         % (entry["decl"]["variant"], len(missing),
                            ", ".join(missing)))
    kit.weighted_normals_all(meshes)
    return meshes


def target_look(rest):
    """Three fixed angles, Workbench, about a second a frame.

    The cheap answer to a SHAPE question. No gate, no export, no Godot. Open
    the PNG: a triangle count cannot tell you that a roof overhangs its own
    doorway, and the first frame can.
    """
    import registry
    import shot
    import kit

    if not rest:
        raise SystemExit("FAIL: look needs an asset id, e.g. Terrain/grass")
    aid, kw = rest[0], _kwargs(rest[1:])
    entry = registry.resolve(aid)

    _fresh_scene()
    _ground(kit)
    parts = _build_subject(entry, "LOOK", kw)
    size = kit.bounds(parts)
    print("look %s: %d mesh(es), %.2f x %.2f x %.2f m"
          % (aid, len(parts), size[0], size[1], size[2]))

    stem = aid.replace("/", "_")
    # FRONT is dead-on -Y, because that is the direction every asset fronts.
    # It used to be (-1.00, -0.55, 0.30), which puts the camera mostly at -X --
    # so the angle called "front" was a LEFT SIDE view for every asset in the
    # project, and a villager rendered with one eye behind his own hair before
    # anyone noticed. `dirv` is the direction from the subject TO the camera.
    for name, dirv in (("front", (0.00, -1.00, 0.30)),
                       ("three_quarter", (-0.85, -1.00, 0.42)),
                       ("along", (-1.00, -0.20, 0.22))):
        shot.render(os.path.join(OUT, "look", "%s_%s.png" % (stem, name)),
                    parts, res=(1400, 1000), fill=0.90, dirv=dirv)
    print("wrote out/look/%s_{front,three_quarter,along}.png" % stem)


def target_measure(rest):
    """The real AABB. Assets are built by code and their dimensions are
    frequently not what the arithmetic suggests. Measure, never derive."""
    import registry
    import kit

    if not rest:
        raise SystemExit("FAIL: measure needs an asset id, e.g. Terrain/grass")
    aid, kw = rest[0], _kwargs(rest[1:])
    entry = registry.resolve(aid)

    _fresh_scene()
    parts = _build_subject(entry, "MEAS", kw)
    lo, hi = kit.bounds_lohi(parts)
    decl = entry["decl"]
    print("%s  (%s.%s.%s)" % (aid, decl["cls"], decl["family"], decl["variant"]))
    for i, axis in enumerate("XYZ"):
        print("  %s  %8.4f .. %8.4f   size %7.4f"
              % (axis, lo[i], hi[i], hi[i] - lo[i]))
    print("  declared footprint  %.3f x %.3f" % tuple(decl["footprint"]))
    print("  measured footprint  %.3f x %.3f" % (hi[0] - lo[0], hi[1] - lo[1]))
    print("  tris %d   cap %d" % (sum(kit.evaluated_tris(p) for p in parts),
                                  registry.tri_cap(decl)))
    print("  fronts -Y; +Z here is +Y in Godot")


def target_ao(rest):
    """Bake AO to vertex colour and render the bake ALONE, plus the material.

    Rendered with Workbench in VERTEX colour mode, so the picture is the
    occlusion map by itself rather than the occlusion multiplied into the
    palette. That is the point: a bake that is silently flat and a bake that is
    working look identical once a green tile is drawn over the top of it.

    No ground plane here, deliberately. Rays are cast against the whole scene,
    so a 60 m plane under the subject reads as an occluder and every
    downward-facing vertex comes back fully dark.
    """
    import registry
    import shot
    import kit
    import aobake

    if not rest:
        raise SystemExit("FAIL: ao needs an asset id, e.g. Buildings/hut")
    aid, kw = rest[0], _kwargs(rest[1:])
    entry = registry.resolve(aid)

    _fresh_scene()
    parts = _build_subject(entry, "AO", kw)
    # MERGE FIRST. The bake writes one value per vertex, and before the merge
    # the parts are unbevelled boxes -- a wall is eight corners, so the whole
    # face is an interpolation between four numbers and a crease gets nothing.
    # merge_many() runs convert(), which bakes the Bevel modifiers, and the
    # bevel puts a vertex loop exactly where the creases are. Same reason
    # mark_sharp() runs on final geometry: AO on an intermediate mesh measures
    # a shape that never ships.
    n_parts = len(parts)
    before = sum(len(p.data.vertices) for p in parts)
    merged = kit.merge_many(parts, entry["decl"]["variant"] + "_mesh")
    parts = [merged]
    print("  merged %d part(s), %d -> %d verts"
          % (n_parts, before, len(merged.data.vertices)))
    stats = aobake.bake(parts)
    print("ao %s: %d verts  min %.3f  mean %.3f  max %.3f"
          % (aid, stats["verts"], stats["min"], stats["mean"], stats["max"]))
    ok, lines = aobake.verify_written(parts)
    for line in lines:
        print("  " + line)
    if not ok:
        raise SystemExit("FAIL: the AO bake did not survive on the mesh. See "
                         "the lines above.")

    stem = aid.replace("/", "_")
    path = os.path.join(OUT, "look", "%s_ao.png" % stem)
    shot.render(path, parts, res=(1400, 1000), fill=0.90,
                dirv=(-0.85, -1.00, 0.42), color_type="VERTEX")
    print("wrote out/look/%s_ao.png" % stem)


def target_lit(rest):
    """Three angles under the GAME light rig: EEVEE, one warm sun, a sky.

    The other half of `-- look`, not a replacement for it. Workbench answers
    "what shape is it" and CANNOT answer "does it work lit", because its studio
    rig follows the camera, has no sky and casts no real shadow -- none of
    which is true of the light the game has. This target is that light: one
    SUN, a gradient sky, Standard view transform, and nothing Godot's GL
    Compatibility renderer lacks. See src/lit.py.

    Measured at 0.2-0.7 s a frame, against Workbench's 0.7 s. It is not the
    cheap loop anyway, because it has to merge and bake AO first.
    """
    import registry
    import kit
    import lit

    if not rest:
        raise SystemExit("FAIL: lit needs an asset id, e.g. Buildings/hut")
    aid, kw = rest[0], _kwargs(rest[1:])
    entry = registry.resolve(aid)

    _fresh_scene()
    parts = _build_subject(entry, "LIT", kw)
    # Merge, then bake, then ground, in that order and no other. The bake needs
    # the vertex loops the merge bakes out of the Bevel modifiers (gotcha #61),
    # and it ray-casts against the whole scene -- so a ground plane laid down
    # first reads as an occluder and every downward-facing vertex comes back
    # fully dark.
    n_parts = len(parts)
    merged = kit.merge_many(parts, entry["decl"]["variant"] + "_mesh")
    print("lit %s: merged %d part(s) -> %d verts"
          % (aid, n_parts, len(merged.data.vertices)))
    lit.bake_isolated([merged])
    lit.ground()

    stem = aid.replace("/", "_")
    # FRONT is dead-on -Y, because that is the direction every asset fronts.
    # It used to be (-1.00, -0.55, 0.30), which puts the camera mostly at -X --
    # so the angle called "front" was a LEFT SIDE view for every asset in the
    # project, and a villager rendered with one eye behind his own hair before
    # anyone noticed. `dirv` is the direction from the subject TO the camera.
    for name, dirv in (("front", (0.00, -1.00, 0.30)),
                       ("three_quarter", (-0.85, -1.00, 0.42)),
                       ("along", (-1.00, -0.20, 0.22))):
        lit.render(os.path.join(OUT, "lit", "%s_%s.png" % (stem, name)),
                   [merged], res=(1200, 800), fill=0.90, dirv=dirv)
    print("wrote out/lit/%s_{front,three_quarter,along}.png" % stem)


def target_field(rest):
    """Render N x N of a tile, laid out on the grid. The tiling answer.

    A single-tile look cannot answer the only question a ground tile has to
    pass: does a FLOOR of them read right. Seams, gaps, and the groove between
    blocks are all properties of the neighbourhood, not of the tile, and the
    reference art is a picture of a neighbourhood.

    Instances share mesh data, so this is cheap and it is also honest about
    what the engine will draw -- one mesh, many transforms, exactly what
    MultiMesh does.
    """
    import bpy
    import registry
    import shot
    import kit

    if not rest:
        raise SystemExit("FAIL: field needs an asset id, e.g. Terrain/grass")
    aid, kw = rest[0], _kwargs(rest[1:])
    n = int(kw.pop("n", 4))
    step = float(kw.pop("step", 1.0))
    entry = registry.resolve(aid)

    _fresh_scene()
    parts = _build_subject(entry, "FIELD", kw)
    tile = kit.merge_many(parts, "tile")

    span = (n - 1) * step * 0.5
    out = [tile]
    for i in range(n):
        for j in range(n):
            if i == 0 and j == 0:
                tile.location = (-span, -span, 0.0)
                continue
            dup = tile.copy()                 # linked data: one mesh, N objects
            dup.data = tile.data
            dup.location = (i * step - span, j * step - span, 0.0)
            bpy.context.scene.collection.objects.link(dup)
            out.append(dup)

    # matrix_world is CACHED. Setting .location does not update it, so every
    # duplicate still reports the origin until the view layer is told -- the
    # first run of this framed a 4 x 4 field as "1.00 x 1.00 x 1.00 m overall"
    # and put the camera 2.86 m from a single tile.
    bpy.context.view_layer.update()

    size = kit.bounds(out)
    print("field %s: %d x %d at %.2f m, %.2f x %.2f x %.2f m overall"
          % (aid, n, n, step, size[0], size[1], size[2]))

    stem = aid.replace("/", "_")
    for name, dirv in (("field_high", (-0.80, -1.00, 0.85)),
                       ("field_low", (-0.70, -1.00, 0.34))):
        shot.render(os.path.join(OUT, "look", "%s_%s.png" % (stem, name)),
                    out, res=(1400, 1000), fill=0.92, dirv=dirv)
    print("wrote out/look/%s_field_{high,low}.png" % stem)


def target_scene(rest):
    """Build the Vale and render it, Workbench and lit.

    The only picture that can answer whether the pieces belong to the same
    world. A per-asset render tells you an asset is correct; only a scene tells
    you the cliff, the bank and the canopy agree with each other -- and only a
    scene shows a fence running through a cottage.
    """
    import shot
    import kit
    import vale

    _fresh_scene()
    placed, frame = vale.build()
    size = kit.bounds(placed)
    tris = sum(kit.evaluated_tris(o) for o in placed)
    meshes = len({o.data.name for o in placed})
    print("vale: %d object(s), %d unique mesh(es), %d tris, %.1f x %.1f x %.1f m"
          % (len(placed), meshes, tris, size[0], size[1], size[2]))

    # The camera is given the FRAMING BOX and nothing else, so it aims at a
    # region and the landscape runs off every edge. Handing it the whole scene
    # is what made three earlier versions read as a diorama: the frame had to
    # contain the map, so the map got squeezed to fit the frame.
    for name, dirv, fill in (("hero", (-0.72, -1.00, 0.88), 1.00),
                             ("high", (-0.55, -1.00, 1.00), 1.00),
                             ("low", (-0.85, -1.00, 0.66), 1.00)):
        shot.render(os.path.join(OUT, "look", "vale_%s.png" % name),
                    [frame], res=(1600, 1000), fill=fill, dirv=dirv,
                    min_span=0.10)
    print("wrote out/look/vale_{hero,high,low}.png")

    import lit
    # The lit pass runs SECOND, always. lit.bake_isolated() ends in
    # aobake.wire_all(), which rewires every material in the file -- a
    # Workbench render taken after that is no longer the render -- look gives.
    lit.bake_isolated(placed)
    for name, dirv in (("hero", (-0.72, -1.00, 0.88)),
                       ("high", (-0.55, -1.00, 1.00)),
                       ("low", (-0.85, -1.00, 0.66))):
        lit.render(os.path.join(OUT, "lit", "vale_%s.png" % name),
                   [frame], res=(1600, 1000), fill=1.00, dirv=dirv,
                   min_span=0.10)
    print("wrote out/lit/vale_{hero,high,low}.png")


def target_asset(rest):
    """THE GATE for one asset. Build it, finish it, and refuse it if it is wrong.

    Until this existed, an asset was "verified" by a human opening a PNG. That
    catches a bad shape and nothing else -- not a blown triangle cap, not a
    footprint that lies to the placement solver, not the ngon debris an EXACT
    boolean leaves behind. Six buildings were authored under that regime and
    the agent that wrote them said so plainly in its report, which is the only
    reason it is being fixed now.

    Checks run in a COLLECT-ALL pass. A build is seconds and the checks are
    milliseconds, so failing fast just means finding one fault per run when you
    could have had all of them.
    """
    import registry
    import kit

    if not rest:
        raise SystemExit("FAIL: asset needs an id, e.g. Terrain/grass")
    aid, kw = rest[0], _kwargs(rest[1:])
    entry = registry.resolve(aid)
    decl = entry["decl"]

    _fresh_scene()
    # _build_subject already fails on soften coverage and adds Weighted Normal.
    parts = _build_subject(entry, "GATE", kw)
    n_parts = len(parts)
    merged = kit.merge_many(parts, decl["variant"] + "_mesh")

    faults = []

    tris = kit.evaluated_tris(merged)
    cap = registry.tri_cap(decl)
    if tris > cap:
        faults.append("triangles: %d against a cap of %d for cls=%s. Fix the "
                      "geometry -- cut bevel segments, cut primitive "
                      "resolution, or cut a part that did not earn its place. "
                      "Never raise the cap."
                      % (tris, cap, decl["cls"]))

    lo, hi = kit.bounds_lohi([merged])
    mx, my = hi[0] - lo[0], hi[1] - lo[1]
    dx, dy = decl["footprint"]
    # 2 cm. An audit of the parent project found 17 of 39 assets understating
    # themselves, the worst by 3.69 m -- and the village reserves ground from
    # the DECLARATION, so an understated footprint gets a neighbour placed
    # inside this asset.
    if mx - dx > 0.02 or my - dy > 0.02:
        faults.append("footprint: declared (%.3f, %.3f) but measures "
                      "(%.3f, %.3f). The village reserves ground from the "
                      "declaration, so this asset will get a neighbour placed "
                      "inside it. Declare (%.2f, %.2f)."
                      % (dx, dy, mx, my, mx + 0.005, my + 0.005))

    # Anchor contract: floor-standing means the origin is the point it stands
    # on, so the mesh must sit ON z=0 rather than through it or above it.
    if decl.get("anchor") == "floor" and abs(lo[2]) > 0.005:
        faults.append("anchor: declares anchor='floor' but its lowest vertex is "
                      "at z=%.4f. Build at the origin, standing on z=0."
                      % lo[2])

    d = kit.mesh_defects(merged)
    dirty = {k: v for k, v in d.items()
             if v and k in ("ngons", "degenerate", "zero_edges", "loose")}
    if dirty:
        faults.append("mesh: %s. An EXACT boolean is topologically correct and "
                      "cosmetically filthy; ngons triangulate differently in "
                      "Blender and in the engine, which is the classic 'it "
                      "looked fine in Blender' artifact."
                      % ", ".join("%s=%d" % kv for kv in sorted(dirty.items())))

    print("%s  (%s.%s.%s)" % (aid, decl["cls"], decl["family"], decl["variant"]))
    print("  parts %d -> 1 mesh   tris %d / %d   %.3f x %.3f x %.3f m"
          % (n_parts, tris, cap, mx, my, hi[2] - lo[2]))
    print("  nonmanifold %d (reported, not failed: 3-4 face T-junctions are "
          "normal for a welded assembly; 1 face would be a hole)"
          % d.get("nonmanifold", 0))

    if faults:
        sep = chr(10) + "  - "
        raise SystemExit("FAIL: %s did not pass the gate - %d fault(s), "
                         "every one listed:%s%s"
                         % (aid, len(faults), sep, sep.join(faults)))
    print("  [GATE] ok")


def target_assets(rest):
    """Every asset through the gate, ONE PROCESS EACH, collect-all.

    One process each because kit.M, kit.STATS and kit.SCHEMES are mutable
    module globals and cross-contamination presents as a GEOMETRY bug -- you
    would not suspect the build system.

    Collect-all because a sweep that stops at the first fault makes you pay for
    a whole run per fault. Every failure is listed, then the sweep fails once.
    """
    import subprocess
    import registry

    found = registry.discover()
    order = sorted(found)
    print("sweep: %d asset(s)" % len(order))

    failed = []
    for aid in order:
        cmd = [sys.argv[0], "--background", "--factory-startup",
               "--python", os.path.abspath(__file__), "--", "asset", aid]
        r = subprocess.run(cmd, capture_output=True, text=True)
        ok = r.returncode == 0
        print("  %-24s %s" % (aid, "ok" if ok else "FAIL"))
        if not ok:
            body = (r.stdout or "") + (r.stderr or "")
            keep = [ln for ln in body.splitlines()
                    if ln.startswith("FAIL") or ln.startswith("  - ")]
            joiner = chr(10) + "    "
            failed.append((aid, joiner.join(keep)
                           or body.strip()[-400:]))

    if failed:
        gap = chr(10) + chr(10)
        body = gap.join("  %s%s    %s" % (a, chr(10), why)
                        for a, why in failed)
        raise SystemExit("FAIL: %d of %d asset(s) did not pass the "
                         "gate:%s%s" % (len(failed), len(order),
                                        gap, body))
    print("[SWEEP] all %d assets ok" % len(order))


def _asset_glb_name(aid):
    """Category__variant.glb. Godot rewrites . : @ / % in NODE names, so the
    file name avoids them entirely rather than relying on a mapping."""
    return aid.replace("/", "__") + ".glb"


def target_library(rest):
    """One GLB per asset into godot/assets/library/, ONE PROCESS EACH.

    One process each because kit.M, kit.STATS and kit.SCHEMES are mutable
    module globals; cross-contamination presents as a geometry bug and you
    would not suspect the build system.
    """
    import subprocess
    import registry
    import buildcache

    outdir = os.environ.get("LAMB_GODOT_ASSETS") or os.path.join(
        os.path.dirname(ROOT), "godot", "assets", "library")
    found = registry.discover()
    order = sorted(found)
    cache = buildcache.load()
    print("library: %d asset(s) -> %s" % (len(order), outdir))

    failed = []
    built = 0
    skipped = []
    for aid in order:
        out_path = os.path.join(outdir, _asset_glb_name(aid))
        # CONTENT-addressed, not timestamp-addressed. The GLBs were always
        # being written to disk; they were simply being rebuilt whether or not
        # anything that feeds them had changed, which cost ~57 s on every run
        # and made editing the LAYOUT rebuild every mesh in the game.
        if buildcache.is_current(cache, aid, found[aid], out_path):
            skipped.append(aid)
            continue
        cmd = [sys.argv[0], "--background", "--factory-startup",
               "--python", os.path.abspath(__file__), "--", "glb", aid]
        r = subprocess.run(cmd, capture_output=True, text=True)
        line = [ln for ln in (r.stdout or "").splitlines()
                if ln.startswith("  glb ")]
        print(line[0] if line else "  %-26s FAIL" % aid)
        if r.returncode != 0:
            body = (r.stdout or "") + (r.stderr or "")
            keep = [ln for ln in body.splitlines() if ln.startswith("FAIL")]
            failed.append((aid, keep[0] if keep else body.strip()[-300:]))
            # Drop the entry rather than leaving a stale one: a failed export
            # must not be able to satisfy the cache on the next run.
            cache.pop(aid, None)
            continue
        cache[aid] = buildcache.digest(aid, found[aid])
        built += 1

    buildcache.save(cache)
    # A marker RUN.bat reads, so it can skip Godot's two-pass reimport when
    # nothing changed -- that reimport is 5.1 s and is pure waste on a run
    # where not one GLB was rewritten.
    try:
        os.makedirs(os.path.join(ROOT, "out"), exist_ok=True)
        with open(os.path.join(ROOT, "out", "library_built.txt"), "w") as fh:
            fh.write(str(built))
    except OSError:
        pass
    if failed:
        gap = chr(10) + "  "
        raise SystemExit("FAIL: %d asset(s) did not export:%s%s"
                         % (len(failed), gap,
                            gap.join("%s  %s" % f for f in failed)))
    print("[LIBRARY] %d built, %d unchanged%s"
          % (built, len(skipped),
             "  (LAMB_REBUILD_ALL=1 to force)" if skipped else ""))


def target_glb(rest):
    """ONE asset to GLB. The per-asset worker `-- library` spawns.

    Folk take the rigged path: bound loose, joined, attached, walk baked, and
    exported WITH the armature. Everything else is merged to a single mesh
    first, which is what MultiMesh and a draw-call budget both want.

    AO is baked here rather than in the engine, per asset, in isolation. It is
    the whole contact-shading budget under GL Compatibility, and glTF COLOR_0
    is defined as multiplying into base colour -- so the multiply survives to
    the Compatibility renderer with nothing to configure.
    """
    import bpy
    import registry
    import kit
    import aobake
    import export_gltf
    import verify_export

    if not rest:
        raise SystemExit("FAIL: glb needs an asset id")
    aid, kw = rest[0], _kwargs(rest[1:])
    entry = registry.resolve(aid)
    decl = entry["decl"]
    outdir = os.environ.get("LAMB_GODOT_ASSETS") or os.path.join(
        os.path.dirname(ROOT), "godot", "assets", "library")
    path = os.path.join(outdir, _asset_glb_name(aid))

    _fresh_scene()
    parts = _build_subject(entry, "GLB", kw)
    rigged = decl["cls"] == "folk"

    if rigged:
        import folkrig
        arm = folkrig.build_armature("%s_rig" % decl["variant"])
        folkrig.bake_and_group(parts, tag="GLB")
        bpy.ops.object.select_all(action="DESELECT")
        for ob in parts:
            ob.select_set(True)
        bpy.context.view_layer.objects.active = parts[0]
        bpy.ops.object.join()
        mesh = bpy.context.object
        mesh.name = "%s_mesh" % decl["variant"]
        folkrig.attach(arm, mesh)
        # All four clips, each on its own NLA track. The exporter's ACTIONS
        # mode collects actions from NLA plus the assigned one; an action that
        # is merely in bpy.data is invisible to it and the GLB comes back with
        # a single animation and no error at all.
        tracks = folkrig.all_actions(arm, mesh)
        print("  clips: %s" % ", ".join(tracks))
        subjects = [mesh]
    else:
        mesh = kit.merge_many(parts, "%s_mesh" % decl["variant"])
        # Origin to the floor contact point. Placement in the engine sets
        # global_position and expects it to mean "where this stands".
        kit.floor_origin(mesh)
        arm = None
        subjects = [mesh]

    aobake.bake(subjects)
    if rigged:
        # Skinned meshes only. GL Compatibility runs a skinning update per
        # SURFACE per frame, so eight flat-colour materials on a villager cost
        # eight of them -- measured at 88.8% of a follower's entire frame cost.
        # Static assets keep their material slots: the same split costs nothing
        # there (353 props and 7338 tiles draw in 1.05 ms) and the per-material
        # authoring is how the whole library is written.
        for nm, was, now in aobake.fold_to_vertex_colour(subjects):
            print("  folded %s: %d surfaces -> %d" % (nm, was, now))
    aobake.wire_all()

    # The vocabulary the engine reads. Custom properties become glTF extras,
    # and Godot must key on THOSE, never on node names -- validate_node_name()
    # rewrites . : @ / % to _.
    mesh["lamb_id"] = aid
    mesh["lamb_class"] = decl["cls"]
    mesh["lamb_family"] = decl["family"]
    mesh["lamb_variant"] = decl["variant"]
    mesh["lamb_footprint"] = list(decl["footprint"])
    mesh["lamb_anchor"] = decl.get("anchor", "floor")

    if rigged:
        export_gltf.export_rigged(arm, [mesh], path)
    else:
        export_gltf.export_static([mesh], path)
    info = verify_export.assert_glb_readback(
        path, want_skin=rigged, want_animation=rigged)
    print("  glb %-26s %6d B  nodes %d  meshes %d  skins %d  anims %d  "
          "COLOR_0 %s" % (aid, os.path.getsize(path), info["nodes"],
                          info["meshes"], info["skins"], info["animations"],
                          "yes" if info["has_color0"] else "NO"))


def target_export(rest):
    """Everything the engine needs: the library, plus the Vale as data.

    The layout goes across as JSON rather than as a baked scene GLB, because
    the village GROWS during play. Godot instances from this the same way the
    look-dev render does, so the two cannot drift into different villages.
    """
    import json
    import vale

    target_library(rest)

    import registry
    found = registry.discover()
    outdir = os.path.join(os.path.dirname(ROOT), "godot", "data")
    os.makedirs(outdir, exist_ok=True)
    path = os.path.join(outdir, "vale.json")
    doc = {
        "tile": vale.TILE,
        "lift": vale.LIFT,
        "upper_blocks": vale.UPPER_BLOCKS,
        "water_drop": vale.WATER_DROP,
        "cols": vale.COLS,
        "rows": vale.ROWS,
        "code": vale.CODE,
        "fill": vale.FILL,
        "lower": list(vale.LOWER),
        "upper": list(vale.UPPER),
        # Footprints travel WITH the props. The engine has to know what ground
        # a prop occupies to keep a follower from walking through a cottage,
        # and the declaration is the only honest source -- re-deriving it from
        # the mesh in Godot would be a second answer to a question that
        # already has one.
        "props": [{"id": a, "col": c, "row": r, "yaw": y, "scale": sc,
                   "fp": list(found[a]["decl"]["footprint"])}
                  for a, c, r, y, sc in (list(vale.RUNS) + vale.props_all())],
        "frame": list(vale.FRAME),
    }
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, indent=1)
    print("[EXPORT] %s  %d props, %d x %d tiles"
          % (path, len(doc["props"]), doc["cols"], doc["rows"]))


def target_cache(rest):
    """Prove the build cache invalidates on exactly the right things.

    A cache that skips when it should not is a stale-asset bug you meet hours
    later in the engine, so the interesting direction is BOTH: it must rebuild
    what changed and it must NOT rebuild what did not.

    Done by digesting against edited COPIES of the sources rather than by
    running 27 Blender exports, so this is a second of arithmetic and can sit
    in the gate.
    """
    import registry
    import buildcache

    found = registry.discover()
    folk = [a for a in found if found[a]["decl"]["cls"] == "folk"]
    other = [a for a in found if found[a]["decl"]["cls"] != "folk"]
    if not folk or not other:
        raise SystemExit("FAIL: cache test needs at least one folk and one "
                         "non-folk asset; found %d / %d"
                         % (len(folk), len(other)))
    tree = sorted(other)[0]

    base = {a: buildcache.digest(a, found[a]) for a in found}
    real_read = buildcache._read
    faults = []

    def with_edit(target_path, label):
        """Digests as they would be if `target_path` had different bytes."""
        def patched(path):
            data = real_read(path)
            return data + b"# probe" if os.path.abspath(path)                 == os.path.abspath(target_path) else data
        buildcache._read = patched
        try:
            return {a: buildcache.digest(a, found[a]) for a in found}
        finally:
            buildcache._read = real_read

    def expect(label, after, should_change):
        moved = {a for a in found if after[a] != base[a]}
        if moved != set(should_change):
            faults.append("%s changed %s, expected %s"
                          % (label, sorted(moved) or "nothing",
                             sorted(should_change) or "nothing"))
        else:
            print("  %-34s -> %d asset(s) invalidated"
                  % (label, len(moved)))

    # 1. One asset's own source invalidates only itself.
    expect("edit %s" % tree, with_edit(found[tree]["path"], tree), [tree])

    # 2. The folk rig invalidates the folk, and NOTHING else. This is the one
    #    that matters most: treating all of assets/_kit as shared made every
    #    animation tweak rebuild the terrain.
    rig = os.path.join(ROOT, "assets", "_kit", "folkrig.py")
    if os.path.exists(rig):
        expect("edit _kit/folkrig.py", with_edit(rig, "rig"), folk)

    # 3. A core module invalidates everything.
    expect("edit src/kit.py",
           with_edit(os.path.join(ROOT, "src", "kit.py"), "kit"), list(found))

    # 4. The LAYOUT invalidates nothing. src/vale.py says where props stand;
    #    it cannot change a mesh, and rebuilding 27 assets because it moved a
    #    tree is the waste this cache exists to remove.
    expect("edit src/vale.py",
           with_edit(os.path.join(ROOT, "src", "vale.py"), "vale"), [])

    if faults:
        gap = chr(10) + "  "
        raise SystemExit("FAIL: build cache invalidates wrongly:%s%s"
                         % (gap, gap.join(faults)))
    print("[CACHE] invalidation is correct in both directions")


def target_list(rest):
    import registry
    found = registry.discover(verbose=True)
    print("%d asset(s)" % len(found))


def target_vocab(rest):
    """Regenerate src/vocab.py from what exists.

    Deliberately a separate, explicit step. If new families were absorbed
    automatically the vocabulary would not be closed, and closing it is the
    whole point -- it is the friction that stops forty near-synonyms.
    """
    import registry
    found = registry.discover()
    families = sorted({e["decl"]["family"] for e in found.values()})
    path = os.path.join(SRC, "vocab.py")
    body = open(path, encoding="utf-8").read()
    head = body.split("FAMILIES = ")[0]
    lines = [head, "FAMILIES = frozenset({\n"]
    for f in families:
        lines.append("    %r,\n" % f)
    lines.append("})\n\n")
    lines.append("# Floor for the selftest ratchet: the number of negative "
                 "controls that must\n")
    lines.append("# exist. It may grow, never shrink -- a case cannot silently "
                 "disappear.\n")
    lines.append("SELFTEST_MIN = 0\n")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("".join(lines))
    print("vocab: %d families from %d assets -> src/vocab.py"
          % (len(families), len(found)))
    for f in families:
        print("  %s" % f)


def target_rig(rest):
    """Skeleton, skin and walk cycle for a folk asset. Checked, then rendered.

    The one target that does NOT merge first. Every other path in this project
    collapses an asset to a single mesh before it measures anything, and rigid
    skinning cannot survive that: the bind assigns each PART to a bone, and
    after a merge there are no parts to assign. So the parts are bound loose
    and joined afterwards, by which point the vertex groups already exist and
    the join just carries them along.

    Four asserts, and all four exist because the failure they catch renders as
    a perfectly plausible picture:

      rigid weights     a vertex on two bones tears an armpit
      sagittal roll     a leg that swings sideways is a curtsy, not a walk
      action deforms    an unslotted action owns fcurves and moves nothing
      cycle closes      frame 1 != frame 25 pops once per stride, forever
      feet on floor     checked on every frame, not on the planted keys

    Frames are shot from a FIXED camera. lit.render() re-solves the framing per
    call, so a per-frame solve would track the character and produce a walk
    where the legs move and the body never does.
    """
    import bpy
    import registry
    import kit
    import lit
    import folkrig

    if not rest:
        raise SystemExit("FAIL: rig needs an asset id, e.g. Folk/villager")
    aid, kw = rest[0], _kwargs(rest[1:])
    entry = registry.resolve(aid)
    decl = entry["decl"]
    if decl["cls"] != "folk":
        raise SystemExit("FAIL: %s is cls=%s. folkrig's skeleton is a folk "
                         "body -- binding it to a building would put a roof on "
                         "a femur." % (aid, decl["cls"]))

    _fresh_scene()
    parts = _build_subject(entry, "RIG", kw)
    tris_loose = sum(kit.evaluated_tris(p) for p in parts)
    arm = folkrig.build_armature("%s_rig" % decl["variant"])
    folkrig.assert_roll_is_sagittal(arm)
    folkrig.bake_and_group(parts, tag="RIG")
    folkrig.assert_rigid_weights(parts)

    bpy.ops.object.select_all(action="DESELECT")
    for ob in parts:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    skinned = bpy.context.object
    skinned.name = "%s_skinned" % decl["variant"]
    folkrig.attach(arm, skinned)
    folkrig.assert_rigid_weights([skinned])

    # The join must not have changed the geometry. It applied nineteen modifier
    # stacks and concatenated the results, and the number that proves it went
    # cleanly is the one the gate already published for this asset.
    tris = kit.evaluated_tris(skinned)
    if tris != tris_loose:
        raise SystemExit("FAIL: the skinned mesh is %d tris but the parts were "
                         "%d. The join changed the geometry -- the usual cause "
                         "is baking AFTER the join, which applies the active "
                         "object's modifier stack to every other part."
                         % (tris, tris_loose))

    act = folkrig.walk_action(arm, skinned)
    travel = folkrig.assert_action_deforms(arm, [skinned])
    gap = folkrig.assert_cycle_closes(arm, [skinned])
    sink, float_ = folkrig.assert_feet_on_floor(arm, [skinned])

    groups = sorted(vg.name for vg in skinned.vertex_groups)
    print("%s  (%s.%s.%s)" % (aid, decl["cls"], decl["family"], decl["variant"]))
    print("  %d part(s) -> 1 skinned mesh   %d tris   %d bones   %d group(s): %s"
          % (len(parts), tris, len(arm.pose.bones),
             len(groups), ", ".join(groups)))
    print("  action %r  %d fcurves  %d frames at %d fps"
          % (act.name, len(folkrig.action_fcurves(act)), folkrig.CYCLE, folkrig.FPS))
    print("  max vertex travel %.3f m   loop gap %.6f m   floor sink %.4f "
          "float %.4f" % (travel, gap, -sink, float_))

    lit.bake_isolated([skinned])
    lit.ground()
    # A hidden box the size of the whole stride, so every frame is solved
    # against the SAME bounds. Hidden from the render, not from the solver --
    # shot.solve_camera reads bound_box off any mesh it is handed.
    lo, hi = kit.bounds_lohi([skinned])
    pad = 0.22
    guide = kit.box("RIG_FrameGuide",
                    ((lo[0] + hi[0]) * 0.5, (lo[1] + hi[1]) * 0.5,
                     (lo[2] + hi[2]) * 0.5),
                    (hi[0] - lo[0] + pad, hi[1] - lo[1] + pad, hi[2] - lo[2]))
    guide.hide_render = True

    stem = aid.replace("/", "_")
    outdir = os.path.join(OUT, "rig")
    frames = [1 + i * (folkrig.CYCLE // 8) for i in range(8)]
    # TWO angles. A walk is judged from the SIDE -- that is the view the stride
    # length, the foot plant and the arm counter-swing are all visible in -- and
    # three-quarter is the view the game will actually use. A cycle that reads
    # in one and not the other is not finished.
    for view, dirv in (("side", (-1.00, 0.00, 0.16)),
                       ("three_quarter", (-0.60, -1.00, 0.22))):
        shots = []
        for f in frames:
            bpy.context.scene.frame_set(f)
            bpy.context.view_layer.update()
            p = os.path.join(outdir, "%s_%s_f%02d.png" % (stem, view, f))
            lit.render(p, [guide, skinned], res=(300, 420), fill=0.94,
                       dirv=dirv)
            shots.append(p)
        out = os.path.join(outdir, "%s_walk_%s.png" % (stem, view))
        _strip(shots, out)
        for p in shots:
            os.remove(p)
        print("  wrote out/rig/%s_walk_%s.png (%d frames)"
              % (stem, view, len(shots)))

    bpy.data.objects.remove(guide, do_unlink=True)
    bpy.context.scene.frame_set(1)
    blend = os.path.join(outdir, "%s_rigged.blend" % stem)
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    print("  wrote %s" % blend)
    print("  [RIG] ok")


def _strip(paths, out):
    """Lay the frames side by side. Eight PNGs in a folder is not a walk cycle
    anyone can read; one strip is."""
    import bpy
    imgs = [bpy.data.images.load(p) for p in paths]
    w, h = imgs[0].size
    strip = bpy.data.images.new("strip", width=w * len(imgs), height=h)
    buf = [0.0] * (w * len(imgs) * h * 4)
    for i, img in enumerate(imgs):
        px = list(img.pixels)
        for y in range(h):
            src = y * w * 4
            dst = (y * w * len(imgs) + i * w) * 4
            buf[dst:dst + w * 4] = px[src:src + w * 4]
    strip.pixels = buf
    strip.filepath_raw = out
    strip.file_format = "PNG"
    strip.save()
    for img in imgs:
        bpy.data.images.remove(img)
    bpy.data.images.remove(strip)


TARGETS = {
    "look": target_look,
    "rig": target_rig,
    "glb": target_glb,
    "library": target_library,
    "export": target_export,
    "lit": target_lit,
    "ao": target_ao,
    "field": target_field,
    "scene": target_scene,
    "asset": target_asset,
    "assets": target_assets,
    "measure": target_measure,
    "cache": target_cache,
    "list": target_list,
    "vocab": target_vocab,
}

# Named here rather than falling through to "unknown target", so the message
# says "not built yet" rather than "no such thing". They are different problems
# and only one of them is a typo.
PLANNED = ("guards",)


def main():
    rest = _args()
    if not rest:
        raise SystemExit("FAIL: no target. Available: %s"
                         % ", ".join(sorted(TARGETS)))
    name, rest = rest[0], rest[1:]
    if name in PLANNED:
        raise SystemExit("FAIL: target %r is planned but not built yet. "
                         "Available now: %s"
                         % (name, ", ".join(sorted(TARGETS))))
    if name not in TARGETS:
        raise SystemExit("FAIL: unknown target %r. Available: %s"
                         % (name, ", ".join(sorted(TARGETS))))
    TARGETS[name](rest)
    timing.stamp("done")


main()
