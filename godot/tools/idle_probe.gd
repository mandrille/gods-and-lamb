extends SceneTree
## Where does a village of fifty actually SPEND ITS TIME?
##
## "They mostly do nothing" is a symptom with at least four different causes,
## and from outside they all look identical: a villager with no destination, a
## villager with a destination and no route, a villager whose job was refused
## for want of materials, and a villager on a perfectly good two-minute walk
## all stand around or drift. So this counts them separately.
const ShotWindowRef := preload("res://tools/shot_window.gd")

const WANT := 24
const SPEED := 10.0
const RUN_FRAMES := 3000

var _f := 0
var _root: Node = null
var _time := {}          ## state -> follower-frames
var _samples := 0
var _peak_floaters := 0
var _shots := 0


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
		_root.village.pop_cap = 200
		while _root.folk.size() < WANT:
			if not _root.spawn_villager():
				break
		Engine.time_scale = SPEED
		print("[IDLE] %d villagers at %.0fx" % [_root.folk.size(), SPEED])
	if _f < 20:
		return false

	for f in _root.folk:
		if not is_instance_valid(f) or f.brain == null:
			continue
		var key: String = ["IDLE", "WALK", "WORK", "TALK"][f.state]
		_time[key] = int(_time.get(key, 0)) + 1
		_samples += 1
	# Photograph a busy moment, and count the feedback while it is live: a
	# floater system that spawns nothing is indistinguishable from one that
	# works until you look.
	_peak_floaters = maxi(_peak_floaters, _root.floaters.live_count())
	if _f == 900 or _f == 1500:
		ShotWindow.shoot("res://shots/idle_%d.png" % _shots)
		print("[IDLE] shot %d, %d floaters live, %d fx emitters"
			% [_shots, _root.floaters.live_count(), _root.fxe.active_count()])
		_shots += 1
	if _f < RUN_FRAMES:
		return false

	Engine.time_scale = 1.0
	_report()
	quit(0)
	return true


func _report() -> void:
	print("")
	print("[IDLE] === %d follower-frames ===" % _samples)
	for key in ["WALK", "WORK", "TALK", "IDLE"]:
		var n := int(_time.get(key, 0))
		print("[IDLE] %-5s %6.1f%%" % [key, 100.0 * float(n) / float(_samples)])

	var replans := 0
	var no_target := 0
	var no_route := 0
	var refused := 0
	var started := 0
	var wants := {}
	for f in _root.folk:
		replans += f.n_replans
		no_target += f.n_no_target
		no_route += f.n_no_route
		refused += f.n_refused
		started += f.n_started
		# What did they ASK for, independent of whether they got it?
		for i in 6:
			wants[f.brain.choose_action()] = int(wants.get(
				f.brain.choose_action(), 0)) + 1
	print("")
	print("[IDLE] replans %d -> %d started, %d no destination, %d no route, "
		% [replans, started, no_target, no_route]
		+ "%d refused" % refused)
	if replans > 0:
		print("[IDLE] %.0f%% of replans produced an actual job"
			% (100.0 * float(started) / float(replans)))
	var sorted: Array = wants.keys()
	sorted.sort_custom(func(a, b): return int(wants[a]) > int(wants[b]))
	var head: Array[String] = []
	for k in sorted:
		head.append("%s %d" % [String(k) if String(k) != "" else "(wander)",
							   int(wants[k])])
	print("[IDLE] what they want right now: %s" % ", ".join(head))

	# WHY do routes fail? The likeliest cause with fifty builders on one plot
	# is that they wall each other in: every hut blocks a 5x5 hole, and enough
	# of them turn open grass into pockets. A flood fill says so outright.
	var seen := {}
	var sizes: Array[int] = []
	var g = _root.grid
	for row in g.rows:
		for col in g.cols:
			var start := Vector2i(col, row)
			if not g.is_walkable(start) or seen.has(start):
				continue
			var n := 0
			var stack: Array[Vector2i] = [start]
			seen[start] = true
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				n += 1
				for d in WalkGrid.NEIGHBOURS:
					var nb: Vector2i = c + d
					if g.is_walkable(nb) and not seen.has(nb):
						seen[nb] = true
						stack.append(nb)
			sizes.append(n)
	sizes.sort()
	sizes.reverse()
	print("[IDLE] walkable regions now: %s (%d in total)"
		% [str(sizes.slice(0, 6)), sizes.size()])
	print("[IDLE] structures: %s" % str(_root.village.structures))
	print("[IDLE] peak resource tokens in flight: %d" % _peak_floaters)
	if _peak_floaters == 0:
		printerr("[IDLE] FAIL: not one job produced a floating token, so no "
			+ "completed work was ever visible to the player.")
