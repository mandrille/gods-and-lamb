# The folk rig

`assets/_kit/folkrig.py` + `build.py -- rig <folk asset>`

This document exists because it reverses a rule that three other files stated
as permanent. If you have read "no rig, ever" somewhere in this repo, that text
is older than this file.

```
blender/assets/_kit/folkrig.py     the skeleton, the bind, the walk, the asserts
blender/build.py       target_rig  build -> bind -> animate -> check -> render
blender/assets/Folk/villager.py    the BASE folk: symmetric rest pose
blender/out/rig/                   walk strips and a rigged .blend per asset
```

Run it from `C:\Goliath\Gods and lamb\blender`:

```
blender --background --factory-startup --python build.py -- rig Folk/villager
```

About 6 s. It fails loudly and it writes pictures; there is no quiet mode.

---

## 1. What changed, and what did not

**Changed.** The folk have a skeleton and a walk cycle. `villager.py` is the
base body and its rest pose was squared up to serve as a bind pose.

**Not changed.** Everything else about the folk contract. `build()` still
returns a flat list of loose parts, the 600-triangle cap still holds, the asset
still fronts -Y, `-- asset` still gates it as an unrigged single mesh, and the
tween-between-tiles movement model is untouched. **The rig is animation, not
physics** — departure #2 in `AGENTS.md` still stands and nothing here has a
collider.

Files that still carry the old claim, or did until this landed:
`assets/Folk/villager.py` (updated), `.claude/agents/lamb-folk.md` (updated).
If you find a fourth, fix it rather than believing it.

---

## 2. The skeleton

Seven bones. That is not a starting point to grow from — it is sized to the
subject, which is a 40 px stack of boxes.

```
Root ──── Torso ──── Head
  │          └────── ArmL, ArmR
  └─────── LegL, LegR
```

Parts are assigned to bones **by name**, in `folkrig.GROUPS`:

| bone | claims parts matching |
|---|---|
| `Head` | `_Head` `_Hair` `_Eye` `_Kerchief` `_Sprig` |
| `Torso` | `_Tunic` `_Apron` `_Vest` `_Hem` `_Strap` `_Pack` `_Bedroll` |
| `ArmL` / `ArmR` | `_ArmL`/`_ArmR`, `_HandL`/`_HandR`, and `_Staff` on the right |
| `LegL` / `LegR` | `_LegL`/`_LegR`, `_BootL`/`_BootR` |

Order matters — first match wins, so `_ArmL` is tested before anything that
could also contain `_Arm`.

**An unclaimed part is a hard failure, never a default.** Falling back to the
root is how a satchel ends up hovering where the character used to be, and it
is invisible until something walks. If you add a part to a folk builder, add
its name here in the same commit.

Skinning is **rigid**: one vertex group per part, weight 1.0, no blending.
Automatic weights on stacked boxes bleed the tunic into the arm and tear a
shoulder on the first frame. One bone per part is exactly predictable, which at
this size is worth more than a soft elbow.

---

## 3. The rest pose rule

**The pose is symmetric. The details are not.**

`villager.py` was originally built with a pose baked into the geometry — arms
at 10° and −15°, head yawed −7°, one boot 28 mm forward — because an unrigged
mesh has to look alive standing still. A rig cannot use that:

- rest pose is what every clip is measured **from**, so a baked lean is a lean
  added to every frame of every animation you will ever write;
- `ArmL` and `ArmR` are mirrored bones, and mirrored bones on an asymmetric
  body deform the two sides differently.

So: arms level, feet level, head facing front. Keep the asymmetry that costs
nothing at runtime — the diagonal strap, an off-centre satchel, a hair parting.
The liveliness that used to come from the lean is now the walk cycle's job.

Squaring the villager up pulled its real footprint from 0.401 × 0.367 to
0.384 × 0.330, so the declaration came down to `(0.40, 0.35)`. **If you level a
pose, re-measure and re-declare** — the old number was reserving village ground
for a stride that is now animated.

---

## 4. The order, which is the whole thing

```
build parts  ->  bake each part  ->  group  ->  join  ->  attach armature
```

Every other target in this project merges an asset to one mesh before it
measures anything. **The rig target cannot**, because rigid skinning assigns
each PART to a bone and after a merge there are no parts — only one soup of
triangles that would have to be re-sorted into groups geometrically.

