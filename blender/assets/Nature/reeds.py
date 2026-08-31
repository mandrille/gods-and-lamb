"""NATURE.grass.reeds - the water-edge stand.

Tall and thin, and nothing else: eleven arcing blades up to a metre, plus three
cattails. The blades exist for the silhouette against open water, which is the
one place in the village where a plant is seen against a flat background rather
than against more plants.

The cattails are the reason this is not just tall grass. Three brown heads are
40 triangles and they are the only warm hue in a stand of green -- against
`water` they are also the only thing that is not a cool colour anywhere in the
frame. Green blades against blue water separate on hue; green blades against a
green bank do not, and the cattails carry the asset in that case.

Blades ARC: two boxes each, the upper leaning about twice as far. A single
straight box is a straw. The second segment costs 12 triangles and is the whole
difference between a reed bed and a bundle of sticks.

Deliberately unbevelled -- `soften_all(width=0.0)` smooth-shades and tags
without adding a radius. A 3 cm blade has no visible edge and bevelling
twenty-two boxes is how an asset loses its cap for nothing.
"""
import os

from kit import M, box, cyl, soften_all
from plantkit import blade, sink, up

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="nature",
    family="grass",
    variant="reeds",
    category=CATEGORY,
    # MEASURED (0.757 x 0.701). The blades lean out from the base, so the
    # stand is nearly three times as wide at head height as the 0.28 m of
    # ground it grows from.
    footprint=(0.76, 0.70),
    anchor="floor",
    slots=(),
)

# (x, y, height, lean_x, lean_y, material). Leans point AWAY from the middle so
# the stand opens like a fountain -- a clump that all leans one way reads as
# wind, which is a thing this game never animates.
BLADES = [
    (-0.11, -0.09, 0.86, 8.0, -9.0, "leaf_dark"),
    (-0.02, -0.13, 0.72, 11.0, -3.0, "leaf"),
    (0.09, -0.10, 0.95, 7.0, 8.0, "leaf_dark"),
    (0.13, 0.00, 0.64, 1.0, 12.0, "crop"),
    (0.10, 0.10, 0.89, -8.0, 9.0, "leaf"),
    (0.01, 0.14, 0.75, -12.0, 2.0, "leaf_dark"),
    (-0.10, 0.11, 0.68, -8.0, -9.0, "crop"),
    (-0.14, 0.01, 0.92, -2.0, -12.0, "leaf"),
    (-0.04, -0.03, 1.00, 3.0, -4.0, "leaf_dark"),
    (0.05, 0.03, 0.81, -4.0, 4.0, "leaf"),
    (0.00, -0.06, 0.58, 6.0, 6.0, "crop"),
]

# (x, y, height, lean_x, lean_y). Shorter than the tallest blades on purpose:
# a cattail that tops the stand reads as the subject, and it is meant to be a
# detail inside it.
CATTAILS = [
    (-0.07, -0.05, 0.66, 6.0, -7.0),
    (0.08, 0.04, 0.78, -5.0, 8.0),
    (0.02, -0.11, 0.58, 4.0, 5.0),
]

HEAD_H = 0.17
HEAD_R = 0.035


def build(tag="REEDS", **kw):
    P = []
    for i, (x, y, h, lx, ly, mat) in enumerate(BLADES):
        P.extend(blade("%s_Blade%d" % (tag, i), (x, y, 0.0), M[mat],
                       height=h, width=0.032, lean=(lx, ly), curl=2.0,
                       flat=0.45))

    for i, (x, y, h, lx, ly) in enumerate(CATTAILS):
        u = up(lx, ly)
        # Lifted by the corner drop of its own lean, the same correction
        # plantkit.blade applies. Without it the stand measured a Z minimum of
        # -2.5 mm and the cattails alone were the cause.
        z0 = sink(0.022, 0.022, lx, ly)
        P.append(box("%s_Stem%d" % (tag, i),
                     (x + u[0] * h * 0.5, y + u[1] * h * 0.5,
                      z0 + u[2] * h * 0.5),
                     (0.022, 0.022, h), M["crop"], rot=(lx, ly, 0)))
        # The head overlaps the top of its own stem rather than balancing on
        # it, so a gap cannot open when the asset is scaled at placement.
        cz = h - HEAD_H * 0.4
        P.append(cyl("%s_Head%d" % (tag, i),
                     (x + u[0] * cz, y + u[1] * cz, z0 + u[2] * cz),
                     HEAD_R, HEAD_H, M["trunk"], verts=6,
                     rot=(lx, ly, 0)))

    soften_all(P, width=0.0)
    return P
