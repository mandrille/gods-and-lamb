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
     the hooves stand 41.5 cm apart, so they break the outline on both sides.
  2. THE LEGS MUST ALSO BE FAT. Fixing the stance alone was not enough. At the
     play camera this animal is about 35 px long -- 65 px to the metre -- so a
     7 cm leg is four pixels before antialiasing takes two of them back, and
     four thin dark strokes under a white body simply dissolve. They are 8.5 cm
     now, thicker than any real sheep's.
  3. GROUND UNDER THE BELLY. 34 cm of clearance on a 68 cm animal: half its
     height is leg. That is what puts grass and a separate shadow underneath,
     and grass under a shape is the whole difference between a creature
     standing on the ground and an object resting on it.
  4. A HEAD END AND A REAR END. The head hangs on a narrow neck, 23 cm in front
     of the fleece and 14 cm below the line of the back, so the plan outline
     points one way. Front-to-back asymmetry is most of what makes a shape read
     as an animal at 40 px; a symmetrical blob reads as an object however well
     it is modelled.
  5. A LUMPY TOP. The three fleece masses sit at three different heights, so
     the back rises 6 cm over the shoulder and falls away to the rump. The
     cow's back is deliberately straight to within 3 cm. That difference
     survives to play distance when nothing else about the two shapes does.

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
    # by the ribs -- 41.5 cm of stance around a 28.5 cm body -- which is the
    # entire point of the stance. Y is nose to tail.
    footprint=(0.42, 0.91),
    anchor="floor",
    slots=(),
    # NOT folkrig. A biped skeleton on this body puts a femur through the
    # fleece and hangs the head off a shoulder.
    rig="critterrig",
)

LEG_TOP = 0.34            # legs run 0 .. LEG_TOP; the fleece starts at 0.33
LEG_W = 0.085             # leg thickness. Four pixels at play scale, not two.
LEG_X = 0.165             # half the stance. MUST exceed half the fleece width.
BARREL_Z = 0.480          # centre of the main fleece mass


