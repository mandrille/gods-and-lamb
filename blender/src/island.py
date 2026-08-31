"""The demo island: a village environment assembled from the tile library.

This is the look-dev scene, not a level. Its job is to answer one question the
per-asset renders cannot: do the pieces belong to the same world when they are
put next to each other. Cliff against grass, water against bank, tree against
tile -- every one of those is a relationship, and a relationship is invisible
in a picture of one asset.

The layout is ASCII on purpose. A village is a shape, and a shape is easier to
judge and to edit as a picture than as a list of coordinates. Two layers give
the reference its stepped-cliff silhouette: LOWER is the shoreline, UPPER is
the raised inland, and a tile present in both is a two-block cliff.

Nothing here is procedural and nothing is random. The scene must render the
same way twice or it is useless for judging a change.
"""
import bpy

import kit
import registry

# G grass   D dirt   S stone   P path   W water   A sand   C crop soil   . empty
#
# HALF-METRE TILES, so this map is twice the resolution of the 1 m version for
# the same physical island. Four times the blocks is the point: a hut spans
# three tiles instead of one and a half, and the ground reads as detail rather
# than as a handful of slabs.
LOWER = [
    "......AAAAAAAA......",
    "....AAAAAAAAAAAA....",
    "...AAGGGGGGGGAAAA...",
    "..AAGGGGGGGGGGGAA...",
    ".AAGGGGGGGGGGGGGAA..",
    ".AGGGGGGGGGGGGGGGAA.",
    "AAGGGGGGGGGGGGGGGGA.",
    "AGGGGGGGGGGGGGGGGGA.",
    "AGGGGGGGGGGGGGGGGGA.",
    "AAGGGGGGGGGGGGGGGGA.",
    ".AGGGGGGGGGGGGGGGAA.",
    ".AAGGGGGGGGGGGGGAA..",
    "..AAGGGGGGGGGGGAA...",
    "...AAAGGGGGGGAAA....",
    "....AAAAAAAAAAA.....",
    "......AAAAAAA.......",
]

# The raised inland. Two blocks up, not one: at half scale a single block is a
# 0.5 m step and reads as a kerb, not as a cliff. The block underneath is
# filled with FILL so the cliff is solid rather than a floating shelf.
UPPER = [
    "....................",
    "....................",
    "....................",
    "....................",
    ".....GGGGGG.........",
    "....GGGGGGGG........",
    "....GGGGGGGG........",
    "....GGGPPGGG........",
    "....GGGPPGGG........",
    "....GGGGGGGG........",
    ".....GGGGGG.........",
    "......GGGG..........",
    "....................",
    "....................",
    "....................",
    "....................",
]

# Water and worked ground are cut into the LOWER layer after the fact, so the
# island reads as land that has been lived on rather than as a mosaic.
PONDS = [(c, r) for r in range(5, 11) for c in range(13, 17)
         if not (r in (5, 10) and c in (13, 16))]
FIELDS = [(c, r) for r in (11, 12) for c in range(5, 10)]
# A route off the plateau. Without it the raised inland is an island on an
# island and the village reads as two unrelated places.
TRACK = [(8, 11), (8, 12), (8, 13), (9, 11), (7, 3), (8, 3), (7, 2), (8, 2)]

CODE = {
    "G": "Terrain/grass",
    "D": "Terrain/dirt",
    "S": "Terrain/stone",
    "P": "Terrain/path",
    "W": "Terrain/water",
    "A": "Terrain/sand",
    "C": "Terrain/soil",
}

# What a cliff is made of under its grass cap.
FILL = "Terrain/dirt"

