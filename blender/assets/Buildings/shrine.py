"""BUILDING.shrine.shrine - the little village church Faith comes from.

REDONE from a Greco-Roman temple onto `refs/buildings/Clay_medieval_church_building`:
an adobe nave with a gable roof, a bell tower at the front corner topped with a
pyramid roof and a cross, three tall arched windows glazed `tile_blue`, and a
plain arched door. The tower is what makes this readable as a CHURCH rather
than another house at fifteen pixels -- it is the one silhouette in the
village with a vertical spike and a cross on it, so it can be found without
being looked for, the same job gold used to do for the old temple.

The windows are tall and narrow rather than square, which is the one shape cue
that reads as "church" instead of "house" even before the tower registers --
a square hole is a house window at any colour.

Fronts -Y. The ridge runs front-to-back, so the -Y elevation is the gable end
and it carries the door, the tower and the front window.
"""
import os

from kit import M, box, cyl, cone, boolean, scheme, gable_roof, gable_cutters, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="building",
    family="shrine",
    variant="shrine",
    category=CATEGORY,
    # MEASURED, not derived: the tower sits OUTSIDE the nave footprint at the
    # front-left corner and its own pyramid roof overhangs further still, so
    # the true X reach is the nave's roof overhang PLUS the tower offset PLUS
    # the tower roof overhang -- three numbers the plan arithmetic on the nave
    # alone does not see.
    footprint=(2.38, 1.85),
    anchor="floor",
    slots=(),
)

NAVE_W, NAVE_D = 1.60, 1.45
NAVE_H, RISE = 0.98, 0.55
OVERHANG, ROOF_T = 0.16, 0.12

DOOR_W, DOOR_H, DOOR_DEPTH = 0.42, 0.72, 0.15

WIN_W, WIN_H, WIN_DEPTH = 0.20, 0.40, 0.11
FRONT_WIN_Z = 0.84
SIDE_WIN_Z = 0.62

TOWER_W, TOWER_D = 0.55, 0.55
TOWER_X = -(NAVE_W * 0.5 + TOWER_W * 0.5 - 0.05)
TOWER_Y = -NAVE_D * 0.5 + TOWER_D * 0.5 - 0.04
TOWER_STACK = 0.40                    # tower body rises this far above the nave ridge
TOWER_ROOF_H = 0.30


def _arch_cut(target, cx, cy, w, z_top, depth, z_bottom=0.0):
    """Rectangle from z_bottom to the springline, half-cylinder above it --
    see bld_house for why these are two SEPARATE booleans and not one joined
    cutter. z_bottom=0 is a DOOR (reaches the floor); a nonzero z_bottom is a
    WINDOW with a sill -- get this wrong and a "window" cuts all the way to
    the ground and doubles as a second doorway, which the first pass of this
    file did to the front window before it was caught here.
    """
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


