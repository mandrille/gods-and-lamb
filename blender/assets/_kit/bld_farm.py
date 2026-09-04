"""Shared builder for BUILDING.farm.* - a low barn beside a fenced crop plot.

Two buildings share this because they ARE the same building: a barn and a
plot of ripe crop, repainted. `farm.py` and `farm_b.py` are ~25-line callers
(ASSET dict + one call), same relationship as `bld_hut`/`hut.py` for house.

The barn is single-storey and wide, not the gambrel two-storey the reference
photo shows -- at play-camera size a hayloft window and a second storey are
both invisible, and a barn this short next to a two-storey cottage is what
actually reads as "farm building" rather than "small house". The five details
that survive: the low wide roof, one door, one hayloft vent, a hay bale, and
the crop plot's own colour.

The crop plot is NOT the Nature/crop_row asset (different cls, and a family's
geometry is not shared across category folders) -- it is three raised beds,
soil topped with a crop_ripe cap, which reads as tidy furrows at distance for
a fraction of crop_row's fourteen scattered stalks. This building's budget
goes to the barn roof, not the garden.

Barn and plot sit side by side along X, both fronting -Y like everything
floor-standing, with a footpath gap between them. The whole assembly is
centred on x=0 so the declared footprint brackets it symmetrically.
"""
from kit import M, box, boolean, scheme, gable_roof, gable_cutters, soften_all

# Sized against the follower (0.855 m) and the batch's 2.5 x 2.5 target: the
# first pass measured 2.35 x 1.19, only half the depth it needed to be,
# because the plot was as shallow as the barn instead of making up the rest
# of the tile the way the fix-round brief asks for. The barn stays modest
# (~1.8 x 1.4, still bigger than the hut) and the plot goes DEEP instead of
# wide -- three long rows reaching well past the barn's own footprint -- so
# the combined assembly reaches 2.5 m without the barn itself ballooning
# past a barn's proportions.

# ---- barn
BARN_CX = -0.45
BW, BD = 1.20, 1.10            # wall box in plan
BH = 0.77                      # eaves -- low and wide, a barn not a house
BRISE = 0.54
BOVER = 0.15
BROOF_T = 0.15

BDOOR_W, BDOOR_H = 0.66, 0.95   # ~1.0 m so a follower walks in clear
BDOOR_DEPTH = 0.24
BDOOR_X = -0.22                 # off-centre, the big barn door the ref shows

VENT = 0.26                    # hayloft vent, square, high in the gable end
VENT_Z = BH + BRISE * 0.42
VENT_X = 0.32
VENT_DEPTH = 0.19

BALE_X, BALE_Y = 0.42, -0.83

# ---- crop plot
PLOT_CX = 0.865
PLOT_W, PLOT_D = 0.55, 2.30     # interior, inside the fence line -- deep,
                                 # not wide, so the plot carries the Y reach
                                 # the barn alone cannot
POST, POST_H = 0.06, 0.34
ROW_W, ROW_D = 0.14, 1.90
ROW_X = (-0.16, 0.0, 0.16)      # three beds, centred, off the plot's own axis
SOIL_H = 0.10
CAP_H = 0.14


