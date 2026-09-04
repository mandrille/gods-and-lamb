"""ANIMALS.livestock.lamb - the sheep's young. A single smooth shape, not a
smaller sheep.

Reference: the small figure in `refs/characters/Clay_lamb_and_sheep...jpeg`,
next to the full sheep. The reference itself makes the design call: the lamb
has no fleece texture at all, just one smooth rounded body with a small head,
tiny ears and dark button eyes -- which is why this builder has none of
`sheep.py`'s three-mass fleece cluster. ONE bevelled `_Body` box carries the
whole silhouette; everything else is a small plain detail on top of it.

`cls="folk"`, `rig="critterrig"`, same pipeline as sheep and cow, at roughly
55% of the sheep's footprint -- small enough that a player tells lamb from
sheep on size and shape alone, the same way they tell cow from sheep. Short,
stubby legs (LEG_TOP well under half the standing height, against the sheep's
even 50%) are what read as YOUNG rather than merely SMALL -- a lamb scaled
down with adult proportions would read as a distant sheep, not a different
animal.

`wool` for the body, head and ears -- the reference is white all over except
the face and legs. `hair_dark` legs and `wood_dark` hooves, the same hue-only
split sheep and wolf both use so a dark leg does not fuse into a dark hoof
under one directional light with no AO pass to separate them.

Built at attention on z=0, fronting -Y.
"""
import os

from kit import M, box, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="folk",
    family="livestock",
    variant="lamb",
    category=CATEGORY,
    # MEASURED. X from the hooves, Y nose to tail -- same convention as
    # sheep.py and cow.py.
    footprint=(0.271, 0.546),
    anchor="floor",
    slots=(),
    rig="critterrig",
)

LEG_TOP = 0.11              # short and stubby -- ~30% of standing height,
                             # against the sheep's even 50%. That difference
                             # is what makes this read as YOUNG, not just small.
LEG_W = 0.045
LEG_X = 0.108                 # half the stance, clear of the body's 0.095 half
                             # width so the legs break the outline from above.
HOOF_H = 0.03
BARREL_Z = 0.195             # centre of the one body mass


def build(tag="LAMB", **kw):
    # A single hero mass -- the fleece-cluster idiom sheep.py uses is exactly
    # what the reference does NOT have. One smooth bevelled box IS the whole
    # design; everything else is plain detail sitting on it.
    hero, plain = [], []

    hero.append(box(tag + "_Body", (0, 0.0, BARREL_Z),
                    (0.19, 0.36, 0.19), M["wool"]))

    # --- head: one small wool mass, no separate muzzle -- the reference's
    # face is a single rounded lump with ears and eyes on it, not a jaw.
    # `stone`, not wool: head, body, ears and tail all in wool gave the
    # head zero separation from the fleece and the asset no hue (review);
    # the reference lamb has a visibly darker face.
    plain.append(box(tag + "_Head", (0, -0.24, 0.22),
                     (0.13, 0.14, 0.135), M["stone"]))
    # Small and drooping, not upright -- a lamb's ears hang, a wolf's prick up.
    for sx in (-1, 1):
        side = "L" if sx < 0 else "R"
        plain.append(box("%s_Ear%s" % (tag, side),
                         (sx * 0.085, -0.23, 0.275),
                         (0.08, 0.06, 0.035), M["petal_pink"],
                         rot=(20, -18 * sx, 0)))
    # Dark dots pushed just past the head's own front edge -- flush with it
    # disappears behind the head's front wall in the ortho front render, the
    # same lesson wolf.py paid for on its brow and eyes.
    for sx in (-1, 1):
        side = "L" if sx < 0 else "R"
        plain.append(box("%s_Eye%s" % (tag, side),
                         (sx * 0.045, -0.315, 0.235),
                         (0.018, 0.012, 0.018), M["hair_dark"]))

    # --- legs and hooves, split the way wolf.py splits leg and paw: a shaft
    # and a wider, flatter cap at the ground, in a different hue so the two
    # separate from each other and from the wool body under one light.
    shaft_h = LEG_TOP - HOOF_H
    shaft_z = HOOF_H + shaft_h * 0.5
    hoof_z = HOOF_H * 0.5
    for sy, fb in ((-1, "F"), (1, "B")):
        y = -0.09 if sy < 0 else 0.11
        for sx in (-1, 1):
            side = "L" if sx < 0 else "R"
            plain.append(box("%s_Leg%s%s" % (tag, fb, side),
                             (sx * LEG_X, y, shaft_z),
                             (LEG_W, LEG_W, shaft_h), M["hair_dark"]))
            plain.append(box("%s_Hoof%s%s" % (tag, fb, side),
                             (sx * LEG_X, y, hoof_z),
                             (LEG_W + 0.01, LEG_W + 0.015, HOOF_H),
                             M["wood_dark"]))

    plain.append(box(tag + "_Tail", (0, 0.205, 0.24),
                     (0.045, 0.04, 0.045), M["wool"]))

    # 0.06 -- proportionally close to the sheep's 0.09 (a quarter of the
    # smallest dimension there too), so the one body mass keeps the same
    # "no straight edge" softness the sheep's fleece has.
    soften_all(hero, width=0.06, segments=2)
    soften_all(plain, width=0.0)
    return hero + plain
