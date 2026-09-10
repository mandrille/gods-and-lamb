extends SceneTree
## Coming back to a village you have known for a week.
##
## The game has kept a great deal of state and no history at all. Ages arrive
## and their notice scrolls past in four seconds; a prophet is named and the
## line is gone before the player has looked up. Everything they have built is
## legible as a SITUATION and none of it is legible as a story -- which is the
## difference between a save file and a place.
##
## And the return screen has only ever been able to talk about a stretch of time
## nobody watched. It has never once mentioned the present tense, so a player
## could read three lines about last night and close the panel onto a fire.
##
## What is asserted here:
##
##   - the chronicle keeps what matters and refuses what does not
##   - it is capped, and it drops the oldest rather than the newest
##   - it survives a save and a load, without a version bump
##   - "waiting for you" is read LIVE off the world, so it cannot be stale
##   - and the return no longer stacks two full-screen panels on each other
const ShotWindowRef := preload("res://tools/shot_window.gd")
const TestGroundRef := preload("res://tools/test_ground.gd")

var _f := 0
var _root: Node = null
var _faults: Array[String] = []


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
		printerr("[CHRON] FAIL: no scene root")
		quit(1)
		return true
	TestGroundRef.green(_root)

	_check_refuses_junk()
	_check_cap()
	_check_round_trip()
	_check_pending_is_live()
	_check_no_stacked_modals()
	_report()
	quit(0 if _faults.is_empty() else 1)
	return true


## It takes what it is meant to take, and nothing else. A chronicle that logged
## every blessing would be a debug console with a serif font on it.
func _check_refuses_junk() -> void:
	var c := Chronicle.new()
	c.add("age", 1, "The First Roof.")
	c.add("blessing", 1, "You blessed somebody.")
	c.add("age", 1, "")
	if c.entries.size() != 1:
		_faults.append("the chronicle took %d of three entries, one of which "
			% c.entries.size() + "was an unlisted kind and one was empty")
	# And it will not print the same sentence twice in a row.
	c.add("age", 1, "The First Roof.")
	if c.entries.size() != 1:
		_faults.append("the same line went in twice running")
	c.add("age", 2, "The Second Roof.")
	if c.entries.size() != 2:
		_faults.append("a genuinely new line was refused")
	print("[CHRON] %d kinds allowed; junk, blanks and repeats refused"
		% Chronicle.KINDS.size())


## It is capped, and what falls off the end is the OLDEST.
func _check_cap() -> void:
	var c := Chronicle.new()
	for i in Chronicle.CAP + 12:
		c.add("age", 1, "entry %d" % i)
	if c.entries.size() != Chronicle.CAP:
		_faults.append("held %d entries against a cap of %d"
			% [c.entries.size(), Chronicle.CAP])
	if String(c.entries[-1].get("text", "")) != "entry %d" % (Chronicle.CAP + 11):
		_faults.append("the newest entry is not at the end")
	if String(c.entries[0].get("text", "")) == "entry 0":
		_faults.append("the cap dropped the newest rather than the oldest")
	# And `recent` reads backwards, newest first, which is what a return
	# screen wants.
	var last := c.recent(3)
	if last.size() != 3 \
			or String(last[0].get("text", "")) != "entry %d" % (Chronicle.CAP + 11):
		_faults.append("recent() does not read newest first")
	print("[CHRON] capped at %d, oldest dropped, newest first out"
		% Chronicle.CAP)


## It goes into the save and comes back, and an ABSENT chronicle is simply an
## empty one -- which is why no version bump is owed for it.
func _check_round_trip() -> void:
	_root.chronicle.entries.clear()
	_root.chronicle.add("prophet", 3, "Hana began to speak for you.")
	_root.chronicle.add("disaster", 4, "You answered the fire. 2 were saved.")
	var doc: Dictionary = SaveGame.capture(
		_root, int(Time.get_unix_time_from_system()), 1)
	var rows = (doc.get("divinity", {}) as Dictionary).get("chronicle", null)
	if rows == null:
		_faults.append("the save has no chronicle in it at all")
		return
	if (rows as Array).size() != 2:
		_faults.append("saved %d entries of two" % (rows as Array).size())
	var back := Chronicle.new()
	back.from_doc(rows)
	if back.entries.size() != 2 \
			or String(back.entries[1].get("text", "")) \
				!= "You answered the fire. 2 were saved." \
			or int(back.entries[0].get("day", 0)) != 3:
		_faults.append("the chronicle did not survive the round trip: %s"
			% str(back.entries))
	# THE OLD-SAVE CASE, which is the whole argument for not bumping VERSION.
	var older := Chronicle.new()
	older.from_doc(null)
	if not older.entries.is_empty():
		_faults.append("a save with no chronicle produced %d entries"
			% older.entries.size())
	print("[CHRON] %d entries survive a save; a save without one loads empty"
		% back.entries.size())


## WAITING FOR YOU is read off the world every time it is asked, so it can
## never promise a fire that has gone out.
func _check_pending_is_live() -> void:
	_root.calamities.clear()
	_root.prayers.active.clear()
	var quiet := Chronicle.pending(_root)
	for line in quiet:
		if String(line).contains("burning"):
			_faults.append("a quiet village reports something burning")
	var c := Calamity.new("fire", Vector2i(6, 6))
	_root.calamities.append(c)
	var loud := Chronicle.pending(_root)
	var says_fire := false
	for line in loud:
		if String(line).contains("burning"):
			says_fire = true
	if not says_fire:
		_faults.append("a village with a fire in it does not mention the fire")
	_root.calamities.clear()
	for line in Chronicle.pending(_root):
		if String(line).contains("burning"):
			_faults.append("the fire went out and the report still claims it")
	print("[CHRON] quiet: %d line(s); burning: %d line(s); out again: %d"
		% [quiet.size(), loud.size(), Chronicle.pending(_root).size()])


## THE STACK. A five-day streak used to open the boon draft and then open the
## morning screen straight on top of it -- an away log the player could read,
## over three cards they could not reach.
func _check_no_stacked_modals() -> void:
	_root.divinity.pending_draft = []
	_root.draft.close()
	_root._draft_owed = ""
	var line: String = _root._streak_gift(5)
	if line == "":
		_faults.append("a five-day streak was worth nothing")
	if _root.draft.is_open() or not _root.divinity.pending_draft.is_empty():
		_faults.append("the boon draft opened during the return, underneath "
			+ "the away log")
	if _root._draft_owed == "":
		_faults.append("the gift was neither shown nor remembered -- it is "
			+ "simply gone")
	# And it arrives once the player has finished reading.
	_root.pay_owed_draft()
	if _root.divinity.pending_draft.is_empty():
		_faults.append("dismissing the away log did not hand over the gift")
	# ...and only once.
	_root.divinity.pending_draft = []
	_root.pay_owed_draft()
	if not _root.divinity.pending_draft.is_empty():
		_faults.append("the gift was handed over twice")
	print("[CHRON] the gift waits for the log to close, and is dealt once")


func _report() -> void:
	for f in _faults:
		print("  - %s" % f)
	if _faults.is_empty():
		print("[CHRON] the village has a past and a present")
	else:
		print("[CHRON] %d FAILURE(S)" % _faults.size())
