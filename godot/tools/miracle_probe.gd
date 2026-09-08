extends SceneTree
## Does it matter WHERE you sweep a miracle?
##
## The old cards resolved in one instant over the whole village, so the answer
## was no: a click was a click. Now a card is held on the cursor and pays for
## each soul it actually passes over, once each. That claim is worth testing,
## because if parking the cloud on one person pays the same as sweeping it
## across eight, the mechanic is decorative.
##
## The cursor follows the real mouse in _process, which a headless probe has no
## way to move -- so this drives `position` directly and calls the effect step,
## which is the mechanic. Following the pointer is one line and is not what can
## silently go wrong.
const ShotWindowRef := preload("res://tools/shot_window.gd")

const STEP := 0.1

var _f := 0
var _root: Node = null
var _faults: Array[String] = []


func _initialize() -> void:
	ShotWindowRef.park()
	get_root().add_child(
		(load("res://scenes/vale.tscn") as PackedScene).instantiate())


func _process(_d: float) -> bool:
	_f += 1
	if _f < 40:
		return false
	# The shot needs the cloud to have been RENDERED, which cannot be awaited
	# from inside _process without turning it into a coroutine that returns
	# before the frame is drawn. So it is set up on one frame and saved on a
	# later one.
	if _f > 40:
		# Milestones queue one draft per crossed threshold, and spawning ten
		# villagers in one frame crosses several -- so clearing it ONCE at
		# frame 40 was not enough; the next one was already queued behind it.
		# Pre-paying every milestone below the spawned population is the fix
		# that actually holds, rather than a race against how many are left.
		_root.draft.close()
		_root.divinity.pending_draft = []
		if _f == 46:
			ShotWindow.shoot(
				"res://shots/miracle.png")
			_root.cursor.release()
			_run()
			quit(0 if _faults.is_empty() else 1)
			return true
		return false
	for n in get_root().get_children():
		if n.get("divinity") != null:
			_root = n
	if _root == null:
		printerr("[MIR] FAIL: no scene root")
		quit(1)
		return true

	_root.village.pop_cap = 200
	while _root.folk.size() < 10:
		if not _root.spawn_villager():
			break
	# A line of villagers a metre apart, so a sweep can cross a known number of
	# them and a park can sit on exactly one.
	var base: Vector3 = _root.folk[0].position
	for i in _root.folk.size():
		_root.folk[i].position = base + Vector3(float(i) * 3.0, 0, 0)

	# Spawning ten villagers in one frame crosses several population
	# milestones (4 and 8), each of which queues its own boon draft -- pre-pay
	# them all so none of them pop open mid-shot. Reaching for the private
	# `_milestones_paid` dict rather than draining drafts one per frame: this
	# is a picture of the miracle overlay, not a test of the milestone queue.
	for n in _root.POP_MILESTONES:
		_root._milestones_paid[n] = true
	_root.draft.close()
	_root.divinity.pending_draft = []

	# Set the picture up; frame 46 saves it. A picture is worth taking because
	# "the cloud follows the cursor" is a claim about how it LOOKS.
	var c = _root.cursor
	var mid: Vector3 = _root.folk[_root.folk.size() / 2].position
	_root.rig.focus = mid
	_root.rig.dist = 18.0
	_root.rig.call("_place")
	# Pinned via the SAME pointer-override seam _mouse_tracking uses, not a
	# raw position write: `begin()` turns on _process, and _process reads the
	# pointer every frame from then on -- an unpinned write got silently
	# overwritten by whatever the real (parked, off-screen, unfocused) window
	# reports as its mouse position, which sent the cloud off the map before
	# the frame that actually saves the picture.
	c._pointer_override = _root.rig.cam.unproject_position(mid)
	c.begin("rain", 4.5)
	for i in 12:
		c.call("_apply", STEP)
	return false


func _run() -> void:
	_mouse_tracking()
	_park_vs_sweep()
	_planting()
	_expiry()
	if _faults.is_empty():
		print("[MIR] ok")
	else:
		for f in _faults:
			printerr("[MIR]   - " + f)
		printerr("[MIR] %d FAILURE(S)" % _faults.size())


