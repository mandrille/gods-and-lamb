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

	_check_desert()
	_check_greening()
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


func _find(ch: String) -> Vector2i:
	for row in _root.builder.lower.size():
		var line: String = _root.builder.lower[row]
		for col in line.length():
			if line[col] != ch:
				continue
			var c := Vector2i(col, row)
			if _root.grid.is_walkable(c):
				return c
	return Vector2i(-1, -1)


func _report() -> void:
	if _faults.is_empty():
		print("[TOUCH] ok")
		return
	print("[TOUCH] %d FAILURE(S)" % _faults.size())
	for f in _faults:
		print("  - %s" % f)
