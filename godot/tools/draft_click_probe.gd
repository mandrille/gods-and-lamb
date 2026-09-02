extends SceneTree
## Can the player actually CLICK a boon card?
##
## Reported from play: "got my first boon but I could not select it." Every
## existing check calls the `chosen` signal or take_boon() directly, so the
## whole input path -- viewport -> CanvasLayer -> Control -> _gui_input -> the
## hit test against _hot -- was never exercised by anything.
const ShotWindowRef := preload("res://tools/shot_window.gd")

var _f := 0
var _root: Node = null
var _got := ""
var _faults: Array[String] = []


func _initialize() -> void:
	ShotWindowRef.park()
	get_root().add_child(
		(load("res://scenes/vale.tscn") as PackedScene).instantiate())


func _process(_d: float) -> bool:
	_f += 1
	if _f < 30:
		return false
	if _f == 30:
		for n in get_root().get_children():
			if n.get("divinity") != null:
				_root = n
		if _root == null:
			printerr("[DRAFT] FAIL: no scene root")
			quit(1)
			return true
		var d = _root.divinity
		d.age = 1
		d.pending_draft = []
		d.faith = 500.0
		_root.draft.chosen.connect(func(id): _got = String(id))
		if not d.commune():
			_faults.append("could not open a draft to click on")
			_finish()
			return true
		print("[DRAFT] open=%s  visible=%s  filter=%d  options=%d"
			% [str(_root.draft.is_open()), str(_root.draft.visible),
			   _root.draft.mouse_filter, _root.pending_size()
			   if _root.has_method("pending_size") else d.pending_draft.size()])
		return false

	# Two separate things were wrong, so they are checked separately.
	#
	# Headless push_input does not drive the viewport's GUI picking (there is
	# no real window or pointer), so this cannot assert "a click arrives". It
	# asserts the two facts that made the click impossible: that the overlay
	# has a rect for the pointer to be inside at all, and that a click landing
	# on a card resolves to that card.
	if _f == 34:
		var r: Rect2 = _root.draft.get_global_rect()
		print("[DRAFT] overlay rect %s (viewport %s)"
			% [str(r), str(get_root().get_visible_rect().size)])
		# THE BUG: PRESET_FULL_RECT resolves against a parent Control, and the
		# parent is a CanvasLayer, so the rect stayed empty and the viewport
		# never found the overlay under the pointer.
		if r.size.x < 1.0 or r.size.y < 1.0:
			_faults.append("the draft has an empty rect, so nothing can ever "
				+ "be clicked on it and it swallows no clicks either")
		elif r.size != get_root().get_visible_rect().size:
			_faults.append("the draft does not cover the screen: %s vs %s"
				% [str(r.size), str(get_root().get_visible_rect().size)])

		var rects: Array = _root.draft.call("_card_rects")
		if rects.is_empty():
			_faults.append("the draft drew no cards")
			_finish()
			return true
		# And the hit test itself, driven by the event position the way
		# _gui_input receives it.
		var at: Vector2 = (rects[0] as Rect2).get_center()
		# Read the expected id BEFORE clicking: choosing takes the boon and
		# closes the draft, which empties pending_draft.
		var want := String((_root.draft.get("_options")[0])["id"])
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = true
		mb.position = at
		_root.draft.call("_gui_input", mb)
		print("[DRAFT] click at card 1 centre %s -> chosen '%s'" % [str(at), _got])
		if _got == "":
			_faults.append("a click on the middle of the first card selected "
				+ "nothing")
		if _got != "" and _got != want:
			_faults.append("clicking card 1 chose '%s', not '%s'" % [_got, want])
		_finish()
		return true
	return false


func _finish() -> void:
	if _faults.is_empty():
		print("[DRAFT] ok")
	else:
		for f in _faults:
			printerr("[DRAFT]   - " + f)
		printerr("[DRAFT] %d FAILURE(S)" % _faults.size())
	quit(0 if _faults.is_empty() else 1)
