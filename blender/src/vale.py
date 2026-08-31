"""The Vale: a continuous landscape, not an island.

Replaces `island.py`, and the island was the problem. An island is a shape with
an edge, so the eye reads the edge first and everything inside it as cargo --
and because the frame had to contain the whole coast, the village was always
squeezed into the middle at whatever density made it fit. Three attempts at
"less packed" all failed for that reason: the container was fixed and only the
contents could move.

So the ground now runs off every side of the frame. The camera is aimed at a
REGION rather than at the whole scene (see FRAME), which means the landscape can
be as large as it likes and the composition is chosen instead of inherited.

What the map has, and why:

* a RIVER, which is the one feature that gives a flat landscape a direction. It
  bends, because a straight one is a canal.
* a ROAD across the whole width, a spur north to the hill and a spur south-east
  to the far fields. Buildings sit ALONG the roads facing them, which is what
  makes a scatter of houses read as a village.
* a BRIDGE where the road meets the river, because a road that stops at water
  is two roads.
* a HILL, two blocks up, so the horizon is not one plane.
* FIELDS beside the village and more out along the south-east spur.

Nothing here is procedural at render time and nothing is random. The maps were
generated once and are literal; the props are placed by hand. The scene must
render the same way twice or it is useless for judging a change.
"""
import math

import bpy

import kit
import registry

# G grass   D dirt   S stone   P path   W water   A sand/bank   C crop   . none
LOWER = [
    "WAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "WWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "WWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "WWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "AWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGAAWWWAAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGGAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGGGAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGCCCCCCCAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGCCCCCCCCAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGCCCCCCCCGAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGCCCCCCCCGGAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGCCCCCCCCGGPPWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGCCCCCCCCGGPPAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGGGGGGGPPGAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGGGGGGGPPGGAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGGGGGGGPPGGAAWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGGGGGGGPPGGGAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGGGGGGGPPGGGGAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGGGGGGGPPGGGGAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGGGGGGGPPGGGGGAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGGGGGGGPPGGGGGAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGGGGGGGPPGGGGGAAWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGGGGGGGPPGGGGGGAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGGGGGGGPPGGGGGGAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGGGGGGGPPGGGGGGAAWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "PPPPPPPPPPPPPPPPPPPPPPPPWWWWPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP",
    "PPPPPPPPPPPPPPPPPPPPPPPPWWWWPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP",
    "PPPPPPPPPPPPPPPPPPPPPPPPWWWWPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP",
    "GGGGGGGGGGGGGGGGGGGGGGGGAWWWAAPPGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGGGGGGGGGGGGGGGGGAWWWWAPPPPGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGGGGGGGGGGGGGGGGGAWWWWAGGPPPPGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGGGGGGGGGGGGGCCCCCAWWWWAGGGPPPPGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGGGGGGGGGGGGGCCCCCAWWWWAGGGGGPPPPGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGGGGGGGGGGGGGCCCCCCAWWWAAGGGGGGPPPPGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGGGGGGGGGGGGGCCCCCCAWWWWAGGGGGGGGPPGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGGGGGGGGGGGGGCCCCCCCAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGGGGGGGGGGGGGCCCCCCCAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGGGGGGGGGGGGGCCCCCCCCAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGGGGGGGGGGGGGGGGGGGGGGAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
    "GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGAWWWWAGGGGGGGGGGGGGGGGGGGGGGGGGGG",
]

# The hill. Two blocks up, with the block beneath filled, so the cliff is solid
# and only the top wears a grass cap. Neither the river nor the roads climb it.
UPPER = [
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "...............................GGGGGGG..........................",
    ".............................GGGGGGGGGGG........................",
    "...........................GGGGGGGGGGGGGGG......................",
    "...........................GGGGGGGGGGGGGGG......................",
    "..........................GGGGGGGGGGGGGGGGG.....................",
    "..........................GGGGGGGGGGGGGGGGG.....................",
    ".........................GGGGGGGGGGGGGGGGGGG....................",
    "..........................GGGGGGGGGGGGGGGGG.....................",
    "..........................GGGGGGGGGGGGGGGGG.....................",
    "...........................GGGGGGGGGGGGGGG......................",
    "...........................GGGGGGGGGGGGGGG......................",
    ".............................GGGGGGGGGGG........................",
    "...............................GGGGGGG..........................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
]

