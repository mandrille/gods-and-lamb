extends SceneTree
## The world answers back.
##
## Every tree, rock, pond and bare patch of dirt used to swallow a click. Now a
## touch is the god's main verb and the whole desert opening rests on it, so
## the things worth asserting are the ones that would ruin it quietly:
##
##   - dirt actually becomes grass, in the ground AND in the document, or the
##     change is a lick of paint the walk grid and the save never hear about
##   - grass grows something, but only where there is room
##   - a rock breaks and is GONE, and pays stone
##   - a touch pays faith to whoever was near enough to see it
##   - the shared cooldown holds, or the whole game is a mouse-speed contest
const ShotWindowRef := preload("res://tools/shot_window.gd")

var _f := 0
var _root: Node = null
var _faults: Array[String] = []
var _water_at_start := 0


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
		printerr("[TOUCH] FAIL: no scene root")
		quit(1)
		return true

	_water_at_start = _count("W")
	_check_desert()
	_check_greening()
	_check_bloom()
	_check_aim()
	_check_fruit()
	_check_broken_rock()
	_check_growing()
	_check_rock()
	_check_faith()
	_check_cooldown()
	_check_survives_land()
	_report()
	quit(0 if _faults.is_empty() else 1)
	return true


## A NEW PLOT IS BARE. This is the opening, and it is the one thing a player
## sees before they have done anything at all.
func _check_desert() -> void:
	var dirt := 0
	var grass := 0
	var props := 0
	var green_props := 0
	for row in _root.builder.lower.size():
		var line: String = _root.builder.lower[row]
		for col in line.length():
			match line[col]:
				"D": dirt += 1
				"G": grass += 1
	for e in _root.builder.placed_props:
		props += 1
		var id := String(e.get("id", ""))
		if id.begins_with("Nature/tree") or id.begins_with("Nature/bush") \
				or id == "Nature/tall_grass" or id == "Nature/flowers":
			green_props += 1
	print("[TOUCH] the plot arrives: %d dirt, %d grass, %d props (%d green)"
		% [dirt, grass, props, green_props])
	if dirt < 100:
		_faults.append("only %d dirt tiles -- the plot did not arrive bare"
			% dirt)
	if green_props > 4:
		_faults.append("%d things were already growing on a bare plot"
			% green_props)


## Dirt becomes grass, everywhere it needs to be true at once.
func _check_greening() -> void:
	var cell := _find("D")
	if cell.x < 0:
		_faults.append("no dirt to green")
		return
	_root._touched_at = -99.0
	_root._on_ground(_root.grid.world_of(cell))
	var doc: String = _root.builder.code_at(_root.builder.lower, cell.x, cell.y)
	var seen: String = _root.grid.code_of(cell)
	print("[TOUCH] greening a cell: document %s, walk grid %s" % [doc, seen])
	if doc != "G":
		_faults.append("the document still says %s after greening" % doc)
	if seen != "G":
		_faults.append("the walk grid still says %s, so nothing can be built "
			% seen + "on ground the player just made")
	if not _root.grid.is_plain(cell):
		_faults.append("greened ground is not plain, so no building will "
			+ "ever go on it")


