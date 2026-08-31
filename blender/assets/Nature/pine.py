"""NATURE.tree.pine - the tall conifer.

Exists to be a SILHOUETTE against `tree`. The broadleaf is a wide round-ish
crown on a short trunk; this is a narrow triangle twice as tall as it is wide.
Two tree shapes in a wood read as a wood. Two of the same shape read as one
asset instanced twice, which is exactly what the island shot showed.

Six stacked chamfered boxes, tapering. Not a cone: `kit.cone` at the vertex
count this needs is a smooth curve, and a smooth curve next to the boxy
canopies and boxy ground blocks is the one part that does not belong. The
tapering stack also gives the tiers a conifer reads by, for free.

WEDDING CAKE is the failure mode here, and the first pass was one. Five tiers
with a 17 per cent width step and 12 cm of overlap left a broad flat shelf on
top of every tier, and five flat shelves in a column read as a tiered cake, not
as a tree. The fix is both halves of that: SMALL width steps (about 12 per
cent, so the tier above nearly covers the one below) and LARGE overlaps (about
half a tier), plus a few degrees of pitch on each so no shelf is horizontal.
The pitch is what kills the cake -- a tilted top face reads as a drooping bough
and a level one reads as a plate.

The greens run dark at the bottom to light at the top rather than alternating.
Alternating banded the trunk like a barber's pole; a single ramp reads as light
coming from above, which is where it comes from.

Fronts -Y, like everything floor-standing.
"""
import os

from kit import M, blob, cyl, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="nature",
    family="tree",
    variant="pine",
    category=CATEGORY,
    # MEASURED (1.220 x 1.216). The tiers are yawed, so their corners reach
    # further than 0.98 x 0.94 suggests -- the widest one alone spans 1.22 m
    # across X, a quarter more than its box size.
    footprint=(1.22, 1.22),
    anchor="floor",
    slots=(),
)

TRUNK_H = 0.36
TRUNK_R = 0.080

# (z centre, size, material, tilt). Yaws are deliberately not multiples of each
# other: a stack on a shared angle lines its corners up and the whole tree
# reads as one extruded prism. The pitch (the first two numbers of the tilt)
# alternates sign so the boughs droop different ways rather than the whole tree
# leaning.
TIERS = [
    (0.53, (0.98, 0.94, 0.56), "leaf_dark", (4.0, -3.0, 16.0)),
    (0.83, (0.88, 0.84, 0.54), "leaf_dark", (-3.0, 5.0, -11.0)),
    (1.13, (0.75, 0.72, 0.52), "leaf", (5.0, 4.0, 27.0)),
    (1.42, (0.61, 0.58, 0.50), "leaf", (-4.0, -5.0, -21.0)),
    (1.69, (0.46, 0.44, 0.47), "leaf_light", (3.0, 6.0, 9.0)),
    (1.94, (0.29, 0.28, 0.44), "leaf_light", (-5.0, 3.0, -30.0)),
]


def build(tag="PINE", **kw):
    # No root flare. The lowest tier hangs to 0.25 m and covers the base, so
    # `tree`'s four flare boxes would be 176 triangles of geometry nobody can
    # see -- and six tiers at two segments needs every one of them.
    trunk = [cyl(tag + "_Trunk", (0, 0, TRUNK_H * 0.5), TRUNK_R, TRUNK_H,
                 M["trunk"], verts=8)]

    canopy = [blob("%s_Tier%d" % (tag, i), (0.0, 0.0, z), size, M[mat],
                   tilt=tilt)
              for i, (z, size, mat, tilt) in enumerate(TIERS)]

    # Two passes, same split as `tree`: the canopy IS the silhouette and gets
    # the chunky 7 cm radius the ground blocks use, the trunk is a few pixels
    # at play distance and gets one segment. Six tiers at two segments is what
    # this asset spends nearly all of its budget on, so the trunk cannot also
    # have a fat one.
    soften_all(canopy, width=0.07, segments=2)
    soften_all(trunk, width=0.05, segments=1)
    return trunk + canopy
