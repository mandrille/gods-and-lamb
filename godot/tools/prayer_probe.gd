extends SceneTree
## The village asks, and finds out whether anybody was listening.
##
## This is the loop the whole design is for, so the assertions are the steps of
## it rather than the shape of the code:
##
##   a hungry villager says something
##   the god drops food where they can see it
##   they eat
##   the prayer resolves AS ANSWERED and pays them
##   -- and if they had sorted it out themselves, it resolves quietly instead
##
## The last line is the one that keeps the game from being whack-a-mole. A
## village that cannot solve its own problems turns a god into customer support.
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
		printerr("[PRAY] FAIL: no scene root")
		quit(1)
		return true
	TestGroundRef.green(_root)
	if _root.prayers == null:
		_faults.append("there is no prayer system at all")
		_report()
		quit(1)
		return true

	_check_quiet_when_fed()
	_check_hunger_speaks()
	_check_capped()
	_check_answered()
	_check_solved_alone()
	_check_expires()
	_check_ailing()
	_check_fire_frightens()
	_check_miracles_answer()
	_report()
	quit(0 if _faults.is_empty() else 1)
	return true


## A FED VILLAGE SAYS NOTHING. A prayer system that fires on a full stomach is
## a notification system, and players learn to ignore those.
func _check_quiet_when_fed() -> void:
	_reset()
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null:
			f.brain.stats["hunger"] = 1.0
	_run(20.0)
	print("[PRAY] a well-fed village raised %d prayers"
		% _root.prayers.active.size())
	if not _root.prayers.active.is_empty():
		_faults.append("a village with nothing wrong prayed anyway")


## HUNGER SPEAKS.
func _check_hunger_speaks() -> void:
	_reset()
	var who = _anyone()
	if who == null:
		_faults.append("nobody to be hungry")
		return
	who.brain.stats["hunger"] = 0.05      # starving
	_run(30.0)
	var p = _root.prayers.of(who)
	print("[PRAY] a starving villager: %s"
		% ("said '%s'" % p.says() if p != null else "said nothing"))
	if p == null:
		_faults.append("a starving villager never asked for anything")
		return
	if not p.urgent:
		_faults.append("a starving villager's prayer was not marked urgent")
	if p.icon() == "":
		_faults.append("the prayer has no icon, so the bubble says nothing")


## NEVER A WALL OF THEM.
func _check_capped() -> void:
	_reset()
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null:
			f.brain.stats["hunger"] = 0.30    # urgent, not desperate
	_run(60.0)
	var n: int = _root.prayers.active.size()
	print("[PRAY] a whole hungry village raised %d prayers (cap %d)"
		% [n, Prayers.MAX_ACTIVE])
	if n > Prayers.MAX_ACTIVE + Prayers.MAX_URGENT_EXTRA:
		_faults.append("%d prayers at once -- the screen is a task list" % n)


## THE WHOLE POINT. Somebody asks, the god feeds them, they are paid.
func _check_answered() -> void:
	_reset()
	var who = _anyone()
	if who == null:
		return
	who.brain.stats["hunger"] = 0.05
	_run(30.0)
	var p = _root.prayers.of(who)
	if p == null:
		_faults.append("nobody prayed, so answering could not be tested")
		return

	# The god drops food where they can see it. Exactly what touching a tree
	# does, built the same way.
	var faith_before := float(who.brain.faith_xp) \
		+ float(who.brain.faith_level) * 10000.0
	var a := DivineAction.make("touch", who.position, 1.0,
							   WorldTouch.WITNESS_RANGE)
	a.tags = DivineAction.FOOD
	_root.divinity.perform(a)
	print("[PRAY] after a FOOD act in sight, marked as god's work: %s"
		% p.touched_by_god)
	if not p.touched_by_god:
		_faults.append("a FOOD act in plain sight of the person asking for "
			+ "food was not recognised as answering them")

	# STILL STANDING until they have actually eaten. Dropping an apple at
	# somebody's feet is not the same as them having eaten it.
	if _root.prayers.of(who) == null:
		_faults.append("the prayer resolved the instant food appeared, before "
			+ "the villager had eaten anything")

	who.brain.stats["hunger"] = 0.9        # they ate
	_run(6.0)
	var faith_after := float(who.brain.faith_xp) \
		+ float(who.brain.faith_level) * 10000.0
	print("[PRAY] once they ate: prayer %s, their faith %.0f -> %.0f"
		% ["gone" if _root.prayers.of(who) == null else "STILL THERE",
		   faith_before, faith_after])
	if _root.prayers.of(who) != null:
		_faults.append("the need was met and the prayer did not resolve")
	if faith_after - faith_before < Prayers.ANSWERED_FAITH * 0.5:
		_faults.append("answering a prayer paid %.0f, which is not the "
			% (faith_after - faith_before) + "difference the design asks for")


## AND THEY CAN SOLVE IT THEMSELVES, quietly, for nothing.
func _check_solved_alone() -> void:
	_reset()
	var who = _anyone()
	if who == null:
		return
	who.brain.stats["hunger"] = 0.05
	_run(30.0)
	if _root.prayers.of(who) == null:
		return
	var before := float(who.brain.faith_xp) \
		+ float(who.brain.faith_level) * 10000.0
	# No divine act at all -- they simply found something.
	who.brain.stats["hunger"] = 0.9
	_run(6.0)
	var after := float(who.brain.faith_xp) \
		+ float(who.brain.faith_level) * 10000.0
	print("[PRAY] solved without the god: prayer %s, faith moved %.1f"
		% ["gone" if _root.prayers.of(who) == null else "STILL THERE",
		   after - before])
	if _root.prayers.of(who) != null:
		_faults.append("a villager sorted their own problem out and the "
			+ "prayer stayed on screen")
	if after - before > 1.0:
		_faults.append("the god was paid %.1f for a problem the village "
			% (after - before) + "solved by itself")


