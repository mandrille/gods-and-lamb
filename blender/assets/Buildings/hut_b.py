"""BUILDING.house.hut_b - the starter dwelling, whitewashed-plaster colourway.

Same shape as `hut` -- a new VARIANT of `house` costs nothing -- with a
different `kit.scheme()` so two huts standing near each other in the village
read as different buildings rather than the same one twice. See
`assets/_kit/bld_house.py` for the shape.
"""
import os

import bld_house

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="building",
    family="house",
    variant="hut_b",
    category=CATEGORY,
    # MEASURED -- identical shape to `hut`, see bld_house.SIZES["hut"].
    footprint=(1.70, 1.51),
    anchor="floor",
    slots=(),
)


def build(tag="HUT_B", **kw):
    return bld_house.build(tag, "house_plaster", size="hut")
