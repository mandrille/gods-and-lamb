---
name: lamb-engine
description: The Gods and Lamb Godot half — godot/ project settings, the GLB library loader, vale_builder.gd, the light rig, followers, scenes, tools and export presets. The project EXISTS as of 2026-08-31 and runs: it builds the Vale from data/vale.json plus a 27-asset GLB library, lights it, and walks rigged followers along paths. Use for "the GLB imports with no metadata", "instance the library", "set up the web export", "the headless test fails", or any GDScript work. Not for Blender-side geometry or the asset gate (lamb-pipeline).
---

Read `C:\Goliath\Gods and lamb\AGENTS.md` first. Then this.

You own `godot/`. Godot **4.7**, renderer **GL Compatibility**, portrait first.

Two parent projects to read before writing something new:

- `C:\Goliath\Robotin\godot` — the glTF-extras bridge, the post-import script,
  the headless tool pattern, the screenshot harness, FX pooling, JSON
  persistence. It has no web export, no Android, no theme and no touch input.
- `C:\Goliath\GoliathRogue` — the shipping half: Web / itch / CrazyGames /
  Android export presets, mobile stretch settings tuned against real handsets,
  autoloads. Its `project.godot` comments carry the measurements.

## Compatibility is not a preference

Godot web export runs the Compatibility renderer only — Forward+ is Vulkan and
browsers get WebGL2. Do not "upgrade" the renderer. The parent project runs
Forward+ and asserts it in its test suite; we assert the opposite, for the same
reason: somebody will otherwise change it and lose the platform.

Consequences you inherit: no volumetric fog, no SSAO, no SSIL, clamped
emissives. Contact shading arrives as vertex colour baked in Blender.

## The bridge

Assets arrive as one `.glb` per asset in `godot/assets/library/`, carrying
`lamb_class`, `lamb_family`, `lamb_variant`, `lamb_id`, `lamb_footprint`,
`lamb_anchor`, `lamb_slots` in glTF `extras`.

- **Never key on node names.** Godot `validate_node_name()` rewrites `.` `:` `@`
  `/` `%` to `_`, so an authored `TERRAIN.ground.grass` arrives as
  `TERRAIN_ground_grass`. Key on `get_meta("extras")`.
- **A brand-new `.glb` must be imported twice.** Godot writes the `.import`
  sidecar on the first pass and only then can attach the post-import script.
  The Blender build post-patches the sidecar so this is handled rather than
  remembered — if you see metadata-free imports, check that first.
- There are **no colliders**. Nothing in this game has physics. If you find
  yourself writing a `StaticBody3D`, stop and ask why.

## Terrain is MultiMesh

Hundreds of ground tiles as separate nodes is the most likely way to kill a
mobile browser. `village_builder.gd` fills one `MultiMeshInstance3D` per tile
type and writes **per-instance colour**, which carries neighbour-aware
darkening: a tile with taller neighbours gets tinted down. Baked vertex AO
handles shading *within* a piece; instance tint handles *between* pieces,
because an instanced mesh cannot know what is beside it.

## Tools

Every CLI tool is `extends SceneTree`, reads args from
`OS.get_cmdline_user_args()` (everything after a bare `--`), prints
`[TAG] label ... ok/FAIL`, and calls `quit(0)` or `quit(1)`.

Screenshot tools are **not** `--headless` — `get_root().get_texture()` needs a
real swapchain. Two mechanisms make them trustworthy, both lifted from the
parent project:

- `ShotWindow.park()` sets `WINDOW_FLAG_NO_FOCUS` and moves the window to
  (-6000, -6000). It still renders; it never steals focus or covers anything.
- **The stale-frame guard.** Byte-compare each capture against the previous one.
  Two frames from different cameras cannot be bit-identical, so a repeat means
  the swapchain never presented. Refuse to write and fail the run. Without this,
  roughly half of all shot runs in the parent project silently wrote copies of
  one frame — and a failed run looked exactly like a good one, so the shots got
  reviewed, believed and reasoned from.

