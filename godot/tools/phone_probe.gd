extends SceneTree
## Can this be played with a thumb, on a phone-shaped screen?
##
## The project has always been configured for portrait (720x1280, expand) and
## the camera rig has always had a touch path, but nothing had ever laid the
## HUD out at that size and looked at it. Every rect in `hud.gd` is a hand-drawn
## constant in pixels, and the whole hit-test layer is `Rect2.has_point` -- so
## the two ways this fails on a handset are both silent:
##
##   - two panels drawn on top of each other, where the top one eats the taps
##     meant for the one underneath
##   - a control that is fine under a mouse pointer and too small for a thumb
##
## Plus the input path itself: a real InputEventScreenTouch has to reach a
## villager, and two fingers have to zoom. Those are pushed through
## `Input.parse_input_event` rather than called directly, because calling the
## handler proves the handler and not the wiring.
const ShotWindowRef := preload("res://tools/shot_window.gd")

## Apple's is 44pt, Google's 48dp. 44 is the number a card has to clear.
const THUMB := 44.0
## A phone in portrait, which is the shipping aspect.
const PHONE := Vector2i(750, 1624)

var _f := 0
var _root: Node = null
var _hud = null
var _faults: Array[String] = []


func _initialize() -> void:
	ShotWindowRef.park()
	get_root().add_child(
		(load("res://scenes/vale.tscn") as PackedScene).instantiate())


func _process(_d: float) -> bool:
	_f += 1
	# The HUD lays out from the viewport, so the size has to be in place before
	# anything is measured -- and one frame has to pass for it to take.
	if _f == 8:
		# A REAL HANDSET, in pixels: 375x812 points at 2x. The game picks its
		# own UI scale from this, and that scale is half of what is being
		# tested -- a layout that passes at 720 units can be unusable at 400.
		get_root().size = PHONE
		_root_scale()
		return false
	if _f < 40:
		return false
	for n in get_root().get_children():
		if n.get("divinity") != null:
			_root = n
	if _root == null:
		printerr("[PHONE] FAIL: no scene root")
		quit(1)
		return true
	_hud = _root.hud
	if _hud == null:
		printerr("[PHONE] FAIL: no HUD")
		quit(1)
		return true

	# A FULL HAND, or the layout check measures an empty screen. The hand is
	# the widest thing on a phone and the thing most likely to collide.
	for _i in _root.divinity.HAND_MAX_NOW:
		_root.divinity.draw_card()

	_check_size()
	_check_top()
	_check_overlap()
	_check_thumb()
	_check_modals()
	_check_tap()
	_check_pinch()
	_report()
	quit(0 if _faults.is_empty() else 1)
	return true


## The UI has to end up dealt out in FEWER units than the window has pixels,
## or every control is drawn at less than a point per unit and the whole screen
## is half-size in the hand.
func _check_size() -> void:
	var vp: Vector2 = _hud.get_viewport_rect().size
	var w: Window = get_root()
	print("[PHONE] %d x %d px, scale factor %.2f, UI laid out in %d x %d units"
		% [PHONE.x, PHONE.y, w.content_scale_factor, vp.x, vp.y])
	if vp.x > 480.0:
		_faults.append("the UI is %d units across on a handset -- everything "
			% vp.x + "on screen will be drawn at well under half size")
	if vp.x < 320.0:
		_faults.append("the UI is only %d units across, which is not enough "
			% vp.x + "room to lay a card hand out in")


## Force the game to re-pick its UI scale for the size just set.
func _root_scale() -> void:
	for n in get_root().get_children():
		if n.has_method("_apply_ui_scale"):
			n._apply_ui_scale()


