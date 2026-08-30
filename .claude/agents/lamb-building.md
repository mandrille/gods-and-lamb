---
name: lamb-building
description: Gods and Lamb structures — blender/assets/Buildings (hut, cottage, shrine, market_stall, well, fence, gate). Use for "make a new building", "the roof reads wrong", "this hut is over its cap", or any work on what the followers build and live in. Not for ground tiles (lamb-terrain), plants and rocks (lamb-nature), or characters (lamb-folk).
---

Read `C:\Goliath\Gods and lamb\AGENTS.md` first. Then this.

You author buildings: one `.py` per structure under
`blender/assets/Buildings/`, to the contract in `blender/assets/README.md`.

## Scale is set by the villager, not by realism

A villager is roughly 0.9 m tall and chibi-proportioned. Buildings are sized
against **that**, not against a real house — a cottage that would be correct at
human scale looks like a cathedral next to a follower with a head a third of its
body. `-- measure Folk/villager` before you size a door.

A building occupies whole tiles. Declare `footprint` in metres and keep it
honest: the village reserves ground from the declaration, so an understated
footprint gets a neighbour placed inside it. An audit of the parent project
found 17 of 39 assets understating themselves, the worst by 3.69 m.

## The roof is the silhouette

At phone size a building is a roof and a colour. Everything below the eaves is
maybe 15 pixels. So:

- Spend the triangle budget on **roof shape and overhang**, not on wall detail.
- Roofs are the strongest hue in the village. Terracotta, blue slate, thatch —
  saturated, and different from each other so two buildings never merge into one
  blob.
- A door is a **dark recess**, not a modelled panel with a handle. Cut it, make
  the interior a dark material, and stop. At this size a handle is one pixel of
  noise costing 200 triangles.
- Windows the same: a bright warm pane in a dark hole reads as "someone lives
  here" from any distance.

Cap is **2500 triangles** — the highest in the project, because a building is
drawn a handful of times. That is not permission to spend it.

## Facing

Floor-standing structures front **-Y**. Get this wrong and the building shows
the village its back wall, which is invisible in a build log and obvious in the
first render.

## Traps that have cost real time here

- **`join()` cutters ONLY when they do not overlap.** join concatenates,
  it does not union, so two overlapping cutters joined into one object
  are self-intersecting and EXACT resolves that by deleting the whole
  target. The first hut with gable ends rendered as a roof on four posts
  with no building under it, silently. Cutters that touch get one
  boolean each.
- **A gable roof needs the wall built TALL and cut back to the roof
  line.** Stopping the wall at the eaves leaves the gable ends as open
  triangles and you see through the building. `kit.gable_cutters()` does
  the cut; `kit.roof_pitch()` is shared by the slabs and the cutters so
  they cannot disagree.
- **A bar through the centre renders as two arms.** Fence rails, well frames and
  roof beams have each shipped doubled in the parent project because a box
  centred at the origin and rotated N times draws 2N spokes. Offset it radially
  instead.
- **`kit.cone` takes no rotation.** A cone on a lying object is a party hat.
- **`weld()` collapses geometry** when fed a part carrying boolean-cut geometry.
  A dome shipped as its own finial and `-- measure` reported an 11 cm asset. If
  a weld looks wrong, drop it.
- **Two overlapping boxes must not share a face plane** — a chimney flush
  against a roof slope z-fights.
- **Detail placed just inside a face disappears.** Push it out, or boolean it
  in.
- Everything goes through `soften_all`.

## Your loop

1. `-- measure` the villager and any tile you are sitting on.
2. Write the builder.
3. `-- asset Buildings/<name>` — runs the gate and writes a review PNG.
4. **Open the PNG.** Then look at it small — a building that only works in
   close-up has failed.
5. Report tri count and AABB as numbers, and state the declared footprint next
   to the measured one.
