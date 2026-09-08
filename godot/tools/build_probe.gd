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
		# Grass, because this probe is not about the desert.
		# Run on the nearly-empty map that exists at frame 20, BEFORE the
		# saturation phase below fills it -- staging twenty buildings after
		# 3200 frames of forty builders working means fighting the very
		# congestion this file exists to test for.
		_check_new_buildings()
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
	_buy_land_and_check()
	# A picture of the saturated village, because "no two footprints intersect"
	# is checkable and "it looks like a village" is not. Skipped when the
	# machine has no display -- the assertions above are the probe, and a
	# locked session should not fail a build.
	if ShotWindowRef.can_shoot():
		get_root().get_texture().get_image().save_png(
			"res://shots/build_full.png")
	_report()
	quit(0 if _faults.is_empty() else 1)
	return true


## Buying land must not demolish what is already built.
##
## rebuild_world() frees every prop and rebuilds from the world document, and
## it was handed the RAW GENERATED one -- so every hut the followers had raised
## disappeared and every tree they had felled grew back. Nothing looked wrong
## in a screenshot, because a rewound village still looks like a village.
##
## Measured cost, from tools/economy_probe.gd: a player who bought land but
## never blessed earned less Faith over ten minutes (339) than one who touched
## nothing at all (443). The purchase that was meant to be the standing
## decision of the run was strictly worse than doing nothing.
func _buy_land_and_check() -> void:
	var before := _building_keys()
	if before.is_empty():
		_faults.append("nothing was built, so the land-purchase check proves "
			+ "nothing")
		return
	var slots: Array = _root.islands.buyable()
	if slots.is_empty():
		_faults.append("no ground was available to buy")
		return
	# Straight to the Faith rather than through the cooldowns -- this is a test
	# of what a purchase DOES, not of whether one can be afforded.
	_root.divinity.add_faith(9999.0)
	if not _root.divinity.buy_island(slots[0]):
		_faults.append("the land could not be bought")
		return
	var after := _building_keys()
	var lost: Array[String] = []
	for k in before:
		if not after.has(k):
			lost.append(k)
	print("[BUILD] after buying land: %d buildings stood, %d stand, %d lost"
		% [before.size(), after.size(), lost.size()])
	if not lost.is_empty():
		_faults.append("buying land destroyed %d building(s), first %s"
			% [lost.size(), lost[0]])


## Every building this content batch adds. Not hut/well/stall/shrine -- those
## already had FOOTPRINTS entries and are exercised by the saturation test
## below.
const NEW_BUILDINGS := [
	"Buildings/mansion", "Buildings/tavern", "Buildings/hotel",
	"Buildings/lumber_camp", "Buildings/mine", "Buildings/smithy",
	"Buildings/barracks", "Buildings/farm", "Buildings/windmill",
	"Buildings/cottage",
]


