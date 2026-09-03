"""BUILDING.house.hut - the starter dwelling, terracotta-block clay style.

REDONE to `refs/buildings/Clay_cottage_house_architectural`: an arched door
instead of the old rectangular cut, small punched windows, a stub chimney,
and a flower pot + barrel at the doorstep. Shape lives in
`assets/_kit/bld_house.py`, shared with `hut_b`, `cottage` and `cottage_b` --
this file is the ASSET dict and the one colourway call.
"""
import os

import bld_house

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="building",
    family="house",
    variant="hut",
    category=CATEGORY,
    # MEASURED, not derived -- see bld_house.SIZES["hut"] and the module
    # docstring on why a rotated roof slab always reaches past the arithmetic.
    footprint=(1.70, 1.51),
    anchor="floor",
    slots=(),
)


def build(tag="HUT", **kw):
    return bld_house.build(tag, "house_terracotta", size="hut")
