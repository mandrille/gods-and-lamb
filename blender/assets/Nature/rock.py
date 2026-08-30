"""NATURE.rock.rock - a boulder, for breaking up a run of empty grass.

Three masses at odd angles. Stone is the one thing in the village allowed to be
irregular, so the tilts are deliberately not multiples of each other -- a rock
built on a 45-degree grid reads as a machined part.
"""
import os

from kit import M, blob, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="nature",
    family="rock",
    variant="rock",
    category=CATEGORY,
    footprint=(0.75, 0.70),
    anchor="floor",
    slots=(),
)


def build(tag="ROCK", **kw):
    P = [
        blob(tag + "_Base", (0.0, 0.0, 0.14), (0.60, 0.52, 0.28),
             M["stone"], tilt=(3, -5, 17)),
        blob(tag + "_Upper", (-0.08, 0.05, 0.31), (0.38, 0.34, 0.24),
             M["stone_dark"], tilt=(-6, 4, -31)),
        blob(tag + "_Chip", (0.19, -0.11, 0.10), (0.22, 0.20, 0.18),
             M["stone"], tilt=(8, 6, 52)),
    ]
    soften_all(P, width=0.055, segments=2)
    return P
