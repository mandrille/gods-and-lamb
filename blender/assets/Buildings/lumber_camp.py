"""BUILDING.works.lumber_camp - a log cabin with a water wheel and a log pile.

First of the "works" family: production buildings, as opposed to `house`
(dwellings). A new family costs a vocabulary regeneration, so it is spent
once here and reused by `mine` and `smithy`.

The reference is a full two-storey log build with a saw, an axe and a stream
of visible pebbles -- none of that survives at fifteen pixels. What does: the
horizontal log-cabin texture (read from a few protruding log-ends at the
corners, not a literal course-by-course stack, which would blow the triangle
budget rebuilding what a shingle roof already tells the eye), the water
wheel, and one pile of logs. The wheel is what makes this camp rather than
just another house painted brown.

The wheel lies in the Y-Z plane, spinning on an axle along X, flush against
the gable-end wall -- `kit.torus(plane="YZ")` orients it that way. Its spokes
are each a SEPARATE box offset to one side of the hub, never a single spoke
box centred on the axle and rotated N times: a box centred at the origin
already reaches both +r and -r, so rotating copies of it draws twice as many
arms as intended. That bug has shipped here before (see the fence and market
stall builders); this wheel avoids it the same way they do.

Fronts -Y: the door is the front gable end, the wheel is mounted on the -X
side wall so it reads in the three-quarter view without hiding the door.
"""
import math
import os

from kit import (M, box, cyl, torus, boolean, scheme, gable_roof,
                 gable_cutters, soften_all)

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="building",
    family="works",
    variant="lumber_camp",
    category=CATEGORY,
    # MEASURED. The roof overhang sets the plan reach on every side; the wheel
    # and log pile both sit inside its shadow rather than past it.
    footprint=(2.34, 2.29),   # re-measured after the fix round
    # X measures 2.492 -- inside the project's 2.5 m plan ceiling with an
    # 8 mm margin, not against it.
    anchor="floor",
    slots=(),
)

# Sized against the follower (0.855 m) and the batch's 2.4 x 2.0 target: the
# first pass measured 1.62 x 1.42, smaller than the hut, and the water wheel
# was 0.54 m across -- half the "about a follower's height" the batch calls
# for. Everything below is that draft scaled by roughly 1.5x, with the wheel
# set directly to a 1.0 m diameter rather than scaled, since it is the one
# part the batch gave an explicit target for.
W, D = 1.82, 1.58          # X trimmed: 1.95 put the plan on the 2.5 m ceiling
H = 1.02
RISE = 0.66
OVERHANG = 0.23
ROOF_T = 0.17

DOOR_W, DOOR_H = 0.63, 0.98    # ~1.0 m so a follower walks in clear
DOOR_DEPTH = 0.23

WIN_W, WIN_H = 0.39, 0.36      # ~0.35 m, the batch's window target
WIN_X, WIN_Z = 0.51, 0.75
WIN_DEPTH = 0.17

LOG_R = 0.068                 # corner log-ends, poking past the wall face
LOG_POKE = 0.09
LOG_ZS = (0.24, 0.54, 0.84)   # three courses per corner

WHEEL_R = 0.50                # 1.0 m across, the batch's explicit target
WHEEL_MINOR = 0.060
WHEEL_Z = WHEEL_R + WHEEL_MINOR   # so the RING's bottom, not its centre,
                                  # touches the ground -- the ring reaches
                                  # major+minor past its own centre.
# On the FRONT (-Y) face, disc toward the camera: on the left side wall the
# one prop that names the building was invisible from the front (review).
WHEEL_X = -W * 0.5 + 0.34
WHEEL_Y = -D * 0.5 - 0.10
SPOKES = 6

PILE_X, PILE_Y = W * 0.5 - 0.18, -D * 0.5 - 0.15