## THE TOP-LEFT STACK FITS, and does not sit on the day clock.
##
## Four things pile into that corner and each one used to carry its own literal
## offset -- which is how the god-level bar was drawn straight through the goal
## line the day it was added. Both of those are read-only text, so nothing
## breaks; it just becomes unreadable, quietly, on the screen the player looks
## at first.
func _check_top() -> void:
	var vp: Vector2 = _hud.get_viewport_rect().size
	var ledger: Rect2 = _hud._ledger_rect()
	var god := Rect2(_hud.PAD, _hud._god_y(), 10.0, _hud.GOD_H)
	print("[PHONE] ledger %.0f units wide in %.0f; rows at y = %.0f / %.0f / "
		% [ledger.size.x, vp.x, ledger.position.y, _hud._god_y()]
		+ "%.0f / %.0f" % [_hud._goal_y(), _hud._combo_y()])
	if ledger.end.x > vp.x + 0.5:
		_faults.append("the ledger is %.0f units wide and the screen is %.0f "
			% [ledger.size.x, vp.x] + "-- the last counters are off the edge")
	if ledger.intersects(Rect2(_hud.PAD, _hud.PAD - 2.0, vp.x - _hud.PAD * 2.0,
							   _hud.DAYBAR_H)):
		_faults.append("the ledger and the day clock are drawn on top of "
			+ "each other")
	if god.position.y < ledger.end.y:
		_faults.append("the god level bar overlaps the ledger")
	if _hud._goal_y() < god.end.y:
		_faults.append("the goal line is drawn through the god level bar")
	# THE NOTICE STACK, which this probe has never checked and which was drawn
	# straight over the ledger on every phone: it started at PAD + 52 = 68,
	# centred, while `_stack_top` put the ledger at 74 -- and `_toast` paints
	# after `_ledger`, so every message covered the village's own resource
	# counts. It is the last rung of the ladder on a narrow screen now.
	var notice := Rect2(_hud.PAD, _hud._notice_y(), 120.0, 32.0)
	print("[PHONE] notice stack starts at y = %.0f" % notice.position.y)
	if notice.intersects(ledger):
		_faults.append("the notice stack is drawn over the ledger")
	if notice.position.y < _hud._combo_y():
		_faults.append("the notice stack is drawn through the combo rung")
	if notice.end.y > vp.y:
		_faults.append("the notice stack starts below the bottom of the screen")
	if _hud._combo_y() < _hud._goal_y() + 12.0:
		_faults.append("the combo pips are drawn through the goal line")


## NOTHING SITS ON TOP OF ANYTHING ELSE. Every one of these is a hit-tested
## rect, so an overlap is not a cosmetic complaint: whichever is tested first
## silently swallows the tap meant for the other.
func _check_overlap() -> void:
	# Deal a hand, so the row above it -- and the reroll in the middle of it --
	# is laid out the way a player actually sees it.
	if _root.divinity.hand.is_empty():
		for i in 3:
			_root.divinity.draw_card()
	# And something on the prayer rail: one village prayer and one person.
	if _root.prayers.active.is_empty():
		var now := float(_root.village.now)
		_root.prayers.active.append(Prayer.new("harvest", null, now))
		for f in _root.folk:
			if is_instance_valid(f) and f.brain != null:
				_root.prayers.active.append(Prayer.new("food", f, now))
				break
	var named: Array = []
	var hand: Array[Rect2] = _hud._hand_rects()
	for i in hand.size():
		named.append(["card %d" % i, hand[i]])
	named.append(["commune", _hud._commune_rect()])
	named.append(["wrath", _hud._wrath_rect()])
	# THE REROLL BUTTON, which used to sit under the Commune/Wrath row on every
	# phone and could not be pressed. It needs a hand to exist at all.
	if _hud._reroll_rect().size.x > 0.0:
		named.append(["reroll", _hud._reroll_rect()])
	var rail: Array[Rect2] = _hud._rail_rects()
	for i in rail.size():
		named.append(["prayer %d" % i, rail[i]])
	# The rail has its own reserved rung: the ledger must start below it.
	if not rail.is_empty() and _hud._stack_top() < rail[0].end.y:
		_faults.append("the ledger starts at %.0f, inside the prayer rail "
			% _hud._stack_top() + "which ends at %.0f" % rail[0].end.y)
	for a in named.size():
		for b in range(a + 1, named.size()):
			var ra: Rect2 = named[a][1]
			var rb: Rect2 = named[b][1]
			# Cards lift when hovered, so allow the lift as slack vertically.
			if not ra.grow(-1.0).intersects(rb.grow(-1.0)):
				continue
			_faults.append("%s and %s overlap on a phone: %s vs %s"
				% [named[a][0], named[b][0], ra, rb])
	print("[PHONE] %d tappable rects, %d overlapping"
		% [named.size(), _faults.size()])
	# And nothing may hang off the screen.
	var vp: Vector2 = _hud.get_viewport_rect().size
	for e in named:
		var r: Rect2 = e[1]
		if r.position.x < 0.0 or r.end.x > vp.x + 0.5 \
				or r.position.y < 0.0 or r.end.y > vp.y + 0.5:
			_faults.append("%s is off the screen: %s in a %s viewport"
				% [e[0], r, vp])


