extends SceneTree
## Does the day actually end, and can the player see it coming?
##
## The countdown is the first thing a stranger reads on this screen and the
## only thing that says the eight minutes are going somewhere. So it is worth
## asserting rather than eyeballing: that a day rolls over exactly once however
## coarse the tick, that the clock counts DOWN, that nightfall fires once and
## is announced, and that the day survives closing the tab.
##
## It also photographs the bar at dawn, midday and dusk, because "the sun turns
## into a moon" is a claim about pixels and only a picture can settle it.
const ShotWindowRef := preload("res://tools/shot_window.gd")

var _f := 0
var _root: Node = null
var _faults: Array[String] = []
var _nights: Array[int] = []
var _shots := 0
var _stage := 0


func _initialize() -> void:
	ShotWindowRef.park()
	get_root().add_child(
		(load("res://scenes/vale.tscn") as PackedScene).instantiate())


func _process(_d: float) -> bool:
	_f += 1
	if _f < 25:
		return false
	if _f == 25:
		for n in get_root().get_children():
			if n.get("divinity") != null:
				_root = n
		if _root == null or _root.get("daylight") == null:
			printerr("[DAY] FAIL: no scene root, or no day clock on it")
			quit(1)
			return true
		_root.daylight.night_fell.connect(func(d: int): _nights.append(d))
		_check_clock()
		_check_rollover()
		_check_save()
		# Back to a fresh morning for the pictures.
		_root.draft.close()
		_root.divinity.pending_draft = []
		_root.daylight.day = 1
		return false

	# Three pictures, each set up one frame and shot the next: the shutter has
	# to fall AFTER the frame that changed the state, or it photographs the
	# frame before it.
	var want := [0.04, 0.55, 0.97]
	var names := ["day_dawn", "day_noon", "day_dusk"]
	if _stage < want.size():
		if _f % 6 == 0:
			_root.daylight.t = Daylight.DAY_SECONDS * want[_stage]
			_root._sky_for(_root.daylight.dusk_amount())
			_root.hud.queue_redraw()
		elif _f % 6 == 3:
			get_root().get_texture().get_image().save_png(
				"res://shots/%s.png" % names[_stage])
			print("[DAY] wrote res://shots/%s.png at %s left, dusk %.2f"
				% [names[_stage], _root.daylight.clock(),
				   _root.daylight.dusk_amount()])
			_shots += 1
			_stage += 1
		return false

	_report()
	quit(0 if _faults.is_empty() else 1)
	return true


## The clock counts DOWN and reads as a clock.
func _check_clock() -> void:
	var d = _root.daylight
	d.day = 1
	d.t = 0.0
	var first: String = d.clock()
	d.tick(60.0)
	var later: String = d.clock()
	print("[DAY] clock %s -> %s after a minute" % [first, later])
	if first != "8:00":
		_faults.append("a fresh day did not read 8:00, it read %s" % first)
	if later >= first:
		_faults.append("the clock did not count down: %s then %s"
			% [first, later])
	if d.fraction() <= 0.0 or d.fraction() >= 1.0:
		_faults.append("fraction() left 0..1 mid-day: %.3f" % d.fraction())
	# Dusk is a warning that arrives before the end, not at it.
	d.t = Daylight.DAY_SECONDS * 0.5
	if d.is_dusk():
		_faults.append("midday reported as dusk")
	d.t = Daylight.DAY_SECONDS * 0.95
	if not d.is_dusk():
		_faults.append("95% through the day was not dusk")
	if d.dusk_amount() <= 0.0 or d.dusk_amount() > 1.0:
		_faults.append("dusk_amount out of range: %.3f" % d.dusk_amount())


## ONE nightfall per day, however coarse the tick.
##
## A probe at 20x can step past a whole day in a single frame, and a rollover
## that silently ate its own nightfall would be a day the player was never
## told about -- and, once the summary screen exists, a day they were never
## paid for.
func _check_rollover() -> void:
	var d = _root.daylight
	_nights.clear()
	d.day = 1
	d.t = 0.0
	d.tick(Daylight.DAY_SECONDS + 1.0)
	if _nights.size() != 1:
		_faults.append("one long tick past midnight fired %d nightfalls, not 1"
			% _nights.size())
	if d.day != 2:
		_faults.append("after one day the counter read %d, not 2" % d.day)
	# Three days in one step: three nights, not one.
	_nights.clear()
	d.tick(Daylight.DAY_SECONDS * 3.0)
	if _nights.size() != 3:
		_faults.append("three days in one tick fired %d nightfalls, not 3"
			% _nights.size())
	print("[DAY] rollover: %d night(s) over three days, now day %d"
		% [_nights.size(), d.day])
	if d.t < 0.0 or d.t >= Daylight.DAY_SECONDS:
		_faults.append("time of day left its range after rollover: %.1f" % d.t)


## The day is part of the village, so it has to survive the tab closing.
func _check_save() -> void:
	var d = _root.daylight
	d.day = 4
	d.t = 123.5
	var doc: Dictionary = d.to_doc()
	var other := Daylight.new()
	other.from_doc(doc)
	if other.day != 4 or not is_equal_approx(other.t, 123.5):
		_faults.append("the day did not survive a round trip: day %d t %.1f"
			% [other.day, other.t])
	# And a junk document must not produce a day zero or a negative clock.
	var junk := Daylight.new()
	junk.from_doc({"day": -5, "t": 99999.0})
	if junk.day < 1 or junk.t >= Daylight.DAY_SECONDS:
		_faults.append("a corrupt day document produced day %d t %.1f"
			% [junk.day, junk.t])
	print("[DAY] day %d at %.1fs survives a save; junk clamps to day %d"
		% [4, 123.5, junk.day])


func _report() -> void:
	if _shots < 3:
		_faults.append("only %d of 3 pictures were taken" % _shots)
	if _faults.is_empty():
		print("[DAY] ok")
		return
	print("[DAY] %d FAILURE(S)" % _faults.size())
	for f in _faults:
		print("  - %s" % f)
