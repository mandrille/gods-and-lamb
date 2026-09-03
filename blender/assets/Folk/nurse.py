"""FOLK.folk.nurse - the wimple and the dress read her before anything else.

`folkbody.body()` has no idea what a dress is -- it always builds the same
short tunic and two bare legs. The trick the reference asks for (a floor-ish
dress with no visible leg) is the same one `adventurer.py` used for its hem
band, just pushed further down: a `_Hem` box big enough to swallow the whole
upper leg, in the SAME `plaster` as the tunic so the two read as one garment
rather than a hemline trim.

`hair="none"` on purpose -- the veil covers the whole crown and both sides, so
any hair style built underneath it would be spending triangles nobody sees.
The veil is named `_Veil...` (Head-bone claimed) even though the side panels
hang down to shoulder height, because it has to move with the head, not the
torso -- a wimple that stayed level while the head turned would shear open at
the neck.
"""
import os

from kit import M, box, cyl
from folkbody import (CHEST, HAND_R, HEAD_D, HEAD_H, HEAD_W, HEAD_Z, HIP_R,
                      body, finish)

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="folk",
    family="folk",
    variant="nurse",
    category=CATEGORY,
    footprint=(0.40, 0.35),   # MEASURED: 0.384 x 0.330 -- the veil sides land inside
    # the same X the villager's own cap-hair sideburns already claim
    anchor="floor",
    slots=(),
)

PALETTE = dict(tunic="plaster", hair="hair_warm", skin="skin",
               boots="leather", legs="wood_dark")


def build(tag="NURSE", **kw):
    hero, plain = body(tag, PALETTE, hair="none", apron=False, kerchief=False,
                       hands="level")

    # The wimple: a cap over the crown -- same box the villager's cap hair
    # style uses, just in `wool` instead of `hair` -- plus two side slabs that
    # keep falling past the head's underside down to shoulder height, which
    # is what makes it a wimple and not a hat.
    plain.append(box(tag + "_VeilCap", (0, 0.012, HEAD_Z + HEAD_H - 0.01),
                     (HEAD_W + 0.03, HEAD_D + 0.03, 0.17), M["wool"]))
    for sx in (-1, 1):
        plain.append(box("%s_VeilSide%s" % (tag, "L" if sx < 0 else "R"),
                         (sx * (HEAD_W * 0.5 - 0.008), 0.045, 0.57),
                         (0.05, HEAD_D * 0.65, 0.30), M["wool"]))

    # The hem: swallows the upper leg the way the cassock does for the
    # priest, same colour as the tunic so it reads as one dress, not a trim.
    plain.append(box(tag + "_Hem", (0, 0, 0.135), (0.26, 0.20, 0.17),
                     M["plaster"]))

    # The emblem: a small green sprig on the chest, the one saturated hue on
    # an otherwise cream-and-brown asset.
    plain.append(box(tag + "_EmblemA", (CHEST[0] - 0.012, CHEST[1] - 0.01,
                     CHEST[2]), (0.03, 0.02, 0.045), M["leaf"]))
    plain.append(box(tag + "_EmblemB", (CHEST[0] + 0.012, CHEST[1] - 0.01,
                     CHEST[2] + 0.01), (0.03, 0.02, 0.045), M["leaf"]))

    # The satchel on the hip. No strap of its own -- body() already draws one
    # diagonal `_Strap` and the API gives no way to add a second without
    # colliding the name (the same reasoning adventurer.py flags for its pack).
    plain.append(box(tag + "_Satchel", HIP_R, (0.10, 0.09, 0.12), M["leather"]))

    # The bottle in HandR: a small stone cylinder, not a box -- the one round
    # silhouette on an asset otherwise built entirely from boxes.
    plain.append(cyl(tag + "_Bottle", HAND_R, 0.028, 0.09, M["stone"]))

    return finish(hero, plain)
