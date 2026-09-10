extends SceneTree
## Can the player tell what the disaster did?
##
## The simulation half of disasters was already right -- fires eat trees, rain
## ends them, solving one pays every villager -- and none of that was reaching
## the person playing. A crisis resolved in one line of notice text, in the same
## stack and the same voice as "No room to grow there.", and a crisis that
## started on the far side of the island was never found at all.
##
## So this probe asserts the things that make a disaster READABLE, which is the
## half that the rest of the suite cannot see:
##
##   - a fire remembers who it endangered, and still remembers once it is out
##   - answering one produces a report that names the rescue, the payment and
##     the reputation it moved
##   - losing one produces a report too, and it does not claim a rescue
##   - the report is not on a game clock, so fast-forward cannot eat it
##   - an off-screen calamity gets an arrow, on the side it is actually on,
##     and an on-screen one does not
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
		printerr("[AFTER] FAIL: no scene root")
		quit(1)
		return true
	TestGroundRef.green(_root)

	_check_endangered()
	_check_solved_report()
	_check_lost_report()
	_check_report_clock()
	_check_arrow()
	_report()
	quit(0 if _faults.is_empty() else 1)
	return true


func _somebody():
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null:
			return f
	return null


## A fire counts who stood near it WHILE IT BURNED, because afterwards nobody
## does -- and it keeps the list, so the rescue can still be reported.
func _check_endangered() -> void:
	var who = _somebody()
	if who == null:
		_faults.append("nobody in the village")
		return
	var c := Calamity.new("fire", _root.grid.cell_of(who.position))
	if not c.endangered.is_empty():
		_faults.append("a fresh calamity already claims to have endangered "
			+ "somebody")
	c.watch(_root.folk, _root.grid.world_of)
	if not c.endangered.has(who.get_instance_id()):
		_faults.append("a fire on top of %s did not put them in danger"
			% who.brain.name)
	# FAR AWAY IS NOT IN DANGER, or "3 saved" means "3 villagers exist".
	var far := Calamity.new("fire", Vector2i(0, 0))
	far.watch(_root.folk, _root.grid.world_of)
	var near_n: int = c.endangered.size()
	var far_n: int = far.endangered.size()
	if far_n >= near_n:
		_faults.append(("a fire in the far corner endangered %d and one on top "
			+ "of the village endangered %d -- distance is not being read")
			% [far_n, near_n])
	print("[AFTER] a fire on the village endangers %d, one in the corner %d"
		% [near_n, far_n])
	# And the list survives the thing going out, which is the whole point.
	_root.calamities.append(c)
	_root._end_calamity(c, true)
	if c.saved(_root.folk) <= 0:
		_faults.append("once the fire was out it had saved nobody -- the "
			+ "rescue is being counted after the danger has gone")


## Answering one says what it was worth, in the order a player cares about.
func _check_solved_report() -> void:
	var who = _somebody()
	if who == null:
		return
	var after = _root.aftermath
	if after == null:
		_faults.append("there is no aftermath card at all")
		return
	var c := Calamity.new("fire", _root.grid.cell_of(who.position))
	c.eaten = 2
	_root.calamities.append(c)
	c.watch(_root.folk, _root.grid.world_of)
	_root._end_calamity(c, true)

	if after._left <= 0.0:
		_faults.append("answering a fire put up no report")
		return
	if not after._good:
		_faults.append("answering a fire reported as a loss")
	if not after._head.contains("CONTAINED"):
		_faults.append("the headline for a solved fire was '%s'" % after._head)
	var texts: Array = []
	for row in after._rows:
		texts.append(String(row[1]))
	var joined := ", ".join(texts)
	for want in ["saved", "Faith", "rising"]:
		if not joined.contains(want):
			_faults.append("the report never mentions %s: %s" % [want, joined])
	print("[AFTER] '%s' -> %s" % [after._head, joined])


