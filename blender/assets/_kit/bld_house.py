"""Shared builder for the `house` family -- hut and cottage are the same
building at two sizes, styled after `refs/buildings/Clay_cottage_house_architectural`:
a chunky terracotta block wall, a plank-toned gable roof, an ARCHED door (not
the rectangular cut the older hut/cottage used), one small punched window
either side of it, a stub chimney, and two props at the doorstep -- a flower
pot and a barrel. That is the five details that survive at 15 px: door,
window, roof, and the one or two props that say "lived in" without spending
triangles on anything smaller than 2 cm.

Two variants (`house_terracotta`/`house_plaster` for hut, `cottage_red`/
`cottage_blue` for cottage) are cheap because they are all colour: this one
file owns the shape, `kit.scheme()` owns the palette, and a variant file is
the ASSET dict plus one call.

Fronts -Y, like everything floor-standing. The wall is built TALL and cut
back to the roof line so it is the pentagon a gabled building actually is --
stopping at the eaves leaves the gable ends open and you see through the
building.
"""
from kit import M, box, cyl, boolean, scheme, gable_roof, gable_cutters, soften_all

# ---------------------------------------------------------------- size table
# W, D: the wall box in plan. H: eaves height. RISE: ridge above the eaves.
# ARCH_R is always DOOR_W * 0.5 -- the door cut is a rectangle up to the
# springline and a half-cylinder above it, and the two have to share a radius
# or the arch has a step in it.
SIZES = {
    "hut": dict(
        W=1.30, D=1.12, H=0.86, RISE=0.52, OVERHANG=0.16, ROOF_T=0.12,
        DOOR_W=0.42, DOOR_H=0.72, DOOR_DEPTH=0.15,
        WIN_W=0.22, WIN_H=0.20, WIN_Z=0.52, WIN_X=0.40, WIN_DEPTH=0.11,
        UPPER_WIN=False,
        # CHIM_STACK is height ABOVE the ridge; the cylinder is built from the
        # GROUND to ridge+STACK so it always pierces the sloped roof cleanly
        # regardless of exactly where the slope sits above CHIM_X/CHIM_Y --
        # the alternative (deriving the slope height at that x) is exactly the
        # arithmetic that put a wall through its own roof once already.
        CHIM_R=0.075, CHIM_STACK=0.20, CHIM_X=-0.34, CHIM_Y=0.30,
        POST=0.10,
    ),
    "cottage": dict(
        W=1.70, D=1.46, H=1.06, RISE=0.62, OVERHANG=0.19, ROOF_T=0.13,
        DOOR_W=0.46, DOOR_H=0.78, DOOR_DEPTH=0.16,
        WIN_W=0.28, WIN_H=0.26, WIN_Z=0.58, WIN_X=0.50, WIN_DEPTH=0.12,
        UPPER_WIN=True, UWIN_W=0.22, UWIN_H=0.22, UWIN_Z=0.94,
        CHIM_R=0.095, CHIM_STACK=0.22, CHIM_X=-0.42, CHIM_Y=0.38,
        POST=0.11,
    ),
}

PANE_INSET = 0.055


def _arch_opening(tag, cx, y_wall, w, h_total, mat_fill):
    """Cut an arched doorway/window and floor it dark. Returns (cut boxes are
    applied immediately; this only builds the dark fill parts).

    The cut is TWO shapes, not one joined cutter: a rectangle from the floor
    to the springline and a half-cylinder above it. `boolean()` is called on
    each separately -- they overlap heavily where the cylinder's lower half
    passes back through the rectangle, and join()-ing overlapping cutters
    produces a self-intersecting solid that EXACT resolves by deleting the
    whole target. Two sequential DIFFERENCE ops on the same wall have no such
    problem; nothing about boolean() requires its cutters to be disjoint from
    each other, only from earlier applied cuts.
    """
    r = w * 0.5
    spring = h_total - r
    fill = []
    fill.append(box("%s_Rect" % tag, (cx, y_wall, spring * 0.5), (w, 0.04, spring),
                    mat_fill))
    fill.append(cyl("%s_Arch" % tag, (cx, y_wall, spring), r, 0.04, mat_fill,
                    axis="Y", verts=12))
    return fill


