extends SceneTree
## The prayer rail, and the village asking as one.
##
## Reported: "The prayers go to the top, you see an icon, click on it, tells you
## what they want" and "Prayers can be global or unique, for example, we want
## more trees vs I want an apple".
##
## What is asserted:
##
##   - there are village-wide prayer kinds, and they say something with no name
##   - no single villager ever makes one
##   - the village asks when its state calls for it, and not otherwise
##   - a matching act ANYWHERE answers it, with no witness needed
##   - it settles, and pays, once the village is actually better
##   - it does not take a hungry person's prayer slot
##   - the rail shows both kinds, on screen, big enough to press
##   - pressing a person's prayer takes the camera to them and selects them
##   - pressing it again closes the card
const ShotWindowRef := preload("res://tools/shot_window.gd")
const TestGroundRef := preload("res://tools/test_ground.gd")

const THUMB := 44.0

var _f := 0
var _root: Node = null
var _faults: Array[String] = []
var _answered := false
var _closed := false


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
		printerr("[RAIL] FAIL: no scene root")
		quit(1)
		return true
	TestGroundRef.green(_root)
	_root.prayers.closed.connect(func(_p, ok):
		_closed = true
		_answered = ok)

	_check_table()
	_check_never_personal()
	_check_harvest()
	_check_room()
	_check_rail()
	_report()
	quit(0 if _faults.is_empty() else 1)
	return true


func _now() -> float:
	return float(_root.village.now)


func _village_kinds() -> Array:
	var out: Array = []
	for kind in Prayer.KINDS:
		if bool(Prayer.KINDS[kind].get("village", false)):
			out.append(String(kind))
	return out


func _check_table() -> void:
	var kinds := _village_kinds()
	if kinds.size() < 3:
		_faults.append("only %d village-wide prayer kinds" % kinds.size())
	for kind in kinds:
		var p := Prayer.new(kind, null, 0.0)
		var line := p.says()
		if line == "" or line.contains("%"):
			_faults.append("the village prayer '%s' says '%s'" % [kind, line])
		if not p.alive(1.0):
			_faults.append("a fresh village prayer '%s' is already dead" % kind)
	print("[RAIL] %d village-wide kinds: %s" % [kinds.size(), str(kinds)])


## A starving, miserable villager asks for plenty -- and never for the village.
func _check_never_personal() -> void:
	var who = null
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null and f.brain.adult:
			who = f
			break
	if who == null:
		_faults.append("no adult to test with")
		return
	who.brain.stats["hunger"] = 0.05
	who.brain.stats["fun"] = 0.05
	who.brain.stats["health"] = 0.05
	var kinds := _village_kinds()
	var seen: Dictionary = {}
	for i in 100:
		var made = _root.prayers._consider(who, _now(), true)
		if made != null:
			seen[made.kind] = true
	for k in seen:
		if String(k) in kinds:
			_faults.append("one villager opened the village's prayer '%s'" % k)
	print("[RAIL] one desperate villager asks for %s" % str(seen.keys()))


## The granary: asked when it is low, answered from anywhere, settled when full.
func _check_harvest() -> void:
	var pr = _root.prayers
	pr.active.clear()
	pr._global_look = 0.0
	pr._global_rest.clear()
	var now := _now()
	# Only the granary may answer, so rest every other village kind.
	for kind in _village_kinds():
		if kind != "harvest":
			pr._global_rest[kind] = now + 99999.0
	_root.village.stores["food"] = 999
	pr._open_global(now)
	if not pr.active.is_empty():
		_faults.append("a full granary asked for a harvest")
		pr.active.clear()
	_root.village.stores["food"] = 0
	pr._global_look = 0.0
	pr._open_global(now)
	var p = null
	for q in pr.active:
		if q.kind == "harvest":
			p = q
	if p == null:
		_faults.append("an empty granary did not ask for anything")
		return
	if not p.urgent:
		_faults.append("an EMPTY granary asked mildly rather than desperately")

	# A food act a long way from anybody: no witness at all.
	var a := DivineAction.make("grow", Vector3(9999, 0, 9999), 1.0, 0.5)
	a.tags = DivineAction.FOOD
	var r: Dictionary = _root.divinity.perform(a)
	if int(r.get("seen", 0)) != 0:
		_faults.append("the far-away act was seen -- this check proves nothing")
	if not p.touched_by_god:
		_faults.append("a food act did not answer the village's harvest prayer "
			+ "because nobody was standing near it")

	_closed = false
	_answered = false
	pr._close(now + 1.0)
	if not pr.active.has(p):
		_faults.append("the prayer closed while the granary was still empty")
	_root.village.stores["food"] = int(_root.folk.size()) * 4 + 10
	var faith_before := _village_faith()
	pr._close(now + 2.0)
	if pr.active.has(p):
		_faults.append("the granary filled and the prayer stayed open")
	if not _closed or not _answered:
		_faults.append("it closed without being counted as answered by the god")
	if _village_faith() <= faith_before:
		_faults.append("answering the village paid the village nothing")
	print("[RAIL] harvest: opened desperate %s, answered from nowhere %s, "
		% [p.urgent, p.touched_by_god] + "closed answered %s" % _answered)


