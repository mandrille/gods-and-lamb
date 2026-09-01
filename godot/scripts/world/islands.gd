extends RefCounted
class_name Islands

## The archipelago: plain square plots you expand onto.
##
## Squares, not blobs. An organic coastline looked like landscape and read like
## nothing you could reason about -- the player could not tell where one plot
## ended, which side was buyable, or how much land a purchase actually bought.
## A square with a sand border answers all three at a glance, and "click the
## water on that side" becomes an obvious gesture instead of a menu.
##
## Emitted in EXACTLY the schema `data/vale.json` uses -- same keys, same tile
## codes, same prop records -- so the ground builder, walk grid, hover picker
## and FX layer all keep reading one shape of document and none of them needs
## to know the world is procedural.
##
## THE FIRST PLOT HAS NO BUILDINGS. Two people, trees, bushes and stone. Every
## structure in the village is one the villagers put up themselves out of wood
## they cut, which is the whole point of a god who cannot give orders: you
## cannot place a hut, you can only make hut-building worth their while.

const SPAN := 21          ## tiles across one plot, sand border included
const GAP := 5            ## tiles of water between neighbours
const PITCH := SPAN + GAP
const GRID := 5           ## GRID x GRID plots
const MARGIN := 3         ## water border around the whole archipelago
const SAND := 2           ## width of the beach ring, in tiles

const TILE := 0.5
const LIFT := 0.5

## Rising, so the second plot is a goal and the last is an achievement.
const PRICE := [0, 35, 80, 140, 220, 320, 440, 580, 740, 920]
const POP_PER_ISLAND := 5

const FOUR_WAY: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0),
								   Vector2i(0, 1), Vector2i(0, -1)]
## Only two directions when laying bridges: a bridge is shared between two
## plots and doing all four would build every span twice.
const EAST_SOUTH: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]

## Declared footprints, matching what the Blender export stamps into vale.json.
## A generated prop has no declaration travelling with it, and the walk grid
## blocks buildings by this number -- guess it small and followers walk through
## walls.
const FOOTPRINTS := {
	"Buildings/hut": [2.0, 2.0], "Buildings/cottage": [2.2, 2.2],
	"Buildings/market_stall": [1.6, 1.2], "Buildings/well": [1.0, 1.0],
	"Buildings/shrine": [1.6, 1.6], "Buildings/bridge": [0.5, 0.68],
}

var unlocked: Dictionary = {}      ## Vector2i slot -> true
var _seed := 20260901


func _init(seed_value := 20260901) -> void:
	_seed = seed_value
	unlocked[home()] = true


static func home() -> Vector2i:
	return Vector2i(GRID / 2, GRID / 2)


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
	return PRICE[n] if n < PRICE.size() else PRICE[PRICE.size() - 1] + 220


## Plots that are not owned but touch one that is. The only ones you may buy:
## a plot across open water with no neighbour would be unreachable, and selling
## the player something nobody can walk to is a bug with a price tag.
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


func origin(slot: Vector2i) -> Vector2i:
	return Vector2i(MARGIN + slot.x * PITCH, MARGIN + slot.y * PITCH)


## The tile at the middle of a plot, which is where its marker floats and where
## a newly-bought plot is centred for the camera.
func centre_cell(slot: Vector2i) -> Vector2i:
	return origin(slot) + Vector2i(SPAN / 2, SPAN / 2)


func slot_of_cell(cell: Vector2i) -> Vector2i:
	for s in unlocked:
		var o: Vector2i = origin(s)
		if cell.x >= o.x and cell.y >= o.y \
				and cell.x < o.x + SPAN and cell.y < o.y + SPAN:
			return s
	return Vector2i(-1, -1)


## --- generation -------------------------------------------------------------

## Build the whole document from scratch. Cheap -- a grid of characters -- and
## regenerating everything rather than patching in the new plot means the two
## paths cannot diverge, because there is only one path.
func build_doc() -> Dictionary:
	var n := cols()
	var ground: Array = []
	var flat: Array = []
	for r in n:
		var line := ""
		var blank := ""
		for c in n:
			line += "W"
			blank += "."
		ground.append(line)
		flat.append(blank)

	var props: Array = []
	for s in unlocked:
		_carve(ground, s)
	# Bridges after all the land exists, or a span would be laid toward a coast
	# that has not been carved yet.
	for s in unlocked:
		_bridge(ground, props, s)
	for s in unlocked:
		_scatter(props, ground, s)

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


