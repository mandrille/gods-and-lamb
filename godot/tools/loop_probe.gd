extends SceneTree
## Does the core loop actually happen, in an ORDINARY village, and can the
## player tell?
##
## Every other probe in this suite rigs the thing it is testing: it starves a
## villager by hand, forces a feud, seats a prophet, calls `_end_calamity`
## directly. That is the right way to test a mechanism and it is exactly how
## fourteen stages of working systems shipped with the loop invisible.
##
## The owner played the web build and said: "I cant see any villagers asking for
## anything". They were right, and nothing here could have told them otherwise.
## Measured on a real fifteen-minute village, the simulation was never at fault:
## 54 prayers opened, four standing at once, the first at forty seconds. What
## was missing was that a prayer's entire presence was a 13 px near-black disc
## in world space, and `opened` was wired to nothing but an analytics counter.
##
## So this probe rigs NOTHING. It starts a village, lets it run, and asserts
## both halves of the sentence: that the village asks, and that asking is
## audible and visible from where the player is sitting.
const ShotWindowRef := preload("res://tools/shot_window.gd")

## Fast enough to cover a session, slow enough that the sim is not skipping.
const SPEED := 6.0
## How much village time to watch.
const WATCH := 900.0

## A player who has seen nobody ask for anything in four minutes has concluded
## the village does not ask.
const FIRST_BY := 240.0
## And a loop that fires three times an hour is not a loop.
const AT_LEAST := 8

## THE LEGIBILITY FLOOR. The guilt mark -- the other "act on this now" cue in
## the game -- is 11 px on a dark disc, and a prayer stands for longer and
## matters more. Anything under this is the bug that was shipped.
const MIN_RADIUS := 16.0

var _f := 0
var _root: Node = null
var _faults: Array[String] = []
var _opened := 0
var _first := -1.0
var _peak := 0
var _notices := 0
var _said: Array[String] = []
var _wanted: Array[String] = []


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
			printerr("[LOOP] FAIL: no scene root")
			quit(1)
			return true
		Engine.time_scale = SPEED
		_root.prayers.opened.connect(func(p):
			_opened += 1
			if _first < 0.0:
				_first = float(_root.village.now)
			# THE EXACT SENTENCE this prayer would say. Matching on the KINDS
			# templates instead looked rigorous and was not: "%s is low." has a
			# tail of "is low.", which the store shortage notice "Food is low."
			# ends with too -- so the check passed on a build where prayers
			# were announced by nothing at all. An exact string cannot be
			# satisfied by accident.
			if _wanted.size() < 200:
				_wanted.append(p.says()))
		# EVERY LINE THE GAME SAYS, so the probe can ask whether the village
		# asking for something is among them.
		# BOTH LANES. Prayers were promoted to `news`, and a probe watching only
		# `notice` would have reported the village asking in silence while it
		# was in fact announcing every single one -- which is exactly the kind
		# of false failure that teaches people to ignore a suite.
		_root.divinity.notice.connect(func(t: String):
			_notices += 1
			if _said.size() < 200:
				_said.append(t))
		_root.divinity.news.connect(func(t: String, _i: String):
			_notices += 1
			if _said.size() < 200:
				_said.append(t))
		return false
	if _root == null:
		return false
	_peak = maxi(_peak, (_root.prayers.active as Array).size())
	if float(_root.village.now) < WATCH:
		return false

	_check_it_happens()
	_check_it_is_said()
	_check_it_is_drawn()
	_report()
	quit(0 if _faults.is_empty() else 1)
	return true


## The village asks, on its own, without anybody rigging a stat.
func _check_it_happens() -> void:
	if _opened < AT_LEAST:
		_faults.append("%d prayers in %.0f village-seconds -- the village does "
			% [_opened, WATCH] + "not ask for anything often enough to be a loop")
	if _first < 0.0:
		_faults.append("nobody asked for anything at all")
	elif _first > FIRST_BY:
		_faults.append("the first prayer came at %.0fs; a player who has seen "
			% _first + "nobody ask in %.0fs has concluded nobody does" % FIRST_BY)
	if _peak <= 0:
		_faults.append("no prayer was ever standing when the clock was read")
	print("[LOOP] %d prayers in %.0fs, first at %.0fs, %d standing at the peak"
		% [_opened, WATCH, _first, _peak])


## AND IT IS SAID OUT LOUD. This is the assertion that would have caught it:
## the prayers were opening the whole time and nothing ever mentioned one.
func _check_it_is_said() -> void:
	var heard := 0
	for want in _wanted:
		if want in _said:
			heard += 1
	if _wanted.is_empty():
		return
	# Most, not all: the notice stack holds three lines for four seconds, and a
	# burst of prayers in one moment will legitimately push one out before this
	# probe sees it. What is being asserted is that announcing them is WIRED,
	# not that the stack is infinite.
	var share: float = float(heard) / float(_wanted.size())
	if share < 0.5:
		_faults.append(("only %d of %d prayers were ever said out loud (%.0f%%)"
			+ " -- the village is asking in silence")
			% [heard, _wanted.size(), share * 100.0])
	print("[LOOP] %d notices; %d of %d prayers were announced by name"
		% [_notices, heard, _wanted.size()])


## AND IT IS BIG ENOUGH TO SEE. Photographed at the default camera distance, the
## original mark was two specks of grey on grey.
func _check_it_is_drawn() -> void:
	if Overhead.PRAY_R < MIN_RADIUS:
		_faults.append("the prayer mark is %.0f px; under %.0f it is a speck at "
			% [Overhead.PRAY_R, MIN_RADIUS] + "the distance the game is played")
	# There was a rim-luminance check here and it has been REMOVED rather than
	# kept, because it passed on the build that shipped the bug: the old rim was
	# a pale grey at luminance 0.89 and the mark was still invisible. The fill
	# was near-black and the whole thing was 13 px. A check that cannot fail on
	# the exact defect it was written for is worse than no check -- it reads as
	# coverage and provides none.
	print("[LOOP] the mark is %.0f px against a floor of %.0f"
		% [Overhead.PRAY_R, MIN_RADIUS])


func _report() -> void:
	for f in _faults:
		print("  - %s" % f)
	if _faults.is_empty():
		print("[LOOP] the village asks, out loud, where it can be seen")
	else:
		print("[LOOP] %d FAILURE(S)" % _faults.size())