def _cut_arch(target, cx, y_center, depth, w, h_total):
    r = w * 0.5
    spring = h_total - r
    boolean(target, box("archcut_rect", (cx, y_center, spring * 0.5),
                        (w, depth, spring), None))
    # verts=12, not the cyl() default of 20 -- this is a BOOLEAN CUTTER, so
    # every one of its facets becomes new edges on the wall, and the wall
    # then carries a bevel on top of that. 12 is still a smooth arc at this
    # scale; 20 nearly doubled the wall's triangle count for a curve nobody
    # can see the difference on at the play camera.
    boolean(target, cyl("archcut_top", (cx, y_center, spring), r, depth, None,
                        axis="Y", verts=12))


def build(tag, scheme_key, size="hut", **kw):
    S = SIZES[size]
    body, trim, roof, accent = scheme(scheme_key)
    W, D, H, RISE = S["W"], S["D"], S["H"], S["RISE"]
    OVERHANG, ROOF_T = S["OVERHANG"], S["ROOF_T"]
    DOOR_W, DOOR_H, DOOR_DEPTH = S["DOOR_W"], S["DOOR_H"], S["DOOR_DEPTH"]
    WIN_W, WIN_H, WIN_Z, WIN_X, WIN_DEPTH = (S["WIN_W"], S["WIN_H"], S["WIN_Z"],
                                             S["WIN_X"], S["WIN_DEPTH"])
    P = []

    walls = box(tag + "_Walls", (0, 0, (H + RISE) * 0.5), (W, D, H + RISE), body)
    for cutter in gable_cutters("wallcut", (0, 0, H), W, D, RISE,
                                overhang=OVERHANG, thickness=ROOF_T):
        boolean(walls, cutter)

    # The arched doorway. Cut through generously (2x wall thickness) so the
    # far face is unambiguously open, not a sliver EXACT has to resolve.
    fy = -D * 0.5
    _cut_arch(walls, 0.0, fy + DOOR_DEPTH * 0.5, DOOR_DEPTH * 2.0, DOOR_W, DOOR_H)

    for sx in (-1, 1):
        boolean(walls, box("wincut_%d" % sx,
                           (sx * WIN_X, fy + WIN_DEPTH * 0.5, WIN_Z),
                           (WIN_W, WIN_DEPTH * 2.0, WIN_H), None))
    if S.get("UPPER_WIN"):
        boolean(walls, box("wincut_up",
                           (0, fy + WIN_DEPTH * 0.5, S["UWIN_Z"]),
                           (S["UWIN_W"], WIN_DEPTH * 2.0, S["UWIN_H"]), None))
    P.append(walls)

    P.extend(_arch_opening(tag + "_DoorDark", 0.0, fy + DOOR_DEPTH,
                           DOOR_W, DOOR_H, M["hollow"]))
    # Door jambs in the ACCENT: on the plaster colourway the accent was
    # spent on a 5 cm flower and body/roof/trim were three warm neutrals
    # (review). Two jambs put the scheme's one hue where the eye lands.
    _jr = DOOR_W * 0.5
    _spring = DOOR_H - _jr
    for _sx in (-1, 1):
        P.append(box("%s_Jamb%s" % (tag, "L" if _sx < 0 else "R"),
                     (_sx * (_jr + 0.035), fy - 0.016, _spring * 0.5),
                     (0.06, 0.045, _spring), accent))
    for sx, side in ((-1, "L"), (1, "R")):
        P.append(box("%s_WinDark%s" % (tag, side),
                     (sx * WIN_X, fy + WIN_DEPTH, WIN_Z),
                     (WIN_W, 0.04, WIN_H), M["hollow"]))
        # Proud of the wall by 1 cm, smaller than the hole by PANE_INSET so a
        # dark border survives -- sunk or exactly hole-sized it disappears
        # into its own shadow at the play camera.
        P.append(box("%s_Pane%s" % (tag, side),
                     (sx * WIN_X, fy - 0.005, WIN_Z),
                     (WIN_W - PANE_INSET, 0.05, WIN_H - PANE_INSET),
                     M["warmglow"]))
    if S.get("UPPER_WIN"):
        P.append(box(tag + "_WinDarkUp", (0, fy + WIN_DEPTH, S["UWIN_Z"]),
                     (S["UWIN_W"], 0.04, S["UWIN_H"]), M["hollow"]))
        P.append(box(tag + "_PaneUp", (0, fy - 0.005, S["UWIN_Z"]),
                     (S["UWIN_W"] - PANE_INSET, 0.05, S["UWIN_H"] - PANE_INSET),
                     M["warmglow"]))

    # Jambs only, up to the springline -- timber against the wall body is the
    # hue break the palette needs, since two neutrals of different brightness
    # read as one flat face under a single key light. No matching lintel: a
    # disc wide enough to trace the arch also covers the LOWER half of its own
    # circle, which sits in front of the open doorway below the springline and
    # reads as a slab blocking the door. The cut's own rounded silhouette
    # carries the curve; soften_all gives it the edge highlight.
    r = DOOR_W * 0.5
    spring = DOOR_H - r
    ty = fy - 0.018
    for sx in (-1, 1):
        P.append(box("%s_Jamb%s" % (tag, "L" if sx < 0 else "R"),
                     (sx * (r + 0.035), ty, spring * 0.5),
                     (0.07, 0.055, spring), trim))

    # Corner posts, eaves height only -- above that is gable, not frame.
    POST = S["POST"]
    for sx in (-1, 1):
        for sy in (-1, 1):
            P.append(box("%s_Post%s%s" % (tag, "L" if sx < 0 else "R",
                                          "F" if sy < 0 else "B"),
                         (sx * (W * 0.5 - POST * 0.4), sy * (D * 0.5 - POST * 0.4),
                          H * 0.5), (POST, POST, H), trim))

    roof_parts = gable_roof(tag + "_Roof", (0, 0, H), W, D, RISE, roof,
                            overhang=OVERHANG, thickness=ROOF_T)
    P.extend(roof_parts)
    P.append(box(tag + "_Ridge", (0, 0, H + RISE), (0.10, D + OVERHANG * 2.0 + 0.06, 0.10),
                 M["wood_dark"]))

    # The chimney runs from the GROUND to ridge+STACK, not from the roof
    # surface upward: the roof height at (CHIM_X, CHIM_Y) is somewhere between
    # the eaves and the ridge depending on x, and a column spanning the whole
    # range pierces the slope cleanly without deriving that height. It is a
    # plain cylinder, not axis-aligned against the sloped slab, so no face
    # plane is shared and there is nothing to z-fight.
    # 8-gon, not the cyl() default of 20 -- a stub this small (radius
    # 7.5-9.5 cm) reads as round at any vertex count once soften_all rounds
    # its rim, so the extra sides bought nothing but triangles.
    CHIM_R, CHIM_STACK = S["CHIM_R"], S["CHIM_STACK"]
    CHIM_X, CHIM_Y = S["CHIM_X"], S["CHIM_Y"]
    chim_top = H + RISE + CHIM_STACK
    chimney = cyl(tag + "_Chimney", (CHIM_X, CHIM_Y, chim_top * 0.5),
                  CHIM_R, chim_top, M["stone"], verts=8)
    P.append(chimney)
    P.append(cyl(tag + "_ChimneyCap", (CHIM_X, CHIM_Y, chim_top - 0.01),
                 CHIM_R + 0.022, 0.05, M["stone_dark"], verts=8))

    # Doorstep props: one flower pot, one barrel, either side of the arch.
    # Both sit close against the wall so they cannot widen the footprint past
    # what the roof overhang already reserves. Low vertex counts throughout --
    # these are 2 of the "five details that survive at 15 px", not showpieces.
    potx, poty = DOOR_W * 0.5 + 0.16, fy - 0.10
    P.append(cyl(tag + "_Pot", (potx, poty, 0.055), 0.055, 0.11, M["terracotta"],
                 verts=8))
    P.append(box(tag + "_Flower", (potx, poty, 0.13), (0.05, 0.05, 0.08), accent))

    barx, bary = -DOOR_W * 0.5 - 0.17, fy - 0.11
    P.append(cyl(tag + "_Barrel", (barx, bary, 0.085), 0.075, 0.17, M["wood"],
                 verts=8))
    # ONE band, not two -- a single dark ring at the belly is enough to read
    # as coopered staves rather than a stool; a second band bought nothing at
    # this size and cost another cylinder's worth of bevel.
    P.append(cyl(tag + "_BarrelBand", (barx, bary, 0.085), 0.078, 0.025,
                 M["wood_dark"], verts=8))

    # HERO is the walls and the two roof slabs -- the masses that carry the
    # silhouette, which is where the visible bevel belongs. Everything else
    # (posts, jambs, chimney, doorstep props, the dark window/door fills) is
    # smooth-shaded only: at the play camera a rounded post edge is nothing,
    # and this builder now carries far more discrete parts than the old
    # single-scheme hut did, so an indiscriminate bevel is what blew the cap
    # first. Same split villager.py uses for the same reason.
    hero = [walls] + roof_parts
    plain = [p for p in P if p not in hero]
    soften_all(hero, width=0.040, segments=2)
    soften_all(plain, width=0.0)
    return P
