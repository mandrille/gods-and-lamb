"""BUILDING.well.well - a stone ring well with a timber frame and a bucket.

The ring is genuinely open: the shaft is cut clean through the stone and floored
with water, not faked with a dark disc laid on top. It costs two booleans
and it is worth them -- an open mouth with something dark and saturated at the
bottom is the whole read of a well, and a flat disc on a solid cylinder reads as
a stone table.

The cylinders are 12-sided on purpose. A well at the play camera is a circle
either way, and twelve facets give the coarse cut-block look the rest of the
stone in this village has, for a third of the geometry of a smooth one.
soften_all's 50-degree angle limit leaves those 30-degree side edges alone and
bevels only the rims, which is exactly the budget this wants.

The winch is a cylinder lying along X BETWEEN two posts, not a bar centred on
the origin and rotated -- a bar through the centre draws two arms, and that
particular bug has shipped in the parent project three times.

The roof is `slate`, not `thatch`. Thatch is only a shade off `gold` in this
palette and the shrine already owns gold -- two small pitched roofs of nearly
the same ochre in one village merge at the play camera. Blue-grey over stone
also lets the well share a hue family with the water it holds.

Fronts -Y. The bucket hangs on the -Y side of the winch so it is not hidden
behind the rope from the front.
"""
import os

from kit import M, box, cyl, boolean, gable_roof, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="building",
    family="well",
    variant="well",
    category=CATEGORY,
    # MEASURED. The little roof is what sets the span, and its rotated slabs
    # reach past the eaves line -- the ring itself is only 0.74 across.
    footprint=(1.04, 0.86),
    anchor="floor",
    slots=(),
)

R_OUT, R_IN = 0.37, 0.26
DRUM_Z = 0.28                     # top of the stone body, under the coping
COPE_T = 0.075
RIM_Z = DRUM_Z + COPE_T           # walking surface of the rim

POST, POST_X = 0.075, 0.30
POST_TOP = 1.00

ROOF_W, ROOF_D = 0.80, 0.62
ROOF_RISE, ROOF_OVER, ROOF_T = 0.24, 0.10, 0.09


def build(tag="WELL", **kw):
    P = []

    # Body and coping are separate cylinders with separate cutters. They could
    # not share one: boolean() consumes the cutter it is given, so a second
    # target needs a second cutter object.
    shaft = cyl(tag + "_Shaft", (0, 0, DRUM_Z * 0.5), R_OUT, DRUM_Z,
                M["stone"], verts=12)
    boolean(shaft, cyl("shaft_cut", (0, 0, DRUM_Z * 0.5), R_IN, DRUM_Z * 3.0,
                       None, verts=12))
    P.append(shaft)

    cope = cyl(tag + "_Coping", (0, 0, DRUM_Z + COPE_T * 0.5), R_OUT + 0.035,
               COPE_T, M["stone_dark"], verts=12)
    boolean(cope, cyl("cope_cut", (0, 0, DRUM_Z + COPE_T * 0.5), R_IN,
                      COPE_T * 3.0, None, verts=12))
    P.append(cope)

    # The water. Saturated blue against grey stone is the hue break -- stone and
    # stone_dark are two neutrals of different value and read as ONE object
    # under a single key light, so this is the only thing separating the ring
    # from the shaft.
    #
    # High in the shaft, and the LIGHT blue. The first pass used water_deep at
    # z=0.10 and it was a black dot: from the play camera you look into the well
    # at forty degrees and see almost none of the shaft floor, so anything set
    # low and dark is simply not in the picture.
    P.append(cyl(tag + "_Water", (0, 0, 0.20), R_IN - 0.015, 0.05,
                 M["water"], verts=12))

    for sx, side in ((-1, "L"), (1, "R")):
        P.append(box("%s_Post%s" % (tag, side),
                     (sx * POST_X, 0, RIM_Z + (POST_TOP - RIM_Z) * 0.5),
                     (POST, POST, POST_TOP - RIM_Z), M["wood"]))

    # The winch barrel. Spans between the posts and no further.
    P.append(cyl(tag + "_Winch", (0, 0, 0.86), 0.055, POST_X * 2.0 - POST,
                 M["wood_dark"], axis="X", verts=10))
    P.append(box(tag + "_Beam", (0, 0, POST_TOP + 0.030),
                 (POST_X * 2.0 + POST, 0.085, 0.070), M["wood_dark"]))

    # Rope and bucket, forward of the barrel.
    P.append(box(tag + "_Rope", (0, -0.075, 0.72), (0.022, 0.022, 0.28),
                 M["wood_dark"]))
    P.append(cyl(tag + "_Bucket", (0, -0.075, 0.505), 0.095, 0.17,
                 M["wood"], verts=10))
    P.append(cyl(tag + "_Band", (0, -0.075, 0.545), 0.104, 0.030,
                 M["iron"], verts=10))

    P.extend(gable_roof(tag + "_Roof", (0, 0, POST_TOP + 0.065), ROOF_W,
                        ROOF_D, ROOF_RISE, M["slate"], overhang=ROOF_OVER,
                        thickness=ROOF_T))
    P.append(box(tag + "_Ridge", (0, 0, POST_TOP + 0.065 + ROOF_RISE),
                 (0.07, ROOF_D + 0.24, 0.07), M["wood_dark"]))

    soften_all(P, width=0.026, segments=2)
    return P
