"""Gods and Lamb: the single entry point.

    blender --background --factory-startup --python build.py -- <target> [args]

Targets:
    look <asset_id> [k=v ...]     three Workbench angles into out/look/   (cheap)
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
    for name, dirv in (("front", (-1.00, -0.55, 0.30)),
                       ("three_quarter", (-0.85, -1.00, 0.42)),
                       ("along", (-0.25, -1.00, 0.18))):
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
    for name, dirv in (("front", (-1.00, -0.55, 0.30)),
                       ("three_quarter", (-0.85, -1.00, 0.42)),
                       ("along", (-0.25, -1.00, 0.18))):
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


TARGETS = {
    "look": target_look,
    "lit": target_lit,
    "ao": target_ao,
    "field": target_field,
    "scene": target_scene,
    "asset": target_asset,
    "assets": target_assets,
    "measure": target_measure,
    "list": target_list,
    "vocab": target_vocab,
}

# Named here rather than falling through to "unknown target", so the message
# says "not built yet" rather than "no such thing". They are different problems
# and only one of them is a typo.
PLANNED = ("library", "export", "guards")


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
