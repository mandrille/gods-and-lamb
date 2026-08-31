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
    "..................................",
    "..................................",
    "..........AAAAAAAAAAAA............",
    "........AAAAAAAAAAAAAAAAA.........",
    ".......AAAAGGGGGGGGGGGAAAAA.......",
    ".....AAAAGGGGGGGGGGGGGGGAAAA......",
    "....AAAGGGGGGGGGGGGGGGGGGGAAA.....",
    "....AAGGGGGGGGGGGGGGGGGGGGGAAA....",
    "...AAAGGGGGGGGGGGGGGGGGGGGGGAAA...",
    "...AAGGGGGGGGGGGGGGGGGGGGGGGGAAA..",
    "..AAAGGGGGGGGGGGGGGGGGGGGGGGGGAA..",
    "..AAGGGGGGGGGGGGGGGGGGGGGGGGGGAA..",
    "..AAGGGGGGGGGGGGGGGGGWWWWWWGGGAAA.",
    "..AAGGGGGGGGGGGGGGGGWWWWWWWWGGAAA.",
    "..AAGGGGGGGGGGGGGGGGWWWWWWWWGGAAA.",
    "..AAGGGGGGGGGGGGGGGGWWWWWWWWGGAA..",
    "..AAAGGGGGGGGGPGGGGGWWWWWWWWGGAA..",
    "...AAGGGGGGGGGPGGGGGGWWWWWWGGAAA..",
    "...AAAGGGGGGGPGGGGGGGGGGGGGGAAA...",
    "....AACCCCCCCCGGGGGGGGGGGGGAAA....",
    "....AAACCCCCCCGGGGGGGGGGGGAAA.....",
    ".....AAAACCCCCGGGGGGGGGGAAAA......",
    "......AAAAACCCGGGGGGGGAAAAA.......",
    "........AAAAAAAAAAAAAAAAA.........",
    "..........AAAAAAAAAAAA............",
    "..................................",
    "..................................",
]

# The raised inland. Two blocks up, not one: at half scale a single block
# is a 0.5 m step and reads as a kerb, not as a cliff. The block underneath
# is filled with FILL so the cliff is solid rather than a floating shelf.
UPPER = [
    "..................................",
    "..................................",
    "..................................",
    "..................................",
    "..................................",
    "..................................",
    "..........GGGGGGG.................",
    ".........GGGGGGGGGG...............",
    "........GGGGGGGGGGG...............",
    "........GGGGGGGGGGGG..............",
    ".......GGGGGPPPPGGGG..............",
    ".......GGGGGPPPPGGGG..............",
    "........GGGGPPPPGGGG..............",
    "........GGGGGGGGGGG...............",
    ".........GGGGGGGGG................",
    "...........GGGGGG.................",
    "..................................",
    "..................................",
    "..................................",
    "..................................",
    "..................................",
    "..................................",
    "..................................",
    "..................................",
    "..................................",
    "..................................",
    "..................................",
]

