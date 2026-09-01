"""NATURE.fruit.apples - a small heap of apples left on the ground.

What the Feast miracle actually PUTS THERE. A miracle that only plays a
particle burst is a miracle the player has to take on trust; a heap of fruit
that villagers then walk over and pick up is one they can watch work.

Three apples and a couple of leaves, deliberately asymmetric so the scatter
can rotate one piece and get variety for free -- the same trick `bush` uses.
The heap sits low: it is food on the grass, not a market display, and at play
distance anything taller reads as a bush.
"""
import os

from kit import M, blob, box, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="nature",
    family="fruit",
    variant="apples",
    category=CATEGORY,
    # MEASURED, not derived: the heap is wider than any single apple because
    # the three are offset, and a footprint guessed from one radius would let
    # a villager stand inside it.
    footprint=(0.34, 0.31),
    anchor="floor",
    slots=(),
)

R = 0.085
# The bevel rounds the bottom of each blob, so a sphere centred at z=R does not
# TOUCH z=0 -- it sits 6.4 mm proud, which is what assert_anchor measured and
# refused. Everything is dropped by that, once, rather than each apple being
# nudged by eye until the gate stopped complaining.
DROP = 0.0064


def build(tag="APPLES", **kw):
    P = []
    # Three, at different heights, so the heap has a top rather than being a
    # row. The tilts stop the spheres reading as identical instances.
    for i, (x, y, z, tilt) in enumerate((
            (-0.075, -0.020, R - DROP, (0, 0, 14)),
            (0.070, 0.035, R - DROP, (0, 0, -22)),
            (0.005, -0.055, R * 2.1 - DROP, (0, 0, 6)))):
        P.append(blob("%s_Apple%d" % (tag, i), (x, y, z),
                      (R * 2.0, R * 1.9, R * 1.85), M["petal_red"], tilt=tilt))

    # One stalk and one leaf on the top apple only. On all three it reads as
    # a bush; on one it reads as fruit.
    P.append(box(tag + "_Stalk", (0.005, -0.055, R * 2.1 + 0.075 - DROP),
                 (0.016, 0.016, 0.070), M["wood_dark"]))
    P.append(blob(tag + "_Leaf", (0.062, -0.048, R * 2.1 + 0.082 - DROP),
                  (0.105, 0.052, 0.022), M["leaf"], tilt=(0, 18, 24)))

    soften_all(P, width=0.022, segments=2)
    return P
