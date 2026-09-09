extends SceneTree
## Close the tab, come back tomorrow.
##
## The one thing the whole daily loop rests on, and the only piece of it that
## had never been tested end to end. `away_probe` proves the ROLL in isolation
## and `night_probe` opens the morning screen on a synthetic document; neither
## touches the real chain, which is: play a village, save it, close it, and
## open it again a day later with the log, the Faith and the streak all landing
## on the same village you left.
##
## THE CLOCK IS INJECTED BY EDITING THE SAVE, not by adding a seam to the game.
## `Away.roll` measures `now - meta.saved_at`, so a save whose `saved_at` is
## backdated twelve hours IS a village left twelve hours ago, and the code
## under test is the shipping code with nothing stubbed. It also means this
## probe cannot drift away from the real path the way a test hook can.
const ShotWindowRef := preload("res://tools/shot_window.gd")

const HOUR := 3600
const PLAY_FRAMES := 300
const SPEED := 20.0

var _f := 0
var _root: Node = null
var _faults: Array[String] = []
var _stage := 0
var _left := {}                    ## the village as it was closed



func _initialize() -> void:
	ShotWindowRef.park()
	SaveGame.erase()
	_open()


func _open() -> void:
	var scene = (load("res://scenes/vale.tscn") as PackedScene).instantiate()
	scene.load_saves = true
	# No modal: this probe reads the log off the data, and a screen that pauses
	# the tree would stop the frames it needs to get there.
	scene.night_screen = false
	get_root().add_child(scene)
	_root = scene


func _reopen() -> void:
	Engine.time_scale = 0.0
	_f = 0
	_root.queue_free()
	_root = null
	_open()


func _process(_d: float) -> bool:
	_f += 1
	if _stage == 0:
		if _f < 20:
			return false
		if _f == 20:
			Engine.time_scale = SPEED
			return false
		if _f < PLAY_FRAMES:
			return false
		Engine.time_scale = 1.0
		_close_the_tab()
		return false

	if _f < 3:
		return false
	match _stage:
		1:
			_check_return(12 * HOUR, "twelve hours")
			_backdate(26 * HOUR)
			_reopen()
			_stage = 2
		2:
			_check_streak(2, "a night away continues the streak")
			_backdate(5 * 24 * HOUR)
			_reopen()
			_stage = 3
		3:
			_check_streak(1, "five days away ends it")
			_check_no_double_pay()
			SaveGame.erase()
			_report()
			quit(0 if _faults.is_empty() else 1)
			return true
	return false


## Play a while, then save exactly as closing the tab would.
func _close_the_tab() -> void:
	var d = _root.divinity
	d.add_faith(300.0)
	var slots: Array = _root.islands.buyable()
	if not slots.is_empty():
		d.buy_island(slots[0])
	_root.saving.aura = "harvest"
	if not _root.saving.save_now("probe"):
		_faults.append("the tab closed and nothing was written")
	_left = {
		"folk": _root.folk.size(),
		"faith": float(d.faith),
		"earned": float(d.total_earned),
		"props": _root.builder.placed_props.size(),
		"day": _root.daylight.day,
	}
	print("[RETURN] closed with %d folk, %d props, %.0f Faith, day %d"
		% [_left["folk"], _left["props"], _left["faith"], _left["day"]])
	_backdate(12 * HOUR)
	_reopen()
	_stage = 1


## Move the save's clock back, which is the same thing as time passing.
func _backdate(seconds: int) -> void:
	var got := SaveGame.read()
	if String(got.get("how", "")) != SaveGame.LOADED:
		_faults.append("could not reopen the save to backdate it (%s)"
			% got.get("how", ""))
		return
	var doc: Dictionary = got["doc"]
	var meta: Dictionary = doc["meta"]
	meta["saved_at"] = int(meta["saved_at"]) - seconds
	# The high-water mark travels with it, or the ratchet that stops clock
	# tampering would read this as the clock going backwards and pay nothing --
	# which is correct behaviour and would make this probe test the wrong thing.
	meta["max_seen_unix"] = int(meta["saved_at"])
	doc["meta"] = meta
	SaveGame.write(doc)