# Props, placed by tile coordinate on whichever layer is topmost there.
# Coordinates are TILE indices, so they doubled with the grid.
# (asset, col, row, yaw, scale)
PROPS = [
    # Coordinates were SOLVED once against the footprint overlap
    # guard below, not hand-placed. Hand placement put a shrine, a
    # market stall and a hut in the same four tiles -- 35 overlaps in
    # all -- because a declared footprint that nothing checks is
    # decoration. Edit these freely; the guard will tell you.
    # (asset, col, row, yaw, scale)
    ("Buildings/bridge", 13, 7, 0.0, 1.00),
    ("Buildings/bridge", 14, 7, 0.0, 1.00),
    ("Buildings/bridge", 15, 7, 0.0, 1.00),
    ("Buildings/cottage", 4, 5, 18.0, 1.00),  # moved from 5,5
    ("Buildings/fence", 5, 11, 0.0, 1.00),
    ("Buildings/fence", 6, 11, 0.0, 1.00),
    ("Buildings/fence", 7, 11, 0.0, 1.00),
    ("Buildings/fence", 9, 11, 0.0, 1.00),
    ("Buildings/fence", 10, 11, 0.0, 1.00),
    ("Buildings/hut", 10, 10, -24.0, 1.00),  # moved from 10,9
    ("Buildings/market_stall", 11, 5, 200.0, 1.00),  # moved from 10,5
    ("Buildings/shrine", 8, 7, 0.0, 1.00),
    ("Buildings/well", 5, 9, 0.0, 1.00),  # moved from 6,9
    ("Nature/bush", 2, 11, 122.0, 0.85),  # moved from 2,9
    ("Nature/bush", 12, 1, 15.0, 1.00),  # moved from 12,3
    ("Nature/bush", 17, 11, -60.0, 0.90),  # moved from 17,10
    ("Nature/crop_row", 5, 11, 0.0, 1.00),  # moved from 5,12
    ("Nature/crop_row", 7, 10, 0.0, 1.00),  # moved from 7,12
    ("Nature/crop_row", 7, 12, 0.0, 1.00),  # moved from 6,12
    ("Nature/crop_row", 8, 15, 0.0, 1.00),  # moved from 6,13
    ("Nature/crop_row", 9, 13, 0.0, 1.00),  # moved from 8,12
    ("Nature/crop_row", 10, 15, 0.0, 1.00),  # moved from 7,13
    ("Nature/flowers", 4, 6, 15.0, 1.00),
    ("Nature/flowers", 6, 13, 70.0, 1.00),
    ("Nature/flowers", 9, 4, -40.0, 1.00),
    ("Nature/flowers", 15, 11, -15.0, 1.00),
    ("Nature/lily_pad", 13, 9, 110.0, 0.95),
    ("Nature/lily_pad", 14, 3, 20.0, 1.00),  # moved from 14,6
    ("Nature/lily_pad", 15, 9, -55.0, 0.90),  # moved from 15,8
    ("Nature/log", 14, 14, -25.0, 1.00),  # moved from 14,13
    ("Nature/pine", 2, 9, 24.0, 1.00),  # moved from 5,7
    ("Nature/pine", 14, 5, -37.0, 0.88),  # moved from 11,6
    ("Nature/reeds", 11, 7, -30.0, 1.00),  # moved from 12,10
    ("Nature/reeds", 12, 3, 0.0, 1.00),  # moved from 12,5
    ("Nature/reeds", 17, 9, 65.0, 0.90),  # moved from 16,9
    ("Nature/rock", 1, 4, -12.0, 0.80),  # moved from 2,4
    ("Nature/rock", 14, 1, 71.0, 0.70),  # moved from 13,2
    ("Nature/rock", 15, 12, 33.0, 1.00),  # moved from 16,12
    ("Nature/stump", 6, 14, 12.0, 1.00),  # moved from 5,14
    ("Nature/tall_grass", 2, 6, 100.0, 1.00),
    ("Nature/tall_grass", 3, 10, 25.0, 1.00),
    ("Nature/tall_grass", 11, 13, -60.0, 1.00),
    ("Nature/tall_grass", 17, 7, 45.0, 1.00),
    ("Nature/tree", 0, 6, 128.0, 0.95),  # moved from 3,8
    ("Nature/tree", 4, 13, 61.0, 0.92),
    ("Nature/tree", 13, 12, 40.0, 0.90),
    ("Nature/tree", 17, 4, -18.0, 0.84),  # moved from 16,4
]

# Below this footprint area a prop is scatter, and scatter may sit wherever it
# likes. A tile is 0.25 m2, so this exempts anything smaller than one tile.
MIN_RESERVE_AREA = 0.25
OVERLAP_TOL = 0.02        # 2 cm of touching is contact, not collision

TILE = 0.5        # must match tilekit.SIZE
LIFT = 0.5        # one block of height, = tilekit.HEIGHT
UPPER_BLOCKS = 2  # how many blocks the plateau stands above the shore


def _grid(layer):
    """{(col, row): code} from an ASCII layer, skipping empty cells."""
    out = {}
    for row, line in enumerate(layer):
        for col, ch in enumerate(line):
            if ch != ".":
                out[(col, row)] = ch
    return out


def _prototype(aid, cache):
    """Build an asset once and keep the merged mesh to instance from.

    One mesh, many transforms -- which is both cheap here and honest about what
    the engine does with MultiMesh. Building the tile 90 times would also take
    90 times as long and prove nothing extra.
    """
    if aid in cache:
        return cache[aid]
    entry = registry.resolve(aid)
    parts = entry["build"]("PROTO_" + aid.replace("/", "_"))
    meshes = [p for p in parts if getattr(p, "type", None) == "MESH"]
    frac, missing = kit.soften_coverage(meshes)
    if missing:
        raise SystemExit("FAIL: %s left %d mesh(es) out of the rounding pass: %s"
                         % (aid, len(missing), ", ".join(missing)))
    kit.weighted_normals_all(meshes)
    proto = kit.merge_many(meshes, aid.replace("/", "_") + "_proto")
    proto.hide_render = True           # the prototype itself is never in shot
    cache[aid] = proto
    return proto