## Persistence

`user://` JSON, `JSON.stringify` out and `JSON.parse_string` in with a type
guard. No `Resource`, no custom binary, no version field to forget to bump. The
Faith ledger is `add` / `can_afford` / `spend`, and `spend` is all-or-nothing —
check before you deduct. `user://` maps to IndexedDB in a web export, so this
works unchanged there.


## The project, and how a change gets from Blender to a running frame

```
blender ... build.py -- export          # 27 GLBs + data/vale.json
godot --headless --path . --import      # TWICE for a brand-new .glb
godot --headless --path . --script res://tools/vale_test.gd
godot --path . --resolution 1600x1000 --audio-driver Dummy       --script res://tools/shots.gd     # NOT headless: needs a swapchain
```

| file | what it owns |
|---|---|
| `scripts/vale_builder.gd` | reads `data/vale.json`, ground through MultiMesh, props instanced |
| `scripts/vale_light.gd` | the game rig, and it MIRRORS `blender/src/lit.py` |
| `scripts/follower.gd` | path walking plus the walk clip |
| `scripts/vale_root.gd` | assembles all of it at runtime |
| `tools/vale_test.gd` | renderer, layout, library completeness, skin + clip |
| `tools/shots.gd` | screenshots, with a stale-frame guard and photometrics |

The layout is DATA, not a baked scene, and the same file drives the Blender
look-dev render. Two copies of a village layout is two villages, and the one
you are not looking at is the one that drifts.

`vale_light.gd` exists to be the same rig `lit.py` renders with. A number that
differs there makes every look-dev render a lie. The sun transfers exactly:
Blender divides irradiance by pi and Godot does not, so `lit.py`'s SUN energy
of pi is `light_energy = 1.0`, and 3.6 degrees of angular size carries across
unchanged.

## Traps this half has already paid for

- **`Camera3D.fov` is VERTICAL; a Blender lens is horizontal.** Setting one
  from the other made the Godot shot far wider than the render it was supposed
  to match -- wide enough to see past the edge of the map. Set
  `keep_aspect = KEEP_WIDTH` and then 35 mm means 35 mm in both.
- **The play camera never sees the horizon.** It is pitched down about 35
  degrees with an 18-degree half-FOV, so everything past the edge of the map is
  the sky's GROUND hemisphere, not its blue. At the stock dark grey that reads
  as a black void and looks exactly like the sky failed to render. It is a hazy
  meadow green now.
- **A `class_name` from a sibling tool is not in the global cache on a
  `--script` run.** `preload()` it.
- **`max()` returns Variant**, so `var x := a / max(b, 1)` will not infer a
  type and is a parse error. Annotate or cast.
- Structural changes inside an instantiated sub-scene are NOT serialised, which
  is why everything is built in `_ready()` and `vale.tscn` is four lines.

## Traps that have cost real time here

- **Structural changes inside an instantiated sub-scene are not serialised.**
  Build behaviour at runtime in `_ready()` via `_build.call_deferred()`, not at
  scene-build time. Deferred because Godot refuses `add_child` while the parent
  is still setting up children.
- **`amount_ratio`, never `amount`,** on any `GPUParticles3D` — changing
  `amount` reallocates GPU buffers, which is the exact cost pooling exists to
  avoid.
- Android back quits the app by default. `config/quit_on_go_back=false`, and
  turn the press into `ui_cancel`.
- Stretch `expand`, not `ignore`. A 19.5:9 handset otherwise renders into a 16:9
  box with bars down both sides.

## Your loop

1. Change the GDScript.
2. `godot --headless --path . --import` then
   `godot --headless --path . --script res://tools/village_test.gd`.
3. For anything visual, run the shot tool (not headless) and **open the PNG**.
4. Report the exact commands, their output, and the paths of any PNGs.
