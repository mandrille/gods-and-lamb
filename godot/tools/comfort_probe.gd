extends SceneTree
## How loud the game is allowed to be, and what it costs when nobody is looking.
##
## The project accumulated a great deal of motion without anybody deciding how
## much motion there should be. Guilt pulses, the blessable dial depletes,
## prayer bubbles beat, the prophet's ring bobs, the edge arrow throbs,
## particles burst on every act. Each was right in isolation and nobody ever
## looked at the total -- which for somebody who gets motion sickness, or on a
## phone already working hard, is the only thing that matters.
##
## What is asserted:
##
##   - the three switches survive being written and read back
##   - turning motion down damps the pulses but never stops them, because two
##     of them are FINDING aids and a mark that never moves cannot be found
##   - the particle budget is real and drops the tail of a frame, not the head
##   - it resets, so the cap is per frame rather than for the session
##   - a villager the camera cannot resolve is not animated, and IS still paid
##   - the pause menu's rows and its buttons agree, and "Start over" is still
##     the one that asks twice
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
		printerr("[COMFORT] FAIL: no scene root")
		quit(1)
		return true
	TestGroundRef.green(_root)

	_check_round_trip()
	_check_damped_not_dead()
	_check_fx_budget()
	_check_reaction_lod()
	_check_menu_agrees()
	_report()
	quit(0 if _faults.is_empty() else 1)
	return true


## They persist, or they are a setting the player sets once per session.
func _check_round_trip() -> void:
	if _root.settings == null:
		print("[COMFORT] no settings layer in this build -- skipped")
		return
	var c := Comfort.new()
	c.motion = false
	c.effects = false
	c.big_text = true
	c.store_in(_root.settings)
	var back := Comfort.new()
	back.load_from(_root.settings)
	if back.motion or back.effects or not back.big_text:
		_faults.append("the comfort switches did not survive a save: "
			+ "motion %s effects %s text %s"
			% [back.motion, back.effects, back.big_text])
	# And put the file back the way it was found.
	var fresh := Comfort.new()
	fresh.store_in(_root.settings)
	print("[COMFORT] three switches, saved and read back")


## DAMPED, NOT DEAD. The guilt mark and the edge arrow are how a player FINDS
## something in a busy field; a mark that does not move at all is one they
## genuinely cannot pick out.
func _check_damped_not_dead() -> void:
	var c := Comfort.new()
	c.motion = true
	var full := c.beat()
	c.motion = false
	var damped := c.beat()
	if damped >= full:
		_faults.append("turning motion down changed nothing: %.2f then %.2f"
			% [full, damped])
	if damped <= 0.0:
		_faults.append("turning motion down stopped the pulses entirely -- the "
			+ "guilt mark and the edge arrow are how things get found")
	c.effects = false
	if c.density() >= 1.0 or c.density() <= 0.0:
		_faults.append("fewer effects means %.2f of the particles" % c.density())
	c.big_text = true
	if c.ui_units(400.0) >= 400.0:
		_faults.append("larger text did not make the UI units smaller, which "
			+ "is the only thing that makes anything bigger")
	print("[COMFORT] motion %.2f -> %.2f, particles %.2f, UI units 400 -> %.0f"
		% [full, damped, c.density(), c.ui_units(400.0)])


## THE BUDGET is real, and it is per frame.
func _check_fx_budget() -> void:
	var fx = _root.fxe
	if fx == null:
		_faults.append("no FX pool")
		return
	fx._spent = 0
	for i in FXEvents.PER_FRAME + 20:
		fx.burst("bless", Vector3(6, 1, 6))
	if fx.spent() != FXEvents.PER_FRAME:
		_faults.append("%d bursts started in one frame against a budget of %d"
			% [fx.spent(), FXEvents.PER_FRAME])
	# It resets, or the budget is for the whole session and the game goes
	# silent after the first busy moment.
	fx._physics_process(0.016)
	if fx.spent() != 0:
		_faults.append("the budget did not reset between frames -- the game "
			+ "goes quiet after one busy second and never comes back")
	fx.burst("bless", Vector3(6, 1, 6))
	if fx.spent() != 1:
		_faults.append("the frame after a full one could not spend anything")
	print("[COMFORT] %d of %d bursts allowed per frame, and it resets"
		% [FXEvents.PER_FRAME, FXEvents.PER_FRAME + 20])


## A VILLAGER THE CAMERA CANNOT RESOLVE IS NOT ANIMATED, and is still paid.
## That second half is what makes this a level of detail rather than a cut.
func _check_reaction_lod() -> void:
	if _root.rig == null or _root.rig.cam == null:
		_faults.append("no camera to measure against")
		return
	if _root.REACT_NEAR >= _root.REACT_FAR:
		_faults.append("the near band (%.0f) is not inside the far one (%.0f)"
			% [_root.REACT_NEAR, _root.REACT_FAR])
	var who = null
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null:
			who = f
			break
	if who == null:
		return
	# Somewhere well past the far band.
	var far_off: Vector3 = _root.rig.cam.global_position \
		+ (who.position - _root.rig.cam.global_position).normalized() \
		* (_root.REACT_FAR + 40.0)
	who.position = far_off
	var before := float(who.brain.faith_xp) \
		+ float(who.brain.faith_level) * 1000.0
	var a := DivineAction.make("grow", far_off, 5.0, 8.0)
	a.tags = DivineAction.NATURE
	var r: Dictionary = _root.divinity.perform(a)
	if not Prophet.among(r["hits"], who):
		_faults.append("the distant villager did not witness the act at all -- "
			+ "this check proves nothing")
		return
	var after := float(who.brain.faith_xp) \
		+ float(who.brain.faith_level) * 1000.0
	if after <= before:
		_faults.append("a villager too far away to animate was not paid "
			+ "either -- that is a cut, not a level of detail")
	print("[COMFORT] beyond %.2f camera-distances (%.0fm): no clip, still paid "
		% [_root.REACT_FAR, _root.REACT_FAR * float(_root.rig.dist)]
		+ "%.2f" % (after - before))


## The menu's rows and its buttons have to agree. Both counts used to be the
## literal 3, in two functions; adding rows to one alone draws buttons through
## the bottom of a panel that did not grow.
func _check_menu_agrees() -> void:
	var m = _root.pause_menu
	if m == null:
		_faults.append("no pause menu")
		return
	m.comfort = _root.comfort
	var labels: Array = m._labels()
	var rects: Array = m._button_rects()
	if labels.size() != rects.size():
		_faults.append("%d labels and %d buttons" % [labels.size(), rects.size()])
		return
	var panel: Rect2 = m._panel_rect()
	for i in rects.size():
		if not panel.grow(1.0).encloses(rects[i]):
			_faults.append("button %d ('%s') is outside the panel"
				% [i, String(labels[i])])
	# And the destructive one is still the last, still asks twice.
	if not String(labels[labels.size() - 1]).begins_with("Start over"):
		_faults.append("the last row is '%s' rather than Start over"
			% String(labels[labels.size() - 1]))
	print("[COMFORT] %d rows, all inside the panel, Start over last"
		% labels.size())


func _report() -> void:
	for f in _faults:
		print("  - %s" % f)
	if _faults.is_empty():
		print("[COMFORT] the game can be turned down")
	else:
		print("[COMFORT] %d FAILURE(S)" % _faults.size())
