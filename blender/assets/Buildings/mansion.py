"""BUILDING.house.mansion - the grandest house in the village, `mansion_teal`.

Styled after `refs/buildings/Medieval_clay_mansion_architecture`, cut down to
what survives at fifteen pixels: a tall two-storey gable body roofed
`tile_blue`, a single-storey lean-to WING roofed `tile_green` so the two new
roof tiles this batch added sit side by side the way the reference uses them,
a railed balcony over the front door, and a small domed tower astride the
ridge. That is more masses than the other houses, which is why this is one of
the batch's two cap risks -- the wing's roof is a single tilted slab (a
mono-pitch shed, not a second gable) and the tower is a box-and-dome, not a
second full gable_roof(), because a second ridge/eaves/gable-cutter set here
would have doubled the triangle count for a silhouette detail nobody needs at
play distance.

Same family as `hut`/`cottage` and deliberately so -- it is still a HOUSE, the
biggest one, not a new kind of building.

Fronts -Y. The ridge runs front-to-back; the balcony and the door are on the
gable end.
"""
import math
import os

from kit import M, box, cyl, sphere, boolean, scheme, gable_roof, gable_cutters, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="building",
    family="house",
    variant="mansion",
    category=CATEGORY,
    # MEASURED: the wing's shed roof oversails the main wall in +X, and the
    # tower's dome oversails the ridge in Z but also nudges +Y past the
    # ridge beam -- neither shows up in the wall-box arithmetic.
    footprint=(2.52, 1.97),
    anchor="floor",
    slots=(),
)

W, D = 1.62, 1.52
H, RISE = 1.28, 0.62
OVERHANG, ROOF_T = 0.17, 0.13

DOOR_W, DOOR_H, DOOR_DEPTH = 0.44, 0.74, 0.15
GWIN_W, GWIN_H, GWIN_Z, GWIN_X, GWIN_DEPTH = 0.26, 0.26, 0.52, 0.48, 0.11

BAL_Z = 0.88                      # floor of the balcony doorway
BAL_DOOR_W, BAL_DOOR_H = 0.40, 0.62
BAL_DEPTH = 0.24                  # how far the platform projects
BAL_RAIL_H = 0.20

TOWER_R, TOWER_STACK, DOME_H = 0.24, 0.34, 0.20

WING_W, WING_D, WING_H = 0.62, 0.52, 0.66     # plan size and eaves height
WING_X = W * 0.5 + WING_W * 0.5 - 0.06        # nudged into the main corner
WING_PITCH_RISE = 0.30                        # the shed slab's own rise


def _arch_cut(target, cx, cy, w, z_top, depth, z_bottom=0.0):
    r = w * 0.5
    spring = z_top - r
    h_rect = spring - z_bottom
    boolean(target, box("archcut_rect", (cx, cy, z_bottom + h_rect * 0.5),
                        (w, depth, h_rect), None))
    boolean(target, cyl("archcut_top", (cx, cy, spring), r, depth, None,
                        axis="Y", verts=12))


def _arch_fill(tag, cx, cy, w, z_top, mat, z_bottom=0.0):
    r = w * 0.5
    spring = z_top - r
    h_rect = spring - z_bottom
    parts = [box("%s_Rect" % tag, (cx, cy, z_bottom + h_rect * 0.5),
                 (w, 0.04, h_rect), mat)]
    parts.append(cyl("%s_Arch" % tag, (cx, cy, spring), r, 0.04, mat,
                     axis="Y", verts=12))
    return parts


