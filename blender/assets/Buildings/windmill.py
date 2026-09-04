"""BUILDING.mill.windmill - a round stone tower with four sails on -Y.

Only member of the `mill` family (new this batch). The cap risk in this
asset is not triangles, it is FOOTPRINT: a windmill's sails are its whole
identity, and sails long enough to read as sails from across the village
reach past 1 m from the hub on each side. What keeps the plan AABB down to
roughly 2.2 x 1.2 rather than 2.2 x 2.2 is orientation -- the sails lie in
the X-Z (vertical) plane, spinning on a hub whose axle points along Y, so
their long reach is HORIZONTAL AND VERTICAL, never into the ground plane.
Lay them flat instead (spinning about Z, like a horizontal fan) and the
footprint would be a square the size of the sail span, which is not a
windmill any village has room for.

Each sail is a box offset from the hub by HALF its own length, not a bar
spanning hub-to-hub and rotated four times -- a bar through the centre
already reaches both the 0-degree and 180-degree position, so four copies of
it would draw eight arms. This is the same fix the water wheel spokes and
the farm fence both needed; kit.torus's own docstring examples this pattern.

Fronts -Y: the sails and the door both face the viewer.
"""
import math
import os

from kit import M, box, cyl, cone, boolean, scheme, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="building",
    family="mill",
    variant="windmill",
    category=CATEGORY,
    # MEASURED. Sail tip-to-tip on X, tower + roof overhang on Y -- the two
    # axes are set by completely different parts and neither predicts the
    # other.
    footprint=(2.23, 1.15),
    anchor="floor",
    slots=(),
)

TOWER_R = 0.50   # grown from 0.34: the fix round asked Y to grow toward
                  # 1.2 m without the sails leaving -Y, and the tower's own
                  # diameter is the one dimension that does that without
                  # touching the sail geometry at all
ROOF_RISE = 0.40
ROOF_OVER = 0.05

DOOR_W, DOOR_H = 0.28, 0.46
DOOR_DEPTH = 0.20

HUB_Y = -TOWER_R * 0.76 - 0.03   # against the TAPERED wall at hub height
HUB_R = 0.06

SAIL_LEN = 1.05
# The hub sits high enough that the LOWEST sail -- pointing straight down,
# reaching HUB_R + SAIL_LEN past the hub -- still clears the ground with an
# 8 cm margin. The first pass mounted it at 0.70 of a much shorter tower and
# the down-pointing blade measured z = -0.466: `-- measure` never lies, but
# a sail's reach past its own hub is easy to forget while eyeballing a
# tower's proportions.
HUB_Z = 1.50                    # sails in an X clear the ground by a margin
TOWER_H = HUB_Z + 0.06          # eaves just above the hub mount; 1.56 m --
                                # a 1.2 m drum under a cone read as a silo
TOP_R = TOWER_R * 0.76          # tapered, like the reference
SAIL_W, SAIL_T = 0.11, 0.028
PAD_W, PAD_T = 0.14, 0.030
PAD_RS = (0.34, 0.72)           # two lattice pads per blade, at these radii

IVY_X, IVY_Y = TOWER_R - 0.03, -0.06


def build(tag="WINDMILL", **kw):
    body, trim, roof, accent = scheme(kw.get("scheme", "windmill_stone"))
    hero, plain = [], []

    tower = cone(tag + "_Tower", (0, 0, TOWER_H * 0.5), TOWER_R, TOP_R, TOWER_H,
                 body, verts=12)
    boolean(tower, box("door_cut",
                       (0, -TOWER_R - DOOR_DEPTH, DOOR_H * 0.5),
                       (DOOR_W, DOOR_DEPTH * 2.0, DOOR_H), None))
    hero.append(tower)

    plain.append(box(tag + "_DoorDark", (0, -TOWER_R + 0.01, DOOR_H * 0.5),
                 (DOOR_W, 0.04, DOOR_H), M["hollow"]))

    hero.append(cone(tag + "_Roof", (0, 0, TOWER_H + ROOF_RISE * 0.5),
                     TOP_R + ROOF_OVER, 0.02, ROOF_RISE, roof, verts=12))

    # Ivy: three overlapping leaf boxes climbing the base -- the one warm-
    # green break in an otherwise all-stone silhouette.
    for i, (dz, sc) in enumerate(((0.0, 1.0), (0.13, 0.82), (0.24, 0.60))):
        plain.append(box("%s_Ivy%d" % (tag, i), (IVY_X, IVY_Y, 0.10 + dz),
                     (0.09 * sc, 0.09 * sc, 0.15 * sc), accent,
                     rot=(4, 6, 12 * i)))

    # The hub and its axle nub, proud of the tower face.
    plain.append(cyl(tag + "_Hub", (0, HUB_Y, HUB_Z), HUB_R, 0.05, trim,
                 axis="Y", verts=10))
    plain.append(cyl(tag + "_Axle", (0, HUB_Y - 0.03, HUB_Z), 0.028, 0.06,
                 trim, axis="Y", verts=8))

    # Four sails, each one box offset to ONE side of the hub -- see the
    # module docstring for why this is not a single centred bar rotated.
    for i in range(4):
        # +45: at 0/90/180/270 one sail ran straight down the tower face
        # through the roof, the wall and the door (review).
        ang = math.radians(90.0 * i + 45.0)
        s, c = math.sin(ang), math.cos(ang)
        r_mid = HUB_R + SAIL_LEN * 0.5
        plain.append(box("%s_Sail%d" % (tag, i),
                     (r_mid * s, HUB_Y, HUB_Z + r_mid * c),
                     (SAIL_W, SAIL_T, SAIL_LEN), M["wood"],
                     rot=(0, math.degrees(ang), 0)))
        # Two lattice pads per blade -- the "clay-pad" cross-slats the batch
        # calls for, each its own box at the SAME radius rule, rotated 90
        # degrees further so it lies ACROSS the blade rather than along it.
        for j, r in enumerate(PAD_RS):
            plain.append(box("%s_Pad%d_%d" % (tag, i, j),
                         (r * s, HUB_Y - 0.006, HUB_Z + r * c),
                         (PAD_W, PAD_T, PAD_W * 0.42), M["wood_dark"],
                         rot=(0, math.degrees(ang), 0)))

    soften_all(hero, width=0.05, segments=2)
    soften_all(plain, width=0.0)
    return hero + plain
