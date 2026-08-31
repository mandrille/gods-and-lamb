"""NATURE.tree.log - a fallen mossy log.

The one horizontal thing in the vegetation set. Everything else in Nature is a
vertical mass, so a metre-long lying cylinder breaks up a run of grass in a way
another bush cannot -- it is a different silhouette, not a different green.

Three hues, and each of them is doing a job:

  `trunk`  the bark, the dark anchor
  `sand`   the broken ends. Bark against exposed heartwood is the only detail
           on a log that survives to island distance, and it only survives if
           the two differ in HUE. A darker or lighter brown end reads as
           shadow, which under GL Compatibility is exactly what it would be
           mistaken for -- there is no AO pass to say otherwise.
  `leaf`   moss on the upper side. Green on brown is the strongest separation
           available in this palette and it is what says "fallen a while ago"
           rather than "a piece of timber someone left here".

The end discs PROTRUDE past the body rather than sitting flush with it. Two
coplanar faces z-fight, and the log is instanced along a whole shoreline.

Not level, and not on an axis: yawed 12 degrees off X and tipped 4 degrees
along its length, so it never lines up with the tile grid it lies on.
"""
import math
import os

from kit import M, blob, cyl, soften_all, seat
from plantkit import up

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="nature",
    family="tree",
    variant="log",
    category=CATEGORY,
    # MEASURED (1.085 x 0.476). The yaw means the Y span is not the log's
    # diameter -- a 1.02 m body turned 12 degrees reaches 0.21 m across on its
    # own, before the moss on top of it.
    footprint=(1.09, 0.48),
    anchor="floor",
    slots=(),
)

LEN = 1.02
R = 0.135
YAW = 12.0        # degrees off +X, so the log never parallels a tile edge
TIP = 4.0         # degrees of rise along its length: the ground is not flat
CZ = 0.172        # centre height, set so the LOW end still clears z=0 --
                  # the rise along the length drops one end by 3.6 cm


def build(tag="LOG", **kw):
    # rot REPLACES the axis argument in kit.cyl, so the whole orientation is
    # written once here. Ry(90 - TIP) lays the cylinder down and leaves it
    # rising slightly; Rz(YAW) turns it off the grid.
    lie = (0.0, 90.0 - TIP, YAW)
    # up() does not know about the yaw, so turn the direction by hand.
    axis = up(0.0, 90.0 - TIP)
    c, s = math.cos(math.radians(YAW)), math.sin(math.radians(YAW))
    axis = (axis[0] * c - axis[1] * s, axis[0] * s + axis[1] * c, axis[2])

    body = [cyl(tag + "_Body", (0, 0, CZ), R, LEN, M["trunk"], verts=12,
                rot=lie)]
    # A broken branch, on one side only. A log with a symmetric feature at both
    # ends reads as a rolling pin.
    #
    # 55 degrees above horizontal, and it took two tries to land there: straight
    # up it was a peg driven into the trunk, and at 35 it pointed roughly along
    # the play camera so all that showed was its unlit end cap and it read as a
    # knot-hole bored into the log.
    stub_at = 0.28
    body.append(cyl(tag + "_Stub",
                    (axis[0] * stub_at - 0.023, axis[1] * stub_at - 0.040,
                     CZ + 0.086),
                    0.050, 0.26, M["trunk"], verts=6, rot=(35.0, 0.0, -30.0)))

    ends = []
    for i, sign in enumerate((1, -1)):
        # Pushed just PAST the body end and no further. Buried flush it would
        # share a face with the cap and z-fight; the first version stood 3.7 cm
        # proud and read as a lid bolted on rather than as the cut face.
        d = sign * (LEN * 0.5 + 0.004)
        ends.append(cyl("%s_End%d" % (tag, i),
                        (axis[0] * d, axis[1] * d, CZ + axis[2] * d),
                        0.126, 0.030, M["sand"], verts=10, rot=lie))

    # Moss, only on the upper side and only in patches. A log furred evenly
    # along its whole length reads as a green log, which is a different object.
    #
    # Seated at 0.55 of the radius and no deeper than 10 cm, so a patch caps the
    # crown of the log rather than clinging to its shoulder. At 0.42 with 13 cm
    # of depth the biggest one hung off the side as a green brick.
    #
    # Pitched a few degrees each, because three flat-topped patches in a line
    # are three roof tiles.
    moss = []
    for i, (t, dx, dy, size, mat, pitch) in enumerate((
            (-0.28, 0.02, -0.03, (0.30, 0.25, 0.10), "leaf_dark", (5, -4)),
            (0.05, -0.03, 0.03, (0.20, 0.18, 0.09), "leaf", (-6, 5)),
            (0.32, 0.02, 0.03, (0.24, 0.21, 0.10), "leaf_dark", (4, 6)))):
        moss.append(blob("%s_Moss%d" % (tag, i),
                         (axis[0] * t + dx, axis[1] * t + dy,
                          CZ + axis[2] * t + R * 0.55),
                         size, M[mat],
                         tilt=(pitch[0], pitch[1], YAW + (i - 1) * 9.0)))

    soften_all(body + ends, width=0.05, segments=1)
    soften_all(moss, width=0.05, segments=2)
    # A lying cylinder with a tip angle does not rest where the arithmetic
    # says. Measured: this was floating 5 mm above the ground.
    seat(body + ends + moss)
    return body + ends + moss
