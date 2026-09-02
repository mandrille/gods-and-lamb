"""ANIMALS.livestock.sheep - the village flock. Sheared for wool.

THE FIRST NON-PERSON FOLLOWER, and the thing it had to prove is that a
quadruped can go through the same pipeline as a villager without either of them
bending. It does: `cls="folk"`, because every number the pipeline cares about is
a follower's -- 600 triangles, 40 px tall, rigged, animated, walking between
tiles -- and `rig="critterrig"`, because the seven bones are arranged for four
legs instead of two. See `assets/_kit/critterrig.py`.

WHAT MAKES A SHEEP A SHEEP AT 40 PIXELS, in the order it matters:

  1. It is a CLOUD ON SHORT LEGS. The fleece is three overlapping boxes
     bevelled to within a whisker of collapsing -- 8 cm of radius on a 34 cm
     box -- so the silhouette has no straight edge anywhere. The cow beside it
     is built from the same boxes at half the radius and reads as hard. That
     contrast is most of what separates the two from above.
  2. The head is BLACK, SMALL and LOW. A Suffolk face is the one marking that
     survives being four pixels wide, and a sheep carries it well below the
     line of its own back -- which is also what stops the silhouette reading as
     a goat.
  3. The legs barely exist. First pass gave it 32 cm of leg and it came back
     looking like an occasional table; they are 22 cm now and set inside the
     fleece width, so from the play camera the animal is a woolly oval with a
     dark dot at one end.

COLOUR. `wool` is the only near-neutral in the palette and this asset is mostly
made of it, which walks straight into the house rule that every asset needs a
saturated hue. It gets one: a raddle mark sprayed on the back -- the paint a
real shepherd uses to tell his flock from the neighbour's -- and it is on the
one surface a camera pitched 35 degrees down actually sees. It is deliberately
off-centre. The POSE is symmetric; the DETAILS are not, and that split is the
rig's rule rather than a preference.

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
    # MEASURED with `-- measure`, not derived. X is the width across the ribs;
    # Y is nose to tail, and it is two and a half times the villager's because
    # an animal is long where a person is tall.
    footprint=(0.39, 0.87),
    anchor="floor",
    slots=(),
    # NOT folkrig. A biped skeleton on this body puts a femur through the
    # fleece and hangs the head off a shoulder.
    rig="critterrig",
)

LEG_TOP = 0.22            # legs run 0 .. LEG_TOP and vanish inside the fleece
BARREL_Z = 0.375          # centre of the main fleece mass
BACK_Z = 0.545            # top of the fleece, which is where the mark goes


def build(tag="SHEEP", **kw):
    # Hero parts carry the silhouette and earn a bevel; everything else is
    # smooth-shaded only. On a 600-triangle budget a bevelled box costs nine
    # plain ones, so the three fleece masses take the whole allowance and the
    # head, legs and trim go through soften_all at width 0.
    hero, plain = [], []

    # --- the fleece: three masses, not one box, because a single box reads as
    # a crate on legs from every angle.
    #
    # THE THREE WIDTHS ARE ALMOST EQUAL, and that is the fix for a fault the
    # first version had: at 0.38 / 0.365 / 0.33 the narrower lumps sat INSIDE
    # the barrel and their bevels met its side in a step, so the sheep had a
    # hard vertical notch across its shoulder -- the same fault villager.py
    # records on the hair. Within 5 mm the bevels merge into one continuous
    # cloud instead. The shape comes from the overlap in Y and Z, not from the
    # width.
    hero.append(box(tag + "_Fleece", (0, 0.02, BARREL_Z),
                    (0.380, 0.44, 0.340), M["wool"]))
    hero.append(box(tag + "_FleeceShoulder", (0, -0.155, BARREL_Z + 0.005),
                    (0.375, 0.26, 0.335), M["wool"]))
    hero.append(box(tag + "_FleeceRump", (0, 0.20, BARREL_Z - 0.003),
                    (0.375, 0.25, 0.330), M["wool"]))

    # The raddle mark. Sits 1 cm proud of the crown so it survives the bevel
    # pulling the top down, and off-centre in X because this is the asymmetry
    # the rest pose is not allowed to carry.
    plain.append(box(tag + "_Mark", (0.055, 0.06, BACK_Z - 0.010),
                     (0.110, 0.140, 0.035), M["cloth_red"]))

    # --- head and neck, carried LOW and well in front. Both dark: at this size
    # the face is one shape, and a separate jaw or cheek would be two pixels of
    # noise. The neck overlaps the shoulder mass by half its depth so the join
    # is buried rather than shown.
    plain.append(box(tag + "_Neck", (0, -0.315, 0.340),
                     (0.135, 0.130, 0.150), M["hair_dark"]))
    # There is no collar, and there were two attempts at one. Buried in the
    # fleece it showed 2 mm of red and read as a shading fault; sized to show,
    # it read as a bib hanging off the animal's chest. The join it was meant to
    # explain does not need explaining -- a black head against a cream fleece
    # is the strongest value contrast on the asset. The saturated hue the house
    # rule asks for is the raddle mark, which is also the one the play camera
    # actually sees.
    plain.append(box(tag + "_Head", (0, -0.395, 0.315),
                     (0.145, 0.175, 0.155), M["hair_dark"]))
    plain.append(box(tag + "_Muzzle", (0, -0.495, 0.285),
                     (0.095, 0.060, 0.080), M["hair_dark"]))
    # Wool coming down over the forehead. This is the marking that says SHEEP
    # rather than goat or dog. It has to CAP the skull and not overhang it: at
    # 15 x 11.5 x 6 cm it read as a mattress balanced on the animal's head, and
    # it is a third of that volume now. Small enough to be a tuft, proud enough
    # to break the black outline against the sky.
    plain.append(box(tag + "_Topknot", (0, -0.452, 0.385),
                     (0.130, 0.098, 0.045), M["wool"]))
    # Ears out to the SIDE, not back. From 35 degrees above they are most of
    # what makes the dark dot read as a head rather than as a hole.
    for sx in (-1, 1):
        side = "L" if sx < 0 else "R"
        plain.append(box("%s_Ear%s" % (tag, side),
                         (sx * 0.088, -0.365, 0.360),
                         (0.080, 0.050, 0.038), M["hair_dark"],
                         rot=(0, -18 * sx, 0)))
    # Pale eyes on a dark face -- the inverse of the villager's, for the same
    # reason: two dots of the opposite value is what makes a face. Set outside
    # the muzzle in X so they sit on cheek rather than on nose.
    for sx in (-1, 1):
        side = "L" if sx < 0 else "R"
        plain.append(box("%s_Eye%s" % (tag, side),
                         (sx * 0.052, -0.487, 0.330),
                         (0.028, 0.018, 0.028), M["wool"]))

    # --- legs. Short, thin, dark, and set INSIDE the fleece width so the
    # overhead silhouette stays a clean oval. Level, both pairs: a leg forward
    # in the rest pose is a limp added to every frame of every clip.
    for sy, fb in ((-1, "F"), (1, "B")):
        for sx in (-1, 1):
            name = "%s_Leg%s%s" % (tag, fb, "L" if sx < 0 else "R")
            plain.append(box(name,
                             (sx * 0.120, -0.140 if sy < 0 else 0.190,
                              LEG_TOP * 0.5),
                             (0.064, 0.064, LEG_TOP), M["hair_dark"]))

    plain.append(box(tag + "_Tail", (0, 0.300, 0.400),
                     (0.070, 0.065, 0.100), M["wool"]))

    # 0.09 asked, clamped to a quarter of the smallest dimension -- 8.4 cm on a
    # 34 cm box. That is as round as soften_all will make a box, and it is the
    # point: the sheep must have no straight edge and the cow must have some.
    soften_all(hero, width=0.09, segments=2)
    soften_all(plain, width=0.0)
    return hero + plain
