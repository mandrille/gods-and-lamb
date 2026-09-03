extends SceneTree
## Is the hand actually locked at three, and does a reroll do what it claims?
##
## Reported: "cards are locked to 3, hovering over them raises a bit and
## explains you what they do... if you don't want to use one you can reroll
## spending faith." The lift-and-explain half already existed (HUD._hand /
## _tooltip); this checks the two things that did not: HAND_MAX actually caps
## the hand at three rather than growing at Age II the way it used to, and the
## new per-card reroll spends Faith, replaces exactly one card, and refuses
## when it cannot be afforded.
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
	if _f == 30:
		for n in get_root().get_children():
			if n.get("divinity") != null:
				_root = n
		if _root == null:
			printerr("[HAND] FAIL: no scene root")
			quit(1)
			return true

		var d = _root.divinity
		d.age = 1                      # cards do not draw before Age I
		print("[HAND] HAND_MAX = %d" % Divinity.HAND_MAX)
		if Divinity.HAND_MAX != 3:
			_faults.append("HAND_MAX is %d, not the locked 3 that was asked "
				% Divinity.HAND_MAX + "for")
		_fills_and_caps(d)
		# PERSISTENT, not a one-shot call: HUD's own automatic _process()
		# re-derives _hot from the real mouse every frame, which is garbage in
		# this parked/unfocused window and would undo a single manual call on
		# the very next tick. _hover_override keeps it pointed here across
		# every frame between now and the screenshot.
		var rects: Array = _root.hud.call("_hand_rects")
		if not rects.is_empty():
			_root.hud._hover_override = (rects[0] as Rect2).get_center()
		return false
	if _f < 36:
		return false
	if _f == 36:
		get_root().get_texture().get_image().save_png(
			"res://shots/hand_hover.png")
		var d = _root.divinity
		_reroll_spends_and_replaces(d)
		_reroll_refuses_when_broke(d)
		_reroll_bounds(d)
		_tooltip_geometry()

		if _faults.is_empty():
			print("[HAND] ok")
		else:
			for f in _faults:
				printerr("[HAND]   - " + f)
			printerr("[HAND] %d FAILURE(S)" % _faults.size())
		quit(0 if _faults.is_empty() else 1)
		return true
	return false


func _fills_and_caps(d) -> void:
	d.hand.clear()
	for i in 10:
		d.draw_card()
	print("[HAND] drew 10 times; hand holds %d" % d.hand.size())
	if d.hand.size() != Divinity.HAND_MAX:
		_faults.append("drawing repeatedly filled the hand to %d, not the "
			% d.hand.size() + "locked cap of %d" % Divinity.HAND_MAX)


func _reroll_spends_and_replaces(d) -> void:
	d.faith = 100.0
	var before: float = d.faith
	var was: Array = d.hand.duplicate(true)
	var ok: bool = d.reroll_card(0)
	print("[HAND] reroll(0): %s, %s -> %s, faith %.0f -> %.0f"
		% [str(ok), String(was[0]["id"]), String(d.hand[0]["id"]),
		   before, d.faith])
	if not ok:
		_faults.append("reroll refused with 100 Faith in hand")
	if d.hand.size() != was.size():
		_faults.append("reroll changed the SIZE of the hand from %d to %d"
			% [was.size(), d.hand.size()])
	if before - d.faith != Divinity.HAND_REROLL_COST:
		_faults.append("reroll charged %.1f, not the declared cost %.1f"
			% [before - d.faith, Divinity.HAND_REROLL_COST])
	# The other two slots must be untouched -- a reroll on card 0 is not
	# licence to reshuffle the whole hand.
	for i in range(1, was.size()):
		if String(was[i]["id"]) != String(d.hand[i]["id"]):
			_faults.append("reroll(0) also changed slot %d" % i)


func _reroll_refuses_when_broke(d) -> void:
	d.faith = 0.0
	var was: Dictionary = d.hand[0].duplicate()
	var ok: bool = d.reroll_card(0)
	print("[HAND] reroll with 0 Faith: %s" % str(ok))
	if ok:
		_faults.append("reroll succeeded with no Faith to pay for it")
	if String(d.hand[0]["id"]) != String(was["id"]):
		_faults.append("the card changed even though the reroll was refused")


func _reroll_bounds(d) -> void:
	d.faith = 100.0
	if d.reroll_card(-1) or d.reroll_card(d.hand.size() + 5):
		_faults.append("reroll accepted an out-of-range index instead of "
			+ "refusing it")


## The reroll button has to be drawn INSIDE the panel it is offered on --
## the "one source" comment on _tooltip_geo is a promise, and this is what
## checking that promise looks like.
func _tooltip_geometry() -> void:
	var hud = _root.hud
	if hud == null:
		_faults.append("no HUD to test tooltip geometry against")
		return
	var anchor := Rect2(100, 400, 96, 116)
	var card: Dictionary = {"id": "rain", "name": "Rain", "desc":
		"Everyone is washed clean, and the crops drink."}
	var geo: Dictionary = hud.call("_tooltip_geo", anchor, card)
	var panel: Rect2 = geo["panel"]
	var reroll: Rect2 = geo["reroll"]
	print("[HAND] tooltip panel %s, reroll button %s" % [str(panel), str(reroll)])
	if not panel.encloses(reroll):
		_faults.append("the reroll button is drawn outside its own tooltip "
			+ "panel: %s not inside %s" % [str(reroll), str(panel)])
