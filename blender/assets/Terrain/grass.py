"""TERRAIN.ground.grass - the default village floor.

The first asset in the project, and the one that settled the shape every other
ground tile uses. The reasoning lives here; the geometry lives in
assets/_kit/tilekit.py.

Shape follows the Kubikos-style reference: a chunky block with a generous top
radius, a thick grass band draping over the dirt, and enough of a groove
between neighbours that a floor reads as individual blocks rather than one flat
sheet.

That last point is not the obvious build. Rounding ALL edges of the tile pulls
the four side faces inward, so two neighbours no longer touch and a field shows
the sky through the cracks. Instead the sides stay flat and full width and only
the CAP is rounded -- top rim at full radius, cap verticals at a third of it.
Tiles butt together, a cliff face is a clean vertical plane, and the groove
where two caps meet is the block separation the reference wants.

Two materials, not one: a grass cap over a dirt body. A single colour would put
grass down the cliff faces, and every exposed edge in the village is a cliff
face.
"""
import os

from kit import M
from tilekit import ground_tile

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


def build(tag="GRASS", **kw):
    return ground_tile(tag, M["dirt"], M["grass"])
