extends SceneTree
## Where does the frame go?
##
## Reported from play: "the game just runs slow". Runs the real scene at normal
## speed with a realistic village and reports frame time, plus the cost of the
## things most likely to be responsible.
const ShotWindowRef := preload("res://tools/shot_window.gd")

const WARMUP := 90
static func sample() -> int:
	var v := OS.get_environment("PERF_SAMPLE")
	return int(v) if v != "" else 400
static func want_folk() -> int:
	var v := OS.get_environment("PERF_FOLK")
	return int(v) if v != "" else 24

var _f := 0
var _root: Node = null
var _times: Array[float] = []
var _last := 0
var _rebuilds := 0
var _rebuild_us := 0


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
			printerr("[PERF] FAIL: no scene root")
			quit(1)
			return true
		_root.village.pop_cap = 200
		while _root.folk.size() < want_folk():
			if not _root.spawn_villager():
				break
		_root.village.give({"wood": 300, "stone": 300, "food": 300})
		print("[PERF] %d villagers, normal speed" % _root.folk.size())
		return false
	if _f < WARMUP:
		return false

	var now := Time.get_ticks_usec()
	if _last > 0:
		_times.append(float(now - _last) / 1000.0)
	_last = now

	if _times.size() < sample():
		return false
	_report()
	quit(0)
	return true


func _over() -> int:
	var n := 0
	for t in _times:
		if t > 16.7:
			n += 1
	return n


func _report() -> void:
	_times.sort()
	var total := 0.0
	for t in _times:
		total += t
	var n := _times.size()
	var mean := total / float(n)
	print("[PERF] frame ms: mean %.2f  median %.2f  p95 %.2f  worst %.2f"
		% [mean, _times[n / 2], _times[int(float(n) * 0.95)], _times[n - 1]])
	print("[PERF] that is %.0f fps mean, %.0f fps at p95"
		% [1000.0 / maxf(mean, 0.001),
		   1000.0 / maxf(_times[int(float(n) * 0.95)], 0.001)])
	# The other things a felled tree sets off, timed the same way, to find what
	# is left after the grid rebuild stopped dominating.
	var c: Vector2i = _root.builder.cell_of(_root.folk[0].position)
	var t1 := Time.get_ticks_usec()
	var made: bool = _root.builder.add_prop("Nature/stump", c.x + 3, c.y + 3, 0.0)
	print("[PERF] builder.add_prop (instantiates the scene) %.2f ms, ok=%s"
		% [float(Time.get_ticks_usec() - t1) / 1000.0, str(made)])
	var t2 := Time.get_ticks_usec()
	_root.village.census(_root.builder.placed_props)
	print("[PERF] village.census %.2f ms"
		% [float(Time.get_ticks_usec() - t2) / 1000.0])
	var t3 := Time.get_ticks_usec()
	_root.fxe.burst("chop", _root.folk[0].position)
	print("[PERF] fxe.burst %.2f ms"
		% [float(Time.get_ticks_usec() - t3) / 1000.0])
	var t4 := Time.get_ticks_usec()
	_root.pick.setup(_root.rig, _root.builder, _root.builder.placed_props)
	print("[PERF] pick.setup %.2f ms"
		% [float(Time.get_ticks_usec() - t4) / 1000.0])

	# One rebuild timed in isolation, for reference against the frame times.
	var t0 := Time.get_ticks_usec()
	_root.rebuild_grid()
	print("[PERF] one rebuild_grid costs %.2f ms"
		% [float(Time.get_ticks_usec() - t0) / 1000.0])
	print("[PERF] frames over 16.7 ms: %d of %d" % [_over(), _times.size()])
	print("[PERF] grid: %d changes asked for -> %d rebuilds actually paid for"
		% [_root.n_grid_requests, _root.n_grid_rebuilds])
	print("[PERF] nodes %d, props %d, folk %d"
		% [get_root().get_child_count(true),
		   _root.builder.placed_props.size(), _root.folk.size()])
	print("[PERF] draw calls %d, primitives %d"
		% [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		   Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	print("[PERF] process %.2f ms, physics %.2f ms"
		% [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		   Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
