extends RefCounted
class_name Islands

## ONE landmass that grows. Not an archipelago.
##
## The land is a grid of square PLOTS sitting flush against each other, with no
## water between them and no bridges joining them. Buying a plot extends the
## landmass in that direction -- the new ground simply continues from the old,
## and the seam is invisible because nothing about the terrain is drawn
## per-plot.
##
## That last part is the whole trick, and it is why the previous version read
## as islands. When each plot generated its own beach, its own road cross and
## its own stream, buying a neighbour produced a SECOND island bolted on: two
## coasts meeting, two road systems that did not line up, two streams that
## stopped at the seam. So the features are GLOBAL now. One river meanders
## across the whole world; one road grid runs across the whole world; cliffs
## and fields sit at fixed world positions. A plot does not draw any of them --
## it only says which cells EXIST, and every feature is clipped to whatever
## land is currently there. Buy a plot and the river you can already see simply
## carries on into it.
##
## Emitted in EXACTLY the schema `data/vale.json` uses, so the ground builder,
## walk grid, hover picker and FX layer all keep reading one shape of document
## and none of them needs to know the world is procedural.
##
## NOTHING IS BUILT FOR YOU. Every structure is one the villagers raise.

## Tiles across one plot. Big: the opening should be a landscape you look
## around in, not a tile you look at.
const SPAN := 34
## FLUSH -- no gap. A gap here is what made plots read as separate islands.
const PITCH := SPAN
const GRID := 3           ## GRID x GRID plots
const MARGIN := 2         ## empty border, so edge tiles are not clipped

const TILE := 0.5
const LIFT := 0.5

## Rising, so the second plot is a goal and the last is an achievement.
const PRICE := [0, 40, 95, 170, 265, 380, 520, 690, 880]
## Three plots should comfortably hold twenty-odd people. At 6 a whole village
## fitted in a corner of the land it had paid for, and the cap -- not the
## arrival rate, not the food -- was what stopped it growing.
const POP_PER_ISLAND := 7

const FOUR_WAY: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0),
								   Vector2i(0, 1), Vector2i(0, -1)]

## Declared footprints, matching what the Blender export stamps into vale.json.
## A generated prop has no declaration travelling with it, and the walk grid
## blocks buildings by this number -- guess it small and followers walk through
## walls.
const FOOTPRINTS := {
	"Buildings/hut": [2.0, 2.0], "Buildings/hut_b": [2.0, 2.0],
	"Buildings/cottage": [2.4, 2.2], "Buildings/cottage_b": [2.4, 2.2],
	"Buildings/market_stall": [1.6, 1.2], "Buildings/well": [1.0, 1.0],
	"Buildings/shrine": [2.5, 2.0], "Buildings/bridge": [0.5, 0.62],
	"Buildings/mansion": [2.6, 2.4], "Buildings/tavern": [2.2, 2.1],
	"Buildings/hotel": [2.4, 2.0], "Buildings/lumber_camp": [2.5, 2.4],
	"Buildings/mine": [2.4, 2.2], "Buildings/smithy": [2.2, 2.2],
	"Buildings/barracks": [2.5, 2.5], "Buildings/farm": [2.6, 2.6],
	"Buildings/farm_b": [2.6, 2.6], "Buildings/windmill": [2.4, 1.4],
}

## How often a road runs, in tiles, and how wide. Global lines, so roads line
## up across a plot seam instead of each plot drawing its own cross.
const ROAD_EVERY := 23
const ROAD_WIDE := 2

## The world seed. Named rather than repeated as a literal in three places,
## because a save stores it and a loader has to ask for the same default.
const DEFAULT_SEED := 20260901

var unlocked: Dictionary = {}      ## Vector2i slot -> true
var _seed := DEFAULT_SEED


func _init(seed_value := DEFAULT_SEED) -> void:
	_seed = seed_value
	unlocked[home()] = true


static func home() -> Vector2i:
	return Vector2i(GRID / 2, GRID / 2)


func cols() -> int:
	return GRID * PITCH + MARGIN * 2


func rows() -> int:
	return cols()


func count() -> int:
	return unlocked.size()


func pop_cap() -> int:
	return count() * POP_PER_ISLAND


func price_next() -> int:
	var n := count()
	return PRICE[n] if n < PRICE.size() else PRICE[PRICE.size() - 1] + 220


## Plots that are not owned but touch one that is.
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