func _check_thumb() -> void:
	var smallest := 9999.0
	var worst := ""
	var named: Array = [["commune", _hud._commune_rect()],
						["wrath", _hud._wrath_rect()]]
	if _hud._reroll_rect().size.x > 0.0:
		named.append(["reroll", _hud._reroll_rect()])
	var hand: Array[Rect2] = _hud._hand_rects()
	for i in hand.size():
		named.append(["card %d" % i, hand[i]])
	for e in named:
		var r: Rect2 = e[1]
		var m: float = minf(r.size.x, r.size.y)
		if m < smallest:
			smallest = m
			worst = String(e[0])
	print("[PHONE] smallest tap target: %s at %.0f px (thumb needs %.0f)"
		% [worst, smallest, THUMB])
	if smallest < THUMB:
		_faults.append("%s is %.0f px on its short side -- too small for a thumb"
			% [worst, smallest])


## EVERY MODAL FITS. These are the screens that stop the game and ask for a
## decision -- the boon draft, nightfall, the pause menu -- and each was laid
## out around a width constant chosen on a desktop. A card the player cannot
## see is a choice they are not making; a button off the right edge cannot be
## pressed at all, and the modal eats input until it is.
func _check_modals() -> void:
	var vp: Vector2 = _hud.get_viewport_rect().size
	var draft = _root.draft
	if draft != null:
		draft.size = vp
		draft._options = [
			{"id": "a", "name": "Kindled Hearth", "rank": 1, "icon": "heart",
			 "what": "Hunger, weariness and loneliness come on more slowly.",
			 "blurb": "Needs grow 12% slower"},
			{"id": "b", "name": "Deep Roots", "rank": 2, "icon": "sprout",
			 "what": "The fields keep giving a little longer than they should.",
			 "blurb": "Harvests yield 20% more"},
			{"id": "c", "name": "Long Watch", "rank": 3, "icon": "dove",
			 "what": "Someone is always awake, and the flock sleeps easier.",
			 "blurb": "Wolves come half as often"},
		]
		var rects: Array[Rect2] = draft._card_rects()
		print("[PHONE] boon draft: %d cards, first %s, reroll %s"
			% [rects.size(), rects[0] if rects.size() > 0 else Rect2(),
			   draft._reroll_rect()])
		_fits("boon draft card %d", rects, vp)
		_fits1("the reroll button", draft._reroll_rect(), vp)
		for a in rects.size():
			for b in range(a + 1, rects.size()):
				if rects[a].grow(-1.0).intersects(rects[b].grow(-1.0)):
					_faults.append("boon cards %d and %d overlap" % [a, b])
		draft._options = []
	# THE PAUSE MENU, which is where the comfort switches live and which grew
	# from three rows to six the day they arrived. A modal that fits at three
	# rows is not a modal that fits at six, and nothing was checking.
	var pause = _root.pause_menu
	if pause != null:
		pause.size = vp
		pause.comfort = _root.comfort
		var pr: Rect2 = pause._panel_rect()
		print("[PHONE] pause menu: %d rows, %s" % [pause._labels().size(), pr])
		_fits1("the pause menu", pr, vp)
		var buttons: Array = pause._button_rects()
		for i in buttons.size():
			_fits1("pause row %d" % i, buttons[i], vp)
			if buttons[i].size.y < THUMB:
				_faults.append("pause row %d is %.0f units tall, under a thumb"
					% [i, buttons[i].size.y])

	var night = _root.day_screen
	if night != null:
		night.size = vp
		var p: Rect2 = night._panel_rect()
		print("[PHONE] nightfall panel: %s" % p)
		_fits1("the nightfall panel", p, vp)
		_fits("nightfall aura %d", night._aura_rects(), vp)
	var menu = _root.pause_menu
	if menu != null:
		menu.size = vp
		_fits("pause menu button %d", menu._button_rects(), vp)


