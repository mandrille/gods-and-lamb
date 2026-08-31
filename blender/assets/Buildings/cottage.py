"""BUILDING.house.cottage - the settled dwelling, a step up from the hut.

Same family as `hut` and deliberately so: a new VARIANT of an existing family
costs nothing, and this IS a house. What makes it read as the upgrade is
everything the hut does not have -- walls a third taller, a tiled roof instead
of thatch, two lit windows, a framed door, and a chimney.

The roof is still the silhouette. The tile roof is `terracotta`, the strongest
hue in the village and deliberately nothing like the hut's `thatch`, so a
village of both never merges into one straw-coloured blob.

Windows are the cheapest "someone lives here" signal there is: a recess cut into
the wall, floored with `hollow`, and a warm pane sitting slightly PROUD of the
wall face. Proud, not flush and not sunk -- detail placed just inside a face
disappears at the play camera, and the pane is the whole point of the window.
The pane is smaller than the hole so a dark border survives around it; that
border is what makes it a window rather than a yellow sticker.

The wall is built TALL and cut back to the roof line, so it is the pentagon a
gabled house actually is. Stopping it at the eaves leaves the gable ends open.

Fronts -Y. The ridge runs front-to-back, so the -Y elevation is the gable end
and it carries the door, the two windows and the frame.
"""
import os

from kit import (M, box, boolean, scheme, gable_roof, gable_cutters,
                 soften_all)

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="building",
    family="house",
    variant="cottage",
    category=CATEGORY,
    # MEASURED, not derived. The roof slabs are rotated, so their thickness
    # adds to the horizontal reach and X comes out well past W/2 + OVERHANG.
    # The village reserves ground from this number, so understating it puts a
    # neighbour inside the eaves.
    footprint=(2.15, 1.88),
    anchor="floor",
    slots=(),
)

W, D = 1.70, 1.46             # the wall box in plan
H = 1.06                      # eaves height -- a third over the hut's 0.80
RISE = 0.62                   # ridge above the eaves
OVERHANG = 0.19
ROOF_T = 0.13

DOOR_W, DOOR_H = 0.46, 0.78   # 0.78 against a 0.9 m follower: it walks in
DOOR_DEPTH = 0.16
JAMB = 0.075

WIN_W, WIN_H = 0.36, 0.32     # the HOLE
WIN_Z = 0.62
WIN_X = 0.55                  # either side of the door
WIN_DEPTH = 0.12
PANE_INSET = 0.06             # dark border left showing around the pane

CHIM_W, CHIM_D = 0.24, 0.26
CHIM_X, CHIM_Y = -0.40, 0.40  # on the left slope, back half


def build(tag="COTTAGE", **kw):
    body, trim, roof, accent = scheme(kw.get("scheme", "cottage_red"))
    P = []

    walls = box(tag + "_Walls", (0, 0, (H + RISE) * 0.5), (W, D, H + RISE),
                body)

    # ONE BOOLEAN PER CUTTER. The two gable cutters overlap heavily either side
    # of the ridge and join() only concatenates meshes -- it does not union
    # them -- so a joined pair is a self-intersecting solid with no coherent
    # inside and EXACT answers by deleting the whole wall. That is a real
    # failure this project has already paid for once.
    for cutter in gable_cutters("wallcut", (0, 0, H), W, D, RISE,
                                overhang=OVERHANG, thickness=ROOF_T):
        boolean(walls, cutter)

    # Door and windows are cut one at a time for the same reason: the door
    # cutter and the window cutters do not touch each other, but they DO share
    # the wall, and a separate boolean each costs nothing here and cannot
    # interact.
    boolean(walls, box("door_cut",
                       (0, -D * 0.5 + DOOR_DEPTH * 0.5, DOOR_H * 0.5),
                       (DOOR_W, DOOR_DEPTH * 2.0, DOOR_H), None))
    for sx in (-1, 1):
        boolean(walls, box("win_cut_%d" % sx,
                           (sx * WIN_X, -D * 0.5 + WIN_DEPTH * 0.5, WIN_Z),
                           (WIN_W, WIN_DEPTH * 2.0, WIN_H), None))
    P.append(walls)

    # The back of each hole. An open hole shows the inside of the far wall,
    # which at this scale is a bright smear, not depth.
    P.append(box(tag + "_DoorDark", (0, -D * 0.5 + DOOR_DEPTH, DOOR_H * 0.5),
                 (DOOR_W, 0.04, DOOR_H), M["hollow"]))
    for sx, side in ((-1, "L"), (1, "R")):
        P.append(box("%s_WinDark%s" % (tag, side),
                     (sx * WIN_X, -D * 0.5 + WIN_DEPTH, WIN_Z),
                     (WIN_W, 0.04, WIN_H), M["hollow"]))
        # PROUD of the wall by 1 cm. Sunk into the recess it falls into its own
        # shadow and the window goes dark at the play camera.
        P.append(box("%s_Pane%s" % (tag, side),
                     (sx * WIN_X, -D * 0.5 - 0.005, WIN_Z),
                     (WIN_W - PANE_INSET, 0.05, WIN_H - PANE_INSET),
                     M["warmglow"]))

    # Door frame: two jambs and a lintel, standing proud of the wall so they
    # cast their own edge. Timber against plaster is the hue break -- two
    # neutrals of different brightness would read as one flat face.
    fy = -D * 0.5 - 0.020
    for sx, side in ((-1, "L"), (1, "R")):
        P.append(box("%s_Jamb%s" % (tag, side),
                     (sx * (DOOR_W * 0.5 + JAMB * 0.5), fy,
                      (DOOR_H + JAMB) * 0.5),
                     (JAMB, 0.070, DOOR_H + JAMB), trim))
    P.append(box(tag + "_Lintel", (0, fy, DOOR_H + JAMB * 0.5),
                 (DOOR_W + JAMB * 2.0, 0.070, JAMB), trim))

    # Corner posts, eaves height only -- above that is gable, not frame.
    for sx in (-1, 1):
        for sy in (-1, 1):
            P.append(box("%s_Post%s%s" % (tag, "L" if sx < 0 else "R",
                                          "F" if sy < 0 else "B"),
                         (sx * (W * 0.5 - 0.045), sy * (D * 0.5 - 0.045),
                          H * 0.5), (0.11, 0.11, H), trim))

    P.extend(gable_roof(tag + "_Roof", (0, 0, H), W, D, RISE, roof,
                        overhang=OVERHANG, thickness=ROOF_T))
    P.append(box(tag + "_Ridge", (0, 0, H + RISE), (0.10, D + 0.42, 0.10),
                 M["wood_dark"]))

    # The stack pierces the left slope. It is a plain axis-aligned box against a
    # ROTATED slab, so no two faces are coplanar and there is nothing to
    # z-fight -- a chimney sat flush on a slope is the classic version of that
    # bug. It starts below the roof underside so no gap opens where it emerges.
    P.append(box(tag + "_Chimney", (CHIM_X, CHIM_Y, (H + RISE + 0.30) * 0.5),
                 (CHIM_W, CHIM_D, H + RISE + 0.30), M["stone"]))
    P.append(box(tag + "_ChimneyCap", (CHIM_X, CHIM_Y, H + RISE + 0.32),
                 (CHIM_W + 0.07, CHIM_D + 0.07, 0.08), M["stone_dark"]))

    # 2 segments, not 3: this carries twice the hut's part count and the bevel
    # is where the triangles go. At 4 cm on a 1.7 m wall the radius still
    # reads.
    soften_all(P, width=0.040, segments=2)
    return P
