"""FOLK.folk.builder - the reference this whole batch got handed first.

`Clay_builder_carrying_hammer` is named directly in batch-ids.md as THE
builder reference: leather cap, hammer, rock. Nothing here is guessed --
`sand` for the tunic (the one warm neutral this batch has not used yet, and
distinct in hue from every other job's tunic so a builder never reads as a
priest at 40 px), a stitched leather cap instead of hair, and both hands full.

Hammer in HandR, rock in HandL -- the rig table sends a held tool to the hand
that holds it, and this is the one job where BOTH hands hold something, so
both anchors get used instead of one prop and one bare `_Hand` box.
"""
import os

from kit import M, box
from folkbody import BELT, HAND_L, HAND_R, HIP_L, HIP_R, body, finish

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="folk",
    family="folk",
    variant="builder",
    category=CATEGORY,
    footprint=(0.58, 0.34),   # MEASURED: 0.414 x 0.335 -- the hammer head sets X
    anchor="floor",
    slots=(),
)

# `cloth_teal`, not sand: sand tunic + leather cap + leather belt + leather
# pouches was four warm browns (review); the reference is olive over leather.
PALETTE = dict(tunic="cloth_teal", hair="hair_warm", skin="skin",
               boots="leather", legs="wood_dark")


def build(tag="BUILDER", **kw):
    hero, plain = body(tag, PALETTE, hair="none", apron=False, kerchief=False,
                       hands="level")

    # The cap: a slightly wider box over the crown (leather, not hair), with
    # a thin seam line so it does not read as a bald skull with a lid on it.
    plain.append(box(tag + "_Cap", (0, 0.012, 0.77), (0.37, 0.33, 0.15),
                     M["leather"]))
    plain.append(box(tag + "_CapSeam", (0, 0.012, 0.735), (0.375, 0.335, 0.02),
                     M["wood_dark"]))

    # The belt, with two pouches -- a working tool belt, not the priest's
    # cassock sash.
    plain.append(box(tag + "_Belt", BELT, (0.26, 0.05, 0.04), M["leather"]))
    for side, anchor in (("L", HIP_L), ("R", HIP_R)):
        plain.append(box(tag + "_Pouch" + side, anchor, (0.07, 0.07, 0.08),
                         M["leather"]))

    # The hammer in HandR: a wood haft leaning back over the shoulder as if
    # just swung down, a stone head crossing the top.
    # Head-sized, like the reference, and out past the head box in X so it
    # is not a detached grey tab beside the ear (review). Haft starts IN the
    # hand and leans out, not back -- a back lean hid it behind the skull.
    haft_z = HAND_R[2] + 0.14
    plain.append(box(tag + "_Hammer", (HAND_R[0] + 0.04, HAND_R[1] - 0.02, haft_z),
                     (0.034, 0.034, 0.30), M["wood"], rot=(0, -16, 0)))
    plain.append(box(tag + "_HammerHead",
                     (HAND_R[0] + 0.085, HAND_R[1] - 0.02, haft_z + 0.15),
                     (0.16, 0.08, 0.08), M["stone"], rot=(0, -16, 0)))

    # The rock in HandL, dark stone so it does not disappear against the
    # tunic sleeve it sits beside.
    plain.append(box(tag + "_Rock", (HAND_L[0] - 0.03, HAND_L[1] - 0.05,
                     HAND_L[2] + 0.05), (0.12, 0.11, 0.10), M["stone_dark"]))

    return finish(hero, plain)
