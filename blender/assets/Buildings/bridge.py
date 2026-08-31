"""BUILDING.bridge.bridge - ONE plank bridge section, exactly one tile long.

Same contract as `fence`: a run piece chained along +X, so the X span must be
EXACTLY the 0.5 m grid module or a crossing drifts by a plank every section.
`-- measure` has to come back 0.5000 on X.

The deck is four separate planks with gaps rather than one slab. Over water the
gaps are the only thing that says "planks" at forty pixels -- a solid slab in
`wood` reads as a brown tile. The outermost planks are placed so their outer
faces land exactly on +/-0.25, which is what fixes the module; everything else
about the spacing is free.

Rails get one post per section at the LEFT end, for the reason fence.py gives:
a post at each end doubles into a lump at every joint.

The stringers underneath are `wood_dark` and run the full module. They are not
decoration -- without them you see daylight between the planks straight down to
the water, and the deck stops reading as a solid thing to walk on.
"""
import os

from kit import M, box, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

from tilekit import SIZE as TILE

ASSET = dict(
    cls="building",
    family="bridge",
    variant="bridge",
    category=CATEGORY,
    # MEASURED. X is the module by construction; Y is the rail posts, which sit
    # outboard of the deck.
    footprint=(0.50, 0.68),
    anchor="floor",
    slots=(),
)

DECK_D = 0.62                 # across the crossing, Y
PLANKS = 4
PLANK_GAP = 0.022
STRINGER_Z, STRINGER_T = 0.035, 0.070
DECK_Z, DECK_T = 0.098, 0.056
POST_W, POST_D, POST_H = 0.060, 0.060, 0.46
RAIL_T = 0.045
RAIL_Z = (0.26, 0.40)     # top rail top must clear POST_H, see below


def build(tag="BRIDGE", **kw):
    P = []

    # Two beams carrying the deck, inboard of the rail posts.
    for sy, side in ((-1, "F"), (1, "B")):
        P.append(box("%s_Stringer%s" % (tag, side),
                     (0.0, sy * (DECK_D * 0.5 - 0.075), STRINGER_Z),
                     (TILE, 0.090, STRINGER_T), M["wood_dark"]))

    # The plank width is solved from the module, NOT chosen: N planks and N-1
    # gaps must add up to exactly TILE, and then the end planks' outer faces
    # land on +/-TILE/2 by construction. Laying planks on a TILE/N pitch instead
    # centres them in their cells and leaves half a gap at each end, which
    # measured 0.478 and would have opened a 2 cm seam every section.
    plank_w = (TILE - (PLANKS - 1) * PLANK_GAP) / PLANKS
    for i in range(PLANKS):
        x = -TILE * 0.5 + plank_w * 0.5 + i * (plank_w + PLANK_GAP)
        P.append(box("%s_Plank%d" % (tag, i), (x, 0.0, DECK_Z),
                     (plank_w, DECK_D, DECK_T), M["wood"]))

    # Rails. One post per side, flush to the left edge of the module.
    px = -TILE * 0.5 + POST_W * 0.5
    post_top = DECK_Z + POST_H
    for sy, side in ((-1, "F"), (1, "B")):
        # Overlapping the deck edge by 3 cm, not standing clear of it. Set
        # outboard with an 18 mm air gap the post had nothing under it and
        # nothing beside it, and the first render was a rail hanging in space
        # next to the planks.
        py = sy * (DECK_D * 0.5 + POST_D * 0.5 - 0.030)
        # Down to z=0. These are piles: a bridge post that starts at deck level
        # is standing on the water.
        P.append(box("%s_Post%s" % (tag, side), (px, py, post_top * 0.5),
                     (POST_W, POST_D, post_top), M["wood_dark"]))
        # The top rail sits BELOW the post top, not level with it. At 0.44 its
        # rounded top stood 2.5 mm proud of the post and the post stopped
        # reading as a post -- a newel that does not cap its rail looks like a
        # rail that has been stabbed.
        for j, z in enumerate(RAIL_Z):
            P.append(box("%s_Rail%s%d" % (tag, side, j), (0.0, py, DECK_Z + z),
                         (TILE, 0.038, RAIL_T), M["wood"]))

    soften_all(P, width=0.022, segments=2)
    return P
