extends SceneTree
## What the game would tell a portal, and what the panel can force.
##
## Every tuning decision in this project has come from a probe measuring an
## ideal player. That is a good way to find bugs and a poor way to find out
## where a real person stops -- and this game is aimed at CrazyGames and
## Playgama, both of which ask the same handful of questions.
##
## The counting is written now, complete and testable, with no network in it at
## all. An SDK is twenty lines of JavaScriptBridge and cannot be written until
## there is a portal build to write it against; what cannot be retrofitted is
## having named the events and kept the counting honest.
##
## What is asserted:
##
##   - a typo is a metric that reads zero, never a second metric
##   - a funnel step lands ONCE, and records how far into the session
##   - depth is the furthest step reached
##   - nothing personal can be recorded, because there is nowhere to put it
##   - the sink is called for everything, exactly once each
##   - the debug panel can force every waiting system without a village running
const ShotWindowRef := preload("res://tools/shot_window.gd")
const TestGroundRef := preload("res://tools/test_ground.gd")

var _f := 0
var _root: Node = null
var _faults: Array[String] = []


func _initialize() -> void:
	ShotWindowRef.park()
	get_root().add_child(
		(load("res://scenes/vale.tscn") as PackedScene).instantiate())


func _process(_d: float) -> bool:
	_f += 1
	if _f < 30:
		return false
	for n in get_root().get_children():
		if n.get("divinity") != null:
			_root = n
	if _root == null:
		printerr("[STATS] FAIL: no scene root")
		quit(1)
		return true
	TestGroundRef.green(_root)

	_check_typos_are_dropped()
	_check_funnel_once()
	_check_depth()
	_check_sink()
	_check_wired_up()
	_check_debug_forces()
	_report()
	quit(0 if _faults.is_empty() else 1)
	return true


## An unnamed metric is dropped. Without this a typo silently creates a second
## counter, both of them read low, and the tuning done off them is wrong.
func _check_typos_are_dropped() -> void:
	var a := Analytics.new()
	a.note("touches")
	a.note("touchez")
	a.reach("first_touchh")
	if a.count("touches") != 1:
		_faults.append("a named counter did not count")
	if a.counts.size() != 1:
		_faults.append("a mistyped counter created a metric: %s"
			% str(a.counts.keys()))
	if not a.firsts.is_empty():
		_faults.append("a mistyped funnel step was recorded")
	print("[STATS] %d counters and %d funnel steps are the only names accepted"
		% [Analytics.COUNTERS.size(), Analytics.FUNNEL.size()])


## A first is a FIRST, and it remembers how far into the session it happened.
func _check_funnel_once() -> void:
	var a := Analytics.new()
	a.begin(100.0)
	a.now = 130.0
	a.reach("first_touch")
	a.now = 400.0
	a.reach("first_touch")
	if not is_equal_approx(float(a.firsts["first_touch"]), 30.0):
		_faults.append("the first touch was recorded at %.0fs into the session "
			% float(a.firsts["first_touch"]) + "rather than 30")
	if a.firsts.size() != 1:
		_faults.append("the same step landed twice")
	print("[STATS] first_touch at %.0fs, and it does not move"
		% float(a.firsts["first_touch"]))


## Depth is the FURTHEST step reached, not the number of steps reached -- a
## player who somehow skipped one has still got that far.
func _check_depth() -> void:
	var a := Analytics.new()
	if a.depth() != 0:
		_faults.append("a session that has done nothing has depth %d" % a.depth())
	a.reach(Analytics.FUNNEL[0])
	a.reach(Analytics.FUNNEL[4])
	if a.depth() != 5:
		_faults.append("reaching step 5 of the funnel reads as depth %d"
			% a.depth())
	var doc := a.to_doc()
	for key in ["session", "depth", "funnel", "counts"]:
		if not doc.has(key):
			_faults.append("the report has no '%s'" % key)
	print("[STATS] two steps in, one of them fifth: depth %d of %d"
		% [a.depth(), Analytics.FUNNEL.size()])