def build(tag="SHRINE", **kw):
    body, trim, roof, accent = scheme(kw.get("scheme", "church_tile"))
    P = []

    walls = box(tag + "_Nave", (0, 0, (NAVE_H + RISE) * 0.5),
               (NAVE_W, NAVE_D, NAVE_H + RISE), body)
    for cutter in gable_cutters("navecut", (0, 0, NAVE_H), NAVE_W, NAVE_D,
                                RISE, overhang=OVERHANG, thickness=ROOF_T):
        boolean(walls, cutter)

    fy = -NAVE_D * 0.5
    front_sill = FRONT_WIN_Z - WIN_H * 0.5
    front_top = FRONT_WIN_Z + WIN_H * 0.5
    _arch_cut(walls, 0.0, fy + DOOR_DEPTH * 0.5, DOOR_W, DOOR_H, DOOR_DEPTH * 2.0)
    _arch_cut(walls, 0.0, fy + WIN_DEPTH * 0.5, WIN_W, front_top, WIN_DEPTH * 2.0,
             z_bottom=front_sill)
    # Side windows, one per long wall -- the row the reference repeats along
    # its whole length, cut down to one each because a building this small is
    # drawn a handful of times, not close enough to count a second.
    for sx in (-1, 1):
        boolean(walls, box("sidewin_%d" % sx,
                           (sx * (NAVE_W * 0.5 - WIN_DEPTH * 0.5), 0.0, SIDE_WIN_Z),
                           (WIN_DEPTH * 2.0, WIN_W, WIN_H), None, rot=None))
    P.append(walls)

    # The door's dark fill and the two arch windows' blue glazing. Front
    # window height matches the taller cut above (springline measured off
    # FRONT_WIN_Z, not off WIN_H alone).
    P.extend(_arch_fill(tag + "_DoorDark", 0.0, fy + DOOR_DEPTH, DOOR_W, DOOR_H,
                        M["hollow"]))
    P.extend(_arch_fill(tag + "_FrontGlass", 0.0, fy + WIN_DEPTH, WIN_W, front_top,
                        M["tile_blue"], z_bottom=front_sill))
    for sx in (-1, 1):
        # Side windows are rectangular cuts (see sidewin_ above, a box not an
        # arch -- the long wall is thin on triangle budget already from the
        # tower and a second arch cutter per side was not worth the cost) but
        # still glazed the same hue, so they read as the same window family.
        P.append(box("%s_SideGlass%d" % (tag, sx),
                     (sx * (NAVE_W * 0.5 - 0.005), 0.0, SIDE_WIN_Z),
                     (0.05, WIN_W - 0.05, WIN_H - 0.05), M["tile_blue"]))
        P.append(box("%s_SideDark%d" % (tag, sx),
                     (sx * (NAVE_W * 0.5 - WIN_DEPTH), 0.0, SIDE_WIN_Z),
                     (0.04, WIN_W, WIN_H), M["hollow"]))

    # Door jambs -- timber against adobe, the hue break the palette needs.
    r = DOOR_W * 0.5
    spring = DOOR_H - r
    ty = fy - 0.018
    for sx in (-1, 1):
        P.append(box("%s_Jamb%s" % (tag, "L" if sx < 0 else "R"),
                     (sx * (r + 0.035), ty, spring * 0.5),
                     (0.07, 0.055, spring), trim))

    roof_parts = gable_roof(tag + "_Roof", (0, 0, NAVE_H), NAVE_W, NAVE_D, RISE,
                            roof, overhang=OVERHANG, thickness=ROOF_T)
    P.extend(roof_parts)
    P.append(box(tag + "_Ridge", (0, 0, NAVE_H + RISE),
                 (0.10, NAVE_D + OVERHANG * 2.0 + 0.06, 0.10), M["wood_dark"]))

    # The bell tower. A straight box from the GROUND to ridge+STACK (same
    # pierce-through trick bld_house uses for a chimney) so it always cuts the
    # sloped roof cleanly wherever the slope sits above it, then a 4-sided
    # `cone` for the pyramid cap -- `cone` takes no rotation and needs none
    # here, the tower is upright.
    tower_top = NAVE_H + RISE + TOWER_STACK
    tower = box(tag + "_Tower", (TOWER_X, TOWER_Y, tower_top * 0.5),
               (TOWER_W, TOWER_D, tower_top), body)
    # One small arch slit, front-facing, so the tower reads as a belfry and
    # not a blank chimney -- the one window this asset spends on the tower.
    # Sill at TOWER_SLIT_Z0, well above the nave ridge, so it reads as a
    # belfry opening and not a second door punched through the tower base.
    TOWER_SLIT_Z0 = NAVE_H + RISE * 0.35
    _arch_cut(tower, TOWER_X, TOWER_Y - TOWER_D * 0.5 + 0.10, 0.16,
             TOWER_SLIT_Z0 + 0.30, 0.24, z_bottom=TOWER_SLIT_Z0)
    P.append(tower)
    P.extend(_arch_fill(tag + "_TowerDark", TOWER_X, TOWER_Y - TOWER_D * 0.5 + 0.02,
                        0.16, TOWER_SLIT_Z0 + 0.30, M["hollow"], z_bottom=TOWER_SLIT_Z0))

    P.append(box(tag + "_TowerBand", (TOWER_X, TOWER_Y, tower_top + 0.015),
                 (TOWER_W + 0.05, TOWER_D + 0.05, 0.03), trim))
    P.append(cone(tag + "_TowerRoof", (TOWER_X, TOWER_Y, tower_top + TOWER_ROOF_H * 0.5),
                  TOWER_W * 0.62, 0.0, TOWER_ROOF_H, roof, verts=4))

    # The cross -- two thin slabs, proud of the roof tip. Nothing about a
    # bell tower silhouette says "church" as unambiguously as this does; it
    # is the two triangles of budget best spent in the whole asset.
    # 0.08, not flush with the apex: the cone's tip is a single POINT, so the
    # cross base needs to sit INSIDE it by a couple of centimetres or the two
    # meet at a zero-area seam that reads as a gap in a raking light.
    cross_z = tower_top + TOWER_ROOF_H + 0.08
    P.append(box(tag + "_CrossV", (TOWER_X, TOWER_Y, cross_z),
                 (0.025, 0.025, 0.20), trim))
    P.append(box(tag + "_CrossH", (TOWER_X, TOWER_Y, cross_z + 0.035),
                 (0.13, 0.025, 0.025), trim))

    # HERO carries the visible bevel: the nave walls, the roof slabs and the
    # tower -- the three masses that make the silhouette. Trim, glazing and
    # the cross are smooth-shaded only.
    hero = [walls, tower] + roof_parts
    plain = [p for p in P if p not in hero]
    soften_all(hero, width=0.032, segments=2)
    soften_all(plain, width=0.0)
    return P