# Water, tilled ground, the plaza and the track are part of the MAP now rather
# than lists patched over it afterwards. The map is the picture; a list of
# coordinates layered on top of it is a second picture nobody can see.
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
    # SOLVED against the guards below -- spacing, clearance and
    # containment -- then written out literally. Buildings are confined
    # to the inner ground: two huts solved onto the beach ring, where
    # the land falls away behind them, and each read as a tan plane
    # floating over the sea.
    # The fence and bridge RUNS are seeded FIRST and everything else is
    # fitted around them, because a run is intent.
    # (asset, col, row, yaw, scale)
    ("Buildings/bridge", 20, 14, 0.0, 1.00),
    ("Buildings/bridge", 21, 14, 0.0, 1.00),
    ("Buildings/bridge", 22, 14, 0.0, 1.00),
    ("Buildings/bridge", 23, 14, 0.0, 1.00),
    ("Buildings/bridge", 24, 14, 0.0, 1.00),
    ("Buildings/bridge", 25, 14, 0.0, 1.00),
    ("Buildings/bridge", 26, 14, 0.0, 1.00),
    ("Buildings/bridge", 27, 14, 0.0, 1.00),
    ("Buildings/cottage", 10, 13, 18.0, 1.00),
    ("Buildings/cottage", 14, 7, -142.0, 1.00),
    ("Buildings/cottage", 23, 9, 96.0, 1.00),
    ("Buildings/fence", 11, 15, 0.0, 1.00),
    ("Buildings/fence", 12, 15, 0.0, 1.00),
    ("Buildings/fence", 13, 15, 0.0, 1.00),
    ("Buildings/fence", 14, 15, 0.0, 1.00),
    ("Buildings/fence", 15, 15, 0.0, 1.00),
    ("Buildings/fence", 16, 15, 0.0, 1.00),
    ("Buildings/hut", 12, 19, -24.0, 1.00),
    ("Buildings/hut", 18, 19, 150.0, 1.00),
    ("Buildings/shrine", 17, 13, 0.0, 1.00),
    ("Buildings/well", 23, 19, 0.0, 1.00),
    ("Nature/bush", 6, 7, 15.0, 1.00),
    ("Nature/bush", 7, 15, 122.0, 0.85),
    ("Nature/bush", 8, 8, 44.0, 0.90),
    ("Nature/bush", 10, 12, 44.0, 0.90),
    ("Nature/bush", 10, 16, -60.0, 0.95),
    ("Nature/bush", 12, 14, -30.0, 1.00),
    ("Nature/bush", 14, 19, 78.0, 1.00),
    ("Nature/bush", 15, 6, 44.0, 0.90),
    ("Nature/bush", 16, 20, 15.0, 0.85),
    ("Nature/bush", 17, 7, -30.0, 1.00),
    ("Nature/bush", 18, 17, 122.0, 0.95),
    ("Nature/bush", 19, 20, -60.0, 1.00),
    ("Nature/bush", 21, 5, 78.0, 0.85),
    ("Nature/bush", 22, 18, 15.0, 0.95),
    ("Nature/bush", 24, 11, 122.0, 1.00),
    ("Nature/bush", 26, 19, -60.0, 0.85),
    ("Nature/bush", 29, 12, 78.0, 0.95),
    ("Nature/crop_row", 6, 19, 0.0, 1.00),
    ("Nature/crop_row", 7, 19, 0.0, 1.00),
    ("Nature/crop_row", 7, 20, 0.0, 1.00),
    ("Nature/crop_row", 8, 19, 0.0, 1.00),
    ("Nature/crop_row", 8, 20, 0.0, 1.00),
    ("Nature/crop_row", 9, 20, 0.0, 1.00),
    ("Nature/crop_row", 9, 21, 0.0, 1.00),
    ("Nature/crop_row", 10, 19, 0.0, 1.00),
    ("Nature/crop_row", 10, 20, 0.0, 1.00),
    ("Nature/crop_row", 10, 21, 0.0, 1.00),
    ("Nature/crop_row", 10, 22, 0.0, 1.00),
    ("Nature/crop_row", 11, 19, 0.0, 1.00),
    ("Nature/crop_row", 11, 20, 0.0, 1.00),
    ("Nature/crop_row", 11, 21, 0.0, 1.00),
    ("Nature/crop_row", 11, 22, 0.0, 1.00),
    ("Nature/crop_row", 12, 20, 0.0, 1.00),
    ("Nature/crop_row", 12, 21, 0.0, 1.00),
    ("Nature/crop_row", 12, 22, 0.0, 1.00),
    ("Nature/crop_row", 13, 19, 0.0, 1.00),
    ("Nature/crop_row", 13, 20, 0.0, 1.00),
    ("Nature/crop_row", 13, 21, 0.0, 1.00),
    ("Nature/crop_row", 13, 22, 0.0, 1.00),
    ("Nature/crop_row", 14, 22, 0.0, 1.00),
    ("Nature/flowers", 5, 12, 15.0, 1.00),
    ("Nature/flowers", 6, 14, -40.0, 1.00),
    ("Nature/flowers", 7, 16, 70.0, 1.00),
    ("Nature/flowers", 8, 11, 30.0, 1.00),
    ("Nature/flowers", 9, 14, -15.0, 1.00),
    ("Nature/flowers", 11, 6, -80.0, 1.00),
    ("Nature/flowers", 11, 18, 110.0, 1.00),
    ("Nature/flowers", 13, 7, 30.0, 1.00),
    ("Nature/flowers", 15, 8, 30.0, 1.00),
    ("Nature/flowers", 15, 19, 15.0, 1.00),
    ("Nature/flowers", 16, 4, -40.0, 1.00),
    ("Nature/flowers", 17, 10, -80.0, 1.00),
    ("Nature/flowers", 17, 15, 70.0, 1.00),
    ("Nature/flowers", 18, 15, -15.0, 1.00),
    ("Nature/flowers", 19, 14, 110.0, 1.00),
    ("Nature/flowers", 20, 8, 15.0, 1.00),
    ("Nature/flowers", 22, 5, -40.0, 1.00),
    ("Nature/flowers", 22, 6, 70.0, 1.00),
    ("Nature/flowers", 23, 8, -15.0, 1.00),
    ("Nature/flowers", 25, 11, 110.0, 1.00),
    ("Nature/flowers", 26, 7, 15.0, 1.00),
    ("Nature/flowers", 27, 17, -40.0, 1.00),
    ("Nature/flowers", 29, 13, 70.0, 1.00),
    ("Nature/lily_pad", 20, 15, 75.0, 0.90),
    ("Nature/lily_pad", 21, 13, 20.0, 1.00),
    ("Nature/lily_pad", 22, 13, -55.0, 0.90),
    ("Nature/lily_pad", 23, 13, 110.0, 0.95),
    ("Nature/lily_pad", 24, 13, 75.0, 1.00),
    ("Nature/lily_pad", 25, 12, 20.0, 0.90),
    ("Nature/lily_pad", 26, 12, -55.0, 0.95),
    ("Nature/lily_pad", 26, 17, 110.0, 1.00),
    ("Nature/log", 9, 15, -25.0, 1.00),
    ("Nature/log", 18, 4, 60.0, 1.00),
    ("Nature/log", 22, 7, 140.0, 1.00),
    ("Nature/log", 28, 15, -25.0, 1.00),
    ("Nature/pine", 5, 10, 12.0, 0.95),
    ("Nature/pine", 9, 16, 12.0, 0.95),
    ("Nature/pine", 10, 6, 24.0, 1.00),
    ("Nature/pine", 14, 13, -37.0, 0.90),
    ("Nature/pine", 18, 6, 70.0, 1.00),
    ("Nature/pine", 18, 9, 130.0, 1.05),
    ("Nature/pine", 18, 16, -88.0, 1.00),
    ("Nature/pine", 21, 21, 44.0, 0.95),
    ("Nature/pine", 26, 18, 165.0, 1.00),
    ("Nature/reeds", 19, 15, 0.0, 1.00),
    ("Nature/reeds", 20, 11, 65.0, 0.90),
    ("Nature/reeds", 20, 18, -30.0, 1.00),
    ("Nature/reeds", 22, 11, 120.0, 0.90),
    ("Nature/reeds", 23, 18, 0.0, 1.00),
    ("Nature/reeds", 25, 18, 65.0, 0.90),
    ("Nature/reeds", 27, 11, -30.0, 1.00),
    ("Nature/reeds", 27, 18, 120.0, 0.90),
    ("Nature/reeds", 28, 14, 0.0, 1.00),
    ("Nature/reeds", 28, 17, 65.0, 0.90),
    ("Nature/rock", 4, 6, 33.0, 1.00),
    ("Nature/rock", 5, 7, 25.0, 0.85),
    ("Nature/rock", 6, 6, -12.0, 0.80),
    ("Nature/rock", 10, 3, 71.0, 0.90),
    ("Nature/rock", 12, 4, 25.0, 0.85),
    ("Nature/rock", 14, 23, 140.0, 1.00),
    ("Nature/rock", 18, 5, -66.0, 0.70),
    ("Nature/rock", 19, 3, 33.0, 0.80),
    ("Nature/rock", 21, 9, 25.0, 0.85),
    ("Nature/rock", 23, 23, -12.0, 0.90),
    ("Nature/rock", 25, 19, -66.0, 0.70),
    ("Nature/rock", 27, 7, 71.0, 1.00),
    ("Nature/rock", 30, 11, 140.0, 0.80),
    ("Nature/rock", 32, 14, 33.0, 0.90),
    ("Nature/stump", 6, 8, 12.0, 1.00),
    ("Nature/stump", 14, 18, 12.0, 1.00),
    ("Nature/stump", 20, 20, 95.0, 1.00),
    ("Nature/stump", 24, 10, -40.0, 1.00),
    ("Nature/tall_grass", 3, 11, -70.0, 1.00),
    ("Nature/tall_grass", 4, 11, 8.0, 1.00),
    ("Nature/tall_grass", 5, 15, 25.0, 1.00),
    ("Nature/tall_grass", 5, 20, 20.0, 1.00),
    ("Nature/tall_grass", 6, 16, -60.0, 1.00),
    ("Nature/tall_grass", 7, 17, 45.0, 1.00),
    ("Nature/tall_grass", 10, 15, 100.0, 1.00),
    ("Nature/tall_grass", 10, 23, 20.0, 1.00),
    ("Nature/tall_grass", 11, 16, 8.0, 1.00),
    ("Nature/tall_grass", 14, 4, 25.0, 1.00),
    ("Nature/tall_grass", 15, 18, -60.0, 1.00),
    ("Nature/tall_grass", 16, 21, 45.0, 1.00),
    ("Nature/tall_grass", 16, 23, -70.0, 1.00),
    ("Nature/tall_grass", 17, 21, 100.0, 1.00),
    ("Nature/tall_grass", 18, 21, 8.0, 1.00),
    ("Nature/tall_grass", 19, 17, 25.0, 1.00),
    ("Nature/tall_grass", 20, 10, -60.0, 1.00),
    ("Nature/tall_grass", 21, 7, 45.0, 1.00),
    ("Nature/tall_grass", 22, 22, 20.0, 1.00),
    ("Nature/tall_grass", 23, 5, 8.0, 1.00),
    ("Nature/tall_grass", 23, 6, 100.0, 1.00),
    ("Nature/tall_grass", 24, 8, 25.0, 1.00),
    ("Nature/tall_grass", 25, 10, -60.0, 1.00),
    ("Nature/tall_grass", 27, 8, 45.0, 1.00),
    ("Nature/tall_grass", 27, 19, -70.0, 1.00),
    ("Nature/tall_grass", 28, 13, 100.0, 1.00),
    ("Nature/tall_grass", 30, 17, 20.0, 1.00),
    ("Nature/tree", 6, 15, -18.0, 1.00),
    ("Nature/tree", 7, 7, 61.0, 0.92),
    ("Nature/tree", 9, 19, -50.0, 1.00),
    ("Nature/tree", 10, 9, 40.0, 1.00),
    ("Nature/tree", 15, 10, 80.0, 0.90),
    ("Nature/tree", 15, 17, 40.0, 0.98),
    ("Nature/tree", 15, 21, 128.0, 0.86),
    ("Nature/tree", 18, 22, 22.0, 1.00),
    ("Nature/tree", 20, 12, 61.0, 0.86),
    ("Nature/tree", 21, 6, -95.0, 0.92),
    ("Nature/tree", 27, 12, 128.0, 0.92),
    ("Nature/tree", 29, 15, -18.0, 0.98),
]

