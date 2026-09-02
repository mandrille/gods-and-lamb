"""ANIMALS.livestock.cow - the village herd. Milked for dairy.

Sibling to `sheep.py` and built to be its opposite in every channel that
survives to 40 px. The two stand in the same field and the player has to tell
them apart at a glance from 30 m up, so the differences are made on purpose
rather than left to happen:

              sheep                      cow
  mass        0.55 m tall, an oval       0.74 m tall, a long rectangle
  edges       8 cm bevel, no straight    4.5 cm bevel, corners you can see
  colour      cream all over             brown / WHITE BAND / brown
  plan        legs hidden inside         horns out past the shoulders
  head        small, dark, carried low   large, level, pale-faced

THE WHITE BAND IS A MASS, NOT A DECAL, and that is the whole lesson of the
first version. The play camera is pitched 35 degrees down, so the surface it
sees most of is the top of the barrel, and a single flat brown rectangle up
there reads as scenery rather than as an animal. The obvious fix -- lay white
patches on the spine -- produced exactly what it sounds like: two pale slabs
hovering a centimetre above the back, visibly not part of the cow from any
angle but straight down.

So the marking is the BARREL. The body is three masses; the middle one is
`plaster` and the two ends are `hair_warm`, the belt is therefore flush by
construction, it cannot float, it costs nothing, and from above the cow is an
unmistakable brown-white-brown bar. A Belted Galloway, near enough. When a
marking has to survive at thirty pixels, make it out of the shape.

THE HORNS reach just past the shoulders, and no further. Two versions of them
read as antlers on a moose -- 16 cm at a 22 degree lift, then 13 cm at 20 --
because a horn seen from the side shows its LONG face, and at that size a long
face is a plank. They are 11.5 cm at 16 degrees now, sitting on the poll rather
than above it, and they clear the widest part of the body by 6 mm. That margin
is the point: from directly overhead a quadruped's body plan is an anonymous
blob, and a pair of pale spurs past the shoulder line is the only unambiguous
cow signal at that angle.

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
    # MEASURED. X is set by the white band, which stands 6 mm proud of the
    # ribs; Y is muzzle to tail-tip.
    footprint=(0.46, 1.28),
    anchor="floor",
    slots=(),
    rig="critterrig",
)

LEG_TOP = 0.34            # legs run 0 .. LEG_TOP, up inside the barrel
BARREL_Z = 0.515          # centre of the main body mass


def build(tag="COW", **kw):
    # Three hero masses and everything else plain, same budget split as the
    # sheep: a bevelled box is nine plain ones on a 600-triangle cap.
    hero, plain = [], []

    # --- the barrel, in three masses, and the MIDDLE one is the white belt.
    # Shoulder is a touch taller than the rump, which is the one bit of real
    # cow anatomy that survives this far down: seen from the side a cow is a
    # wedge, high at the front.
    hero.append(box(tag + "_Body", (0, 0.06, BARREL_Z),
                    (0.440, 0.62, 0.440), M["plaster"]))
    hero.append(box(tag + "_BodyShoulder", (0, -0.24, BARREL_Z + 0.010),
                    (0.435, 0.28, 0.430), M["hair_warm"]))
    hero.append(box(tag + "_Rump", (0, 0.34, BARREL_Z - 0.010),
                    (0.435, 0.26, 0.420), M["hair_warm"]))

    # --- neck and head, carried LEVEL with the back rather than raised. A cow
    # holding its head up is a bull about to charge; at rest it carries it low
    # and forward, and that profile is also what stops the silhouette reading
    # as a horse.
    #
    # THE STEP DOWN FROM WITHERS TO POLL is what makes it a taper instead of a
    # train. The first version kept the neck nearly as tall as the barrel and
    # 30 cm wide against the head's 26, so shoulder, neck and head were three
    # rectangles of the same size in a row; the top line falls 0.74 -> 0.63 ->
    # 0.59 now and each mass is narrower than the one behind it.
    plain.append(box(tag + "_Neck", (0, -0.435, 0.495),
                     (0.265, 0.240, 0.265), M["hair_warm"]))
    plain.append(box(tag + "_Head", (0, -0.575, 0.475),
                     (0.235, 0.235, 0.230), M["hair_warm"]))
    # ONE white face marking in two boxes, blaze meeting muzzle at z=0.50 so it
    # runs unbroken from poll to nose. That is a Hereford, and it replaces a
    # PINK muzzle that was the loudest thing on the asset from every angle --
    # `petal_pink` at 15 x 8.5 cm on the front of the head read as a brick
    # glued to it. Pink survives on the udder, which is where a saturated hue
    # is worth having and where nothing but a close-up ever sees it.
    plain.append(box(tag + "_Muzzle", (0, -0.703, 0.425),
                     (0.150, 0.045, 0.085), M["plaster"]))
    plain.append(box(tag + "_Blaze", (0, -0.694, 0.520),
                     (0.125, 0.040, 0.115), M["plaster"]))
    for sx in (-1, 1):
        side = "L" if sx < 0 else "R"
        plain.append(box("%s_Eye%s" % (tag, side),
                         (sx * 0.072, -0.698, 0.528),
                         (0.040, 0.022, 0.040), M["hair_dark"]))
        # Ears BELOW the horns and set in from them, or the two merge into one
        # wide bar and the head grows a moustache.
        plain.append(box("%s_Ear%s" % (tag, side),
                         (sx * 0.145, -0.530, 0.535),
                         (0.098, 0.062, 0.046), M["hair_warm"],
                         rot=(0, -14 * sx, 0)))
        # Rotation about Y tilts the long axis in the XZ plane, and the sign
        # must flip with the side or one horn points at the sky and the other
        # at the ground. Sand, not `plaster`: the belt and the blaze are
        # already near-white, and three near-whites on one asset read as one
        # material with a lighting bug.
        plain.append(box("%s_Horn%s" % (tag, side),
                         (sx * 0.163, -0.552, 0.610),
                         (0.115, 0.040, 0.040), M["sand"],
                         rot=(0, -16 * sx, 0)))

    # --- legs. Long enough that the cow stands clear above the sheep's whole
    # silhouette, dark enough to separate from the barrel where they meet it.
    for sy, fb in ((-1, "F"), (1, "B")):
        for sx in (-1, 1):
            name = "%s_Leg%s%s" % (tag, fb, "L" if sx < 0 else "R")
            plain.append(box(name,
                             (sx * 0.150, -0.235 if sy < 0 else 0.330,
                              LEG_TOP * 0.5),
                             (0.118, 0.118, LEG_TOP), M["wood_dark"]))

    # The udder is the whole reason this asset exists in the design -- it is
    # what the villagers milk -- and it is invisible from the play camera. It
    # is here for the three-quarter view and it costs twelve triangles.
    plain.append(box(tag + "_Udder", (0, 0.300, 0.268),
                     (0.170, 0.180, 0.125), M["petal_pink"]))
    plain.append(box(tag + "_Tail", (0, 0.485, 0.478),
                     (0.050, 0.055, 0.385), M["hair_warm"]))
    plain.append(box(tag + "_TailTip", (0, 0.485, 0.272),
                     (0.065, 0.070, 0.080), M["hair_dark"]))

    # 0.045, against the sheep's 0.09. Half the radius on the same primitive is
    # the difference between an animal made of wool and an animal made of hide,
    # and at play distance it is most of what tells the two apart in shadow.
    soften_all(hero, width=0.045, segments=2)
    soften_all(plain, width=0.0)
    return hero + plain
