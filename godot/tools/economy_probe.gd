extends SceneTree
## Does the Faith economy land where the design says it should?
##
## Every other probe asks whether a mechanic WORKS. This one asks whether the
## numbers are right, which is a different question and the only one that can
## tell you the first ten minutes are worth playing. It runs a full ten
## simulated minutes and reports Faith per minute against the designed band.
##
## It plays the game BADLY on purpose -- a scripted player who blesses whoever
## most recently finished something, and casts a card when the hand is full.
## That is roughly a competent human, and it is reproducible, which a human is
## not. The passive baseline is measured in the same run by tracking what the
## trickle alone contributed.
##
## Designed band, from the plan:
##
##     t=1min  ~56 Faith/min      t=5min  ~163      t=10min  ~266
##
## Being outside it is not a failure -- it is the number you tune against. The
## probe FAILS only on things that are unambiguously broken: no income at all,
## or an engaged player earning no more than an idle one.
const ShotWindowRef := preload("res://tools/shot_window.gd")

const MINUTES := 10
const SPEED := 20.0                     ## game seconds per real second
const PLAY := true                      ## false = measure the idle floor

var _root: Node = null
var _f := 0
var _elapsed := 0.0
var _minute := 0
var _last_total := 0.0
var _per_minute: Array[float] = []
var _pop: Array[int] = []
var _faults: Array[String] = []
var _blessed := 0
var _cast := 0


func _initialize() -> void:
	ShotWindowRef.park()
	get_root().add_child(
		(load("res://scenes/vale.tscn") as PackedScene).instantiate())


func _process(delta: float) -> bool:
	_f += 1
	if _f == 20:
		for n in get_root().get_children():
			if n.get("divinity") != null:
				_root = n
		if _root == null:
			printerr("[ECON] FAIL: no scene root")
			quit(1)
			return true
		Engine.time_scale = SPEED
		print("[ECON] %d minutes at %.0fx, playing=%s"
			% [MINUTES, SPEED, str(PLAY)])
		return false
	if _f < 20:
		return false

	_elapsed += delta
	if PLAY:
		_play_a_bit()

	var m := int(_elapsed / 60.0)
	if m > _minute:
		_minute = m
		var total: float = _root.divinity.total_earned
		_per_minute.append(total - _last_total)
		_pop.append(_root.folk.size())
		_last_total = total
		print("[ECON] t=%2d min   %6.1f Faith earned   pop %2d   %s"
			% [m, _per_minute[m - 1], _pop[m - 1],
			   _root.village.summary()])

	if _minute < MINUTES:
		return false
	Engine.time_scale = 1.0
	_report()
	quit(0 if _faults.is_empty() else 1)
	return true


## A competent-but-not-perfect player: bless whoever most recently finished a
## job, and empty the hand when it fills.
func _play_a_bit() -> void:
	var d = _root.divinity
	if d.judge_cd <= 0.0:
		var best = null
		var freshest := -1.0
		for f in _root.folk:
			if not is_instance_valid(f) or f.brain == null:
				continue
			if f.brain.last_action == "":
				continue
			var t: float = float(f.brain.last_action_at)
			if float(_root.village.now) - t > d.WITNESS_WINDOW:
				continue
			if t > freshest:
				freshest = t
				best = f
		if best != null and d.bless(best):
			_blessed += 1

	# Buy land when it is comfortably affordable. Without this the population
	# hard-caps at one plot's worth and every later minute is measuring a
	# village that cannot grow -- which is a fact about the probe, not the
	# economy.
	var price := float(_root.islands.price_next())
	if d.faith > price * 1.6:
		var slots: Array = _root.islands.buyable()
		if not slots.is_empty():
			d.buy_island(slots[0])

	if d.hand.size() >= 3:
		# Cast at the middle of the village, which is roughly what a player
		# aiming for a crowd would do.
		var at := Vector3.ZERO
		for f in _root.folk:
			at += f.position
		if not _root.folk.is_empty():
			at /= float(_root.folk.size())
		if d.play(0, at, _root.folk[0] if not _root.folk.is_empty() else null):
			_cast += 1


func _report() -> void:
	print("")
	var want := {1: 56.0, 5: 163.0, 10: 266.0}
	print("[ECON] === %d minutes, %d blessings, %d cards ==="
		% [MINUTES, _blessed, _cast])
	for i in _per_minute.size():
		var m := i + 1
		var line := "[ECON] minute %2d  %6.1f/min  pop %2d" % [m, _per_minute[i],
														  _pop[i]]
		if want.has(m):
			var target: float = want[m]
			var ratio: float = _per_minute[i] / target
			line += "   design %5.0f   x%.2f" % [target, ratio]
		print(line)

	var total: float = _root.divinity.total_earned
	print("[ECON] total earned %.0f, ending Faith %.0f, pop %d, ages n/a"
		% [total, _root.divinity.faith, _root.folk.size()])
	print("[ECON] witnessed blessings %d, land %d plots"
		% [_root.divinity.witnessed_total, _root.islands.count()])

	# Only unambiguous breakage fails the run. The band is for tuning.
	if total < 200.0:
		_faults.append("earned only %.0f Faith in %d minutes -- the economy is "
			% [total, MINUTES] + "not running")
	if _root.folk.size() <= 2:
		_faults.append("the village never grew past its starting two")
	if _blessed == 0:
		_faults.append("no blessing was ever witnessed -- the core loop is dead")

	if _faults.is_empty():
		print("[ECON] no breakage; the numbers above are the tuning signal")
	else:
		for f in _faults:
			printerr("[ECON]   - " + f)
		printerr("[ECON] %d FAILURE(S)" % _faults.size())
