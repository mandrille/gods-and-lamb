"""FOLK.folk.priest - reads a book, wears the village's only grey.

Every other folk job is a hue on top of the shared skin/hair/boot palette; the
priest is the one place a NEUTRAL earns its keep, because the reference's
whole silhouette is a column of stone-grey cassock over the tunic. Rule 5 in
AGENTS.md says two neutrals of different VALUE read as one object under the
key light -- so the cassock is grey, but the tunic underneath (visible only at
the cuffs, since the cassock hides the rest) is `cloth_red`: the one saturated
hue this asset gets, and it is what tells a priest from a grey rock at 40 px.

The cassock is bigger than the tunic in every dimension on purpose -- a robe
drapes OVER the garment beneath it, and it reaches low enough to cover the
upper leg the way batch-ids.md asks, the same trick the nurse's `_Hem` and the
adventurer's pack use to hide a seam rather than trying to align one exactly.

BUILT AT ATTENTION like every rigged folk: no lean, no yaw. The stole hangs
symmetric because it is a garment, not a hand-placed accessory -- the book
tilted in HandL is where this asset keeps its asymmetry.
"""
import os

from kit import M, box
from folkbody import CHEST, HAND_L, body, finish

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="folk",
    family="folk",
    variant="priest",
    category=CATEGORY,
    footprint=(0.39, 0.39),   # MEASURED: 0.384 x 0.330, same as villager's own AABB
    anchor="floor",
    slots=(),
)

PALETTE = dict(tunic="cloth_red", hair="hair_warm", skin="skin",
               boots="leather", legs="wood_dark")


def build(tag="PRIEST", **kw):
    hero, plain = body(tag, PALETTE, hair="cap", apron=False, kerchief=False,
                       hands="level")

    # The cassock: wider and taller than the shared tunic box in every
    # dimension, so it reads as worn OVER it rather than replacing it, and low
    # enough to hide the upper leg the way batch-ids.md's table asks.
    plain.append(box(tag + "_Cassock", (0, 0, 0.26), (0.27, 0.20, 0.42),
                     M["stone"]))

    # The stole: two thin wool strips down the chest, just proud of the
    # cassock so they do not z-fight, plus two dark dots for the trim the
    # reference shows without spending a third strip on it.
    for sx in (-1, 1):
        # `cloth_blue`, not wool: stone cassock + wool stole + plaster pages
        # was three neutrals under one key light (review, hue-not-value).
        # The dots were 2 cm boxes, under the visibility floor -- gone.
        plain.append(box("%s_Stole%s" % (tag, "L" if sx < 0 else "R"),
                         (sx * 0.045, -0.108, 0.33), (0.036, 0.018, 0.26),
                         M["cloth_blue"]))

    # The book: a wood spine with two plaster pages, tilted up as if held open
    # for reading rather than just carried.
    # Held OPEN at the chest, front and centre, 16 cm wide -- at HAND_L it
    # was side-on and 10 cm, and the one prop that says "priest" never
    # showed from the front (review). Still on the ArmL bone by name.
    bx, by, bz = CHEST[0], CHEST[1] - 0.05, CHEST[2] + 0.02
    plain.append(box(tag + "_BookSpine", (bx, by, bz), (0.018, 0.06, 0.12),
                     M["wood_dark"], rot=(-35, 0, 0)))
    plain.append(box(tag + "_BookPages", (bx, by - 0.012, bz),
                     (0.16, 0.10, 0.012), M["plaster"], rot=(-35, 0, 0)))

    return finish(hero, plain)
