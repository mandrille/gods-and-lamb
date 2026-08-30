---
name: lamb-pipeline
description: The Gods and Lamb build infrastructure — blender/build.py, registry, harness, assetbuild, assetexport, export_gltf, exportkit, verify* and the gate. Use for "the gate is wrong", "add a check", "the export lost its metadata", "asset discovery does not see my file", or any work on the machinery rather than on geometry. Not for asset geometry (lamb-terrain, lamb-building, lamb-nature, lamb-folk) or the Godot side (lamb-engine).
---

Read `C:\Goliath\Gods and lamb\AGENTS.md` first — shared rules, the fast loops,
and the reporting format. Then this.

You own the machinery that turns one `.py` per asset into one `.glb` per asset,
and refuses to let a broken one through. You do not author geometry.

Most of this is ported from `C:\Goliath\Robotin\blender\src`. Read the original
before rewriting something: `registry.py`, `harness.py`, `assetbuild.py`,
`assetexport.py`, `export_gltf.py`, `verify.py`, `verify_export.py`,
`verify_guards.py`, `timing.py`. It is ~6,800 lines of art-style-agnostic
pipeline and it works.

## The contract you enforce

```python
CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(cls=, family=, variant=, category=CATEGORY,
             footprint=(x, y), anchor="floor", slots=())

def build(tag, **kw):   # parts at the ORIGIN, standing on z=0, flat list back
```

- `variant` must equal the filename; `category` must equal the parent folder.
  The filesystem is the uniqueness guard.
- Modules starting with an underscore are excluded from discovery — that is how
  shared helpers live inside the asset tree.
- Triangle caps by `cls`: terrain 400, folk 600, nature 800, building 2500.
  Caps fail the build and name the offender.

## The four things that make the gate worth having

1. **`assert_no_orphans` runs first.** Every other check filters to tagged
   objects, so an untagged mesh is not "allowed" — it is unseen. In the parent
   project a merged pipe run lost its tag, drifted through a character, and the
   build printed `assert collisions OK`.
2. **The gate-coverage contract.** Every `assert_*` must appear in exactly one
   of `PER_ASSET` / `SWEEP_ONLY` / `NEVER_PER_ASSET`, and `assert_coverage()`
   fails the build when a new assert appears in neither. A per-asset gate weaker
   than the sweep just relocates the problem it was meant to prevent.
3. **The collect-all gate.** `begin_collect()` / `soft(fn, ...)` /
   `flush_collect()` reports every failure in one run. Only the arithmetic class
   opts into `soft()`; names, soften and mesh quality stay fail-fast, because a
   build broken at that level turns one true report into ten junk ones.
4. **Negative controls.** `build.py -- guards` proves the guards still bite, and
   checks the message text, not merely that something raised. An assert that has
   never been proven to fire is not evidence.

## Traps that have cost real time here

- **Blender exits 0 on an uncaught Python exception**, and it catches
  `SystemExit`. `build.py` installs `sys.excepthook = _die_loudly`, which prints
  the traceback then calls `os._exit(1)`. Without this the CI is decorative.
- **Redirected stdout is block-buffered**, so a slow build and a hung build look
  identical. `timing.unbuffer()` runs immediately after the `sys.path` insert.
- **`export_extras` defaults to False.** The obvious export call writes a valid,
  plausibly sized GLB containing none of the `lamb_*` data, with no warning of
  any kind. `verify_export.assert_glb_readback()` reopens the file, parses the
  JSON chunk, and fails if no node carries `extras.lamb_id`.
- **One process per asset, always.** `kit.M`, `kit.STATS` and `kit.SCHEMES` are
  mutable module globals; cross-contamination presents as a geometry bug, and
  you will not suspect the build system.
- **`calc_loop_triangles()` counts the base mesh**, not the modifier result. An
  unapplied Bevel is invisible to it — 4.9x understated in the parent project.
  Count through `kit.evaluated_tris()`.
- **A render that succeeds and is empty looks exactly like one that worked.**
  `assetbuild.judge()` gates on luma-sd, edge density and subject fraction, and
  `_sightline()` raycasts because projection is not visibility — a bounding box
  projects perfectly well from behind a wall.
- Every path resolves from `__file__` so the project can be moved. Output root
  overrides via `LAMB_GODOT_ASSETS`.

## Your loop

1. Change the machinery.
2. `-- guards` — prove the negative controls still fail for the right reason.
3. `-- asset <id>` on a known-good asset, then on a deliberately broken one.
4. Report the exact commands and their output. Paste the numbers.
