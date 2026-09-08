extends RefCounted
class_name WalkGrid

## Where a follower may walk, and how to get from one place to another.
##
## Built once from the same `vale.json` the ground is built from, so the map a
## follower reasons about and the map you can see are the same map. Two sources
## would drift, and the one that drifts is always the invisible one.
##
## Rules, in the order they are applied:
##
##   WATER is not walkable. That is the whole point of the river: it divides
##   the vale, and a follower that wants the far bank has to find a crossing.
##   A BRIDGE tile puts the water back to walkable, so the bridges are the
##   crossings and there are no others.
##
##   BUILDINGS block their declared footprint. The footprint travels in
##   vale.json with the prop, because the declaration is the only honest source
##   -- re-deriving it from the mesh here would be a second answer to a
##   question that already has one, and the two would disagree the day someone
##   edits a builder.
##
##   TREES, rocks, logs and stumps block a single tile. Scatter -- flowers,
##   grass, reeds, lily pads -- blocks nothing; a follower walking through a
##   tuft of grass is correct.
##
##   The HILL is not walkable at all, and that is a KNOWN GAP rather than a
##   decision. Nothing in the asset library is a ramp or a stair, so the high
##   ground has no connection to the vale floor; making it walkable would let
##   followers step up a two-block cliff. It needs a ramp asset. Until then the
##   shrine is scenery.

const BLOCK_SINGLE := ["Nature/tree", "Nature/pine", "Nature/rock",
					   "Nature/log", "Nature/stump"]
const BRIDGE := "Buildings/bridge"
const NEIGHBOURS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0),
									 Vector2i(0, 1), Vector2i(0, -1)]

## How far out to look for somewhere to stand next to a thing. Must exceed the
## half-footprint of the biggest building in tiles; the cottage is the current
## worst case at 3, so this has real headroom rather than a hard-won exact fit.
const MAX_BESIDE := 7

var cols := 0
var rows := 0
var tile := 0.5
var lift := 0.5

var _solid: PackedByteArray = PackedByteArray()
var _astar := AStarGrid2D.new()
var _by_id: Dictionary = {}          ## asset id -> Array[Vector2i] of its cells
var _walkable_cells: Array[Vector2i] = []
## The ground layer, kept so callers can ask what KIND of tile a cell is and
## not merely whether it can be stood on. Building sites need that: a hut in
## the middle of the road is walkable ground and still the wrong place.
var _lower: Array = []
## Cells covered by a BUILDING footprint, as distinct from cells blocked by a
## tree. A building site may not sit on another building; a tree standing in
## the way is cleared to make room, the way clearing land actually works.
var _built: PackedByteArray = PackedByteArray()
## Which connected walkable region each cell belongs to, -1 for none. Filled by
## the same flood fill that counts them.
var _region: PackedInt32Array = PackedInt32Array()
## Solidity from the GROUND alone, before any prop is considered. Terrain only
## changes when land is bought; props change every time a tree falls. Keeping
## the two apart is what lets rebuild_props be cheap.
var _terrain: PackedByteArray = PackedByteArray()
var _quiet := false


func build(doc: Dictionary) -> void:
	cols = int(doc.get("cols", 0))
	rows = int(doc.get("rows", 0))
	tile = float(doc.get("tile", 0.5))
	lift = float(doc.get("lift", 0.5))
	var lower: Array = doc.get("lower", [])
	var upper: Array = doc.get("upper", [])
	_lower = lower

	_solid.resize(cols * rows)
	_solid.fill(1)
	_built.resize(cols * rows)
	_built.fill(0)

	for row in rows:
		for col in cols:
			var lo := _code(lower, col, row)
			var up := _code(upper, col, row)
			# Ground that does not exist, water, and anything on the hill are
			# all solid at this stage. Bridges open the water again below.
			var ok := lo != "." and lo != "W" and up == "."
			_solid[row * cols + col] = 0 if ok else 1
	_terrain = _solid.duplicate()

	# Props. Bridges FIRST, so a bridge deck beats the water underneath it, and
	# blockers after, so nothing re-opens ground a building stands on.
	_apply_props(doc.get("props", []))

	_astar.region = Rect2i(0, 0, cols, rows)
	_astar.cell_size = Vector2(1, 1)
	# Diagonals only where both orthogonal neighbours are open, or a follower
	# cuts the corner of a cottage and walks through its wall.
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	for row in rows:
		for col in cols:
			if _solid[row * cols + col] == 1:
				_astar.set_point_solid(Vector2i(col, row), true)
			else:
				_walkable_cells.append(Vector2i(col, row))

	if not _quiet:
		print("[WALK] %d of %d cells walkable, %d blocked, %d bridge decks"
			% [_walkable_cells.size(), cols * rows,
			   (cols * rows) - _walkable_cells.size(),
			   (_by_id.get(BRIDGE, []) as Array).size()])
	_report_regions()


