extends SceneTree
## Do jobs actually change behaviour, and does a child ever take one?
##
## Five claims, each isolated rather than left to emerge from a long run:
## a lumberjack chops far more often than a plain villager making the same
## decisions over the same world; a priest standing at a shrine can choose
## `bless_flock` and it raises a neighbour's favour; a nurse's `tend` raises
## the lowest health in reach; a bard's `sing` raises a neighbour's fun; and a
## child never rolls a job action, however good the odds look on paper.
##
## Real Follower objects are used for the four job checks (spawned through
## ValeRoot._spawn_thinker, exactly the path play uses) rather than isolated
## Brain objects, so the job's effect is exercised through the SAME
## `finished` signal wiring _wire_follower sets up for a real game -- the
## action is forced directly (`_pending` + `_begin_work`) rather than walked
## to, because getting there is Follower/WalkGrid's job and already has its
## own probes.
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
		printerr("[JOBS] FAIL: no scene root")
		quit(1)
		return true

	_check_bias()
	_check_priest()
	_check_nurse()
	_check_bard()
	_check_child()
	_finish()
	return true


## Two Brain objects, same seed, same world, differing only in `job` --
## everything else (personality, starting stats, rng sequence) starts
## identical, so any gap in how often each chooses "chop" is Jobs.mult and
## the job-gate at work and nothing else.
func _check_bias() -> void:
	var a := Brain.new(4001)
	a.village = _root.village
	a.grid = _root.grid
	a.boons = _root.divinity.boons
	a.job = "villager"
	a.at_cell = _root.grid.random_cell(_root._rng)

	var b := Brain.new(4001)
	b.village = _root.village
	b.grid = _root.grid
	b.boons = _root.divinity.boons
	b.job = "lumberjack"
	b.at_cell = a.at_cell

	var a_chops := 0
	var b_chops := 0
	for i in 20:
		if a.choose_action() == "chop":
			a_chops += 1
		if b.choose_action() == "chop":
			b_chops += 1
	print("[JOBS] chose chop: villager %d/20, lumberjack %d/20" % [a_chops, b_chops])
	if b_chops < maxi(2 * a_chops, 6):
		_faults.append("a lumberjack did not chop at least ~2x as often as a "
			+ "plain villager (%d vs %d)" % [b_chops, a_chops])


func _check_priest() -> void:
	# Retry the site -- the church footprint is 2.5 x 2.0 m and one random
	# cell overlaps something more often than not -- and CHECK add_prop's
	# result. The first version did not, so on an unlucky cell the priest
	# was tested beside a shrine that had never been placed.
	var cell := Vector2i(-1, -1)
	for attempt in 60:
		var c: Vector2i = _root.grid.random_cell(_root._rng)
		if _root.grid.is_buildable(c) and _root.builder.add_prop(
				"Buildings/shrine", c.x, c.y):
			cell = c
			break
	if cell.x < 0:
		_faults.append("could not stage a shrine for the priest check")
		return
	_root.rebuild_grid()

	# BESIDE the church, not inside its footprint: a follower standing in a
	# wall is on a blocked cell, and a brain on a blocked cell vetoes jobs.
	var pos: Vector3 = _root.grid.world_of(cell) + Vector3(0, 0, 1.6)
	var priest = _root._spawn_thinker("priest", pos, 1.8)
	var neighbour = _root._spawn_thinker("villager", pos + Vector3(0.6, 0, 0), 1.8)
	_stand_beside(priest, neighbour, 0.6)
	if priest == null or neighbour == null:
		_faults.append("could not spawn a priest and a neighbour")
		return
	priest.brain.job = "priest"
	priest.brain.at_cell = cell

	var picked_it := false
	for i in 60:
		if priest.brain.choose_action() == "bless_flock":
			picked_it = true
			break
	print("[JOBS] a priest at a staged shrine chose bless_flock: %s" % picked_it)
	if not picked_it:
		_faults.append("a priest never chose bless_flock even with a shrine standing")

	neighbour.brain.last_action = "chop"
	neighbour.brain.last_action_at = float(_root.village.now)
	var before: float = float(neighbour.brain.favour.get("chop", 1.0))

	priest.brain._cooldowns.erase("bless_flock")
	priest._pending = "bless_flock"
	priest._begin_work()
	if priest.brain.action != "bless_flock":
		_faults.append("a priest could not begin bless_flock")
		return
	priest.brain.action_left = 0.001
	priest._process(0.01)

	var after: float = float(neighbour.brain.favour.get("chop", 1.0))
	print("[JOBS] bless_flock: neighbour favour(chop) %.3f -> %.3f" % [before, after])
	if after <= before:
		_faults.append("bless_flock did not raise a neighbour's favour")


