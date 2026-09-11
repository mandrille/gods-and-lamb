extends SceneTree
## Can the player reach the loop at all?
##
## The owner played the deployed build and reported four things: trees grow but
## cannot be clicked for apples, it says "No room to grow there", the villagers
## who wanted to eat do not go and eat the apples, and the whole screen can be
## filled with fruit. Every one of those turned out to be a specific defect
## between the player's finger and a working simulation.
##
## This probe is the guard on all four. It asserts the RUNGS OF THE CHAIN the
## owner drew, from the bottom up:
##
##   - a tree the player grew can be clicked at all
##   - a click near a tree means the tree, not a refusal
##   - being refused never costs the next touch
##   - a hungry villager walks to fruit and eats it
##   - and still eats normally when there is no fruit
##   - a tree runs out of apples
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
		printerr("[REACH] FAIL: no scene root")
		quit(1)
		return true
	TestGroundRef.green(_root)

	_check_grown_things_are_clickable()
	_check_near_a_tree_means_the_tree()
	_check_refusal_is_free()
	_check_hunger_walks_to_fruit()
	_check_hunger_still_works_without_fruit()
	_check_a_tree_runs_out()
	_report()
	quit(0 if _faults.is_empty() else 1)
	return true


## --- helpers ----------------------------------------------------------------

func _settle() -> void:
	# The picker and the walk grid are both refreshed on the coalesced rebuild,
	# so a probe has to let that happen rather than reading straight after a
	# placement.
	_root._grid_dirty = true
	_root._grid_wait = 0.0
	_root._service_grid(1.0)


func _picked(aid: String) -> int:
	var n := 0
	for p in _root.pick.props:
		if String(p.get("id", "")) == aid:
			n += 1
	return n


func _standing(aid: String) -> int:
	var n := 0
	for e in _root.builder.placed_props:
		if String(e.get("id", "")) == aid and not bool(e.get("gone", false)) \
				and is_instance_valid(e.get("node")):
			n += 1
	return n


## A cell of plain grass with nothing near it, so a grow can actually succeed.
func _free_cell() -> Vector2i:
	for row in range(4, _root.builder.lower.size() - 4):
		for col in range(4, _root.builder.lower[row].length() - 4):
			var c := Vector2i(col, row)
			if not _root.grid.is_plain(c) or _root._prop_on(c):
				continue
			if _root.builder.would_overlap("Nature/tree", c.x, c.y):
				continue
			return c
	return Vector2i(-1, -1)


func _adult():
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null and f.brain.adult:
			return f
	return null


## --- the checks ---------------------------------------------------------------

## THE ONE THAT SHIPPED. `rebuild_grid` returned early whenever `grid` was
## non-null, which is always after `_ready`, so the `pick.setup` below it was
## dead code and the click picker's cached AABBs were built twice a session:
## at startup, and when an island was bought. Everything the player grew was
## unclickable for the rest of the game.
func _check_grown_things_are_clickable() -> void:
	var before := _picked("Nature/tree")
	var cell := _free_cell()
	if cell.x < 0:
		_faults.append("nowhere on the map is clear enough to grow a tree")
		return
	if not _root.builder.add_prop("Nature/tree", cell.x, cell.y, 0.0):
		_faults.append("could not place a tree to test with")
		return
	_root.queue_grid_rebuild()
	_settle()
	var after := _picked("Nature/tree")
	if after <= before:
		_faults.append(("a tree was grown and the click picker never heard "
			+ "about it -- %d known before, %d after. Everything the player "
			+ "creates is unclickable.") % [before, after])
	print("[REACH] trees known to the picker: %d -> %d after growing one"
		% [before, after])


## A click in the ring around a trunk is a click ON the tree. That ring is a
## deny zone -- `would_overlap` reserves 5x5 around every hard prop while the
## walk grid blocks only the centre -- and it is exactly where somebody aiming
## at the canopy lands.
func _check_near_a_tree_means_the_tree() -> void:
	var tree: Dictionary = {}
	for e in _root.builder.placed_props:
		if String(e.get("id", "")) == "Nature/tree" \
				and is_instance_valid(e.get("node")):
			tree = e
			break
	if tree.is_empty():
		_faults.append("no tree standing to aim near")
		return
	var home := Vector2i(int(tree["col"]), int(tree["row"]))
	# A cell one step off the trunk: grass, nothing on it, and inside the halo.
	var beside := Vector2i(-1, -1)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c: Vector2i = home + d
		if _root.grid.is_plain(c) and not _root._prop_on(c) \
				and _root.builder.would_overlap("Nature/tree", c.x, c.y):
			beside = c
			break
	if beside.x < 0:
		print("[REACH] no refused cell beside the trunk to aim at -- skipped")
		return
	var apples := _standing("Nature/apples")
	_root._touched_at = -99.0
	_root._on_ground(_root.grid.world_of(beside))
	_settle()
	if _standing("Nature/apples") <= apples:
		_faults.append("a click one cell off a trunk produced no fruit -- it "
			+ "was refused instead of being read as a touch on the tree")
	print("[REACH] a click beside the trunk: apples %d -> %d"
		% [apples, _standing("Nature/apples")])


