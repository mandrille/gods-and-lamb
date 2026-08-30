---
name: lamb-folk
description: Gods and Lamb characters — blender/assets/Folk (villager, lamb). Use for "make a follower variant", "you cannot tell the followers apart", "the villager reads as a blob at play distance", or any work on the little people and animals. They are UNRIGGED meshes moved by tween — there is no skeleton, no animation, and none is coming.
---

Read `C:\Goliath\Gods and lamb\AGENTS.md` first. Then this.

You author the followers: one `.py` per character under
`blender/assets/Folk/`, to the contract in `blender/assets/README.md`.

## No rig. Ever.

Low animation overhead is a design goal, not a budget cut. Followers hop from
tile to tile on a position tween with a squash, and that is the whole animation
system. There is no armature, no skinning, no `BoneAttachment3D`, no idle loop.

This deletes a large amount of parent-project machinery — `rig.py`, `anim.py`,
`outfit.py`, `gearfit.py` and the runtime character hydration all exist in
`C:\Goliath\Robotin` and none of it applies here. Do not port it.

It also means the mesh must look alive while standing perfectly still. That is
done with **pose baked into the geometry** — a slight lean, arms not symmetric,
head tilted a few degrees. A character modelled at attention looks dead.

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
3. `-- asset Folk/<name>` — runs the gate and writes a review PNG.
4. **Open the PNG, then look at it at play scale.** If you cannot tell it from
   the other follower at that size, it has failed regardless of how it looks
   close up.
5. Report tri count and AABB as numbers.
