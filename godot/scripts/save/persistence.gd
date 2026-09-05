extends Node
class_name Persistence

## The disk, and when to touch it.
##
## NOT an autoload, deliberately. This project has no [autoload] section and
## assembles everything at runtime in ValeRoot._ready(), and every probe in
## tools/ instantiates vale.tscn itself -- so a save autoload would fire during
## economy_probe's ten simulated minutes at 20x and overwrite the player's real
## village with a robot's. That is not hypothetical; it is what "assembled at
## runtime, headless-testable" costs you if you break it.
##
## The guard is a CHECK rather than a rule to remember. A probe runs with
## `--script tools/x.gd`, so the SceneTree ITSELF carries that script; the game
## boots `run/main_scene` and its SceneTree has none. One comparison separates
## them, in both directions, and it cannot be forgotten by a future probe
## author because nobody has to remember to opt out.

## Real seconds between autosaves, and the floor between any two writes.
##
## Measured in WALL time, not game time, and that is the exception that proves
## village.gd's rule about Time.get_ticks_msec. Game state is measured in game
## seconds; an I/O budget is measured in real ones -- economy_probe runs at 20x
## and would otherwise autosave twenty times as often, and on web every write
## is an IndexedDB transaction.
const AUTOSAVE_SECS := 20.0
const MIN_GAP_SECS := 5.0

var host = null                         ## ValeRoot
var armed := false                      ## may this touch the disk at all
var aura := ""                          ## set at nightfall; steers the away roll
var away: Dictionary = {}               ## the roll from this launch, if any
## How many CALENDAR days in a row this village has been opened. The actual
## daily hook: an absence pays a capped amount, but showing up pays a streak.
var streak := 1

var _high_water := 0                    ## the latest unix time ever seen
var _last_write_ms := 0
var _next_ms := 0
var _rng := RandomNumberGenerator.new()


## True for the game, false for every `--script` probe. See the class comment.
static func is_real_game(tree: SceneTree) -> bool:
	return tree != null and tree.get_script() == null


## Read at the very start of ValeRoot._ready, before anything is built.
## `force` is for save_probe, which is the one probe that wants the disk.
static func probe_read(tree: SceneTree, force := false) -> Dictionary:
	if not force and not is_real_game(tree):
		return {"doc": {}, "how": SaveGame.FRESH}
	return SaveGame.read()


func _ready() -> void:
	armed = armed or is_real_game(get_tree())
	_rng.randomize()
	_next_ms = Time.get_ticks_msec() + int(AUTOSAVE_SECS * 1000.0)


func _process(_delta: float) -> void:
	if armed and Time.get_ticks_msec() >= _next_ms:
		save_now("autosave")


## Every lifecycle point a browser tab actually gives us.
##
## The periodic autosave is the MECHANISM; these are opportunistic top-ups.
## Anything that assumes a clean shutdown is wrong on a portal --
## WM_CLOSE_REQUEST does not fire when a tab is closed, so it is wired for the
## desktop build and never relied on.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			save_now("blur")            # the workhorse on web
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_GO_BACK_REQUEST:
			save_now("close")


## Remember the newest wall-clock time this save has ever been opened at.
##
## It never goes down, which is what makes setting the clock forward,
## collecting, and setting it back pay nothing on the way home. One integer.
func note_time(unix: int) -> void:
	_high_water = maxi(_high_water, unix)


func save_now(why := "") -> bool:
	if not armed or host == null:
		return false
	var now_ms := Time.get_ticks_msec()
	if why == "autosave" and now_ms - _last_write_ms < int(MIN_GAP_SECS * 1000.0):
		return false
	var now_unix := int(Time.get_unix_time_from_system())
	note_time(now_unix)
	_last_write_ms = now_ms
	_next_ms = now_ms + int(AUTOSAVE_SECS * 1000.0)
	var doc := SaveGame.capture(host, now_unix, _rng.randi())
	doc["meta"]["max_seen_unix"] = maxi(now_unix, _high_water)
	if aura != "":
		doc["meta"]["aura"] = aura
	doc["meta"]["streak"] = streak
	return SaveGame.write(doc)


## What the last session left behind, and what it is worth. Called once, after
## the village has been restored -- an away log that promised something the
## restored world does not show would be worse than no log at all.
func open_log(doc: Dictionary, now_unix: int) -> Dictionary:
	if doc.is_empty():
		return {}
	var meta: Dictionary = doc.get("meta", {})
	note_time(int(meta.get("max_seen_unix", 0)))
	aura = String(meta.get("aura", ""))
	streak = _streak_for(meta, now_unix)
	away = Away.roll(doc, now_unix)
	away["streak"] = streak
	note_time(now_unix)
	return away


## A new CALENDAR day continues the streak; a whole day missed ends it.
##
## Calendar days rather than 24-hour blocks, because "come back tomorrow" is
## what a person means by tomorrow -- a player who plays at 9pm and again at
## 8am the next morning has come back two days running, and telling them
## otherwise because eleven hours is not twenty-four would be pedantry the
## streak exists to avoid.
func _streak_for(meta: Dictionary, now_unix: int) -> int:
	var was := int(meta.get("streak", 1))
	var then := int(meta.get("saved_at", now_unix))
	if now_unix < then:
		return was                       # a clock correction is not a lapse
	var a := Time.get_datetime_dict_from_unix_time(then)
	var b := Time.get_datetime_dict_from_unix_time(now_unix)
	if a["year"] == b["year"] and a["month"] == b["month"] and a["day"] == b["day"]:
		return was                       # same day, same streak
	# One night away continues it; two ends it. 48 hours is the honest cutoff
	# for "yesterday" without needing a calendar library.
	if now_unix - then <= 48 * 3600:
		return was + 1
	return 1
