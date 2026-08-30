"""Gods and Lamb: the single entry point.

    blender --background --factory-startup --python build.py -- <target> [args]

Targets:
    look <asset_id> [k=v ...]     three Workbench angles into out/look/   (cheap)
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
if SRC not in sys.path:
    sys.path.insert(0, SRC)

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
    "measure": target_measure,
    "list": target_list,
    "vocab": target_vocab,
}

# Named here rather than falling through to "unknown target", so the message
# says "not built yet" rather than "no such thing". They are different problems
# and only one of them is a typo.
PLANNED = ("asset", "assets", "library", "export", "guards")


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