CODE = {
    "G": "Terrain/grass",
    "D": "Terrain/dirt",
    "S": "Terrain/stone",
    "P": "Terrain/path",
    "W": "Terrain/water",
    "A": "Terrain/sand",
    "C": "Terrain/soil",
}

FILL = "Terrain/dirt"        # what a cliff is made of under its grass cap

TILE = 0.5                   # must match tilekit.SIZE
LIFT = 0.5                   # one block of height, = tilekit.HEIGHT
UPPER_BLOCKS = 2             # blocks the hill stands above the vale floor
# How far a water tile surface sits below the grid top. Must match the drop
# in Terrain/water, or a lily pad floats above its own pond.
WATER_DROP = 0.06

# The camera aims at THIS, not at the whole scene, which is what lets the
# landscape run off the frame instead of being fitted inside it.
# (centre col, centre row, width in tiles, depth in tiles)
FRAME = (21, 34, 21, 14)

# Buildings stand apart from other buildings by this much ground beyond their
# own footprints. Overlap and crowding are different faults: five houses 20 cm
# apart pass an overlap test and read as a terrace.
BUILDING_CLEARANCE = 1.30
CHAINING = ("Buildings/fence", "Buildings/bridge")

# Only these are held apart. Everything else is dressing and may touch -- a
# field is contiguous crop rows by definition, and flowers beside tall grass is
# not a collision.
BULKY = ("Buildings/", "Nature/tree", "Nature/pine")
OVERLAP_TOL = 0.02


def is_bulky(aid):
    return any(aid.startswith(b) for b in BULKY)


def wants_clearance(aid):
    return aid.startswith("Buildings/") and aid not in CHAINING


# --------------------------------------------------------------------- props
# PLACED BY HAND, not solved. A solver only knows "somewhere it fits", and what
# makes a village read as a village is houses standing ALONG a road facing it --
# a relationship a fitting algorithm has no notion of.
#
# Yaw faces each building at the road it belongs to. Everything fronts -Y, so
# yaw 0 faces south (down-screen), 180 faces north.
BUILDINGS = [
    # The main street, north side, facing south onto the road.
    ("Buildings/cottage", 3, 28, 0.0, 1.0),
    ("Buildings/hut", 10, 28, 0.0, 1.0),
    ("Buildings/cottage", 17, 28, 0.0, 1.0),
    # South side, facing north back across it.
    ("Buildings/hut", 7, 38, 180.0, 1.0),
    ("Buildings/cottage", 14, 38, 180.0, 1.0),
    ("Buildings/well", 20, 37, 0.0, 1.0),
    # East of the river, where the road climbs toward the hill.
    ("Buildings/hut", 33, 29, 200.0, 1.0),
    ("Buildings/market_stall", 33, 37, 180.0, 1.0),
    # The shrine crowns the hill, alone, which is the whole point of it.
    ("Buildings/shrine", 34, 19, 180.0, 1.0),
]

# Runs. A fence is a line and a bridge is a crossing; both are seeded before
# anything else and everything is fitted around them.
RUNS = (
    # The bridge carries the road over the river. ONE row, not three: the deck
    # is 0.68 m deep against a 0.5 m grid, so laying it in adjacent rows
    # overlaps each section with its neighbour by 18 cm. It chains along X and
    # only along X -- the run axis is a property of the asset, not a choice
    # made here.
    [("Buildings/bridge", c, 33, 0.0, 1.0) for c in range(23, 29)]
    # A fence along the north side of the street, breaking either side of each
    # house so the run reads as boundary rather than as a barricade.
    + [("Buildings/fence", c, 30, 0.0, 1.0) for c in range(2, 10)]
    + [("Buildings/fence", c, 30, 0.0, 1.0) for c in range(14, 18)]
    + [("Buildings/fence", c, 36, 0.0, 1.0) for c in range(10, 14)]
)

