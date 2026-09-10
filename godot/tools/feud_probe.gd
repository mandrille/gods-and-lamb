extends SceneTree
## Two villagers wanting opposite things from the same field.
##
## Every other prayer in the game can be answered by the world quietly sorting
## itself out -- somebody finds a bush, a fire burns down, a fever breaks -- and
## that is deliberate: the village must be able to solve its own problems or the
## game is whack-a-mole with a deity skin on. A feud is the one shape that
## cannot. Nobody is coming to settle it but the player, and settling it means
## disappointing somebody who is standing right there.
##
## So the things worth asserting are the ones that would quietly turn it back
## into two ordinary prayers:
##
##   - a feud never resolves itself, however long it is left
##   - the TAG of what the god does decides it, not the aim and not the timing
##   - answering one DENIES the other, rather than leaving it standing
##   - being denied is remembered, and remembered as the god's doing
##   - it is rare, it needs both camps to exist, and it never doubles up
##   - neither half can ever be opened on its own
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
		printerr("[FEUD] FAIL: no scene root")
		quit(1)
		return true
	TestGroundRef.green(_root)
	_populate()

	_check_table()
	_check_never_settles()
	_check_solo_never_opens()
	_check_tag_decides()
	_check_denial_is_remembered()
	_check_rarity()
	_report()
	quit(0 if _faults.is_empty() else 1)
	return true


## A FEUD NEEDS A VILLAGE. The gate is six people, because a hamlet of three
## does not have two camps in it -- and the probe honours that gate rather than
## reaching past it, so what is being tested is the real path.
func _populate() -> void:
	_root.village.pop_cap = maxi(int(_root.village.pop_cap),
								 Prayers.FEUD_MIN_FOLK + 2)
	var guard := 0
	while _adults().size() < Prayers.FEUD_MIN_FOLK and guard < 40:
		guard += 1
		if not _root.spawn_villager():
			break
	var adults := _adults()
	if adults.size() < Prayers.FEUD_MIN_FOLK:
		_faults.append("could only raise %d adults against a gate of %d -- "
			% [adults.size(), Prayers.FEUD_MIN_FOLK]
			+ "nothing below can be tested")
	print("[FEUD] village of %d adults, gate is %d"
		% [adults.size(), Prayers.FEUD_MIN_FOLK])


func _adults() -> Array:
	var out: Array = []
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null and f.brain.adult:
			out.append(f)
	return out


## The two sides must want genuinely different things, and both must be things
## the player can actually do. A feud between two tags the god cannot produce is
## an argument with no answer.
func _check_table() -> void:
	var feuds: Array = []
	for kind in Prayer.KINDS:
		if bool(Prayer.KINDS[kind].get("feud", false)):
			feuds.append(String(kind))
	if feuds.size() != 2:
		_faults.append("%d feud kinds -- an argument needs exactly two sides"
			% feuds.size())
		return
	var a: int = int(Prayer.KINDS[feuds[0]]["tag"])
	var b: int = int(Prayer.KINDS[feuds[1]]["tag"])
	if a & b != 0:
		_faults.append("both sides of the feud share a tag -- one act would "
			+ "answer both of them at once")
	# And the jobs behind them must not overlap, or one villager could be
	# picked for both ends of their own argument.
	for job in Prayers.CLEARERS:
		if job in Prayers.GROWERS:
			_faults.append("%s is on both sides of the feud" % job)
	print("[FEUD] %s (tag %d) against %s (tag %d)"
		% [feuds[0], a, feuds[1], b])


## Left alone, it stands. This is the assertion the whole stage rests on.
func _check_never_settles() -> void:
	var pair := _make()
	if pair.is_empty():
		return
	var p: Prayer = pair[0]
	if p.met(_root):
		_faults.append("a feud reports itself settled with nobody having done "
			+ "anything -- the choice evaporates on its own")
	# Even with the asker in perfect health and no danger anywhere near.
	p.who.brain.stats["hunger"] = 1.0
	p.who.brain.stats["health"] = 1.0
	p.who.brain.stats["fun"] = 1.0
	if p.met(_root):
		_faults.append("a well-fed happy villager's feud counts as answered")
	print("[FEUD] left alone for a lifetime, a feud is still open: %s"
		% (not p.met(_root)))
	_clear()


## Neither side is ever dealt on its own by the ordinary path.
func _check_solo_never_opens() -> void:
	var pr = _root.prayers
	var who = null
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null and f.brain.adult:
			who = f
			break
	if who == null:
		return
	# Starve them and strip their fun, which is the state that makes the
	# ordinary path deal a prayer at all, then ask a hundred times.
	who.brain.stats["hunger"] = 0.05
	who.brain.stats["fun"] = 0.05
	who.brain.stats["health"] = 0.05
	var seen: Dictionary = {}
	for i in 100:
		var made = pr._consider(who, float(_root.village.now), true)
		if made != null:
			seen[made.kind] = true
	for kind in seen:
		if bool(Prayer.KINDS[kind].get("feud", false)):
			_faults.append("the ordinary path dealt a lone '%s' -- half an "
				% kind + "argument, with nothing that can ever answer it")
	print("[FEUD] a desperate villager asks for %s, and never a feud"
		% str(seen.keys()))