## Two claims: every "Buildings/*" id ACTIONS can `build` or WANTED can want
## has a declared footprint (an id with none gives the walk grid nothing to
## block with -- a follower walks straight through the wall of whatever was
## missed), and two of each new building, staged at the scale extremes
## `ValeRoot._raise_structure` actually uses (0.94 and 1.06), do not overlap.
func _check_new_buildings() -> void:
	# Twenty large footprints do not comfortably fit on the single starting
	# plot once roads, fields and cliffs take their share of it -- measured,
	# staging from the plot's own centre still ran out of room on the last
	# one or two. Bought outright rather than density-tuned around: two more
	# plots is plenty of land and exercises `buy_island` -> `rebuild_world`
	# again before the saturation phase does its own purchase below.
	_root.divinity.add_faith(9999.0)
	for i in 2:
		var slots: Array = _root.islands.buyable()
		if slots.is_empty():
			break
		_root.divinity.buy_island(slots[0])
	# Grass AFTER the purchases: a bought plot arrives bare, and this probe is
	# about where buildings land rather than about the desert.
	TestGround.green(_root)

	var referenced: Dictionary = {}
	for a in Brain.ACTIONS:
		var aid := String(Brain.ACTIONS[a].get("builds", ""))
		if aid.begins_with("Buildings/"):
			referenced[aid] = true
	for aid in Village.WANTED:
		if String(aid).begins_with("Buildings/"):
			referenced[String(aid)] = true
	for aid in referenced:
		if not Islands.FOOTPRINTS.has(aid):
			_faults.append("%s is built or wanted but has no FOOTPRINTS entry"
				% aid)

	# Twenty hints spread across a 5x4 lattice covering the WHOLE home plot --
	# ONLY the home island is unlocked this early, so anything off it fails
	# `is_buildable` outright. A single shared hint (the plot centre, tried
	# first) rings outward from one spot and exhausts the middle of the plot
	# long before the later buildings are placed, reporting "no room" while
	# the plot's own corners sit empty; spreading the starting points avoids
	# fighting that self-inflicted crowding.
	var staged: Array[Dictionary] = []
	var home_origin: Vector2i = _root.islands.origin(Islands.home())
	var idx := 0
	for aid in NEW_BUILDINGS:
		for scale_v in [1.06, 0.94]:
			var gx := idx % 5
			var gy := (idx / 5) % 4
			var hint := home_origin + Vector2i(5 + gx * 6, 5 + gy * 7)
			idx += 1
			var spot := _find_free_spot(aid, hint)
			if spot.x < 0:
				_faults.append("no room to stage %s at scale %.2f"
					% [aid, scale_v])
				continue
			if not _stage_building(aid, spot.x, spot.y, scale_v):
				_faults.append("%s at scale %.2f could not be placed at all"
					% [aid, scale_v])
				continue
			staged.append({"id": aid, "col": spot.x, "row": spot.y,
						   "fp": Islands.FOOTPRINTS.get(aid, [2.5, 2.5])})

	var tile: float = _root.builder.tile
	var clashes := 0
	var worst := ""
	for i in staged.size():
		for j in range(i + 1, staged.size()):
			var a: Dictionary = staged[i]
			var b: Dictionary = staged[j]
			var ahc := int(ceil(float(a["fp"][0]) / tile / 2.0))
			var ahr := int(ceil(float(a["fp"][1]) / tile / 2.0))
			var bhc := int(ceil(float(b["fp"][0]) / tile / 2.0))
			var bhr := int(ceil(float(b["fp"][1]) / tile / 2.0))
			var dc: int = absi(int(a["col"]) - int(b["col"]))
			var dr: int = absi(int(a["row"]) - int(b["row"]))
			if dc <= ahc + bhc and dr <= ahr + bhr:
				clashes += 1
				if worst == "":
					worst = "%s at (%d,%d) and %s at (%d,%d)" % [
						a["id"], int(a["col"]), int(a["row"]),
						b["id"], int(b["col"]), int(b["row"])]
	print("[BUILD] new-batch: staged %d of %d, %d overlapping pairs"
		% [staged.size(), NEW_BUILDINGS.size() * 2, clashes])
	if clashes > 0:
		_faults.append("%d staged new buildings overlap; first: %s"
			% [clashes, worst])

	# STRUCK BACK DOWN. This check's whole job is the footprint arithmetic,
	# not to leave twenty buildings standing for the saturation phase below to
	# trip over -- several of them are stand-in Node3Ds with no real GLB, and
	# `carry_doc`'s land-purchase test would (correctly) report them lost the
	# moment the world rebuilds, for a reason that has nothing to do with land
	# purchase at all.
	for e in _root.builder.placed_props.duplicate():
		if NEW_BUILDINGS.has(String(e.get("id", ""))):
			_root.builder.remove_prop(e)
	_root.village.census(_root.builder.placed_props)


## Most of NEW_BUILDINGS has no GLB in the CURRENT library -- the Blender side
## of this batch is still in flight -- so `ValeBuilder.add_prop` cannot place
## them at all. Staged with a bare Node3D standing in for the mesh when that
## happens: `would_overlap` and the walk grid only care that `node` is a
## valid, positioned thing and that the id/footprint are right, never what it
## looks like. Cottage already has its GLB and goes through the real path.
func _stage_building(aid: String, col: int, row: int, scale_v: float) -> bool:
	if _root.builder._packed_of(aid) != null:
		return _root.builder.add_prop(aid, col, row, 0.0, scale_v)
	if _root.builder.would_overlap(aid, col, row):
		return false
	var node := Node3D.new()
	node.position = (_root.builder.world_of(col, row)
		+ Vector3(0, _root.builder.lift, 0))
	_root.builder.add_child(node)
	_root.builder.placed_props.append({
		"id": aid, "node": node, "pos": node.position,
		"col": col, "row": row, "yaw": 0.0, "scale": scale_v,
		"fp": Islands.FOOTPRINTS.get(aid, [0.5, 0.5])})
	return true


## A buildable cell, clear of anything already staged, searched outward in
## rings from `hint` so ten different buildings do not all fight over the
## same patch of ground.
func _find_free_spot(aid: String, hint: Vector2i) -> Vector2i:
	for ring in range(0, 40):
		for i in range(-ring, ring + 1):
			for j in range(-ring, ring + 1):
				if maxi(absi(i), absi(j)) != ring:
					continue
				var c := Vector2i(hint.x + i * 2, hint.y + j * 2)
				if not _root.grid.is_buildable(c):
					continue
				if _root.builder.would_overlap(aid, c.x, c.y):
					continue
				return c
	return Vector2i(-1, -1)


## Identity is the CELL and the id, not the node -- every node is freed and
## remade by the rebuild, so comparing instances would always report total loss.
func _building_keys() -> Dictionary:
	var out := {}
	for e in _root.builder.placed_props:
		var aid := String(e["id"])
		if aid.begins_with("Buildings/") and aid != "Buildings/bridge":
			out["%s@%d,%d" % [aid, int(e["col"]), int(e["row"])]] = true
	return out


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
