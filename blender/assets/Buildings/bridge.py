"""BUILDING.bridge.bridge - ONE plank bridge section, exactly one tile long.

Same contract as `fence`: a run piece chained along +X, so the X span must be
EXACTLY the 0.5 m grid module or a crossing drifts by a plank every section.
`-- measure` has to come back 0.5000 on X.

The deck is four separate planks with gaps rather than one slab. Over water the
gaps are the only thing that says "planks" at forty pixels -- a solid slab in
`wood` reads as a brown tile. The outermost planks are placed so their outer
faces land exactly on +/-0.25, which is what fixes the module; everything else
about the spacing is free.

There are no rails. Every placement of this asset got the yaw wrong in a new
way while it had them -- handrails cutting through their own planks, rails
laid across the span instead of along it -- and a flat deck simply has no
wrong orientation available. Rotate it ninety degrees and it is still a
correct bridge.

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
    # MEASURED. X is the module by construction; Y is now just the deck, since
    # the rails that used to stand outboard of it are gone.
    footprint=(0.50, 0.62),
    anchor="floor",
    slots=(),
)

DECK_D = 0.62                 # across the crossing, Y
PLANKS = 4
PLANK_GAP = 0.022
STRINGER_Z, STRINGER_T = 0.035, 0.070
DECK_Z, DECK_T = 0.098, 0.056


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

    # NO RAILS. They were posts and two handrails outboard on Y, and every
    # time this asset was placed the yaw was wrong in some new way -- rails
    # cutting through the planks, rails running across the span instead of
    # along it. A flat deck has no wrong orientation to get wrong: rotate it
    # ninety degrees and it is still a correct bridge.
    #
    # It also matches what the deck is FOR here. These are short crossings
    # over a shallow stream, not a viaduct, and the reference art has a plain
    # plank causeway.

    soften_all(P, width=0.022, segments=2)
    return P
