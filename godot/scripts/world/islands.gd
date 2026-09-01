extends RefCounted
class_name Islands

## The archipelago: a small island you start on, and more you buy with Faith.
##
## Generated rather than authored, and emitted in EXACTLY the schema
## `data/vale.json` uses -- same keys, same tile codes, same prop records. That
## is the whole trick that makes this cheap: the ground builder, the walk grid,
## the hover picker and the FX layer all keep reading one shape of document and
## none of them needs to know the world is now procedural. A second, parallel
## "island renderer" would have been a second answer to every question the
## builder already answers, and the two would disagree within a week.
##
## Islands sit on a coarse grid with open water between them. Buying one
## generates its terrain and its scatter AND lays a bridge to whichever
## unlocked neighbour it touches -- without that the new island is scenery,
## because nothing in this game can swim.

## Tiles across one island's bounding box.
##
## Sized against the BUILDINGS, not by eye. At 15 the island was 11 tiles of
## land across and the four starting structures blocked 99 of its 117 walkable
## cells with their footprints -- the scatter could then place almost nothing,
## and the walk grid came back with four disconnected pockets of two or three
## tiles each. A cottage is 2.2 m on a 0.5 m tile, so it costs a 7x7 hole; the
## island has to be several of those across before it is a place rather than a
## plinth.
const SPAN := 25
const GAP := 6            ## tiles of water between neighbours
const PITCH := SPAN + GAP
const GRID := 3           ## GRID x GRID slots
const MARGIN := 3         ## water border around the whole archipelago

const TILE := 0.5
const LIFT := 0.5

## What each island costs, by how many you already own. Rising, so the second
## island is a goal and the ninth is an achievement.
const PRICE := [0, 40, 90, 160, 260, 380, 520, 700, 900]

## Population room each island adds. The first is deliberately tiny: five
## people on a small island is a village you can actually watch, which is the
## whole reason the slice starts here.
const POP_PER_ISLAND := 5

## Typed, because a bare array literal yields Variant elements and every
## Vector2i arithmetic off one is then untyped.
const FOUR_WAY: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0),
								   Vector2i(0, 1), Vector2i(0, -1)]
## Only two directions: a bridge is shared between two islands, and laying all
## four would build every span twice.
const EAST_SOUTH: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]

var unlocked: Dictionary = {}      ## Vector2i slot -> true
var rng := RandomNumberGenerator.new()
var _seed := 20260901


func _init(seed_value := 20260901) -> void:
	_seed = seed_value
	rng.seed = seed_value
	unlocked[Vector2i(GRID / 2, GRID / 2)] = true      ## the middle one


func cols() -> int:
	return GRID * PITCH - GAP + MARGIN * 2


func rows() -> int:
	return cols()


func count() -> int:
	return unlocked.size()


func pop_cap() -> int:
	return count() * POP_PER_ISLAND


func price_next() -> int:
	var n := count()
	return PRICE[n] if n < PRICE.size() else PRICE[PRICE.size() - 1] + 200


## Slots that are not owned but touch one that is. The only ones you may buy:
## an island across open water with no neighbour would be unreachable, and
## selling the player something nobody can walk to is a bug with a price tag.
func buyable() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for s in unlocked:
		for d in FOUR_WAY:
			var n: Vector2i = s + d
			if n.x < 0 or n.y < 0 or n.x >= GRID or n.y >= GRID:
				continue
			if unlocked.has(n) or out.has(n):
				continue
			out.append(n)
	out.sort_custom(func(a, b): return a.y * GRID + a.x < b.y * GRID + b.x)
	return out


func unlock(slot: Vector2i) -> bool:
	if unlocked.has(slot) or not buyable().has(slot):
		return false
	unlocked[slot] = true
	return true


## Which island a tile belongs to, or (-1,-1) for open water. Used to decide
## where a new follower may appear and which island a miracle landed on.
func slot_of_cell(cell: Vector2i) -> Vector2i:
	for s in unlocked:
		var o: Vector2i = _origin(s)
		if cell.x >= o.x and cell.y >= o.y \
				and cell.x < o.x + SPAN and cell.y < o.y + SPAN:
			return s
	return Vector2i(-1, -1)