And the bake must come **before** the join, not after. `join()` keeps the
ACTIVE object's modifier stack and throws the rest away, so joining first put
the head's Bevel on all nineteen parts and a 516-triangle villager came out at
2052 with nothing erroring. `convert(target="MESH")` over the whole selection
bakes each object against its own stack; the join is then pure concatenation.

The guard is a triangle-count comparison against the loose parts, and it is
worth having because the fault renders as a perfectly good character. Only the
number says anything is wrong. See gotcha #75.

One `Armature` modifier goes on the **joined** mesh, first in its stack. That
is also what a glTF skin is; nineteen armature modifiers would export as
nineteen skinned meshes and nineteen draw calls.

---

## 5. The four asserts, and why each exists

Every one of these catches a failure that renders as a plausible picture. That
is the bar for adding another: if the fault is visible in a normal render, an
assert is not what you need.

| assert | catches |
|---|---|
| `assert_rigid_weights` | a vertex on two bones — tears an armpit |
| `assert_roll_is_sagittal` | a leg that swings sideways: a curtsy, not a walk |
| `assert_action_deforms` | an action that owns fcurves and moves nothing |
| `assert_cycle_closes` | frame 1 ≠ frame 25 — pops once per stride, forever |
| `assert_feet_on_floor` | wading through the ground, or floating above it |

Two of them are worth understanding before you change anything.

**`assert_roll_is_sagittal` measures, it does not read.** Arms and legs swing
fore and aft, which is a rotation about world X — but a bone pointing straight
down has no natural roll and Blender picks one. The roll *number* is
unreadable, so the assert rotates each swinger 20° about its own local X and
checks where the tail actually went.

**`assert_feet_on_floor` checks every frame, not the keys.** The keys are the
frames that were explicitly planted, so checking those would be checking that
an assignment assigned. It caught the villager sinking 9.9 mm through the
ground at frame 5, between two correct keys, because the leg rotations ease on
a bezier and the height between two keys is whatever the curve felt like.

---

## 6. The walk, and how the height is decided

24 frames at 24 fps, five keys: contact, pass, contact, pass, contact. The last
is a copy of the first so the cycle closes. A three-key walk reads as a limp,
because the two contacts are not the same distance from the pass.

**Forward is NEGATIVE rotation about X.** The character fronts −Y, and for a
point below the pivot `Rx(θ)` sends it to +Y for positive θ. Backwards gives a
moonwalk, which looks deliberate enough to survive a casual look.

**The body height is not authored.** One bone per leg means the foot swings on
an arc about the hip, so a 26° stride lifts the boot's leading corner about
6 cm — both feet hovering at every contact. Deriving the drop from leg length
and `cos(swing)` gets the leg but not the boot, which is 15 cm deep and tilts
with it. So each frame is posed first and the root is dropped by whatever the
**measured** lowest vertex turns out to be, on all 25 frames. Change the swing,
change the boot shape, and the feet still land. The vertical bob is then the
foot arc itself rather than a number somebody invented.

This is the local form of the project rule *measure, never derive*. If you add
a run or an idle, plant it the same way.

`pose_bone.location` is in **bone space**. The Root bone points along +Z, so
its local Y is world up and its local Z is world −Y — writing the bob to `.z`
slides the character backwards, and in a side view of a walk that reads as a
stride. `_lift_axis()` finds the right component by nudging each one 1 cm and
keeping whichever actually raised the mesh.

---

## 7. Adding a folk variant that rigs

1. Write the builder to the normal contract in `assets/README.md`. Build it at
   the origin on z=0, fronting −Y, **symmetric pose**.
2. Name the parts so `folkrig.GROUPS` claims them, or add the new names to
   `GROUPS`. `-- rig` will refuse the asset and list what it could not place.
3. `-- asset Folk/<name>` — the normal gate: tri cap, footprint, anchor, mesh
   defects. The rig does not exempt anything from it.
4. `-- rig Folk/<name>` — bind, animate, check, render.
5. **Open both strips.** Side is where a stride is judged; three-quarter is
   what the game will actually show. A cycle that reads in one and not the
   other is not finished.
6. Report the numbers: parts, tris, bones, groups, vertex travel, loop gap,
   floor sink/float.

A healthy run:

