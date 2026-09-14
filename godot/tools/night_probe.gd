extends SceneTree
## Nightfall, the aura, and the morning after.
##
## The day now STOPS the village, which makes this the most dangerous screen in
## the game: a modal that pauses the tree and cannot be dismissed is a hang,
## and a hang on a portal is a player who never comes back. So the dismissal is
## asserted from both buttons, and the pause is asserted to lift.
##
## It also checks the thing the whole night exists for: that the aura the
## player picks is written to the save and read by tomorrow's away roll.
const ShotWindowRef := preload("res://tools/shot_window.gd")

var _f := 0
var _root: Node = null
var _faults: Array[String] = []
var _stage := 0
var _shots := 0
var _skipped_shots := false


func _initialize() -> void:
	ShotWindowRef.park()
	SaveGame.erase()
	var scene = (load("res://scenes/vale.tscn") as PackedScene).instantiate()
	scene.load_saves = true
	get_root().add_child(scene)
	_root = scene


func _process(_d: float) -> bool:
	_f += 1
	if _f < 25:
		return false
	if _f == 25:
		if _root == null or _root.get("day_screen") == null:
			printerr("[NIGHT] FAIL: no day screen")
			quit(1)
			return true
		# A probe does not get the modal by default -- that is what keeps
		# economy_probe from hanging at minute eight. This one wants it.
		_root.night_screen = true
		_root.divinity.add_faith(300.0)
		return false

	match _stage:
		0:
			_open_night()
		1:
			_shoot("night_summary")
		2:
			_pick_aura()
		3:
			_press_keep_watch()
		4:
			_open_morning()
		5:
			_shoot("night_morning")
		6:
			_press_begin()
		7:
			_check_away_reads_aura()
			SaveGame.erase()
			_report()
			quit(0 if _faults.is_empty() else 1)
			return true
	return false


## Nightfall opens the screen and stops the village.
func _open_night() -> void:
	_root.daylight.t = Daylight.DAY_SECONDS - 0.01
	_root.daylight.tick(0.02)
	if not _root.day_screen.is_open():
		_faults.append("the day ended and no summary opened")
	if not paused:
		_faults.append("night did not pause the village -- the summary is a "
			+ "screen you have to read while the world runs on underneath it")
	print("[NIGHT] nightfall: screen open %s, paused %s"
		% [_root.day_screen.is_open(), paused])
	_stage += 1


## The one choice of the night reaches the disk layer.
func _pick_aura() -> void:
	_root.day_screen.aura_chosen.emit("vigil")
	if String(_root.saving.aura) != "vigil":
		_faults.append("choosing an aura did not reach Persistence")
	print("[NIGHT] aura chosen: %s" % _root.saving.aura)
	_stage += 1


## "Keep watch" rolls straight on, and the pause LIFTS. This is the hang test.
func _press_keep_watch() -> void:
	_root.day_screen.resumed.emit()
	if _root.day_screen.is_open():
		_faults.append("keep watch left the summary on screen")
	if paused:
		_faults.append("keep watch left the village paused -- the game is hung")
	# And the day ledger reset, or tomorrow's summary counts today again.
	var again: Dictionary = _root._day_summary(_root.daylight.day)
	if int(again.get("built", -1)) != 0 or int(again.get("newcomers", -1)) != 0:
		_faults.append("the new day started with yesterday's numbers still on "
			+ "the ledger: %s" % again)
	print("[NIGHT] keep watch: open %s, paused %s, fresh ledger %s"
		% [_root.day_screen.is_open(), paused, again])
	_stage += 1


func _open_morning() -> void:
	_root.day_screen.open_morning({
		"day": 4, "faith": 128.0, "streak": 3,
		"gift": "A gift waits for you.",
		"span": "You were gone 14 hours.",
		"lines": ["Bram and Hana brought in what wood they could.",
				  "Wolves came out of the trees. The flock is smaller.",
				  "Odo kept the shrine lit for you."],
	})
	paused = true
	if not _root.day_screen.is_open():
		_faults.append("the morning screen did not open")
	_stage += 1


func _press_begin() -> void:
	_root.day_screen.rested.emit()
	if _root.day_screen.is_open():
		_faults.append("beginning the day left the morning screen up")
	if paused:
		_faults.append("beginning the day left the village paused")
	print("[NIGHT] morning dismissed: paused %s" % paused)
	_stage += 1


## The aura is not decoration: tomorrow's log has to read it.
##
## Vigil suppresses wolves, so a village that would otherwise be raided must
## come back with no wolf line at all. Rolled over many seeds, because one roll
## proves nothing about a weighted draw.
func _check_away_reads_aura() -> void:
	var save := {
		"v": SaveGame.VERSION,
		"meta": {"saved_at": 1788561234, "max_seen_unix": 1788561234,
				 "away_seed": 4242, "aura": "vigil"},
		"world": {"props": []},
		"village": {"stores": {"food": 20, "wood": 5, "stone": 5}},
		"divinity": {"income_per_s": 0.8, "total_earned": 800.0, "age": 2},
		"folk": [{"seed": 1}, {"seed": 2}, {"seed": 3}],
		"beasts": [{"kind": "Animals/sheep"}, {"kind": "Animals/sheep"}],
	}
	var wolf_line := ""
	for e in Away.EVENTS:
		if String(e["id"]) == "wolf":
			wolf_line = String(e["line"])
	var with_vigil := 0
	var without := 0
	for k in 200:
		save["meta"]["away_seed"] = k * 7919 + 5
		save["meta"]["aura"] = "vigil"
		if _has(Away.roll(save, 1788561234 + 20000)["lines"], wolf_line):
			with_vigil += 1
		save["meta"]["aura"] = ""
		if _has(Away.roll(save, 1788561234 + 20000)["lines"], wolf_line):
			without += 1
	print("[NIGHT] wolf lines over 200 nights: %d under Vigil, %d without"
		% [with_vigil, without])
	if with_vigil != 0:
		_faults.append("Vigil was chosen and wolves still took the flock "
			+ "%d times" % with_vigil)
	if without == 0:
		_faults.append("wolves never appeared even WITHOUT Vigil, so the "
			+ "comparison proves nothing")


func _has(lines: Array, line: String) -> bool:
	for l in lines:
		if String(l) == line:
			return true
	return false


func _shoot(name: String) -> void:
	# One frame later than the state change, or it photographs the frame before.
	if _f % 4 != 0:
		return
	if not ShotWindowRef.can_shoot():
		_skipped_shots = true
		_stage += 1
		return
	ShotWindow.shoot("res://shots/%s.png" % name)
	print("[NIGHT] wrote res://shots/%s.png" % name)
	_shots += 1
	_stage += 1


func _report() -> void:
	paused = false
	if _skipped_shots:
		print("[NIGHT] no display: %d picture(s) skipped, checks still ran"
			% (2 - _shots))
	elif _shots < 2:
		_faults.append("only %d of 2 pictures were taken" % _shots)
	if _faults.is_empty():
		print("[NIGHT] ok")
		return
	print("[NIGHT] %d FAILURE(S)" % _faults.size())
	for f in _faults:
		print("  - %s" % f)
