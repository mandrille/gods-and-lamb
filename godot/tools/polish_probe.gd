extends SceneTree
## Can the player SEE the loop they are being asked to play?
##
## Every check here is about legibility rather than simulation. The sim was
## right long before this file existed; what was missing was any way to read it.
## Four things drove the whole economy and were drawn nowhere:
##
##   - the witness window, which decides whether a blessing pays at all
##   - the judgement cooldown, which silently ate the click that asked
##   - the combo chain, and the moment it breaks
##   - `favour`, the entire result of the only steering verb in the game
##
## So this asserts they are reachable from the UI's side, not merely that the
## numbers exist inside Divinity.
const ShotWindowRef := preload("res://tools/shot_window.gd")

const SPEED := 6.0
const RUN_FRAMES := 900

var _f := 0
var _root: Node = null
var _faults: Array[String] = []
var _refused := 0
var _saw_window := false
var _best_chain := 0


func _initialize() -> void:
	ShotWindowRef.park()
	get_root().add_child(
		(load("res://scenes/vale.tscn") as PackedScene).instantiate())


func _process(delta: float) -> bool:
	_f += 1
	if _f < 20:
		return false
	if _f == 20:
		for n in get_root().get_children():
			if n.get("divinity") != null:
				_root = n
		if _root == null:
			printerr("[POLISH] FAIL: no scene root")
			quit(1)
			return true
		_root.divinity.judge_refused.connect(func(_who): _refused += 1)
		Engine.time_scale = SPEED
		return false

	_play()
	if _f < RUN_FRAMES:
		return false

	if _f == RUN_FRAMES:
		Engine.time_scale = 1.0
		_check_goal()
		_check_window()
		_check_cooldown()
		_check_combo()
		_check_favour()
		_check_notices()
		_shoot()
		return false
	# The shutter falls LATER than the state change, or it photographs the
	# frame before the one being set up.
	if _f < RUN_FRAMES + 8:
		return false
	if not ShotWindowRef.can_shoot():
		print("[POLISH] no display: the picture was skipped, checks still ran")
		_report()
		quit(0 if _faults.is_empty() else 1)
		return true
	ShotWindow.shoot("res://shots/polish_hud.png")
	print("[POLISH] wrote res://shots/polish_hud.png")
	_report()
	quit(0 if _faults.is_empty() else 1)
	return true


## Play like a competent player: take any gift, and bless whoever just finished.
func _play() -> void:
	var d = _root.divinity
	if not d.pending_draft.is_empty():
		d.take_boon(String(d.pending_draft[0]["id"]))
	for f in _root.folk:
		if not is_instance_valid(f) or f.brain == null:
			continue
		if d.witness_left(f) > 0.0:
			_saw_window = true
			d.bless(f)
			_best_chain = maxi(_best_chain, d.combo_chain)
			break


## There is always something to aim at, and it is never the empty string.
func _check_goal() -> void:
	var goal: String = _root.next_goal()
	print("[POLISH] goal line: %s" % goal)
	if goal == "":
		_faults.append("next_goal() came back empty -- the player is told "
			+ "nothing about what to do")
	# It must also track the state rather than being a fixed string: a village
	# that has passed the first age must not still be asked to raise a roof.
	if _root.divinity.age > 0 and goal == "Raise a roof":
		_faults.append("the goal line is stuck on the first age's goal")


## The window the whole economy turns on is readable from outside Divinity.
func _check_window() -> void:
	if not _saw_window:
		_faults.append("witness_left() never went above zero in %d frames -- "
			% RUN_FRAMES + "either nobody worked, or the UI can never draw it")
	# And it is bounded: a fraction, not a duration.
	for f in _root.folk:
		if not is_instance_valid(f) or f.brain == null:
			continue
		var v: float = _root.divinity.witness_left(f)
		if v < 0.0 or v > 1.0:
			_faults.append("witness_left() returned %.3f, outside 0..1" % v)
			break
	print("[POLISH] witness window observed: %s" % _saw_window)


