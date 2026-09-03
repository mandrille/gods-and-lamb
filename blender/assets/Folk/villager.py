"""FOLK.folk.villager - a follower. The thing the whole game is about.

THE BASE FOLK, and the one that carries the skeleton. `assets/_kit/folkrig.py`
binds seven bones to these parts by name and drives them with a walk cycle:
`build.py -- rig Folk/villager`.

That reverses this file's original doctrine, which said unrigged and permanent,
and the reversal is the owner's call rather than a drift. What it costs is
written down here so nobody re-derives it: an armature, a skin weight per
vertex, and a pose evaluation per follower per frame.

BUILT AT ATTENTION, which is the part that changed with the rig. The first
version baked a pose into the geometry -- arms at different angles, head yawed,
one boot forward -- because a still mesh has to look alive. A RIG cannot use
that. Rest pose is what every animation is measured from, so a baked lean is a
lean added to every frame of every clip, and a mirrored bone on an asymmetric
body deforms the two sides differently.

So the POSE is symmetric and the DETAILS are not. Arms hang level, feet are
level, the head faces front; the strap still runs corner to corner, and the
asymmetry that made it look alive standing still is now the walk cycle's job.

PROPORTIONS, which are the whole job and took two attempts:

    head + hair   0.46 .. 0.90     49% of total height
    torso         0.22 .. 0.48
    legs + boots  0.00 .. 0.22

The first pass gave the head 39% and long arms and legs, and it came back
reading as a small adult rather than as the reference. Three rules pulled it
back, all of them from the reference rather than from anatomy:

* the head is WIDER than the body (0.34 against 0.24). If they are the same
  width the figure reads as a column with a face on it.
* arms are SHORT. They stop at the bottom of the tunic, not at the hip -- long
  arms are the single strongest signal of an adult.
* legs are short and the boots are oversized. Most of the lower half is boot.

Do not "fix" any of this toward realism. At 40 px the head IS the character and
the body is a coloured stand for it.

COLOUR is where the reference had to be argued with. Its tunic is a bright
grass green, which works on the reference's white backdrop and would be
camouflage here: a follower stands ON `grass` for the entire game. So the tunic
is a darker, bluer green that separates from the ground, and the ORANGE apron is
the identity -- warm against green is the only thing that reads a person out of
a field at play distance.

Fronts -Y, like everything floor-standing.

MIGRATED onto `assets/_kit/folkbody.py`, the one shared human body: this file
now supplies only the villager's palette (dark-green tunic, orange apron,
warm hair) and calls `folkbody.body()` at its defaults (cap hair, apron on,
kerchief on, hands level). The geometry below is unchanged -- the migration's
own regression test was that this file's `-- measure` and `-- rig` numbers do
not move.
"""
import os

from folkbody import body, finish

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="folk",
    family="folk",
    variant="villager",
    category=CATEGORY,
    # MEASURED, and re-measured after the rest pose was squared up: levelling
    # the feet and the arms pulled 2 cm off X and 4 cm off Y, because the old
    # numbers were reserving ground for a stride that is now the walk cycle's.
    footprint=(0.40, 0.35),
    anchor="floor",
    slots=(),
)

# Darker, bluer green than the reference's grass green -- the reference is
# drawn on a white backdrop and this thing stands ON `grass` for the whole
# game, so its own reference colour would be camouflage. The orange apron is
# the identity: warm against green is what reads a person out of a field at
# play distance.
PALETTE = dict(tunic="cloth_green", apron="cloth_orange", kerchief="cloth_red",
               hair="hair_warm", skin="skin", boots="leather", legs="wood_dark")


def build(tag="VILLAGER", **kw):
    hero, plain = body(tag, PALETTE, hair="cap", apron=True, kerchief=True,
                       hands="level")
    return finish(hero, plain)
