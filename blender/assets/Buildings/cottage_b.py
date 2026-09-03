"""BUILDING.house.cottage_b - the settled dwelling, slate-and-plaster colourway.

Same shape as `cottage`, a different `kit.scheme()` -- see
`assets/_kit/bld_house.py` for the shape.
"""
import os

import bld_house

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="building",
    family="house",
    variant="cottage_b",
    category=CATEGORY,
    # MEASURED -- identical shape to `cottage`, see bld_house.SIZES["cottage"].
    footprint=(2.16, 1.90),
    anchor="floor",
    slots=(),
)


def build(tag="COTTAGE_B", **kw):
    return bld_house.build(tag, "cottage_blue", size="cottage")
