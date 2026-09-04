extends SceneTree
## Does a saved village come back as the same village?
##
## Field by field, because "it loaded" is not the question. The dangerous
## failures here all LOOK fine: a villager with the right name reasoning about
## the previous world, a walk speed that compounds a little on every load, a
## felled tree standing again because the delta was applied to a regenerated
## document. Each of those produces plausible behaviour, which is the worst
## kind of bug to ship.
##
## This is the one probe that is allowed to touch the disk, so it writes to its
## own file and deletes it afterwards -- a leftover save from a probe run would
## silently become the village a human loads.
const ShotWindowRef := preload("res://tools/shot_window.gd")

const SPEED := 20.0
const RUN_FRAMES := 420

var _f := 0
var _root: Node = null
var _faults: Array[String] = []
var _before := {}
var _cycle := 0
var _walk_seen: Array[float] = []


func _initialize() -> void:
	ShotWindowRef.park()
	SaveGame.erase()
	_open()


func _open() -> void:
	var scene = (load("res://scenes/vale.tscn") as PackedScene).instantiate()
	# The one probe that WANTS the disk. Everything else is guarded off it by
	# Persistence.is_real_game.
	scene.load_saves = true
	get_root().add_child(scene)
	_root = scene


func _process(_d: float) -> bool:
	_f += 1
	# The first cycle needs frames to settle; a LOADED one must be measured as
	# early as possible. Twenty frames of grace is twenty frames of income, and
	# the whole question here is whether a number came back unchanged.
	if _cycle == 0:
		if _f < 20:
			return false
		if _f == 20:
			if _root == null or _root.get("divinity") == null:
				printerr("[SAVE] FAIL: no scene root")
				quit(1)
				return true
			Engine.time_scale = SPEED
			return false
	elif _root == null or _root.get("divinity") == null:
		printerr("[SAVE] FAIL: the loaded scene has no root")
		quit(1)
		return true

	if _cycle == 0:
		if _f < RUN_FRAMES:
			return false
		Engine.time_scale = 1.0
		_stir()
		_before = _fingerprint()
		if not _root.saving.save_now("probe"):
			_faults.append("save_now refused to write")
		_reopen()
		return false

	# Cycles 1 and 2 both load. The SECOND one is the point: a modifier that
	# compounds on load is invisible after one round trip and obvious after two.
	#
	if _f < 2:
		return false
	var after := _fingerprint()
	_walk_seen.append(float(after.get("walk_total", 0.0)))
	if _cycle == 1:
		_compare(_before, after)
		_reopen()
		return false

	if not is_equal_approx(_walk_seen[0], _walk_seen[1]):
		_faults.append("walk speed drifted between the first and second load: "
			+ "%.4f then %.4f -- a boost is being applied on top of a boosted "
			% [_walk_seen[0], _walk_seen[1]]
			+ "value, which compounds on every load forever")
	SaveGame.erase()
	_report()
	quit(0 if _faults.is_empty() else 1)
	return true


func _reopen() -> void:
	# Frozen BEFORE the new scene exists. The comparison is of a saved village
	# against a loaded one, and a loaded one that has been running for twenty
	# frames has earned twenty frames of Faith -- the probe measuring itself.
	Engine.time_scale = 0.0
	_cycle += 1
	_f = 0
	_root.queue_free()
	_root = null
	_open()


## Make the village worth saving: money, land, a boon, and a felled tree.
func _stir() -> void:
	var d = _root.divinity
	d.add_faith(400.0)
	var slots: Array = _root.islands.buyable()
	if not slots.is_empty():
		d.buy_island(slots[0])
	if not d.pending_draft.is_empty():
		d.take_boon(String(d.pending_draft[0]["id"]))
	else:
		d.grant_draft("probe")
		if not d.pending_draft.is_empty():
			d.take_boon(String(d.pending_draft[0]["id"]))
	# Fell something, so the save has to remember an ABSENCE as well as a
	# presence. A tree that comes back is the delta's whole risk.
	for e in _root.builder.placed_props:
		if String(e.get("id", "")).begins_with("Nature/tree"):
			_root.builder.remove_prop(e)
			break
	# Settle before measuring: remove_prop leaves the census and the walk grid
	# stale, and a "before" taken here would blame the save for the difference.
	_root.grid.rebuild_props(_root.builder.live_doc())
	_root.village.census(_root.builder.placed_props)


