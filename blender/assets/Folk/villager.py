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
"""
import math
import os

from kit import M, box, soften_all

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

HEAD_W, HEAD_D, HEAD_H = 0.34, 0.30, 0.32
HEAD_Z = 0.46             # underside of the head
BODY_Z = 0.22             # underside of the tunic
BODY_H = 0.26
YAW = 0.0                 # head yaw. ZERO now: this is a rest pose, and a
                          # yawed head is a yaw added to every frame of
                          # every clip. The Head bone does it at runtime.


def build(tag="VILLAGER", **kw):
    # Hero parts carry the silhouette and earn a bevel. Everything else is
    # smooth-shaded only -- at 40 px a rounded elbow is nothing, and this asset
    # has 600 triangles to live inside.
    hero, plain = [], []

    head_c = HEAD_Z + HEAD_H * 0.5
    hero.append(box(tag + "_Head", (0, 0, head_c),
                    (HEAD_W, HEAD_D, HEAD_H), M["skin"], rot=(0, 0, YAW)))

    # Hair: a cap over the crown and two lobes down the sides, ALL sharing the
    # head yaw. Masses at different yaws meet along a slanted crease that reads
    # as a notch -- the same fault the tree canopy had, and a head is the worst
    # place to have it.
    hero.append(box(tag + "_Hair", (0, 0.012, HEAD_Z + HEAD_H - 0.01),
                    (HEAD_W + 0.03, HEAD_D + 0.03, 0.17),
                    M["hair_warm"], rot=(0, 0, YAW)))
    # Sideburns, not side PANELS. The first pass ran them the full depth and
    # height of the head, which from any three-quarter angle turned the whole
    # side of the face brown and hid an eye behind its own hair. They sit high
    # and back, and the lower front of the head stays skin.
    for sx in (-1, 1):
        plain.append(box("%s_HairSide%s" % (tag, "L" if sx < 0 else "R"),
                         (sx * (HEAD_W * 0.5 - 0.008), 0.045, head_c + 0.075),
                         (0.042, HEAD_D * 0.62, HEAD_H * 0.44),
                         M["hair_warm"], rot=(0, 0, YAW)))
    # The back of the crown, which is what stops the hair reading as a cap.
    plain.append(box(tag + "_HairBack", (0, 0.125, head_c + 0.045),
                     (HEAD_W - 0.05, 0.075, HEAD_H * 0.55),
                     M["hair_warm"], rot=(0, 0, YAW)))

    # Face: two dark eyes and nothing else. A mouth is three pixels of noise at
    # play distance, and the eyes are what make it a person.
    #
    # The eye CENTRES turn with the head, not just the eye boxes. `rot=` yaws a
    # box about its own centre, so the head rotates out from under anything
    # sitting on its face: at YAW -7 the right eye sat 9 mm BEHIND its own
    # cheek and every front render was a face with one eye. Not the same fault
    # as the look camera that used to be a side view -- but it produced the
    # identical picture, which is how it survived that fix.
    c, s = math.cos(math.radians(YAW)), math.sin(math.radians(YAW))
    for sx in (-1, 1):
        ex, ey = sx * 0.075, -HEAD_D * 0.5 + 0.012
        plain.append(box("%s_Eye%s" % (tag, "L" if sx < 0 else "R"),
                         (ex * c - ey * s, ex * s + ey * c, head_c - 0.01),
                         (0.05, 0.03, 0.068), M["hair_dark"], rot=(0, 0, YAW)))

    # Torso. Narrower than the head on purpose. The orange apron is a separate
    # slab standing slightly proud rather than a face on the tunic, because two
    # materials on one box would need a boolean and buy nothing.
    hero.append(box(tag + "_Tunic", (0, 0, BODY_Z + BODY_H * 0.5),
                    (0.24, 0.19, BODY_H), M["cloth_green"]))
    plain.append(box(tag + "_Apron", (0, -0.098, BODY_Z + 0.11),
                     (0.175, 0.025, 0.19), M["cloth_orange"]))
    plain.append(box(tag + "_Kerchief", (0, -0.005, HEAD_Z - 0.01),
                     (0.235, 0.205, 0.055), M["cloth_red"], rot=(0, 0, YAW)))
    # One strap, no bag. A satchel is the reference's asymmetry, and at this
    # size the strap carries all of it -- the bag itself was a brown blob on
    # the apron and cost triangles the head wanted.
    #
    # Rotated about Y, NOT about Z. A Z yaw spins a long box in PLAN, so this
    # was a horizontal bar sticking a hand's width out of his ribs and casting
    # a hard shadow across the apron -- it read as a shading fault at close
    # range and it was geometry the whole time. About Y it runs shoulder to hip
    # and stays inside the tunic width. Pushed 1.4 cm proud of the apron face
    # so it sits ON the garment instead of fighting it for the same plane.
    plain.append(box(tag + "_Strap", (0, -0.112, BODY_Z + 0.14),
                     (0.26, 0.026, 0.042), M["leather"], rot=(0, 34, 0)))

    # Arms, SHORT, and hanging LEVEL. They used to hang at 10 and -15 so the
    # figure did not read as a doll standing to attention -- which is exactly
    # the reading a rest pose is supposed to have. The ArmL/ArmR bones swing
    # them, and they must start from the same angle or the walk is lopsided
    # by the difference for its whole length.
    for sx in (-1, 1):
        side = "L" if sx < 0 else "R"
        plain.append(box("%s_Arm%s" % (tag, side),
                         (sx * 0.152, 0.0, BODY_Z + 0.145),
                         (0.072, 0.072, 0.17), M["cloth_green"]))
        plain.append(box("%s_Hand%s" % (tag, side),
                         (sx * 0.156, 0.0, BODY_Z + 0.04),
                         (0.072, 0.072, 0.062), M["skin"]))

    # Legs and boots. Short legs, oversized boots, and both feet LEVEL -- one
    # foot forward in the rest pose is a permanent limp once the LegL/LegR
    # bones add their own swing on top of it.
    for sx in (-1, 1):
        side = "L" if sx < 0 else "R"
        plain.append(box("%s_Leg%s" % (tag, side),
                         (sx * 0.066, 0.0, 0.145),
                         (0.088, 0.088, 0.13), M["wood_dark"]))
        plain.append(box("%s_Boot%s" % (tag, side),
                         (sx * 0.066, -0.016, 0.048),
                         (0.115, 0.15, 0.096), M["leather"]))

    # Two passes. 2.5 cm at two segments on the head, hair cap and tunic is the
    # same chunky radius the ground tiles carry, so the folk and the world read
    # as one thing. Everything else goes through soften_all at width 0 --
    # smooth-shaded and tagged, no radius, no triangles.
    soften_all(hero, width=0.025, segments=2)
    soften_all(plain, width=0.0)
    return hero + plain
