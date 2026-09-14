extends SceneTree
## The hand: three cards, identical cards stack, and one reroll for all of them.
##
## Reported: the per-card reroll was "impossible" to click, and the owner asked
## for three things instead -- reroll the whole hand from a button at the side,
## let two or three of the same card be played together for a bigger reward
## with the UI saying so, and add cards that affect every villager at once.
##
## What is asserted:
##
##   - the hand still caps at three
##   - identical cards collapse into one stack, in first-appearance order
##   - playing a stack spends EVERY copy and hands the miracle their number
##   - a stacked miracle reaches further than a single one
##   - a village-wide card lands on every villager
##   - one reroll replaces the whole hand, charges once, and refuses when broke
##   - the reroll button is on screen, thumb-sized, and covers nothing
const ShotWindowRef := preload("res://tools/shot_window.gd")

const THUMB := 44.0

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
		d.age = 1
		for id in ["grove", "rain", "plenty", "feast"]:
			if not (id in d.unlocked_cards):
				d.unlocked_cards.append(id)
		_fills_and_caps(d)
		_stacks(d)
		# A stack in hand for the screenshot: two Groves and a Rain.
		d.hand.clear()
		for id in ["grove", "grove", "rain"]:
			d.hand.append(SaveGame.card_by_id(d, id))
		var rects: Array = _root.hud.call("_hand_rects")
		if not rects.is_empty():
			_root.hud._hover_override = (rects[0] as Rect2).get_center()
		return false
	if _f < 36:
		return false
	if _f == 36:
		ShotWindow.shoot("res://shots/hand_hover.png")
		var d = _root.divinity
		_reroll_geometry()
		_play_stack(d)
		_village_wide(d)
		_reroll(d)
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
	if Divinity.HAND_MAX != 3:
		_faults.append("HAND_MAX is %d, not the locked 3" % Divinity.HAND_MAX)
	d.hand.clear()
	for i in 10:
		d.draw_card()
	print("[HAND] drew 10 times; hand holds %d" % d.hand.size())
	if d.hand.size() != Divinity.HAND_MAX:
		_faults.append("drawing filled the hand to %d, not %d"
			% [d.hand.size(), Divinity.HAND_MAX])


## Identical cards are one stack, and the stack remembers where it first was.
func _stacks(d) -> void:
	d.hand.clear()
	for id in ["rain", "grove", "rain"]:
		d.hand.append(SaveGame.card_by_id(d, id))
	var st: Array = d.stacks()
	var shown: Array[String] = []
	for e in st:
		shown.append("%s x%d" % [e["card"]["id"], e["count"]])
	print("[HAND] rain, grove, rain -> %d stacks: %s" % [st.size(), str(shown)])
	if st.size() != 2:
		_faults.append("three cards with a duplicate made %d stacks, not 2"
			% st.size())
		return
	if String(st[0]["card"]["id"]) != "rain" or int(st[0]["count"]) != 2:
		_faults.append("the first stack should be rain x2 in first-appearance "
			+ "order, got %s x%d" % [st[0]["card"]["id"], st[0]["count"]])
	if d.hand.size() != 3:
		_faults.append("looking at the hand as stacks changed the hand itself")


## Playing a stack spends every copy and makes one stronger miracle.
func _play_stack(d) -> void:
	var cursor = _root.cursor
	if cursor == null:
		_faults.append("no miracle cursor in the scene")
		return
	if cursor.is_active():
		cursor.release()
	d.hand.clear()
	for id in ["grove", "grove", "rain"]:
		d.hand.append(SaveGame.card_by_id(d, id))
	var single: float = d.boons.card_radius()
	if not d.play_stack("grove"):
		_faults.append("playing a stack of two Groves was refused")
		return
	var left: int = d.hand.size()
	var power: int = int(cursor.power)
	var reach: float = float(cursor.radius)
	cursor.release()
	print("[HAND] two Groves as one: power %d, reach %.2f against %.2f alone, "
		% [power, reach, single] + "%d card(s) left" % left)
	if left != 1:
		_faults.append("playing a stack of two left %d cards, not 1 -- the "
			% left + "copies were not spent together")
	if power != 2:
		_faults.append("the miracle was handed power %d for two cards" % power)
	if reach <= single:
		_faults.append("a stack of two reached %.2f, no further than one "
			% reach + "card (%.2f) -- it is not rewarding more" % single)


## A village-wide card lands on everybody.
func _village_wide(d) -> void:
	var folk: Array = []
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null:
			f.brain.stats["hunger"] = 0.1
			folk.append(f)
	if folk.is_empty():
		_faults.append("no villagers to feed")
		return
	d.hand.clear()
	d.hand.append(SaveGame.card_by_id(d, "plenty"))
	if not d.play_stack("plenty"):
		_faults.append("Plenty was refused")
		return
	var fed := 0
	for f in folk:
		if float(f.brain.stats["hunger"]) > 0.5:
			fed += 1
	print("[HAND] Plenty fed %d of %d villagers" % [fed, folk.size()])
	if fed != folk.size():
		_faults.append("a village-wide card reached %d of %d villagers"
			% [fed, folk.size()])


## One reroll for the whole hand.
func _reroll(d) -> void:
	d.hand.clear()
	for id in ["grove", "rain", "feast"]:
		d.hand.append(SaveGame.card_by_id(d, id))
	d.faith = 100.0
	var before: float = d.faith
	var ok: bool = d.reroll_hand()
	print("[HAND] reroll_hand: %s, faith %.0f -> %.0f, hand %d"
		% [str(ok), before, d.faith, d.hand.size()])
	if not ok:
		_faults.append("reroll refused with 100 Faith in hand")
	if not is_equal_approx(before - float(d.faith), Divinity.HAND_REROLL_COST):
		_faults.append("reroll charged %.1f, not the declared %.1f"
			% [before - float(d.faith), Divinity.HAND_REROLL_COST])
	if d.hand.size() != 3:
		_faults.append("reroll changed the size of the hand to %d" % d.hand.size())
	d.faith = 0.0
	var snapshot: Array = d.hand.map(func(c): return String(c["id"]))
	if d.reroll_hand():
		_faults.append("reroll succeeded with no Faith to pay for it")
	if d.hand.map(func(c): return String(c["id"])) != snapshot:
		_faults.append("the hand changed even though the reroll was refused")
	d.hand.clear()
	if d.reroll_hand():
		_faults.append("rerolling an empty hand succeeded")


## The button is somewhere a person can press.
func _reroll_geometry() -> void:
	var hud = _root.hud
	var r: Rect2 = hud._reroll_rect()
	var vp: Vector2 = hud.get_viewport_rect().size
	print("[HAND] reroll button %s in a %s view" % [r, vp])
	if r.size.x <= 0.0:
		_faults.append("there is a hand and no reroll button")
		return
	if minf(r.size.x, r.size.y) < THUMB:
		_faults.append("the reroll button is %.0f units on its short side"
			% minf(r.size.x, r.size.y))
	if r.position.x < 0.0 or r.end.x > vp.x + 0.5 or r.end.y > vp.y + 0.5:
		_faults.append("the reroll button hangs off the screen")
	var others: Array = [["commune", hud._commune_rect()],
						 ["wrath", hud._wrath_rect()]]
	var cards: Array = hud._hand_rects()
	for i in cards.size():
		others.append(["card %d" % i, cards[i]])
	for o in others:
		if r.grow(-1.0).intersects((o[1] as Rect2).grow(-1.0)):
			_faults.append("the reroll button overlaps %s" % o[0])
