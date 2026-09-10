extends SceneTree
## Something to be doing for the next five minutes.
##
## The game has ages, which are an hour, and prayers, which are ninety seconds,
## and between them it has had nothing -- no reason to sit down for THIS session
## rather than any other. A prophecy is the middle rung.
##
## The things worth asserting are the ones that would turn it into a quest log
## or into a punishment:
##
##   - nobody speaks one when there is no prophet
##   - it is never already true when it is spoken
##   - it measures the world, not a number kept for it
##   - fulfilling one pays, and settles it
##   - missing one costs NOTHING, which is the whole design
##   - one at a time, with a breath between
##   - every kind is reachable and every kind is legible
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
		printerr("[SEER] FAIL: no scene root")
		quit(1)
		return true
	TestGroundRef.green(_root)

	_check_table()
	_check_needs_a_prophet()
	_check_never_born_true()
	_check_measures_the_world()
	_check_fulfilment_pays()
	_check_missing_costs_nothing()
	_check_one_at_a_time()
	_report()
	quit(0 if _faults.is_empty() else 1)
	return true


func _now() -> float:
	return float(_root.village.now)


## Seat a prophet so prophecies are possible at all.
func _seat() -> void:
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null and f.brain.adult:
			f.brain.faith_level = Prophet.NEEDS_LEVEL
			break
	_root.divinity.prophet.choose(_root.folk)


func _unseat() -> void:
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null:
			f.brain.faith_level = 0
	_root.divinity.prophet.who = null


func _reset() -> void:
	_root.prophecies.current = null
	_root.prophecies._next_at = -1.0


## Every kind must be measurable, sayable and showable. A kind with no line is
## a prophecy the player is never told about.
func _check_table() -> void:
	for kind in Prophecy.KINDS:
		var row: Dictionary = Prophecy.KINDS[kind]
		for key in ["step", "icon", "says", "short"]:
			if not row.has(key):
				_faults.append("%s has no '%s'" % [kind, key])
		if int(row.get("step", 0)) < Prophecies.MIN_ROOM:
			_faults.append("%s asks for %d more than you have, which is not a "
				% [kind, int(row.get("step", 0))] + "prophecy")
		# And it must actually read something rather than fall through to 0.
		var p := Prophecy.new(String(kind), 999, _now())
		p.at(_root)
	print("[SEER] %d kinds, all measurable: %s"
		% [Prophecy.KINDS.size(), str(Prophecy.KINDS.keys())])


## NO PROPHET, NO PROPHECY. Not a balance gate -- there is nobody to say it.
func _check_needs_a_prophet() -> void:
	_reset()
	_unseat()
	var now := _now()
	_root.prophecies.tick(now)
	_root.prophecies.tick(now + Prophecies.REST * 3.0)
	if _root.prophecies.current != null:
		_faults.append("a village with nobody to speak for it was still "
			+ "foretold something")
	print("[SEER] with no prophet, %d prophecies"
		% (0 if _root.prophecies.current == null else 1))


## It is never true the moment it is spoken.
func _check_never_born_true() -> void:
	_reset()
	_seat()
	var now := _now()
	# Twenty times over, because the kind is shuffled and a single run only
	# tests whichever one came up first.
	for i in 20:
		_reset()
		_root.prophecies.tick(now)
		_root.prophecies.tick(now + Prophecies.REST + 1.0)
		var p = _root.prophecies.current
		if p == null:
			_faults.append("a village with a prophet was foretold nothing")
			break
		if p.done(_root):
			_faults.append("'%s' was already fulfilled when it was spoken: "
				% p.kind + "%d against a target of %d" % [p.at(_root), p.need])
			break
		if p.spoken == "":
			_faults.append("'%s' was foretold silently" % p.kind)
			break
	print("[SEER] twenty prophecies, none of them already true")