# Which props are subject to the spacing guard at all.
#
# This started as an area heuristic -- anything bigger than one tile -- and that
# was wrong in both directions. It let a hut sit 30 cm from a cottage, and it
# forbade a FIELD, because contiguous crop rows are the whole idea of a field
# and the guard read them as forty collisions. Forty-two props got dropped.
#
# So it is a list, not a threshold. Buildings and trees are the things that
# have to stand apart to read as a village; everything else is dressing and may
# sit wherever it likes, including touching.
BULKY = ("Buildings/", "Nature/tree", "Nature/pine")
# A fence inside a cottage is still a fault -- chaining pieces are checked
# for raw overlap, they are only exempt from the CLEARANCE halo.


def is_bulky(aid):
    return any(aid.startswith(b) for b in BULKY)

# Ground a building reserves BEYOND its own footprint, in metres, total across
# each axis. Overlap and crowding are different faults: the first island passed
# the overlap guard and still had five buildings shoulder to shoulder on one
# plateau, because "not intersecting" is a very low bar for architecture.
# Villages have gaps between houses and that is most of what makes them read as
# villages.
BUILDING_CLEARANCE = 1.10
# ...except the pieces whose whole job is to touch the next one.
CHAINING = ("Buildings/fence", "Buildings/bridge")
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


