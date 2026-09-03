"""BUILDING.inn.hotel - the village's tall lodging house, `hotel_timber`.

Styled after `refs/buildings/Clay_medieval_hotel_architecture`: three stacked
storeys (one tall wall cut back to the roofline, the storeys implied by
horizontal timber bands rather than three separate boxes -- a second and
third floor box each would have needed their own gable treatment and this
family already has one cap-risk sibling in `mansion`), half-timbering as thin
`wood_dark` boxes over the `sand` body, a second-floor balcony with a potted
plant, a hanging sign, and a `shingle` roof.

Second member of the `inn` family alongside `tavern` -- both are places a
follower goes INSIDE the fiction, sharing nothing structurally (this is three
rooms stacked, tavern is one), which is what the family groups on.

Fronts -Y. The ridge runs front-to-back; door, balcony and sign are on the
gable end.
"""
import os

from kit import M, box, cyl, boolean, scheme, gable_roof, gable_cutters, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="building",
    family="inn",
    variant="hotel",
    category=CATEGORY,
    # MEASURED: the balcony platform and the sign bracket both project past
    # the wall-box plan, and the rotated roof slab reaches past it too.
    footprint=(1.96, 1.77),
    anchor="floor",
    slots=(),
)

W, D = 1.56, 1.36
F1_H, F2_H, F3_H = 0.62, 0.58, 0.52       # three storeys, implied by timber bands
H = F1_H + F2_H + F3_H
RISE, OVERHANG, ROOF_T = 0.54, 0.16, 0.12

DOOR_W, DOOR_H, DOOR_DEPTH = 0.42, 0.72, 0.15
GWIN_W, GWIN_H, GWIN_Z, GWIN_X, WIN_DEPTH = 0.24, 0.22, F1_H * 0.5, 0.44, 0.11
WIN2_W, WIN2_H = 0.24, 0.24
WIN2_Z = F1_H + F2_H * 0.5
WIN3_W, WIN3_H = 0.20, 0.20
WIN3_Z = F1_H + F2_H + F3_H * 0.5

BEAM_T = 0.028
BAL_DEPTH = 0.20
BAL_RAIL_H = 0.18

SIGN_X = GWIN_X


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


