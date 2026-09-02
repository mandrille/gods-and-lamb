extends SceneTree
## Are there animals, do they move, and do they give anything back?
##
## Livestock are deliberately not Followers -- they have no needs, no brain and
## no pathfinder -- so none of the existing probes touch them. Three claims are
## worth holding: that they exist and are separate from the people, that they
## actually wander rather than standing where they spawned, and that they add
## to the stores where the player can see it happen.
const ShotWindowRef := preload("res://tools/shot_window.gd")

const SPEED := 8.0
const RUN := 900

var _f := 0
var _root: Node = null
var _start: Array[Vector3] = []
var _food_at_start := 0
var _faults: Array[String] = []


func _initialize() -> void:
	ShotWindowRef.park()
	get_root().add_child(
		(load("res://scenes/vale.tscn") as PackedScene).instantiate())


func _process(_d: float) -> bool:
	_f += 1
	if _f == 30:
		for n in get_root().get_children():
			if n.get("divinity") != null:
				_root = n
		if _root == null:
			printerr("[STOCK] FAIL: no scene root")
			quit(1)
			return true
		if _root.beasts.is_empty():
			_faults.append("no livestock in the world at all")
			_finish()
			return true
		for b in _root.beasts:
			_start.append(b.position)
		# Emptied, so anything in the larder at the end came from the animals.
		# Villagers can only ADD to it, which makes this a floor rather than an
		# exact figure -- see the assertion.
		_food_at_start = 0
		_root.village.stores["food"] = 0
		var kinds := {}
		for b in _root.beasts:
			kinds[b.kind] = int(kinds.get(b.kind, 0)) + 1
		print("[STOCK] %d animals: %s" % [_root.beasts.size(), str(kinds)])
		if kinds.size() < 2:
			_faults.append("only one kind of animal; there should be sheep "
				+ "AND cows")
		Engine.time_scale = SPEED
		return false
	if _f < 30:
		return false

	# A picture of them out in the field.
	if _f == 320:
		var b = _root.beasts[0]
		_root.rig.focus = b.position
		_root.rig.dist = 14.0
		_root.rig.call("_place")
		return false
	if _f == 326:
		get_root().get_texture().get_image().save_png("res://shots/livestock.png")
		return false

	if _f < RUN:
		return false
	Engine.time_scale = 1.0
	_check()
	_finish()
	return true


func _check() -> void:
	# They have to MOVE. A herd of statues is scenery with an animation player.
	var moved := 0
	var furthest := 0.0
	for i in _root.beasts.size():
		var d: float = _root.beasts[i].position.distance_to(_start[i])
		furthest = maxf(furthest, d)
		if d > 0.5:
			moved += 1
	print("[STOCK] %d of %d wandered; furthest travelled %.1f m"
		% [moved, _root.beasts.size(), furthest])
	if moved == 0:
		_faults.append("not one animal moved; they are props with a walk cycle")

	# And they have to pay. Villagers also add food, so this is a floor: what
	# matters is that it is not zero and that the animals are the reason there
	# is a floor at all.
	var food: int = _root.village.amount("food")
	print("[STOCK] food in the store after the run: %d (started at %d)"
		% [food, _food_at_start])
	if food <= _food_at_start:
		_faults.append("the stores did not grow at all with animals in the "
			+ "field")

	# Buying land brings more of them.
	var before: int = _root.beasts.size()
	var slots: Array = _root.islands.buyable()
	if slots.is_empty():
		_faults.append("no ground to buy, so the herd-grows-with-land rule "
			+ "went untested")
		return
	_root.divinity.add_faith(9999.0)
	_root.divinity.buy_island(slots[0])
	print("[STOCK] after buying a plot: %d animals (was %d)"
		% [_root.beasts.size(), before])
	if _root.beasts.size() <= before:
		_faults.append("buying land brought no livestock with it")

	# Livestock must never leak into the PEOPLE. Everything that iterates folk
	# -- blessing, judgement, the social layer, the census -- assumes a brain.
	for f in _root.folk:
		if f is Critter:
			_faults.append("a Critter turned up in `folk`")
			break


func _finish() -> void:
	if _faults.is_empty():
		print("[STOCK] ok")
	else:
		for f in _faults:
			printerr("[STOCK]   - " + f)
		printerr("[STOCK] %d FAILURE(S)" % _faults.size())
	quit(0 if _faults.is_empty() else 1)
