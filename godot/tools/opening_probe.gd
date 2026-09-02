extends SceneTree
## What actually happens in the first five minutes?
##
## The brief: "I want them to chop and build something in the first 30s", and
## "on 5min you should have some sort of village and be making decisions".
## Both are about the OPENING, which every other probe skips past -- the
## economy probe reports per-minute totals and the idle probe runs a village
## that already exists. This one watches the first moments and timestamps them.
const ShotWindowRef := preload("res://tools/shot_window.gd")

const SPEED := 8.0
const MINUTES := 5.0

var _f := 0
var _root: Node = null
var _t := 0.0
var _marks: Dictionary = {}
var _faults: Array[String] = []
var _next_min := 1
var _shots := 0


func _initialize() -> void:
	ShotWindowRef.park()
	get_root().add_child(
		(load("res://scenes/vale.tscn") as PackedScene).instantiate())


func _mark(key: String) -> void:
	if not _marks.has(key):
		_marks[key] = _t
		print("[OPEN] %6.1fs  %s" % [_t, key])


func _process(delta: float) -> bool:
	_f += 1
	if _f == 20:
		for n in get_root().get_children():
			if n.get("divinity") != null:
				_root = n
		if _root == null:
			printerr("[OPEN] FAIL: no scene root")
			quit(1)
			return true
		_root.divinity.age_reached.connect(func(_i, nm): _mark("age: " + nm))
		_root.divinity.draft_offered.connect(func(_o, src):
			_mark("a decision to make (draft: %s)" % src)
			# Take it, so the run continues like a played game rather than
			# stalling behind an overlay nobody clicks.
			_root.divinity.take_boon(String(_root.divinity.pending_draft[0]["id"])))
		for f in _root.folk:
			f.finished.connect(func(act): _mark("first %s finished" % act))
		Engine.time_scale = SPEED
		print("[OPEN] start: %d folk, %s"
			% [_root.folk.size(), _root.village.summary()])
		return false
	if _f < 20:
		return false

	_t += delta
	if _root.village.amount("wood") > 0:
		_mark("first wood in the store")
	var built := 0
	for e in _root.builder.placed_props:
		var aid := String(e["id"])
		if aid.begins_with("Buildings/") and aid != "Buildings/bridge":
			built += 1
	if built > 0:
		_mark("first building standing")
	if built >= 3:
		_mark("three buildings standing")
	if _root.folk.size() >= 4:
		_mark("four followers")

	# A picture at the moments the brief is about: "something in the first 30s"
	# and "a village by 5 min".
	if _shots == 0 and _t >= 30.0:
		_shots = 1
		get_root().get_texture().get_image().save_png(
			"res://shots/opening_30s.png")
	if _shots == 1 and _t >= 300.0:
		_shots = 2
		get_root().get_texture().get_image().save_png(
			"res://shots/opening_5min.png")

	if _t >= float(_next_min) * 60.0:
		print("[OPEN] --- %d min: pop %d, %d buildings, %.0f Faith, %s"
			% [_next_min, _root.folk.size(), built, _root.divinity.faith,
			   _root.village.summary()])
		_next_min += 1

	if _t < MINUTES * 60.0:
		return false
	Engine.time_scale = 1.0
	_report(built)
	quit(0 if _faults.is_empty() else 1)
	return true


func _report(built: int) -> void:
	print("")
	var chop: float = float(_marks.get("first chop finished", 9999.0))
	var first: float = float(_marks.get("first building standing", 9999.0))
	print("[OPEN] first chop %.1fs, first building %.1fs (want both under 30s)"
		% [chop, first])
	if chop > 30.0:
		_faults.append("nobody finished chopping until %.0fs" % chop)
	if first > 30.0:
		_faults.append("nothing was built until %.0fs -- the opening is empty"
			% first)
	var decision: float = float(_marks.get_or_add("", 0.0))
	var any_draft := false
	for k in _marks:
		if String(k).begins_with("a decision"):
			any_draft = true
	if not any_draft:
		_faults.append("no decision was ever offered in five minutes")
	if built < 3:
		_faults.append("only %d building(s) after five minutes -- that is not "
			% built + "a village")
	if _faults.is_empty():
		print("[OPEN] the opening lands")
	else:
		for f in _faults:
			printerr("[OPEN]   - " + f)
		printerr("[OPEN] %d FAILURE(S)" % _faults.size())
