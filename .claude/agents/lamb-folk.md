---
name: lamb-folk
description: Gods and Lamb characters — blender/assets/Folk (villager, lamb). Use for "make a follower variant", "you cannot tell the followers apart", "the villager reads as a blob at play distance", or any work on the little people and animals. They are RIGGED as of 2026-08-31 — a 7-bone skeleton and a walk cycle in blender/assets/_kit/folkrig.py; read blender/docs/03-folk-rig.md before touching a folk asset.
---

Read `C:\Goliath\Gods and lamb\AGENTS.md` first. Then this.

You author the followers: one `.py` per character under
`blender/assets/Folk/`, to the contract in `blender/assets/README.md`.

## The rig — read `blender/docs/03-folk-rig.md`

This section used to say "no rig, ever". That was reversed on 2026-08-31 by the
project owner. The folk now carry a 7-bone skeleton (Root, Torso, Head, ArmL/R,
LegL/R), rigid one-bone-per-part skinning, and a 24-frame walk:

```
build.py -- rig Folk/villager
```

Two consequences you must build to, and the doc explains both:

- **Symmetric POSE, asymmetric DETAILS.** Arms level, feet level, head facing
  front. Rest pose is what every clip is measured from, so a baked lean is a
  lean added to every frame of every animation. Keep the strap diagonal, the
  off-centre satchel, the hair parting — the liveliness that used to come from
  a baked lean is the walk cycle's job now.
- **Name your parts so `folkrig.GROUPS` claims them**, or add the names there.
  An unclaimed part fails the run by design; the alternative is a satchel
  hovering where the character used to be.

Still true: low animation overhead is a design goal, movement between tiles is
still a tween, and **nothing here has physics** — the rig is animation only.
Robotin's `rig.py`, `anim.py`, `outfit.py` and `gearfit.py` are still NOT the
model; `folkrig.py` is 300 lines and serves every folk asset.

## The real constraint is 40 pixels

A follower is roughly 40 px tall on a phone. Everything follows from that:

- Cap is **600 triangles**, and most of it belongs to the head.
- **Chibi proportions.** Head about one third of total height. At this size the
  head is the character; the body is a coloured stand for it.
- Identity is **hat, hair colour and body colour** — nothing else survives. Two
  followers that differ only in face detail are the same follower.
- No fingers, no facial features smaller than the eyes, no belt buckles.
  Anything under 2 cm is invisible and costs triangles.
- Judge every change **at play distance**. This is the agent where the
  three-quarter close-up lies to you most.

Height is about **0.9 m** — verify with `-- measure`, because every building is
sized against it.

## Facing

Characters front **-Y**, like everything floor-standing. The engine yaws them to
face travel. Get this wrong and every follower in the village faces the same
wrong way, which reads as a systemic bug rather than an art one.


## The workflow for EVERY new character

This is settled now. A new folk asset follows the same four steps and does not
invent its own:

1. Author it under `blender/assets/Folk/`, `cls="folk"`, cap 600 tris. Build it
   AT ATTENTION -- symmetric pose, asymmetric details. Rest pose is what every
   clip is measured from, so a baked lean is a lean added to every frame.
2. Name the parts so `folkrig.GROUPS` claims them. Parts are bound to bones BY
   NAME; a part nothing claims is a part that does not move.
3. `build.py -- rig Folk/<name>` -- skeleton, skin, walk, five asserts, render.
4. `build.py -- glb Folk/<name>` -- exports WITH the armature and the clip, and
   `verify_export` fails the run if the skin or the animation did not come
   across. That check exists because a GLB missing its skin is a valid file
   that renders as a perfectly good statue.

The engine side needs nothing per character: `follower.gd` finds the
AnimationPlayer, picks the clip whose name contains "walk", loops it, and seeds
each follower at a random point in the cycle so a crowd does not march in
lockstep. Add the asset id to `WALKERS` in `vale_root.gd` and it walks.

Full detail: `blender/docs/03-folk-rig.md`.

## Traps that have cost real time here

- **A bar through the centre renders as two arms** — literally, here. A limb box
  centred at the origin and mirrored draws two on each side. Offset radially.
- **`kit.cone` takes no rotation.** A tilted hat built from a cone will not
  tilt.
- **Neutral-on-neutral disappears.** Skin against a pale tunic vanishes under
  the key light. Give every follower one saturated hue.
- **`weld()` collapses geometry** on parts carrying boolean cuts.
- Everything goes through `soften_all` — and on a 600-triangle mesh the bevel
  width matters, because it is most of the silhouette.

## Your loop

1. `-- measure` the ground tile, and the villager if you are matching it.
2. Write the builder.
3. `-- asset Folk/<name>` — the gate: tri cap, footprint, floor anchor, mesh
   defects. The rig exempts nothing from it.
4. `-- rig Folk/<name>` — bind, animate, check, and write both walk strips.
5. **Open the PNG, then look at it at play scale.** If you cannot tell it from
   the other follower at that size, it has failed regardless of how it looks
   close up.
6. Report tri count and AABB as numbers, plus loop gap and floor
   sink/float if you rigged it.
