extends SceneTree
## Do followers respect the map? Two claims, both checkable.
##
##   1. No follower is EVER on a water tile that is not a bridge deck.
##   2. Followers actually cross the river, and only at bridges.
##
## Claim 1 is the one that matters: a pathfinder that merely usually avoids
## water is a pathfinder that will walk someone into the river on the frame
## nobody is looking. So it is sampled every frame for every follower, not
## spot-checked.
const ShotWindowRef := preload("res://tools/shot_window.gd")

var _f := 0
var _root: Node = null
var _grid = null
var _violations := 0
var _worst := ""
var _samples := 0
var _crossed := {}          ## follower -> last side of the river
var _crossings := 0
var _bridge_cells := {}
var _divide_x := 0.0

func _initialize() -> void:
	ShotWindowRef.park()
	get_root().add_child((load("res://scenes/vale.tscn") as PackedScene).instantiate())

func _process(_d: float) -> bool:
	_f += 1
	if _f == 20:
		for n in get_root().get_children():
			if n.get("grid") != null:
				_root = n
				_grid = n.get("grid")
		if _grid == null:
			printerr("[WALK] no grid")
			quit(1)
			return true
		for c in _grid.cells_of("Buildings/bridge"):
			_bridge_cells[c] = true
		# Where the river actually is, in world x. The obvious divide -- x > 0 --
		# is NOT the river: the map is 96 cells wide and the water sits around
		# col 38, which is several metres west of the origin. Measuring crossings
		# of the wrong line reports zero forever and reads as a bug in the
		# bridges rather than a bug in the ruler.
		var lo := 1 << 30
		var hi := -1
		for c in _bridge_cells:
			var cell: Vector2i = c
			lo = mini(lo, cell.x)
			hi = maxi(hi, cell.x)
		_divide_x = _grid.world_of(Vector2i((lo + hi) / 2, 0)).x
		print("[WALK] watching %d bridge decks; river divide at x = %.2f"
			% [_bridge_cells.size(), _divide_x])
	if _f < 20 or _root == null:
		return false

	var lower: Array = _root.builder.doc.get("lower", [])
	for child in _root.get_children():
		if not String(child.name).begins_with("Follower"):
			continue
		var cell: Vector2i = _grid.cell_of(child.position)
		_samples += 1
		var code: String = _root.builder.code_at(lower, cell.x, cell.y)
		if code == "W" and not _bridge_cells.has(cell):
			_violations += 1
			_worst = "%s at cell (%d,%d) on water" % [child.name, cell.x, cell.y]
		# River crossing: which side of the water column is this follower on?
		var side := 1 if child.position.x > _divide_x else 0
		if _crossed.has(child) and _crossed[child] != side:
			_crossings += 1
		_crossed[child] = side

	if _f < 900:
		return false
	print("[WALK] %d follower-frames sampled" % _samples)
	print("[WALK] on-water violations: %d %s"
		% [_violations, "" if _violations == 0 else "  worst: " + _worst])
	# Context, not a verdict: whether anyone HAPPENED to want the far bank in a
	# fifteen-second window is a fact about their errands, not about the map.
	# _routes_hold() below is what actually decides.
	print("[WALK] river side-changes observed: %d (informational)" % _crossings)
	if _violations > 0:
		printerr("[WALK] FAIL: a follower stood on open water.")
		quit(1)
		return true
	if not _routes_hold():
		quit(1)
		return true
	print("[WALK] ok")
	quit(0)
	return true


## Watching is not proving.
##
## Six followers going about their errands will not cross the river, because a
## need sends them to the NEAREST tree or hut and the nearest one is always on
## their own bank. Zero observed crossings is therefore not evidence about the
## bridges either way -- it is evidence that nobody had a reason to go.
##
## So ask directly: request many long routes and inspect every cell of every one
## of them. That turns the interesting claim from "we did not see it break" into
## "we asked N times and it held", and it covers the crossing case whether or
## not the simulation happened to want it.
func _routes_hold() -> bool:
	var lower: Array = _root.builder.doc.get("lower", [])
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260901

	# Split the walkable map by which side of the bridges a cell sits on. The
	# bridges are a short span, so their column range names the river.
	var bcol_lo := 1 << 30
	var bcol_hi := -1
	for c in _bridge_cells:
		var cell: Vector2i = c
		bcol_lo = mini(bcol_lo, cell.x)
		bcol_hi = maxi(bcol_hi, cell.x)

	var west: Array[Vector2i] = []
	var east: Array[Vector2i] = []
	for i in 4000:
		var c: Vector2i = _grid.random_cell(rng)
		if c.x < bcol_lo - 2:
			west.append(c)
		elif c.x > bcol_hi + 2:
			east.append(c)
	print("[WALK] river spans cols %d..%d; sampled %d west / %d east cells"
		% [bcol_lo, bcol_hi, west.size(), east.size()])
	if west.is_empty() or east.is_empty():
		printerr("[WALK] FAIL: could not sample cells on both banks.")
		return false

	var tested := 0
	var unreachable := 0
	var used_bridge := 0
	var wet := 0
	var jumps := 0
	var worst_jump := 0.0
	var n := mini(200, mini(west.size(), east.size()))
	for i in n:
		# Both directions: a one-way test would miss an asymmetric grid.
		for pair in [[west[i], east[i]], [east[i], west[i]]]:
			tested += 1
			var route: Array = _grid.path_world(pair[0], pair[1])
			if route.is_empty():
				unreachable += 1
				continue
			var on_bridge := false
			var prev: Vector3 = route[0]
			for w in route:
				var pt: Vector3 = w
				var cell: Vector2i = _grid.cell_of(pt)
				if _bridge_cells.has(cell):
					on_bridge = true
				elif _root.builder.code_at(lower, cell.x, cell.y) == "W":
					wet += 1
				# Consecutive waypoints must be adjacent cells. A gap means the
				# route teleports over whatever sits between them, which is
				# exactly how a follower would end up inside a cottage.
				var step := pt.distance_to(prev)
				if step > _grid.tile * 1.5:
					jumps += 1
					worst_jump = maxf(worst_jump, step)
				prev = pt
			if on_bridge:
				used_bridge += 1

	print("[WALK] %d cross-river routes requested, %d unreachable"
		% [tested, unreachable])
	print("[WALK] routed over a bridge deck: %d of %d" % [used_bridge, tested - unreachable])
	print("[WALK] waypoints on open water: %d" % wet)
	print("[WALK] non-adjacent waypoint steps: %d (worst %.2f m)" % [jumps, worst_jump])
	if wet > 0:
		printerr("[WALK] FAIL: a route ran through open water.")
		return false
	if jumps > 0:
		printerr("[WALK] FAIL: a route skipped over blocked ground.")
		return false
	if unreachable > 0:
		printerr("[WALK] FAIL: %d cross-river routes had no path, but the map is "
			% unreachable + "one connected region -- the grid and A* disagree.")
		return false
	if used_bridge == 0:
		printerr("[WALK] FAIL: not one route crossed at a bridge.")
		return false
	return true
