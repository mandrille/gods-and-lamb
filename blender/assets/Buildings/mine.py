"""BUILDING.works.mine - a rock outcrop with a timbered tunnel and a hut.

Second of the `works` family (see `lumber_camp` for why the family exists).

The reference is a rounded dark boulder with a wood-framed tunnel punched
through it and a small adobe hut built against the side. That two-mass split
survives here almost unchanged because it is already the simplest possible
read: one dark rounded mass says "rock", one square mass with a coloured door
says "someone works here", and the timber frame between them is the only
thing that has to be modelled rather than implied by colour.

Sized against the follower (0.855 m) and the batch's 2.2 x 2.0 target: the
first pass measured 1.51 x 1.03, smaller than the hut, because the rock and
the hut were both scaled down together with nothing in the file anchored to
the villager who has to fit through the tunnel. The opening is now ~1.1 m
tall -- walkable -- rather than 0.46 m, which was barely half a follower.

The rock is a SINGLE box with an unusually wide bevel rather than several
blended blobs -- soften_all clamps width to a quarter of the smallest
dimension, so one box asked for a generous width comes back looking like a
dressed boulder for the cost of one part's edges, not several.

Fronts -Y: the tunnel mouth and the hut door both open toward the viewer.
"""
import math
import os

from kit import M, box, cyl, boolean, scheme, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="building",
    family="works",
    variant="mine",
    category=CATEGORY,
    # MEASURED. The rock's own wide bevel eats into its declared box size less
    # than the hut's roof reaches past ITS wall, so the two ends of the
    # asset do not scale the same way the arithmetic suggests.
    footprint=(2.13, 2.09),
    anchor="floor",
    slots=(),
)

ROCK_CX = -0.55
RW, RD, RH = 1.35, 1.46, 1.05

TUN_W, TUN_H = 0.55, 1.10       # ~1.1 m so a 0.855 m follower walks in clear
TUN_DEPTH = 0.42
JAMB = 0.09

HUT_CX = 0.50
HW, HD, HH = 0.80, 0.72, 0.62
HROOF_RISE = 0.26
HROOF_T = 0.10
HROOF_OVER = 0.14

DOOR_W, DOOR_H = 0.46, 0.75
DOOR_DEPTH = 0.15

ORE = ((-0.16, -0.95, 0.085, 0.15), (0.03, -1.02, 0.090, 0.13),
      (-0.03, -0.85, 0.085, 0.16))


