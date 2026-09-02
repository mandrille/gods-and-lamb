"""ANIMALS.livestock.sheep - the village flock. Sheared for wool.

THE FIRST NON-PERSON FOLLOWER, and the thing it had to prove is that a
quadruped can go through the same pipeline as a villager without either of them
bending. It does: `cls="folk"`, because every number the pipeline cares about is
a follower's -- 600 triangles, 40 px tall, rigged, animated, walking between
tiles -- and `rig="critterrig"`, because the seven bones are arranged for four
legs instead of two. See `assets/_kit/critterrig.py`.

WHAT READS AS A CREATURE FROM 35 DEGREES ABOVE, which is the only view the game
has and therefore the only one this asset may be judged in. Two versions were
rejected here and both looked fine in close-up:

  1. THE LEGS MUST STAND WIDER THAN THE BODY. This is the whole lesson. The
     fleece was 38 cm across and the legs stood 24 cm apart, so the body
     overhung each leg by 7 cm -- and an overhang of ANY size hides a leg
     completely from a camera looking down at it. There were four legs on the
     asset and not one of them was ever visible. The fleece is 28.5 cm now and
     the hooves stand 38 cm apart, so they break the outline on both sides.
  2. GROUND UNDER THE BELLY. 30 cm of clearance on a 63 cm animal: half its
     height is leg. That is what puts grass and a separate shadow underneath,
     and grass under a shape is the whole difference between a creature
     standing on the ground and an object resting on it.
  3. A HEAD END AND A REAR END. The head hangs on a neck, 28 cm in front of the
     fleece and 20 cm below the line of the back, so the plan outline points
     one way. Front-to-back asymmetry is most of what makes a shape read as an
     animal at 40 px; a symmetrical blob reads as an object however well it is
     modelled.
  4. A LUMPY TOP. The three fleece masses sit at three different heights, so
     the back rises over the shoulder and falls to the rump. The cow's back is
     deliberately straight. That difference survives to play distance when
     nothing else about the two shapes does.

The version before this one read as a computer mouse, and the diagnosis was
exact: a rounded white capsule with a red dot on it, no legs, no head, lying on
grass. The red dot was a raddle mark -- the paint a real shepherd uses -- and at
play scale it was an LED on a device. It is gone. The saturated hue the house
rule asks for is a `cloth_red` collar instead, and it sits on the NECK: a band
at a joint reads as a collar, a patch in the middle of a smooth back reads as a
button.

Built at attention on z=0, fronting -Y, like everything floor-standing.
"""
import os

from kit import M, box, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="folk",
    family="livestock",
    variant="sheep",
    category=CATEGORY,
    # MEASURED with `-- measure`, not derived. X is set by the HOOVES and not
    # by the ribs, which is the entire point of the stance. Y is nose to tail.
    footprint=(0.39, 0.93),
    anchor="floor",
    slots=(),
    # NOT folkrig. A biped skeleton on this body puts a femur through the
    # fleece and hangs the head off a shoulder.
    rig="critterrig",
)

LEG_TOP = 0.32            # legs run 0 .. LEG_TOP; the fleece starts at 0.30
LEG_X = 0.155             # half the stance. MUST exceed half the fleece width.
BARREL_Z = 0.450          # centre of the main fleece mass