## GREENING IS A TIDE. One touch lays 4x4 down at once and the patch keeps
## spreading on its own out to 16x16.
func _check_bloom() -> void:
	var cell := _find("D")
	if cell.x < 0:
		_faults.append("no dirt left to test the spread on")
		return
	var before := _count("G")
	_root._touched_at = -99.0
	_root._on_ground(_root.grid.world_of(cell))
	var seeded := _count("G") - before
	print("[TOUCH] the touch itself greened %d tiles" % seeded)
	if seeded < 4:
		_faults.append("a touch greened %d tile(s) -- the 4x4 seed did not land"
			% seeded)
	if seeded > WorldTouch.SEED_SIZE * WorldTouch.SEED_SIZE:
		_faults.append("a touch greened %d tiles, more than the %d a seed can"
			% [seeded, WorldTouch.SEED_SIZE * WorldTouch.SEED_SIZE])
	if _root._tides.is_empty():
		_faults.append("the touch started no spread, so the patch will never "
			+ "grow past its first 4x4")
		return

	# IT KEEPS GOING WITHOUT BEING TOUCHED AGAIN, and it stops.
	var steps := 0
	while not _root._tides.is_empty() and steps < 40:
		steps += 1
		_root.village.now = float(_root.village.now) + WorldTouch.TIDE_STEP
		_root._tick_tides()
	var grown := _count("G") - before
	print("[TOUCH] it spread on its own to %d tiles over %d steps"
		% [grown, steps])
	if steps >= 40:
		_faults.append("the spread never finished -- it runs forever")
	if grown <= seeded:
		_faults.append("the spread stopped at its seed: %d tiles" % grown)
	var cap: int = WorldTouch.TIDE_MAX * WorldTouch.TIDE_MAX
	if grown > cap:
		_faults.append("the spread reached %d tiles, past the %dx%d maximum"
			% [grown, WorldTouch.TIDE_MAX, WorldTouch.TIDE_MAX])

	# THE WALK GRID AGREES about every one of them, or the ground and the
	# pathfinder disagree about most of a lawn and only the middle is real.
	var wrong := 0
	for c in WorldTouch.block(cell, WorldTouch.TIDE_MAX):
		if _root.builder.code_at(_root.builder.lower, c.x, c.y) != "G":
			continue
		if _root.grid.code_of(c) != "G":
			wrong += 1
	if wrong > 0:
		_faults.append("%d greened tile(s) never reached the walk grid" % wrong)

	# AND IT DOES NOT EAT THE POND. `set_tiles` converts whatever tile it is
	# handed, so without a filter a spread that reached the shore would turn the
	# water into a lawn. Only what the touch table says becomes grass may go.
	print("[TOUCH] water tiles left on the map: %d" % _count("W"))
	if _count("W") <= 0 and _water_at_start > 0:
		_faults.append("the spread turned every pond on the map into grass")

	# The shape is a function of the cell and the step, so an interrupted
	# spread resumes identically rather than rerolling itself.
	if WorldTouch.takes(cell, 3, 0.62) != WorldTouch.takes(cell, 3, 0.62):
		_faults.append("the same square takes at a different moment each time")


## A CLICK LANDS ON THE TILE IT WAS AIMED AT.
##
## `CameraRig.ground_at` intersects a horizontal plane, and that plane was at
## y = 0 while the walkable surface is at `lift` -- 0.5 m, the top of a ground
## tile. At this camera's fixed 35.5 degree pitch a half-metre height error
## projects to 0.5 / tan(35.5) = 0.70 m along the ground, and tiles are 0.5 m
## across: every click landed about a tile and a half from where the player was
## pointing, always in the same direction.
##
## It read as two separate complaints -- "clicking is inaccurate" and "trees
## spawn underground", the latter because the tree grew on a tile the player
## never chose, often at an island edge or against a cliff.
func _check_aim() -> void:
	var cam: Camera3D = _root.rig.cam
	var worst := 0.0
	var missed := 0
	var tried := 0
	for row in range(4, _root.builder.lower.size(), 7):
		for col in range(4, String(_root.builder.lower[row]).length(), 7):
			var c := Vector2i(col, row)
			if not _root.grid.is_walkable(c):
				continue
			var world: Vector3 = _root.grid.world_of(c)
			if cam.is_position_behind(world):
				continue
			var screen: Vector2 = cam.unproject_position(world)
			var back = _root.rig.ground_at(screen)
			if back == null:
				continue
			tried += 1
			worst = maxf(worst, Vector2(world.x - (back as Vector3).x,
										world.z - (back as Vector3).z).length())
			if _root.grid.cell_of(back as Vector3) != c:
				missed += 1
	print("[TOUCH] aimed at %d tiles: %d landed elsewhere, worst miss %.2f m"
		% [tried, missed, worst])
	if tried < 4:
		_faults.append("could not see enough tiles to test aim")
		return
	if missed > 0:
		_faults.append("%d of %d clicks landed on a different tile than the "
			% [missed, tried] + "one they were aimed at")
	# Half a tile is the most a rounding error may cost.
	if worst > _root.builder.tile * 0.5:
		_faults.append("a click missed its point by %.2f m, which is more than "
			% worst + "half a tile")


