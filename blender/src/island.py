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
    ("Buildings/hut", 8, 6, 0.0, 1.0),
    # On the plateau, framing the hut.
    ("Nature/tree", 6, 5, 24.0, 1.0),
    ("Nature/tree", 10, 9, -37.0, 0.88),
    ("Nature/bush", 6, 10, -48.0, 0.95),
    ("Nature/bush", 10, 4, 80.0, 1.05),
    # On the shore, below the cliff.
    ("Nature/tree", 4, 12, 61.0, 0.92),
    ("Nature/tree", 15, 3, -18.0, 0.84),
    ("Nature/tree", 3, 7, 128.0, 0.95),
    ("Nature/bush", 12, 12, 15.0, 1.0),
    ("Nature/bush", 2, 9, 122.0, 0.85),
    ("Nature/bush", 16, 8, -60.0, 0.9),
    ("Nature/rock", 17, 11, 33.0, 1.0),
    ("Nature/rock", 2, 5, -12.0, 0.8),
    ("Nature/rock", 12, 2, 71.0, 0.7),
    ("Nature/rock", 5, 14, 12.0, 0.75),
    # The field, on the flat below the plateau.
    ("Nature/crop_row", 5, 11, 0.0, 1.0),
    ("Nature/crop_row", 6, 11, 0.0, 1.0),
    ("Nature/crop_row", 7, 11, 0.0, 1.0),
    ("Nature/crop_row", 5, 12, 0.0, 1.0),
    ("Nature/crop_row", 6, 12, 0.0, 1.0),
]

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