def _barn(tag, body, trim, roof):
    """(hero, plain) -- hero carries the silhouette, plain is everything else.

    Two-tier softening, same split the house style guide asks for: the walls
    and roof are the 2-3 masses that read at play distance and earn a real
    bevel, everything bolted onto them (posts, dark recesses, the bale) is
    smooth-shaded flat. The first cut of this file bevelled all thirteen
    parts at segments=2 and came back 3034 tris against a 2500 cap -- a barn
    this small cannot afford a rounded corner post AND a rounded bale.
    """
    hero, plain = [], []
    cx = BARN_CX

    walls = box(tag + "_Walls", (cx, 0, (BH + BRISE) * 0.5),
                (BW, BD, BH + BRISE), body)
    for cutter in gable_cutters("bwallcut", (cx, 0, BH), BW, BD, BRISE,
                                overhang=BOVER, thickness=BROOF_T):
        boolean(walls, cutter)
    boolean(walls, box("bdoor_cut",
                       (cx + BDOOR_X, -BD * 0.5 + BDOOR_DEPTH * 0.5,
                        BDOOR_H * 0.5),
                       (BDOOR_W, BDOOR_DEPTH * 2.0, BDOOR_H), None))
    boolean(walls, box("bvent_cut",
                       (cx + VENT_X, -BD * 0.5 + VENT_DEPTH * 0.5, VENT_Z),
                       (VENT, VENT_DEPTH * 2.0, VENT), None))
    hero.append(walls)

    plain.append(box(tag + "_DoorDark",
                 (cx + BDOOR_X, -BD * 0.5 + BDOOR_DEPTH, BDOOR_H * 0.5),
                 (BDOOR_W, 0.06, BDOOR_H), M["hollow"]))
    plain.append(box(tag + "_VentDark",
                 (cx + VENT_X, -BD * 0.5 + VENT_DEPTH, VENT_Z),
                 (VENT, 0.06, VENT), M["hollow"]))

    for sx in (-1, 1):
        for sy in (-1, 1):
            plain.append(box("%s_Post%s%s" % (tag, "L" if sx < 0 else "R",
                                          "F" if sy < 0 else "B"),
                         (cx + sx * (BW * 0.5 - 0.06),
                          sy * (BD * 0.5 - 0.06), BH * 0.5),
                         (0.14, 0.14, BH), trim))

    hero.extend(gable_roof(tag + "_Roof", (cx, 0, BH), BW, BD, BRISE, roof,
                        overhang=BOVER, thickness=BROOF_T))
    plain.append(box(tag + "_Ridge", (cx, 0, BH + BRISE),
                 (0.12, BD + 0.45, 0.12), M["wood_dark"]))

    # The hay bale. A single blob in the accent hue by the door -- the one
    # thing in the picture that says "farm" rather than "small red house".
    plain.append(box(tag + "_Bale", (cx + BALE_X, BALE_Y, 0.185),
                 (0.31, 0.31, 0.31), M["crop_ripe"], rot=(4.0, -3.0, 18.0)))
    return hero, plain


def _plot(tag, accent):
    """All plain -- a fence and three garden beds carry no silhouette."""
    P = []
    cx = PLOT_CX
    hw, hd = PLOT_W * 0.5, PLOT_D * 0.5

    # Corner posts plus one mid-post per long side, and a SINGLE rail per side
    # -- a bar spanning the whole side would be one box centred on that side's
    # midpoint, which is fine (it does not pass through another side's rail),
    # but two full-length rails crossing at a shared corner post never share a
    # centreline, so there is no doubled-spoke risk here the way a round frame
    # has it.
    for sx in (-1, 1):
        for sy in (-1, 1):
            P.append(box("%s_Post%d%d" % (tag, sx, sy),
                         (cx + sx * hw, sy * hd, POST_H * 0.5),
                         (POST, POST, POST_H), M["wood_dark"]))
    for sy in (-1, 1):
        P.append(box("%s_RailY%d" % (tag, sy),
                     (cx, sy * hd, POST_H * 0.62),
                     (PLOT_W + POST, 0.05, 0.07), M["wood"]))

    for i, rx in enumerate(ROW_X):
        P.append(box("%s_Soil%d" % (tag, i), (cx + rx, 0, SOIL_H * 0.5),
                     (ROW_W, ROW_D, SOIL_H), M["soil"]))
        # Five short tufts with gaps per row -- one continuous 1.9 m cap at
        # the fence-rail height read as a slatted bench (review).
        for t in range(5):
            ty = (t - 2) * (ROW_D * 0.19)
            P.append(box("%s_Crop%d_%d" % (tag, i, t),
                         (cx + rx, ty, SOIL_H + CAP_H * 0.55),
                         (ROW_W - 0.02, ROW_D * 0.11, CAP_H * 1.3), accent))
    return P


def build(tag, scheme_key):
    """(tag, scheme_key) -> parts. Called by farm.py / farm_b.py, one line each."""
    body, trim, roof, accent = scheme(scheme_key)
    hero, plain = _barn(tag, body, trim, roof)
    plain.extend(_plot(tag, accent))
    # 3.4 cm on the two masses that carry the silhouette; everything else
    # smooth-shaded flat, not bevelled -- a fence post and a garden bed have
    # no edge anyone sees at play distance and a bevel on thirteen small parts
    # is pure cost. See _barn's docstring for the number this replaced.
    soften_all(hero, width=0.053, segments=2)
    soften_all(plain, width=0.0)
    return hero + plain
