extends SceneTree
## A tab closed mid-write is normal. Prove it costs at most one autosave.
##
## Every case here is a file the game will genuinely meet on a portal: a
## truncated write, a browser that cleared storage, a stale cached build
## meeting a newer save. None of them may push a fatal, and none of them may
## ever be shown to the player as an error -- a corrupt file is either a
## recovered village or a first run.

const PATH := "user://probe_save.json"
const BACKUP := "user://probe_save.bak.json"

var _faults: Array[String] = []


func _initialize() -> void:
	_clean()
	_case("missing file", "", SaveGame.FRESH)
	_case("empty file", "", SaveGame.FRESH, true)
	_case("half an object", "{", SaveGame.FRESH, true)
	_case("a JSON array", "[1, 2, 3]", SaveGame.FRESH, true)
	_case("valid JSON, not a save", '{"hello": "world"}', SaveGame.FRESH, true)
	_case("no version key", '{"village": {}, "folk": []}', SaveGame.FRESH, true)

	var good := _good()
	var text := JSON.stringify(good)
	# 90% is the row that matters: it proves JSON.parse_string REJECTS a
	# partial object rather than us assuming it does.
	for cut in [25, 50, 90]:
		_case("truncated at %d%%" % cut,
			  text.substr(0, int(text.length() * cut / 100.0)),
			  SaveGame.FRESH, true)

	_future(good)
	_older(good)
	_recovery(good)
	_round_trip(good)
	_clean()
	_report()
	quit(0 if _faults.is_empty() else 1)


func _case(label: String, contents: String, want: String, write := false) -> void:
	_clean()
	if write:
		var f := FileAccess.open(PATH, FileAccess.WRITE)
		f.store_string(contents)
		f.close()
	var got := SaveGame.read(PATH, BACKUP)
	var how := String(got.get("how", ""))
	print("[CORRUPT] %-24s -> %s" % [label, how])
	if how != want:
		_faults.append("%s gave %s, wanted %s" % [label, how, want])
	if not (got.get("doc", {}) as Dictionary).is_empty() and want == SaveGame.FRESH:
		_faults.append("%s returned a document it should have refused" % label)


## A newer save must be REFUSED and LEFT ALONE. A portal serving a stale
## cached build must never eat the village a newer build wrote.
func _future(good: Dictionary) -> void:
	_clean()
	var doc := good.duplicate(true)
	doc["v"] = SaveGame.VERSION + 5
	SaveGame.write(doc, PATH, BACKUP)
	var got := SaveGame.read(PATH, BACKUP)
	print("[CORRUPT] %-24s -> %s" % ["newer version", got["how"]])
	if String(got["how"]) != SaveGame.REFUSED:
		_faults.append("a newer save was not refused")
	if not FileAccess.file_exists(PATH):
		_faults.append("a newer save was DELETED rather than left alone")


## An older save with no migrator is archived, never dropped on the floor.
func _older(good: Dictionary) -> void:
	_clean()
	var doc := good.duplicate(true)
	doc["v"] = 0
	SaveGame.write(doc, PATH, BACKUP)
	var got := SaveGame.read(PATH, BACKUP)
	print("[CORRUPT] %-24s -> %s" % ["older version", got["how"]])
	if String(got["how"]) != SaveGame.ARCHIVED:
		_faults.append("an older save was not archived")
	if not FileAccess.file_exists("user://save_v0.json.old"):
		_faults.append("the archive file was not written")
	DirAccess.remove_absolute("user://save_v0.json.old")


## The whole point of writing through a backup.
func _recovery(good: Dictionary) -> void:
	_clean()
	SaveGame.write(good, PATH, BACKUP)          # first write: no backup yet
	var second := good.duplicate(true)
	second["divinity"]["faith"] = 999.0
	SaveGame.write(second, PATH, BACKUP)        # rotates the first into .bak
	if not FileAccess.file_exists(BACKUP):
		_faults.append("the second write did not leave a backup")
	# Now kill the live file the way a closed tab does, mid-write.
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string('{"v": 1, "villa')
	f.close()
	var got := SaveGame.read(PATH, BACKUP)
	print("[CORRUPT] %-24s -> %s" % ["truncated, backup good", got["how"]])
	if String(got["how"]) != SaveGame.RECOVERED:
		_faults.append("a truncated file with a good backup did not recover")
	else:
		var faith: float = float(got["doc"]["divinity"]["faith"])
		if not is_equal_approx(faith, float(good["divinity"]["faith"])):
			_faults.append("recovery returned the wrong village: faith %.1f"
				% faith)


func _round_trip(good: Dictionary) -> void:
	_clean()
	SaveGame.write(good, PATH, BACKUP)
	var got := SaveGame.read(PATH, BACKUP)
	if String(got["how"]) != SaveGame.LOADED:
		_faults.append("a healthy save did not load")
		return
	# Compared field by field with a cast, not by str(). JSON has ONE number
	# type, so every int comes back a float and a literal comparison fails on
	# a file that is perfectly correct. The lesson is real even though the
	# assertion was wrong: anything reading a saved number without a cast gets
	# a float, which is how boon ranks -- used to index ["I","II","III"] --
	# arrived as 1.0 and were caught by save_probe.
	var a: Dictionary = good["folk"][0]
	var b: Dictionary = got["doc"]["folk"][0]
	for key in ["seed", "c", "r"]:
		if int(a[key]) != int(b[key]):
			_faults.append("folk %s: %s -> %s" % [key, a[key], b[key]])
	if String(a["job"]) != String(b["job"]):
		_faults.append("folk job: %s -> %s" % [a["job"], b["job"]])
	print("[CORRUPT] %-24s -> %s" % ["healthy save", got["how"]])


func _good() -> Dictionary:
	return {
		"v": SaveGame.VERSION,
		"meta": {"saved_at": 1788561234, "max_seen_unix": 1788561234,
				 "away_seed": 7},
		"world": {"seed": 20260901, "unlocked": ["1,1"], "props": []},
		"village": {"stores": {"food": 3, "wood": 3, "stone": 3}, "now": 12.0},
		"divinity": {"faith": 25.0, "income_per_s": 0.4, "age": 0,
					 "boons": {"held": {}}},
		"root": {"next_seed": 3, "milestones_paid": []},
		"folk": [{"seed": 1, "job": "villager", "c": 4, "r": 4}],
		"beasts": [],
	}


## Leave nothing behind: a save left by a probe would silently become the
## village a human opens.
func _clean() -> void:
	for p in [PATH, BACKUP, "user://save_v0.json.old"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _report() -> void:
	if _faults.is_empty():
		print("[CORRUPT] ok")
		return
	print("[CORRUPT] %d FAILURE(S)" % _faults.size())
	for f in _faults:
		print("  - %s" % f)
