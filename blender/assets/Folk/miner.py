"""FOLK.folk.miner - works the mine.

No reference exists for this one (batch-ids.md section on characters says so
explicitly) -- same body, a dark helm, a pick over the shoulder, an ore sack
on the hip. Those three details carry the whole identity, in that order: the
dark `_Helm` reads first as a silhouette change against every other job's
hair, the pick is the vertical accent, the sack is the low accent that keeps
the eye from reading him as just a dark-headed villager.

`hair="none"` -- the helm replaces hair entirely rather than sitting on top of
it, which is also why it is built as its own hero mass at the same size and
position folkbody's own cap uses, not as an addition to a hair style.

Leather tunic (a mine coverall, not a garment folkbody's default palette
reaches for) with an iron-dark belt: iron against leather is a hue break, not
just a value one, which is the rule the whole batch runs on.

Fronts -Y, symmetric rest pose -- the pick's shoulder lean is a prop detail,
never a baked arm angle.
"""
import os

from kit import M, box
from folkbody import BELT, HAND_R, HEAD_D, HEAD_H, HEAD_W, HEAD_Z, HIP_L, body, finish

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="folk",
    family="folk",
    variant="miner",
    category=CATEGORY,
    # MEASURED: the pick's iron head, pushed clear of the head box so it
    # does not vanish behind it (see the build() comment), is what sets X --
    # by a wide margin over the swinging-arm column every other job uses.
    footprint=(0.55, 0.38),
    anchor="floor",
    slots=(),
)

PALETTE = dict(tunic="leather", hair="hair_warm", skin="skin",
               boots="leather", legs="wood_dark")


def build(tag="MINER", **kw):
    hero, plain = body(tag, PALETTE, hair="none", apron=False,
                       kerchief=False, hands="level")

    # Helm: same footprint folkbody's own cap hair uses, dark wood so it
    # reads as a hard shell rather than cloth.
    extra_hero = [box(tag + "_Helm", (0, 0.012, HEAD_Z + HEAD_H - 0.01),
                      (HEAD_W + 0.04, HEAD_D + 0.04, 0.18), M["wood_dark"])]

    extra_plain = [
        box(tag + "_Belt", BELT, (0.26, 0.20, 0.032), M["iron_dark"]),
        # Pick: wood haft tilted OUT in X (rot about Y, the strap/axe trick --
        # affects X and Z, not Y), iron head at the top pushed well past the
        # head's own 0.17 half-width. A first attempt tilted the haft back
        # about X instead: the top swung behind the head box in depth and
        # the whole pick vanished, the same screen-space-occlusion trap the
        # lumberjack's axe hit -- an X/Z overlap with a closer, opaque part
        # hides a prop regardless of which bone claims it.
        box(tag + "_Pick", (HAND_R[0], HAND_R[1] - 0.02, 0.44),
           (0.03, 0.03, 0.40), M["wood"], rot=(0, 20, 0)),
        box(tag + "_PickHead", (0.27, HAND_R[1] - 0.02, 0.63),
           (0.17, 0.045, 0.05), M["iron_dark"]),
        # Ore sack on the hip, sand-coloured.
        box(tag + "_Sack", HIP_L, (0.14, 0.12, 0.15), M["sand"]),
    ]

    return finish(hero, plain, extra_hero=extra_hero, extra_plain=extra_plain)
