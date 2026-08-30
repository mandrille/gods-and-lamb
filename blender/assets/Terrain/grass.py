"""TERRAIN.ground.grass - one village ground tile.

The first asset in the project, and it exists to prove three things before
anything else is built on them: that the palette reads, that the rounding pass
lands, and that a tile of this shape actually tiles.

Shape follows the Kubikos-style reference: a chunky cube with a generous top
radius, a thick grass band draping over the top of the dirt, and enough of a
groove between neighbours that a floor reads as individual blocks rather than
one flat sheet.

That last point drives the geometry, and it is not the obvious build. Rounding
ALL edges of the tile pulls the four side faces inward, so two neighbours no
longer touch and a field of grass shows the sky through the cracks. Instead the
sides stay flat and full width and only the top rim is rounded: tiles butt
together, a cliff face is a clean vertical plane, and the groove where two tops
meet is the block separation the reference wants.

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
CAP = 0.30        # depth of the grass band down the side faces. Thick, per the
                  # reference -- a thin fringe reads as a painted line. Most of
                  # the top of this band is eaten by ROUND, so the band has to
                  # be deeper than the green you want to SEE on the side.
SIDE = 0.35       # cap vertical-edge rounding, as a fraction of ROUND. The
                  # Bevel modifier multiplies its width by the edge weight, so
                  # one modifier does both radii.
ROUND = 0.11      # top radius. Chunky is the point -- at 0.05 the tile read as
                  # a box with its corners knocked off. But 0.15 was too far
                  # the other way: with three segments and weighted normals the
                  # top domes and a floor of them reads as sofa cushions. 0.11
                  # keeps a flat top with a crisp round-over, which is what the
                  # reference actually has.


def build(tag="GRASS", **kw):
    cap_z = HEIGHT - CAP * 0.5
    body_h = HEIGHT - CAP

    # Built as two stacked boxes that MEET rather than overlap. Two coplanar
    # faces inside a solid would z-fight once the tile is instanced a few
    # hundred times, and the merge welds the seam anyway.
    body = box(tag + "_Body", (0, 0, body_h * 0.5), (SIZE, SIZE, body_h),
               M["dirt"])
    cap = box(tag + "_Cap", (0, 0, cap_z), (SIZE, SIZE, CAP), M["grass"])

    # Only the cap is top-rounded -- it owns the top face. The body is buried
    # between its neighbours and the cap above it, so rounding it would cost
    # triangles for geometry nobody can see, and would open the very gap this
    # asset exists to avoid.
    # side=0.35 rounds the CAP vertical edges to a third of the top radius, so
    # a floor reads as separated blocks the way the reference does. The body is
    # deliberately left square: round it too and every point where four tiles
    # meet becomes a hole you can see the sky through.
    soften_top(cap, width=ROUND, segments=3, side=SIDE)
    soften_all([body], width=0.0)   # smooth-shade only; tags it `softened`

    return [body, cap]
