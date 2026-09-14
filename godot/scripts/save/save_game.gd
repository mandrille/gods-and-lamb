extends RefCounted
class_name SaveGame

## Write the ledger, reconstruct the world.
##
## Everything derivable from a seed is regenerated on load; only what the
## player's choices actually changed is written to disk. That is not a size
## optimisation -- it is the only split that keeps a save readable after the
## content changes, and it falls out of two facts that are already true here:
## `Islands.build_doc()` emits an identical document for a given seed, and
## `Follower.think()` derives a villager's NAME and their entire PERSONALITY
## from one integer. So a follower costs one seed plus what happened to them.
##
## The persistence idiom -- FileAccess, JSON.stringify, JSON.parse_string,
## user:// (which maps to IndexedDB on web) -- is copied from settings.gd
## deliberately. Two ways to write a file in one project is one too many.
##
## Unlike settings.gd this DOES carry a version int. The failure modes are not
## the same shape: a settings key that falls back costs a slider position, and
## a save key that falls back costs a village.

## 2: the plots shrank from 34 tiles to 20 on a 5x5 grid. Every saved cell and
## slot coordinate changed MEANING -- which is exactly the rule for when a bump
## is owed, as opposed to adding an optional key -- so a version-1 village is
## archived rather than loaded with its huts standing in the river.
const VERSION := 2
const PATH := "user://save.json"
const BACKUP := "user://save.bak.json"

## Outcomes of read(), named so a probe can assert on them rather than
## inferring from side effects.
const LOADED := "loaded"           ## the save opened
const RECOVERED := "recovered"     ## the main file was bad, the backup was not
const FRESH := "fresh"             ## nothing usable; start a new vale
const ARCHIVED := "archived"       ## an old version, moved aside
const REFUSED := "refused"         ## a NEWER version; left untouched


## --- disk -------------------------------------------------------------------

## Read the save, falling back through backup to fresh.
##
## Returns {"doc": Dictionary, "how": String}. Never throws, never shows the
## player an error: a corrupt file is either a recovered village or a first
## run. A tab killed mid-write is not an exceptional case on the web, it is
## Tuesday.
static func read(path := PATH, backup := BACKUP) -> Dictionary:
	var main := _read_one(path)
	if not main.is_empty():
		var verdict := _judge(main, path)
		if verdict != "":
			return {"doc": {}, "how": verdict}
		return {"doc": main, "how": LOADED}
	var spare := _read_one(backup)
	if not spare.is_empty() and _judge(spare, backup) == "":
		return {"doc": spare, "how": RECOVERED}
	return {"doc": {}, "how": FRESH}


## Version policy. Returns "" to accept, or the outcome that rejected it.
static func _judge(doc: Dictionary, path: String) -> String:
	var v: int = int(doc.get("v", -1))
	if v == VERSION:
		return ""
	if v > VERSION:
		# A portal serving a stale cached build must never eat a newer save.
		push_warning("SaveGame: save is version %d, this build reads %d -- "
			% [v, VERSION] + "left untouched")
		return REFUSED
	# Older, and no migrator yet: move it aside rather than delete it. The
	# archive path ships from day one so a future version has somewhere to
	# migrate FROM.
	var old := "user://save_v%d.json.old" % v
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(path, old)
	print("[SAVE] archived a version %d save to %s" % [v, old])
	return ARCHIVED


