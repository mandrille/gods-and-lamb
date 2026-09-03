"""BUILDING.farm.farm_b - the same barn and crop plot, painted green.

Shares `assets/_kit/bld_farm.py` with `farm`. See that module for the shape
reasoning; this file exists to give the village a second farm that does not
read as a repeated copy of the first from across the map.

Fronts -Y.
"""
import os

from bld_farm import build as _build

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="building",
    family="farm",
    variant="farm_b",
    category=CATEGORY,
    footprint=(2.42, 2.37),
    anchor="floor",
    slots=(),
)


def build(tag="FARM_B", **kw):
    return _build(tag, kw.get("scheme", "farm_green"))