# Nature, placed by zone. Deliberately sparse near the road and dense away from
# it: the eye needs somewhere to rest, and an evenly-scattered landscape reads
# as wallpaper.
WOODS = [
         (3, 43), (6, 45), (9, 44), (2, 40), (6, 41), (10, 47), (13, 44),
         (4, 36), (16, 46), (10, 41), (44, 30), (46, 36), (43, 41), (45, 44), (41, 25), (46, 18), (43, 14), (39, 43), (36, 46), (33, 43)
]
PINES = [
         (38, 16), (41, 20), (30, 15), (44, 23), (36, 13), (2, 22), (5, 18),
         (3, 13), (7, 12), (45, 11)
]
SCATTER_BUSH = [(9, 35), (17, 35), (25, 29), (30, 31), (35, 35), (12, 22),
                (20, 18), (28, 43), (18, 42), (8, 31), (40, 34), (22, 13),
                (33, 40), (15, 15), (2, 30), (47, 28)]
SCATTER_FLOWER = [(6, 31), (10, 31), (16, 31), (21, 31), (26, 36), (31, 31),
                  (36, 31), (12, 36), (18, 36), (23, 43), (29, 30), (34, 32),
                  (8, 26), (13, 19), (39, 29), (43, 32), (19, 22), (25, 40)]
SCATTER_GRASS = [(4, 32), (9, 32), (13, 32), (18, 32), (22, 31), (27, 30),
                 (32, 32), (37, 32), (41, 32), (45, 32), (7, 22), (11, 26),
                 (16, 40), (21, 26), (26, 22), (31, 44), (36, 26), (40, 39),
                 (44, 26), (3, 27), (17, 18), (29, 18), (42, 36), (14, 13)]
ROCKS = [(24, 16), (28, 25), (19, 12), (23, 37), (30, 21), (38, 38), (42, 44),
         (7, 16), (35, 29), (12, 12), (26, 46), (46, 40)]
REEDS = [(21, 15), (22, 21), (23, 27), (28, 30), (29, 36), (31, 41), (33, 46),
         (13, 11), (17, 13), (25, 18), (30, 39), (34, 44), (20, 24), (26, 31)]
LILIES = [(11, 11), (13, 15), (16, 19), (19, 23), (22, 27), (26, 33), (28, 37),
          (31, 42), (33, 46), (15, 17), (24, 30), (29, 40)]
LOGS = [(6, 39), (12, 45), (41, 37), (44, 16)]
STUMPS = [(9, 40), (15, 43), (39, 40), (42, 18)]


def _grid(layer):
    out = {}
    for row, line in enumerate(layer):
        for col, ch in enumerate(line):
            if ch != ".":
                out[(col, row)] = ch
    return out


ROWS = len(LOWER)
COLS = max(len(r) for r in LOWER)
OX = -(COLS - 1) * TILE * 0.5
OY = -(ROWS - 1) * TILE * 0.5


def world(col, row):
    """Tile centre in world space. Row 0 is the FAR edge, so rows run -Y."""
    return (OX + col * TILE, OY + (ROWS - 1 - row) * TILE)


def _kind(lower, upper, col, row):
    return upper.get((col, row)) or lower.get((col, row))


def _prototype(aid, cache):
    """Build an asset once and instance it. One mesh, many transforms --
    cheap here, and honest about what MultiMesh does in the engine."""
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
    # The origin has to be the floor contact point or placement buries the
    # asset by however tall its first part happens to be. See kit.floor_origin.
    kit.floor_origin(proto)
    lo = min(v.co.z for v in proto.data.vertices)
    if abs(lo) > 1e-4:
        raise SystemExit("FAIL: %s prototype sits at local z=%.4f after "
                         "floor_origin; placement would bury it." % (aid, lo))
    proto.hide_render = True
    cache[aid] = proto
    return proto


def _place(proto, location, yaw=0.0, scale=1.0):
    dup = proto.copy()
    dup.data = proto.data
    dup.hide_render = False
    dup.location = location
    dup.rotation_euler = (0.0, 0.0, math.radians(yaw))
    dup.scale = (scale, scale, scale)
    bpy.context.scene.collection.objects.link(dup)
    return dup