def build(tag="MINE", **kw):
    body, trim, roof, accent = scheme(kw.get("scheme", "mine_rock"))
    hero, plain = [], []

    # The rock. Cut BEFORE the wide bevel -- boolean on a bevelled face tears
    # the cut edge, which is gotcha #1 in every builder in this tree.
    # The rock stands BACK (+0.22 in Y) as a backdrop and the timbered mouth
    # stands forward of it: the first pass put the largest mass in front and
    # squeezed the dark entrance -- the thing the reference leads with --
    # into a slot (review).
    ROCK_Y = 0.22
    rock = box(tag + "_Rock", (ROCK_CX, ROCK_Y, RH * 0.5), (RW, RD, RH), body)
    boolean(rock, box("tun_cut",
                      (ROCK_CX, ROCK_Y - RD * 0.5 + TUN_DEPTH * 0.5, TUN_H * 0.5),
                      (TUN_W, TUN_DEPTH * 2.0, TUN_H), None))
    hero.append(rock)

    plain.append(box(tag + "_TunDark",
                 (ROCK_CX, ROCK_Y - RD * 0.5 + TUN_DEPTH, TUN_H * 0.5),
                 (TUN_W, 0.05, TUN_H), M["hollow"]))
    # A dark throat from the frame back to the rock, so the mouth reads as a
    # tunnel and not a doorway painted on the frame.
    plain.append(box(tag + "_Throat", (ROCK_CX, ROCK_Y - RD * 0.5 - 0.10, TUN_H * 0.5),
                 (TUN_W, 0.22, TUN_H), M["hollow"]))

    # Timber frame, 25 cm proud of the rock face -- the hue break that keeps a
    # wooden frame from reading as one more grey surface next to the stone.
    fy = ROCK_Y - RD * 0.5 - 0.25
    for sx in (-1, 1):
        plain.append(box("%s_Jamb%s" % (tag, "L" if sx < 0 else "R"),
                     (ROCK_CX + sx * (TUN_W * 0.5 + JAMB * 0.5), fy,
                      (TUN_H + JAMB) * 0.5),
                     (JAMB, 0.12, TUN_H + JAMB), trim))
    plain.append(box(tag + "_Lintel", (ROCK_CX, fy, TUN_H + JAMB * 0.5),
                 (TUN_W + JAMB * 2.0, 0.12, JAMB), trim))
    # The accent on the lintel too: rock + frame + ore was three dark
    # neutrals with the one red spent on the hut's curtain (review).
    plain.append(box(tag + "_LintelMark", (ROCK_CX, fy - 0.065, TUN_H + JAMB * 0.5),
                 (TUN_W * 0.6, 0.012, JAMB * 0.6), accent))

    # Ore, spilled in front of the tunnel mouth -- iron_dark rather than
    # another stone, or it vanishes against the rock it just came out of.
    # Lifted above its own half-height: a TILTED box's lowest point is a
    # corner, not the face centre the arithmetic assumes.
    for i, (ox, oy, s, h) in enumerate(ORE):
        plain.append(box("%s_Ore%d" % (tag, i),
                     (ROCK_CX + ox, oy, h * 0.5 + 0.015),
                     (s, s, h), M["iron_dark"], rot=(4 * (i + 1), -3 * i, 14 * i)))

    # Pick and bucket, leaning by the spill.
    # Centred well above half its own length so the tilt cannot dip the low
    # end below the floor.
    plain.append(cyl(tag + "_PickHandle", (ROCK_CX - 0.33, -0.78, 0.395),
                 0.030, 0.72, M["wood"], axis="Z", verts=6, rot=(0, 12, 6)))
    plain.append(box(tag + "_PickHead", (ROCK_CX - 0.39, -0.775, 0.735),
                 (0.24, 0.05, 0.055), M["iron_dark"], rot=(0, 0, 6)))
    plain.append(cyl(tag + "_Bucket", (ROCK_CX - 0.10, -1.02, 0.13),
                 0.110, 0.22, M["wood"], verts=10))
    plain.append(cyl(tag + "_BucketBand", (ROCK_CX - 0.10, -1.02, 0.17),
                 0.118, 0.034, M["iron"], verts=10))

    # The hut, built against the rock's east flank. Its own eaves and roof so
    # it never has to agree with the rock's bevel.
    hwalls = box(tag + "_HutWalls", (HUT_CX, 0, HH * 0.5), (HW, HD, HH), body)
    boolean(hwalls, box("hdoor_cut",
                        (HUT_CX, -HD * 0.5 + DOOR_DEPTH * 0.5, DOOR_H * 0.5),
                        (DOOR_W, DOOR_DEPTH * 2.0, DOOR_H), None))
    hero.append(hwalls)

    # The cloth_red door: a hung curtain, not a hollow recess -- the batch
    # calls for a COLOURED door here specifically, so accent hue does the
    # work a dark hole would otherwise do for a wooden one.
    # Centred at just over half its own height -- at DOOR_H * 0.46 exactly
    # (half of a "DOOR_H - 0.04" tall panel) the floor sat at -0.010.
    plain.append(box(tag + "_Curtain",
                 (HUT_CX, -HD * 0.5 + DOOR_DEPTH * 0.7, DOOR_H * 0.5 - 0.015),
                 (DOOR_W - 0.04, 0.03, DOOR_H - 0.04), accent))
    plain.append(box(tag + "_DoorDark",
                 (HUT_CX, -HD * 0.5 + DOOR_DEPTH, DOOR_H * 0.5),
                 (DOOR_W, 0.035, DOOR_H), M["hollow"]))

    # One shed slope, not a full gable -- the hut is a lean-to against the
    # rock, and a single slope reads as attached where a ridge would not.
    slope_run = HW * 0.5 + HROOF_OVER
    pitch = math.degrees(math.atan2(HROOF_RISE, slope_run))
    slope_len = math.hypot(slope_run, HROOF_RISE)
    hero.append(box(tag + "_HutRoof",
                (HUT_CX + slope_run * 0.5 - HROOF_OVER, 0, HH + HROOF_RISE * 0.5),
                (slope_len, HD + HROOF_OVER * 2.0, HROOF_T), roof,
                rot=(0.0, -pitch, 0.0)))

    # 0.06, not 0.18: an 18 cm bevel on a 2 m block was a smooth grey
    # capsule that read as a beanbag (review).
    soften_all(hero, width=0.06, segments=2)
    soften_all(plain, width=0.0)
    return hero + plain