## AND ONE THAT IS NEVER ANSWERED GOES AWAY. A prayer nobody acts on must not
## sit there forever accusing the player.
func _check_expires() -> void:
	_reset()
	var who = _anyone()
	if who == null:
		return
	who.brain.stats["hunger"] = 0.05
	_run(30.0)
	var p = _root.prayers.of(who)
	if p == null:
		return
	_root.village.now = float(_root.village.now) + Prayer.LIFETIME + 1.0
	_root.prayers.tick(0.016)
	# THAT prayer, not "a prayer from that villager". They are still starving,
	# so the moment the old one expires a fresh one is allowed to open -- which
	# is correct, and which made the first version of this check read the new
	# prayer as the old one refusing to die.
	var still: bool = _root.prayers.active.has(p)
	print("[PRAY] after %.0fs unanswered: that prayer is %s (%d standing now)"
		% [Prayer.LIFETIME, "gone" if not still else "STILL THERE",
		   _root.prayers.active.size()])
	if still:
		_faults.append("an unanswered prayer never expires -- it sits there "
			+ "accusing the player forever")


## MORE THAN ONE THING TO ASK FOR. A prayer system with one kind is a hunger
## meter with a bubble on it.
func _check_ailing() -> void:
	_reset()
	var who = _anyone()
	if who == null:
		return
	who.brain.stats["health"] = 0.10
	_run(30.0)
	var p = _root.prayers.of(who)
	print("[PRAY] a sick villager: %s"
		% ("said '%s'" % p.says() if p != null else "said nothing"))
	if p == null:
		_faults.append("a villager at 10% health never asked for anything")
	elif p.kind != "healing":
		_faults.append("a sick villager asked for '%s'" % p.kind)


## A FIRE MAKES PEOPLE ASK, and that is what finally puts disasters inside the
## loop rather than beside them. Answered when the danger stops, however it
## stops -- there is no stat to recover here.
func _check_fire_frightens() -> void:
	_reset()
	var who = _anyone()
	if who == null:
		return
	who.brain.stats["health"] = 1.0
	var c := Calamity.new("fire", _root.grid.cell_of(who.position))
	_root.calamities.append(c)
	_run(30.0)
	var p = _root.prayers.of(who)
	print("[PRAY] with a fire at their feet: %s"
		% ("said '%s'" % p.says() if p != null else "said nothing"))
	if p == null:
		_faults.append("a fire beside a villager frightened nobody into asking")
		_root.calamities.erase(c)
		return
	if p.kind != "safety":
		_faults.append("a villager beside a fire asked for '%s'" % p.kind)
	if not p.urgent:
		_faults.append("standing next to a fire is not urgent")
	# The fire is answered by the fire STOPPING, not by a stat.
	_root.calamities.erase(c)
	_run(6.0)
	print("[PRAY] once the fire was out: %s"
		% ("gone" if _root.prayers.of(who) == null else "STILL THERE"))
	if _root.prayers.of(who) != null:
		_faults.append("the danger passed and the prayer stayed on screen")


## A MIRACLE ANSWERS ONE. Until now the cursor credited as it swept and told
## nothing downstream, so a miracle was the one divine act in the game that
## could not answer a prayer.
func _check_miracles_answer() -> void:
	_reset()
	var who = _anyone()
	if who == null:
		return
	who.brain.stats["health"] = 0.10
	_run(30.0)
	var p = _root.prayers.of(who)
	if p == null or p.kind != "healing":
		return
	# What the cursor does at the end of a `mend` sweep that touched them.
	var a := DivineAction.miracle("mend", who.position)
	_root.divinity.report(a, [[who, 1.0]], 0.0, 0)
	print("[PRAY] a mend sweep marked the healing prayer as answered: %s"
		% p.touched_by_god)
	if not p.touched_by_god:
		_faults.append("a mend miracle over the person asking to be healed "
			+ "was not recognised as answering them")
	if int(DivineAction.MIRACLE_TAGS.get("mend", 0)) & DivineAction.LIFE == 0:
		_faults.append("mend does not carry the LIFE tag, so nothing it does "
			+ "can ever answer a plea for healing")


## --- helpers ----------------------------------------------------------------

## Advance the village clock and let the prayer system look, without waiting for
## real frames.
func _run(secs: float) -> void:
	var step := 3.0
	var done := 0.0
	while done < secs:
		_root.village.now = float(_root.village.now) + step
		_root.prayers.tick(step)
		done += step


func _reset() -> void:
	_root.prayers.active.clear()
	_root.prayers._cooldown.clear()
	_root.prayers._next_look.clear()
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null:
			f.brain.stats["hunger"] = 1.0


func _anyone():
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null and f.brain.adult:
			return f
	return null


func _report() -> void:
	if _faults.is_empty():
		print("[PRAY] ok")
		return
	print("[PRAY] %d FAILURE(S)" % _faults.size())
	for f in _faults:
		print("  - %s" % f)
