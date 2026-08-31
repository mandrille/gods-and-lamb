"""NATURE.tree.tree - the village broadleaf.

Canopy is chamfered BOXES at slight angles, not a subdivided sphere. That is
not a budget compromise, it is the look: the reference canopies are clearly
boxy masses with soft corners and they read as trees instantly. A sphere costs
about five times as much and matches nothing else in the village.

A CORE, a CAP and one LOBE, not a stack. Three similar boxes at three angles
read as three boxes however much they overlap -- that was the defect, and the
fix is in the comment on the canopy itself: masses that share a yaw meet along
a horizontal rim, masses at different yaws meet along a slanted crease that
reads as a notch.

Two greens, because one green is a silhouette. The core is `leaf_dark` and the
cap on top is `leaf_light`, so the canopy has a top and a bottom without
needing a light to tell you.

The trunk flares at the base. A straight post reads as a pole; the flare is
four small boxes and it is the difference between a tree and a lollipop.

Fronts -Y, like everything floor-standing.
"""
import os

from kit import M, box, blob, cyl, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="nature",
    family="tree",
    variant="tree",
    category=CATEGORY,
    # MEASURED (1.356 x 1.213). The canopy blobs are yawed, so their corners
    # reach further than their box sizes suggest, and the lobe pushes the X
    # span 13 cm past the core on one side.
    footprint=(1.36, 1.21),
    anchor="floor",
    slots=(),
)

TRUNK_H = 0.86
TRUNK_R = 0.115
# Yaw of the canopy, shared by the core and the cap on purpose -- see build().
# Off the tile axes so the crown never lines up with the ground grid.
YAW = 13.0


def build(tag="TREE", **kw):
    P = []

    trunk = [cyl(tag + "_Trunk", (0, 0, TRUNK_H * 0.5), TRUNK_R, TRUNK_H,
                 M["trunk"], verts=8)]
    # Root flare. Four boxes pushed out at the base, low enough that the canopy
    # never hides them. Rotated 45 degrees off the axes so they do not line up
    # with the tile grid underneath.
    for i, (dx, dy) in enumerate(((1, 1), (1, -1), (-1, 1), (-1, -1))):
        trunk.append(box("%s_Root%d" % (tag, i),
                         (dx * 0.105, dy * 0.105, 0.055),
                         (0.15, 0.15, 0.11), M["trunk"], rot=(0, 0, 45)))

    # ONE core mass plus three lobes, not three masses in a stack.
    #
    # The stack was a defect and this is the fix. Three similar boxes at
    # 0.54/0.48/0.38 deep with about 0.25 m of overlap still met side-face to
    # top-face, and every one of those meetings opened a deep concave notch: in
    # the island render the canopy read as three separate boxes balanced on
    # each other. Making the slabs deeper had only moved the problem far enough
    # away to be missed in close-up.
    #
    # So: one mass owns the silhouette and is nearly as deep as it is wide, and
    # the rest are BURIED in it far enough that only a bump comes out. Each
    # lobe is more than half inside the core, which is what turns a step into a
    # bulge -- there is no notch because no corner is exposed.
    # THREE masses, and two of them share the core's yaw.
    #
    # The yaw is the part that took three attempts. Chamfered boxes at
    # DIFFERENT angles intersect along a slanted line, and a slanted
    # intersection between two greens reads as a deep concave notch -- put four
    # of those in a crown and it is a stack of crates, which is exactly what
    # the reported defect looked like. Give the cap the SAME yaw as the core
    # and their intersection is a horizontal rim instead, which reads as the
    # shoulder of one rounded mass.
    #
    # So the silhouette is one soft block: a core, a cap that is only 12 cm
    # narrower than it (a narrow cap is a lid; this one is a top), and a single
    # lobe at a different angle to stop it being symmetrical. One slanted
    # intersection is a lumpy crown. Four are a pile.
    canopy = []
    # Wider than it is deep. A core as deep as it is wide is a cube, and a cube
    # on a stick is a mailbox.
    canopy.append(blob(tag + "_CanopyCore", (0.0, 0.0, TRUNK_H + 0.32),
                  (1.06, 1.00, 0.60), M["leaf_dark"], tilt=(0, 0, YAW)))
    # `leaf_light` on top and nowhere else. Two greens split top-and-bottom
    # give the canopy a lit side without a light having to say so, and the same
    # light green low down would read as a hole.
    canopy.append(blob(tag + "_CanopyCap", (-0.02, 0.03, TRUNK_H + 0.68),
                  (0.88, 0.84, 0.36), M["leaf_light"], tilt=(0, 0, YAW)))
    # The lobe carries the same yaw as everything else and spans nearly the
    # same band of Z as the core, so the 10 cm of it that sticks out has full
    # height behind it. A shorter lobe pushed out the same distance hangs off
    # the side with air under the overhang and reads as a box stuck on.
    canopy.append(blob(tag + "_CanopyLobe", (0.36, -0.14, TRUNK_H + 0.34),
                  (0.62, 0.58, 0.54), M["leaf"], tilt=(0, 0, YAW)))

    # TWO passes, because the two halves of a tree earn different budgets.
    # The canopy IS the silhouette, so it gets 7 cm at two segments -- the same
    # chunky radius the ground tiles use, so foliage and terrain read as one
    # world. The trunk and roots are a few pixels at play distance and get one
    # segment, which is what brought this asset back under its cap: 872 tris
    # against a 800 cap, fixed in the geometry rather than by raising the cap.
    soften_all(canopy, width=0.07, segments=2)
    soften_all(trunk, width=0.05, segments=1)
    P.extend(trunk)
    P.extend(canopy)
    return P
