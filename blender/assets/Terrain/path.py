"""TERRAIN.ground.path - a trodden route through the village.

Geometry and the reasoning behind it: assets/_kit/tilekit.py and
Terrain/grass.py. Every ground tile is that one shape with two materials.
"""
import os

from kit import M
from tilekit import ground_tile

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="terrain",
    family="ground",
    variant="path",
    category=CATEGORY,
    footprint=(0.5, 0.5),
    anchor="floor",
    slots=(),
)


def build(tag="PATH", **kw):
    # Pale stone on earth. The path has to separate from grass by HUE, not
    # brightness -- there is no ambient occlusion here to draw the border.
    return ground_tile(tag, M["dirt"], M["stone"])
