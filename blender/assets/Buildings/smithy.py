"""BUILDING.works.smithy - a rounded adobe kiln with a forge, an anvil, a rack.

Third of the `works` family (see `lumber_camp`). The registered colourway
(`smithy_adobe`: body=adobe, roof=adobe) paints the roof the SAME hue as the
body, which is why this is built as the reference actually shows it: one
rounded clay mass, not a walled building with a separate pitched roof on top.
A second box in the same material would share a seam with nothing to see it
by -- the hue-not-value rule cannot separate two surfaces from the SAME
material, so the honest build is not to draw the seam at all.

Sized against the follower (0.855 m) and the batch's own target (2.0 x 1.8):
the first pass measured 0.82 x 0.93, smaller than the hut, because every
dimension was chosen relative to the OTHER dimensions in the file rather than
to the villager standing next to it. The forge opening is ~1.0 m at its peak
now -- tall enough that the fire reads as a room, not a slot -- and the anvil
stump is 0.45 m, roughly hip-height on a follower.

The arched opening is two cuts, not one curved one: a box for the straight
sides and a horizontal cylinder half-sunk at the top for the round of the
arch. Both are subtracted from the block separately -- they overlap where
they meet, and overlapping cutters may never be `join()`-ed into a single
boolean, only cut one at a time.

Fronts -Y: the forge mouth faces the viewer, the anvil stands in front of it
and the tool rack is on the near side wall where the three-quarter view
catches it.
"""
import os

from kit import M, box, cyl, boolean, scheme, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="building",
    family="works",
    variant="smithy",
    category=CATEGORY,
    # MEASURED. The block's own wide bevel and the anvil standing forward of
    # the forge mouth both reach past the arithmetic box size.
    footprint=(2.01, 1.86),
    anchor="floor",
    slots=(),
)

SW, SD, SH = 1.92, 1.38, 1.15

ARCH_W, ARCH_H = 0.62, 0.70     # straight-sided part of the opening; the
                                 # round top adds ARCH_R more, so the peak
                                 # sits at ~1.0 m -- "walk up to the forge"
ARCH_DEPTH = 0.50
ARCH_R = ARCH_W * 0.5           # the round top's radius

CHIM_W = 0.25
CHIM_H = 0.55
CHIM_X, CHIM_Y = -0.30, 0.27

ANVIL_X, ANVIL_Y = 0.62, -0.95   # clear of the jamb (x = +-0.363), or the
                                  # anvil and the arch frame overlap in the
                                  # front elevation even though neither
                                  # mesh actually touches the other
STUMP_R, STUMP_H = 0.14, 0.45   # hip-height on a 0.855 m follower

RACK_X = SW * 0.5 + 0.02


def build(tag="SMITHY", **kw):
    body, trim, roof, accent = scheme(kw.get("scheme", "smithy_adobe"))
    hero, plain = [], []

    block = box(tag + "_Block", (0, 0, SH * 0.5), (SW, SD, SH), body)
    boolean(block, box("arch_cut",
                       (0, -SD * 0.5 + ARCH_DEPTH * 0.5, ARCH_H * 0.5),
                       (ARCH_W, ARCH_DEPTH * 2.0, ARCH_H), None))
    # The round top of the arch: a cylinder lying along Y, its axis at the
    # straight cut's top edge so the two cuts meet with no step between them.
    boolean(block, cyl("arch_round", (0, -SD * 0.5 + ARCH_DEPTH * 0.5, ARCH_H),
                       ARCH_R, ARCH_DEPTH * 2.0, None, axis="Y", verts=12))
    hero.append(block)

    # The back of the recess only -- a thin plate, not a box filling the
    # whole cut depth. A "backing" as deep as the cavity IS the cavity, and a
    # warmglow slab placed inside a solid box of that depth is occluded by
    # its own floor.
    back_y = -SD * 0.5 + ARCH_DEPTH
    plain.append(box(tag + "_ForgeDark", (0, back_y, ARCH_H * 0.42),
                 (ARCH_W - 0.03, 0.05, ARCH_H * 0.7), M["hollow"]))
    # The fire, well forward of the back wall and proud of the coal bed --
    # sunk flush it falls into its own shadow, the same lesson the cottage's
    # window pane learned.
    plain.append(box(tag + "_Fire", (0, back_y - 0.14, 0.14),
                 (ARCH_W - 0.16, 0.09, 0.20), M["warmglow"]))

    # Stone surround, proud of the adobe face -- the hue break an arch needs
    # against a body of the exact colour its own roof will be.
    fy = -SD * 0.5 - 0.034
    for sx in (-1, 1):
        plain.append(box("%s_Jamb%s" % (tag, "L" if sx < 0 else "R"),
                     (sx * (ARCH_W * 0.5 + 0.053), fy, ARCH_H * 0.5),
                     (0.105, 0.115, ARCH_H), trim))
    # A RING, not a disc: a plain cylinder here would cover the opening it is
    # meant to frame, hiding the fire behind a slab of stone_dark. Cut clean
    # through with a second, unjoined boolean -- the two cutters overlap at
    # the bore, which is exactly why they are not `join()`-ed first.
    arch_top = cyl(tag + "_ArchTop", (0, fy, ARCH_H), ARCH_R + 0.085, 0.115,
                   trim, axis="Y", verts=14)
    boolean(arch_top, cyl("archtop_cut", (0, fy, ARCH_H), ARCH_R + 0.011,
                          0.115 * 3.0, None, axis="Y", verts=14))
    plain.append(arch_top)

    # Chimney, off-centre on the rounded top -- centred would sit exactly on
    # the ridge line a rounded block does not have, and read as a mistake.
    plain.append(box(tag + "_Chimney", (CHIM_X, CHIM_Y, SH + CHIM_H * 0.5),
                 (CHIM_W, CHIM_W, CHIM_H), body))
    plain.append(box(tag + "_ChimCap", (CHIM_X, CHIM_Y, SH + CHIM_H + 0.045),
                 (CHIM_W + 0.09, CHIM_W + 0.09, 0.09), trim))

    # Anvil on its stump, standing forward of the forge mouth.
    plain.append(cyl(tag + "_Stump", (ANVIL_X, ANVIL_Y, STUMP_H * 0.5),
                 STUMP_R, STUMP_H, M["wood"], verts=10))
    plain.append(box(tag + "_AnvilBase", (ANVIL_X, ANVIL_Y, STUMP_H + 0.10),
                 (0.14, 0.21, 0.13), accent))
    plain.append(box(tag + "_AnvilTop", (ANVIL_X, ANVIL_Y - 0.02, STUMP_H + 0.28),
                 (0.14, 0.38, 0.09), accent))

    # Tool rack on the near side wall: a board and two hanging silhouettes,
    # proud of the face so they read as HUNG rather than painted on.
    plain.append(box(tag + "_Rack", (RACK_X, -0.27, 0.80),
                 (0.038, 0.46, 0.086), trim))
    plain.append(box(tag + "_Tool0", (RACK_X + 0.048, -0.42, 0.57),
                 (0.034, 0.034, 0.38), accent))
    plain.append(box(tag + "_Tool1", (RACK_X + 0.048, -0.15, 0.61),
                 (0.034, 0.19, 0.034), accent))

    soften_all(hero, width=0.15, segments=3)
    soften_all(plain, width=0.0)
    return hero + plain
