---
name: lamb-nature
description: Gods and Lamb plant life and scatter — blender/assets/Nature (tree, bush, flower, rock, crop_row, pumpkin). Use for "add a plant", "the trees look like lollipops", "green up the village", or any work on vegetation and natural scatter. Not for the ground itself (lamb-terrain) or built structures (lamb-building).
---

Read `C:\Goliath\Gods and lamb\AGENTS.md` first. Then this.

You author vegetation and natural scatter: one `.py` per plant under
`blender/assets/Nature/`, to the contract in `blender/assets/README.md`.

Cap is **800 triangles**. Vegetation is the class most likely to blow a budget
by accident, because foliage wants to be round and round is expensive.

## Foliage is blocks, not spheres

The style is rounded cubes. A tree canopy is **two or three chamfered boxes at
slight angles**, not a subdivided sphere. This is not a compromise for the
budget — it is the look. Look at the reference: the canopies are clearly boxy
masses with soft corners, and they read as trees instantly.

Consequences:

- Never reach for `sphere()` for a canopy. A squashed box with a generous bevel
  costs a fifth as much and matches the village.
- **Bevel angle limit is 50 degrees for a reason.** At 30 degrees the facets of
  a coarse sphere (about 36 degrees apart) qualify as edges, and the bevel
  rounds curvature that was already round. In the parent project this doubled a
  plant from 1024 to 2296 triangles for no visible change.
- Two canopy blocks in slightly different greens read as depth. One green does
  not.

## Scatter reads as a group, not as an object

Flowers, bushes and crops are seen in fives and tens. Author the single piece so
that a field of them has variety in **silhouette**, and let the engine vary
rotation and tint. Do not build six flower variants when one plus a yaw is
enough.

`crop_row` is a row, not a plant — one asset covering a whole tile is cheaper
and reads better than nine instanced sprouts.

## Traps that have cost real time here

- **`weld()` collapses geometry** when fed a part carrying boolean-cut geometry.
  Vegetation in the parent project ships **unwelded** for exactly this reason.
  If a weld looks wrong, drop it.
- **A bar through the centre renders as two arms** — this catches radial leaf
  arrangements. Offset radially instead of centring and rotating.
- **`kit.cone` takes no rotation.** A leaning trunk built from a cone will not
  lean.
- **Green on green disappears.** A bush against grass needs a hue shift, not
  just a darker green. Trunks are the saturated anchor.
- Everything goes through `soften_all`.

## Your loop

1. `-- measure` the ground tile and anything you are sitting beside.
2. Write the builder.
3. `-- asset Nature/<name>` — runs the gate and writes a review PNG.
4. **Open the PNG.** Then imagine ten of them in a clump: does it read as a
   thicket, or as ten identical objects?
5. Report tri count and AABB as numbers.