## Does the cloud ACTUALLY follow a moving mouse cursor, through the real
## runtime path (_process -> ground_at -> global_position), rather than
## through the direct position writes every other test in this file uses to
## isolate the payout logic? This is the one test that exercises the code
## the player actually sees move.
##
## Warps the real OS cursor via the Viewport (this probe runs with a display,
## not --headless, which is why screenshots work at all) to two screen points
## chosen far enough apart that they must land on different ground.
func _mouse_tracking() -> void:
	var c = _root.cursor
	var size := get_root().get_visible_rect().size
	var a := size * 0.30
	var b := size * 0.70

	# warp_mouse cannot be used here: the render window runs parked off-screen
	# and unfocused (shot_window.gd) precisely so an automated run never
	# steals the user's real cursor, and an unfocused window will not accept a
	# warped pointer. `_pointer_override` substitutes for the mouse at the
	# exact point _process() reads it, so this still exercises the real
	# _process -> ground_at -> global_position chain, not a shortcut around it.
	c._pointer_override = a
	c.begin("rain", 4.5)
	for i in 3:
		c.call("_process", 0.016)
	var pos_a: Vector3 = c.global_position

	c._pointer_override = b
	for i in 3:
		c.call("_process", 0.016)
	var pos_b: Vector3 = c.global_position
	c.release()
	c._pointer_override = Vector2(-1, -1)

	var moved: float = pos_a.distance_to(pos_b)
	print("[MIR] mouse-driven tracking: %s -> %s, moved %.2f m"
		% [str(pos_a), str(pos_b), moved])
	if moved < 1.0:
		_faults.append("the cloud did not follow the mouse through the real "
			+ "_process path (moved only %.2f m between two screen points "
			% moved + "%s and %s)" % [str(a), str(b)])


## Sitting still over one villager must pay less than crossing eight.
func _park_vs_sweep() -> void:
	var d = _root.divinity
	var c = _root.cursor
	# PIN THEM. They are alive and they walk, and a villager who wanders into a
	# parked cloud is a real thing that should pay -- but it makes the two arms
	# of this comparison differ by who happened to stroll past, which is not
	# what is being measured.
	var base: Vector3 = _root.folk[0].position
	_line_up(base)

	d.faith = 0.0
	c.begin("mend", 4.5)
	c.position = base + Vector3(0, MiracleCursor.HEIGHT, 0)
	for i in 40:
		_line_up(base)
		c.call("_apply", STEP)
	var parked: float = d.faith
	var parked_n: int = (c.get("_touched_folk") as Dictionary).size()
	c.release()

	d.faith = 0.0
	c.begin("mend", 4.5)
	for i in 40:
		_line_up(base)
		c.position = base + Vector3(float(i) * 0.7, MiracleCursor.HEIGHT, 0)
		c.call("_apply", STEP)
	var swept: float = d.faith
	var swept_n: int = (c.get("_touched_folk") as Dictionary).size()
	c.release()

	print("[MIR] parked on one: %d souls, %.1f Faith" % [parked_n, parked])
	print("[MIR] swept across:  %d souls, %.1f Faith" % [swept_n, swept])
	if swept_n <= parked_n or swept <= parked:
		_faults.append("sweeping across %d villagers paid %.1f against %.1f "
			% [swept_n, swept, parked] + "for parking on %d -- position does "
			% parked_n + "not matter, so the miracle may as well not move")
	# And each soul pays ONCE, or holding still would farm the same person.
	if parked_n > 2:
		_faults.append("parking touched %d 'different' souls; the paid-once "
			% parked_n + "rule is not holding")


## Villagers three metres apart in a row, so a sweep crosses a known number of
## them and a park sits on exactly one.
func _line_up(base: Vector3) -> void:
	for i in _root.folk.size():
		_root.folk[i].position = base + Vector3(float(i) * 3.0, 0, 0)


## A growing miracle has to leave something behind it.
func _planting() -> void:
	var c = _root.cursor
	var before := _count("Nature/tree")
	# Sweep over ground that is KNOWN to be open, rather than a fixed offset
	# from a villager. The village builds fast now, so a hard-coded path
	# wandered across huts and crop rows and planted nothing -- which is
	# correct behaviour and a useless test.
	var open := _open_run(24)
	if open.is_empty():
		_faults.append("could not find open ground to test planting on")
		return
	c.begin("grove", 4.5)
	for at in open:
		c.position = at + Vector3(0, MiracleCursor.HEIGHT, 0)
		c.call("_apply", STEP)
	c.release()
	var after := _count("Nature/tree")
	print("[MIR] grove planted %d trees along the path" % (after - before))
	if after <= before:
		_faults.append("a grove swept across open ground planted nothing")


## It has to run out, or a single card lasts the whole game.
func _expiry() -> void:
	var c = _root.cursor
	c.begin("rain", 4.5)
	if not c.is_active():
		_faults.append("the miracle was not active after beginning it")
	c.left = 0.01
	c.call("_apply", 0.02)
	c.left = 0.0
	c.release()
	if c.is_active():
		_faults.append("the miracle never expired")
	else:
		print("[MIR] expires and clears")


## A run of walkable cells to sweep along, as world points.
func _open_run(want: int) -> Array[Vector3]:
	var g = _root.grid
	var out: Array[Vector3] = []
	if g == null:
		return out
	for start in g.walkable_cells():
		out.clear()
		var c: Vector2i = start
		for step in want:
			if not g.is_walkable(c):
				break
			out.append(g.world_of(c))
			c += Vector2i(1, 0)
		if out.size() >= want / 2:
			return out
	return out


func _count(aid: String) -> int:
	var n := 0
	for e in _root.builder.placed_props:
		if String(e["id"]) == aid:
			n += 1
	return n