## How many DISCONNECTED walkable regions are there, and how big.
##
## This is the check that catches a bridge which does not actually reach both
## banks. A pathfinder cannot tell you that: it simply returns no route, the
## follower shrugs and wanders locally, and the village looks fine while half
## of it is quietly unreachable. A flood fill says it out loud at startup.
## The prop layer, on top of whatever the terrain already said.
func _apply_props(props: Array) -> void:
	# Bridges FIRST, so a bridge deck beats the water underneath it, and
	# blockers after, so nothing re-opens ground a building stands on.
	for p in props:
		var aid := String(p["id"])
		var cell := Vector2i(int(p["col"]), int(p["row"]))
		if not _by_id.has(aid):
			_by_id[aid] = []
		(_by_id[aid] as Array).append(cell)
		if aid == BRIDGE and _inside(cell):
			_solid[cell.y * cols + cell.x] = 0
	for p in props:
		var aid := String(p["id"])
		var cell := Vector2i(int(p["col"]), int(p["row"]))
		if aid == BRIDGE:
			continue
		if aid.begins_with("Buildings/"):
			var fp: Array = p.get("fp", [0.5, 0.5])
			var sc := float(p.get("scale", 1.0))
			_block_footprint(cell, float(fp[0]) * sc, float(fp[1]) * sc)
			_mark_built(cell, float(fp[0]) * sc, float(fp[1]) * sc)
		elif aid in BLOCK_SINGLE:
			_block_cell(cell)


## Redo the PROPS only, keeping the terrain, the AStar grid and its settings.
##
## A tree falling changes one cell, and rebuilding the whole grid for it cost
## 30 ms -- a two-frame stall, more than once a second in a busy village, which
## is what "the game just runs slow" was. The expensive parts of build() are
## AStarGrid2D.update(), which reallocates all ~10,000 points, and the 10,000
## set_point_solid calls that follow it. Neither depends on the props.
##
## So the terrain solidity is kept from the last full build, the prop layer is
## laid on top of a copy of it, and only the cells whose solidity ACTUALLY
## CHANGED are pushed into the pathfinder.
func rebuild_props(doc: Dictionary) -> void:
	if _terrain.is_empty():
		build(doc)
		return
	_quiet = true
	var was := _solid.duplicate()
	_solid = _terrain.duplicate()
	_built.fill(0)
	_by_id.clear()
	_apply_props(doc.get("props", []))

	_walkable_cells.clear()
	for row in rows:
		var base := row * cols
		for col in cols:
			var i := base + col
			var solid := _solid[i] == 1
			if not solid:
				_walkable_cells.append(Vector2i(col, row))
			if (was[i] == 1) != solid:
				_astar.set_point_solid(Vector2i(col, row), solid)
	_report_regions()


## The fill also RECORDS which region each cell is in, and that is the half
## that matters. Reporting alone left the problem exactly as described above:
## measured on a live village, 620 of 1078 decisions -- 57% -- ended in "no
## route", because a villager on the main landmass kept choosing the nearest
## tree without ever asking whether it was on the same side of the river.
## A villager may now only want what it can actually walk to.
func _report_regions() -> void:
	var seen := {}
	var sizes: Array[int] = []
	_region = PackedInt32Array()
	_region.resize(cols * rows)
	_region.fill(-1)
	var next_id := 0
	for start in _walkable_cells:
		if seen.has(start):
			continue
		var id := next_id
		next_id += 1
		var n := 0
		var stack: Array[Vector2i] = [start]
		seen[start] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			_region[c.y * cols + c.x] = id
			n += 1
			for d in NEIGHBOURS:
				var nb: Vector2i = c + d
				if is_walkable(nb) and not seen.has(nb):
					seen[nb] = true
					stack.append(nb)
		sizes.append(n)
	sizes.sort()
	sizes.reverse()
	var head: Array[String] = []
	for i in mini(4, sizes.size()):
		head.append(str(sizes[i]))
	if not _quiet:
		print("[WALK] %d disconnected region(s); largest: %s%s"
			% [sizes.size(), ", ".join(head),
			   "" if sizes.size() == 1 else
			   "  <- anything not in the largest is unreachable from it"])


