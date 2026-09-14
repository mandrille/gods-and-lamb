extends SceneTree
## When does an ordinary village first reach each age, and first see a disaster?
## Observation only -- rigs nothing, asserts nothing.
const ShotWindowRef := preload("res://tools/shot_window.gd")
const SPEED := 8.0
const WATCH := 1800.0
var _f := 0
var _root: Node = null
var _ages := {}
var _first_disaster := -1.0
var _kinds := {}
var _disasters := 0
var _touch_at := 0.0
var _greened := 0
var _grown := 0
var _first_card := -1.0
var _cards_played := 0


func _initialize() -> void:
	ShotWindowRef.park()
	get_root().add_child(
		(load("res://scenes/vale.tscn") as PackedScene).instantiate())


func _process(_d: float) -> bool:
	_f += 1
	if _f == 20:
		for n in get_root().get_children():
			if n.get("divinity") != null:
				_root = n
		if _root == null:
			printerr("no root"); quit(1); return true
		Engine.time_scale = SPEED
		_root.divinity.age_reached.connect(func(i: int, what: String):
			_ages[i] = [what, float(_root.village.now)])
		return false
	if _root == null:
		return false
	_play_god()
	if _first_card < 0.0 and not (_root.divinity.hand as Array).is_empty():
		_first_card = float(_root.village.now)
	var n: int = (_root.calamities as Array).size()
	if n > 0:
		for c in _root.calamities:
			if not _kinds.has(c):
				_kinds[c] = String(c.kind)
				_disasters += 1
				if _first_disaster < 0.0:
					_first_disaster = float(_root.village.now)
	if float(_root.village.now) < WATCH:
		return false
	print("[WATCH] %.0f village-seconds, folk %d, age %d, earned %.0f, buildings %d"
		% [_root.village.now, _root.folk.size(), _root.divinity.age,
		   _root.divinity.total_earned, Prophecy.read("roofs", _root)])
	for i in _ages.keys():
		print("[WATCH] age %d '%s' at %.0fs" % [i, _ages[i][0], _ages[i][1]])
	print("[WATCH] first disaster at %.0fs; %d disasters: %s"
		% [_first_disaster, _disasters, str(_kinds.values())])
	print("[WATCH] stores %s" % str(_root.village.stores))
	print("[WATCH] ENGAGED: greened %d, grew %d; first card in hand at %.0fs"
		% [_greened, _grown, _first_card])
	print("[WATCH] director calamity gate: folk >= %d; timer left %.0f"
		% [Director.CALAMITY_FOLK, _root._calamity_timer])
	quit(0)
	return true


## Plays like opening_probe: green next to the people, plant at the edge.
func _play_god() -> void:
	var t := float(_root.village.now)
	if t < _touch_at or _root.folk.is_empty():
		return
	_touch_at = t + WorldTouch.COOLDOWN
	var here: Vector2i = _root.grid.cell_of(_root.folk[0].position)
	var grass := _find(here, "G", true)
	if grass.x >= 0 and _grown * 2 < _greened:
		_root._touched_at = -99.0
		_root._on_ground(_root.grid.world_of(grass))
		_grown += 1
		return
	var dirt := _find(here, "D", false)
	if dirt.x < 0:
		return
	_root._touched_at = -99.0
	_root._on_ground(_root.grid.world_of(dirt))
	_greened += 1


func _find(from: Vector2i, ch: String, far: bool) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := -1 if far else 1 << 30
	for row in _root.builder.lower.size():
		var line: String = _root.builder.lower[row]
		for col in line.length():
			if line[col] != ch:
				continue
			var c := Vector2i(col, row)
			if _root._prop_on(c):
				continue
			var d: int = absi(c.x - from.x) + absi(c.y - from.y)
			if d > 16:
				continue
			if (far and d > best_d) or (not far and d < best_d):
				best_d = d
				best = c
	return best
