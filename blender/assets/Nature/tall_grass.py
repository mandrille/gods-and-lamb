"""NATURE.grass.tall_grass - a tuft, for scattering by the dozen.

The cheapest thing in Nature and the one there will be most of. `bush` is two
chamfered masses and spends its whole budget on the rounding; this is nine
unbevelled blades and comes in at a quarter of the cost, which is what makes it
affordable to put one on every third grass tile.

It has to be a TUFT and not a small bush, or there is no reason for it to exist
beside `bush`. The blades fan outward and arc, so the silhouette is spiky where
the bush's is round -- at island distance that difference in silhouette is the
entire asset, because the greens are the same greens.

Darker and bluer than the ground it stands on. `grass` is a bright yellow-green
and `leaf_dark`/`leaf` are the cool end of the palette; a tuft in the ground's
own green would be invisible, and there is no ambient occlusion under GL
Compatibility to draw a border for it.

Deliberately unbevelled -- `soften_all(width=0.0)` smooth-shades and tags
without a radius. A 2.5 cm blade has no edge anyone can see, and the whole
point of this asset is that it is cheap.
"""
import os

from kit import M, soften_all
from plantkit import blade

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="nature",
    family="grass",
    variant="tall_grass",
    category=CATEGORY,
    # MEASURED (0.472 x 0.448). A 0.16 m base, but the blades arc out to three
    # times that.
    footprint=(0.47, 0.45),
    anchor="floor",
    slots=(),
)

# (x, y, height, lean_x, lean_y, material). Leans point away from the middle so
# the tuft opens; heights vary by more than half so the silhouette is ragged
# rather than a shrub-shaped dome.
BLADES = [
    (-0.06, -0.05, 0.34, 17.0, -19.0, "leaf_dark"),
    (0.01, -0.08, 0.24, 22.0, -4.0, "leaf"),
    (0.07, -0.04, 0.40, 14.0, 16.0, "leaf_dark"),
    (0.08, 0.03, 0.28, -5.0, 23.0, "leaf"),
    (0.03, 0.08, 0.36, -18.0, 13.0, "leaf_dark"),
    (-0.05, 0.07, 0.22, -21.0, -7.0, "leaf"),
    (-0.08, 0.00, 0.31, -8.0, -20.0, "leaf_dark"),
    (-0.01, -0.01, 0.43, 7.0, -5.0, "leaf"),
    (0.03, 0.01, 0.26, -9.0, 9.0, "leaf_dark"),
]


def build(tag="TALLGRASS", **kw):
    P = []
    for i, (x, y, h, lx, ly, mat) in enumerate(BLADES):
        P.extend(blade("%s_Blade%d" % (tag, i), (x, y, 0.0), M[mat],
                       height=h, width=0.030, lean=(lx, ly), curl=2.0,
                       flat=0.40))
    soften_all(P, width=0.0)
    return P