## Every cell somebody can stand on. Returned by reference -- callers read it,
## they do not own it.
func walkable_cells() -> Array[Vector2i]:
	return _walkable_cells


## Which connected region a cell is in. -1 when it is not walkable at all, or
## when the cell is off the map -- both mean "you cannot get there".
func region_of(c: Vector2i) -> int:
	if not _inside(c) or _region.is_empty():
		return -1
	return _region[c.y * cols + c.x]


## Can somebody standing at `a` get TO OR BESIDE `b`?
##
## Answered from the flood fill rather than by running A*, so it costs an array
## lookup and can be asked about every candidate target before one is chosen.
##
## "Or beside" is the whole subtlety. Targets are usually PROPS -- a tree, a
## bush, a rock -- and a prop's own cell is blocked, so its region is -1. A
## first version compared regions directly and therefore judged every resource
## in the world unreachable: villagers stopped chopping entirely, wood sat at
## 0/16 for ten minutes, no hut was ever raised and no age was ever reached.
## They fell back on `sow`, which targets open ground and so still passed, and
## laid 81 crop rows in a village with no buildings.
##
## So an unwalkable target is judged by the ground around it, which is where
## the villager would actually stand -- the same cell `beside` hands back.
func reachable(a: Vector2i, b: Vector2i) -> bool:
	var ra := region_of(a)
	if ra < 0:
		return true          # caller is nowhere sensible; do not veto on that
	if ra == region_of(b):
		return true
	for d in NEIGHBOURS:
		if region_of(b + d) == ra:
			return true
	return false


func _code(layer: Array, col: int, row: int) -> String:
	if row < 0 or row >= layer.size():
		return "."
	var line: String = layer[row]
	if col < 0 or col >= line.length():
		return "."
	return line[col]


func _inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows


func _block_cell(c: Vector2i) -> void:
	if _inside(c):
		_solid[c.y * cols + c.x] = 1


## Ceil, not int. A 2.15 m building spans more than four 0.5 m tiles and
## rounding down leaves a walkable strip THROUGH the wall -- the same off-by-a
## -tile that let a hut hang over the coast in the Blender containment guard.
func _block_footprint(centre: Vector2i, w: float, d: float) -> void:
	var hc := int(ceil(w / tile / 2.0))
	var hr := int(ceil(d / tile / 2.0))
	for i in range(-hc, hc + 1):
		for j in range(-hr, hr + 1):
			_block_cell(centre + Vector2i(i, j))


## The ground code at a cell: "G" grass, "P" road, "C" ploughed, "W" water...
func code_of(c: Vector2i) -> String:
	return _code(_lower, c.x, c.y)


func _mark_built(centre: Vector2i, w: float, d: float) -> void:
	var hc := int(ceil(w / tile / 2.0))
	var hr := int(ceil(d / tile / 2.0))
	for i in range(-hc, hc + 1):
		for j in range(-hr, hr + 1):
			var c := centre + Vector2i(i, j)
			if _inside(c):
				_built[c.y * cols + c.x] = 1


## Could a building stand here?
##
## Grass, and not already inside another building. Deliberately NOT
## `is_walkable` -- that also refuses any cell holding a tree or a rock, and
## with ~25 of those scattered per plot the strictest requirement (a 7x7 clear
## for a hut) had **zero** valid sites on the entire starting map. A hut could
## never be built anywhere, and the failure was silent: build actions were
## chosen, no destination was found, and the villagers wandered.
##
## Clearing a tree to raise a house is what actually happens, so a tree does
## not veto a site -- `ValeBuilder.add_prop` removes what stands in the
## footprint when the building goes up.
## One tile changed under us. Update the cache rather than rebuilding.
##
## A full build costs ~30 ms and the player is turning dirt to grass several
## times a second. Both are walkable, so the pathfinding does not move at all;
## what changes is `is_plain` and `is_buildable`, which read the codes straight
## out of this cache.
func set_code(c: Vector2i, ch: String) -> void:
	if not _inside(c) or c.y >= _lower.size():
		return
	var line: String = _lower[c.y]
	if c.x >= line.length():
		return
	_lower[c.y] = line.substr(0, c.x) + ch + line.substr(c.x + 1)