def build(tag="LUMBER", **kw):
    body, trim, roof, accent = scheme(kw.get("scheme", "lumber_log"))
    hero, plain = [], []

    walls = box(tag + "_Walls", (0, 0, (H + RISE) * 0.5), (W, D, H + RISE),
                body)
    for cutter in gable_cutters("wallcut", (0, 0, H), W, D, RISE,
                                overhang=OVERHANG, thickness=ROOF_T):
        boolean(walls, cutter)
    boolean(walls, box("door_cut",
                       (0, -D * 0.5 + DOOR_DEPTH * 0.5, DOOR_H * 0.5),
                       (DOOR_W, DOOR_DEPTH * 2.0, DOOR_H), None))
    boolean(walls, box("win_cut",
                       (WIN_X, -D * 0.5 + WIN_DEPTH * 0.5, WIN_Z),
                       (WIN_W, WIN_DEPTH * 2.0, WIN_H), None))
    hero.append(walls)

    plain.append(box(tag + "_DoorDark", (0, -D * 0.5 + DOOR_DEPTH, DOOR_H * 0.5),
                 (DOOR_W, 0.05, DOOR_H), M["hollow"]))
    plain.append(box(tag + "_WinDark", (WIN_X, -D * 0.5 + WIN_DEPTH, WIN_Z),
                 (WIN_W, 0.05, WIN_H), M["hollow"]))
    plain.append(box(tag + "_Pane", (WIN_X, -D * 0.5 - 0.007, WIN_Z),
                 (WIN_W - 0.09, 0.06, WIN_H - 0.09), M["warmglow"]))

    # Log-cabin corner ends. Only the two FRONT corners -- the back ones are
    # never in frame from the play camera and every course costs a cylinder.
    for sx, side in ((-1, "L"), (1, "R")):
        for i, z in enumerate(LOG_ZS):
            plain.append(cyl("%s_LogEnd%s%d" % (tag, side, i),
                         (sx * (W * 0.5 + LOG_POKE * 0.5), -D * 0.5, z),
                         LOG_R, D * 0.12, trim, axis="Y", verts=8))

    hero.extend(gable_roof(tag + "_Roof", (0, 0, H), W, D, RISE, roof,
                        overhang=OVERHANG, thickness=ROOF_T))
    plain.append(box(tag + "_Ridge", (0, 0, H + RISE), (0.12, D + 0.45, 0.12),
                 M["wood_dark"]))

    # The water wheel. Hub, then six spokes each offset to ONE side of it --
    # not a single bar through the centre, which would draw twice as many.
    plain.append(torus(tag + "_Wheel", (WHEEL_X, WHEEL_Y, WHEEL_Z), WHEEL_R,
                 WHEEL_MINOR, M["wood_dark"], plane="XZ", verts=16, rings=6))
    plain.append(cyl(tag + "_Hub", (WHEEL_X, WHEEL_Y, WHEEL_Z), 0.083, 0.075,
                 accent, axis="Y", verts=8))
    for i in range(SPOKES):
        ang = math.radians(360.0 / SPOKES * i)
        r_mid = WHEEL_R * 0.52
        plain.append(box("%s_Spoke%d" % (tag, i),
                     (WHEEL_X + r_mid * math.sin(ang), WHEEL_Y,
                      WHEEL_Z + r_mid * math.cos(ang)),
                     (0.042, 0.042, WHEEL_R * 0.9), trim,
                     rot=(0, -math.degrees(ang), 0)))
    plain.append(cyl(tag + "_Axle", (WHEEL_X, WHEEL_Y + 0.042, WHEEL_Z),
                 0.033, 0.15, accent, axis="Y", verts=8))
    # A short trickle at the foot of the wheel -- the accent hue break that
    # keeps a wooden wheel from reading as one more log against the wall.
    # A pond under the wheel, not a blue plank beside it.
    plain.append(box(tag + "_Water", (WHEEL_X, WHEEL_Y - 0.10, 0.03),
                 (WHEEL_R * 1.5, 0.55, 0.06), M["water"]))

    # The log pile. Two on the ground, one nested in the saddle -- a triangle
    # cross-section is what makes a pile of round things sit still.
    for i, (oy, oz) in enumerate(((-0.09, 0.083), (0.09, 0.083), (0.0, 0.22))):
        plain.append(cyl("%s_Log%d" % (tag, i), (PILE_X, PILE_Y + oy, oz),
                     0.083, 0.51, M["wood"], axis="X", verts=8))

    soften_all(hero, width=0.036, segments=2)
    soften_all(plain, width=0.0)
    return hero + plain
