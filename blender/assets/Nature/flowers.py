"""NATURE.flower.flowers - a clump of flowering plants for grass.

One asset, not one flower. Flowers are seen in fives and tens, so a single
bloom would be instanced into a polka-dot grid; a clump with an asymmetric
silhouette can be yawed and dropped anywhere and no two placements look alike.

FOUR petal colours in one clump, on purpose. A monochrome clump reads as a
coloured smear at island distance; a mixed one reads as flowers, because
"several small saturated dots of different hues low in the grass" is what a
flower bed actually looks like from forty metres. The single most valuable
thing here is hue, not shape -- a bloom is 8 cm and that is four pixels.

The base is LEAVES, not a cushion. The first pass sat the stems on two
chamfered slabs and the result read as seven mushrooms on a green pillow -- the
blades cost the same and the clump reads as a plant.

Everything green here is `leaf_dark`/`leaf`, which are bluer and darker than
the `grass` tile the clump stands on. Green on green disappears: there is no
ambient occlusion pass under GL Compatibility to draw a border, so the hue
shift is the only thing separating the clump from the ground.

Stems and leaves go through `soften_all(width=0.0)` -- smooth-shaded, tagged,
no radius. A 2 cm stem has no edge anyone can see and bevelling nine of them is
how a plant loses its cap for nothing.
"""
import os

from kit import M, blob, box, soften_all
from plantkit import blade, stalk, tip_of

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="nature",
    family="flower",
    variant="flowers",
    category=CATEGORY,
    # MEASURED (0.493 x 0.438). The leaning stems and the leaves reach well
    # past the 0.3 m of ground the clump grows from.
    footprint=(0.49, 0.44),
    anchor="floor",
    slots=(),
)

# (x, y, height, lean_x, lean_y, petal material). Scattered by hand and off the
# tile axes so a bed of these does not read as a lattice, and the tall ones are
# not all on one side or the clump leans.
BLOOMS = [
    (-0.13, -0.09, 0.25, 9.0, -7.0, "petal_red"),
    (0.02, -0.15, 0.19, -5.0, 11.0, "petal_gold"),
    (0.15, -0.02, 0.28, 8.0, 12.0, "petal_blue"),
    (-0.16, 0.08, 0.21, -11.0, -8.0, "petal_pink"),
    (-0.01, 0.05, 0.31, 4.0, -3.0, "petal_gold"),
    (0.12, 0.14, 0.23, -8.0, 7.0, "petal_red"),
    (0.00, 0.19, 0.17, 6.0, 5.0, "petal_blue"),
]

# (x, y, height, lean_x, lean_y, material). Leaves, not a cushion -- see build.
LEAVES = [
    (-0.09, -0.07, 0.17, 26.0, -22.0, "leaf_dark"),
    (0.06, -0.12, 0.13, 30.0, -6.0, "leaf"),
    (0.14, 0.03, 0.16, 5.0, 31.0, "leaf_dark"),
    (0.01, 0.13, 0.14, -27.0, 14.0, "leaf"),
    (-0.13, 0.05, 0.18, -18.0, -26.0, "leaf_dark"),
    (-0.02, -0.02, 0.12, 12.0, 9.0, "leaf"),
    (0.11, -0.06, 0.15, 21.0, 18.0, "leaf"),
    (-0.06, 0.11, 0.16, -24.0, -4.0, "leaf_dark"),
    (0.04, 0.05, 0.11, -7.0, 15.0, "leaf"),
]


def build(tag="FLOWERS", **kw):
    thin = []
    heads = []

    # The clump has to sit on something or the stems read as wires stuck in the
    # ground -- but the first pass used two chamfered slabs for that and the
    # asset read as seven mushrooms on a green cushion. Leaves are what a
    # flowering plant has at the bottom, so the base is arcing blades and ONE
    # small mass buried among them to stop light showing through the middle.
    #
    # The mass is deliberately SMALL -- 17 cm across, well inside the ring of
    # leaves. At 24 cm it was still visible as a slab between the blades and
    # the plinth read came straight back.
    foliage = [
        blob(tag + "_Crown", (-0.01, 0.00, 0.035), (0.17, 0.15, 0.07),
             M["leaf_dark"], tilt=(0, 0, 17)),
    ]
    for i, (x, y, h, lx, ly, mat) in enumerate(LEAVES):
        thin.extend(blade("%s_Leaf%d" % (tag, i), (x, y, 0.0), M[mat],
                          height=h, width=0.038, lean=(lx, ly), curl=2.4,
                          flat=0.42))

    for i, (x, y, h, lx, ly, mat) in enumerate(BLOOMS):
        base = (x, y, 0.05)
        thin.append(stalk("%s_Stem%d" % (tag, i), base, M["leaf"],
                          height=h, width=0.020, lean=(lx, ly)))
        top = tip_of(base, h, (lx, ly))
        # Taller than it is wide, and it swallows the top of its own stem. A
        # wide flat head is a mushroom cap; a bud that is a little taller than
        # it is broad is the shape that survives being four pixels across.
        heads.append(box("%s_Head%d" % (tag, i),
                         (top[0], top[1], top[2] + 0.008),
                         (0.070, 0.070, 0.075), M[mat], rot=(lx, ly, 0)))

    soften_all(foliage, width=0.05, segments=2)
    # The heads earn a radius the stems do not: they are the only saturated
    # thing here, and a bevel is what catches the key light and stops seven
    # cubes reading as seven cubes.
    soften_all(heads, width=0.03, segments=1)
    soften_all(thin, width=0.0)
    return foliage + thin + heads
