extends SceneTree
## Do wolves hunt, get hunted back, frighten the village, and stay inside the
## rules -- nobody dies of fright, and a smite that catches a wolf must not
## also catch the sheep standing next to it?
##
## Phase 1 needs real simulated time (a wolf has to walk to a sheep, the same
## way anything else in this game gets anywhere) so it runs at high
## Engine.time_scale and is judged against a game-second budget, the same
## pattern tools/economy_probe.gd uses. Everything after it is forced
## directly -- `_hunt_effect`, `_cause_trouble`, `Divinity.smite` -- because
## walking there is a different probe's job.
const ShotWindowRef := preload("res://tools/shot_window.gd")

const SPEED := 12.0
const HUNT_SECONDS := 20.0

var _f := 0
var _root: Node = null
var _faults: Array[String] = []
var _removed: Array[String] = []
var _elapsed := 0.0
var _phase := 0
var _shot := false
var _saved := false
var _pair: Array = []


func _initialize() -> void:
	ShotWindowRef.park()
	get_root().add_child(
		(load("res://scenes/vale.tscn") as PackedScene).instantiate())


func _process(delta: float) -> bool:
	_f += 1
	if _f < 20:
		return false
	if _f == 20:
		for n in get_root().get_children():
			if n.get("divinity") != null:
				_root = n
		if _root == null:
			printerr("[WOLF] FAIL: no scene root")
			quit(1)
			return true
		_root.beast_removed.connect(func(kind: String): _removed.append(kind))
		_start_hunt()
		Engine.time_scale = SPEED
		_phase = 1
		return false

	if _phase == 1:
		_elapsed += delta
		if not _shot and _elapsed > 0.9:
			_shot = true
			_frame_pair()
			return false
		if _shot and not _saved:
			_saved = true
			get_root().get_texture().get_image().save_png(
				"res://shots/wolf_hunt.png")
			print("[WOLF] wrote res://shots/wolf_hunt.png")
		if _removed.has("Animals/sheep"):
			print("[WOLF] the wolf caught the sheep at t=%.1f game-s" % _elapsed)
			_phase = 2
		elif _elapsed >= HUNT_SECONDS:
			_faults.append("a wolf 3 m from a sheep did not catch it within "
				+ "%.0f game-seconds" % HUNT_SECONDS)
			_phase = 2
		else:
			return false

	Engine.time_scale = 1.0
	_hunter_vs_wolf()
	_check_frighten()
	_check_smite()
	_check_no_deaths()
	_finish()
	return true


## Point the camera at the predator and its prey, whatever they are doing.
func _frame_pair() -> void:
	var live: Array = []
	for n in _pair:
		if is_instance_valid(n):
			live.append(n.global_position)
	if live.is_empty():
		return
	var mid := Vector3.ZERO
	for v in live:
		mid += v
	mid /= float(live.size())
	# Clear the thicket in front of them. The pair spawns wherever the grid
	# offers ground, and twice that was behind three bushes and a pine.
	var doomed: Array = []
	for e in _root.builder.placed_props:
		var node = e.get("node")
		if is_instance_valid(node) and node.global_position.distance_to(mid) < 4.0:
			doomed.append(e)
	for e in doomed:
		_root.builder.remove_prop(e)
	_root.queue_grid_rebuild()
	_root.rig.focus = mid
	_root.rig.dist = 8.0
	_root.rig.call("_place")


func _start_hunt() -> void:
	# Both ends of the 3 m gap have to be ground. A random cell put the sheep
	# past the island rim, standing on the backdrop.
	var cell: Vector2i = _root.grid.random_cell(_root._rng)
	for _try in 200:
		var c: Vector2i = _root.grid.random_cell(_root._rng)
		var away: Vector3 = _root.grid.world_of(c) + Vector3(3.0, 0, 0)
		if _root.grid.is_plain(c) and _root.grid.is_plain(_root.grid.cell_of(away)):
			cell = c
			break
	var at: Vector3 = _root.grid.world_of(cell)
	if not _root._spawn_beast("Animals/wolf", at):
		_faults.append("could not spawn a wolf")
		return
	if not _root._spawn_beast("Animals/sheep", at + Vector3(3.0, 0, 0)):
		_faults.append("could not spawn a sheep")
		return
	# Remembered so the shot can be framed on where they ACTUALLY are when the
	# shutter falls -- a wolf that has run 3 m is not where it was spawned.
	_pair = [_root.beasts[_root.beasts.size() - 2],
			 _root.beasts[_root.beasts.size() - 1]]
	print("[WOLF] wolf spawned, sheep 3 m away")


