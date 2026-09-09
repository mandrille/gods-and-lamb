extends SceneTree
## The world takes things back.
##
## Until calamities the game had no subtraction in it: a greened hillside stayed
## green forever and a player who had built one could stop looking at it. So the
## things worth asserting are the ones that would quietly turn a crisis back into
## scenery:
##
##   - a fire actually EATS something (a calamity that damages nothing is a
##     notification, and players learn to dismiss notifications)
##   - a drought puts grass back to dirt in the document AND the walk grid, or
##     the ground lies to the pathfinder
##   - the right miracle ends it, the wrong one does not
##   - solving pays FAITH TO EVERY VILLAGER, and pays more for a fire caught
##     early than one caught late, or the best play is to let it burn
##   - it burns out on its own, so being unable to look away is not the same as
##     being unable to lose
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
		printerr("[CALAMITY] FAIL: no scene root")
		quit(1)
		return true
	TestGroundRef.green(_root)

	_check_table()
	_check_fire()
	_check_drought()
	_check_drought_spares_buildings()
	_check_tornado()
	_check_answer()
	_check_thanks()
	_check_burnout()
	_check_gate()
	_report()
	quit(0 if _faults.is_empty() else 1)
	return true


## Every kind has an answer, and every answer is a card the player can hold.
func _check_table() -> void:
	var ids: Array = []
	for c in _root.divinity.DECK:
		ids.append(String(c.get("id", "")))
	for kind in Calamity.KINDS:
		var answers: Array = Calamity.ANSWERS.get(kind, [])
		if answers.is_empty():
			_faults.append("%s has no answer -- it is a tax, not a crisis"
				% kind)
		for a in answers:
			if not ids.has(String(a)):
				_faults.append("%s is answered by %s, which is not in the deck"
					% [kind, a])
		if not Calamity.LOOK.has(kind):
			_faults.append("%s has no look" % kind)


## A fire eats a tree and leaves scorched ground.
func _check_fire() -> void:
	var cell := _plant_tree()
	if cell.x < 0:
		_faults.append("could not grow a tree to burn")
		return
	var before: int = _root.builder.placed_props.size()
	var c := Calamity.new("fire", cell)
	_root._bite(c)
	var after: int = _root.builder.placed_props.size()
	print("[CALAMITY] fire: props %d -> %d, ground %s, eaten %d"
		% [before, after,
		   _root.builder.code_at(_root.builder.lower, cell.x, cell.y), c.eaten])
	if after >= before:
		_faults.append("a fire burned for a full bite and took nothing")
	if _root.builder.code_at(_root.builder.lower, cell.x, cell.y) != "D":
		_faults.append("fire left the ground green where a tree had stood")


## A drought turns grass to dirt, in the document and in the walk grid both.
func _check_drought() -> void:
	var cell := _find("G")
	if cell.x < 0:
		_faults.append("no grass to dry out")
		return
	var c := Calamity.new("drought", cell)
	_root._bite(c)
	var doc: String = _root.builder.code_at(_root.builder.lower, cell.x, cell.y)
	var seen: String = _root.grid.code_of(cell)
	print("[CALAMITY] drought: document %s, walk grid %s, eaten %d"
		% [doc, seen, c.eaten])
	if c.eaten <= 0:
		_faults.append("a drought dried nothing")
	if doc != "D":
		_faults.append("the document still says %s after a drought" % doc)
	if seen != "D":
		_faults.append("the walk grid still says %s, so the ground and the "
			% seen + "pathfinder disagree about a dried tile")


## A DROUGHT DOES NOT DRY THE GROUND OUT FROM UNDER A BUILDING.
##
## It did. Grass reverted to dirt wherever the drought reached, buildings
## included, which left a well standing on ground that every buildability test
## in the game says nothing may be built on. It surfaced as build_probe failing
## intermittently -- "buildings on non-grass" -- and looked like flakiness,
## because whether a drought fired near the village at all varied run to run.
func _check_drought_spares_buildings() -> void:
	var cell := _find("G")
	if cell.x < 0:
		return
	if not _root.builder.add_prop("Buildings/well", cell.x, cell.y):
		print("[CALAMITY] nowhere to stand a well; skipped")
		return
	var well: Dictionary = _root.builder.placed_props[-1]
	var c := Calamity.new("drought", cell)
	for i in 3:
		_root._bite(c)
	var under: String = _root.builder.code_at(_root.builder.lower,
											  cell.x, cell.y)
	# TAKE THE WELL BACK DOWN. These checks share one living world in order,
	# and a building left standing blocks the tree the tornado check needs --
	# which reads as "a tornado left a tree standing" three functions later.
	_root.builder.remove_prop(well)
	_root.queue_grid_rebuild()
	print("[CALAMITY] after three drought bites the well stands on '%s'" % under)
	if under != "G":
		_faults.append("a drought dried the ground out from under a building, "
			+ "leaving it on '%s' -- which nothing may be built on" % under)


