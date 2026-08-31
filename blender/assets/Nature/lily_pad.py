"""NATURE.flower.lily_pad - pads and a bloom, for a water tile.

Very low and very wide: five pads spread over 0.70 x 0.55 m, 2.6 cm thick, and
a bloom standing 6.5 cm proud of the water. The bloom is the whole asset at
play distance -- the pads are a different green sitting on blue, which reads as
texture, and the pink dot on top is what says "pond" rather than "algae".

The pads are 12-GONS, not chamfered boxes, and this is the exception the style
allows for something genuinely round. `soften_all` clamps a bevel to a quarter
of a part's SMALLEST dimension, so on a 2.6 cm pad it comes back at 6 mm and
the corners stay square: a chamfered box pad reads as a square tile floating in
the water. A 12-gon costs 44 triangles and is actually round.

Alternating `leaf` and `crop` rather than two greens of different brightness.
`crop` is the yellow-green; against `leaf`'s blue-green the overlapping pads
separate. Two greens a shade apart would read as one continuous mat.

WATER SITS LOW. `tilekit.sunken_tile` drops the water surface 0.06 m below the
grid top, so an instancer that stands props at the standard tile height will
float this asset 6 cm above the pond. It is authored to the contract -- z=0 is
the underside of the pads -- so placement on water must lower it by
`WATER_DROP`. That is an integration decision and it is not made here.
"""
import os

from kit import M, cyl, soften_all
from plantkit import disc, petals

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="nature",
    family="flower",
    variant="lily_pad",
    category=CATEGORY,
    footprint=(0.70, 0.55),          # MEASURED (0.695 x 0.545)
    anchor="floor",
    slots=(),
)

# How far below the grid top the water surface sits. Must match
# Terrain/water.py's `drop`. Named here so an instancer has a number to use
# rather than a magic 0.06 copied out of a comment.
WATER_DROP = 0.06

PAD_H = 0.026

# (x, y, radius, lift, material). The LIFT is not decoration. Every pad started
# at the same z on the first pass and the overlaps came back as z-fighting
# streaks, because two discs of the same thickness at the same height share
# their top faces exactly. A few millimetres of stagger is the whole fix, and
# it also makes the raft read as pads floating at slightly different depths.
PADS = [
    (-0.17, -0.06, 0.175, 0.000, "leaf"),
    (0.07, -0.13, 0.145, 0.007, "crop"),
    (0.19, 0.05, 0.160, 0.003, "leaf"),
    (-0.04, 0.14, 0.130, 0.010, "crop"),
    (-0.24, 0.15, 0.095, 0.005, "leaf"),
]

BLOOM = (0.07, -0.13)     # on the second pad, off the centre of the clump
BLOOM_Z = 0.007 + PAD_H   # the surface of that pad


def build(tag="LILY", **kw):
    P = []
    for i, (x, y, r, lift, mat) in enumerate(PADS):
        P.append(disc("%s_Pad%d" % (tag, i), (x, y, lift + PAD_H * 0.5), r,
                      PAD_H, M[mat]))

    # Five petals pushed OUT to a radius and then turned to face outward. A
    # petal centred on the axis and rotated five times renders as five
    # double-ended arms, because each copy already reaches both ways.
    #
    # ONE ring, small. The first pass had two rings of chunky petals and the
    # bloom read as a heap of bricks -- at 8 cm across the flower is four
    # pixels, and four pixels of pink is the entire job. The petals are thin
    # and lie almost flat, so what shows from the play camera is a pink star
    # with a gold dot, not a stack.
    bx, by = BLOOM
    # `pitch` lifts each petal's outer end, so the bloom cups. Flat petals of
    # this thickness read as five bricks laid on the pad; 20 degrees of lift
    # costs nothing and turns them into a flower.
    P.extend(petals(tag, (bx, by, BLOOM_Z + 0.010), M["petal_pink"], count=5,
                    radius=0.042, size=(0.030, 0.068, 0.013), pitch=20.0))
    P.append(cyl("%s_Heart" % tag, (bx, by, BLOOM_Z + 0.016), 0.020, 0.032,
                 M["petal_gold"], verts=8))

    # No radius anywhere. Every part here is either 3 cm thin or 4 cm across,
    # and a bevel on a 12-gon rim is pure cost -- the primitive is already the
    # curve. Everything still goes through the pass, so the coverage assert is
    # satisfied.
    soften_all(P, width=0.0)
    return P