func _origin(slot: Vector2i) -> Vector2i:
	return Vector2i(MARGIN + slot.x * PITCH, MARGIN + slot.y * PITCH)


## --- generation -------------------------------------------------------------

## Build the whole document from scratch. Cheap enough to call on every
## purchase (a 60x60 grid of characters), and regenerating everything rather
## than patching in the new island means the two paths cannot diverge -- there
## is only one path.
func build_doc() -> Dictionary:
	var n := cols()
	var ground: Array = []
	for r in n:
		var line := ""
		for c in n:
			line += "W"
		ground.append(line)

	var props: Array = []
	for s in unlocked:
		_carve(ground, s)
	# Bridges after all the land exists, or a span would be laid toward a coast
	# that has not been carved yet and would land in open water.
	for s in unlocked:
		_bridge(ground, props, s)
	for s in unlocked:
		_scatter(props, ground, s)

	var flat: Array = []
	for r in n:
		var line := ""
		for c in n:
			line += "."
		flat.append(line)

	return {
		"cols": n, "rows": n, "tile": TILE, "lift": LIFT,
		"upper_blocks": 2, "water_drop": 0.06,
		"code": {"G": "Terrain/grass", "D": "Terrain/dirt",
				 "S": "Terrain/stone", "P": "Terrain/path",
				 "W": "Terrain/water", "A": "Terrain/sand",
				 "C": "Terrain/soil"},
		"fill": "Terrain/dirt",
		"lower": ground, "upper": flat, "props": props,
	}


## Stamp one island's ground into the character grid.
##
## A rounded blob rather than a square: an island with corners reads as a
## platform. The radius wobbles with a couple of sine terms so no two slots
## come out the same shape, seeded off the slot so a given island is always
## itself no matter what order they were bought in.
func _carve(ground: Array, slot: Vector2i) -> void:
	var o := _origin(slot)
	var mid := float(SPAN - 1) * 0.5
	var r := RandomNumberGenerator.new()
	r.seed = _seed + slot.x * 7919 + slot.y * 104729
	var wob_a := r.randf_range(0.0, TAU)
	var wob_b := r.randf_range(0.0, TAU)

	for j in SPAN:
		for i in SPAN:
			var dx := float(i) - mid
			var dy := float(j) - mid
			var dist := sqrt(dx * dx + dy * dy)
			var ang := atan2(dy, dx)
			var edge := mid * (0.86 + 0.10 * sin(ang * 3.0 + wob_a)
									+ 0.06 * sin(ang * 5.0 + wob_b))
			if dist > edge:
				continue
			# A sand ring where the land meets the water, so the coast reads as
			# a beach instead of grass stopping dead.
			var ch := "A" if dist > edge - 1.35 else "G"
			_put(ground, o.x + i, o.y + j, ch)


func _put(ground: Array, col: int, row: int, ch: String) -> void:
	if row < 0 or row >= ground.size():
		return
	var line: String = ground[row]
	if col < 0 or col >= line.length():
		return
	ground[row] = line.substr(0, col) + ch + line.substr(col + 1)


func _char_at(ground: Array, col: int, row: int) -> String:
	if row < 0 or row >= ground.size():
		return "W"
	var line: String = ground[row]
	if col < 0 or col >= line.length():
		return "W"
	return line[col]


## Lay a bridge from this island to its neighbour to the east and to the south,
## if those are unlocked. Only two of the four directions, because a bridge is
## shared and doing all four would build every span twice.
func _bridge(ground: Array, props: Array, slot: Vector2i) -> void:
	for d in EAST_SOUTH:
		var other: Vector2i = slot + d
		if not unlocked.has(other):
			continue
		var a := _origin(slot)
		var mid := SPAN / 2
		# Walk out from the middle of this island toward the neighbour and lay
		# deck over every water tile until land resumes. Measuring the span
		# rather than assuming GAP tiles is what makes it survive the wobbly
		# coastline: the two shores are not where the bounding boxes are.
		var col := a.x + mid
		var row := a.y + mid
		var step: Vector2i = d
		var laid := 0
		var guard := PITCH * 2
		# Advance to the first water tile.
		while guard > 0 and _char_at(ground, col, row) != "W":
			col += step.x
			row += step.y
			guard -= 1
		while guard > 0 and _char_at(ground, col, row) == "W":
			props.append({"id": "Buildings/bridge", "col": col, "row": row,
						  "yaw": 0.0 if d.y != 0 else 90.0, "scale": 1.0,
						  "fp": [0.5, 0.68]})
			laid += 1
			col += step.x
			row += step.y
			guard -= 1


