"""TERRAIN.ground.grass - one village ground tile.

The first asset in the project, and it exists to prove three things before
anything else is built on them: that the palette reads, that the rounding pass
lands, and that a tile of this shape actually tiles.

That last one drives the geometry. The art direction is rounded cubes, so the
obvious build is a 1 m box through soften_all(). It is wrong: bevelling the
vertical edges pulls the four side faces inward, and two neighbouring tiles
then meet with a gap you can see the sky through. So the sides stay flat and
full width and only the top rim is rounded -- soften_top() -- which leaves a
shallow groove between tiles that reads as the tile grid in the reference art.

Two boxes, not one: a grass cap over a dirt body. A single box would show grass
down the cliff faces, and every exposed edge in the village is a cliff face.
"""
import os

from kit import M, box, soften_top, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="terrain",
    family="ground",
    variant="grass",
    category=CATEGORY,
    footprint=(1.0, 1.0),
    anchor="floor",
    slots=(),
)

SIZE = 1.0        # the grid module. Nothing may overhang it.
HEIGHT = 1.0      # top surface at z=1.0; everything that stands on the ground
                  # assumes exactly this.
CAP = 0.18        # depth of the grass layer down the side faces


def build(tag="GRASS", **kw):
    cap_z = HEIGHT - CAP * 0.5
    body_h = HEIGHT - CAP

    # Built as two stacked boxes that MEET rather than overlap. Two coplanar
    # faces inside a solid would z-fight the moment the tile is instanced a few
    # hundred times, and the merge welds the seam anyway.
    body = box(tag + "_Body", (0, 0, body_h * 0.5), (SIZE, SIZE, body_h),
               M["dirt"])
    cap = box(tag + "_Cap", (0, 0, cap_z), (SIZE, SIZE, CAP), M["grass"])

    # Only the cap is top-rounded -- it owns the top face. The body is buried
    # between its neighbours and the cap above it, so rounding it would cost
    # triangles for geometry nobody can see, and would open the very gap this
    # asset exists to avoid.
    soften_top(cap, width=0.09, segments=3)
    soften_all([body], width=0.0)   # smooth-shade only; tags it `softened`

    return [body, cap]
