"""BUILDING.house.hut - the starter dwelling, a thatched one-room hut.

Scale is set by the villager, not by realism. A follower is ~0.9 m tall and
chibi-proportioned, so a hut that would be correct at human scale reads as a
cathedral beside it. The door is 0.72 -- comfortably over a follower head,
comfortably under a real door.

The roof is the silhouette. At phone size this building is a roof and a colour
and nothing else, so the overhang is generous and the walls are plain. The door
is a cut recess floored with `hollow`, not a modelled panel: at fifteen pixels a
handle is noise costing two hundred triangles.

The wall is built TALL and cut back to the roof line, so it is the pentagon a
gabled house actually is. Stopping it at the eaves leaves the gable ends open
and you see straight through the building.

Fronts -Y, like everything floor-standing.
"""
import os

from kit import M, box, boolean, gable_roof, gable_cutters, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="building",
    family="house",
    variant="hut",
    category=CATEGORY,
    # MEASURED, not derived: the roof slab is rotated, so its thickness adds to
    # the horizontal extent and the real span is 1.665, not the 1.60 the
    # arithmetic suggests. The village reserves ground from this declaration, so
    # understating it gets a neighbour placed inside the eaves. Tile
    # reservation is ceil() of this: 2 x 2.
    #
    # Y was 1.40 here and `-- measure` says 1.440: the ridge beam is D + 0.34
    # long and reaches 2 cm past the roof at each gable, which the wall-box
    # arithmetic does not see. Understated by exactly the 4 cm the comment above
    # warns about.
    footprint=(1.67, 1.44),
    anchor="floor",
    slots=(),
)

W, D = 1.30, 1.10             # the wall box in plan
H = 0.80                      # eaves height -- where the roof springs from
DOOR_W, DOOR_H = 0.44, 0.72
DOOR_DEPTH = 0.16
RISE = 0.50                   # ridge above the eaves
OVERHANG = 0.15
ROOF_T = 0.12
POST = 0.11


def build(tag="HUT", **kw):
    P = []

    # Tall enough to reach the ridge, then cut back to the roof underside. What
    # survives is a pentagonal prism: four walls and two gable ends in one box.
    walls = box(tag + "_Walls", (0, 0, (H + RISE) * 0.5), (W, D, H + RISE),
                M["plaster"])
    # ONE BOOLEAN PER CUTTER, not join()-then-cut. The two gable cutters
    # overlap heavily either side of the ridge, and join() only concatenates
    # meshes -- it does not union them -- so the joined cutter is a
    # self-intersecting solid with no coherent inside. EXACT took that to mean
    # the whole wall and removed it: the first render of this was a roof on
    # four posts with no building under it.
    #
    # The "join cutters first" rule is for cutters that do NOT touch, like a
    # bolt circle. These do.
    for cutter in gable_cutters("wallcut", (0, 0, H), W, D, RISE,
                                overhang=OVERHANG, thickness=ROOF_T):
        boolean(walls, cutter)

    # The doorway, cut after the gable so the two booleans cannot interact.
    # Floored with a dark box rather than left open: an open hole shows the
    # inside of the far wall, which at this scale reads as a bright smear, not
    # as depth.
    boolean(walls, box("door_cut",
                       (0, -D * 0.5 + DOOR_DEPTH * 0.5, DOOR_H * 0.5),
                       (DOOR_W, DOOR_DEPTH * 2.0, DOOR_H), None))
    P.append(walls)
    P.append(box(tag + "_DoorDark", (0, -D * 0.5 + DOOR_DEPTH, DOOR_H * 0.5),
                 (DOOR_W, 0.04, DOOR_H), M["hollow"]))

    # Corner posts. Timber against plaster is the hue break the palette needs;
    # two neutrals of different brightness would read as one object. Only up to
    # the eaves -- above that is gable, not frame.
    for sx in (-1, 1):
        for sy in (-1, 1):
            P.append(box("%s_Post%s%s" % (tag, "L" if sx < 0 else "R",
                                          "F" if sy < 0 else "B"),
                         (sx * (W * 0.5 - POST * 0.35),
                          sy * (D * 0.5 - POST * 0.35), H * 0.5),
                         (POST, POST, H), M["wood"]))

    P.extend(gable_roof(tag + "_Roof", (0, 0, H), W, D, RISE, M["thatch"],
                        overhang=OVERHANG, thickness=ROOF_T))
    P.append(box(tag + "_Ridge", (0, 0, H + RISE), (0.09, D + 0.34, 0.09),
                 M["wood_dark"]))

    # 4 cm on a 1.3 m wall: a visible radius that still reads as a wall rather
    # than a cushion. soften_all clamps it to a quarter of the smallest
    # dimension, so the 11 cm posts get 2.75 cm and stay posts.
    soften_all(P, width=0.04, segments=3)
    return P
