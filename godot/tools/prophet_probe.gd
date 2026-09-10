extends SceneTree
## The one who tells the others what you meant.
##
## Faith has only ever travelled one way in this game: the god acts, whoever is
## standing close enough sees it, their belief moves. Nobody has ever told
## anybody anything, so a miracle over the north field is worth nothing at all
## to the four people working the south one.
##
## The prophet is the seam where that changes, and the things worth asserting
## are the ones that would quietly turn them back into an ordinary villager with
## a hat:
##
##   - the title goes to whoever believes hardest, and not to a child
##   - it does not flicker between two people a hair apart
##   - it can be LOST, which is what makes having one mean anything
##   - an act they witness reaches people who did not see it
##   - and never pays twice to somebody who was already there
##   - and pays nothing at all when the prophet was somewhere else
##   - they name the god once per axis, not once per act
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
		printerr("[PROPHET] FAIL: no scene root")
		quit(1)
		return true
	TestGroundRef.green(_root)

	_check_none_at_first()
	_check_chosen_by_faith()
	_check_hysteresis()
	_check_can_be_lost()
	_check_retell()
	_check_retell_needs_the_prophet()
	_check_proclaims_once()
	_report()
	quit(0 if _faults.is_empty() else 1)
	return true


func _adults() -> Array:
	var out: Array = []
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null and f.brain.adult:
			out.append(f)
	return out


func _flatten() -> void:
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null:
			f.brain.faith_level = 0
			f.brain.faith_xp = 0.0
	_root.divinity.prophet.who = null
	_root.divinity.prophet.named = ""
	_root.divinity.prophet._next_look = -1.0


## A village of unbelievers has nobody to speak for it, and that is correct --
## the title has to be reachable, not automatic.
func _check_none_at_first() -> void:
	_flatten()
	_root.divinity.prophet.choose(_root.folk)
	if _root.divinity.prophet.has():
		_faults.append("a village of Atheists produced a prophet -- the title "
			+ "is being handed out rather than earned")
	print("[PROPHET] a village of unbelievers has %d prophets"
		% (1 if _root.divinity.prophet.has() else 0))


## It goes to whoever believes hardest.
func _check_chosen_by_faith() -> void:
	_flatten()
	var folk := _adults()
	if folk.size() < 2:
		_faults.append("fewer than two adults -- nothing to choose between")
		return
	folk[0].brain.faith_level = Prophet.NEEDS_LEVEL
	folk[1].brain.faith_level = Prophet.NEEDS_LEVEL + 1
	_root.divinity.prophet.choose(_root.folk)
	if _root.divinity.prophet.who != folk[1]:
		_faults.append("the title went to %s over %s, who believes more"
			% [_root.divinity.prophet.name_of(), folk[1].brain.name])
	# Read BEFORE the child test, which flattens the village again -- reporting
	# afterwards printed an empty name and made a passing check look broken.
	var took: String = _root.divinity.prophet.name_of()
	# AND NOT TO A CHILD, however devout they are.
	_flatten()
	var kid = null
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null and not f.brain.adult:
			kid = f
			break
	if kid != null:
		kid.brain.faith_level = 4
		_root.divinity.prophet.choose(_root.folk)
		if _root.divinity.prophet.who == kid:
			_faults.append("a child was made prophet")
	print("[PROPHET] the most devout adult takes it: %s, and never a child"
		% took)


## It does not change hands over a rounding error.
func _check_hysteresis() -> void:
	_flatten()
	var folk := _adults()
	if folk.size() < 2:
		return
	folk[0].brain.faith_level = Prophet.NEEDS_LEVEL
	_root.divinity.prophet.choose(_root.folk)
	var first = _root.divinity.prophet.who
	# The incumbent slips one tier -- above the keeping bar, below the winning
	# one -- while a rival sits exactly at the winning bar.
	first.brain.faith_level = Prophet.KEEPS_LEVEL
	for f in folk:
		if f != first:
			f.brain.faith_level = Prophet.KEEPS_LEVEL
	_root.divinity.prophet.choose(_root.folk)
	if _root.divinity.prophet.who != first:
		_faults.append("the title changed hands between two villagers at the "
			+ "same tier -- it will flicker between them forever")
	print("[PROPHET] an incumbent at tier %d keeps it against equals"
		% Prophet.KEEPS_LEVEL)