def build(tag="HOTEL", **kw):
    body, trim, roof, accent = scheme(kw.get("scheme", "hotel_timber"))
    P = []

    walls = box(tag + "_Walls", (0, 0, (H + RISE) * 0.5), (W, D, H + RISE), body)
    for cutter in gable_cutters("wallcut", (0, 0, H), W, D, RISE,
                                overhang=OVERHANG, thickness=ROOF_T):
        boolean(walls, cutter)

    fy = -D * 0.5
    _arch_cut(walls, 0.0, fy + DOOR_DEPTH * 0.5, DOOR_W, DOOR_H, DOOR_DEPTH * 2.0)
    boolean(walls, box("gwin_cut", (GWIN_X, fy + WIN_DEPTH * 0.5, GWIN_Z),
                       (GWIN_W, WIN_DEPTH * 2.0, GWIN_H), None))
    boolean(walls, box("w2_cut", (0.0, fy + WIN_DEPTH * 0.5, WIN2_Z),
                       (WIN2_W, WIN_DEPTH * 2.0, WIN2_H), None))
    boolean(walls, box("w3_cut", (0.0, fy + WIN_DEPTH * 0.5, WIN3_Z),
                       (WIN3_W, WIN_DEPTH * 2.0, WIN3_H), None))
    P.append(walls)

    P.extend(_arch_fill(tag + "_DoorDark", 0.0, fy + DOOR_DEPTH, DOOR_W, DOOR_H,
                        M["hollow"]))
    P.append(box(tag + "_GWinDark", (GWIN_X, fy + WIN_DEPTH, GWIN_Z),
                 (GWIN_W, 0.04, GWIN_H), M["hollow"]))
    P.append(box(tag + "_GWinPane", (GWIN_X, fy - 0.005, GWIN_Z),
                 (GWIN_W - 0.05, 0.05, GWIN_H - 0.05), M["warmglow"]))
    P.append(box(tag + "_Win2Dark", (0.0, fy + WIN_DEPTH, WIN2_Z),
                 (WIN2_W, 0.04, WIN2_H), M["hollow"]))
    P.append(box(tag + "_Win2Pane", (0.0, fy - 0.005, WIN2_Z),
                 (WIN2_W - 0.05, 0.05, WIN2_H - 0.05), M["warmglow"]))
    P.append(box(tag + "_Win3Dark", (0.0, fy + WIN_DEPTH, WIN3_Z),
                 (WIN3_W, 0.04, WIN3_H), M["hollow"]))
    P.append(box(tag + "_Win3Pane", (0.0, fy - 0.005, WIN3_Z),
                 (WIN3_W - 0.045, 0.05, WIN3_H - 0.045), M["warmglow"]))

    r = DOOR_W * 0.5
    spring = DOOR_H - r
    ty = fy - 0.016
    for sx in (-1, 1):
        P.append(box("%s_Jamb%s" % (tag, "L" if sx < 0 else "R"),
                     (sx * (r + 0.03), ty, spring * 0.5),
                     (0.055, 0.045, spring), trim))

    # Half-timbering: two horizontal bands marking the floor lines, and four
    # corner posts full height -- the grid the reference repeats over the
    # whole face, cut down to the lines that actually carry the READ (floor
    # divisions and corners) rather than every stud the reference draws.
    ty2 = fy - 0.006
    for bz in (F1_H, F1_H + F2_H):
        P.append(box("%s_Band%d" % (tag, int(bz * 100)), (0, ty2, bz),
                     (W - 0.02, BEAM_T, BEAM_T * 1.4), M["wood_dark"]))
    for sx in (-1, 1):
        P.append(box("%s_CornerPost%d" % (tag, sx), (sx * (W * 0.5 - 0.025), ty2,
                     H * 0.5), (BEAM_T * 1.3, BEAM_T, H), M["wood_dark"]))
    # One pair of short diagonal braces at the top storey -- the one
    # timber-frame flourish this budget spends beyond the grid. rot is about
    # Y, not Z: the wall faces -Y, so a diagonal drawn ON that flat vertical
    # face is a tilt between X (across) and Z (up), which is the Y axis's
    # rotation -- a Z (yaw) rotation would instead swing the brace into and
    # out of the wall, invisible face-on.
    for sx in (-1, 1):
        P.append(box("%s_Brace%d" % (tag, sx),
                     (sx * (GWIN_X * 0.55), ty2, F1_H + F2_H + F3_H * 0.5),
                     (0.30, BEAM_T, BEAM_T * 1.3), M["wood_dark"],
                     rot=(0, sx * 28, 0)))

    roof_parts = gable_roof(tag + "_Roof", (0, 0, H), W, D, RISE, roof,
                            overhang=OVERHANG, thickness=ROOF_T)
    P.extend(roof_parts)
    P.append(box(tag + "_Ridge", (0, 0, H + RISE), (0.09, D + OVERHANG * 2.0 + 0.06, 0.09),
                 M["wood_dark"]))

    # The balcony: a shallow ledge under the second-floor window with a rail
    # and one potted plant -- `accent` is `leaf` for this scheme, so the
    # foliage is the scheme's own colour rather than a hardcoded green.
    bal_y = fy - BAL_DEPTH * 0.5
    bal_z = F1_H + F2_H * 0.12
    P.append(box(tag + "_Balcony", (0, bal_y, bal_z - 0.03),
                 (WIN2_W + 0.34, BAL_DEPTH, 0.05), trim))
    rail_y = fy - BAL_DEPTH + 0.02
    n_bal = 4
    for i in range(n_bal):
        rx = -(WIN2_W + 0.30) * 0.5 + (WIN2_W + 0.30) * i / (n_bal - 1)
        P.append(box("%s_Baluster%d" % (tag, i), (rx, rail_y, bal_z + BAL_RAIL_H * 0.5),
                     (0.03, 0.03, BAL_RAIL_H), trim))
    P.append(box(tag + "_RailTop", (0, rail_y, bal_z + BAL_RAIL_H),
                 (WIN2_W + 0.34, 0.045, 0.03), trim))
    potx, poty = WIN2_W * 0.5 + 0.10, bal_y
    P.append(cyl(tag + "_Pot", (potx, poty, bal_z + 0.03), 0.045, 0.08,
                 M["terracotta"], verts=8))
    P.append(box(tag + "_Plant", (potx, poty, bal_z + 0.10), (0.06, 0.06, 0.10),
                 accent))

    # The hanging sign, ground floor, opposite the lit window.
    bx = -GWIN_X
    bracket_z = DOOR_H + 0.05
    P.append(box(tag + "_Bracket", (bx, fy - 0.085, bracket_z),
                 (0.028, 0.15, 0.028), M["iron_dark"]))
    board_z = bracket_z - 0.11
    P.append(box(tag + "_SignBoard", (bx, fy - 0.145, board_z),
                 (0.19, 0.022, 0.15), trim))
    P.append(box(tag + "_SignMark", (bx, fy - 0.157, board_z),
                 (0.085, 0.01, 0.065), M["cloth_red"]))

    hero = [walls] + roof_parts
    plain = [p for p in P if p not in hero]
    soften_all(hero, width=0.032, segments=2)
    soften_all(plain, width=0.0)
    return P
