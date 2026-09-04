"""FOLK.folk.hunter - watches the tree line, brings back meat.

The reference is a green-hooded archer with a stern brow, a topknot, a belt
of pouches and a longbow. At 40 px only the silhouette-scale pieces of that
survive: the topknot bun, the hood collar, and the bow held out to the side.
The stern brow is the one small-scale detail kept anyway, because it sits
right where the eye already lands on every follower (the face) and costs one
thin box.

`hair="topknot"` leaves the sides bare on purpose (its own docstring) -- this
job does not fight that, it is what makes the silhouette read as an archer
rather than another cap-haired villager.

No apron, no kerchief: the hood collar (`_Hood`) stands in for both, built the
same "one box wraps the whole neck" way folkbody's own kerchief is.

Fronts -Y, symmetric rest pose -- the bow is held in a level hand, not drawn;
drawing it would be a pose baked into every walk frame.
"""
import os

from kit import M, box, cyl
from folkbody import BACK, BELT, BROW, HAND_L, HIP_L, HIP_R, body, finish

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="folk",
    family="folk",
    variant="hunter",
    category=CATEGORY,
    # MEASURED: the bow's limbs set X, the quiver on the back sets Y --
    # both past the shared body's own column.
    footprint=(0.44, 0.37),
    anchor="floor",
    slots=(),
)

PALETTE = dict(tunic="cloth_green", hair="hair_warm", skin="skin",
               boots="leather", legs="wood_dark")


def build(tag="HUNTER", **kw):
    hero, plain = body(tag, PALETTE, hair="topknot", apron=False,
                       kerchief=False, hands="level")

    extra_plain = [
        # Stern brow: one thin dark box, level, right above the eyes.
        box(tag + "_Brow", BROW, (0.16, 0.02, 0.03), M["hair_dark"]),
        # Hood collar -- wraps the whole neck like folkbody's own kerchief.
        # `cloth_orange`: green tunic + green hood + green sleeves was one
        # green mass on green grass (review); the reference carries a warm
        # trim band, and this is the follower that most needs one.
        box(tag + "_Hood", (0, 0.0, BROW[2] - 0.30),
           (0.27, 0.24, 0.075), M["cloth_orange"]),
        box(tag + "_Belt", BELT, (0.26, 0.20, 0.032), M["leather"]),
        box(tag + "_Pouch1", (HIP_L[0] - 0.01, HIP_L[1] - 0.05, HIP_L[2] + 0.06),
           (0.07, 0.06, 0.08), M["leather"]),
        box(tag + "_Pouch2", (HIP_R[0] + 0.01, HIP_R[1] - 0.05, HIP_R[2] + 0.06),
           (0.07, 0.06, 0.08), M["leather"]),
        # Bow in the left hand: grip plus two angled limbs, all wood, plus a
        # thin taut string running between the tips.
        # Limbs at 4.5 cm: three 2.4 cm sticks were one dark line at 40 px
        # (review). The 1 cm string cost a box and read as nothing -- gone.
        box(tag + "_BowGrip", (HAND_L[0], HAND_L[1] - 0.025, HAND_L[2]),
           (0.045, 0.045, 0.11), M["wood"]),
        box(tag + "_BowUpper", (HAND_L[0] - 0.03, HAND_L[1] - 0.025, HAND_L[2] + 0.125),
           (0.045, 0.045, 0.20), M["wood"], rot=(0, -18, 0)),
        box(tag + "_BowLower", (HAND_L[0] - 0.03, HAND_L[1] - 0.025, HAND_L[2] - 0.125),
           (0.045, 0.045, 0.20), M["wood"], rot=(0, 18, 0)),
        # Quiver on the back, angled off the diagonal like the adventurer's
        # pack strap -- a detail, not a pose.
        cyl(tag + "_Quiver", (BACK[0] + 0.03, BACK[1], BACK[2]), 0.045, 0.26,
           M["leather"], axis="Z", rot=(12, 0, -8)),
    ]

    return finish(hero, plain, extra_plain=extra_plain)
