"""BUILDING.stall.market_stall - an open timber stall with a striped awning.

Low, wide and cheerful, and deliberately the opposite shape to everything else
in the village: houses are tall and narrow with a peaked roof, so a stall that
is short and broad with a single flat slope cannot be confused with one at any
distance.

The awning is real stripes, not a stripe texture -- there are no textures in
this project. Five slats laid side by side alternate between the scheme roof
colour and wool, which costs five boxes and is the single loudest thing in the
village. They tilt about X together, and because they are separated along X they
cannot intersect each other however steep the pitch gets.

The slat angle is SOLVED from the back and front edge points rather than typed
in. An angle typed in and edge points typed in disagree the moment either is
touched, and then the awning either floats off the posts or drives through the
counter.

Fronts -Y: the counter and the goods face the customer, the back board is the
far side.
"""
import math
import os

from kit import M, box, scheme, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="building",
    family="stall",
    variant="market_stall",
    category=CATEGORY,
    # MEASURED. The awning slats are rotated about X, so their thickness adds to
    # the Y reach at both ends and Y comes out past the flat span of the slats.
    footprint=(1.43, 1.04),
    anchor="floor",
    slots=(),
)

POST = 0.085
POST_X, POST_Y = 0.62, 0.34

CTR_W, CTR_D, CTR_T = 1.40, 0.36, 0.070
CTR_Z = 0.48                        # top face; waist-high on a 0.9 m follower
CTR_Y = -0.26

AWN_W = 1.44
SLATS = 5
SLAT_GAP = 0.010
SLAT_T = 0.045
AWN_BACK = (0.38, 1.08)             # (y, z) of the high edge
AWN_FRONT = (-0.64, 0.78)           # (y, z) of the low edge


def _awning_z(y):
    """Height of the awning CENTRELINE at a given y."""
    t = ((y - AWN_BACK[0])
         / (AWN_FRONT[0] - AWN_BACK[0]))
    return AWN_BACK[1] + t * (AWN_FRONT[1] - AWN_BACK[1])


def build(tag="STALL", **kw):
    body, trim, roof, accent = scheme(kw.get("scheme", "stall_market"))
    P = []

    # Each post is cut to the awning it holds up, so the back pair is taller
    # than the front pair and the slope is visibly SUPPORTED rather than
    # hovering. One shared post height put 6 cm of every front post through the
    # awning, which rendered as four brown pimples on the stripes.
    for sx, xs in ((-1, "L"), (1, "R")):
        for sy, ys in ((-1, "F"), (1, "B")):
            top = _awning_z(sy * POST_Y) - SLAT_T * 0.5
            P.append(box("%s_Post%s%s" % (tag, xs, ys),
                         (sx * POST_X, sy * POST_Y, top * 0.5),
                         (POST, POST, top), body))

    P.append(box(tag + "_Counter", (0, CTR_Y, CTR_Z - CTR_T * 0.5),
                 (CTR_W, CTR_D, CTR_T), body))
    # The apron hangs BELOW and PROUD of the counter lip. Set flush with the lip
    # it would share a face plane with the counter front and z-fight; 1 cm out
    # is also what gives the counter a visible edge from the side.
    apron_top = CTR_Z - CTR_T
    P.append(box(tag + "_Apron", (0, CTR_Y - CTR_D * 0.5 - 0.010,
                                  apron_top * 0.5 + 0.05),
                 (CTR_W - 0.06, 0.045, apron_top - 0.10), trim))
    P.append(box(tag + "_BackBoard", (0, POST_Y + 0.015, 0.62),
                 (1.28, 0.050, 0.34), M["wood_dark"]))

    # Produce. Three blocks of the accent hue on the counter: at the play camera
    # this is the only thing that says the stall is trading rather than shut.
    for i, (gx, gs, gm) in enumerate(((-0.42, 0.20, accent),
                                      (0.02, 0.17, M["pumpkin"]),
                                      (0.44, 0.19, accent))):
        P.append(box("%s_Goods%d" % (tag, i), (gx, CTR_Y, CTR_Z + gs * 0.35),
                     (gs, gs * 0.80, gs * 0.70), gm))

    # Solve the slat length and pitch from the two edge points.
    dy = AWN_FRONT[0] - AWN_BACK[0]
    dz = AWN_FRONT[1] - AWN_BACK[1]
    length = math.hypot(dy, dz)
    # Rotation about X maps local +Y to (0, cos a, sin a). Pointing local +Y at
    # the BACK edge (which is +Y and higher) gives a positive angle.
    ang = math.degrees(math.atan2(-dz, -dy))
    cy = (AWN_BACK[0] + AWN_FRONT[0]) * 0.5
    cz = (AWN_BACK[1] + AWN_FRONT[1]) * 0.5

    pitch = AWN_W / SLATS
    for i in range(SLATS):
        x = -AWN_W * 0.5 + pitch * (i + 0.5)
        P.append(box("%s_Slat%d" % (tag, i), (x, cy, cz),
                     (pitch - SLAT_GAP, length, SLAT_T),
                     roof if i % 2 == 0 else M["wool"],
                     rot=(ang, 0.0, 0.0)))

    soften_all(P, width=0.026, segments=2)
    return P
