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
LOWER = [
    "..AAAAAA....",
    ".AAGGGGAA...",
    ".AGGGGGGAA..",
    "AGGGGGGGGA..",
    "AGGGGGGGGGA.",
    "AGGGGGGGGGA.",
    ".AGGGGGGGGA.",
    ".AAGGGGGGA..",
    "..AAAAAAA...",
]

# The raised inland. Where a tile appears here it sits one block above LOWER,
# and the exposed side of that block is the cliff face the grass band drapes.
UPPER = [
    "............",
    "............",
    "...GGG......",
    "..GGGGG.....",
    "..GGPPG.....",
    "..GGPPG.....",
    "...GGGG.....",
    "....GG......",
    "............",
]

# Water and worked ground are cut into the LOWER layer after the fact, so the
# island reads as land that has been lived on rather than as a mosaic.
# The plateau used to reach col 7 and buried most of this, so the first island
# showed a single blue sliver at the far edge. The cliff was hiding the water,
# which is exactly the kind of thing only a SCENE render tells you.
PONDS = [(7, 3), (8, 3),
         (7, 4), (8, 4), (9, 4),
         (7, 5), (8, 5), (9, 5),
         (7, 6), (8, 6)]
FIELDS = [(3, 7), (4, 7), (5, 7)]
# A route off the plateau. Without it the raised inland is an island on an
# island and the village reads as two unrelated places.
TRACK = [(5, 6), (5, 7), (4, 2), (5, 2)]

CODE = {
    "G": "Terrain/grass",
    "D": "Terrain/dirt",
    "S": "Terrain/stone",
    "P": "Terrain/path",
    "W": "Terrain/water",
    "A": "Terrain/sand",
    "C": "Terrain/soil",
}

# Props, placed by tile coordinate on whichever layer is topmost there.
# (asset, col, row, yaw, scale)
PROPS = [
    ("Buildings/hut", 4, 4, 0.0, 1.0),
    # On the plateau, framing the hut.
    ("Nature/tree", 3, 3, 24.0, 1.0),
    ("Nature/tree", 5, 6, -37.0, 0.88),
    ("Nature/bush", 3, 6, -48.0, 0.95),
    ("Nature/bush", 5, 2, 80.0, 1.05),
    # On the shore, below the cliff.
    ("Nature/tree", 2, 7, 61.0, 0.92),
    ("Nature/tree", 8, 2, -18.0, 0.84),
    ("Nature/bush", 6, 7, 15.0, 1.0),
    ("Nature/bush", 1, 5, 122.0, 0.85),
    ("Nature/rock", 9, 6, 33.0, 1.0),
    ("Nature/rock", 1, 3, -12.0, 0.8),
    ("Nature/rock", 6, 1, 71.0, 0.7),
    # The field, on the flat below the plateau.
    ("Nature/crop_row", 3, 7, 0.0, 1.0),
    ("Nature/crop_row", 4, 7, 0.0, 1.0),
    ("Nature/crop_row", 5, 7, 0.0, 1.0),
]

TILE = 1.0
LIFT = 1.0        # one block of height per layer


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

    # Ground. The upper layer sits a block higher AND keeps a block beneath it,
    # so a cliff is solid rather than a floating shelf.
    for (col, row), ch in sorted(lower.items()):
        x, y = world(col, row)
        placed.append(_place(_prototype(CODE[ch], cache), (x, y, 0.0)))
    for (col, row), ch in sorted(upper.items()):
        x, y = world(col, row)
        placed.append(_place(_prototype(CODE[ch], cache), (x, y, LIFT)))

    # Props sit on whichever layer is topmost under them.
    for aid, col, row, yaw, scale in PROPS:
        if (col, row) not in lower and (col, row) not in upper:
            raise SystemExit("FAIL: prop %s is at (%d, %d), which is not land."
                             % (aid, col, row))
        z = LIFT * 2.0 if (col, row) in upper else LIFT
        x, y = world(col, row)
        placed.append(_place(_prototype(aid, cache), (x, y, z), yaw, scale))

    bpy.context.view_layer.update()
    return placed
