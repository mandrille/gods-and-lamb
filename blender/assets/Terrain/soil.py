"""TERRAIN.ground.soil - tilled earth, for crops.

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
    variant="soil",
    category=CATEGORY,
    footprint=(1.0, 1.0),
    anchor="floor",
    slots=(),
)


def build(tag="SOIL", **kw):
    return ground_tile(tag, M["dirt_dark"], M["soil"])