func _fingerprint() -> Dictionary:
	var d = _root.divinity
	var v = _root.village
	var props := {}
	for e in _root.builder.placed_props:
		if not is_instance_valid(e.get("node")):
			continue
		props["%d,%d" % [int(e.get("col", -1)), int(e.get("row", -1))]] = \
			"%s|%.2f|%.3f" % [String(e["id"]), float(e.get("yaw", 0.0)),
							  float(e.get("scale", 1.0))]
	var folk := []
	var walk_total := 0.0
	for f in _root.folk:
		if not is_instance_valid(f) or f.brain == null:
			continue
		walk_total += float(f.speed)
		folk.append({
			"name": String(f.brain.name),
			"job": String(f.brain.job),
			"seed": int(f.brain.seed_value),
			"tag": String(f.brain.personality.describe()),
			"morality": float(f.brain.morality),
			"hunger": float(f.brain.stats["hunger"]),
			"wired": f.finished.get_connections().size(),
		})
	folk.sort_custom(func(a, b): return int(a["seed"]) < int(b["seed"]))
	return {
		"props": props,
		"faith": float(d.faith),
		"earned": float(d.total_earned),
		"age": int(d.age),
		"cards": d.unlocked_cards.duplicate(),
		"boons": d.boons.held.duplicate(),
		"stores": v.stores.duplicate(),
		"pop_cap": int(v.pop_cap),
		"structures": v.structures.duplicate(),
		"walkable": _root.grid.walkable_cells().size(),
		"folk": folk,
		"walk_total": walk_total,
	}


func _compare(a: Dictionary, b: Dictionary) -> void:
	# The props, both ways: everything that stood must stand, and nothing that
	# was felled may be back.
	var lost := 0
	var risen := 0
	for k in a["props"]:
		if not b["props"].has(k):
			lost += 1
	for k in b["props"]:
		if not a["props"].has(k):
			risen += 1
	print("[SAVE] props %d -> %d  (%d lost, %d resurrected)"
		% [(a["props"] as Dictionary).size(), (b["props"] as Dictionary).size(),
		   lost, risen])
	if lost > 0:
		_faults.append("%d prop(s) did not come back" % lost)
	if risen > 0:
		_faults.append("%d prop(s) came back that were not standing -- a "
			% risen + "felled tree regrew, which means the world was "
			+ "regenerated over the top of the save")

	# FAITH AND TOTAL EARNED ARE COMPARED AGAINST THE FILE, not against the
	# fingerprint taken before the save.
	#
	# The question a save probe asks is "did what I wrote come back", and those
	# two are the only fields the game itself moves during a load: restoring
	# followers re-plans them, and a job that completes on the first frame pays
	# out. Measured at about 0.14 Faith on a 500-Faith village, it does not
	# compound (the second load lands on the same number), and blaming the save
	# layer for it would train us to ignore this assertion.
	var doc: Dictionary = SaveGame.read().get("doc", {})
	var saved: Dictionary = doc.get("divinity", {})
	for key in [["faith", "faith"], ["earned", "total_earned"]]:
		var want: float = float(saved.get(key[1], 0.0))
		var got: float = float(b[key[0]])
		if absf(want - got) > 0.5:
			_faults.append("%s: file says %.3f, village loaded %.3f"
				% [key[0], want, got])
	print("[SAVE] file faith %.3f, loaded %.3f (drift %.3f on load)"
		% [float(saved.get("faith", 0.0)), float(b["faith"]),
		   float(b["faith"]) - float(saved.get("faith", 0.0))])

	for key in ["age", "pop_cap", "walkable"]:
		if typeof(a[key]) == TYPE_FLOAT:
			if not is_equal_approx(float(a[key]), float(b[key])):
				_faults.append("%s: %.3f -> %.3f" % [key, a[key], b[key]])
		elif a[key] != b[key]:
			_faults.append("%s: %s -> %s" % [key, a[key], b[key]])
	for key in ["cards", "boons", "stores", "structures"]:
		if str(a[key]) != str(b[key]):
			_faults.append("%s: %s -> %s" % [key, a[key], b[key]])
	print("[SAVE] faith %.1f, age %d, boons %s, stores %s"
		% [b["faith"], b["age"], b["boons"], b["stores"]])

	# THE PEOPLE. Names and personalities are derived from the stored seed
	# rather than written down, so this is the direct proof that the
	# "derive, don't store" half of the format is sound.
	var fa: Array = a["folk"]
	var fb: Array = b["folk"]
	if fa.size() != fb.size():
		_faults.append("%d followers saved, %d restored" % [fa.size(), fb.size()])
	for i in mini(fa.size(), fb.size()):
		for key in ["name", "job", "seed", "tag"]:
			if fa[i][key] != fb[i][key]:
				_faults.append("follower %d %s: %s -> %s"
					% [i, key, fa[i][key], fb[i][key]])
		if not is_equal_approx(float(fa[i]["morality"]), float(fb[i]["morality"])):
			_faults.append("follower %s morality %.3f -> %.3f"
				% [fa[i]["name"], fa[i]["morality"], fb[i]["morality"]])
		# Wired the same way a founded villager is: a restore path that forgets
		# _wire_follower produces a villager whose every job is silent.
		if int(fb[i]["wired"]) < 1:
			_faults.append("restored follower %s has no `finished` listener -- "
				% fb[i]["name"] + "_wire_follower did not run on the "
				+ "restore path")
	if not fb.is_empty():
		print("[SAVE] folk %d, first %s the %s (%s), wired %d"
			% [fb.size(), fb[0]["name"], fb[0]["job"], fb[0]["tag"],
			   fb[0]["wired"]])


func _report() -> void:
	if _faults.is_empty():
		print("[SAVE] ok")
		return
	print("[SAVE] %d FAILURE(S)" % _faults.size())
	for f in _faults:
		print("  - %s" % f)
