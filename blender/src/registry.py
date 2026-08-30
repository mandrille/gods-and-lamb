"""Asset discovery and declaration checking.

One .py per asset under blender/assets/<Category>/<variant>.py. The filesystem
is the uniqueness guard: `variant` must equal the filename and `category` must
equal the parent folder, so two assets cannot claim the same identity without
one of them overwriting the other on disk first.

Modules whose name starts with an underscore are excluded, which is how shared
helpers live inside the asset tree (assets/_kit/).
"""
import importlib.util
import os

import vocab

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ASSETS = os.path.join(ROOT, "assets")

CLASSES = ("terrain", "nature", "folk", "building")

# Family first, then class. Caps fail the build and name the offender; a cap is
# fixed by fixing the geometry, never by raising the number.
TRI_CAP_CLASS = {"terrain": 400, "folk": 600, "nature": 800, "building": 2500}
TRI_CAP_DEFAULT = 800

# Both spellings of a declaration are accepted: the ASSET dict, and flat
# module-level constants. The dict is preferred in new files.
CONST_KEYS = ("CLASS", "FAMILY", "VARIANT", "CATEGORY", "FOOTPRINT", "ANCHOR",
              "SLOTS", "TRI_CAP", "SCHEME", "PARAMS")
DECL_KEYS = ("cls", "family", "variant", "category", "footprint", "anchor",
             "slots", "tri_cap", "scheme", "params")

_CACHE = {}


def _load_module(path):
    name = "asset_" + os.path.splitext(os.path.basename(path))[0]
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _declaration(mod):
    decl = dict(getattr(mod, "ASSET", {}) or {})
    for ck, dk in zip(CONST_KEYS, DECL_KEYS):
        if hasattr(mod, ck) and dk not in decl:
            decl[dk] = getattr(mod, ck)
    return decl


def _check_declaration(path, mod, decl, seen):
    """Raise SystemExit naming the file and the fix. Never a bare assert."""
    rel = os.path.relpath(path, ASSETS).replace("\\", "/")
    stem = os.path.splitext(os.path.basename(path))[0]
    folder = os.path.basename(os.path.dirname(path))

    if not callable(getattr(mod, "build", None)):
        raise SystemExit("FAIL: %s has no build(tag, **kw). One function is the "
                         "entire interface." % rel)
    for key in ("cls", "family", "variant", "category"):
        if not decl.get(key):
            raise SystemExit("FAIL: %s declares no %s." % (rel, key))
    if decl["variant"] != stem:
        raise SystemExit("FAIL: %s declares variant=%r but the file is named "
                         "%r. The filesystem is the uniqueness guard, so they "
                         "must agree." % (rel, decl["variant"], stem))
    if decl["category"] != folder:
        raise SystemExit("FAIL: %s declares category=%r but sits in %r."
                         % (rel, decl["category"], folder))
    if decl["cls"] not in CLASSES:
        raise SystemExit("FAIL: %s declares cls=%r; known classes are %s."
                         % (rel, decl["cls"], ", ".join(CLASSES)))
    if vocab.FAMILIES and decl["family"] not in vocab.FAMILIES:
        raise SystemExit(
            "FAIL: %s declares family=%r, which is not in the closed "
            "vocabulary. Reuse an existing family and take a fresh variant if "
            "one fits; otherwise regenerate with `build.py -- vocab`.\n"
            "  known: %s" % (rel, decl["family"], ", ".join(sorted(vocab.FAMILIES))))

    fp = decl.get("footprint")
    if not (isinstance(fp, (tuple, list)) and len(fp) == 2):
        raise SystemExit("FAIL: %s declares footprint=%r; it must be (x, y) in "
                         "metres." % (rel, fp))

    key = (decl["family"], decl["variant"])
    if key in seen:
        raise SystemExit("FAIL: %s and %s both declare (family=%r, variant=%r). "
                         "The pair must be unique."
                         % (rel, seen[key], key[0], key[1]))
    seen[key] = rel


def asset_id(decl):
    return "%s/%s" % (decl["category"], decl["variant"])


def tri_cap(decl):
    if decl.get("tri_cap"):
        return int(decl["tri_cap"])
    return TRI_CAP_CLASS.get(decl["cls"], TRI_CAP_DEFAULT)


def discover(verbose=False):
    """{asset_id: {"path", "module", "decl", "build"}} over the whole tree."""
    if _CACHE and not os.environ.get("LAMB_NO_REGISTRY_CACHE"):
        return _CACHE
    if not vocab.FAMILIES:
        print("[VOCAB] OPEN - src/vocab.py is empty, so any family name is "
              "accepted. Run `build.py -- vocab` once the asset set settles; "
              "verify.assert_names fails the sweep until you do.")
    found = {}
    seen = {}
    for dirpath, dirnames, filenames in os.walk(ASSETS):
        dirnames[:] = [d for d in dirnames if not d.startswith("_")]
        for fn in sorted(filenames):
            if not fn.endswith(".py") or fn.startswith("_"):
                continue
            path = os.path.join(dirpath, fn)
            mod = _load_module(path)
            decl = _declaration(mod)
            _check_declaration(path, mod, decl, seen)
            aid = asset_id(decl)
            found[aid] = {"path": path, "module": mod, "decl": decl,
                          "build": mod.build}
            if verbose:
                print("  %-24s %-8s %s" % (aid, decl["cls"], decl["family"]))
    _CACHE.clear()
    _CACHE.update(found)
    return found


def resolve(aid):
    """One asset by "Category/variant". Raises naming the near misses."""
    all_assets = discover()
    if aid in all_assets:
        return all_assets[aid]
    near = [k for k in all_assets if aid.lower() in k.lower()]
    raise SystemExit("FAIL: no asset %r.%s"
                     % (aid, ("\n  did you mean: " + ", ".join(sorted(near)))
                        if near else "\n  known: "
                        + ", ".join(sorted(all_assets)) if all_assets
                        else " The assets tree is empty."))
