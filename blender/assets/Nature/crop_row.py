"""NATURE.crop.crop_row - a whole tile of ripe cereal.

One asset covering a whole tile, not nine instanced sprouts: cheaper, it reads
better at play distance, and a field of it tiles without a visible grid of
identical plants.

Stalks, not rows. The first version was four long blades with a wide slab on
top of each, and in the island shot it read as a stack of planks lying at an
angle -- nothing like a crop. Cereal is a lot of thin vertical things, so that
is what this is: seven stalks scattered off the axes, each with a fatter ripe
head, leaning slightly in different directions.

Deliberately NOT bevelled. soften_all(width=0.0) smooth-shades and tags them
without adding a radius, because a 5 cm stalk has no edge anyone can see and a
bevel on fourteen boxes was the whole of an 864-tri asset against a 800 cap.
Everything still goes through the pass, so the coverage assert is satisfied.
"""
import os

from kit import M, box, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="nature",
    family="crop",
    variant="crop_row",
    category=CATEGORY,
    footprint=(0.68, 0.70),
    anchor="floor",
    slots=(),
)

H = 0.40          # stalk height
STALK = 0.048
HEAD = 0.085

# Scattered by hand rather than on a grid, and off the tile axes, so a field of
# these does not read as a lattice. (x, y, lean_x, lean_y)
STALKS = [
    (-0.26, -0.22, 5.0, -3.0),
    (-0.05, -0.30, -4.0, 6.0),
    (0.24, -0.18, 7.0, 2.0),
    (-0.30, 0.06, -6.0, -5.0),
    (-0.02, 0.02, 3.0, 4.0),
    (0.27, 0.11, -5.0, -2.0),
    (0.06, 0.29, 4.0, -6.0),
]


def build(tag="CROP", **kw):
    P = []
    for i, (x, y, lx, ly) in enumerate(STALKS):
        P.append(box("%s_Stalk%d" % (tag, i), (x, y, H * 0.5),
                     (STALK, STALK, H), M["crop"], rot=(ly, lx, 0)))
        # The head is the only ripe-coloured part. A stalk that is gold all the
        # way down reads as straw, not as wheat.
        P.append(box("%s_Head%d" % (tag, i), (x, y, H - 0.06),
                     (HEAD, HEAD, 0.17), M["crop_ripe"], rot=(ly, lx, 0)))
    soften_all(P, width=0.0)
    return P
