extends SceneTree
## Do buildings ever end up on top of each other?
##
## This is the regression guard for a bug seen in play: huts stacked into each
## other. Three separate causes compounded, and a test that only exercised one
## of them would pass while the bug survived --
##
##   1. `ValeBuilder.add_prop` checked only the tile CODE, never whether a prop
##      already stood there. It was answering "is this ground" to a question
##      that meant "is this free".
##   2. The site was chosen at decision time and used ~20 s later after the
##      walk, with nothing re-checking on arrival.
##   3. `Village.claim` reserved the KIND of building, not the SITE, so two
##      villagers both told to build a hut could walk to the same ground.
##
## So this does not test any of the three. It saturates a village with builders
## and asserts the OUTCOME: no two footprints intersect, no matter which path
## placed them. That holds however the causes are fixed or refactored later.
const ShotWindowRef := preload("res://tools/shot_window.gd")

const WANT := 40
const SPEED := 12.0
const RUN_FRAMES := 3200

var _f := 0
var _root: Node = null
var _faults: Array[String] = []


func _initialize() -> void:
	ShotWindowRef.park()
	get_root().add_child(
		(load("res://scenes/vale.tscn") as PackedScene).instantiate())


func _process(_d: float) -> bool:
	_f += 1
	if _f == 20:
		for n in get_root().get_children():
			if n.get("divinity") != null:
				_root = n
		if _root == null:
			printerr("[BUILD] FAIL: no scene root")
			quit(1)
			return true
		# Enough builders and enough materials that they will try constantly --
		# the bug needs CONTENTION to appear, so a quiet village proves nothing.
		_root.village.pop_cap = 200
		while _root.folk.size() < WANT:
			if not _root.spawn_villager():
				break
		_root.village.give({"wood": 400, "stone": 400, "food": 400})
		Engine.time_scale = SPEED
		print("[BUILD] %d villagers, materials stocked, %.0fx"
			% [_root.folk.size(), SPEED])
	if _f < 20:
		return false

	# Keep topping the stores up: the point is to keep them building, not to
	# find out how fast they run out of wood.
	if _f % 120 == 0:
		_root.village.give({"wood": 200, "stone": 200, "food": 200})
	if _f < RUN_FRAMES:
		return false

	Engine.time_scale = 1.0
	# A picture of the saturated village, because "no two footprints intersect"
	# is checkable and "it looks like a village" is not.
	get_root().get_texture().get_image().save_png("res://shots/build_full.png")
	_report()
	quit(0 if _faults.is_empty() else 1)
	return true


func _report() -> void:
	var props: Array = _root.builder.placed_props
	var built: Array = []
	for e in props:
		if String(e["id"]).begins_with("Buildings/") \
				and String(e["id"]) != "Buildings/bridge":
			built.append(e)
	print("[BUILD] %d props standing, %d of them buildings"
		% [props.size(), built.size()])
	print("[BUILD] structures: %s" % str(_root.village.structures))
	var replans := 0
	var no_target := 0
	var started := 0
	for f in _root.folk:
		replans += f.n_replans
		no_target += f.n_no_target
		started += f.n_started
	print("[BUILD] %d replans -> %d jobs started, %d found no destination"
		% [replans, started, no_target])
	print("[BUILD] placement: %d attempts, %d placed (%d after moving), %d failed"
		% [_root.n_build_try, _root.n_build_ok, _root.n_build_moved,
		   _root.n_build_fail])
	print("[BUILD] wants hut %.2f, claimed %d, standing %d"
		% [_root.village.wants("Buildings/hut"),
		   _root.village.claimed("Buildings/hut"),
		   _root.village.count_of("Buildings/hut")])

	# Every pair, in CELLS, against the declared footprints -- the same
	# arithmetic the walk grid blocks with, so a pass here means a villager can
	# also walk between them.
	var tile: float = _root.builder.tile
	var clashes := 0
	var worst := ""
	for i in built.size():
		for j in range(i + 1, built.size()):
			var a: Dictionary = built[i]
			var b: Dictionary = built[j]
			var afp: Array = a.get("fp", [0.5, 0.5])
			var bfp: Array = b.get("fp", [0.5, 0.5])
			var ahc := int(ceil(float(afp[0]) / tile / 2.0))
			var ahr := int(ceil(float(afp[1]) / tile / 2.0))
			var bhc := int(ceil(float(bfp[0]) / tile / 2.0))
			var bhr := int(ceil(float(bfp[1]) / tile / 2.0))
			var dc: int = absi(int(a["col"]) - int(b["col"]))
			var dr: int = absi(int(a["row"]) - int(b["row"]))
			if dc <= ahc + bhc and dr <= ahr + bhr:
				clashes += 1
				if worst == "":
					worst = "%s at (%d,%d) and %s at (%d,%d)" % [
						a["id"], int(a["col"]), int(a["row"]),
						b["id"], int(b["col"]), int(b["row"])]
	print("[BUILD] overlapping pairs: %d" % clashes)
	if clashes > 0:
		_faults.append("%d buildings overlap; first: %s" % [clashes, worst])

	# And nothing may sit on a road, in the river or on a field -- a hut in the
	# middle of the highway is walkable ground and still the wrong place.
	var offside := 0
	for e in built:
		var code: String = _root.grid.code_of(
			Vector2i(int(e["col"]), int(e["row"])))
		if code != "G":
			offside += 1
	print("[BUILD] buildings on non-grass: %d" % offside)
	if offside > 0:
		_faults.append("%d buildings stand on road, field or water" % offside)

	# Buildings square to the grid.
	var skew := 0
	for e in built:
		var node = e.get("node")
		if not is_instance_valid(node):
			continue
		var deg: float = rad_to_deg(node.rotation.y)
		if absf(fposmod(deg + 45.0, 90.0) - 45.0) > 1.0:
			skew += 1
	print("[BUILD] buildings off the 90-degree grid: %d" % skew)
	if skew > 0:
		_faults.append("%d buildings sit at an odd angle" % skew)

	if _faults.is_empty():
		print("[BUILD] all checks ok")
	else:
		for f in _faults:
			printerr("[BUILD]   - " + f)
		printerr("[BUILD] %d FAILURE(S)" % _faults.size())