## A TREE FRUITS: several heaps under the canopy, and they are food a villager
## will actually walk to. `forage` lists Nature/apples as a source and consumes
## it, so this is a closed loop and not a decoration.
func _check_fruit() -> void:
	var tree := {}
	for e in _root.builder.placed_props:
		if String(e.get("id", "")) == "Nature/tree":
			tree = e
			break
	if tree.is_empty():
		# Grow one: a bare plot has no trees, which is the whole point of it.
		var cell := _find("G")
		if cell.x < 0 or not _root.builder.add_prop("Nature/tree",
													cell.x, cell.y):
			print("[TOUCH] nowhere to put a tree; skipped the fruit check")
			return
		tree = _root.builder.placed_props[-1]
	var before := _heaps()
	_root._touched_at = -99.0
	_root._on_picked(tree)
	var made := _heaps() - before
	print("[TOUCH] touching a tree left %d apple heaps under it" % made)
	if made < 2:
		_faults.append("a tree gave %d heap(s) -- it is producing an item, "
			% made + "not fruiting")
	# The tree is still standing. A tree consumed by being touched is a
	# resource node, and the player would learn not to touch them.
	if not is_instance_valid(tree.get("node")):
		_faults.append("touching a tree destroyed it")
	# And the heaps are somewhere a villager can reach.
	var here: Vector2i = Vector2i(int(tree.get("col", 0)),
								  int(tree.get("row", 0)))
	var reachable := 0
	for e in _root.builder.placed_props:
		if String(e.get("id", "")) != "Nature/apples":
			continue
		var c := Vector2i(int(e.get("col", 0)), int(e.get("row", 0)))
		if absi(c.x - here.x) > WorldTouch.FRUIT_REACH 				or absi(c.y - here.y) > WorldTouch.FRUIT_REACH:
			continue
		if _root.grid.is_walkable(c):
			reachable += 1
	print("[TOUCH] %d of them are on ground a villager can stand on" % reachable)
	if reachable < 2:
		_faults.append("only %d heap(s) landed where anyone can get at them"
			% reachable)
	if not Brain.ACTIONS["forage"]["sources"].has("Nature/apples"):
		_faults.append("nothing eats apple heaps, so a tree drops food that "
			+ "sits there forever")


## A BROKEN ROCK IS GONE, and stays gone.
##
## Driven through the PICKER rather than by calling the handler, because the
## bug was in the seam between them: `hover` built its own dictionaries with
## the same fields, GDScript compares dictionaries by reference, and so
## `placed_props.erase(entry)` erased nothing. The rock vanished from the
## screen and stayed in the builder's list -- paying stone on every click
## forever, blocking its tile, and coming back on the next grid rebuild.
func _check_broken_rock() -> void:
	var rock := {}
	for e in _root.builder.placed_props:
		if String(e.get("id", "")) == "Nature/rock":
			rock = e
			break
	if rock.is_empty():
		print("[TOUCH] no rock left to break twice")
		return
	var cam: Camera3D = _root.rig.cam
	var at: Vector3 = rock["node"].global_position + Vector3(0, 0.2, 0)
	# Look at it, or it may be off screen or behind the camera.
	_root.rig.focus = at
	_root.rig.dist = 12.0
	_root.rig._place()
	_root.pick.setup(_root.rig, _root.builder, _root.builder.placed_props)
	var screen: Vector2 = cam.unproject_position(at)

	var stone: int = _root.village.amount("stone")
	_root._touched_at = -99.0
	_root.pick._claim(screen)
	var after_first: int = _root.village.amount("stone")
	# And again, on the very same spot.
	_root._touched_at = -99.0
	_root.pick._claim(screen)
	var after_second: int = _root.village.amount("stone")
	print("[TOUCH] breaking the same rock twice: stone %d -> %d -> %d"
		% [stone, after_first, after_second])
	if after_first <= stone:
		_faults.append("clicking a rock through the picker paid nothing")
	if after_second > after_first:
		_faults.append("a broken rock paid out again -- it is still in the "
			+ "world and will keep paying forever")
	for e in _root.builder.placed_props:
		if e.get("node") == rock.get("node"):
			_faults.append("the broken rock is still in the builder's list, so "
				+ "it still blocks its tile and returns on the next rebuild")
			break


func _count(ch: String) -> int:
	var n := 0
	for row in _root.builder.lower.size():
		n += String(_root.builder.lower[row]).count(ch)
	return n


func _heaps() -> int:
	var n := 0
	for e in _root.builder.placed_props:
		if String(e.get("id", "")) == "Nature/apples":
			n += 1
	return n


## Grass grows, and only where there is room.
func _check_growing() -> void:
	var cell := _find("G")
	if cell.x < 0:
		_faults.append("no grass to grow on")
		return
	var before: int = _root.builder.placed_props.size()
	_root._touched_at = -99.0
	_root._on_ground(_root.grid.world_of(cell))
	var after: int = _root.builder.placed_props.size()
	print("[TOUCH] growing on grass: %d props -> %d" % [before, after])
	if after <= before:
		_faults.append("touching clear grass grew nothing")
	# And the same cell again must NOT stack a second plant on the first.
	_root._touched_at = -99.0
	_root._on_ground(_root.grid.world_of(cell))
	if _root.builder.placed_props.size() > after:
		_faults.append("a second touch stacked another plant on the first")
	# The seed is a function of the CELL, so it cannot be rerolled.
	if WorldTouch.seed_for(cell) != WorldTouch.seed_for(cell):
		_faults.append("the same cell grows different things")