## Put the second one WHERE THIS PROBE MEANS, after the spawn.
##
## Spawning re-plans, and a re-plan snaps a follower onto a walkable cell --
## so "half a metre to the side" is only half a metre away if that spot
## happened to be free. It usually was, while the world was generated from an
## unseeded rng and every run got a different layout. The moment the world
## became deterministic (the save stores its seed) this probe landed on a
## staging where the neighbour was snapped FOUR metres off and the priest's
## three-metre blessing correctly missed them -- a real check failing for a
## reason that had nothing to do with the thing it checks.
func _stand_beside(who, other, gap: float) -> void:
	if who == null or other == null:
		return
	other.position = who.position + Vector3(gap, 0, 0)
	other.path.clear()


func _check_nurse() -> void:
	var pos: Vector3 = _root.grid.world_of(_root.grid.random_cell(_root._rng))
	var nurse = _root._spawn_thinker("nurse", pos, 1.8)
	var patient = _root._spawn_thinker("villager", pos + Vector3(0.4, 0, 0), 1.8)
	_stand_beside(nurse, patient, 0.4)
	if nurse == null or patient == null:
		_faults.append("could not spawn a nurse and a patient")
		return
	nurse.brain.job = "nurse"
	patient.brain.stats["health"] = 0.2
	var before: float = float(patient.brain.stats["health"])

	nurse._pending = "tend"
	nurse._begin_work()
	if nurse.brain.action != "tend":
		_faults.append("a nurse could not begin tend")
		return
	nurse.brain.action_left = 0.001
	nurse._process(0.01)

	var after: float = float(patient.brain.stats["health"])
	print("[JOBS] tend: lowest-health neighbour %.2f -> %.2f" % [before, after])
	if after <= before:
		_faults.append("tend did not raise the lowest-health neighbour")


func _check_bard() -> void:
	var pos: Vector3 = _root.grid.world_of(_root.grid.random_cell(_root._rng))
	var bard = _root._spawn_thinker("bard", pos, 1.8)
	var neighbour = _root._spawn_thinker("villager", pos + Vector3(0.5, 0, 0), 1.8)
	_stand_beside(bard, neighbour, 0.5)
	if bard == null or neighbour == null:
		_faults.append("could not spawn a bard and a neighbour")
		return
	bard.brain.job = "bard"
	neighbour.brain.stats["fun"] = 0.3
	var before: float = float(neighbour.brain.stats["fun"])

	bard._pending = "sing"
	bard._begin_work()
	if bard.brain.action != "sing":
		_faults.append("a bard could not begin sing")
		return
	bard.brain.action_left = 0.001
	bard._process(0.01)

	var after: float = float(neighbour.brain.stats["fun"])
	print("[JOBS] sing: neighbour fun %.2f -> %.2f" % [before, after])
	if after <= before:
		_faults.append("sing did not raise a neighbour's fun")


## Forced onto a job it did not earn, on a full larder and full needs, so the
## ONLY thing that could still steer it into a job action is the WORK pool --
## which choose_action must never reach for a child at all.
func _check_child() -> void:
	var pos: Vector3 = _root.grid.world_of(_root.grid.random_cell(_root._rng))
	var kid = _root._spawn_thinker("priest", pos, 1.8)
	if kid == null:
		_faults.append("could not spawn a follower for the child-gate check")
		return
	kid.become_child()
	kid.brain.job = "priest"
	for k in kid.brain.stats:
		kid.brain.stats[k] = 1.0
	var job_rolls := 0
	for i in 60:
		if kid.brain.choose_action() in ["bless_flock", "tend", "sing", "hunt"]:
			job_rolls += 1
	print("[JOBS] a child rolled a job action %d/60 times" % job_rolls)
	if job_rolls > 0:
		_faults.append("a child chose a job action %d time(s)" % job_rolls)


func _finish() -> void:
	if _faults.is_empty():
		print("[JOBS] ok")
	else:
		for f in _faults:
			printerr("[JOBS]   - " + f)
		printerr("[JOBS] %d FAILURE(S)" % _faults.size())
	quit(0 if _faults.is_empty() else 1)