def wants_clearance(aid):
    """True for a building that should stand apart from other buildings.

    Not the chaining pieces: a fence and a bridge exist to touch the next
    section, and a fence running along a cottage wall is a garden, not a
    collision. Clearance is applied to a PAIR only when both sides want it --
    inflating a house against a fence made the guard reject ten perfectly good
    placements and would have pushed every fence a metre off the thing it is
    supposed to enclose.
    """
    return aid.startswith("Buildings/") and aid not in CHAINING


def _check_on_land(entries, land_tiles):
    """Fail if a prop hangs off the island.

    The placement guard checked SPACING and nothing else, so a cottage whose
    centre tile was land could still overhang the coast by most of its width --
    two huts ended up standing on air at the shoreline, roofs out over the sea.
    A tile being land says nothing about a 2.15 m building centred on it.

    So the footprint is sampled on the tile grid and every cell it covers must
    be land. Sampling rather than clipping because the grid IS the ground: a
    prop that covers a tile needs that tile to exist.

    Scatter is exempt. A tuft of grass over the lip of a sand tile is fine, and
    demanding otherwise strips the coast bare.
    """
    off = []
    for aid, x, y, w, d in entries:
        if not is_bulky(aid):
            continue
        cols = int(w / TILE / 2) + 1
        rows_ = int(d / TILE / 2) + 1
        missing = 0
        total = 0
        for i in range(-cols, cols + 1):
            for j in range(-rows_, rows_ + 1):
                px, py = x + i * TILE, y + j * TILE
                if abs(i * TILE) > w * 0.5 or abs(j * TILE) > d * 0.5:
                    continue
                total += 1
                if (px, py) not in land_tiles:
                    missing += 1
        if missing:
            off.append("%s at (%.2f, %.2f) has %d of %d footprint cell(s) off "
                       "the island" % (aid, x, y, missing, total))
    if off:
        raise SystemExit("FAIL: %d prop(s) hang off the island:%s  %s"
                         % (len(off), chr(10), (chr(10) + "  ").join(off)))


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

    Only BULKY props participate. Flowers beside tall grass is dressing, not a
    collision, and a field is contiguous crop rows by definition.
    """
    big = [e for e in entries if is_bulky(e[0])]
    clashes = []
    for i in range(len(big)):
        aid_a, ax, ay, aw, ad = big[i]
        for j in range(i + 1, len(big)):
            aid_b, bx, by, bw, bd = big[j]
            pad = (BUILDING_CLEARANCE
                   if wants_clearance(aid_a) and wants_clearance(aid_b) else 0.0)
            gap_x = abs(ax - bx) - (aw + bw) * 0.5 - pad
            gap_y = abs(ay - by) - (ad + bd) * 0.5 - pad
            if gap_x < -OVERLAP_TOL and gap_y < -OVERLAP_TOL:
                clashes.append("%s and %s are %.2f x %.2f m too close%s"
                               % (aid_a, aid_b, -gap_x, -gap_y,
                                  " (footprints plus %.2f m clearance)" % pad
                                  if pad else " (footprints overlap)"))
    if clashes:
        raise SystemExit("FAIL: %d prop placement(s) overlap:%s  %s"
                         % (len(clashes), chr(10), (chr(10) + "  ").join(clashes)))


def build():
    """Assemble the island. Returns the list of placed objects."""
    cache = {}
    placed = []

    lower = _grid(LOWER)
    upper = _grid(UPPER)
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
    land_world = {world(c, r) for (c, r) in set(lower) | set(upper)}
    _check_on_land(boxes, land_world)
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