## A rock breaks, pays stone, and is gone.
func _check_rock() -> void:
	var rock := {}
	for e in _root.builder.placed_props:
		if String(e.get("id", "")) == "Nature/rock":
			rock = e
			break
	if rock.is_empty():
		print("[TOUCH] no rock on this plot to break")
		return
	var stone: int = _root.village.amount("stone")
	var props: int = _root.builder.placed_props.size()
	_root._touched_at = -99.0
	_root._on_picked(rock)
	print("[TOUCH] breaking a rock: stone %d -> %d, props %d -> %d"
		% [stone, _root.village.amount("stone"),
		   props, _root.builder.placed_props.size()])
	if _root.village.amount("stone") <= stone:
		_faults.append("breaking a rock paid no stone")
	if _root.builder.placed_props.size() >= props:
		_faults.append("the rock was still standing after it broke")


## A touch is a sermon: whoever saw it gains faith.
func _check_faith() -> void:
	var who = null
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null:
			who = f
			break
	if who == null:
		_faults.append("nobody to witness a touch")
		return
	var cell: Vector2i = _root.grid.cell_of(who.position)
	var before := float(who.brain.faith_xp) \
		+ float(who.brain.faith_level) * 1000.0
	_root._touched_at = -99.0
	_root._on_ground(_root.grid.world_of(cell))
	var after := float(who.brain.faith_xp) \
		+ float(who.brain.faith_level) * 1000.0
	print("[TOUCH] a villager standing on the spot gained %.1f faith"
		% (after - before))
	if after <= before:
		_faults.append("a touch under a villager's feet gave them no faith")


## The cooldown is the only thing between this and a clicker.
func _check_cooldown() -> void:
	var cell := _find("D")
	if cell.x < 0:
		return
	# `_touch_take` is the one that stamps; `_touch_ready` only answers. Both
	# are checked, because a predicate that quietly consumed what it was asked
	# about is exactly the bug this pair was split to prevent.
	_root._touched_at = -99.0
	if not _root._touch_ready():
		_faults.append("the first touch was refused")
	if not _root._touch_ready():
		_faults.append("merely asking whether a touch is ready used it up")
	if not _root._touch_take():
		_faults.append("the first touch was refused")
	if _root._touch_take():
		_faults.append("two touches landed in the same instant -- the game is "
			+ "a mouse-speed contest")
	_root.village.now = float(_root.village.now) + WorldTouch.COOLDOWN + 0.01
	if not _root._touch_take():
		_faults.append("the cooldown never lifts")
	print("[TOUCH] cooldown holds and lifts after %.2fs" % WorldTouch.COOLDOWN)


## THE GROUND THE PLAYER MADE SURVIVES BUYING LAND.
##
## Buying a plot regenerates the world from the generator, and the generator
## emits bare dirt -- so this greened every tile the player had made back into
## desert. The whole opening, undone by the reward for finishing it. It is the
## kind of bug that is invisible in a probe suite and obvious in about four
## seconds of play.
func _check_survives_land() -> void:
	var greened: Array[Vector2i] = []
	for i in 12:
		var c := _find("D")
		if c.x < 0:
			break
		_root._touched_at = -99.0
		_root._on_ground(_root.grid.world_of(c))
		if _root.builder.code_at(_root.builder.lower, c.x, c.y) == "G":
			greened.append(c)
	if greened.is_empty():
		_faults.append("could not green anything to test a land purchase")
		return
	var slots: Array = _root.islands.buyable()
	if slots.is_empty():
		print("[TOUCH] no land to buy; skipped the survival check")
		return
	_root.divinity.add_faith(9999.0)
	_root.divinity.buy_island(slots[0])
	var lost := 0
	for c in greened:
		if _root.builder.code_at(_root.builder.lower, c.x, c.y) != "G":
			lost += 1
	print("[TOUCH] after buying land, %d of %d greened tiles survived"
		% [greened.size() - lost, greened.size()])
	if lost > 0:
		_faults.append("buying land turned %d greened tile(s) back to desert"
			% lost)
	# And the new plot arrives BARE, or land is a delivery rather than a canvas.
	var fresh_dirt := 0
	for row in _root.builder.lower.size():
		var line: String = _root.builder.lower[row]
		for col in line.length():
			if line[col] == "D":
				fresh_dirt += 1
	if fresh_dirt < 100:
		_faults.append("the bought plot did not arrive bare: %d dirt left"
			% fresh_dirt)


## A cell of this code with NOTHING STANDING ON IT.
##
## The prop test is not fussiness: the checks below run in order against one
## living world, and once one of them plants a tree the next one asking for
## "some grass" was handed the square with the tree on it and reported that
## growing does not work.
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
		print("[TOUCH] ok")
		return
	print("[TOUCH] %d FAILURE(S)" % _faults.size())
	for f in _faults:
		print("  - %s" % f)