```
Folk/villager  (folk.folk.villager)
  19 part(s) -> 1 skinned mesh   516 tris   7 bones   6 group(s): ...
  action 'walk'  15 fcurves  24 frames at 24 fps
  max vertex travel 0.201 m   loop gap 0.000000 m   floor sink -0.0000 float 0.0000
  [RIG] ok
```

The tri count must equal what `-- asset` reported for the same asset. If it
does not, read section 4 before touching anything else.

---

## 7b. Quadrupeds take a DIFFERENT skeleton

`assets/_kit/critterrig.py` + `rig="critterrig"` in the declaration.

The livestock — `Animals/sheep`, `Animals/cow` — are `cls="folk"` by every
measure this pipeline uses (600 triangles, 40 px, rigged, walking between
tiles) and they are NOT bound by folkrig. Seven bones again, arranged for four
legs:

```
Root ------ Body ------ Head
  |
  +-------- LegFL, LegFR, LegBL, LegBR
```

Three things are worth knowing before you add another animal.

**Which rig runs is a DECLARATION, not a class.** `build.py`'s `_rig_module`
imports whatever `ASSET["rig"]` names and falls back to `folkrig`, so both
`-- rig` and `-- glb` work against the interface rather than against one
skeleton. Adding a class instead would have split the triangle cap, the cache
rule and the material fold along a line that has nothing to do with a leg
count.

**The joints are MEASURED, not tabled.** `folkrig.SKELETON` is coordinates
copied out of `villager.py`, which is fine when there is one body. There are
two animals at different sizes, so `critterrig.measured_skeleton()` reads every
joint off the EVALUATED bounds of the parts that will hang on it — the
front-left leg bone runs from the top of whatever `_LegFL` turned out to be
down to its lowest vertex. Move a leg in the builder and the bone follows. The
bounds must be evaluated, not raw: the sheep's fleece asks for an 8 cm bevel,
so its un-evaluated cage is eight centimetres wider than the animal.

**The gait is DIAGONAL.** Front-left swings with back-right. A lateral pair is
a real gait for a camel and reads as a broken animation for a cow. Swing is 17
degrees against the folk's 26 — at the folk's angle short stiff legs scissor
past each other and the animal skates.

Clips are `walk`, `idle` and `graze`, against the folk's `walk`, `idle`,
`pickup` and `chop`. `graze` carries the one assert that is new here,
`assert_head_dips`: the skull sits ABOVE its pivot and the legs hang below
theirs, so the two take OPPOSITE signs for "forward", and the version of that
mistake folkrig already paid for was villagers arching away from the tree they
were chopping.

## 8. What is NOT done

**Idle, carry and the tile-hop are still not clips of their own.** The walk,
idle, pickup and chop clips exist and export (`-- glb` reads back `anims 4`
on every human); a carry pose and the hop the tween does are not written.

**critterrig is still its own module.** It imports folkrig for the asserts and
the bake order and defines its own skeleton, groups and clips -- two files
that both know what a bone roll is for. A third body plan (a bird, a fish)
would be the moment to ask whether the generic half wants its own module.

**The shared body has one strap.** `_kit/folkbody.py` always draws the
diagonal `_Strap`; there is no flag to omit or reposition it, so every job
that wanted its own bag (adventurer's pack, nurse's satchel) drew a second
one beside it. A `strap=` parameter is the fix and was not in scope.

### 8b. What WAS done since this section was written

- **The exporter landed.** `-- library` writes one `.glb` per asset into
  `godot/assets/library/` with skin + animation; Godot's `Follower` finds the
  clips by name.
- **The adventurer is squared.** Its baked head yaw, arm tilt and leading boot
  are gone; it rests symmetric like the villager and its walk no longer leans.
- **There is a shared BODY.** `_kit/folkbody.py` owns every human proportion
  and builds the body; `SKELETON` here is imported from it, so the coordinate
  table at the top of this document can no longer drift from the geometry.
  Nine humans stand on it (villager, adventurer, and seven jobs), each a
  ~40-line file of palette + props. See `assets/README.md` §"Humans".

---

## 9. Related

- Gotcha **#73** — `mark_sharp` on the base cage creases every bevel
- Gotcha **#74** — Blender 5.2 removed `Action.fcurves`
- Gotcha **#75** — `join()` applies the active object's modifier stack to all
- `assets/README.md` — the asset contract every folk still obeys
- `AGENTS.md` §2 — look before you build; the cost table