def build(tag="SHEEP", **kw):
    # Hero parts carry the silhouette and earn a bevel; everything else is
    # smooth-shaded only. On a 600-triangle budget a bevelled box costs nine
    # plain ones, so the three fleece masses take the whole allowance and the
    # head, legs and trim go through soften_all at width 0.
    hero, plain = [], []

    # --- the fleece: three masses at THREE DIFFERENT HEIGHTS. A single box
    # reads as a crate on legs; three boxes with a level top read as a longer
    # crate. The shoulder tops out 6.6 cm above the rump and 5 cm above the
    # barrel, which is a back line with a HUMP in it -- the one shape cue that
    # separates this from the cow at any distance, and the reason the cow's
    # three masses are deliberately level to within 3 cm.
    #
    # The widths stay within 1 cm of each other. At 38 / 36.5 / 33 the narrower
    # lumps sat INSIDE the barrel and their bevels met its side in a hard
    # vertical notch across the shoulder, the same fault villager.py records on
    # the hair. The shape comes from the overlap in Y and Z, never from width.
    # The BARREL alone is long enough to reach both pairs of legs. The lumps
    # are then free to sit high without opening a gap over a shoulder, which is
    # what happened when the front legs hung off a lump whose underside had
    # been raised to make the back line interesting.
    hero.append(box(tag + "_Fleece", (0, 0.010, BARREL_Z),
                    (0.285, 0.44, 0.300), M["wool"]))
    hero.append(box(tag + "_FleeceShoulder", (0, -0.175, BARREL_Z + 0.040),
                    (0.278, 0.28, 0.320), M["wool"]))
    hero.append(box(tag + "_FleeceRump", (0, 0.200, BARREL_Z - 0.010),
                    (0.280, 0.26, 0.300), M["wool"]))

    # --- head and neck. The neck is a real mass and not a seam: it carries the
    # head down and out in front of the fleece so the plan view has a pointed
    # end. Both dark -- at this size a face is one shape, and a separate jaw
    # would be two pixels of noise.
    plain.append(box(tag + "_Neck", (0, -0.300, 0.490),
                     (0.110, 0.150, 0.175), M["hair_dark"]))
    # The collar rings the NECK, which is where a collar goes. An earlier
    # version put this same red as a mark on the back and it read as a button
    # on a gadget; an earlier one still made it a slab across the chest and it
    # read as a bib. On a neck that is now a visible separate mass it simply
    # reads as a collar -- and it is the only saturated hue on an asset made
    # almost entirely of near-white.
    plain.append(box(tag + "_Collar", (0, -0.340, 0.485),
                     (0.130, 0.050, 0.185), M["cloth_red"]))
    # THE HEAD RIDES AT MID-HEIGHT, not down at the hooves. Carrying it low is
    # right for a sheep and the first attempt at it took the instruction too
    # far: at 15.5 x 19 x 17 cm centred on z=0.355 the head was as big as a
    # third of the fleece and hung down among the front legs, so from the play
    # camera the animal had two body masses and no neck. It is two thirds that
    # volume now and sits between the belly line and the back -- forward of the
    # fleece, below the spine, clear of the legs.
    plain.append(box(tag + "_Head", (0, -0.420, 0.460),
                     (0.140, 0.170, 0.155), M["hair_dark"]))
    plain.append(box(tag + "_Muzzle", (0, -0.518, 0.430),
                     (0.090, 0.055, 0.078), M["hair_dark"]))
    # Wool coming down over the forehead. This is the marking that says SHEEP
    # rather than goat or dog, and it is the only pale thing on the head -- so
    # from above it is what stops the head reading as the animal's own shadow.
    plain.append(box(tag + "_Topknot", (0, -0.455, 0.543),
                     (0.118, 0.088, 0.036), M["wool"]))
    # Ears out to the SIDE, not back.
    for sx in (-1, 1):
        side = "L" if sx < 0 else "R"
        plain.append(box("%s_Ear%s" % (tag, side),
                         (sx * 0.080, -0.390, 0.515),
                         (0.074, 0.045, 0.033), M["hair_dark"],
                         rot=(0, -20 * sx, 0)))
    # Pale eyes on a dark face -- the inverse of the villager's, for the same
    # reason: two dots of the opposite value is what makes a face.
    for sx in (-1, 1):
        side = "L" if sx < 0 else "R"
        plain.append(box("%s_Eye%s" % (tag, side),
                         (sx * 0.046, -0.528, 0.442),
                         (0.024, 0.016, 0.024), M["wool"]))

    # --- legs. OUTSIDE the fleece in plan (LEG_X 0.165 against a half-width
    # of 0.1425, so 2.3 cm of every leg stands clear of the body), half the
    # animal's height long, and deliberately too fat. All three are SILHOUETTE
    # decisions rather than anatomy: a leg the body overhangs is a leg the play
    # camera never sees, a belly with no daylight under it is a box on the
    # floor, and a leg under 8 cm is two pixels at the size this is judged at.
    # Level, both pairs -- a leg forward in the rest pose is a limp added to
    # every frame of every clip.
    for sy, fb in ((-1, "F"), (1, "B")):
        for sx in (-1, 1):
            name = "%s_Leg%s%s" % (tag, fb, "L" if sx < 0 else "R")
            plain.append(box(name,
                             (sx * LEG_X, -0.160 if sy < 0 else 0.200,
                              LEG_TOP * 0.5),
                             (LEG_W, LEG_W, LEG_TOP), M["hair_dark"]))

    plain.append(box(tag + "_Tail", (0, 0.325, 0.530),
                     (0.070, 0.060, 0.100), M["wool"]))

    # 0.09 asked, clamped to a quarter of the smallest dimension -- 7.1 cm on a
    # 28.5 cm box. That is as round as soften_all will make a box, and it is
    # the point: the sheep must have no straight edge and the cow must have
    # some.
    soften_all(hero, width=0.09, segments=2)
    soften_all(plain, width=0.0)
    return hero + plain
