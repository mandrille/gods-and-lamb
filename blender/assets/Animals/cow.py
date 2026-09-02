"""ANIMALS.livestock.cow - the village herd. Milked for dairy.

Sibling to `sheep.py` and built to be its opposite in every channel that
survives to 40 px. The two stand in the same field and the player has to tell
them apart at a glance from 30 m up, so the differences are made on purpose
rather than left to happen:

              sheep                      cow
  mass        0.68 m tall, an oval       0.80 m tall, a long rectangle
  back        lumpy: rises at the withers  straight: 3 cm over its whole length
  edges       7 cm bevel, no straight    4.5 cm bevel, corners you can see
  colour      cream all over             brown / WHITE BAND / brown
  head        small, dark, low           large, pale-faced, HORNED
  stance      hooves 41.5 cm apart       hooves 51.5 cm apart

READ `sheep.py`'s HEADER FIRST. The five rules about what makes a shape read as
a creature from 35 degrees above -- legs wider than the body, legs fat enough to
survive a thumbnail, daylight under the belly, a head end and a rear end, and a
distinct back line -- were paid for on both assets at once and they are written
out there. This file obeys them with 44 cm of leg at 12.5 cm thick, a 34 cm
barrel standing inside a 51.5 cm stance, and a head carried on a neck 18 cm
below the line of the back.

THE WHITE BAND IS A MASS, NOT A DECAL. The play camera is pitched 35 degrees
down, so the surface it sees most of is the top of the barrel, and a single flat
brown rectangle up there reads as scenery. The obvious fix -- lay white patches
on the spine -- produced exactly what it sounds like: two pale slabs hovering a
centimetre above the back, visibly not part of the cow from any angle but
straight down. So the marking IS the barrel. The body is three masses; the
middle one is `plaster` and the two ends are `hair_warm`, the belt is therefore
flush by construction, it cannot float, it costs nothing, and from above the cow
is an unmistakable brown-white-brown bar. A Belted Galloway, near enough. When a
marking has to survive at thirty pixels, make it out of the shape.

THE HORNS reach past everything except the hooves, and they are the single
clearest animal cue at distance -- the one feature nothing else in the village
has. Two versions of them read as antlers on a moose (16 cm at a 22 degree lift,
then 13 cm at 20) because a horn seen from the side shows its LONG face, and at
that size a long face is a plank. They are 11.5 cm at 16 degrees now, sitting on
the poll rather than above it.

`cls="folk"` and `rig="critterrig"`, for the reasons written out in sheep.py.
Built at attention on z=0, fronting -Y.
"""
import os

from kit import M, box, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="folk",
    family="livestock",
    variant="cow",
    category=CATEGORY,
    # MEASURED. X is set by the HOOVES, which stand well outside the ribs so
    # the legs break the outline from above. Y is muzzle to tail-tip.
    footprint=(0.52, 1.32),
    anchor="floor",
    slots=(),
    rig="critterrig",
)

LEG_TOP = 0.44            # legs run 0 .. LEG_TOP; the barrel starts at 0.44
LEG_W = 0.125             # leg thickness. Eight pixels at play scale, not four.
LEG_X = 0.195             # half the stance. MUST exceed half the barrel width.
BARREL_Z = 0.610          # centre of the main body mass