## Build the whole document from scratch.
##
## Cheap -- a grid of characters -- and regenerating everything rather than
## patching in the new plot means the two paths cannot diverge, because there
## is only one path. Every feature is computed from the WORLD seed at world
## coordinates and then clipped to the land that exists, so buying a plot
## reveals more of the same landscape rather than generating a new one.
func build_doc() -> Dictionary:
	var n := cols()
	var ground: Array = []
	var upper: Array = []
	for r in n:
		var a := ""
		var b := ""
		for c in n:
			a += "."
			b += "."
		ground.append(a)
		upper.append(b)

	# 1. The land itself: every cell of every owned plot, and nothing else.
	for s in unlocked:
		var o := origin(s)
		for j in SPAN:
			for i in SPAN:
				_put(ground, o.x + i, o.y + j, "G")

	# 2. Global features, in the order things sit on top of each other: water
	#    cuts the ground, roads cross it on bridges, fields and shelves take
	#    what is left.
	var river := _river_cells(n)
	for cell in river:
		var c: Vector2i = cell
		if _char_at(ground, c.x, c.y) == "G":
			_put(ground, c.x, c.y, String(river[cell]))

	var props: Array = []
	_roads(ground, props, n)
	_fields(ground, n)
	_cliffs(ground, upper, n)
	for s in unlocked:
		_scatter(props, ground, upper, s)

	return {
		"cols": n, "rows": n, "tile": TILE, "lift": LIFT,
		"upper_blocks": 2, "water_drop": 0.06,
		"code": {"G": "Terrain/grass", "D": "Terrain/dirt",
				 "S": "Terrain/stone", "P": "Terrain/path",
				 "W": "Terrain/water", "A": "Terrain/sand",
				 "C": "Terrain/soil"},
		"fill": "Terrain/dirt",
		"lower": ground, "upper": upper, "props": props,
	}


func _put(ground: Array, col: int, row: int, ch: String) -> void:
	if row < 0 or row >= ground.size():
		return
	var line: String = ground[row]
	if col < 0 or col >= line.length():
		return
	ground[row] = line.substr(0, col) + ch + line.substr(col + 1)


func _char_at(ground: Array, col: int, row: int) -> String:
	if row < 0 or row >= ground.size():
		return "."
	var line: String = ground[row]
	if col < 0 or col >= line.length():
		return "."
	return line[col]