func _village_faith() -> float:
	var t := 0.0
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null:
			t += float(f.brain.faith_xp) + float(f.brain.faith_level) * 1000.0
	return t


## A village prayer does not take a hungry person's slot.
func _check_room() -> void:
	var pr = _root.prayers
	pr.active.clear()
	pr.active.append(Prayer.new("harvest", null, _now()))
	var personal := 0
	for p in pr.active:
		if not p.village_wide():
			personal += 1
	var room: int = Prayers.MAX_ACTIVE - personal
	if room != Prayers.MAX_ACTIVE:
		_faults.append("a village prayer used up a personal prayer slot")
	pr.active.clear()


## The rail: both kinds, on screen, pressable, and it takes you there.
func _check_rail() -> void:
	var hud = _root.hud
	var pr = _root.prayers
	pr.active.clear()
	var who = null
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null:
			who = f
			break
	if who == null:
		return
	var person := Prayer.new("food", who, _now())
	pr.active.append(Prayer.new("trees", null, _now()))
	pr.active.append(person)
	var list: Array = hud._rail_prayers()
	var rects: Array = hud._rail_rects()
	var vp: Vector2 = hud.get_viewport_rect().size
	print("[RAIL] %d on the rail at %s in a %s view" % [rects.size(), str(rects), vp])
	if rects.size() != 2:
		_faults.append("two prayers standing and %d slots on the rail" % rects.size())
		return
	if not list[0].village_wide():
		_faults.append("the village's prayer is not first on the rail")
	for r in rects:
		if minf(r.size.x, r.size.y) < THUMB:
			_faults.append("a rail slot is %.0f on its short side" % minf(r.size.x, r.size.y))
		if r.position.x < 0.0 or r.end.x > vp.x + 0.5 or r.position.y < 0.0:
			_faults.append("a rail slot is off the screen: %s" % r)
		if r.intersects(hud._ledger_rect()):
			_faults.append("a rail slot sits on the ledger")

	var i: int = list.find(person)
	hud._open_rail(i)
	if hud._rail_open != person:
		_faults.append("pressing a prayer did not open its card")
	if _root.overhead.selected != who:
		_faults.append("pressing a person's prayer did not select them")
	var focus: Vector3 = _root.rig.focus
	var flat := Vector2(who.position.x - focus.x, who.position.z - focus.z)
	if flat.length() > 0.6:
		_faults.append("pressing a person's prayer left the camera %.1f m away"
			% flat.length())
	var card: Rect2 = hud._rail_detail_rect()
	if card.size.x <= 0.0 or card.end.x > vp.x + 0.5:
		_faults.append("the prayer card is missing or off the screen: %s" % card)
	hud._open_rail(i)
	if hud._rail_open != null:
		_faults.append("pressing the same prayer again did not close its card")
	print("[RAIL] pressing %s's prayer selects them and moves the camera to "
		% who.brain.name + "within %.2f m" % flat.length())
	pr.active.clear()


func _report() -> void:
	for f in _faults:
		print("  - %s" % f)
	if _faults.is_empty():
		print("[RAIL] the village asks, and you can see who")
	else:
		print("[RAIL] %d FAILURE(S)" % _faults.size())
