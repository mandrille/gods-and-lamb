"""ANIMALS.predator.wolf - the village's first ENEMY.

Reference: `refs/characters/Evil_clay_wolf_with_glowing...jpeg` -- dark, crouched,
red-eyed, teeth bared. NOT `Clay_wolf_standing`, which is a friendly dog and the
wrong animal entirely.

Sibling to `sheep.py` and `cow.py` in every way that pipeline cares about --
`cls="folk"`, `rig="critterrig"`, the same tri budget, the same 35-degree play
camera -- and their opposite in every way that reads as a THREAT rather than
livestock:

              sheep / cow                wolf
  posture     standing tall              CROUCHED -- back line ~0.41 m, the
                                          cow's is 0.78 m
  edges       soft (7 / 4.5 cm bevel)    sharper, 4.5 cm, and one fewer hero
                                          mass -- less plush reads as leaner
  head        carried mid-height,        forward of the shoulders and DOWN,
              level with the back        below the back line -- a stalking
                                          reach, not a grazing dip
  colour      near-white / brown-white   almost entirely `hair_dark`; the only
                                          saturated note is TWO POINTS of
                                          `ember`, and nothing else in the game
                                          uses that material
  silhouette  a level back, four fat     a raised `_Ruff` mass over the
              legs, done                 shoulders (the one hump on an
                                          otherwise low, long body) and a
                                          drooping, segmented tail

THE RUFF IS THE SHOULDER HUMP the reference photo shows -- a block of fur
proud of the neck where a real wolf's hackles sit. It is the only place this
asset breaks its own low profile, which is what makes it read as alert rather
than merely lying down.

THE FACE IS BUILT IN THREE FORWARD STAGES -- `_Head`, `_Muzzle`, `_Snout` --
each narrower and lower than the last, so the plan silhouette comes to a point
instead of a blunt rectangle. `_Brow` sits proud of the head's own top edge by
a centimetre, which is what puts a shadow over the eye sockets under one
directional light with no AO pass to do it for us. The `_Eye`s sit just under
that ridge, in `ember` -- an emissive red used nowhere else in the game, so a
red glint in the grass is legible as THIS animal from the first frame a player
sees one. `_Fang` is two `wool` wedges at the mouth corner: `wool` because it
is the only near-white in the kit and a fang has to read as bone-pale against
a body that is otherwise almost all one dark hue.

LEGS AND PAWS ARE SEPARATE MASSES, unlike the sheep/cow's single leg box.
`_LegXX` is the shaft, `_PawXX` a wider, flatter pad at the ground -- both
`wood_dark` against a `hair_dark` body, which is the sheep/cow's hue-not-value
lesson applied here too: a same-material leg on a same-material barrel is one
shape under the key light regardless of how the geometry actually splits.

Built at attention on z=0, fronting -Y, like everything floor-standing.
"""
import os

from kit import M, box, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="folk",
    family="predator",           # NEW family -- needs LAMB_VOCAB_OPEN=1
    variant="wolf",
    category=CATEGORY,
    # MEASURED with `-- measure`. X is the PAWS (they stand outside the ruff
    # on purpose, same reason the sheep's hooves stand outside its fleece); Y
    # is snout-tip to tail-tip.
    footprint=(0.41, 1.08),
    anchor="floor",
    slots=(),
    # NOT folkrig -- see sheep.py/cow.py for why a biped skeleton is wrong for
    # a four-legged body.
    rig="critterrig",
)

LEG_TOP = 0.20             # legs run 0 .. LEG_TOP; the body starts at ~0.19
LEG_W = 0.075               # shaft thickness
LEG_X = 0.155               # half the stance. Exceeds half the body width
                             # (0.12) by 3.5 cm so the paws break the outline.
PAW_H = 0.05                 # the flat pad at the ground; the shaft is the rest
BARREL_Z = 0.300             # centre of the main body mass -- low and long