## BEING TOLD NO MUST NOT COST THE NEXT TOUCH. The refusal path spent the full
## 0.45 s cooldown on its way out, so the player pressed twice and the game
## answered once.
func _check_refusal_is_free() -> void:
	# THE REAL REFUSAL, which is grass inside some hard prop's halo with no
	# tree near enough to have been meant instead. Water is not a refusal --
	# it pays food and fun, and an earlier version of this check aimed there
	# and reported a bug that was a working feature.
	var blocked := Vector2i(-1, -1)
	for e in _root.builder.placed_props:
		var id := String(e.get("id", ""))
		if not (id == "Nature/rock" or id == "Nature/log"
				or id == "Nature/stump"):
			continue
		var home := Vector2i(int(e.get("col", -999)), int(e.get("row", -999)))
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1),
				  Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1)]:
			var c: Vector2i = home + d
			if not _root.grid.is_plain(c) or _root._prop_on(c):
				continue
			if not _root.builder.would_overlap("Nature/tree", c.x, c.y):
				continue
			if not _root._tree_near(c).is_empty():
				continue          # this one becomes a fruit touch, by design
			blocked = c
			break
		if blocked.x >= 0:
			break
	if blocked.x < 0:
		print("[REACH] no genuinely refused cell on this map -- skipped")
		return
	_root._touched_at = -99.0
	var before: float = float(_root._touched_at)
	_root._on_ground(_root.grid.world_of(blocked))
	if not is_equal_approx(float(_root._touched_at), before):
		_faults.append("a refused touch spent the cooldown -- the player's "
			+ "next tap is eaten by the one that was already ignored")
	print("[REACH] a genuinely refused touch leaves the cooldown at %.0f"
		% _root._touched_at)


## THE RUNG THE OWNER ASKED FOR TWICE. A hungry villager standing in a field of
## fruit used to eat from the abstract granary instead.
func _check_hunger_walks_to_fruit() -> void:
	var who = _adult()
	if who == null:
		_faults.append("nobody to feed")
		return
	# Fruit within reach, a full granary, and a hungry villager. If the granary
	# wins this, spawning apples can never answer a food prayer.
	var home: Vector2i = _root.grid.cell_of(who.position)
	var placed := 0
	for d in [Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(0, 2)]:
		var c: Vector2i = home + d
		if _root.builder.add_prop("Nature/apples", c.x, c.y, 0.0):
			placed += 1
	if placed == 0:
		_faults.append("could not lay any fruit near the villager")
		return
	_settle()
	_root.village.give({"food": 20})
	who.brain.stats["hunger"] = 0.10
	var chose := String(who.brain._answer_need("hunger", 0.10))
	if chose != "graze":
		_faults.append(("a starving villager standing next to %d heaps of "
			+ "fruit chose '%s' -- food they can see must beat food in a "
			+ "ledger, or answering a food prayer with an apple does nothing")
			% [placed, chose])
	print("[REACH] hungry, %d heaps within two cells, a full granary: chose '%s'"
		% [placed, chose])


## And with no fruit anywhere, hunger still resolves. `_action_for_need` used
## to give up on the first candidate that failed a gate, so adding a second
## honest answer could have starved the village beside a full granary.
func _check_hunger_still_works_without_fruit() -> void:
	var who = _adult()
	if who == null:
		return
	for e in _root.builder.placed_props.duplicate():
		if String(e.get("id", "")) == "Nature/apples":
			_root.builder.remove_prop(e)
	_settle()
	_root.village.give({"food": 20})
	who.brain.stats["hunger"] = 0.10
	var chose := String(who.brain._answer_need("hunger", 0.10))
	if chose == "":
		_faults.append("with no fruit and a FULL granary, hunger had no answer "
			+ "at all -- the village would starve beside its own larder")
	print("[REACH] hungry, no fruit, a full granary: chose '%s'" % chose)


## A tree runs out. There was no cap of any kind.
func _check_a_tree_runs_out() -> void:
	var tree: Dictionary = {}
	for e in _root.builder.placed_props:
		if String(e.get("id", "")) == "Nature/tree" \
				and is_instance_valid(e.get("node")):
			tree = e
			break
	if tree.is_empty():
		return
	var counts: Array = []
	for i in 8:
		_root._touched_at = -99.0
		_root._on_picked(tree)
		_settle()
		counts.append(_standing("Nature/apples"))
	if counts[-1] > WorldTouch.FRUIT_HELD * 3:
		_faults.append(("eight clicks on one tree left %d heaps under it "
			+ "against a cap of %d -- the island can be carpeted")
			% [counts[-1], WorldTouch.FRUIT_HELD])
	if counts[-1] <= 0:
		_faults.append("eight clicks on a tree produced no fruit at all")
	print("[REACH] eight clicks on one tree: %s heaps standing (cap %d)"
		% [str(counts), WorldTouch.FRUIT_HELD])


func _report() -> void:
	for f in _faults:
		print("  - %s" % f)
	if _faults.is_empty():
		print("[REACH] the player can reach the loop")
	else:
		print("[REACH] %d FAILURE(S)" % _faults.size())
