"""Skip re-exporting an asset whose inputs have not changed.

WHY. `-- export` spawned one Blender process per asset and rebuilt all 27 every
time, taking ~57 s. Nothing about that was conditional: editing `src/vale.py`
-- which only changes where props are PLACED and cannot change a single mesh --
rebuilt every mesh in the game, and so did editing a Godot script, because
RUN.bat's staleness gate compares one timestamp against every .py in the tree.

The GLBs were always being saved. They were just being thrown away and remade.

WHAT COUNTS AS AN INPUT. A digest per asset over:

  - the asset's own source file
  - the CORE modules that shape every export -- the kit, the AO bake, the glTF
    flags, the read-back check, and build.py itself
  - only the `_kit` helpers that asset actually uses

The last one is the difference between a useful cache and a decorative one.
Treating all of `assets/_kit/` as a shared dependency means touching the folk
rig rebuilds all six terrain tiles, and during the animation work that is
exactly what happened, over and over.

CONSERVATIVE ON PURPOSE. When in doubt this rebuilds. A stale GLB is a bug you
find hours later in the engine; a needless rebuild costs two seconds. The cache
is keyed on CONTENT, not timestamps, so `git checkout` of an old asset
correctly rebuilds it and `touch` correctly does not.
"""
import hashlib
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                     # blender/
KIT_DIR = os.path.join(ROOT, "assets", "_kit")
CACHE_PATH = os.path.join(ROOT, "out", "library_cache.json")

# Changing any of these can change the bytes of every GLB, so they go into
# every asset's digest. Kept explicit rather than globbing src/: a glob would
# quietly pull in look.py and shot.py, which only affect PNG renders, and every
# look-dev tweak would then invalidate the whole library.
CORE = [
    os.path.join(ROOT, "build.py"),
    os.path.join(HERE, "kit.py"),
    os.path.join(HERE, "vfold.py"),
    os.path.join(HERE, "export_gltf.py"),
    os.path.join(HERE, "verify_export.py"),
]

VERSION = 2          # bump to invalidate every entry deliberately


def _read(path):
    try:
        with open(path, "rb") as fh:
            return fh.read()
    except OSError:
        # A missing dependency is itself a state worth hashing -- it must not
        # silently produce the same digest as a present one.
        return b"<missing:%s>" % os.path.basename(path).encode()


def _kit_files_for(src_path, decl):
    """The `_kit` helpers this asset depends on.

    Matched by NAME APPEARING IN THE SOURCE, plus one rule the source cannot
    tell us: folk assets are rigged and animated by `folkrig` from build.py, so
    they depend on it whether or not they import it themselves. Miss that and a
    change to the walk cycle leaves the villager's old GLB in place, which is a
    stale-asset bug that looks like the animation code not working.
    """
    if not os.path.isdir(KIT_DIR):
        return []
    text = _read(src_path).decode("utf-8", "replace")
    out = []
    for fn in sorted(os.listdir(KIT_DIR)):
        if not fn.endswith(".py"):
            continue
        stem = fn[:-3]
        used = stem in text
        if decl.get("cls") == "folk" and stem == "folkrig":
            used = True
        if used:
            out.append(os.path.join(KIT_DIR, fn))
    return out


def digest(aid, entry):
    h = hashlib.sha256()
    h.update(b"v%d\n" % VERSION)
    h.update(aid.encode("utf-8"))
    for path in CORE:
        h.update(_read(path))
    h.update(_read(entry["path"]))
    for path in _kit_files_for(entry["path"], entry.get("decl", {})):
        h.update(os.path.basename(path).encode())
        h.update(_read(path))
    return h.hexdigest()


def load():
    try:
        with open(CACHE_PATH, encoding="utf-8") as fh:
            data = json.load(fh)
        if isinstance(data, dict):
            return data
    except (OSError, ValueError):
        pass
    return {}


def save(cache):
    os.makedirs(os.path.dirname(CACHE_PATH), exist_ok=True)
    with open(CACHE_PATH, "w", encoding="utf-8") as fh:
        json.dump(cache, fh, indent=1, sort_keys=True)


def is_current(cache, aid, entry, out_path):
    """True when the GLB on disk was built from exactly these inputs.

    The output file is checked too, and by SIZE as well as existence: a
    zero-byte GLB left behind by a Blender that died mid-write would otherwise
    match its digest forever and the engine would load nothing.
    """
    if os.environ.get("LAMB_REBUILD_ALL"):
        return False
    if not os.path.exists(out_path) or os.path.getsize(out_path) < 128:
        return False
    return cache.get(aid) == digest(aid, entry)
