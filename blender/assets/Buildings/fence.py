"""BUILDING.fence.fence - ONE fence section, exactly one tile long.

This is a run piece, not a building: the village chains copies of it end to end
along +X, so the X span must be EXACTLY the 0.5 m grid module. Anything else
accumulates a gap or an overlap every section and a ten-post run is visibly
crooked by the far end. `-- measure` has to come back 0.5000 on X.

That is also why there is only ONE post, flush against the LEFT end rather than
one at each end. A post at each end doubles up at every joint into a fat lump,
and a post straddling the boundary would push the span past 0.5. One post per
section reads as a properly spaced run; the far end of a run simply finishes on
a rail, which is what a real fence does anyway.

Waist-high on purpose -- 0.62 against a 0.9 m follower. A fence that clears a
follower's head reads as a stockade, and this is a garden.

Fronts -Y: the rails face the viewer, the post is behind them.
"""
import os

from kit import M, box, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

# The grid module. Imported rather than written as 0.5 so that a change to the
# tile size cannot leave this silently one module out of step.
from tilekit import SIZE as TILE

ASSET = dict(
    cls="building",
    family="fence",
    variant="fence",
    category=CATEGORY,
    # MEASURED. X is the tile exactly, by construction. Y is the post, which is
    # deeper than the rails.
    footprint=(0.50, 0.12),
    anchor="floor",
    slots=(),
)

POST_W, POST_D = 0.075, 0.090
POST_H = 0.62
CAP_W, CAP_D = POST_W + 0.030, POST_D + 0.030
RAIL_T, RAIL_D = 0.045, 0.040       # thickness in Z, depth in Y
RAIL_Z = (0.26, 0.50)


def build(tag="FENCE", **kw):
    P = []

    # Rails span the full module, x = -0.25 .. +0.25, so consecutive sections
    # butt into a continuous timber line. The bevel rounds the rail corners but
    # leaves the end FACE at x = +/-0.25, so the AABB stays exactly one tile.
    for i, z in enumerate(RAIL_Z):
        P.append(box("%s_Rail%d" % (tag, i), (0.0, 0.0, z),
                     (TILE, RAIL_D, RAIL_T), M["wood"]))

    # The post is inset by half the CAP width, not half the post width: the cap
    # is the widest thing on the post and it is the cap that has to stay inside
    # the module. Sizing this off POST_W put the cap 1.8 cm over the boundary
    # and the section measured 0.518.
    px = -TILE * 0.5 + CAP_W * 0.5
    P.append(box(tag + "_Post", (px, 0.0, POST_H * 0.5),
                 (POST_W, POST_D, POST_H), M["wood_dark"]))
    # A cap wider than the post, so the top of the run is a row of dots rather
    # than a row of line-ends. At forty pixels that is the whole silhouette.
    P.append(box(tag + "_Cap", (px, 0.0, POST_H + 0.022),
                 (CAP_W, CAP_D, 0.045), M["wood"]))

    # 2.4 cm: soften_all clamps to a quarter of the smallest dimension, so the
    # 4 cm rails get 1 cm and stay rails.
    soften_all(P, width=0.024, segments=2)
    return P
