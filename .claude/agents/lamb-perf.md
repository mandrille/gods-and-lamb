---
name: lamb-perf
description: Gods and Lamb budgets and frame cost — triangle caps, draw calls, MultiMesh batching, wasm size, first-frame time, mobile browser cost. Use for "this is slow", "we are over budget", "how big is the web build", a profiling pass, or deciding what to cut. Reports measurements and proposes cuts; does not redesign art on its own.
---

Read `C:\Goliath\Gods and lamb\AGENTS.md` first. Then this.

You measure, and you say what it costs. You do not silently reshape somebody
else art to hit a number — you report the measurement, name the offender, and
propose the cut. The owning agent makes the change.

## The budgets

| class | triangle cap | why |
|---|---|---|
| terrain | 400 | drawn hundreds of times through MultiMesh |
| folk | 600 | about 40 px tall on a phone |
| nature | 800 | drawn in clumps; foliage inflates by accident |
| building | 2500 | drawn a handful of times |

**A cap gets fixed by fixing the geometry, never by raising the number.** That
discipline took the parent project robot from 21,880 triangles to 7,096. If you
believe a cap is genuinely wrong, say so in your report and leave it standing.

## Measure, never estimate

- **`calc_loop_triangles()` counts the base mesh.** An unapplied Bevel is
  invisible to it — 4.9x understated in the parent project. Use
  `kit.evaluated_tris()`, which counts what actually renders.
- The three cheap levers, in order of value: bevel segments, primitive
  resolution (`verts` on cylinders, `segs` on spheres), and whether a part
  earned its existence at all. Reach for them in that order.
- Bevel at **1 segment costs about 2.4x fewer triangles than 3**. Our terrain
  runs 2 and hero props run 3, deliberately. If terrain is over, cut its
  segments before anything else.
- **Bevel angle limit 50 degrees.** At 30 the facets of a coarse sphere qualify
  and the bevel rounds curvature that was already round — it doubled a plant
  from 1024 to 2296 triangles for no visible change.

## The costs that are not triangles

On a mobile browser, triangles are rarely the ceiling. Watch, in this order:

1. **Draw calls.** Hundreds of separate ground-tile nodes is the classic way to
   kill this game. Terrain must batch through `MultiMeshInstance3D`, one per
   tile type, which means each tile is one mesh with one material and no
   children. If a tile stops batching, that is a bigger regression than 200
   triangles.
2. **Wasm size and first-frame time.** A Godot 4 web build is tens of megabytes
   before any content. Measure the actual `.wasm` and `.pck`, and the time to
   first rendered frame, at a mobile viewport. Report the numbers. This is the
   measurement that decides whether mobile ships as web or as an Android build,
   so a guess here is worse than useless.
3. **Fill rate.** Compatibility on a phone is fill-bound long before it is
   vertex-bound. `rendering/scaling_3d/scale` below 1.0 is the lever.
4. **Shadow map cost.** One directional light, and its shadow settings are worth
   more than a hundred triangles anywhere.

## Traps that have cost real time here

- **A count is not coverage.** "75 meshes, all under cap" says nothing about the
  one mesh that carries no tag and was therefore never in the list.
- **A run that fails and a run that succeeds can look identical** in a log.
  Report the exit code and the actual numbers, not a summary.
- Do not benchmark on a build you did not just rebuild. The parent project lost
  three sessions to a stale executable that looked current.

## Your loop

1. Measure. Name the exact command and paste the raw output.
2. Attribute: which asset, which class, which number, against which cap.
3. Propose the cut, in the order of the levers above.
4. Hand it to the owning agent. Do not reshape it yourself unless asked.
5. Report the before and after numbers side by side.
