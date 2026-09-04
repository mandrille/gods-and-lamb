"""FOLK.folk.bard - the lute carries this one, not the clothes.

Orange tunic, blue patch: `folkbody.body()` already builds an `_Apron` box at
chest height for exactly this shape, so the "patch" in the batch spec is not
a new part -- it is the stock apron with `apron="cloth_blue"` in the palette.
Reusing the anchor the API already gives you is cheaper than inventing a new
box that sits in the same place.

`hair="curly"` is the only style with no hero box (see its docstring in
folkbody.py) -- it is smooth-shaded curls riding on the head's own bevel, so
adding the tucked leaf costs one more plain part, not a second hero pass.

The lute is the one prop on this batch built at Torso instead of a hand: it
is held two-handed in front of the chest, so there is no single arm bone it
belongs to, and batch-ids.md's rig table puts anything held that way on
Torso rather than splitting it across ArmL and ArmR (which would shear the
neck away from the body on the first swing of either arm).
"""
import os

from kit import M, box
from folkbody import CHEST, HIP_L, body, finish

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="folk",
    family="folk",
    variant="bard",
    category=CATEGORY,
    footprint=(0.49, 0.36),   # MEASURED: 0.390 x 0.325 -- the lute sits inside the arms
    anchor="floor",
    slots=(),
)

PALETTE = dict(tunic="cloth_orange", apron="cloth_blue", hair="hair_warm",
               skin="skin", boots="leather", legs="wood_dark")


def build(tag="BARD", **kw):
    hero, plain = body(tag, PALETTE, hair="curly", apron=True, kerchief=False,
                       hands="level")

    # The leaf tucked in the curls, off-centre the way a tucked object
    # actually sits rather than balanced on the crown.
    plain.append(box(tag + "_Leaf", (0.09, 0.05, 0.75), (0.09, 0.02, 0.045),
                     M["leaf"], rot=(0, 0, 25)))

    # A second, smaller patch away from the apron -- one saturated gold spot
    # so the tunic reads as mended, not just two-tone.
    plain.append(box(tag + "_TunicPatch", (0.09, -0.09, 0.27),
                     (0.045, 0.02, 0.045), M["petal_gold"]))

    # The lute: a rounded plaster body, a dark wood neck angled up and out,
    # three tiny pegs at the tip. Held in front at chest height, offset left
    # of centre the way a lute actually sits against the strumming arm.
    lx, ly, lz = CHEST[0] + 0.02, CHEST[1] - 0.03, CHEST[2] - 0.02
    # Narrower and 3 cm lower than the first pass, which covered the whole
    # tunic front and hid the orange/blue patchwork that IS the bard; the
    # neck is shorter and swung well out so it no longer crosses the face
    # (the pegs were landing on the cheek and read as a moustache).
    lz -= 0.03
    plain.append(box(tag + "_LuteBody", (lx, ly, lz), (0.10, 0.06, 0.15),
                     M["plaster"]))
    plain.append(box(tag + "_LuteNeck", (lx - 0.055, ly - 0.01, lz + 0.115),
                     (0.032, 0.032, 0.11), M["wood_dark"], rot=(0, 30, 8)))
    peg_x, peg_z = lx - 0.10, lz + 0.165
    for i, mat in enumerate(("petal_red", "petal_blue", "petal_gold")):
        plain.append(box("%s_LutePeg%d" % (tag, i),
                         (peg_x + i * 0.02, ly - 0.02, peg_z),
                         (0.02, 0.02, 0.02), M[mat]))

    # The satchel on the hip, same as the other travelling jobs.
    plain.append(box(tag + "_Satchel", HIP_L, (0.10, 0.09, 0.12), M["leather"]))

    return finish(hero, plain)