static func _read_one(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	# Truncated JSON parses to null; an array parses fine and is not a save.
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parsed
	# A shape guard as well as a type guard -- a partial object cannot hold all
	# three of these.
	if not (d.has("v") and d.has("village") and d.has("folk")):
		return {}
	return d


## Rotate, then write. A tab killed during the write leaves save.json
## truncated and save.bak.json complete, which is the whole point.
static func write(doc: Dictionary, path := PATH, backup := BACKUP) -> bool:
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(backup)
		DirAccess.rename_absolute(path, backup)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("SaveGame: could not open %s for writing" % path)
		return false
	# Compact, not indented: this is written every twenty seconds and each web
	# write is an IndexedDB transaction.
	f.store_string(JSON.stringify(doc))
	f.close()
	return true


static func erase(path := PATH, backup := BACKUP) -> void:
	for p in [path, backup]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


## --- capture ----------------------------------------------------------------

static func capture(root, now_unix: int, away_seed: int) -> Dictionary:
	var d = root.divinity
	var v = root.village
	return {
		"v": VERSION,
		"meta": {
			"saved_at": now_unix,
			"max_seen_unix": now_unix,
			"away_seed": away_seed,
			"session_s": float(v.now),
		},
		"world": {
			"seed": root.islands._seed,
			"unlocked": _keys(root.islands.unlocked),
			"rng_state": int(root._rng.state),
			"props": root.builder.live_doc().get("props", []),
		},
		"village": {
			"stores": v.stores.duplicate(),
			"now": float(v.now),
			"total_gathered": v.total_gathered,
			"total_eaten": v.total_eaten,
			"richness": _floats(v._richness),
		},
		"daylight": root.daylight.to_doc() if root.daylight != null else {},
		"divinity": _capture_divinity(d),
		"root": {
			"next_seed": root._next_seed,
			"milestones_paid": _keys_int(root._milestones_paid),
		},
		"folk": _capture_folk(root),
		"beasts": _capture_beasts(root),
	}


static func _capture_divinity(d) -> Dictionary:
	var hand: Array = []
	for c in d.hand:
		hand.append(String(c.get("id", "")))
	return {
		"faith": float(d.faith),
		"total_earned": float(d.total_earned),
		# Stamped rather than recomputed, so the away roll is a function of one
		# float and needs to know nothing about Brain, mood or personality.
		"income_per_s": float(d.income_per_s()),
		"age": int(d.age),
		"god_level": int(d.god_level),
		"last_age_at": float(d._last_age_at),
		"tutorial_gift": bool(d._tutorial_gift_given),
		"unlocked_cards": d.unlocked_cards.duplicate(),
		"hand": hand,
		"drafts_taken": int(d.drafts_taken),
		"witnessed_total": int(d.witnessed_total),
		# Optional, like the faith ladder: an old save has no opinion of you
		# yet, which is exactly what a fresh Reputation says too.
		"reputation": d.reputation.to_doc(),
		# THE HISTORY, and like the reputation above it is optional: an old
		# save has no chronicle, which is exactly what a village that has done
		# nothing memorable yet also has. No version bump is owed for a key
		# whose absent value equals today's behaviour.
		"chronicle": (d.host.chronicle.to_doc()
					  if d.host != null and d.host.chronicle != null else []),
		"boons": {"held": d.boons.held.duplicate(),
				  "rank3_open": bool(d.boons.rank3_open)},
	}


static func _capture_folk(root) -> Array:
	var out: Array = []
	for f in root.folk:
		if not is_instance_valid(f) or f.brain == null:
			continue
		var b = f.brain
		var cell: Vector2i = root.grid.cell_of(f.position)
		out.append({
			"seed": int(b.seed_value),
			"job": String(b.job),
			"c": cell.x, "r": cell.y,
			"age": float(b.age),
			"adult": bool(b.adult),
			# The BASE roll, never f.speed. Storing the boosted value and
			# boosting it again on load compounds on every single load, which
			# is the classic idle-game save bug.
			"walk": float(f._base_walk),
			"morality": float(b.morality),
			# THE FAITH LADDER, which was not saved at all.
			#
			# Every reload reset the whole village to Atheist, and because
			# `devotion()` is (faith_level + progress) / 4 and feeds
			# `income_per_s`, a save/load silently deleted the player's entire
			# accumulated passive economy along with it.
			#
			# Optional keys, and NO version bump: every field in
			# `_restore_followers` is read with a default, so an old save
			# loaded by this build yields 0/0 -- Atheist -- which is precisely
			# what the build did yesterday. It is never worse on an old file,
			# and a bump would be worse on a new one: a portal serving a stale
			# cached build would hit REFUSED and leave the player looking at a
			# village they cannot open.
			"fxp": float(b.faith_xp),
			"ftr": int(b.faith_level),
			"stats": b.stats.duplicate(),
			"favour": _deviations(b.favour),
			"mem": _capture_memories(b),
			"log": b.thought_log.slice(maxi(0, b.thought_log.size() - 8)),
		})
	return out


## Only what is not 1.0. Brain seeds every action to 1.0, so a full dump is
## thirty numbers of noise per villager -- the same "deviations only"
## discipline settings.gd already enforces for the debug sliders.
static func _deviations(favour: Dictionary) -> Dictionary:
	var out := {}
	for k in favour:
		if absf(float(favour[k]) - 1.0) > 0.001:
			out[String(k)] = float(favour[k])
	return out


static func _capture_memories(b) -> Array:
	var out: Array = []
	if b.memories == null:
		return out
	for e in b.memories.entries:
		# Already on their way out via Memories.tick; not worth the bytes.
		if float(e.get("heat", 0.0)) < 0.05:
			continue
		out.append({"k": String(e.get("kind", "")), "t": String(e.get("text", "")),
					"o": String(e.get("other", "")),
					"v": float(e.get("valence", 0.0)),
					"h": float(e.get("heat", 0.0)),
					# The residue, or a memory of being saved comes back as an
					# ordinary one and fades away over the next minute.
					"kp": float(e.get("keep", 0.0)),
					"a": float(e.get("age", 0.0))})
	return out


static func _capture_beasts(root) -> Array:
	var out: Array = []
	for b in root.beasts:
		if not is_instance_valid(b):
			continue
		var cell: Vector2i = root.grid.cell_of(b.position)
		out.append({"kind": String(b.kind), "c": cell.x, "r": cell.y})
	return out


## --- apply ------------------------------------------------------------------

## The world document a loaded save wants: the pristine generated archipelago
## for the unlocked plots, with the props that were actually standing.
static func doc_for(islands, world: Dictionary) -> Dictionary:
	var base: Dictionary = islands.build_doc()
	var props: Array = world.get("props", [])
	if props.is_empty():
		return base
	base["props"] = props
	return base


## Push the saved god state back. Called BEFORE add_child, so nothing has
## ticked with the wrong numbers.
static func apply_divinity(d, doc: Dictionary) -> void:
	d.faith = float(doc.get("faith", d.faith))
	d.total_earned = float(doc.get("total_earned", 0.0))
	d.age = int(doc.get("age", 0))
	d.god_level = maxi(1, int(doc.get("god_level", 1)))
	d._last_age_at = float(doc.get("last_age_at", -999.0))
	d._tutorial_gift_given = bool(doc.get("tutorial_gift", false))
	d.drafts_taken = int(doc.get("drafts_taken", 0))
	d.witnessed_total = int(doc.get("witnessed_total", 0))
	d.reputation.from_doc(doc.get("reputation", {}))
	var cards: Array = doc.get("unlocked_cards", [])
	if not cards.is_empty():
		d.unlocked_cards.clear()
		for c in cards:
			d.unlocked_cards.append(String(c))
	# Cards by id: the DECK is a const, so storing the dictionaries would
	# duplicate it and pin the save to today's card text. It is an ARRAY of
	# card dictionaries, not a map -- calling .get(id, {}) on it threw, and
	# because the throw aborted this whole function every line BELOW it was
	# silently skipped: the hand, the boons and rank III all came back empty
	# while the save file held them correctly. Hence save_probe.
	d.hand.clear()
	for cid in doc.get("hand", []):
		var spec := card_by_id(d, String(cid))
		if not spec.is_empty():
			d.hand.append(spec)
	var boons: Dictionary = doc.get("boons", {})
	# Ranks are INTS. JSON has one number type, so they come back as floats,
	# and a float rank blows up the very next thing that indexes with it:
	# ["I", "II", "III"][r - 1].
	d.boons.held.clear()
	for id in (boons.get("held", {}) as Dictionary):
		d.boons.held[String(id)] = int(boons["held"][id])
	d.boons.rank3_open = bool(boons.get("rank3_open", false))
	if int(doc.get("age", 0)) >= 2:
		d.draw_seconds = 8.0


static func card_by_id(d, cid: String) -> Dictionary:
	for c in d.DECK:
		if String(c.get("id", "")) == cid:
			return c
	return {}


## --- little helpers ---------------------------------------------------------
##
## Vector2i keys do not survive JSON, so they travel as "x,y" strings.

static func _keys(d: Dictionary) -> Array:
	var out: Array = []
	for k in d:
		out.append("%d,%d" % [k.x, k.y])
	return out


static func _keys_int(d: Dictionary) -> Array:
	var out: Array = []
	for k in d:
		out.append(int(k))
	return out


static func _floats(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out["%d,%d" % [k.x, k.y]] = float(d[k])
	return out


static func cell_key(s: String) -> Vector2i:
	var parts := s.split(",")
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))