## THE SEAM. Everything goes through the sink, once each, and everything that
## arrives there is a name and a number -- there is nowhere to put anything
## about the person playing, which is the privacy argument made structurally
## rather than in a policy document.
func _check_sink() -> void:
	var a := Analytics.new()
	var seen: Array = []
	a.sink = func(event: String, value: float, _p: Dictionary):
		seen.append([event, value])
	a.begin(0.0)
	a.now = 12.0
	a.note("touches", 3)
	a.reach("first_touch")
	a.note("nonsense")
	if seen.size() != 2:
		_faults.append("the sink saw %d events of two" % seen.size())
		return
	if String(seen[0][0]) != "touches" or not is_equal_approx(float(seen[0][1]), 3.0):
		_faults.append("the counter reached the sink as %s" % str(seen[0]))
	if not String(seen[1][0]).begins_with("funnel:"):
		_faults.append("the funnel step reached the sink as %s" % str(seen[1]))
	print("[STATS] the sink saw %s" % str(seen))


## AND IT IS ACTUALLY WIRED UP. The counting being correct is worth nothing if
## nothing in the game ever calls it, which is the failure this whole file
## exists to prevent.
func _check_wired_up() -> void:
	var s = _root.stats
	if s == null:
		_faults.append("the village keeps no stats at all")
		return
	# AND THE SESSION CLOCK IS THE SESSION, not the age of the village. On a
	# loaded save `Village.now` carries hours of history; a funnel stamped with
	# that would report the first blessing four hours in.
	if s.started <= 0.0 and float(_root.village.now) > 1.0:
		_faults.append("the session clock starts at the dawn of the village "
			+ "rather than when the tab was opened")
	var before: int = s.count("blessings")
	var who = null
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null and f.brain.adult:
			who = f
			break
	if who == null:
		return
	_root.divinity.judged.emit(who, true)
	if s.count("blessings") <= before:
		_faults.append("a blessing happened and nothing counted it")
	if not s.reached("first_bless"):
		_faults.append("the first blessing did not mark the funnel")
	# And a disaster, through the real path.
	var d_before: int = s.count("disasters_started")
	_root.divinity.age = 2
	_root._start_calamity()
	if s.count("disasters_started") <= d_before:
		_faults.append("a calamity started and nothing counted it")
	_root.calamities.clear()
	print("[STATS] the live village counts blessings (%d) and disasters (%d)"
		% [s.count("blessings"), s.count("disasters_started")])


## THE PANEL. Every system built since stage 5 waits on something -- a hungry
## villager, a quiet stretch, six people, four minutes -- which is right for
## playing and hopeless for looking at.
func _check_debug_forces() -> void:
	var m := DebugMenu.new()
	m._host = _root
	for name in ["_force_prayer", "_force_feud", "_force_fire",
				 "_force_prophet", "_force_prophecy", "_force_draft"]:
		if not m.has_method(name):
			_faults.append("the debug panel cannot force %s" % name)
	# The two that must actually produce something, called for real.
	_root.divinity.prophet.who = null
	m._force_prophet()
	if not _root.divinity.prophet.has():
		_faults.append("the panel could not seat a prophet")
	_root.prophecies.current = null
	m._force_prophecy()
	if _root.prophecies.current == null:
		_faults.append("the panel could not make anybody foretell anything")
	_root.divinity.pending_draft = []
	m._force_draft()
	if _root.divinity.pending_draft.is_empty():
		_faults.append("the panel could not deal a gift")
	print("[STATS] the panel seats a prophet, foretells '%s', and deals a gift"
		% (_root.prophecies.current.kind if _root.prophecies.current != null
		   else "nothing"))
	m.free()


func _report() -> void:
	for f in _faults:
		print("  - %s" % f)
	if _faults.is_empty():
		print("[STATS] the game can be counted and forced")
	else:
		print("[STATS] %d FAILURE(S)" % _faults.size())