## The village came back, and it came back with something to read.
func _check_return(seconds: int, label: String) -> void:
	var d = _root.divinity
	var log: Dictionary = _root.saving.away
	var lines: Array = log.get("lines", [])
	var faith: float = float(log.get("faith", 0.0))
	print("[RETURN] after %s: %d line(s), %d Faith, streak %d"
		% [label, lines.size(), int(faith), int(log.get("streak", 0))])
	for line in lines:
		print("[RETURN]   - %s" % line)

	if lines.is_empty():
		_faults.append("came back after %s to an empty log" % label)
	if faith <= 0.0:
		_faults.append("came back after %s and earned nothing" % label)

	# THE VILLAGE IS THE ONE THAT WAS LEFT. An away log that arrives on a fresh
	# vale is worse than no away log: it reads as the game having forgotten.
	if _root.folk.size() != int(_left["folk"]):
		_faults.append("left %d folk, came back to %d"
			% [_left["folk"], _root.folk.size()])
	if _root.builder.placed_props.size() != int(_left["props"]):
		_faults.append("left %d props, came back to %d"
			% [_left["props"], _root.builder.placed_props.size()])
	if _root.daylight.day != int(_left["day"]):
		_faults.append("the day number moved while nobody was playing: %d -> %d"
			% [_left["day"], _root.daylight.day])

	# THE PAYOUT IS CREDITED, not merely computed -- the line that would catch a
	# log which reads beautifully and pays nothing into the bank.
	#
	# Stated as a floor rather than an equality, because the village KEEPS
	# PLAYING once it is back: a returning village that comes back further along
	# than it left can cross an age gate in the frames right after loading and
	# be paid its lump, which has nothing to do with the away log. That is
	# correct behaviour, and asserting equality made this fail by exactly 40 --
	# the First Roof lump -- the moment greening spread in patches and the saved
	# village got that far inside the probe's play window.
	var gained: float = float(d.faith) - float(_left["faith"])
	if gained < faith - 2.0:
		_faults.append("the log promised %d Faith but the balance only rose "
			% int(faith) + "by %.0f (%.0f -> %.0f)"
			% [gained, float(_left["faith"]), float(d.faith)])

	# AND NOTHING APPEARED FROM NOWHERE. Every credit in the game goes through
	# `add_faith`, which raises the lifetime counter by the same amount -- so
	# the two must move together, and a payout applied straight to the balance
	# (or applied twice) breaks this identity without breaking the floor above.
	var earned: float = float(d.total_earned) - float(_left["earned"])
	print("[RETURN] balance +%.0f, lifetime earned +%.0f" % [gained, earned])
	if absf(gained - earned) > 2.0:
		_faults.append("the balance rose %.0f but lifetime earnings rose %.0f "
			% [gained, earned] + "-- Faith was credited outside the ledger")

	# The aura set at nightfall survived the absence and steered the roll.
	if String(_root.saving.aura) != "harvest":
		_faults.append("the aura did not survive the absence: %s"
			% _root.saving.aura)


func _check_streak(want: int, why: String) -> void:
	var got: int = int(_root.saving.streak)
	print("[RETURN] streak %d (%s)" % [got, why])
	if got != want:
		_faults.append("%s: streak %d, wanted %d" % [why, got, want])


## Opening twice in a row pays once.
##
## The obvious exploit and the obvious bug are the same shape: if the payout is
## a function of "time since saved" and opening the game writes a new save,
## then closing and opening repeatedly must not print money.
func _check_no_double_pay() -> void:
	var before := float(_root.divinity.faith)
	_root.saving.save_now("probe")
	var again := Away.roll(SaveGame.read().get("doc", {}),
						   int(Time.get_unix_time_from_system()))
	print("[RETURN] reopening immediately pays %.1f" % float(again["faith"]))
	if float(again["faith"]) > 0.0:
		_faults.append("closing and reopening at once paid %.0f Faith, so the "
			% float(again["faith"]) + "loop can be farmed")
	if absf(float(_root.divinity.faith) - before) > 0.01:
		_faults.append("saving changed the balance")


func _report() -> void:
	Engine.time_scale = 1.0
	if _faults.is_empty():
		print("[RETURN] ok")
		return
	print("[RETURN] %d FAILURE(S)" % _faults.size())
	for f in _faults:
		print("  - %s" % f)