def build(tag="MANSION", **kw):
    body, trim, roof, accent = scheme(kw.get("scheme", "mansion_teal"))
    P = []

    walls = box(tag + "_Walls", (0, 0, (H + RISE) * 0.5), (W, D, H + RISE), body)
    for cutter in gable_cutters("wallcut", (0, 0, H), W, D, RISE,
                                overhang=OVERHANG, thickness=ROOF_T):
        boolean(walls, cutter)

    fy = -D * 0.5
    _arch_cut(walls, 0.0, fy + DOOR_DEPTH * 0.5, DOOR_W, DOOR_H, DOOR_DEPTH * 2.0)
    for sx in (-1, 1):
        boolean(walls, box("gwin_%d" % sx,
                           (sx * GWIN_X, fy + GWIN_DEPTH * 0.5, GWIN_Z),
                           (GWIN_W, GWIN_DEPTH * 2.0, GWIN_H), None))
    # The balcony doorway -- an arch, upper floor, centred.
    _arch_cut(walls, 0.0, fy + DOOR_DEPTH * 0.5, BAL_DOOR_W,
             BAL_Z + BAL_DOOR_H, DOOR_DEPTH * 2.0, z_bottom=BAL_Z)
    P.append(walls)

    P.extend(_arch_fill(tag + "_DoorDark", 0.0, fy + DOOR_DEPTH, DOOR_W, DOOR_H,
                        M["hollow"]))
    for sx, side in ((-1, "L"), (1, "R")):
        P.append(box("%s_GWinDark%s" % (tag, side),
                     (sx * GWIN_X, fy + GWIN_DEPTH, GWIN_Z),
                     (GWIN_W, 0.04, GWIN_H), M["hollow"]))
        P.append(box("%s_GWinPane%s" % (tag, side),
                     (sx * GWIN_X, fy - 0.005, GWIN_Z),
                     (GWIN_W - 0.05, 0.05, GWIN_H - 0.05), M["warmglow"]))
    P.extend(_arch_fill(tag + "_BalDoorDark", 0.0, fy + DOOR_DEPTH, BAL_DOOR_W,
                        BAL_Z + BAL_DOOR_H, M["hollow"], z_bottom=BAL_Z))

    # Door jambs, ground floor only -- the hue break.
    r = DOOR_W * 0.5
    spring = DOOR_H - r
    ty = fy - 0.018
    for sx in (-1, 1):
        P.append(box("%s_Jamb%s" % (tag, "L" if sx < 0 else "R"),
                     (sx * (r + 0.035), ty, spring * 0.5),
                     (0.06, 0.05, spring), trim))

    # The balcony: a platform proud of the wall, a rail of thin balusters and
    # a cap rail. Balusters are BOXES at segments=2 -- cylinders here would be
    # the same mistake the old barrel-band design made, more triangles for a
    # part too small to read as round anyway.
    bal_y = fy - BAL_DEPTH * 0.5
    P.append(box(tag + "_Balcony", (0, bal_y, BAL_Z - 0.03),
                 (BAL_DOOR_W + 0.34, BAL_DEPTH, 0.06), trim))
    rail_y = fy - BAL_DEPTH + 0.02
    n_baluster = 5
    for i in range(n_baluster):
        bx = -( (BAL_DOOR_W + 0.30) * 0.5) + (BAL_DOOR_W + 0.30) * i / (n_baluster - 1)
        P.append(box("%s_Baluster%d" % (tag, i), (bx, rail_y, BAL_Z + BAL_RAIL_H * 0.5),
                     (0.035, 0.035, BAL_RAIL_H), trim))
    P.append(box(tag + "_RailTop", (0, rail_y, BAL_Z + BAL_RAIL_H),
                 (BAL_DOOR_W + 0.34, 0.05, 0.035), trim))

    roof_parts = gable_roof(tag + "_Roof", (0, 0, H), W, D, RISE, roof,
                            overhang=OVERHANG, thickness=ROOF_T)
    P.extend(roof_parts)
    P.append(box(tag + "_Ridge", (0, 0, H + RISE), (0.10, D + OVERHANG * 2.0 + 0.06, 0.10),
                 M["wood_dark"]))

    # The tower: box pierced through the roof (same trick as bld_house's
    # chimney), astride the ridge at the FRONT, capped with a squashed sphere
    # for the dome -- cheap because it is small and low-segment, not because
    # it is a cone: a dome has no apex to fake with one.
    tower_y = fy + 0.30
    tower_top = H + RISE + TOWER_STACK
    P.append(cyl(tag + "_Tower", (0, tower_y, tower_top * 0.5), TOWER_R,
                 tower_top, body, verts=10))
    P.append(box(tag + "_TowerBand", (0, tower_y, tower_top + 0.01),
                 (TOWER_R * 2.0 + 0.05, TOWER_R * 2.0 + 0.05, 0.03), trim))
    P.append(sphere(tag + "_Dome", (0, tower_y, tower_top + DOME_H * 0.35),
                    TOWER_R + 0.03, roof, squash=0.62, segs=10))
    P.append(box(tag + "_Finial", (0, tower_y, tower_top + DOME_H * 0.62),
                 (0.03, 0.03, 0.10), trim))

    # The wing: a single-storey lean-to at the +X corner, roofed in the
    # SECOND new tile colour so the batch's two roof tiles sit side by side
    # the way the reference does. A mono-pitch (one rotated slab) rather than
    # a second gable_roof() -- a full ridge/eaves/gable-cutter set here would
    # have been triangle spend on a silhouette nobody reads twice.
    wing_y = fy + WING_D * 0.5 + 0.05
    wing = box(tag + "_Wing", (WING_X, wing_y, WING_H * 0.5),
              (WING_W, WING_D, WING_H), body)
    P.append(wing)
    P.append(box(tag + "_WingWinDark", (WING_X, fy - 0.005, WING_H * 0.58),
                 (0.22, 0.04, 0.20), M["hollow"]))
    P.append(box(tag + "_WingWinPane", (WING_X, fy - 0.015, WING_H * 0.58),
                 (0.17, 0.05, 0.15), M["warmglow"]))
    # One tilted slab, resting on the WING's own flat top -- not spanning down
    # from the main eave. The first version pinned the inner edge at the main
    # eave height (H) and the outer edge at the wing's eave height (WING_H)
    # and connected them with one straight slope; since the wing BOX top is
    # FLAT at WING_H for its whole run, that slab only touched the box at the
    # single outer corner and floated up to 62 cm clear of the box everywhere
    # else -- a roof hovering over its own wall with daylight under it.
    # A lean-to actually attaches partway UP the taller wall it leans on and
    # stays close to the box it covers, so both ends are pinned near WING_H
    # with a shallow pitch between them, and the tall wall stays visible
    # above the attachment line the way a real lean-to leaves it.
    x_inner = W * 0.5 - 0.02
    x_outer = WING_X + WING_W * 0.5 + 0.08
    z_inner = WING_H + 0.22
    z_outer = WING_H + 0.03
    dx = x_outer - x_inner
    dz = z_outer - z_inner             # negative: outer eave sits lower
    wing_slope = math.hypot(dx, dz)
    wing_pitch = math.degrees(math.atan2(-dz, dx))
    P.append(box(tag + "_WingRoof",
                 ((x_inner + x_outer) * 0.5, wing_y, (z_inner + z_outer) * 0.5),
                 (wing_slope, WING_D + 0.14, ROOF_T), accent,
                 rot=(0, wing_pitch, 0)))

    hero = [walls, wing] + roof_parts
    plain = [p for p in P if p not in hero]
    soften_all(hero, width=0.036, segments=2)
    soften_all(plain, width=0.0)
    return P