def _check_spacing(entries):
    """Fail if two bulky props are inside each other, or two buildings crowd.

    Clearance applies to a PAIR, not to a prop: inflating a house against a
    fence would push every fence a metre off the thing it encloses, and a fence
    along a cottage wall is a garden.
    """
    big = [e for e in entries if is_bulky(e[0])]
    clashes = []
    for i in range(len(big)):
        aid_a, ax, ay, aw, ad = big[i]
        for j in range(i + 1, len(big)):
            aid_b, bx, by, bw, bd = big[j]
            pad = (BUILDING_CLEARANCE
                   if wants_clearance(aid_a) and wants_clearance(aid_b) else 0.0)
            gx = abs(ax - bx) - (aw + bw) * 0.5 - pad
            gy = abs(ay - by) - (ad + bd) * 0.5 - pad
            if gx < -OVERLAP_TOL and gy < -OVERLAP_TOL:
                clashes.append("%s and %s are %.2f x %.2f m too close%s"
                               % (aid_a, aid_b, -gx, -gy,
                                  " (plus %.2f m clearance)" % pad if pad
                                  else " (footprints overlap)"))
    if clashes:
        raise SystemExit("FAIL: %d placement(s) too close:%s  %s"
                         % (len(clashes), chr(10), (chr(10) + "  ").join(clashes)))


def _check_ground(entries, tiles):
    """Fail if a building stands on ground that is not there, or on water.

    A tile being land says nothing about a 2.15 m building CENTRED on it. The
    footprint is sampled on the tile grid with ceil, because a 1.67 m building
    spans more than three 0.5 m tiles and rounding down let one hang a third of
    itself over open water.
    """
    bad = []
    for aid, col, row, w, d in entries:
        if not aid.startswith("Buildings/") or aid in CHAINING:
            continue
        hc = int(math.ceil(w / TILE / 2.0))
        hr = int(math.ceil(d / TILE / 2.0))
        off = [(col + i, row + j)
               for i in range(-hc, hc + 1) for j in range(-hr, hr + 1)
               if tiles.get((col + i, row + j)) not in ("G", "P", "C")]
        if off:
            bad.append("%s at (%d, %d) stands on %d cell(s) that are water, "
                       "bank, or nothing at all" % (aid, col, row, len(off)))
    if bad:
        raise SystemExit("FAIL: %d building(s) on bad ground:%s  %s"
                         % (len(bad), chr(10), (chr(10) + "  ").join(bad)))


def _check_seating(placed_props):
    """Every prop must stand ON the ground under it, not in it or above it.

    The fault this exists for was invisible for four scene renders: a merged
    prototype inherits the origin of its first part, so placing it at the tile
    top buried it by that part's half-height. The cottage was 0.84 m under, the
    ground tiles were 0.175 m out, and the whole scene sat on a datum nobody
    had checked because every PER-ASSET measurement is taken where the asset was
    built, and a thing measured where it was built is always right.

    So the check is on the assembled scene and it compares world space against
    the expected ground height, which is the only place the fault can show.
    """
    bad = []
    for aid, ob, expect_z in placed_props:
        lo = min((ob.matrix_world @ v.co).z for v in ob.data.vertices)
        if abs(lo - expect_z) > 0.01:
            bad.append("%s base at z=%.3f, ground at z=%.3f (%s by %.3f m)"
                       % (aid, lo, expect_z,
                          "sunk" if lo < expect_z else "floating",
                          abs(lo - expect_z)))
    if bad:
        shown = bad[:8]
        more = ("" if len(bad) <= 8
                else "%s  ... and %d more" % (chr(10), len(bad) - 8))
        raise SystemExit("FAIL: %d prop(s) not seated on the ground:%s  %s%s"
                         % (len(bad), chr(10), (chr(10) + "  ").join(shown), more))


