"""TERRAIN.ground.dirt - bare earth, the floor under a path or a ploughed field.

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
    variant="dirt",
    category=CATEGORY,
    footprint=(0.5, 0.5),
    anchor="floor",
    slots=(),
)


def build(tag="DIRT", **kw):
    # A darker crust over the same body. Without the two-tone the block is a
    # single flat brown and the rounded cap has nothing to catch.
    return ground_tile(tag, M["dirt"], M["dirt_dark"])
