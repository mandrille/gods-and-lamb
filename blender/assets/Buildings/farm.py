"""BUILDING.farm.farm - a red barn beside a fenced plot of ripe crop.

Shares `assets/_kit/bld_farm.py` with `farm_b`: a new VARIANT of the same
family costs nothing, and this and `farm_b` are the same barn in a different
paint. See the kit module for the shape reasoning.

Fronts -Y: the barn door and the crop plot's open side both face the viewer.
"""
import os

from bld_farm import build as _build

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="building",
    family="farm",
    variant="farm",
    category=CATEGORY,
    # MEASURED. See bld_farm.py: barn and plot sit side by side with a
    # footpath gap, so neither the barn's roof arithmetic nor the plot's
    # fence line predicts the combined span.
    footprint=(2.42, 2.37),
    anchor="floor",
    slots=(),
)


def build(tag="FARM", **kw):
    return _build(tag, kw.get("scheme", "farm_red"))