func is_buildable(c: Vector2i) -> bool:
	return (_inside(c) and _code(_lower, c.x, c.y) == "G"
			and _built[c.y * cols + c.x] == 0)


## Plain open grass: walkable, and not a road, a field, a bank or water.
##
## What a BUILDING SITE has to be. Anything walkable will do for standing on,
## which is why huts ended up straddling the road -- the site test asked the
## wrong question.
func is_plain(c: Vector2i) -> bool:
	return is_walkable(c) and _code(_lower, c.x, c.y) == "G"


func is_walkable(c: Vector2i) -> bool:
	return _inside(c) and _solid[c.y * cols + c.x] == 0


func world_of(c: Vector2i) -> Vector3:
	var ox := -float(cols - 1) * tile * 0.5
	var oz := -float(rows - 1) * tile * 0.5
	return Vector3(ox + c.x * tile, lift, oz + (rows - 1 - c.y) * tile)


func cell_of(world: Vector3) -> Vector2i:
	var ox := -float(cols - 1) * tile * 0.5
	var oz := -float(rows - 1) * tile * 0.5
	var col := int(round((world.x - ox) / tile))
	var row := (rows - 1) - int(round((world.z - oz) / tile))
	return Vector2i(col, row)


func random_cell(rng: RandomNumberGenerator) -> Vector2i:
	if _walkable_cells.is_empty():
		return Vector2i.ZERO
	return _walkable_cells[rng.randi_range(0, _walkable_cells.size() - 1)]


## Cells occupied by an asset kind, for "go stand near a tree".
func cells_of(asset_id: String) -> Array:
	return _by_id.get(asset_id, [])


## A walkable cell beside `c`, since the interesting things -- trees, doors --
## are themselves solid and cannot be stood on.
##
## Takes an optional rng and picks RANDOMLY among the cells at the nearest ring
## that has any. Returning the first hit in scan order instead would send every
## follower who ever wants this tree to the same cell on the same side of it,
## and two of them standing in the same half-metre is the single most obvious
## way for a village to stop looking alive.
##
## MAX_BESIDE has to clear the largest FOOTPRINT, not merely "be a bit of room".
## It was 3, and a cottage blocks 7x7 around its own centre -- so every cell the
## search could reach was inside the building and `beside()` returned "nowhere"
## for every house, shrine and well in the village. The visible symptom was not
## an error: followers simply never slept, prayed or washed, every one of those
## bars sat at zero, and the village looked merely unhappy rather than broken.
func beside(c: Vector2i, rng: RandomNumberGenerator = null) -> Vector2i:
	for r in range(1, MAX_BESIDE + 1):
		var ring: Array[Vector2i] = []
		for i in range(-r, r + 1):
			for j in range(-r, r + 1):
				# The ring only, not the filled square: the inner cells were
				# already offered at a smaller radius and rejected.
				if absi(i) != r and absi(j) != r:
					continue
				var n: Vector2i = c + Vector2i(i, j)
				if is_walkable(n):
					ring.append(n)
		if ring.is_empty():
			continue
		if rng == null:
			return ring[0]
		return ring[rng.randi_range(0, ring.size() - 1)]
	return Vector2i(-1, -1)


## World-space waypoints from one cell to another, or [] if unreachable.
##
## Unreachable is a normal answer, not an error: the river genuinely separates
## two halves of the vale except at the bridges, and the hill is cut off
## entirely. A caller that cannot handle [] will stand still forever.
func path_world(from: Vector2i, to: Vector2i) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if not is_walkable(from) or not is_walkable(to):
		return out
	var cells := _astar.get_id_path(from, to)
	for c in cells:
		out.append(world_of(c))
	return out