## WHAT THE GOD DID, NOT WHERE THEY POINTED. Both askers stand together, so
## both see everything; the tag is the only thing that can separate them.
func _check_tag_decides() -> void:
	var pair := _make()
	if pair.is_empty():
		return
	var quarry: Prayer = pair[0] if pair[0].kind == "quarry" else pair[1]
	var grove: Prayer = pair[1] if pair[0].kind == "quarry" else pair[0]
	var before := _standing(grove.who)

	# An act that says NATURE where both of them can see it.
	var a := DivineAction.make("grow", grove.who.position, 4.0, 9.0)
	a.tags = DivineAction.NATURE
	a.verb = "Something grows."
	_root.divinity.perform(a)
	_root.prayers._close(float(_root.village.now))

	if _root.prayers.active.has(grove):
		_faults.append("growing something did not answer the villager asking "
			+ "for growth")
	if _root.prayers.active.has(quarry):
		_faults.append("the losing side is still standing -- both of them are "
			+ "waiting for an answer that already went to somebody else")
	if not quarry.denied:
		_faults.append("the losing side closed without being marked denied, so "
			+ "nothing downstream can tell it apart from a prayer that lapsed")
	if grove.denied:
		_faults.append("the side that WON was marked denied")
	var after := _standing(grove.who)
	if after <= before:
		_faults.append("the villager whose side you took thinks no better of "
			+ "you: %.2f then %.2f" % [before, after])
	print("[FEUD] a NATURE act answered '%s' and denied '%s'"
		% [grove.kind, quarry.kind])
	_clear()


## Being denied is not the same as being ignored, and the villager knows it.
func _check_denial_is_remembered() -> void:
	var pair := _make()
	if pair.is_empty():
		return
	var quarry: Prayer = pair[0] if pair[0].kind == "quarry" else pair[1]
	var grove: Prayer = pair[1] if pair[0].kind == "quarry" else pair[0]
	var before := _standing(quarry.who)

	var a := DivineAction.make("grow", grove.who.position, 4.0, 9.0)
	a.tags = DivineAction.NATURE
	_root.divinity.perform(a)
	_root.prayers._close(float(_root.village.now))

	var after := _standing(quarry.who)
	if after >= before:
		_faults.append("the villager you turned down thinks no worse of you: "
			+ "%.2f then %.2f" % [before, after])
	# And it is a memory OF THE GOD, so it does not evaporate in ninety
	# seconds the way an opinion about the weather does.
	var kept := false
	for e in quarry.who.brain.memories.entries:
		if String(e.get("kind", "")) == Memories.KIND_PUNISHMENT \
				and float(e.get("keep", 0.0)) > 0.0:
			kept = true
	if not kept:
		_faults.append("being turned down left no lasting memory -- they will "
			+ "have forgotten before they finish walking home")
	print("[FEUD] the one you turned down: standing %.2f -> %.2f, and it stays"
		% [before, after])
	_clear()


## It is rare, it needs a village, and it never runs two at once.
func _check_rarity() -> void:
	var pr = _root.prayers
	_clear()
	pr._feud_at = -1.0
	var now := float(_root.village.now)
	pr._open_feud(now)
	var first := _feuding(pr)
	if first != 2:
		_faults.append("asking for an argument in a village of %d produced %d "
			% [_adults().size(), first] + "prayer(s)")
	# Immediately again: nothing, because one is already standing.
	pr._open_feud(now)
	if _feuding(pr) > first:
		_faults.append("a second argument opened while the first was still "
			+ "going -- the player is being asked to disappoint four people")
	# And even with the field clear, not before the cooldown. The prayers are
	# cleared BY HAND here rather than through `_clear`, which also resets the
	# feud clock -- resetting the very thing under test is how a cooldown check
	# passes while the cooldown does nothing.
	pr.active.clear()
	pr._cooldown.clear()
	pr._open_feud(now + Prayers.FEUD_EVERY * 0.5)
	if _feuding(pr) > 0:
		_faults.append("a new feud opened %.0fs after the last one, against a "
			% (Prayers.FEUD_EVERY * 0.5) + "cooldown of %.0fs"
			% Prayers.FEUD_EVERY)
	print("[FEUD] one argument at a time, and never inside %.0fs"
		% Prayers.FEUD_EVERY)
	_clear()


## --- helpers ----------------------------------------------------------------

## Force a pair into being, whatever jobs the village happens to have rolled.
func _make() -> Array:
	_clear()
	var pr = _root.prayers
	var folk := _adults()
	if folk.size() < Prayers.FEUD_MIN_FOLK:
		return []
	# Stand them together and give them the two jobs, so `_open_feud` is being
	# asked the real question rather than a rigged one.
	folk[1].position = folk[0].position + Vector3(1.5, 0, 0)
	folk[0].brain.job = Prayers.CLEARERS[0]
	folk[1].brain.job = Prayers.GROWERS[0]
	pr._feud_at = -1.0
	pr._cooldown.clear()
	pr._open_feud(float(_root.village.now))
	var out: Array = []
	for p in pr.active:
		if p.feud():
			out.append(p)
	if out.size() != 2:
		_faults.append("asked for an argument and got %d prayer(s)" % out.size())
		return []
	if out[0].rival != out[1] or out[1].rival != out[0]:
		_faults.append("the two halves of the feud do not point at each other")
	return out


func _clear() -> void:
	_root.prayers.active.clear()
	_root.prayers._cooldown.clear()
	_root.prayers._feud_at = -1.0


func _feuding(pr) -> int:
	var n := 0
	for p in pr.active:
		if p.feud():
			n += 1
	return n


## What this villager currently thinks of the god.
func _standing(f) -> float:
	if not is_instance_valid(f) or f.brain == null:
		return 0.0
	return float(f.brain.memories.divine_standing())


func _report() -> void:
	for f in _faults:
		print("  - %s" % f)
	if _faults.is_empty():
		print("[FEUD] the argument holds")
	else:
		print("[FEUD] %d FAILURE(S)" % _faults.size())