func _hunter_vs_wolf() -> void:
	var cell: Vector2i = _root.grid.random_cell(_root._rng)
	var at: Vector3 = _root.grid.world_of(cell)
	if not _root._spawn_beast("Animals/wolf", at):
		_faults.append("could not spawn a second wolf for the hunter check")
		return
	var wolf = _root.beasts[_root.beasts.size() - 1]
	var hunter = _root._spawn_thinker("hunter", at, 1.8)
	if hunter == null:
		_faults.append("could not spawn a hunter")
		return
	hunter.brain.job = "hunter"
	var starting_hp: int = wolf.hp
	for i in starting_hp:
		_root._hunt_effect(hunter, hunter.position)
	print("[WOLF] hunter landed %d hit(s) on a %d-hp wolf" % [starting_hp, starting_hp])
	if not _removed.has("Animals/wolf"):
		_faults.append("a hunter could not kill a wolf even after enough hits")


func _check_frighten() -> void:
	var cell: Vector2i = _root.grid.random_cell(_root._rng)
	var at: Vector3 = _root.grid.world_of(cell)
	if not _root._spawn_beast("Animals/wolf", at):
		_faults.append("could not spawn a wolf for the frighten check")
		return
	var wolf = _root.beasts[_root.beasts.size() - 1]
	var villager = _root._spawn_thinker("villager", at + Vector3(1.0, 0, 0), 1.8)
	if villager == null:
		_faults.append("could not spawn a villager for the frighten check")
		return
	villager.brain.flee_from = null
	wolf._cause_trouble()
	var frightened: bool = villager.brain.flee_from != null
	print("[WOLF] a villager 1 m from a wolf was frightened: %s" % frightened)
	if not frightened:
		_faults.append("a wolf within trouble range did not frighten a villager")
	elif villager.brain.choose_action() != "flee":
		_faults.append("a frightened villager's next decision was not flee")


func _check_smite() -> void:
	var cell: Vector2i = _root.grid.random_cell(_root._rng)
	var at: Vector3 = _root.grid.world_of(cell)
	if not _root._spawn_beast("Animals/wolf", at):
		_faults.append("could not spawn a wolf for the smite check")
		return
	var wolf = _root.beasts[_root.beasts.size() - 1]
	if not _root._spawn_beast("Animals/sheep", at + Vector3(0.3, 0, 0)):
		_faults.append("could not spawn a sheep for the smite check")
		return
	var sheep = _root.beasts[_root.beasts.size() - 1]
	_root.divinity.faith = 500.0
	_root.divinity.smite(at, 2.5)
	var wolf_gone: bool = not is_instance_valid(wolf) or not _root.beasts.has(wolf)
	var sheep_spared: bool = is_instance_valid(sheep) and _root.beasts.has(sheep)
	print("[WOLF] smite: wolf removed=%s, sheep spared=%s"
		% [wolf_gone, sheep_spared])
	if not wolf_gone:
		_faults.append("smite did not remove a wolf standing in its radius")
	if not sheep_spared:
		_faults.append("smite destroyed a sheep -- livestock should be spared, "
			+ "the way a bridge is")


func _check_no_deaths() -> void:
	var worst := 1.0
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null:
			worst = minf(worst, float(f.brain.stats["health"]))
	print("[WOLF] worst folk health after the run: %.3f" % worst)
	if worst < 0.05:
		_faults.append("a follower's health fell below the 0.05 floor")


func _finish() -> void:
	if _faults.is_empty():
		print("[WOLF] ok")
	else:
		for f in _faults:
			printerr("[WOLF]   - " + f)
		printerr("[WOLF] %d FAILURE(S)" % _faults.size())
	quit(0 if _faults.is_empty() else 1)