## It reads the world. Move the world, and the number moves.
func _check_measures_the_world() -> void:
	_reset()
	_seat()
	var before := Prophecy.read("faithful", _root)
	var lifted := 0
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null and f.brain.adult \
				and int(f.brain.faith_level) < 2:
			f.brain.faith_level = 2
			lifted += 1
	var after := Prophecy.read("faithful", _root)
	if lifted > 0 and after <= before:
		_faults.append("%d villagers reached Believer and the count did not "
			% lifted + "move: %d then %d" % [before, after])
	# And the food reading is the store, not a tally of its own.
	var food_before := Prophecy.read("food", _root)
	_root.village.give({"food": 3})
	if Prophecy.read("food", _root) <= food_before:
		_faults.append("food went into the store and the prophecy did not see "
			+ "it")
	print("[SEER] believers %d -> %d, and food follows the store"
		% [before, after])


## Being right pays, and closes it.
func _check_fulfilment_pays() -> void:
	_reset()
	_seat()
	var now := _now()
	var p := Prophecy.new("food", Prophecy.read("food", _root) + 2, now)
	_root.prophecies.current = p
	var faith_before := float(_root.divinity.faith)
	_root.village.give({"food": 5})
	_root.prophecies.tick(now + 1.0)
	if _root.prophecies.current != null:
		_faults.append("the prophecy came true and stayed open")
	if float(_root.divinity.faith) <= faith_before:
		_faults.append("being right was worth nothing: %.1f then %.1f"
			% [faith_before, float(_root.divinity.faith)])
	print("[SEER] fulfilled: %.0f Faith -> %.0f"
		% [faith_before, float(_root.divinity.faith)])


## AND MISSING ONE COSTS NOTHING. There is no penalty anywhere in this game for
## not doing something, and a timer you are punished for missing turns an idle
## game into a job.
func _check_missing_costs_nothing() -> void:
	_reset()
	_seat()
	var now := _now()
	var p := Prophecy.new("food", Prophecy.read("food", _root) + 9999, now)
	_root.prophecies.current = p
	var faith_before := float(_root.divinity.faith)
	var folk_before: int = _root.folk.size()
	var standing := _standing()
	_root.prophecies.tick(now + Prophecy.WINDOW + 1.0)
	if _root.prophecies.current != null:
		_faults.append("the hour passed and the prophecy is still standing")
	if float(_root.divinity.faith) < faith_before:
		_faults.append("missing a prophecy cost %.1f Faith"
			% (faith_before - float(_root.divinity.faith)))
	if _root.folk.size() < folk_before:
		_faults.append("missing a prophecy cost a villager")
	if _standing() < standing - 0.001:
		_faults.append("missing a prophecy cost %.2f of the village's opinion"
			% (standing - _standing()))
	print("[SEER] missed one: Faith %.0f -> %.0f, standing %.2f -> %.2f"
		% [faith_before, float(_root.divinity.faith), standing, _standing()])


## One at a time, and a breath between.
func _check_one_at_a_time() -> void:
	_reset()
	_seat()
	var now := _now()
	_root.prophecies.tick(now)
	_root.prophecies.tick(now + Prophecies.REST + 1.0)
	var first = _root.prophecies.current
	if first == null:
		_faults.append("nothing was foretold")
		return
	_root.prophecies.tick(now + Prophecies.REST + 2.0)
	if _root.prophecies.current != first:
		_faults.append("a second prophecy replaced the first while it stood")
	# Settle it, and nothing new arrives until the rest has passed.
	_root.prophecies.current = null
	_root.prophecies._next_at = now + Prophecies.REST * 3.0
	_root.prophecies.tick(now + Prophecies.REST * 2.0)
	if _root.prophecies.current != null:
		_faults.append("the next prophecy arrived before the breath between "
			+ "them was over")
	print("[SEER] one at a time, with %.0fs between" % Prophecies.REST)


func _standing() -> float:
	var total := 0.0
	var n := 0
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null:
			total += float(f.brain.memories.divine_standing())
			n += 1
	return total / maxf(1.0, float(n))


func _report() -> void:
	for f in _faults:
		print("  - %s" % f)
	if _faults.is_empty():
		print("[SEER] the hour is foretold")
	else:
		print("[SEER] %d FAILURE(S)" % _faults.size())