## A square of grass inside a border of sand. The corners are notched by one
## tile so the plot reads as a piece of land rather than as a tile in a grid --
## one notch is enough, and it costs four characters.
func _carve(ground: Array, slot: Vector2i) -> void:
	var o := origin(slot)
	for j in SPAN:
		for i in SPAN:
			var edge: int = mini(mini(i, j), mini(SPAN - 1 - i, SPAN - 1 - j))
			if edge == 0 and (i == j or i == SPAN - 1 - j):
				continue                      # the four corner notches
			_put(ground, o.x + i, o.y + j, "A" if edge < SAND else "G")


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


## Lay a bridge to the neighbour east and south, if those are owned.
##
## YAW IS THE WHOLE THING HERE. One bridge section is a plank deck whose module
## runs along its LOCAL X, with the rails outboard on Y. So a span travelling
## east-west wants yaw 0, and one travelling north-south wants yaw 90. This had
## the two swapped, which laid every deck ACROSS its own span -- the planks ran
## the wrong way and the handrails cut through them.
func _bridge(ground: Array, props: Array, slot: Vector2i) -> void:
	for d in EAST_SOUTH:
		if not unlocked.has(slot + d):
			continue
		var a := origin(slot)
		var mid := SPAN / 2
		var col := a.x + mid
		var row := a.y + mid
		var guard := PITCH * 2
		# Walk out to the first water tile, then deck every one until land
		# resumes. Measuring the span rather than assuming GAP tiles keeps it
		# correct whatever the coast does.
		while guard > 0 and _char_at(ground, col, row) != "W":
			col += d.x
			row += d.y
			guard -= 1
		while guard > 0 and _char_at(ground, col, row) == "W":
			props.append({"id": "Buildings/bridge", "col": col, "row": row,
						  "yaw": 0.0 if d.x != 0 else 90.0, "scale": 1.0,
						  "fp": [0.5, 0.68]})
			col += d.x
			row += d.y
			guard -= 1


## What grows on a plot. NO BUILDINGS ANYWHERE -- every structure in this game
## is one the villagers raise themselves. The starting plot is a little kinder
## than the rest (more bushes, which are food they can reach on day one) but it
## is still bare ground and trees.
func _scatter(props: Array, ground: Array, slot: Vector2i) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = _seed + slot.x * 31337 + slot.y * 6971
	var o := origin(slot)
	var taken: Dictionary = {}
	for p in props:
		taken[Vector2i(int(p["col"]), int(p["row"]))] = 2.0

	var first := slot == home()
	var plan: Array = []
	if first:
		plan = [["Nature/tree", 7, 1.5], ["Nature/bush", 9, 1.0],
				["Nature/rock", 4, 1.0], ["Nature/flowers", 8, 0.7],
				["Nature/tall_grass", 14, 0.5], ["Nature/log", 2, 1.0],
				["Nature/stump", 2, 0.9]]
	else:
		plan = [["Nature/tree", 9, 1.5], ["Nature/pine", 5, 1.5],
				["Nature/bush", 6, 1.0], ["Nature/rock", 5, 1.0],
				["Nature/log", 2, 1.0], ["Nature/flowers", 6, 0.7],
				["Nature/tall_grass", 12, 0.5], ["Nature/stump", 3, 0.9]]

	for entry in plan:
		var aid := String(entry[0])
		var want := int(entry[1])
		var clear := float(entry[2])
		var placed := 0
		for attempt in want * 40:
			if placed >= want:
				break
			var col := o.x + r.randi_range(SAND, SPAN - 1 - SAND)
			var row := o.y + r.randi_range(SAND, SPAN - 1 - SAND)
			# Grass only. The beach is left clear so the plot has a visible
			# edge and so villagers always have a way round the outside.
			if _char_at(ground, col, row) != "G":
				continue
			var cell := Vector2i(col, row)
			if _too_close(taken, cell, clear):
				continue
			taken[cell] = clear
			props.append({"id": aid, "col": col, "row": row,
						  "yaw": r.randf_range(0.0, 360.0), "scale": 1.0,
						  "fp": FOOTPRINTS.get(aid, [0.5, 0.5])})
			placed += 1


## Is `cell` too near something already placed?
##
## The required gap is the SUM of the two half-extents, not the larger of the
## two radii. With max(), a tuft of grass had to stand three metres from a hut
## because the hut's clearance applied to everything it was compared against,
## and that rejected three quarters of the scatter.
func _too_close(taken: Dictionary, cell: Vector2i, clear: float) -> bool:
	for other in taken:
		var o: Vector2i = other
		var need: float = (clear + float(taken[other])) * 0.5
		if Vector2(cell.x - o.x, cell.y - o.y).length() * TILE < need:
			return true
	return false