## One river for the whole world, as {cell: "W" or "A"}.
##
## Computed over the FULL grid regardless of what is unlocked and then clipped,
## so the river never moves when land is bought -- it is revealed further. A
## river generated per plot jumps at every seam, which is exactly what made
## the last version look like separate islands stuck together.
func _river_cells(n: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = _seed + 5150
	var out := {}
	var phase := r.randf_range(0.0, TAU)
	var phase2 := r.randf_range(0.0, TAU)
	var base := float(n) * 0.5 + r.randf_range(-4.0, 4.0)
	for row in n:
		var t := float(row)
		var mid := base + sin(t * 0.055 + phase) * 7.0 \
				   + sin(t * 0.019 + phase2) * 4.0
		for k in range(-3, 4):
			# Three tiles of water with ONE of sand each side. At four tiles of
			# bank the river read as a beach with a stripe of water down it.
			out[Vector2i(int(round(mid)) + k, row)] = "W" if absi(k) <= 2 else "A"
	return out


## A road grid across the whole world, and a bridge wherever a road meets the
## river. Roads sit on fixed global lines, so two plots either side of a seam
## share the same road instead of each drawing its own cross.
func _roads(ground: Array, props: Array, n: int) -> void:
	var crossings: Array[Vector2i] = []
	for axis in 2:
		var line := ROAD_EVERY / 2
		while line < n:
			for w in ROAD_WIDE:
				var fixed: int = line + w
				for t in n:
					var col: int = fixed if axis == 0 else t
					var row: int = t if axis == 0 else fixed
					var ch := _char_at(ground, col, row)
					if ch == "G" or ch == "A" or ch == "C":
						_put(ground, col, row, "P")
					elif ch == "W":
						crossings.append(Vector2i(col, row))
			line += ROAD_EVERY

	for c in crossings:
		# A bridge deck's plank module runs along its LOCAL X with the rails
		# outboard on Y, so a north-south span wants yaw 90 and an east-west
		# one wants yaw 0. Swapping these lays every deck across its own span
		# and the handrails cut through the planks.
		var vertical := _char_at(ground, c.x, c.y - 1) == "W" \
			or _char_at(ground, c.x, c.y + 1) == "W"
		props.append({"id": "Buildings/bridge", "col": c.x, "row": c.y,
					  "yaw": 90.0 if vertical else 0.0, "scale": 1.0,
					  "fp": [0.5, 0.62]})


## Farmland and raised shelves, on a JITTERED LATTICE.
##
## Both were scattered at random points over the whole world grid, and with
## only one plot owned almost every one of them landed on empty space -- so
## the opening had no fields and no cliffs at all despite the code placing
## seven of each. A lattice with a seeded offset per cell guarantees that
## wherever land appears there are some, and keeps them in exactly the same
## world positions as more land is bought.
func _lattice(n: int, step: int, salt: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := RandomNumberGenerator.new()
	var gx := 0
	while gx < n:
		var gy := 0
		while gy < n:
			# Seeded from the CELL, so a given lattice cell always jitters the
			# same way no matter what order things are generated in.
			r.seed = _seed + salt + gx * 73856093 + gy * 19349663
			out.append(Vector2i(gx + r.randi_range(0, step - 1),
								gy + r.randi_range(0, step - 1)))
			gy += step
		gx += step
	return out


func _fields(ground: Array, n: int) -> void:
	var r := RandomNumberGenerator.new()
	for spot in _lattice(n, 21, 3307):
		r.seed = _seed + spot.x * 7919 + spot.y * 104729
		if r.randf() < 0.45:
			continue                      # not every lattice cell gets one
		var w := r.randi_range(5, 10)
		var h := r.randi_range(4, 8)
		for j in h:
			for i in w:
				if _char_at(ground, spot.x + i, spot.y + j) == "G":
					_put(ground, spot.x + i, spot.y + j, "C")


func _cliffs(ground: Array, upper: Array, n: int) -> void:
	var r := RandomNumberGenerator.new()
	for spot in _lattice(n, 29, 8291):
		r.seed = _seed + spot.x * 31337 + spot.y * 6971
		if r.randf() < 0.4:
			continue
		var w := r.randi_range(8, 13)
		var h := r.randi_range(7, 11)
		for j in h:
			for i in w:
				# Notched corners, so a shelf is not a rectangle stamped on
				# the grass.
				if i + j < 2 or (w - 1 - i) + (h - 1 - j) < 2:
					continue
				if _char_at(ground, spot.x + i, spot.y + j) != "G":
					continue
				_put(upper, spot.x + i, spot.y + j, "G")


## Everything that stands on the land. Seeded per plot so a plot keeps its own
## character, and placed only where it belongs -- reeds line the bank, lily
## pads float, everything else keeps to open grass and off the roads, the
## fields and the shelves, all of which want to stay legible.
func _scatter(props: Array, ground: Array, upper: Array,
			  slot: Vector2i) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = _seed + slot.x * 31337 + slot.y * 6971
	var o := origin(slot)
	var taken: Dictionary = {}
	for p in props:
		taken[Vector2i(int(p["col"]), int(p["row"]))] = 2.0

	var plan := [["Nature/tree", 18, 1.5], ["Nature/pine", 7, 1.5],
				 ["Nature/bush", 14, 1.0], ["Nature/rock", 9, 1.0],
				 ["Nature/log", 3, 1.0], ["Nature/stump", 3, 0.9],
				 ["Nature/flowers", 16, 0.7], ["Nature/tall_grass", 24, 0.5],
				 ["Nature/reeds", 12, 0.6], ["Nature/lily_pad", 7, 0.6],
				 # Wild grain on the ploughed ground. The villagers sow more.
				 ["Nature/crop_row", 26, 0.55]]

	for entry in plan:
		var aid := String(entry[0])
		var want := int(entry[1])
		var clear := float(entry[2])
		var wants_water := aid == "Nature/lily_pad"
		var wants_bank := aid == "Nature/reeds"
		var wants_soil := aid == "Nature/crop_row"
		var placed := 0
		for attempt in want * 40:
			if placed >= want:
				break
			var col := o.x + r.randi_range(0, SPAN - 1)
			var row := o.y + r.randi_range(0, SPAN - 1)
			var ch := _char_at(ground, col, row)
			var ok := ch == "G"
			if wants_water:
				ok = ch == "W"
			elif wants_bank:
				ok = ch == "A"
			elif wants_soil:
				ok = ch == "C"
			if not ok or _char_at(upper, col, row) != ".":
				continue
			var cell := Vector2i(col, row)
			if _too_close(taken, cell, clear):
				continue
			taken[cell] = clear
			# Buildings square to the grid; nature at any angle it likes.
			var yaw: float = 90.0 * float(r.randi_range(0, 3)) 				if aid.begins_with("Buildings/") else r.randf_range(0.0, 360.0)
			props.append({"id": aid, "col": col, "row": row,
						  "yaw": yaw, "scale": 1.0,
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
