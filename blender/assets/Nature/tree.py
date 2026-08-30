"""NATURE.tree.tree - the village broadleaf.

Canopy is three chamfered BOXES at slight angles, not a subdivided sphere. That
is not a budget compromise, it is the look: the reference canopies are clearly
boxy masses with soft corners and they read as trees instantly. A sphere costs
about five times as much and matches nothing else in the village.

Two greens, because one green is a silhouette. The lower mass is `leaf_dark`
and the upper catches `leaf_light`, so the canopy has a top and a bottom
without needing a light to tell you.

The trunk flares at the base. A straight post reads as a pole; the flare is
four small boxes and it is the difference between a tree and a lollipop.

Fronts -Y, like everything floor-standing.
"""
import os

from kit import M, box, blob, cyl, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="nature",
    family="tree",
    variant="tree",
    category=CATEGORY,
    # MEASURED. The canopy blobs are rotated, so their corners reach further
    # than their box sizes suggest.
    footprint=(1.14, 1.11),
    anchor="floor",
    slots=(),
)

TRUNK_H = 0.86
TRUNK_R = 0.115


def build(tag="TREE", **kw):
    P = []

    trunk = [cyl(tag + "_Trunk", (0, 0, TRUNK_H * 0.5), TRUNK_R, TRUNK_H,
                 M["trunk"], verts=8)]
    # Root flare. Four boxes pushed out at the base, low enough that the canopy
    # never hides them. Rotated 45 degrees off the axes so they do not line up
    # with the tile grid underneath.
    for i, (dx, dy) in enumerate(((1, 1), (1, -1), (-1, 1), (-1, -1))):
        trunk.append(box("%s_Root%d" % (tag, i),
                         (dx * 0.105, dy * 0.105, 0.055),
                         (0.15, 0.15, 0.11), M["trunk"], rot=(0, 0, 45)))

    # Three masses. The lowest is the widest and darkest, so the canopy reads as
    # sitting ON the trunk rather than skewered by it.
    canopy = []
    # Deeper than they are wide-looking, and OVERLAPPING. The first version
    # used flat 0.36-0.40 slabs spaced apart and the canopy read as three
    # stacked pancakes rather than one mass -- at island distance you could
    # count them.
    canopy.append(blob(tag + "_CanopyLow", (0.0, 0.0, TRUNK_H + 0.22),
                  (0.94, 0.90, 0.54), M["leaf_dark"], tilt=(0, 0, 14)))
    canopy.append(blob(tag + "_CanopyMid", (-0.07, 0.06, TRUNK_H + 0.46),
                  (0.82, 0.78, 0.48), M["leaf"], tilt=(0, 0, -9)))
    canopy.append(blob(tag + "_CanopyTop", (0.08, -0.05, TRUNK_H + 0.68),
                  (0.56, 0.54, 0.38), M["leaf_light"], tilt=(0, 0, 22)))

    # TWO passes, because the two halves of a tree earn different budgets.
    # The canopy IS the silhouette, so it gets 7 cm at two segments -- the same
    # chunky radius the ground tiles use, so foliage and terrain read as one
    # world. The trunk and roots are a few pixels at play distance and get one
    # segment, which is what brought this asset back under its cap: 872 tris
    # against a 800 cap, fixed in the geometry rather than by raising the cap.
    soften_all(canopy, width=0.07, segments=2)
    soften_all(trunk, width=0.05, segments=1)
    P.extend(trunk)
    P.extend(canopy)
    return P