## A judgement asked for too early SAYS SO. It used to return false in silence.
func _check_cooldown() -> void:
	var d = _root.divinity
	var who = null
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null:
			who = f
			break
	if who == null:
		_faults.append("no follower to judge")
		return
	d.judge_cd = 0.0
	var before := _refused
	d.bless(who)                       # lands, and arms the cooldown
	d.bless(who)                       # too early: must be refused OUT LOUD
	if _refused <= before:
		_faults.append("a bless during the cooldown was swallowed -- no "
			+ "judge_refused, so no sound and no button state")
	print("[POLISH] refusals heard: %d" % (_refused - before))


## The chain is readable and it BREAKS audibly.
func _check_combo() -> void:
	var d = _root.divinity
	var seen := []
	d.combo_changed.connect(func(chain: int, mult: float):
		seen.append([chain, mult]))
	d.combo_chain = 3
	d.combo_left = d.COMBO_WINDOW
	d._break_combo()
	if seen.is_empty():
		_faults.append("breaking a chain of 3 emitted nothing at all")
	elif int(seen[-1][0]) != 0:
		_faults.append("a broken chain did not report chain 0")
	print("[POLISH] best chain reached %d, break reported: %s"
		% [_best_chain, not seen.is_empty()])


## Blessing steers a villager, and the panel can say so.
func _check_favour() -> void:
	var panel = _root.panel
	var who = null
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null:
			who = f
			break
	if who == null:
		return
	# Push one action well clear of 1.0, the way a few blessings would.
	who.brain.favour["chop"] = 2.4
	var line: String = panel._favour_line(who.brain)
	print("[POLISH] favour line: %s" % line)
	if line == "":
		_faults.append("a villager with favour 2.4 on an action showed no "
			+ "favour line -- the result of blessing is still invisible")
	# And an unsteered villager must NOT get a line, or it is noise. Every
	# action, not just the one we pushed -- this one has been blessed all run
	# and the first version of this check quietly tested nothing.
	var kept: Dictionary = who.brain.favour.duplicate()
	for act in who.brain.favour:
		who.brain.favour[act] = 1.0
	if panel._favour_line(who.brain) != "":
		_faults.append("a villager with every favour at 1.0 showed a line")
	who.brain.favour = kept
	if panel.divinity == null:
		_faults.append("the panel has no divinity, so it can never dim its "
			+ "buttons on the cooldown")


## Four things happening at once leave four lines, not one.
func _check_notices() -> void:
	var hud = _root.hud
	hud._notices.clear()
	for t in ["A wolf took a sheep.", "Hana has a child.",
			  "Odo took more than his share.", "The Watched Village."]:
		hud._say(t, 4.0)
	if hud._notices.size() != hud.NOTICE_MAX:
		_faults.append("the notice stack held %d of a maximum %d"
			% [hud._notices.size(), hud.NOTICE_MAX])
	# Newest first: the thing that just happened is the thing to read.
	if not hud._notices.is_empty() \
			and String(hud._notices[0]["text"]) != "The Watched Village.":
		_faults.append("the newest notice is not on top")
	# A repeat refreshes rather than stacking three identical lines.
	hud._say("The Watched Village.", 4.0)
	var same := 0
	for n in hud._notices:
		if String(n["text"]) == "The Watched Village.":
			same += 1
	if same != 1:
		_faults.append("a repeated notice stacked %d copies" % same)
	print("[POLISH] notice stack: %d lines, newest %s"
		% [hud._notices.size(), String(hud._notices[0]["text"])])


## A picture of the HUD with all of it on screen at once.
func _shoot() -> void:
	var d = _root.divinity
	# The draft overlay dims the whole screen and this picture is OF the HUD.
	_root.draft.close()
	d.pending_draft = []
	d.judge_cd = 0.0
	d.combo_chain = 3
	d.combo_left = d.COMBO_WINDOW
	d._combo_last = null
	_root.hud._combo_mult = 1.70
	_root.hud._combo_chain = 3
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null:
			_root.overhead.selected = f
			_root.panel.show_for(f)
			break
	_root.hud.queue_redraw()
	_root.panel.queue_redraw()
	_root.overhead.queue_redraw()


func _report() -> void:
	if _faults.is_empty():
		print("[POLISH] ok")
		return
	print("[POLISH] %d FAILURE(S)" % _faults.size())
	for f in _faults:
		print("  - %s" % f)