def build(tag="SHEEP", **kw):
    # Hero parts carry the silhouette and earn a bevel; everything else is
    # smooth-shaded only. On a 600-triangle budget a bevelled box costs nine
    # plain ones, so the three fleece masses take the whole allowance and the
    # head, legs and trim go through soften_all at width 0.
    hero, plain = [], []

    # --- the fleece: three masses at THREE DIFFERENT HEIGHTS. A single box
    # reads as a crate on legs; three boxes with a level top read as a longer
    # crate. The shoulder stands 2.8 cm above the barrel and the rump between
    # them, which is a back line with a bump in it -- the one shape cue that
    # separates this from the cow at any distance.
    #
    # The widths stay within 1 cm of each other. At 38 / 36.5 / 33 the narrower
    # lumps sat INSIDE the barrel and their bevels met its side in a hard
    # vertical notch across the shoulder, the same fault villager.py records on
    # the hair. The shape comes from the overlap in Y and Z, never from width.
    hero.append(box(tag + "_Fleece", (0, 0.010, BARREL_Z),
                    (0.285, 0.40, 0.300), M["wool"]))
    hero.append(box(tag + "_FleeceShoulder", (0, -0.160, BARREL_Z + 0.028),
                    (0.278, 0.26, 0.315), M["wool"]))
    hero.append(box(tag + "_FleeceRump", (0, 0.190, BARREL_Z + 0.005),
                    (0.280, 0.24, 0.290), M["wool"]))

    # --- head and neck. The neck is a real mass and not a seam: it carries the
    # head down and out in front of the fleece so the plan view has a pointed
    # end. Both dark -- at this size a face is one shape, and a separate jaw
    # would be two pixels of noise.
    plain.append(box(tag + "_Neck", (0, -0.300, 0.415),
                     (0.135, 0.160, 0.190), M["hair_dark"]))
    # The collar rings the NECK, which is where a collar goes. An earlier
    # version put this same red as a mark on the back and it read as a button
    # on a gadget; an earlier one still made it a slab across the chest and it
    # read as a bib. On a neck that is now a visible separate mass it simply
    # reads as a collar -- and it is the only saturated hue on an asset made
    # almost entirely of near-white.
    plain.append(box(tag + "_Collar", (0, -0.345, 0.405),
                     (0.155, 0.055, 0.200), M["cloth_red"]))
    plain.append(box(tag + "_Head", (0, -0.435, 0.355),
                     (0.155, 0.190, 0.170), M["hair_dark"]))
    plain.append(box(tag + "_Muzzle", (0, -0.545, 0.315),
                     (0.100, 0.060, 0.090), M["hair_dark"]))
    # Wool coming down over the forehead. This is the marking that says SHEEP
    # rather than goat or dog, and it is the only pale thing on the head -- so
    # from above it is what stops the head reading as the animal's own shadow.
    plain.append(box(tag + "_Topknot", (0, -0.480, 0.440),
                     (0.135, 0.100, 0.050), M["wool"]))
    # Ears out to the SIDE, not back.
    for sx in (-1, 1):
        side = "L" if sx < 0 else "R"
        plain.append(box("%s_Ear%s" % (tag, side),
                         (sx * 0.090, -0.405, 0.415),
                         (0.085, 0.050, 0.040), M["hair_dark"],
                         rot=(0, -20 * sx, 0)))
    # Pale eyes on a dark face -- the inverse of the villager's, for the same
    # reason: two dots of the opposite value is what makes a face.
    for sx in (-1, 1):
        side = "L" if sx < 0 else "R"
        plain.append(box("%s_Eye%s" % (tag, side),
                         (sx * 0.052, -0.554, 0.365),
                         (0.028, 0.018, 0.028), M["wool"]))

    # --- legs. OUTSIDE the fleece in plan (LEG_X 0.155 against a half-width of
    # 0.1425) and half the animal's height long. Both are SILHOUETTE decisions
    # rather than anatomy: a leg the body overhangs is a leg the play camera
    # never sees, and a belly with no daylight under it is a box on the floor.
    # Level, both pairs -- a leg forward in the rest pose is a limp added to
    # every frame of every clip.
    for sy, fb in ((-1, "F"), (1, "B")):
        for sx in (-1, 1):
            name = "%s_Leg%s%s" % (tag, fb, "L" if sx < 0 else "R")
            plain.append(box(name,
                             (sx * LEG_X, -0.160 if sy < 0 else 0.200,
                              LEG_TOP * 0.5),
                             (0.070, 0.070, LEG_TOP), M["hair_dark"]))

    plain.append(box(tag + "_Tail", (0, 0.315, 0.500),
                     (0.070, 0.060, 0.100), M["wool"]))

    # 0.09 asked, clamped to a quarter of the smallest dimension -- 7.1 cm on a
    # 28.5 cm box. That is as round as soften_all will make a box, and it is
    # the point: the sheep must have no straight edge and the cow must have
    # some.
    soften_all(hero, width=0.09, segments=2)
    soften_all(plain, width=0.0)
    return hero + plain