## And it can be taken away, which is the half that matters.
func _check_can_be_lost() -> void:
	_flatten()
	var folk := _adults()
	if folk.is_empty():
		return
	folk[0].brain.faith_level = Prophet.NEEDS_LEVEL
	_root.divinity.prophet.choose(_root.folk)
	if not _root.divinity.prophet.has():
		_faults.append("could not make a prophet at all")
		return
	# Faith falls away below even the keeping bar.
	folk[0].brain.faith_level = Prophet.KEEPS_LEVEL - 1
	_root.divinity.prophet.choose(_root.folk)
	if _root.divinity.prophet.has():
		_faults.append("a prophet who lost their faith kept the title")
	print("[PROPHET] faith falls below tier %d and the title is gone: %s"
		% [Prophet.KEEPS_LEVEL, not _root.divinity.prophet.has()])


## THE RUMOUR. An act the prophet sees reaches people who did not.
func _check_retell() -> void:
	_flatten()
	var folk := _adults()
	if folk.size() < 2:
		return
	var seer = folk[0]
	var absent = folk[1]
	seer.brain.faith_level = Prophet.NEEDS_LEVEL
	_root.divinity.prophet.choose(_root.folk)
	if _root.divinity.prophet.who != seer:
		_faults.append("could not seat the prophet for the retell check")
		return
	# Stand the other one well outside any witness band but inside earshot.
	absent.position = seer.position + Vector3(Prophet.RETELL_RADIUS * 0.8, 0, 0)
	var before := _faith(absent)

	var a := DivineAction.make("grow", seer.position, 6.0, 4.0)
	a.tags = DivineAction.NATURE
	var r: Dictionary = _root.divinity.perform(a)

	if Prophet.among(r["hits"], absent):
		_faults.append("the supposedly absent villager was inside the witness "
			+ "band -- this check proves nothing")
		return
	var after := _faith(absent)
	if after <= before:
		_faults.append("somebody out of sight of a miracle the prophet watched "
			+ "heard nothing about it")
	if int(r.get("told", 0)) <= 0:
		_faults.append("the report does not say anybody was told")
	# And a secondhand account is worth less than being there.
	var direct := 6.0
	if after - before >= direct:
		_faults.append("hearing about it (%.2f) is worth as much as watching it "
			% (after - before) + "(%.2f)" % direct)
	print("[PROPHET] %d told, and being told is worth %.2f against %.1f for "
		% [int(r.get("told", 0)), after - before, direct] + "being there")


## And no prophet means no rumour. Without this the retell is just a bigger
## witness radius that happens to be spelled differently.
func _check_retell_needs_the_prophet() -> void:
	_flatten()
	var folk := _adults()
	if folk.size() < 2:
		return
	var actor = folk[0]
	var absent = folk[1]
	absent.position = actor.position + Vector3(Prophet.RETELL_RADIUS * 0.8, 0, 0)
	var before := _faith(absent)
	var a := DivineAction.make("grow", actor.position, 6.0, 4.0)
	a.tags = DivineAction.NATURE
	var r: Dictionary = _root.divinity.perform(a)
	if _faith(absent) > before:
		_faults.append("word spread with nobody to spread it")
	if int(r.get("told", 0)) != 0:
		_faults.append("the report claims %d were told with no prophet"
			% int(r.get("told", 0)))
	print("[PROPHET] with no prophet standing there, %d hear about it"
		% int(r.get("told", 0)))


## They name you once per axis, not once per act.
func _check_proclaims_once() -> void:
	_flatten()
	var folk := _adults()
	if folk.is_empty():
		return
	folk[0].brain.faith_level = Prophet.NEEDS_LEVEL
	var p = _root.divinity.prophet
	p.choose(_root.folk)
	var first: String = p.proclaim("Protector", "protector")
	var again: String = p.proclaim("Protector", "protector")
	var changed: String = p.proclaim("Provider", "provider")
	if first == "":
		_faults.append("the prophet had nothing to say about a settled "
			+ "reputation")
	if again != "":
		_faults.append("the prophet repeats itself: '%s'" % again)
	if changed == "":
		_faults.append("the god's reputation changed and the prophet said "
			+ "nothing")
	# And a village with no prophet says nothing at all.
	p.who = null
	if p.proclaim("Provider", "wrath") != "":
		_faults.append("a village with no prophet still proclaimed")
	print("[PROPHET] %s" % first)


func _faith(f) -> float:
	if not is_instance_valid(f) or f.brain == null:
		return 0.0
	return float(f.brain.faith_xp) + float(f.brain.faith_level) * 1000.0


func _report() -> void:
	for f in _faults:
		print("  - %s" % f)
	if _faults.is_empty():
		print("[PROPHET] the word spreads")
	else:
		print("[PROPHET] %d FAILURE(S)" % _faults.size())