def _place(proto, location, yaw=0.0, scale=1.0):
    import math
    dup = proto.copy()
    dup.data = proto.data              # linked: one mesh for every instance
    dup.hide_render = False
    dup.location = location
    dup.rotation_euler = (0.0, 0.0, math.radians(yaw))
    dup.scale = (scale, scale, scale)
    bpy.context.scene.collection.objects.link(dup)
    return dup


def _check_overlaps(entries):
    """Fail if two sizeable props are placed inside each other.

    The declared footprint was being used for nothing. It is checked for honesty
    by the asset gate and then ignored at placement time, which meant the first
    populated island had a shrine, a market stall and a hut occupying the same
    four tiles -- obvious in the render, and obvious only in the render.

    This is an AABB test on the declared footprints and it is deliberately
    crude. It ignores yaw, so a rotated building reserves more ground than it
    uses; that makes it conservative, which is the right direction for a guard
    whose job is to stop two houses sharing a wall. The parent project needed a
    full separating-axis test because it packed props into rooms; an open
    village does not.

    Small scatter is exempt from small scatter. Flowers beside tall grass is
    dressing, not a collision, and forbidding it would make the island bare.
    """
    big = [e for e in entries if e[3] * e[4] >= MIN_RESERVE_AREA]
    clashes = []
    for i in range(len(big)):
        aid_a, ax, ay, aw, ad = big[i]
        for j in range(i + 1, len(big)):
            aid_b, bx, by, bw, bd = big[j]
            gap_x = abs(ax - bx) - (aw + bw) * 0.5
            gap_y = abs(ay - by) - (ad + bd) * 0.5
            if gap_x < -OVERLAP_TOL and gap_y < -OVERLAP_TOL:
                clashes.append("%s and %s overlap by %.2f x %.2f m"
                               % (aid_a, aid_b, -gap_x, -gap_y))
    if clashes:
        raise SystemExit("FAIL: %d prop placement(s) overlap:%s  %s"
                         % (len(clashes), chr(10), (chr(10) + "  ").join(clashes)))


def build():
    """Assemble the island. Returns the list of placed objects."""
    cache = {}
    placed = []

    lower = _grid(LOWER)
    upper = _grid(UPPER)
    for (col, row) in PONDS:
        if (col, row) in lower:
            lower[(col, row)] = "W"
    for (col, row) in FIELDS:
        if (col, row) in lower and (col, row) not in upper:
            lower[(col, row)] = "C"
    for (col, row) in TRACK:
        if (col, row) in lower and (col, row) not in upper:
            lower[(col, row)] = "P"

    rows = len(LOWER)
    cols = max(len(r) for r in LOWER)
    ox = -(cols - 1) * TILE * 0.5
    oy = -(rows - 1) * TILE * 0.5

    def world(col, row):
        # Row 0 is the FAR edge, so rows run -Y as they go down the layout.
        # Getting this backwards mirrors the island, which is invisible in the
        # ASCII and obvious in the render.
        return (ox + col * TILE, oy + (rows - 1 - row) * TILE)

    # Ground. The upper layer stands UPPER_BLOCKS up and the blocks beneath it
    # are filled, so a cliff is solid rather than a floating shelf -- and only
    # the topmost block wears the grass cap, which is what makes the cliff face
    # read as earth with turf on top.
    for (col, row), ch in sorted(lower.items()):
        x, y = world(col, row)
        placed.append(_place(_prototype(CODE[ch], cache), (x, y, 0.0)))
    for (col, row), ch in sorted(upper.items()):
        x, y = world(col, row)
        for block in range(1, UPPER_BLOCKS):
            placed.append(_place(_prototype(FILL, cache), (x, y, LIFT * block)))
        placed.append(_place(_prototype(CODE[ch], cache),
                             (x, y, LIFT * UPPER_BLOCKS)))

    # Footprints, in world space, BEFORE anything is built -- a placement fault
    # should cost a second, not a whole island build.
    import registry as _reg
    boxes = []
    for aid, col, row, yaw, scale in PROPS:
        if (col, row) not in lower and (col, row) not in upper:
            raise SystemExit("FAIL: prop %s is at (%d, %d), which is not land."
                             % (aid, col, row))
        fx, fy = _reg.discover()[aid]["decl"]["footprint"]
        x, y = world(col, row)
        boxes.append((aid, x, y, fx * scale, fy * scale))
    _check_overlaps(boxes)

    # Props sit on whichever layer is topmost under them. A tile TOP is its
    # base plus one block, so a prop on the shore stands at LIFT and one on the
    # plateau stands at LIFT * (UPPER_BLOCKS + 1).
    for aid, col, row, yaw, scale in PROPS:
        if (col, row) not in lower and (col, row) not in upper:
            raise SystemExit("FAIL: prop %s is at (%d, %d), which is not land."
                             % (aid, col, row))
        blocks = UPPER_BLOCKS + 1 if (col, row) in upper else 1
        x, y = world(col, row)
        placed.append(_place(_prototype(aid, cache), (x, y, LIFT * blocks),
                             yaw, scale))

    bpy.context.view_layer.update()
    return placed