def build():
    """Assemble the vale. Returns (placed objects, framing box)."""
    cache = {}
    placed = []
    lower = _grid(LOWER)
    upper = _grid(UPPER)
    topmost = {}
    for key in lower:
        topmost[key] = upper.get(key) or lower[key]

    props = list(RUNS) + list(BUILDINGS)
    for aid, cells, yaws, scales in (
            ("Nature/tree", WOODS, (24.0, -37.0, 128.0, 61.0, -95.0), (1.0, 0.9, 0.95)),
            ("Nature/pine", PINES, (12.0, -88.0, 44.0), (1.0, 0.92, 1.05)),
            ("Nature/bush", SCATTER_BUSH, (15.0, 122.0, -60.0, 78.0), (1.0, 0.85)),
            ("Nature/flowers", SCATTER_FLOWER, (15.0, -40.0, 70.0), (1.0,)),
            ("Nature/tall_grass", SCATTER_GRASS, (25.0, -60.0, 100.0), (1.0,)),
            ("Nature/rock", ROCKS, (33.0, -12.0, 71.0), (1.0, 0.8, 0.9)),
            ("Nature/reeds", REEDS, (0.0, 65.0, -30.0), (1.0, 0.9)),
            ("Nature/lily_pad", LILIES, (20.0, -55.0, 110.0), (1.0, 0.9)),
            ("Nature/log", LOGS, (-25.0, 60.0), (1.0,)),
            ("Nature/stump", STUMPS, (12.0, 95.0), (1.0,))):
        for i, (col, row) in enumerate(cells):
            props.append((aid, col, row, yaws[i % len(yaws)],
                          scales[i % len(scales)]))
    # Every crop tile grows something. A field with gaps reads as a failed one.
    for (col, row), ch in sorted(lower.items()):
        if ch == "C" and (col, row) not in upper:
            props.append(("Nature/crop_row", col, row, 0.0, 1.0))

    # Guards run on the declared footprints BEFORE anything is built: a
    # placement fault should cost a second, not a whole landscape.
    found = registry.discover()
    boxes, ground = [], []
    for aid, col, row, yaw, scale in props:
        if (col, row) not in lower:
            raise SystemExit("FAIL: prop %s is at (%d, %d), which is off the map."
                             % (aid, col, row))
        fx, fy = found[aid]["decl"]["footprint"]
        x, y = world(col, row)
        boxes.append((aid, x, y, fx * scale, fy * scale))
        ground.append((aid, col, row, fx * scale, fy * scale))
    _check_ground(ground, topmost)
    _check_spacing(boxes)

    # Ground.
    for (col, row), ch in sorted(lower.items()):
        x, y = world(col, row)
        placed.append(_place(_prototype(CODE[ch], cache), (x, y, 0.0)))
    for (col, row), ch in sorted(upper.items()):
        x, y = world(col, row)
        for block in range(1, UPPER_BLOCKS):
            placed.append(_place(_prototype(FILL, cache), (x, y, LIFT * block)))
        placed.append(_place(_prototype(CODE[ch], cache),
                             (x, y, LIFT * UPPER_BLOCKS)))

    # Props, on whichever layer is topmost under them. A tile TOP is its base
    # plus one block, so a prop on the vale floor stands at LIFT and one on the
    # hill stands at LIFT * (UPPER_BLOCKS + 1). Water sits a little lower, and
    # anything on it is seated to the water surface rather than the bank.
    seated = []
    for aid, col, row, yaw, scale in props:
        on_hill = (col, row) in upper
        blocks = UPPER_BLOCKS + 1 if on_hill else 1
        z = LIFT * blocks
        if not on_hill and lower.get((col, row)) == "W":
            z -= WATER_DROP
        x, y = world(col, row)
        ob = _place(_prototype(aid, cache), (x, y, z), yaw, scale)
        placed.append(ob)
        seated.append((aid, ob, z))
    bpy.context.view_layer.update()
    _check_seating(seated)

    # The framing box. Hidden from the render, and the ONLY thing the camera
    # solver is given -- so it frames this region and lets the landscape run
    # off every edge, instead of shrinking the whole map to fit the frame.
    fc, fr, fw, fd = FRAME
    cx, cy = world(fc, fr)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, LIFT * 1.6))
    box = bpy.context.object
    box.name = "FRAME_REGION"
    box.scale = (fw * TILE, fd * TILE, LIFT * 3.2)
    box.hide_render = True
    bpy.context.view_layer.update()
    return placed, box
