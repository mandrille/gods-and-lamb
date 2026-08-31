"""Shared geometry for thin, bladed plants.

Lives beside the assets rather than in src/ because it is art, not machinery:
it encodes what a blade of grass IS in this village. `assets/_kit/` is skipped
by registry discovery, which is how a shared helper lives inside the asset
tree.

Everything here returns SHARP parts and softens nothing. The caller owns the
rounding pass, because a builder mixes blades (which want `width=0.0`) with
masses (which want a real radius) and those are two different passes.

Nothing here bevels, and that is the point. A 4 cm blade has no edge anyone can
see at the play camera, and bevelling fourteen of them is how `crop_row` first
came in at 864 triangles against an 800 cap.
"""
import math

from kit import box, cyl


def up(lean_x, lean_y):
    """The world direction a box built with `rot=(lean_x, lean_y, 0)` points.

    kit.box applies an XYZ euler, so its local +Z lands here. Needed because a
    box rotates about its CENTRE: to stack a second segment on the tip of the
    first you have to know where the tip went, and "centre plus half the
    height" is only true for something standing straight up.
    """
    rx = math.radians(lean_x)
    ry = math.radians(lean_y)
    return (math.cos(rx) * math.sin(ry), -math.sin(rx), math.cos(rx) * math.cos(ry))


def sink(sx, sy, lean_x, lean_y):
    """How far the low corner of a leaning box drops below its base point.

    A box rotates about its CENTRE, so putting the centre half a height up the
    lean direction lands the bottom FACE on the base -- but that face is tilted,
    and its downhill corner is under the ground. First pass of `reeds` and
    `tall_grass` both measured a Z minimum of about -9 mm for exactly this, and
    a plant that starts below the tile is a plant that floats the moment the
    tile it stands on is a cliff edge. Lift by the drop and the AABB starts at
    zero.
    """
    rx = math.radians(lean_x)
    ry = math.radians(lean_y)
    return 0.5 * (sx * abs(math.sin(ry)) + sy * abs(math.sin(rx)))


def blade(name, base, mat, height=0.34, width=0.035, lean=(0.0, 0.0), curl=2.2,
          taper=0.80, flat=0.55):
    """One arcing blade: two boxes, the upper leaning `curl` times as far.

    Two segments, not one. A single leaning box is a straw; the second segment
    bending further is what makes a tuft read as grass rather than as a hedgehog
    of sticks, and it costs 12 triangles.

    `flat` squashes the section across local Y, so the blade is a RIBBON rather
    than a square rod. It is free -- same eight vertices -- and it is the whole
    difference between grass and a bundle of dowels.

    The upper segment starts BELOW the tip of the lower one. At the first pass
    the two met exactly and the change of angle opened a visible notch on the
    outside of every bend; overlapping by the blade's own width closes it and
    costs nothing.

    `base` is the point on the ground the blade grows from, so a caller scatters
    by position and never has to solve for a centre.
    """
    lx, ly = lean
    wy = width * flat
    h1 = height * 0.55
    ov = width * 0.9
    h2 = height - h1 + ov
    base = (base[0], base[1], base[2] + sink(width, wy, lx, ly))

    u1 = up(lx, ly)
    lo = box(name + "a",
             (base[0] + u1[0] * h1 * 0.5,
              base[1] + u1[1] * h1 * 0.5,
              base[2] + u1[2] * h1 * 0.5),
             (width, wy, h1), mat, rot=(lx, ly, 0))

    tip = (base[0] + u1[0] * h1, base[1] + u1[1] * h1, base[2] + u1[2] * h1)
    u2 = up(lx * curl, ly * curl)
    d = h2 * 0.5 - ov
    hi = box(name + "b",
             (tip[0] + u2[0] * d, tip[1] + u2[1] * d, tip[2] + u2[2] * d),
             (width * taper, wy * taper, h2), mat,
             rot=(lx * curl, ly * curl, 0))
    return [lo, hi]


def stalk(name, base, mat, height=0.5, width=0.03, lean=(0.0, 0.0)):
    """A single straight stem. One box; the head goes on `tip_of`."""
    u = up(*lean)
    base = (base[0], base[1], base[2] + sink(width, width, *lean))
    return box(name,
               (base[0] + u[0] * height * 0.5,
                base[1] + u[1] * height * 0.5,
                base[2] + u[2] * height * 0.5),
               (width, width, height), mat, rot=(lean[0], lean[1], 0))


def tip_of(base, height, lean=(0.0, 0.0)):
    """Where a `stalk` of this height ends, so a flower head can sit on it."""
    u = up(*lean)
    return (base[0] + u[0] * height,
            base[1] + u[1] * height,
            base[2] + u[2] * height)


def petals(tag, centre, mat, count=5, radius=0.055, size=(0.05, 0.085, 0.026),
           phase=0.0, pitch=0.0):
    """A ring of petals OFFSET radially, never a bar through the middle.

    A part centred on the axis and rotated N times renders as N/2 double-ended
    arms, because each copy already reaches out both ways. Every petal here is
    pushed out to `radius` first and only then turned to face outward.

    `pitch` lifts each petal's outer end. It has to be applied about X BEFORE
    the azimuth is applied about Z -- Blender's XYZ euler does exactly that
    order, so one rotation tuple gives a cupped bloom rather than five flat
    bricks lying on a leaf.
    """
    out = []
    for i in range(count):
        a = math.radians(phase + 360.0 * i / count)
        out.append(box("%s_Petal%d" % (tag, i),
                       (centre[0] + math.sin(a) * radius,
                        centre[1] + math.cos(a) * radius,
                        centre[2]),
                       size, mat, rot=(pitch, 0, -math.degrees(a))))
    return out


def disc(name, centre, r, h, mat, verts=12):
    """A low round plate -- a lily pad, a growth ring, a cut end.

    A 12-gon, not a bevelled box: the box bevel is clamped by the THICKNESS, so
    a 3 cm pad comes back with 7 mm corners and reads as a square. A 12-gon
    costs 44 triangles and is actually round.
    """
    return cyl(name, centre, r, h, mat, verts=verts)