def build(tag="COW", **kw):
    # Three hero masses and everything else plain, same budget split as the
    # sheep: a bevelled box is nine plain ones on a 600-triangle cap.
    hero, plain = [], []

    # --- the barrel, in three masses, and the MIDDLE one is the white belt.
    # The three tops sit within 3 cm of each other, so the back line is
    # STRAIGHT. That is the deliberate opposite of the sheep's, whose shoulder
    # stands 6 cm proud of its barrel, and at play distance the two back lines
    # are doing more work than the colours are.
    #
    # The barrel alone is long enough to reach both pairs of legs, so neither
    # end mass ever has to carry one -- same note, same reason, in sheep.py.
    hero.append(box(tag + "_Body", (0, 0.050, BARREL_Z),
                    (0.340, 0.66, 0.340), M["plaster"]))
    hero.append(box(tag + "_BodyShoulder", (0, -0.270, BARREL_Z + 0.015),
                    (0.335, 0.28, 0.350), M["hair_warm"]))
    hero.append(box(tag + "_Rump", (0, 0.350, BARREL_Z - 0.005),
                    (0.335, 0.26, 0.330), M["hair_warm"]))

    # --- neck and head, carried LOW and forward rather than raised. A cow
    # holding its head up is a bull about to charge; at rest it carries it
    # below the withers, and that drop is also what stops the plan outline
    # being a symmetrical bar.
    #
    # THE STEP DOWN FROM WITHERS TO POLL is what makes it a taper instead of a
    # train. An early version kept the neck nearly as tall as the barrel and
    # 30 cm wide against the head's 26, so shoulder, neck and head were three
    # rectangles of the same size in a row; the top line falls 0.80 -> 0.695 ->
    # 0.6175 now and each mass is narrower than the one behind it.
    plain.append(box(tag + "_Neck", (0, -0.475, 0.565),
                     (0.245, 0.240, 0.260), M["hair_warm"]))
    plain.append(box(tag + "_Head", (0, -0.635, 0.505),
                     (0.235, 0.235, 0.225), M["hair_warm"]))
    # ONE white face marking in two boxes, blaze meeting muzzle at z=0.495 so
    # it runs unbroken from poll to nose. That is a Hereford, and it replaced a
    # PINK muzzle that was the loudest thing on the asset from every angle --
    # `petal_pink` at 15 x 8.5 cm on the front of the head read as a brick
    # glued to it. Pink survives on the udder, which is where a saturated hue
    # is worth having and where nothing but a close-up ever sees it.
    plain.append(box(tag + "_Muzzle", (0, -0.762, 0.455),
                     (0.150, 0.045, 0.085), M["plaster"]))
    plain.append(box(tag + "_Blaze", (0, -0.753, 0.550),
                     (0.125, 0.040, 0.115), M["plaster"]))
    for sx in (-1, 1):
        side = "L" if sx < 0 else "R"
        plain.append(box("%s_Eye%s" % (tag, side),
                         (sx * 0.072, -0.757, 0.558),
                         (0.040, 0.022, 0.040), M["hair_dark"]))
        # Ears BELOW the horns and set in from them, or the two merge into one
        # wide bar and the head grows a moustache.
        plain.append(box("%s_Ear%s" % (tag, side),
                         (sx * 0.145, -0.590, 0.565),
                         (0.098, 0.062, 0.046), M["hair_warm"],
                         rot=(0, -14 * sx, 0)))
        # Rotation about Y tilts the long axis in the XZ plane, and the sign
        # must flip with the side or one horn points at the sky and the other
        # at the ground. Sand, not `plaster`: the belt and the blaze are
        # already near-white, and three near-whites on one asset read as one
        # material with a lighting bug.
        plain.append(box("%s_Horn%s" % (tag, side),
                         (sx * 0.175, -0.612, 0.640),
                         (0.115, 0.040, 0.040), M["sand"],
                         rot=(0, -16 * sx, 0)))

    # --- legs. OUTSIDE the barrel in plan (LEG_X 0.195 against a half-width
    # of 0.170, so 5.7 cm of every leg stands clear), 44 cm long against an
    # 80 cm animal, and 12.5 cm thick. An earlier version stood them at 0.155
    # inside a 0.220 half-width, so the body overhung every leg by 6.5 cm and
    # the play camera never saw one -- see sheep.py, rules 1 and 2.
    # `wood_dark` rather than the body brown, so the leg separates from the
    # barrel at the point where the two meet.
    for sy, fb in ((-1, "F"), (1, "B")):
        for sx in (-1, 1):
            name = "%s_Leg%s%s" % (tag, fb, "L" if sx < 0 else "R")
            plain.append(box(name,
                             (sx * LEG_X, -0.250 if sy < 0 else 0.340,
                              LEG_TOP * 0.5),
                             (LEG_W, LEG_W, LEG_TOP), M["wood_dark"]))

    # The udder is the whole reason this asset exists in the design -- it is
    # what the villagers milk -- and it is invisible from the play camera. It
    # is here for the three-quarter view and it costs twelve triangles.
    plain.append(box(tag + "_Udder", (0, 0.320, 0.400),
                     (0.170, 0.180, 0.130), M["petal_pink"]))
    plain.append(box(tag + "_Tail", (0, 0.495, 0.585),
                     (0.050, 0.055, 0.400), M["hair_warm"]))
    plain.append(box(tag + "_TailTip", (0, 0.495, 0.365),
                     (0.065, 0.070, 0.080), M["hair_dark"]))

    # 0.045, against the sheep's 0.09. Half the radius on the same primitive is
    # the difference between an animal made of wool and an animal made of hide,
    # and at play distance it is most of what tells the two apart in shadow.
    soften_all(hero, width=0.045, segments=2)
    soften_all(plain, width=0.0)
    return hero + plain