## Everything that stands on an island. Seeded off the slot so an island keeps
## its own character, and placed by rejection sampling against what is already
## there -- two cottages in the same square metre is the failure mode, and it
## is cheaper to retry a point than to write a packing algorithm.
func _scatter(props: Array, ground: Array, slot: Vector2i) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = _seed + slot.x * 31337 + slot.y * 6971
	var o := _origin(slot)
	var taken: Dictionary = {}
	for p in props:
		taken[Vector2i(int(p["col"]), int(p["row"]))] = 2.0

	var home := slot == Vector2i(GRID / 2, GRID / 2)
	# The starting island is furnished; the rest are wild until the villagers
	# get there. That is what makes buying one feel like frontier rather than
	# like being handed a second village.
	var plan: Array = []
	if home:
		plan = [["Buildings/hut", 2, 3.0], ["Buildings/cottage", 1, 3.2],
				["Buildings/market_stall", 1, 2.6], ["Buildings/well", 1, 2.2],
				["Nature/crop_row", 18, 0.55], ["Nature/tree", 6, 1.4],
				["Nature/bush", 5, 1.0], ["Nature/rock", 4, 1.0],
				["Nature/flowers", 8, 0.7], ["Nature/tall_grass", 12, 0.5]]
	else:
		plan = [["Nature/tree", 9, 1.4], ["Nature/pine", 4, 1.4],
				["Nature/bush", 6, 1.0], ["Nature/rock", 5, 1.0],
				["Nature/log", 2, 1.0], ["Nature/flowers", 7, 0.7],
				["Nature/tall_grass", 14, 0.5], ["Nature/stump", 3, 0.9]]

	for entry in plan:
		var aid := String(entry[0])
		var want := int(entry[1])
		var clear := float(entry[2])
		var placed := 0
		for attempt in want * 40:
			if placed >= want:
				break
			var i := r.randi_range(1, SPAN - 2)
			var j := r.randi_range(1, SPAN - 2)
			var col := o.x + i
			var row := o.y + j
			# Grass only. Building on the sand ring puts a cottage half in the
			# sea, and the coast is what makes the island read as an island.
			if _char_at(ground, col, row) != "G":
				continue
			var cell := Vector2i(col, row)
			if _too_close(taken, cell, clear):
				continue
			taken[cell] = clear
			props.append({"id": aid, "col": col, "row": row,
						  "yaw": r.randf_range(0.0, 360.0), "scale": 1.0,
						  "fp": _footprint(aid)})
			placed += 1


## Is `cell` too near something already placed?
##
## The required gap is the SUM of the two half-extents, not the larger of the
## two radii. With max() a tuft of grass had to stand three metres from a hut,
## because the hut's own clearance applied to everything it was compared
## against -- and on a twelve-metre island that rejected 44 of 58 props and
## left it looking abandoned. Half-sum is the honest question: do these two
## things overlap.
func _too_close(taken: Dictionary, cell: Vector2i, clear: float) -> bool:
	for other in taken:
		var o: Vector2i = other
		var need: float = (clear + float(taken[other])) * 0.5
		var d := Vector2(cell.x - o.x, cell.y - o.y).length() * TILE
		if d < need:
			return true
	return false


## Declared footprints, matching what the Blender export stamps into vale.json.
## Kept here because a generated prop has no declaration to travel with it, and
## the walk grid blocks buildings by this number -- guess it small and
## followers walk through walls.
const FOOTPRINTS := {
	"Buildings/hut": [2.0, 2.0], "Buildings/cottage": [2.2, 2.2],
	"Buildings/market_stall": [1.6, 1.2], "Buildings/well": [1.0, 1.0],
	"Buildings/shrine": [1.6, 1.6], "Buildings/bridge": [0.5, 0.68],
}


func _footprint(aid: String) -> Array:
	return FOOTPRINTS.get(aid, [0.5, 0.5])
