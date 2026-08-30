# Blender gotchas (Blender 5.2, scripted via bpy)

Every entry here cost real debugging time and produced a visibly wrong result
first. They are ordered by how likely they are to bite you.

---

## 1. Bevel must come AFTER every boolean

Bevelling first tears the cut edges. `box()` and `cyl()` in `kit.py` deliberately
produce **sharp** geometry; rounding is a separate pass at the end of each
builder:

```python
def press(...):
    ...                      # all geometry + all booleans
    soften_all(P, width=0.038)
    return P
```

`soften_all` clamps bevel width to 25% of a part's smallest dimension and skips
parts too thin to survive (posters, floor markings), so nothing collapses.

## 2. Weighted Normal and "Smooth by Angle" cannot coexist

This one is subtle and cost the most time.

- `bpy.ops.object.shade_auto_smooth()` in Blender 4.1+ **adds a geometry-nodes
  modifier** named `Smooth by Angle`.
- That modifier is **pinned to the end of the stack**. `modifiers.new()` inserts
  *before* it, and `modifiers.move()` **reports success while silently leaving it
  last**. Verified:

```
pre-move : ['BEVEL', 'WEIGHTED_NORMAL', 'NODES']
move() ok
post-move: ['BEVEL', 'WEIGHTED_NORMAL', 'NODES']   <- unchanged
```

- A Weighted Normal that is not last does nothing — whatever runs after it
  recomputes the normals it just wrote.

**Fix:** for meshes that get WN, remove `Smooth by Angle`, shade the mesh fully
smooth, then add WN. That is the standard hard-surface stack anyway:

```
Bevel  ->  Weighted Normal        (mesh fully smooth-shaded)
```

Large flat faces still read flat because Face Area weighting dominates; bevels
become tight highlights instead of gradients. See `kit.weighted_normals_all`.

