"""TERRAIN.ground.water - a pond or a river block.

Geometry and the reasoning behind it: assets/_kit/tilekit.py and
Terrain/grass.py. Every ground tile is that one shape with two materials.
"""
import os

from kit import M
from tilekit import sunken_tile

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="terrain",
    family="ground",
    variant="water",
    category=CATEGORY,
    footprint=(0.5, 0.5),
    anchor="floor",
    slots=(),
)


def build(tag="WATER", **kw):
    # Sunk 0.06 below the grid top so the bank reads as a bank. Flush water
    # against flush land is two coplanar surfaces and reads as painted-on.
    #
    # Opaque, not transparent: an alpha surface over a modelled bed costs a
    # second draw and an alpha sort on a mobile GPU, for a pond seen from
    # forty degrees. Colour does the job.
    return sunken_tile(tag, M["water_deep"], M["water"], drop=0.06)