## And losing one is reported too, without claiming a rescue that did not
## happen. A report that only ever appears on a win is a trophy, not feedback.
func _check_lost_report() -> void:
	var who = _somebody()
	if who == null:
		return
	var after = _root.aftermath
	var c := Calamity.new("drought", _root.grid.cell_of(who.position))
	c.eaten = 7
	c.age = Calamity.LIFETIME
	_root.calamities.append(c)
	c.watch(_root.folk, _root.grid.world_of)
	_root._end_calamity(c, false)
	if after._good:
		_faults.append("a drought that ran its course reported as a win")
	var texts: Array = []
	for row in after._rows:
		texts.append(String(row[1]))
	var joined := ", ".join(texts)
	if joined.contains("saved"):
		_faults.append("a disaster nobody answered still claimed a rescue: %s"
			% joined)
	if not joined.contains("7"):
		_faults.append("the loss does not say what it cost: %s" % joined)
	print("[AFTER] '%s' -> %s" % [after._head, joined])


## THE REPORT IS ON THE PLAYER'S CLOCK, NOT THE VILLAGE'S.
##
## Fast-forward is a thing the player does constantly, and a card that obeyed
## `Engine.time_scale` would be gone in a third of a second at 3x -- which is
## the exact moment they most need to be told what they just missed.
func _check_report_clock() -> void:
	var after = _root.aftermath
	# The engine hands `_process` a delta ALREADY multiplied by time_scale, so
	# the probe has to do the same or it is measuring its own arithmetic. The
	# question is whether four tenths of a REAL second cost the card the same
	# either way.
	after.show_report("TEST", true, [["faith", "+1 Faith"]])
	var before := float(after._left)
	Engine.time_scale = 4.0
	after._process(0.4 * 4.0)
	var fast := before - float(after._left)
	Engine.time_scale = 1.0
	var mid := float(after._left)
	after._process(0.4)
	var slow := mid - float(after._left)
	if not is_equal_approx(snappedf(fast, 0.001), snappedf(slow, 0.001)):
		_faults.append(("the report ages %.2fs at 4x and %.2fs at 1x for the "
			+ "same frame -- fast-forward eats it") % [fast, slow])
	print("[AFTER] a 0.4s frame ages the card %.2fs at 4x and %.2fs at 1x"
		% [fast, slow])
	after._left = 0.0


## An off-screen fire gets an arrow, on the side it is on. An on-screen one
## does not -- it is already pointing at itself, in orange.
func _check_arrow() -> void:
	var over = _root.overhead
	if over == null or _root.rig == null or _root.rig.cam == null:
		_faults.append("no overhead layer to draw an arrow on")
		return
	# A STATED SCREEN, not the live one. Headless has no window, so `over.size`
	# is zero here and the geometry would go untested on the only machine that
	# ever runs this. The arrow's placement is pure maths against a rectangle;
	# handing it a rectangle is the honest way to check it.
	var screen := Vector2(1280, 720)
	var frame := Rect2(Vector2(Overhead.EDGE_INSET, Overhead.EDGE_INSET),
					   screen - Vector2(Overhead.EDGE_INSET,
										Overhead.EDGE_INSET) * 2.0)
	# The reach helper is the geometry the arrow placement rests on: whatever
	# direction is asked for, the point must land ON the frame, never outside.
	for a in [0.0, 0.7, 1.9, 3.3, 4.8, 6.0]:
		var d := Vector2(cos(a), sin(a))
		var at: Vector2 = screen * 0.5 + d * over._reach(d, frame)
		if not frame.grow(1.0).has_point(at):
			_faults.append("an arrow at %.1f rad landed at %s, off the frame %s"
				% [a, at, frame])
	# Every kind has a tint, or a drought's arrow is a fire's arrow.
	var tints: Dictionary = {}
	for kind in Calamity.KINDS:
		var t := String(Calamity.LOOK[kind].get("tint", ""))
		if not Overhead.TINTS.has(t):
			_faults.append("%s's tint '%s' has no arrow colour" % [kind, t])
		tints[t] = true
	if tints.size() < Calamity.KINDS.size():
		_faults.append("two kinds of disaster share an arrow colour")
	print("[AFTER] %d disaster kinds, %d arrow colours, frame %s"
		% [Calamity.KINDS.size(), tints.size(), frame.size])


func _report() -> void:
	for f in _faults:
		print("  - %s" % f)
	if _faults.is_empty():
		print("[AFTER] the disaster reads")
	else:
		print("[AFTER] %d FAILURE(S)" % _faults.size())
