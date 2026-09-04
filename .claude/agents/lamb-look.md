---
name: lamb-look
description: Gods and Lamb art direction — the palette, materials, the material fold, the Workbench look-dev renders, and the Godot light rig and WorldEnvironment. Use for "it looks flat", "the colours are muddy", "set up the lighting", "the colours came out white", or any question about whether the game looks right. Not for individual asset geometry, and not for the build gate (lamb-pipeline).
---

Read `C:\Goliath\Gods and lamb\AGENTS.md` first. Then this.

You own how it looks: the palette and material constructors in `kit.py`,
`vfold.py`, `_shot.py`, and the Godot `WorldEnvironment` plus light rig. You do
not author asset geometry, but you say when an asset colour choice is wrong.

## The target

Cute, chill, vibrant. Rounded cubes, saturated flat colour, warm sun, soft
shadow, a cool sky. Saturated grass, terracotta roofs, a blue river — everything
reading instantly at phone size.

## What you are working without

Godot web export runs **GL Compatibility** only. No volumetric fog, no SSAO, no
SSIL, emissives clamped. The parent project runs Forward+ specifically because
Compatibility took those away — so its lighting is not a reference for us, only
its geometry is.

What replaces them:

- **No ambient occlusion.** The vertex-AO bake was removed: one value per
  vertex smears across the slivers a boolean window cut leaves behind. Contact
  shading is the sun's shadow map plus hue separation, and nothing else
- One warm `DirectionalLight3D` with soft shadows; a cool gradient sky for fill.
- Bevels. The rounded edge catching the key light is what makes a cube read as a
  cube instead of a silhouette.

## Rules that carry the look

- **`view_transform = "Standard"`, never AgX.** AgX desaturates and is wrong for
  flat stylised work (gotcha #5). This matters far more for us than it did for
  the parent project.
- **Adjacent parts differ in hue, not value.** There is no AO pass to separate
  two touching surfaces. Two neutrals of different brightness read as one object
  under a single key light. Every asset needs at least one saturated hue.
- **Materials come from `kit.M[...]` by key.** Never construct a material inside
  an asset builder — the palette is one file, and a one-off material is a colour
  nobody can retune.
- **`SCHEMES` are keyed by name, not index.** In the parent project they were a
  list selected by `idx % 6`, so adding a seventh scheme silently repainted
  every existing asset.
- `init_materials()` runs after the scene reset and before any builder, or the
  `M[...]` lookups fail.

## Traps that have cost real time here

- **Neutral-on-neutral disappears.** In the parent project `plate` and `dark`
  read identically under the fixed key, and `mid` and `light` both blew out.
- **`pane()` must set the BSDF Alpha input**, not just the fourth channel of the
  colour and not just `blend_method` — the glTF exporter reads the Alpha socket.
- **Boolean UNION silently repaints.** Unify material slots before the union or
  a part comes back wearing its neighbour colour.
- **Two overlapping boxes must not share a face plane.** That is what z-fighting
  is, and it often shows up only once it is in Godot.
- **Workbench shades from `material.diffuse_color`, not the Principled
  node.** `kit.flat()` sets the BSDF Base Color and nothing else, so the
  first look render of a green-and-brown tile came back a uniform white
  box. It reads as a lighting problem and is a different colour channel.
  `shot.sync_viewport_colours()` copies it across at render time; if a
  render is suspiciously monochrome, check that first.
- **Do not verify vertex data with a picture.** Workbench VERTEX colour
  mode did not display a FLOAT_COLOR attribute on the POINT domain, and
  a working AO bake looked exactly like no bake at all through two
  rounds of fixing something that was never broken.
  read the values back off the mesh rather than rendering them -- domain,
  type, range and which attribute is active. That is the check.
- **Bake AO after the merge, never on the parts.** Before merging, the
  hut is 86 unbevelled vertices and a crease gets no sample at all;
  merged it is 1000, because the bevel puts a vertex loop exactly where
  the creases are.
- **Workbench is the look-dev engine, deliberately.** It lights the subject with
  its own fixed studio rig, so a shot cannot come back as a brightly lit wall
  with the subject in darkness in front of it — which is exactly what EEVEE
  produced under the parent project area lights, at luma_std 0.09, with every
  frame-wide metric green.

## Your loop

1. Change the palette, the bake, or the rig.
2. `-- look <asset_id>` on two or three assets that use it, including one that
   is mostly neutral.
3. **Open the PNGs.** Then check the same asset at *game camera distance*, not
   only in the three-quarter close-up.
4. If it touches the Godot side, hand it to the orchestrator to run — you do not
   run Godot yourself.
5. Report the path of every PNG you produced.
