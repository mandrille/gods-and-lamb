"""BUILDING.inn.tavern - the village tavern, first of a NEW family: `inn`.

Styled after `refs/buildings/Clay_medieval_tavern_inn_building`: a cream
plaster cube, a steep terracotta tile roof, ONE `warmglow` window (the
reference lights both, but at fifteen pixels one lit window says "open for
business" as loudly as two, and the second one was budget better spent on the
sign), a hanging sign on a bracket, an arched door and a chimney.

`inn` is a new family -- `hotel` joins it, sharing nothing structurally (this
is a single low room, the hotel is three stacked ones) but both are places a
follower can go INSIDE the fiction rather than just past, which is what the
family name is for.

Fronts -Y. The ridge runs front-to-back, so the -Y elevation is the gable end
and carries the door, the window and the sign.
"""
import os

from kit import M, box, cyl, boolean, scheme, gable_roof, gable_cutters, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="building",
    family="inn",
    variant="tavern",
    category=CATEGORY,
    # MEASURED, not derived -- the rotated roof slab and the sign bracket both
    # reach past the plan arithmetic on the wall box alone.
    footprint=(1.98, 1.96),
    anchor="floor",
    slots=(),
)

W, D = 1.58, 1.38
H, RISE = 0.90, 0.58
OVERHANG, ROOF_T = 0.18, 0.13

DOOR_W, DOOR_H, DOOR_DEPTH = 0.42, 0.72, 0.15
WIN_W, WIN_H, WIN_Z, WIN_X, WIN_DEPTH = 0.28, 0.26, 0.50, 0.42, 0.11

CHIM_R, CHIM_STACK = 0.075, 0.20
CHIM_X, CHIM_Y = 0.46, 0.32

SIGN_X = -DOOR_W * 0.5 - 0.24          # opposite the lit window, off the door


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


def build(tag="TAVERN", **kw):
    body, trim, roof, accent = scheme(kw.get("scheme", "tavern_cream"))
    P = []

    walls = box(tag + "_Walls", (0, 0, (H + RISE) * 0.5), (W, D, H + RISE), body)
    for cutter in gable_cutters("wallcut", (0, 0, H), W, D, RISE,
                                overhang=OVERHANG, thickness=ROOF_T):
        boolean(walls, cutter)

    fy = -D * 0.5
    _arch_cut(walls, 0.0, fy + DOOR_DEPTH * 0.5, DOOR_W, DOOR_H, DOOR_DEPTH * 2.0)
    for wx in (WIN_X, -WIN_X):
        boolean(walls, box("wincut_%d" % int(wx * 100), (wx, fy + WIN_DEPTH * 0.5, WIN_Z),
                           (WIN_W, WIN_DEPTH * 2.0, WIN_H), None))
    P.append(walls)

    P.extend(_arch_fill(tag + "_DoorDark", 0.0, fy + DOOR_DEPTH, DOOR_W, DOOR_H,
                        M["hollow"]))
    # TWO lit windows, one each side of the door: at play scale the tavern
    # with one was the cottage (review), and "lit windows" is the reference's
    # identity. `accent` resolves to `warmglow` for this scheme.
    for wx in (WIN_X, -WIN_X):
        P.append(box("%s_WinDark%d" % (tag, int(wx * 100)), (wx, fy + WIN_DEPTH, WIN_Z),
                     (WIN_W, 0.04, WIN_H), M["hollow"]))
        P.append(box("%s_Pane%d" % (tag, int(wx * 100)), (wx, fy - 0.005, WIN_Z),
                     (WIN_W - 0.055, 0.05, WIN_H - 0.055), accent))

    r = DOOR_W * 0.5
    spring = DOOR_H - r
    ty = fy - 0.018
    for sx in (-1, 1):
        P.append(box("%s_Jamb%s" % (tag, "L" if sx < 0 else "R"),
                     (sx * (r + 0.035), ty, spring * 0.5),
                     (0.065, 0.05, spring), trim))

    roof_parts = gable_roof(tag + "_Roof", (0, 0, H), W, D, RISE, roof,
                            overhang=OVERHANG, thickness=ROOF_T)
    P.extend(roof_parts)
    P.append(box(tag + "_Ridge", (0, 0, H + RISE), (0.10, D + OVERHANG * 2.0 + 0.06, 0.10),
                 M["wood_dark"]))

    # Chimney, same ground-to-ridge+stack pierce-through as the house builder.
    chim_top = H + RISE + CHIM_STACK
    P.append(cyl(tag + "_Chimney", (CHIM_X, CHIM_Y, chim_top * 0.5), CHIM_R,
                 chim_top, M["stone"], verts=8))
    P.append(cyl(tag + "_ChimneyCap", (CHIM_X, CHIM_Y, chim_top - 0.01),
                 CHIM_R + 0.02, 0.05, M["stone_dark"], verts=8))

    # The hanging sign: an L-bracket proud of the wall and a board swinging
    # from it. No text -- at fifteen pixels a board of the trim colour with
    # one accent dot reads as "a sign" exactly as well as painted lettering
    # would, for a triangle count text cannot approach.
    # Hung from the EAVES on a bracket projecting 0.35 m, so it breaks the
    # roofline -- at door height projecting 15 cm it never left the wall's
    # own silhouette and the tavern was the cottage (review).
    bx = SIGN_X
    bracket_z = H - 0.04
    P.append(box(tag + "_Bracket", (bx, fy - 0.19, bracket_z),
                 (0.035, 0.36, 0.035), M["iron_dark"]))
    board_z = bracket_z - 0.16
    P.append(box(tag + "_SignBoard", (bx, fy - 0.31, board_z),
                 (0.26, 0.03, 0.20), trim))
    # A painted mark, not the emissive `accent` -- the sign is read by
    # daylight, and a glowing dot on a board would read as a second window.
    P.append(box(tag + "_SignMark", (bx, fy - 0.328, board_z),
                 (0.13, 0.012, 0.10), M["cloth_red"]))

    hero = [walls] + roof_parts
    plain = [p for p in P if p not in hero]
    soften_all(hero, width=0.036, segments=2)
    soften_all(plain, width=0.0)
    return P