func _fits(label: String, rects: Array, vp: Vector2) -> void:
	for i in rects.size():
		_fits1(label % i, rects[i], vp)


func _fits1(what: String, r: Rect2, vp: Vector2) -> void:
	if r.size == Vector2.ZERO:
		return
	if r.position.x >= -0.5 and r.end.x <= vp.x + 0.5 			and r.position.y >= -0.5 and r.end.y <= vp.y + 0.5:
		return
	_faults.append("%s does not fit the screen: %s in %s" % [what, r, vp])


## A REAL TOUCH BLESSES A VILLAGER. Pushed through the input system, not
## called on the handler, so this covers the wiring as well as the code.
func _check_tap() -> void:
	var who = null
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null:
			who = f
			break
	if who == null:
		_faults.append("nobody to tap")
		return
	var cam: Camera3D = _root.rig.cam
	var at: Vector2 = cam.unproject_position(
		who.global_position + Vector3(0, 0.9, 0))
	_root.divinity.judge_cd = 0.0
	_root.panel.who = null
	_tap(at)
	# THE PANEL is the assertion, not the faith. A tap that misses the villager
	# and lands on the ground behind them still pays faith to everyone standing
	# nearby -- that villager included -- so faith going up proves nothing about
	# whether the finger actually hit the person.
	var hit = _root.panel.who
	print("[PHONE] tapping a villager at %s selected: %s"
		% [at, "nobody" if hit == null else "them"])
	if hit != who:
		_faults.append("a touch on a villager did not select them -- the main "
			+ "verb in the game is unreachable with a finger")


## TWO FINGERS ZOOM. Without this the player is stuck at whatever distance the
## game opened at, because there is no wheel on a phone.
func _check_pinch() -> void:
	var rig = _root.rig
	var before: float = rig.dist
	var mid := Vector2(360.0, 640.0)
	_touch(0, mid - Vector2(60, 0), true)
	_touch(1, mid + Vector2(60, 0), true)
	_drag(0, mid - Vector2(160, 0))
	_drag(1, mid + Vector2(160, 0))
	var after: float = rig.dist
	_touch(0, mid - Vector2(160, 0), false)
	_touch(1, mid + Vector2(160, 0), false)
	print("[PHONE] pinching apart: camera distance %.2f -> %.2f"
		% [before, after])
	if is_equal_approx(before, after):
		_faults.append("a pinch did not move the camera")
	elif after > before:
		_faults.append("spreading two fingers zoomed OUT, which is backwards")
	# And the fingers are released, so the rig is not left mid-gesture.
	if rig._touches.size() > 0:
		_faults.append("%d fingers still held after they were lifted"
			% rig._touches.size())


func _tap(at: Vector2) -> void:
	_touch(0, at, true)
	_touch(0, at, false)


func _touch(index: int, at: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = at
	e.pressed = pressed
	Input.parse_input_event(e)
	root.get_viewport().push_input(e, true)


func _drag(index: int, to: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = to
	root.get_viewport().push_input(e, true)


func _report() -> void:
	if _faults.is_empty():
		print("[PHONE] ok")
		return
	print("[PHONE] %d FAILURE(S)" % _faults.size())
	for f in _faults:
		print("  - %s" % f)