def build(tag="WOLF", **kw):
    # Two hero masses only, against the sheep/cow's three -- a leaner, sharper
    # profile is part of what separates a predator from livestock at a glance,
    # and it buys back the triangles the extra face and leg detail spend.
    hero, plain = [], []

    # --- the body: low and long, with the RUFF as the one raised mass over
    # the shoulders. Everything else stays under the back line the ruff sets,
    # which is what keeps a crouching animal from reading as merely a smaller
    # standing one.
    hero.append(box(tag + "_Body", (0, 0.0, BARREL_Z),
                    (0.24, 0.42, 0.22), M["hair_dark"]))
    hero.append(box(tag + "_Ruff", (0, -0.16, BARREL_Z + 0.04),
                    (0.27, 0.18, 0.26), M["hair_dark"]))
    # The rump is plain, not hero -- a sharper corner here reads as haunch
    # muscle rather than fleece, and the budget the sheep spends on a third
    # bevelled mass goes to the face and the paws instead.
    plain.append(box(tag + "_Rump", (0, 0.22, BARREL_Z - 0.01),
                     (0.22, 0.19, 0.20), M["hair_dark"]))

    # --- head, in three forward stages so the plan view comes to a point.
    # Each stage sits lower than the one behind it -- a stalking reach, not
    # the sheep's head carried at mid-height.
    plain.append(box(tag + "_Neck", (0, -0.29, 0.32),
                     (0.15, 0.15, 0.19), M["hair_dark"]))
    plain.append(box(tag + "_Head", (0, -0.38, 0.335),
                     (0.19, 0.19, 0.185), M["hair_dark"]))
    plain.append(box(tag + "_Muzzle", (0, -0.475, 0.285),
                     (0.13, 0.15, 0.115), M["hair_dark"]))
    plain.append(box(tag + "_Snout", (0, -0.555, 0.265),
                     (0.075, 0.06, 0.075), M["hair_dark"]))
    # A slab proud of the head's own front edge -- the shadow that gives this
    # face a heavy, aggressive brow under one directional light. It has to
    # jut FORWARD of the head box, not merely sit on top of it, or nothing
    # about it is visible from the front camera: an ortho front render shows
    # only the nearest surface at each point, and a slab flush with the head
    # is simply hidden behind the head's own front wall.
    plain.append(box(tag + "_Brow", (0, -0.46, 0.415),
                     (0.19, 0.08, 0.045), M["hair_dark"]))
    # Upright, slight forward-and-outward splay -- an alert ear, not the
    # sheep's floppy side-set one.
    for sx in (-1, 1):
        side = "L" if sx < 0 else "R"
        plain.append(box("%s_Ear%s" % (tag, side),
                         (sx * 0.075, -0.34, 0.47),
                         (0.055, 0.05, 0.11), M["hair_dark"],
                         rot=(-5, -8 * sx, 0)))
    # Two points of EMBER and nothing else in the game uses that material --
    # a red glint under the brow shadow is this animal's whole identity read
    # from across the village. Set ABOVE the muzzle's top edge and forward of
    # the head's own front wall, for the same occlusion reason the brow is:
    # a dot merely inset into the head disappears behind it in a front ortho
    # render, so the eye has to clear the surrounding geometry to be seen.
    for sx in (-1, 1):
        side = "L" if sx < 0 else "R"
        plain.append(box("%s_Eye%s" % (tag, side),
                         (sx * 0.06, -0.485, 0.355),
                         (0.026, 0.018, 0.02), M["ember"]))
    # Two wool wedges at the mouth corner, set forward of the snout's own
    # front edge and low enough to hang below the jawline -- the only
    # bone-pale thing on an otherwise near-monochrome animal, tilted forward
    # like a bared canine.
    for sx in (-1, 1):
        side = "L" if sx < 0 else "R"
        plain.append(box("%s_Fang%s" % (tag, side),
                         (sx * 0.032, -0.58, 0.21),
                         (0.016, 0.016, 0.04), M["wool"],
                         rot=(12, 0, 0)))

    # --- legs and paws, split into two masses where the sheep/cow use one.
    # OUTSIDE the body in plan (LEG_X 0.155 against a half-width of 0.12), so
    # the paws break the outline from the play camera the same way the
    # sheep's hooves do -- see sheep.py rules 1 and 2. `wood_dark` on both so
    # the whole leg separates from the `hair_dark` barrel by hue.
    shaft_h = LEG_TOP - PAW_H
    shaft_z = PAW_H + shaft_h * 0.5
    paw_z = PAW_H * 0.5
    for sy, fb in ((-1, "F"), (1, "B")):
        y = -0.13 if sy < 0 else 0.19
        for sx in (-1, 1):
            side = "L" if sx < 0 else "R"
            plain.append(box("%s_Leg%s%s" % (tag, fb, side),
                             (sx * LEG_X, y, shaft_z),
                             (LEG_W, LEG_W, shaft_h), M["wood_dark"]))
            plain.append(box("%s_Paw%s%s" % (tag, fb, side),
                             (sx * LEG_X, y, paw_z),
                             (0.10, 0.11, PAW_H), M["wood_dark"]))

    # --- tail, three segments that DROOP rather than the sheep's raised
    # puffy one -- a low tail is part of what makes this read as stalking
    # rather than idle livestock, even before it moves.
    plain.append(box(tag + "_Tail1", (0, 0.34, 0.26),
                     (0.08, 0.08, 0.08), M["hair_dark"]))
    plain.append(box(tag + "_Tail2", (0, 0.405, 0.22),
                     (0.07, 0.07, 0.07), M["hair_dark"]))
    plain.append(box(tag + "_Tail3", (0, 0.465, 0.18),
                     (0.055, 0.055, 0.055), M["hair_dark"]))

    # 0.03 -- sharper still than the cow's 0.045, relative to this body's
    # narrower cross-section. The cow's ratio of bevel to half-width is ~26%;
    # 0.045 here would have run past 37% and rounded the barrel into a
    # capsule, which is exactly the plush read this animal must not have.
    soften_all(hero, width=0.03, segments=2)
    soften_all(plain, width=0.0)
    return hero + plain