**Settings used** (match Blender's default panel): Face Area, weight 100,
threshold 0.01, Keep Sharp off, Face Influence off.

## 3. Procedural texture nodes ignore your UVs unless you wire them

`ShaderNodeTexBrick`, `TexNoise`, `TexWave` etc. default to **Generated**
coordinates — the object's normalised bounding box. On a wall that stretches into
vertical stripes no matter how good the UVs are. Unwrapping alone changes
nothing.

You must wire it explicitly: `TexCoord.UV -> Mapping -> node.Vector`.

## 4. `smart_project` rotates islands; use `cube_project` for aligned patterns

Smart project rotates each UV island independently, which stands brick courses on
end. For axis-aligned architectural patterns use:

```python
bpy.ops.uv.cube_project(cube_size=1.0, scale_to_bounds=False)
```

UVs come out in world units, so scale is consistent across every face and courses
stay horizontal.

## 5. AgX desaturates — wrong for flat/stylised work

Blender's default view transform is AgX, which is correct for photoreal and
crushes saturation on flat-colour work. For stylised or pixel output:

```python
scene.view_settings.view_transform = "Standard"
```

Keep AgX for the photoreal path and control exposure instead.

## 6. Posterise in perceptual space, not linear

Blender's pixel buffers are **linear**. Rounding there puts almost every midtone
on a step boundary (sRGB 0.5 is only linear 0.21), so tiny shading variation flips
neighbouring pixels between levels and flat faces come out **mottled**.

Convert to sRGB, quantise, convert back. See `posterize()` in the pixel-art
pipeline notes. Related: area lights fall off with distance, so a single wall
carries a gradient — for flat posterised output use **SUN** lights with shadows
off, and every flat face resolves to exactly one value.

## 7. `Action.fcurves` is gone in Blender 5.x

Slotted actions replaced it. Walk the new structure:

```python
for layer in action.layers:
    for strip in layer.strips:
        for cbag in strip.channelbags:
            for fc in cbag.fcurves: ...
```

## 8. Resolve the EEVEE engine id, never hardcode it

The identifier differs across 4.x/5.x (`BLENDER_EEVEE_NEXT` vs `BLENDER_EEVEE`):

```python
ids = [i.identifier for i in
       bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
```

## 9. EEVEE shadow atlas overflows silently

`Shadow buffer full, may result in missing shadows (2221/2048)`. Each
omnidirectional **point** light costs six shadow faces. `shadow_pool_size` maxes
out at `"2048"`, so raising it cannot fix it — **halve the casters** instead:

```python
for i, ob in enumerate(lamp_lights):
    ob.data.use_shadow = (i % 2 == 0)
```

## 10. `screen.screenshot()` captures a stale buffer

If the window has not actually redrawn, you get a **pure black frame** and no
error. In one run 6 of 7 shots were black. Two defences, both in `src/shots.py`:

```python
bpy.ops.wm.redraw_timer(type="DRAW_WIN_SWAP", iterations=12)
bpy.ops.screen.screenshot(filepath=path)
# then verify: load the PNG and require pixel spread > 0.05
```

Heavy scenes need long settle times — with ~700 modifier stacks, every visibility
or shading change forces a full re-evaluation and the viewport needs tens of
seconds. `redraw_timer` reporting `0.009 ms` means it drew nothing.

## 11. Viewport camera azimuth

`view_rotation = Euler((rx, 0, rz))` puts the camera at

```
offset = d * (sin rx * sin rz,  -sin rx * cos rz,  cos rx)
```

Getting the sign backwards puts the camera outside the building looking at a
blank wall. To look **west** (toward -X) the camera must be at +X, so `rz > 0`.

## 12. Solve camera distance, don't guess it

A 95 mm lens needs ~29 units of standoff for a 3.4-unit subject — not a number
anyone picks by eye. Project the subject's bounding box with
`bpy_extras.object_utils.world_to_camera_view` and iterate distance until it fills
the target fraction of frame. See `character.py`.

## 13. Aim with track quaternions

Hand-rolled Euler aiming produces empty renders. Always:

```python
ob.rotation_euler = (target - ob.location).to_track_quat("-Z", "Y").to_euler()
```

## 14. A volume domain shows its own box

A bounded volume cube fogs only the hall — good — but viewed from **outside**,
its boundary reads as a glassy plane. Keep wide-shot cameras **inside** the
domain.

## 15. OPTIX kernel compilation looks like a hang

First Cycles render with complex procedural shaders can sit for 10+ minutes,
single-threaded, before rendering. It is compiling and caching kernels — the same
scene renders in ~4 s afterwards. Do not kill it.

## 16. Booleans: EXACT, and pre-join cutters

`FAST` mangles coplanar faces, which is exactly what flanges and slot grills are
made of. Always `solver="EXACT"`.

Join cutters before cutting — a 6-hole bolt circle should cost **one** boolean,
not six. Across six flanges that is 6 booleans instead of 36.

## 17. Build at the origin, place with an empty

Build each assembly at the origin, then parent to an empty and transform that.
Keeps every boolean in a sane local space and makes placement trivial to author.

## 18. Detail placed "just inside" a face disappears

Surface detail must sit at a coordinate **outside** the face plane to protrude.
Combined with a heavy bevel pulling the real surface back, anything placed just
inside vanishes except where the corners curve away — producing floating
I-beam-shaped artefacts instead of panel lines.

## 19. Quartering a torus: the cut planes go THROUGH the centre

Building an elbow by cutting a torus with two half-space boxes, it looks sensible
to offset each cut by the tube radius "so the cut clears the tube". It does not:
it keeps roughly **132 degrees** of arc instead of 90. The extra material sticks
out past both end caps, and every downstream piece in a chain visibly fails to
meet its neighbour.

The cut planes must pass exactly through the torus centre. At each quarter end the
arc tangent is perpendicular to its cut plane, so the plane slices the tube
precisely through its circular end cap - which is what makes a socket sit flush.

Verify numerically rather than by eye. For a bend with inlet at the origin flowing
+X and outlet at `(R, 0, R)` flowing +Z:

```
arc vertices must satisfy   x >= 0        (nothing behind the inlet cap)
                            z <= R        (nothing past the outlet cap)
                            max(z) == R   (it actually reaches the cap)
```

Note the inlet cap contributes `x == 0` exactly - the tube's cross-section there
lies in Y/Z, so it never extends to negative X. Expecting `x >= -r` is a wrong
test that fails a correct bend.

Related, same family of mistake: a bend's **centre of curvature is perpendicular
to the flow at the inlet**. For an upward bend that is `(0, 0, R)`, not
`(R, 0, 0)`; the latter gives a piece whose inlet tangent is vertical.

## 20. Offset mounting hardware perpendicular to its run

Brackets carrying a pipe must step **along** the run and offset **perpendicular**
to it, toward the host surface. Offsetting along the run - the obvious mistake
when you already have the run direction to hand - just slides them down the pipe
and leaves them floating off the wall. Their rotation matters too: the mount face
has to point *at* the surface, so it is `rot + 90`, not `rot - 90`.

## 21. Merge props to one mesh - and mind the modifier order when you do

A prop is authored as many primitives because booleans need them separate. A game
wants one mesh per prop. `kit.merge_group()` collapses everything under a prop
root into a single object: **774 mesh objects became 75**.

`join()` keeps only the ACTIVE object's modifiers and silently discards the rest,
so modifiers must be baked with `convert(target='MESH')` *before* joining.
Weighted Normal is then added once per merged mesh, after the join.

Two things this breaks, both fixable:

- **Part-level `rb_provides` disappears.** Freeze the surface as data
  (world-space top Z + XY rect) onto the prop root *before* merging - see
  `rules.capture_surfaces`.
- **`ob.location` stops meaning what you think.** Re-parenting makes local
  coordinates relative to the merged mesh, so a perfectly grid-aligned object
  reads as off-grid. Grid checks must use `matrix_world.translation`.

## 22. An unapplied Bevel is invisible to `calc_loop_triangles()`

`ob.data.calc_loop_triangles()` counts the **base mesh**, not the modifier
result. With an unapplied Bevel that understates real geometry badly - measured
4.87x on one machine (1,884 base vs 9,180 evaluated). Reported poly counts were
wrong by that factor until merging baked the modifiers and made it visible.

To count what actually renders:

```python
dg = bpy.context.evaluated_depsgraph_get()
m = ob.evaluated_get(dg).to_mesh()
m.calc_loop_triangles()
n = len(m.loop_triangles)
ob.evaluated_get(dg).to_mesh_clear()
```

Bevel segments are the cheapest lever on that count - measured on one machine:

| segments | evaluated tris |
|---|---|
| 3 | 9,180 |
| 2 | 6,316 |
| 1 | 3,776 |

## 23. Bevel angle limit: 30 degrees bevels curvature you never wanted

An ANGLE-limited bevel fires on any edge sharper than the limit. At 30 degrees
that includes the facets of a coarse sphere or torus (~36 degrees on a
10-segment sphere) - so every round primitive got bevelled, adding geometry to
surfaces that had no sharp edge to catch light on.

Measured on one plant: **1,024 base -> 2,296 evaluated tris**, more than doubled,
entirely on foliage spheres and a torus rim.

Set the limit to **50 degrees**. Box corners and cylinder rims are 90 degrees and
still bevel; curvature does not. Scene total fell 329k -> 98k tris with no visible
change to the rounded look.

## 24. Three cheap levers on polycount, in order of value

1. **Bevel angle limit** (see above) - free, removes only waste.
2. **Bevel segments.** 1 segment still catches an edge highlight and costs ~2.4x
   fewer tris than 3.
3. **Skip bevelling small assemblies entirely.** Anything under 1 m gets smooth
   shading only - nobody reads edge rounding on an 11 cm mug next to a 1.2 m
   character. Gate on the ASSEMBLY height, not the part, so a desk's thin shelf
   still rounds with the rest of the desk.

Then enforce it: a per-piece triangle cap that fails the build names the builder
that went wrong, instead of letting one prop quietly eat the budget.

## 25. A screenshot retry must re-apply the view, not just re-capture

`screen.screenshot()` returns a stale black buffer when nothing has been marked
dirty. A retry loop that only calls capture again therefore returns the *same*
black buffer every time - the retries look like they are doing something and
never help.

The retry has to go back through the configure step so the view is re-applied and
`area.tag_redraw()` runs again. Symptom before the fix: three retries, three
identical blanks, then `BLANK`. After: first retry succeeds.

Blank frames are intermittent and get more likely later in a long capture run, so
keep the guard even when a run passes clean.

## 26. An AABB is not a collision test for anything rotated

`ob.bound_box` is in **local** space; transforming its eight corners and taking
the world min/max gives an axis-aligned box that, for a rotated thin prop, is
mostly empty air. Measured on this scene: the broom's AABB is **2.84×** the
volume of its true oriented box, the character's **2.27×**.

Consequence: a collision assert built on AABBs reported OK while three broken
placements were visible on screen. Use AABB as a cheap broad-phase reject only,
then confirm with an oriented box.

An OBB is cheap to derive — the local bound box gives the half-extents, and
`matrix_world.to_3x3().col[i]` gives axis *i*, whose **length is the scale on
that axis**, so normalise the axis and multiply the half-extent by that length.
Forgetting the scale silently produces a box the wrong size on any prop that was
placed with a scale factor.

## 27. SAT needs the nine cross products, not just the six face normals

The separating-axis test for two oriented boxes runs over **15** axes: box A's 3
face normals, box B's 3, and the **9 pairwise cross products** of their edge
directions. Testing only the six face normals is the common shortcut and it fails
on precisely one case — two long thin objects crossing at an angle, neither of
which separates along any face normal. That is a broom through a window frame.

Guard against the degenerate case: when two edge directions are near-parallel the
cross product is near-zero and normalising it produces garbage. Skip any axis
shorter than ~1e-6.

## 28. Prop-vs-prop testing is structurally blind to walls

Collision checks filter to movable classes (`prop`, `small`, `kit`), because
walls and floors are containers rather than obstacles — otherwise every object
resting on the floor is a hit. That filter means **a prop inside a wall is not a
collision as far as the test is concerned**, and neither is a prop poking out
through a window.

The fix is a different question, asked separately: does this prop's box fit
inside a declared interior volume? Rooms must therefore *export* the interior
bounds they already compute internally instead of discarding them as locals.

Two things that bite immediately:

- Declare interiors as a **list** of boxes, and require a prop to fit **at least
  one**. A recessed alcove or an adjacent space is not describable as one box,
  and a single loose box either excludes legitimate geometry or leaks into walls.
- Exempt the families that belong *at* the boundary — poster, notice, clock,
  extinguisher, pipe, bracket, string lights. Otherwise every wall-mounted thing
  fails.

## 29. Clamp before you capture surfaces or merge

Auto-clamping a prop back inside the room has to happen in `_place()` **before**
`capture_surfaces()` freezes world-space flat tops and before `merge_group()`
bakes the hierarchy. Clamp afterwards and the recorded surface rectangles refer
to where the prop used to be.

Two rules that keep clamping from being a lie:

- **Log every clamp.** A silent auto-fix hides an authoring error forever. A
  clamp line means the hand-authored position was wrong and should be corrected
  at source.
- **Never squeeze.** A prop that fits no volume is a hard failure, not something
  to scale down.

And expect clamping to *create* work: pushing a prop off a wall can drive it into
another prop, which the pairwise test then catches. That is the checks composing
correctly, not a bug.

## 30. Deleting a parent TELEPORTS its children

`bpy.data.objects.remove(parent)` does not re-parent children to the grandparent
and does not preserve their world transform. Blender keeps the child's **local**
transform and drops the parent's, so the child silently jumps.

This is the single most expensive bug in the project's history. `merge_group`
left the merged mesh parented to an intermediate piece empty; the caller then
deleted those empties as scaffolding; the merged pipe run jumped from
`(2.10, -1.75, 2.00)` to the origin and came to rest **through the character**,
2.7 m away and 12 cm into the floor. It was reported as a defect three separate
times and "fixed" twice by looking at the wrong pipe.

Two defences, both cheap:

- `merge_group` now re-parents the merged mesh to `root` explicitly, preserving
  `matrix_world`.
- `kit.purge()` replaces bare `objects.remove()` loops and **refuses** to delete
  anything that still has children.

## 31. An untagged mesh is not "allowed" — it is INVISIBLE

Every check in `rules.py` starts by filtering to tagged objects. A mesh with no
`rb_class` and no tagged parent is therefore not checked *at all*: it can
intersect anything, sit anywhere, and the build still reports success.

The teleported pipe above had **a 0.24 m interpenetration with the character**
while `assert collisions OK - no props intersect` printed. It was not a failure
of the collision test; the pipe was never a candidate.

It also silently dodged the polycount cap. `assert_polycount` reads
`rb_class` to pick a cap, so an untagged mesh fell through to the 9000 default
instead of the 3000 `kit` cap — 3640 triangles, unnoticed, until it was tagged.

`verify.assert_no_orphans()` now runs FIRST in both scenes. Anything that can be
built can be tagged; if a merge produces a mesh, tag it (`rules.merge_tagged()`
does merge + freeze part boxes + freeze flat tops + tag in the required order).

## 32. `join()` keeps only the ACTIVE object's custom properties

Everything you stored on the other objects is gone. Three separate systems here
have been bitten by it:

| stored on parts | lost on merge | recovered by |
|---|---|---|
| `rb_provides = flat_top` | the bunk mattress's declared surface | `rules.top_surfaces()` |
| per-part oriented boxes | precise collision geometry | `rules.capture_parts()` |
| `rb_top_z` / `rb_top_rect` | resolved host surfaces | `rules.capture_surfaces()` |

The mattress case is the instructive one: `rooms.py` called
`rl.provide(mattress, "flat_top")` and its docstring claimed "the rules validator
will hold anything placed there". The property was destroyed at merge time, so
the surface did not exist at runtime and the docstring had been wrong for weeks.
**Freeze anything you need onto the object that survives, before the join.**

## 33. A blank-frame guard that measures the whole window measures nothing

`bpy.ops.screen.screenshot()` captures the entire Blender window. A guard that
computes min/max spread over that image scores ~1.0 on the toolbars and
properties panel alone — against a 0.05 threshold — so a **completely dead 3D
viewport passes**. One was delivered to a reviewer as part of "6/6 OK".

Also in that guard: `step` was forced to a multiple of 4 and the range started at
0, so every sample landed on index ≡ 0 mod 4 — **only the red channel was ever
examined.**

What actually works (`shotkit.py`):

- measure only the viewport rect, derived as `image_width / window.width` rather
  than from `pixel_size`, so a HiDPI crop cannot silently slide off;
- use `std(luma)` and mean absolute horizontal gradient, not min/max spread — one
  bright overlay glyph pins spread at 1.0;
- **and do not rely on those metrics alone.** The known-bad shot measured
  `luma_std = 0.050`, `edge = 0.0035` — *above* both floors, because the unlit
  wall it was staring at had a faint gradient. What caught it was a ray cast from
  the eye to the declared subject: `sightline blocked by room_wall_Xneg at
  0.56 m`.

`screenshot_area` looks like the obvious fix and is not: under `temp_override`
in a timer callback it returns an undrawn buffer and writes a correctly-sized,
entirely black PNG every time.

## 34. A timer callback cannot fail a process

Shots run off `bpy.app.timers`, and `tick()` ends with `quit_blender()`. There is
no path from "this shot is bad" to a non-zero exit code, so a blank shot logged
`BLANK` and Blender still exited 0 — the calling script saw success.

Write a manifest and check it in a separate process (`verify_shots.py`), or the
best detector in the world changes nothing.

Related: retry with the shot's **own settle time**. A flat 8 s retry on a view
that needed 60 s to resolve fails three times and wastes three minutes.

## 35. Incommensurate grids will fight each other

Cladding ribs sit every **1.1 m**; prop placement snaps to **0.25 m**. Bay
midpoints are therefore at multiples of 1.1 offset by 0.55, and those coincide
with the placement grid **only at ±2.75**.

Symptom: a notice board authored at the bay midpoint -1.65 snapped to -1.75 and
landed back on a rib. Moving it to -1.55 snapped to -1.50 — onto the rib on the
*other* side. There is no grid point in between.

When two modules of spacing meet, either make one a multiple of the other or
accept that only the coincidence points are usable. Anything wider than about
0.6 m on that wall now goes at ±2.75.

## 36. `export_extras` defaults to FALSE

`bpy.ops.export_scene.gltf()` does not export object custom properties unless you
ask. The resulting GLB is valid, a plausible size, and contains **none** of your
metadata. No warning, no error.

For this project that is every `rb_*` tag, all 706 collision boxes and all 16
socket flags — the entire rules system arriving in the engine as anonymous
meshes. `docs/05-extending.md` recommended exactly that call for weeks.

The only defence is to reopen the file and look: `verify_export.assert_glb_readback()`
parses the JSON chunk and fails if no node carries `extras.rb_class`.

## 37. `export_apply` skips Armatures — `object.convert()` does not

`export_apply=True` bakes modifiers but deliberately **disables Armature
modifiers first** (`io_scene_gltf2/blender/exp/nodes.py`), which is what lets a
rigged mesh export with Bevel and Weighted Normal baked *and* its skin intact.

`bpy.ops.object.convert(target="MESH")` — which `kit.merge_group` uses — has no
such exemption. An Armature added before the merge is **baked into the
geometry**, and you get a T-posed mesh with no skin and no error.

So: rig *after* merging, never before.

## 38. Armature first, WeightedNormal last — the stack order is forced

Two existing invariants collide on the character mesh:

- `kit.weighted_normal_coverage` asserts WN is the **last** modifier;
- the Armature must exist but must not be baked by the merge.

The only stack that satisfies both is `[Armature, WeightedNormal]`, built by
adding the Armature **after** `assert_weighted_normals` (which is what adds WN
and moves it last) and then `modifier_move_to_index(index=0)`.

`verify.assert_rig()` checks both ends of the stack and that no vertex is in
zero groups — an unweighted vertex stays behind at the origin while the rest of
the mesh walks away.

## 39. A count is not coverage

The Godot import log read `73 tagged, 66 bodies`. Every assert passed. The
character fell straight through the floor on the first frame.

The shell — floor, four walls, ceiling — is tagged **directly** rather than
through `_place()`, so it never received `rb_part_*`, so it exported with no
collider at all. Seven missing bodies out of seventy-three looked like a
rounding detail in a log line nobody read as a failure.

Two fixes, and the second is the general one:

- `rules.local_boxes()` falls back to the object's own oriented box when no
  parts were captured (exact for the shell, which *is* boxes);
- `verify_export.assert_collision_coverage()` requires **every** non-`NON_BLOCKING`
  tagged mesh to have at least one box.

The wider lesson is the reason `playtest.gd` exists: colliders that are mirrored,
in the wrong space, or a hundred times too big all import cleanly and all pass a
count. Walking through the space is the only test that exercises scale,
placement, handedness and gravity at once.

## 40. Two coordinate conversions, and the second is invisible

Anything computed in Blender space and handed to an engine needs **both**
world→local *and* **Z-up→Y-up: `(x, y, z) → (x, z, −y)`**.

The exporter swizzles every vertex and every node's local TRS, not just the root
(`primitive_extract.zup2yup`). Skip the second conversion on data you compute
yourself and the render is pixel-perfect while the collision is mirrored — you
bounce off thin air on one side of a room and walk through the wall on the other.

Do it in Python, not GDScript, so it can sit under a selftest that round-trips a
box and **rejects a deliberately reflected basis** (determinant −1). A handedness
bug is invisible in screenshots by construction.

## 41. Godot rewrites node names; set `owner` only once in the tree

Two small ones that cost an hour each:

- `String::validate_node_name()` replaces `. : @ / " %` with `_`, so
  `PROP.machine.press` arrives as `PROP_machine_press`. **Never key on node
  names** — key on `get_meta("extras")`. Material *resource* names are not
  sanitised, so matching on those is safe.
- A node's `owner` must already be an ancestor. Building a subtree detached and
  setting `owner` before `add_child` fails on every node with
  `Invalid owner. Owner must be an ancestor in the tree.`

## 42. An EXACT boolean is topologically correct and cosmetically filthy

Correct output is not clean output. Measured across the workshop before anything
cleaned up after it:

```
42,859 faces:  1297 ngons   64 degenerate faces   224 duplicate verts
                            102 zero-length edges
```

Each class hurts differently:

- **degenerate faces** (area ≈ 0) have no usable normal, so they shade as specks
  *and* poison the area-weighted normal of every face touching them;
- **duplicate verts and zero-length edges** appear where a cut lands on an
  existing vertex, and split the shading there;
- **ngons** are the sneaky one — Blender and the engine triangulate them
  differently, so the mesh shades one way in the viewport and another in game.
  That is the "but it looked fine in Blender" artifact.

`kit.clean_mesh()` runs at the cut **and** at the merge. Not retopology: remeshing
would destroy the crisp machined silhouette and the single-segment bevel
highlights, and cost triangles doing it. Booleans leave *rubbish*, and rubbish
gets removed. Cost of the fix: **+2% triangles** (97,234 → 99,189).

## 43. Clean at the CUT, not only at the merge

Most geometry here is merged later and would be cleaned then — but the shell is
not. The floor and the four walls are tagged directly and never merged, so they
kept every ngon their drain and window cuts produced. Cleaning inside `boolean()`
covers both paths and stops debris from one cut feeding the next.

## 44. Cleanup passes create work for each other — iterate to a fixed point

Two ops, and each makes work for the other:

- splitting a non-planar ngon produces **slivers** of its own;
- collapsing a sliver's edge can fuse neighbouring triangles back into an **ngon**.

Running one pass of each left 4 degenerate faces per column. Running them in the
other order left 30 ngons per column. The artifact was being produced *by the
step meant to remove artifacts*. Loop until neither finds work.

Two more specifics worth keeping:

- **Slivers are not welded away.** Three near-collinear verts have long edges, so
  no distance-based `remove_doubles` touches them. Collapse the shortest edge.
- **Do not use `dissolve_limit` for them.** It removes them, and it also
  dissolves every coplanar triangle back into an ngon along with them.

## 45. Weld distance has to clear the sliver, not just the duplicate

At `1e-5` the duplicates went and 14 sliver faces survived on one machine — edges
long enough to dodge the weld, area near enough zero to have no normal. `1e-4`
(0.1 mm) clears them. Everything here is authored in metres and the thinnest
deliberate feature is a 4 mm bevel, so 0.1 mm cannot destroy anything intended.

## 46. Non-manifold is not automatically damage — classify it before "fixing" it

After cleanup the workshop reported 95 non-manifold edges where the source had 0,
which looks exactly like collapse punching holes. It is not. Counting faces per
edge: **91 edges with 3 faces, 4 with 4 faces, and none with 1.**

- **1 face** = a boundary = a genuine hole. Leaks light and shadow. There are none.
- **3+ faces** = a T-junction where welding fused parts that touch — a pipe
  collar's rim meeting the tube it rides on. That is the ordinary cost of merging
  a multi-part prop and welding it.

Two lessons. `assert_mesh_quality` reports non-manifold rather than failing on it,
because failing would demand the pipe kit stop working. And I wrote "pipe bores"
into a log line and a code comment as the explanation before measuring — it was
wrong, and a wrong comment is worse than none.

## 47. Weighted Normal without a bevel MELTS the mesh

The standard hard-surface stack — drop Smooth by Angle, shade fully smooth, let
Bevel + Weighted Normal control the normals — is only correct **where there is a
bevel**. Here there often is not:

- assemblies under `BEVEL_MIN_HEIGHT` (1 m) get no bevel at all;
- parts too thin to bevel are skipped *inside* assemblies that do get one.

So a merged prop is routinely a mix, and shading all of it smooth melts every
unbevelled 90° corner — while also undoing the angle-based shading `soften()` had
just applied.

The fix is one threshold and one flag. Mark edges sharper than **60°** as sharp,
then set `keep_sharp=True`:

| edge | angle | outcome |
|---|---|---|
| single-segment bevel | ~45° | stays smooth — the highlight survives |
| unbevelled box corner | 90° | stays crisp |
| sphere / torus facet | 15–36° | stays smooth |

60° is load-bearing: a 1-segment bevel turns one 90° corner into two ~45° edges,
so the threshold has to sit between them. Mark on the FINAL merged geometry,
where the bevel is already baked and the two cases are simply different angles.

---

## 48. Two overlapping boxes must not share a face PLANE

Interpenetration is fine — it is how every merged prop is built. What is not fine
is two faces landing on the SAME plane. `join()` keeps both, and `clean_mesh`'s
weld plus `recalc_face_normals` then has to pick one; on a non-manifold union it
picks wrong and you get a black patch that is a real hole, not shading.

The shell kit's portal frame produced a 0.16 x 0.16 m black square at both top
corners of every doorway, portal and portal_shut. The jamb's top face sat at
`z1 + 0.08`; so did the head's.

Moving the jamb 40 mm into the head fixed the top plane — and the square came
straight back on the architrave, because head and jambs were both `T + 0.08` deep
and still shared their FRONT and BACK planes. Different DEPTHS, not just different
heights:

    jamb_p, head_p, lip_p = 0.045, 0.059, 0.075

Sharing a plane with something you rest against (skirting on a wall) is fine —
that is face-to-face contact, not two volumes interpenetrating.

---

## 49. `join()` is not a merge — and that is what z-fighting is

`kit.merge_group` finishes with `join()`, which puts many objects into one mesh but
does not resolve them. Two boxes that interpenetrate still carry all four of their
original faces; where two land on one plane the renderer has no depth order and
they flicker. It is not a shading bug — it is two surfaces genuinely occupying one
plane.

Boolean UNION removes the interior faces and leaves one manifold shell. The tell is
in the build output:

    assert mesh quality OK - ... 0 welded T-junctions, 0 holes

A joined prop reports dozens of T-junctions; a welded one reports none.

Cost is 2-3x triangles, because every intersection buys an edge loop — the
container set went 412 -> 1122 (tote) and 296 -> 842 (strongbox). So weld only what
actually shares a plane. The shipping crate cost 1634 fully welded, over the 1200
cap, but 416 when only the posts, top boards and braces were unioned: a slat
passing THROUGH a post has nothing to fight about. Free-standing contents share no
surface at all and should stay out of the weld entirely.

---

## 50. Boolean UNION silently repaints — unify material slots first

A boolean operand carries its own one-entry material slot list, and the modifier
has to remap that index into the target's list. When the lists disagree, faces
arrive on the wrong slot.

Measured on the strongbox: after welding, the brass dial's `Butter` slot was still
present in the merged mesh with ZERO faces on it, and the dial rendered in the body
colour. The `.asset.json` material list still said "Butter", because a slot
EXISTING and a slot BEING USED are different things. That is why this is caught by
counting faces per material, not by reading the sidecar or trusting the render:

    for p in me.polygons:
        n[me.materials[p.material_index].name] += 1

Fix: before any union, give every operand the same slot list and remap each face
index into it. See `_boxkit._unify_materials`.

---

## 51. Rotate about the HINGE, not about the centre

`box(name, centre, size, rot=...)` rotates about the part's own centre. For
anything hinged that is the wrong pivot, and half the part swings into whatever it
is hinged to.

Carton flaps placed on the rim edge and rotated 64 degrees buried 95 mm of every
flap inside the box, through the contents and through each other. Tilting them the
other way does not help — it moves the buried half to the outside.

Solve the centre from the hinge:

    centre = hinge + (length / 2) * direction

with the rotation set to whatever aligns the part's long axis with `direction`.
Same fix for the flight-case lid, and for the wheelbarrow and sack-truck grips,
which floated in mid-air 140 mm off the ends of their raked handles.

---

## 52. A rotated box is TALLER than its own z size

Half its length rotates into z as well:

    reach = length / 2 * cos(theta) + width / 2 * sin(theta)

A 0.26 m strut at 40 degrees centred at z = -0.085 reaches z = +0.026. The wall
shelf's diagonal brackets surfaced through the shelf board and rendered as two
white specks sitting on the top surface.

---

## 53. A torus at its host's radius is buried — and a squashed sphere's radius at z is not R

`sphere(r, squash=s)` scales z, so the horizontal radius at height `dz` from the
centre is `r * sqrt(1 - (dz / (r * s))**2)`, NOT `r`.

The helmet's brim torus was major 0.179 against a shell whose radius at that height
was 0.183, so it sat just inside and surfaced only where the facets bulged past it:
a sawtooth all round the rim. The glove's cuff band had the same bug against a
plain cylinder.

Use a short wide CYLINDER, wider than the host's widest point. It cannot scallop at
any height, and it is cheaper than a torus.

---

## 54. Tapered walls leaning on different axes cannot meet at a corner

Each wall is square to its own base edge, so a box with 7 degrees of draft leaves a
V-shaped slot at every corner that you can see daylight through. A corner post
leaning on BOTH axes at once fills it exactly:

    rot=(-sy * LEAN, sx * LEAN, 0)

Real mouldings are thickened at the corners for the same reason.

---

## 55. Near-tangent overlaps triangulate into slivers under UNION

Stacking rotated boxes to fake a slope is survivable while they stay separate
objects and disastrous once they are unioned: a shallow-angle intersection has no
clean edge loop and comes out as slivers.

The parts bin's sloped side was a full-height rear panel, a 28-degree raked step
and a low front panel. Rebuilt as ONE panel with a single boolean cut it is one
straight edge — and it got cheaper, 330 -> 260 triangles.

Cut the shape you want; do not assemble it out of overlapping wedges. A useful
side effect: a cut plane extrapolated past the material removes nothing, so one
cutter can slope the front of a panel and leave the rear at full height for free.

---

## 56. Blender exits 0 on an uncaught Python exception

`--background --python foo.py` returns 0 even when the script dies with a
traceback. Any guard built on `subprocess.run(...).returncode` is therefore not a
guard.

`build_vocab` runs `-- all` in a child and regenerates `src/vocab.py` from what that
build recorded, on the documented promise that the vocabulary is only regenerated
from a GREEN build. When `scene.py` crashed partway through, the child still
returned 0 and the vocabulary was rewritten from a partial recording: `bracket`
vanished from FAMILIES along with `robotin`, `room`, `lamps`, `bend90`, `bendS` and
the three `straight_*` variants.

Scan the child's stdout and stderr for `Traceback` as well as checking the return
code. Same class of failure `verify_shots.py` already exists to defend against on
the shots side — a timer callback cannot fail a process either.

---

## Environment notes

- **winget's `BlenderFoundation.Blender` treats an older Blender as an upgrade
  and uninstalls it.** It removed a 3.5 install. The `.LTS.x.y` package ids
  install side by side safely.
- The **official Blender MCP server** declares an unbounded `mcp[cli]>=1.2.0`
  which now resolves to mcp 2.x; that dropped `mcp.server.fastmcp` and the server
  will not import. Pin `<2`. It also refuses to start unless Blender's
  `system.use_online_access` is True.

---

# Gods and Lamb additions

Entries below were paid for in THIS project. The numbering continues from the
inherited list only loosely -- what matters is that each one produced a visibly
wrong result first.

## 57. Workbench shades from `material.diffuse_color`, not the Principled node

`kit.flat()` sets the Principled BSDF Base Color input and nothing else, because
that is what Cycles, EEVEE and the glTF exporter all read. Workbench does not:
its MATERIAL colour mode reads `material.diffuse_color`, a different channel
entirely, which defaults to grey.

So the first `-- look` render of a green-and-brown grass tile came back as a
uniform white box. It reads as a lighting problem and it is not one -- the
lighting was fine and the colours were simply somewhere else.

`shot.sync_viewport_colours()` copies Base Color across at render time (and
takes Emission Color instead for anything actually emitting, or a lit window
reads as a dead lump). It runs at render time rather than inside `kit.flat()`
because it is a display property that changes nothing about how the asset
renders in the engine or exports.

## 58. A bevel baked with `bmesh.ops.bevel` is outside the standard stack

The first `soften_top()` baked its bevel directly into the mesh with
`bmesh.ops.bevel` and then called `shade_auto_smooth()`. The geometry was
correct and the shading was wrong: with no Bevel modifier in the stack, and
auto-smooth adding the "Smooth by Angle" nodes modifier that Blender pins to the
end, `weighted_normals_all()` had nothing to sit last after, so every large flat
face carried a soft gradient across it instead of reading flat.

The fix is to stay in the standard hard-surface stack -- **Bevel modifier, then
Weighted Normal last**. To bevel only some edges, the modifier limits by ANGLE
or by WEIGHT, so write the weight and use `limit_method="WEIGHT"`:
`kit.mark_bevel_weight_top()` sets `bevel_weight_edge` on the top rim and
`soften_top()` adds a weight-limited Bevel.

Blender 4.x moved edge bevel weight to a generic named attribute
(`bevel_weight_edge` on the EDGE domain); the old `bm.edges.layers.bevel_weight`
is gone in 5.x. Try the named layer first and treat its absence as a hard
failure -- silently skipping it ships a square tile.

## 59. Rounding all edges of a tile opens gaps between tiles

Bevelling the vertical edges of a ground tile pulls its four side faces inward,
so two neighbouring tiles no longer touch and a field of grass becomes a grid of
separate blocks with the sky showing through the cracks.

Round the TOP RIM only. Side faces stay flat and full width, tiles butt
together, and a cliff face is a clean vertical plane. The shallow groove left
where two tops meet is correct -- the reference art shows exactly that.

The machine-checkable form of this rule is `-- measure`: a 1 m tile must come
back **exactly** 1.000 x 1.000. Anything less and it no longer tiles.
