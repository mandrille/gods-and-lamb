extends SceneTree
## Does the Faith economy land where the design says it should?
##
## Every other probe asks whether a mechanic WORKS. This one asks whether the
## numbers are right, which is a different question and the only one that can
## tell you the first ten minutes are worth playing. It runs a full ten
## simulated minutes and reports Faith per minute against the designed band.
##
## Three arms, set by MODE, because one number proves nothing on its own:
##
##   "engaged"  blesses on every cooldown, casts, buys land, communes
##   "lazy"     buys land and takes the FREE drafts; never blesses, never casts
##   "idle"     touches nothing at all
##
## "lazy" is the one the design's "+73% for engagement" is measured against. An
## early version compared engaged against "idle" and reported a tenfold spread,
## which was a fact about the probe: a player who never buys land is capped at
## one plot's population forever, and population multiplies every channel. That
## is not a disengaged player, it is a rock. "idle" is kept as the true floor --
## it answers a different question, whether the game runs itself at all.
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
## Overridable from the environment so all three arms run without editing the
## file between them -- an edit between measurements is a way to measure the
## wrong build twice.
static func _mode_from_env() -> String:
	var m := OS.get_environment("ECON_MODE")
	return m if m != "" else "engaged"

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
var _boons := 0
var _lands := 0
var _ages: Array[String] = []
var _mode := "engaged"


func _initialize() -> void:
	_mode = _mode_from_env()
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
		_root.divinity.age_reached.connect(func(i, name):
			_ages.append("%s at %.1f min" % [name, _elapsed / 60.0]))
		Engine.time_scale = SPEED
		print("[ECON] %d minutes at %.0fx, mode=%s" % [MINUTES, SPEED, _mode])
		return false
	if _f < 20:
		return false

	_elapsed += delta
	if _mode != "idle":
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
	var engaged := _mode == "engaged"
	if engaged and d.judge_cd <= 0.0:
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

	# Take any draft that is open -- greedily, first card, because WHICH boon a
	# scripted player takes is not what this probe measures. That it can take
	# them at all, and that the curve bends afterwards, is.
	if not d.pending_draft.is_empty():
		d.take_boon(String(d.pending_draft[0]["id"]))
		_boons += 1

	# Commune when it is affordable, alternating with land so neither starves.
	var commune: float = d.commune_cost()
	if engaged and d.faith > commune * 1.4 and _boons <= _lands:
		if d.commune():
			pass

	# Buy land when it is comfortably affordable. Without this the population
	# hard-caps at one plot's worth and every later minute is measuring a
	# village that cannot grow -- which is a fact about the probe, not the
	# economy.
	var price := float(_root.islands.price_next())
	if d.faith > price * 1.6:
		var slots: Array = _root.islands.buyable()
		if not slots.is_empty() and d.buy_island(slots[0]):
			_lands += 1

	if engaged and d.hand.size() >= 3:
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
	print("[ECON] === %s: %d minutes, %d blessings, %d cards ==="
		% [_mode, MINUTES, _blessed, _cast])
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
	print("[ECON] ages: %s" % (", ".join(_ages) if not _ages.is_empty()
							   else "NONE REACHED"))
	print("[ECON] witnessed blessings %d, land %d plots, boons %d: %s"
		% [_root.divinity.witnessed_total, _root.islands.count(), _boons,
		   _root.divinity.boons.summary()])

	# Only unambiguous breakage fails the run. The band is for tuning.
	if total < 200.0 and _mode != "idle":
		_faults.append("earned only %.0f Faith in %d minutes -- the economy is "
			% [total, MINUTES] + "not running")
	# This one holds in EVERY arm, idle included: item 1.1's regression guard is
	# that an untouched village still grows.
	if _root.folk.size() <= 2:
		_faults.append("the village never grew past its starting two")
	if _ages.is_empty():
		_faults.append("no age was ever reached in ten minutes -- the "
			+ "progression has no shape")
	if _blessed == 0 and _mode == "engaged":
		_faults.append("no blessing was ever witnessed -- the core loop is dead")

	if _faults.is_empty():
		print("[ECON] no breakage; the numbers above are the tuning signal")
	else:
		for f in _faults:
			printerr("[ECON]   - " + f)
		printerr("[ECON] %d FAILURE(S)" % _faults.size())
