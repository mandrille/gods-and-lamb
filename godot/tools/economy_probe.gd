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
## The band is PER ARM, re-derived, and MEASURED OVER THREE RUNS EACH.
##
## The original single band (56 / 163 / 266) came from the plan and described a
## village that capped at seven or nine people. Two things moved it out from
## under itself: the population work (three plots now reach twenty-plus) and
## the income floor (see Divinity.income_per_s).
##
## It is also far noisier than one run can show. Nine runs, Faith per minute at
## minute ten:
##
##     engaged   1494, 838, 797     median  838
##     lazy       110, 156, 267     median  156
##     idle        36,  38,  47     median   38
##
## RE-MEASURED after the greening tide and after witness bands + novelty
## (three runs each, minute ten):
##
##     engaged   1377, 1448, 1568   median 1448
##     lazy       177,  178,  180   median  178
##     idle        42,   43,   43   median   43
##
## AND THE ENGAGED ARM CAN NO LONGER MEASURE ANYTHING. Two runs of the build
## immediately before bands and novelty gave 478 and 1311 -- a 2.7x spread from
## one build, wider than any change either of us would make on purpose. The
## cause is the tide: greening now reaches a plot in a few taps, so The First
## Roof lands at 1.1 min instead of 6.1, and whether the later ages fall inside
## ten minutes swings the total by the 1230 Faith their lumps are worth. The
## number is dominated by a coin flip about age timing.
##
## So: the lazy arm is the control and it is the one to trust -- it never
## touches the world, so nothing about terrain payouts can reach it, and it did
## not move (171 before, 178 after). Do not read the engaged median as a tuning
## signal at n=3. If it has to become one again, the fix is to report Faith per
## minute EXCLUDING age lumps, which is the term that actually varies.
##
## THE LAZY AND IDLE ARMS FAIL, and have since the desert start went in --
## verified on the build before bands and novelty, which also reached no age.
## A village whose player never touches the ground never greens, so it has no
## wood, so it builds nothing, so it passes no age gate. That is a real design
## problem rather than a probe bug (the design says villagers should usually
## solve their own problems), and it is left failing on purpose: the sweep only
## runs the engaged arm, so nothing is hidden by it, and weakening the bar to
## make it green would delete the only thing pointing at it.
##
## A single sample of the lazy arm has landed anywhere from 110 to 768 across
## the day. The village's fate is emergent -- whether a farm goes up early,
## whether wolves come, whether mood spirals -- so ONE number is not a band and
## anything tuned against one is tuned against noise. Only minute ten is
## pinned; minutes one and five swing harder still and are left informational.
##
## WHAT THE NUMBERS SAY, and it is a design question rather than a bug:
## engagement is worth about 5x (838 against 156), where the design asks for
## about 1.7x. Before the income floor came up it read as 20x, but that was the
## lazy arm COLLAPSING -- 51 Faith/min at minute ten, less than an idle player
## -- rather than the engaged arm running away. The floor fixed the collapse
## (lazy is now 110-267 where it was 51-58) and left the real gap visible. To
## close it further the levers are WITNESS_FAITH and WORK_BONUS, and pulling
## them is a decision about how much attention should be worth in a portal
## game, not a tuning nit -- so they are untouched here.
##
## THE OPEN QUESTION: at minute ten a lazy village has food 432/432, wood
## 256/256 and stone 160/160 with its people at mood -0.54 and devotion 0.08.
## Full warehouses and wretched villagers. No income formula can fix that; it
## is a needs-simulation problem, and it is why the idle arm still declines.
##
## Being outside a band is not a failure -- it is the number you tune against.
## The probe FAILS only on things that are unambiguously broken: no income at
## all, or an engaged player earning no more than an idle one.
## Medians of three runs each, minute ten only. See the note above.
const BAND := {
	"engaged": {10: 838.0},
	"lazy": {10: 156.0},
	"idle": {10: 38.0},
}
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
var _greened := 0
var _grew := 0
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
		# MOOD AND DEVOTION, not just the money. Faith per head is scaled by
		# both, so a village whose income is falling is telling you something
		# about how its people are doing -- and without these two columns the
		# only reading available was "the number went down", which invites
		# tuning the wrong constant.
		#
		# Devotion comes from `brain.devotion()` now. It used to be read out of
		# `stats["faith"]`, and when faith stopped being a need and became a
		# per-villager LEVEL that key went away -- so this printed an error per
		# minute and aborted the run rather than reporting a number.
		var mood := 0.0
		var devotion := 0.0
		var n := 0
		for f in _root.folk:
			if is_instance_valid(f) and f.brain != null:
				mood += f.brain.mood()
				devotion += f.brain.devotion()
				n += 1
		if n > 0:
			mood /= float(n)
			devotion /= float(n)
		print("[ECON] t=%2d min   %6.1f Faith earned   pop %2d   mood %+.2f   "
			% [m, _per_minute[m - 1], _pop[m - 1], mood]
			+ "devotion %.2f   %s" % [devotion, _root.village.summary()])

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

	# AND TOUCH THE WORLD, which is the verb this probe was written before.
	#
	# The plot arrives as bare desert now: no trees, therefore no wood, and a
	# village with no wood builds nothing and reaches no age. Measured before
	# this was added -- wood sat at 3 for the whole ten minutes, no age was
	# ever reached, and the probe reported it as an economy failure. It was not
	# one. An engaged player greens ground and grows trees on it, so the
	# engaged arm has to as well or it is modelling a player who has not
	# learned the first thing the game teaches.
	if engaged:
		_touch_something()

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


## One touch, on the most useful thing in reach: bare ground becomes grass,
## grass grows a tree. Rate-limited by the game's own shared cooldown, so this
## cannot touch faster than a player could.
func _touch_something() -> void:
	if not _root._touch_ready():
		return
	var dirt := Vector2i(-1, -1)
	var grass := Vector2i(-1, -1)
	for row in _root.builder.lower.size():
		var line: String = _root.builder.lower[row]
		for col in line.length():
			var c := Vector2i(col, row)
			if not _root.grid.is_walkable(c):
				continue
			if line[col] == "G":
				# Room for the thing this square would actually grow, footprint
				# and all -- a tree covers its neighbours, so about half of all
				# grass has no room on it.
				if grass.x < 0 and not _root._prop_on(c) 						and not _root.builder.would_overlap(
							WorldTouch.seed_for(c), c.x, c.y):
					grass = c
			elif line[col] == "D" and dirt.x < 0:
				dirt = c
		if grass.x >= 0 and dirt.x >= 0:
			break
	# Grass first: a tree is what the village is actually short of, and greening
	# every tile before planting anything is not how a person plays either.
	var at: Vector2i = grass if grass.x >= 0 else dirt
	if at.x < 0:
		return
	var props: int = _root.builder.placed_props.size()
	_root._on_ground(_root.grid.world_of(at))
	if _root.builder.placed_props.size() > props:
		_grew += 1
	elif _root.builder.code_at(_root.builder.lower, at.x, at.y) == "G":
		_greened += 1


func _report() -> void:
	print("")
	var want: Dictionary = BAND.get(_mode, BAND["lazy"])
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
	# What the god actually DID to the ground. Without these two counters a run
	# where every touch was silently refused looks identical to a run where the
	# economy is simply weak -- which is exactly how a shared-cooldown bug got
	# read as an income problem for two full sweeps.
	var built := 0
	for aid in _root.village.structures:
		if String(aid).begins_with("Buildings/"):
			built += 1
	print("[ECON] the god greened %d tiles, grew %d things; %d building kinds "
		% [_greened, _grew, built] + "stand")
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
