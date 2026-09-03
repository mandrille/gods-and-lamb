"""BUILDING.house.cottage - the settled dwelling, a step up from the hut.

REDONE onto the shared `assets/_kit/bld_house.py` builder at size="cottage":
a third taller than the hut, an extra window under the gable peak, and the
same arched-door / chimney / doorstep-props treatment. Same family as `hut`
and deliberately so -- a new VARIANT costs nothing and this IS a house, just
the larger of the two the reference shows as stacked blocks.
"""
import os

import bld_house

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="building",
    family="house",
    variant="cottage",
    category=CATEGORY,
    # MEASURED, not derived -- see bld_house.SIZES["cottage"].
    footprint=(2.16, 1.90),
    anchor="floor",
    slots=(),
)


def build(tag="COTTAGE", **kw):
    return bld_house.build(tag, "cottage_red", size="cottage")
