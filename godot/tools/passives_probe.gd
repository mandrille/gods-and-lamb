extends SceneTree
## Do buildings actually DO anything, and does a finished job now pay Faith?
##
## Four measurements, each a before/after around one staged building: passive
## Faith income with and without a shrine; the wood yield multiplier with and
## without a lumber camp; food capacity with and without a farm; and -- the
## live bug fix in this same batch -- `total_earned` actually moving after a
## single chop, now that ValeRoot._wire_follower calls
## Divinity.on_work_done at all instead of not calling it at all.
const ShotWindowRef := preload("res://tools/shot_window.gd")

var _f := 0
var _root: Node = null
var _faults: Array[String] = []


func _initialize() -> void:
	ShotWindowRef.park()
	get_root().add_child(
		(load("res://scenes/vale.tscn") as PackedScene).instantiate())


func _process(_d: float) -> bool:
	_f += 1
	if _f < 20:
		return false
	for n in get_root().get_children():
		if n.get("divinity") != null:
			_root = n
	if _root == null:
		printerr("[PASSIVE] FAIL: no scene root")
		quit(1)
		return true

	_check_faith()
	_check_yield()
	_check_cap()
	_check_work_done()
	_finish()
	return true


func _check_faith() -> void:
	var without: float = _root.village.passive_faith()
	# The church is 2.5 x 2.0 m now, so ONE random cell overlaps something more
	# often than not -- this failed one run in three. Try a spread of cells;
	# this is staging, not a placement test (build_probe covers that).
	var placed := false
	for attempt in 60:
		var cell: Vector2i = _root.grid.random_cell(_root._rng)
		if _root.grid.is_buildable(cell) and _root.builder.add_prop(
				"Buildings/shrine", cell.x, cell.y):
			placed = true
			break
	if not placed:
		_faults.append("could not stage a shrine for the faith-income check")
		return
	_root.village.census(_root.builder.placed_props)
	var with_shrine: float = _root.village.passive_faith()
	print("[PASSIVE] passive faith/s: %.3f without a shrine, %.3f with"
		% [without, with_shrine])
	if with_shrine <= without:
		_faults.append("a shrine added no passive Faith income")


## The lumber camp's GLB does not exist in the CURRENT library -- the Blender
## side of this batch is still in flight. Staged by writing the id straight
## into the census, per the batch's own rule: a passive is a question asked
## of `village.structures`, and `village.census` is what fills that dict, so
## a fake entry with the right id is indistinguishable from a real building
## as far as `passive_yield` is concerned.
func _check_yield() -> void:
	var without: float = _root.village.passive_yield("wood")
	var fake: Array = _root.builder.placed_props.duplicate()
	fake.append({"id": "Buildings/lumber_camp"})
	_root.village.census(fake)
	var with_camp: float = _root.village.passive_yield("wood")
	print("[PASSIVE] wood yield mult: %.2f without a lumber camp, %.2f with"
		% [without, with_camp])
	if with_camp <= without:
		_faults.append("a lumber camp did not raise the wood yield multiplier")
	_root.village.census(_root.builder.placed_props)      ## restore


## Same reasoning as `_check_yield`: the farm's GLB is not in the current
## library either.
func _check_cap() -> void:
	var without: int = _root.village.capacity("food")
	var fake: Array = _root.builder.placed_props.duplicate()
	fake.append({"id": "Buildings/farm"})
	_root.village.census(fake)
	var with_farm: int = _root.village.capacity("food")
	print("[PASSIVE] food capacity: %d without a farm, %d with"
		% [without, with_farm])
	if with_farm <= without:
		_faults.append("a farm did not raise food capacity")
	_root.village.census(_root.builder.placed_props)      ## restore


## THE LIVE BUG. `on_work_done` existed from the first draft and nothing
## called it -- total_earned was flat across an entire finished job. Forced
## the same way jobs_probe forces a job action: `_pending` + `_begin_work`
## rather than a walk, because getting there belongs to a different probe.
func _check_work_done() -> void:
	var before: float = _root.divinity.total_earned
	var cell: Vector2i = _root.grid.random_cell(_root._rng)
	var f = _root._spawn_thinker("lumberjack", _root.grid.world_of(cell), 1.8)
	if f == null:
		_faults.append("could not spawn a lumberjack for the on_work_done check")
		return
	f.brain.at_cell = cell
	f._pending = "chop"
	f._begin_work()
	if f.brain.action != "chop":
		_faults.append("could not force a chop to test the Faith payout")
		return
	f.brain.action_left = 0.001
	f._process(0.01)
	var after: float = _root.divinity.total_earned
	print("[PASSIVE] total_earned after one finished chop: %.2f -> %.2f"
		% [before, after])
	if after <= before:
		_faults.append("total_earned did not grow after a finished chop -- "
			+ "on_work_done is still not firing")


func _finish() -> void:
	if _faults.is_empty():
		print("[PASSIVE] ok")
	else:
		for f in _faults:
			printerr("[PASSIVE]   - " + f)
		printerr("[PASSIVE] %d FAILURE(S)" % _faults.size())
	quit(0 if _faults.is_empty() else 1)
