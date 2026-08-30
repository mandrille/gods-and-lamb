"""NATURE.bush.bush - low scrub, scattered in threes and fours.

Two masses, not one, and in two different greens. Seen in a clump the variety
has to come from rotation and tint at instance time, so the single piece just
has to have an asymmetric silhouette to rotate.
"""
import os

from kit import M, blob, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="nature",
    family="bush",
    variant="bush",
    category=CATEGORY,
    footprint=(0.63, 0.59),
    anchor="floor",
    slots=(),
)


def build(tag="BUSH", **kw):
    P = [
        blob(tag + "_Low", (0.0, 0.0, 0.15), (0.54, 0.48, 0.30),
             M["leaf_dark"], tilt=(0, 0, 12)),
        blob(tag + "_Top", (0.06, -0.04, 0.31), (0.38, 0.34, 0.24),
             M["leaf"], tilt=(0, 0, -20)),
    ]
    soften_all(P, width=0.06, segments=2)
    return P