## A tornado walks, and flattens what it walks over.
func _check_tornado() -> void:
	var cell := _plant_tree()
	if cell.x < 0:
		return
	# It moves BEFORE it eats, so start it one step back.
	var c := Calamity.new("tornado", cell - Vector2i(1, 0), Vector2i(1, 0))
	var before: int = _root.builder.placed_props.size()
	_root._bite(c)
	print("[CALAMITY] tornado: walked to %s, props %d -> %d"
		% [c.cell, before, _root.builder.placed_props.size()])
	if c.cell != cell:
		_faults.append("a tornado did not walk: it is at %s, not %s"
			% [c.cell, cell])
	if _root.builder.placed_props.size() >= before:
		_faults.append("a tornado crossed a tree and left it standing")


## The right card ends it. The wrong one does not.
func _check_answer() -> void:
	var c := Calamity.new("fire", Vector2i(4, 4))
	if not c.answered_by("rain"):
		_faults.append("rain does not put out a fire")
	if c.answered_by("wrath"):
		_faults.append("any card at all ends a fire")
	var d := Calamity.new("tornado", Vector2i(4, 4))
	if d.answered_by("rain"):
		_faults.append("rain stops a tornado, which makes rain the only card")
	if not d.answered_by("calm"):
		_faults.append("calm does not settle a wind")


## Solving pays every villager, and pays MORE for a crisis caught early.
func _check_thanks() -> void:
	var who = null
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null:
			who = f
			break
	if who == null:
		_faults.append("nobody to thank")
		return
	var c := Calamity.new("fire", _root.grid.cell_of(who.position))
	_root.calamities.append(c)
	var before := float(who.brain.faith_xp) \
		+ float(who.brain.faith_level) * 1000.0
	_root._end_calamity(c, true)
	var after := float(who.brain.faith_xp) \
		+ float(who.brain.faith_level) * 1000.0
	print("[CALAMITY] solving one paid a villager %.1f faith" % (after - before))
	if after <= before:
		_faults.append("solving a calamity paid the village nothing")
	if _root.calamities.has(c):
		_faults.append("a solved calamity is still running")
	var early := Calamity.new("fire", Vector2i.ZERO)
	var late := Calamity.new("fire", Vector2i.ZERO)
	late.eaten = 8
	print("[CALAMITY] thanks: caught early %.2f, caught late %.2f"
		% [early.thanks(), late.thanks()])
	if late.thanks() >= early.thanks():
		_faults.append("a fire is worth as much late as early, so the best "
			+ "play is to let it burn")


## It stops on its own.
func _check_burnout() -> void:
	var c := Calamity.new("drought", Vector2i(2, 2))
	if c.expired():
		_faults.append("a calamity expired the instant it started")
	c.age = Calamity.LIFETIME + 1.0
	if not c.expired():
		_faults.append("a calamity never ends on its own -- a village cannot "
			+ "survive one by enduring it")
	_root.calamities.append(c)
	_root._tick_calamities(0.016)
	if _root.calamities.has(c):
		_faults.append("an expired calamity was not cleaned up")


## NOT IN THE FIRST MINUTES. A village of three with no cards has nothing to
## lose and no way to answer; a fire there is a punishment for being new.
func _check_gate() -> void:
	_root.calamities.clear()
	var age: int = _root.divinity.age
	_root.divinity.age = 1
	_root._calamity_timer = 0.01
	_root._tick_calamities(1.0)
	var early: int = _root.calamities.size()
	_root.divinity.age = maxi(age, 2)
	_root._calamity_timer = 0.01
	_root._tick_calamities(1.0)
	var later: int = _root.calamities.size()
	print("[CALAMITY] at age 1: %d running; at age 2: %d" % [early, later])
	if early > 0:
		_faults.append("a calamity hit a first-age village")
	if later < 1:
		_faults.append("no calamity ever starts, so the world never takes "
			+ "anything back")
	# And never two at once: two disasters is not twice the drama.
	_root._calamity_timer = 0.01
	_root._tick_calamities(1.0)
	if _root.calamities.size() > 1:
		_faults.append("%d calamities at once" % _root.calamities.size())
	_root.calamities.clear()


func _plant_tree() -> Vector2i:
	var cell := _find("G")
	if cell.x < 0:
		return cell
	_root.builder.add_prop("Nature/tree", cell.x, cell.y)
	return cell


func _find(ch: String) -> Vector2i:
	for row in _root.builder.lower.size():
		var line: String = _root.builder.lower[row]
		for col in line.length():
			if line[col] != ch:
				continue
			var c := Vector2i(col, row)
			if _root.grid.is_walkable(c) and not _root._prop_on(c):
				return c
	return Vector2i(-1, -1)


func _report() -> void:
	if _faults.is_empty():
		print("[CALAMITY] ok")
		return
	print("[CALAMITY] %d FAILURE(S)" % _faults.size())
	for f in _faults:
		print("  - %s" % f)
