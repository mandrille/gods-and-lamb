---
name: lamb-terrain
description: The Gods and Lamb ground kit — blender/assets/Terrain (grass, cliff_step, water, path, farmland, sand). Use for "make a new tile type", "the tiles have gaps between them", "the cliffs read wrong", or any work on the surface the village stands on. Not for things that sit on the ground (lamb-nature, lamb-building).
---

Read `C:\Goliath\Gods and lamb\AGENTS.md` first. Then this.

You author the ground: one `.py` per tile type under
`blender/assets/Terrain/`, to the contract in `blender/assets/README.md`.

Terrain is different from every other asset class in this project, in two ways
that drive almost every decision you make.

## 1. Terrain instances through MultiMesh

Hundreds of ground tiles as individual nodes is the single thing most likely to
kill a mobile browser. So terrain goes into `MultiMeshInstance3D`, and that
imposes hard constraints:

- **One mesh, one material, no children.** A tile that merges to two meshes, or
  carries a second material slot, cannot be batched. The gate checks this.
- No per-tile geometry variation. Variation comes from **per-instance tint**,
  which the engine applies — not from authoring six grass variants.
- Keep the tile cheap. The cap is **400 triangles** and it is deliberately
  tight, because this mesh is drawn hundreds of times.

## 2. Bevel the top edges only

This is the rule that makes or breaks the look, and it is counter-intuitive.

The style is rounded cubes. But a tile bevelled on **all** edges pulls its
vertical side faces inward, and two neighbouring tiles then meet with a visible
seam of background showing through the gap between them. A field of grass reads
as a grid of separate blocks with cracks between.

So: **round the top rim, leave the four vertical side faces flat and full
width.** Tiles butt together seamlessly, the exposed top edge is soft and cute,
and a cliff face is a clean vertical plane. This is exactly what the reference
image does — look at where two grass tiles meet versus where a grass tile meets
open air.

The same applies to any tile that tiles: path, farmland, sand, water.

## The dimensions

- One tile is **1.0 x 1.0 m** in plan. This is the grid module; nothing may
  overhang it.
- A tile is **1.0 m tall** by default and stands on z=0, so its top surface is
  at z=1.0. Everything that stands on the ground assumes that.
- Water sits slightly lower than grass — a visible drop, not a coplanar surface,
  or it z-fights with the bank.
- Cliff steps come in whole-tile heights. Do not invent a 0.6 m step; the
  village places on a grid and a half-height step will float things.

## Traps that have cost real time here

- **The tiling rule has a machine-checkable form: `-- measure` must come
  back EXACTLY 1.000 x 1.000.** Anything less means a bevel has pulled a
  side face in and the tile no longer tiles. Do not eyeball this.
- **Round the top rim with `kit.soften_top()`, never `soften_all()`.** It
  uses a Bevel modifier limited by edge WEIGHT rather than by angle, so
  Weighted Normal still sits last in the stack. An earlier version baked
  the bevel with bmesh instead, which left the mesh outside the standard
  stack and put a soft gradient across every flat face.
- **`-- measure` before assuming a tile is 1.0 m.** A bevel widens nothing but a
  boolean can, and a tile 1.004 m wide tiles with a visible line every column.
- **A rotated box is taller than its own z size.** If you tilt a slab for a
  bank, its real height is not the number you typed.
- **Neutral-on-neutral disappears.** Dirt sides and stone paths are the two
  places this bites hardest — differ them in hue, not brightness.
- Everything goes through `soften_all`, including a plain cube.
  `assert_soften` measures went-through-the-pass, not has-a-bevel.

## Your loop

1. `-- measure` anything you are sizing against.
2. Write the builder.
3. `-- asset Terrain/<name>` — runs the gate and writes a review PNG.
4. **Open the PNG.** Then place two of the tile side by side mentally and ask
   whether the seam would show. If unsure, say so and ask the orchestrator for a
   two-tile look render.
5. Report tri count and AABB as numbers.
