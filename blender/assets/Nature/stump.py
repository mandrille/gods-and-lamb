"""NATURE.tree.stump - a cut stump, with rings.

Reads as the aftermath of `tree`: same trunk brown, same root flare, and the
top sawn flat at knee height. Placed next to a tree it says a village happened
here, which is a thing no amount of extra foliage can say.

The rings are THREE CONCENTRIC DISCS, not a texture -- there are no textures in
this project. Bark, then pale sapwood, then a red heart, each one stepping a
few millimetres proud of the last so the rim of each catches the key light.
The order matters: `trunk` -> `sand` -> `terracotta` walks around the hue
wheel rather than up a brightness ramp, so the rings survive being four pixels
across at play distance. Three browns of different value would be one brown.

A cone, not a cylinder, for the body. A stump flares: `cone(r1, r2)` with a
3.5 cm difference is the whole of it and costs nothing extra. `kit.cone` takes no
rotation, which is fine here because a stump stands straight -- if this ever
needs to lean it has to be rebuilt from a box.

Fronts -Y, like everything floor-standing.
"""
import os

from kit import M, blob, box, cone, soften_all
from plantkit import disc

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="nature",
    family="tree",
    variant="stump",
    category=CATEGORY,
    # MEASURED (0.591 x 0.549). The root flares are yawed 45 degrees, so they
    # reach past the cone by more than their box size, and the moss at the foot
    # reaches further still on one side.
    footprint=(0.59, 0.55),
    anchor="floor",
    slots=(),
)

# SQUAT. The first pass stood 0.35 m on a 0.43 m base and read as a jar: a
# stump is a cut trunk and the cut is close to the ground, so it has to be
# wider than it is tall or it is a barrel.
H = 0.22          # cut height
R_TOP = 0.215
R_BASE = 0.250


def build(tag="STUMP", **kw):
    body = [cone(tag + "_Body", (0, 0, H * 0.5), R_BASE, R_TOP, H,
                 M["trunk"], verts=10)]
    # Root flare, the same four boxes `tree` uses, turned 45 degrees off the
    # axes so they do not line up with the tile grid underneath. Low and TUCKED
    # IN against the cone: at the first pass they sat clear of it and read as
    # four bricks arranged around a pot.
    for i, (dx, dy) in enumerate(((1, 1), (1, -1), (-1, 1), (-1, -1))):
        body.append(box("%s_Root%d" % (tag, i),
                        (dx * 0.140, dy * 0.140, 0.028),
                        (0.19, 0.19, 0.056), M["trunk"], rot=(0, 0, 45)))

    # Each ring sits a little higher than the one outside it, so its rim is
    # visible edge-on rather than being a flat inlay that only reads from
    # directly above -- and the play camera is never directly above.
    rings = [
        disc(tag + "_Sap", (0, 0, H + 0.004), 0.155, 0.028, M["sand"],
             verts=10),
        disc(tag + "_Heart", (0, 0, H + 0.016), 0.078, 0.034,
             M["terracotta"], verts=8),
    ]

    # Moss at the FOOT, in two patches, not one egg on the flank. Green against
    # brown is the strongest separation this palette has and a stump with
    # nothing green on it reads as a fence post -- but a single mass halfway up
    # the side reads as a separate object leaning on it.
    #
    # Each patch OVERLAPS the cone by about a third of its width and rides up
    # the flare. Sat clear of it they read as two green cushions lying on the
    # ground next to a stump, which is two objects, not one.
    #
    # Lifted clear of z=0 by more than half their own depth, because the tilt
    # drops the downhill corner: the version before this measured a Z minimum
    # of -20 mm and the moss was the whole of it.
    moss = [
        blob(tag + "_Moss0", (-0.170, 0.105, 0.062), (0.23, 0.19, 0.090),
             M["leaf_dark"], tilt=(3, -6, 23)),
        blob(tag + "_Moss1", (0.135, 0.160, 0.052), (0.17, 0.15, 0.072),
             M["leaf"], tilt=(-4, 5, -38)),
    ]

    soften_all(body, width=0.05, segments=1)
    soften_all(moss, width=0.05, segments=2)
    # The rings are 4 cm thin. A bevel there is clamped to a millimetre and
    # spends triangles on an edge nobody can resolve; the step between the
    # discs is what draws them, not a radius.
    soften_all(rings, width=0.0)
    return body + rings + moss
