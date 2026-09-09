extends Node
class_name Chorus

## What the village says back, said once.
##
## `Divinity.witnessed` now fires with a full witness list for every divine act,
## and the naive thing to do with it is give each villager their own floating
## number. That is exactly the failure this exists to prevent: six people near a
## miracle producing six "+2 Faith" labels tells the player less than one line
## saying six people saw it, and it does it while covering the village up.
##
## So this is the ONLY subscriber to that signal, and the only thing in the game
## allowed to turn a divine act into a message. It collects results inside a
## short window, merges the ones that belong together, and emits one summary.
##
## THE WINDOW IS SHORTER THAN THE TOUCH COOLDOWN on purpose (0.35 against 0.45).
## Ordinary drumming on the ground therefore flushes once per touch rather than
## piling into a mush; the batching is for things that genuinely happen at once
## -- a wide miracle over eight people, a disaster answered, a tide greening
## under two separate clusters.

const WINDOW := 0.35               ## village-seconds a batch stays open
## Two acts further apart than this are two events, however close in time.
const NEAR := 6.0
## Minimum gap between two sounds from HERE. Dropped, not queued: a late sound
## is worse than no sound, and SFX has only eight voices with no throttle of its
## own -- a ninth call steals a voice mid-note.
const SOUND_GAP := 0.25

var floaters = null
var fxe = null
var sfx = null
var hud = null
var village = null

## The open batch: {kind, at, seen, faith, tiers, verb, opened, crossed}.
var _batch: Dictionary = {}
var _last_sound := -99.0
## The kind of the notice line currently on top of the stack, so a second
## result of the same kind AMENDS it instead of pushing a near-identical line.
var _last_line_kind := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func listen(divinity) -> void:
	if divinity != null:
		divinity.witnessed.connect(take)


## One resolved act. Merges into the open batch or flushes it and opens a new
## one.
func take(r: Dictionary) -> void:
	var kind := String(r.get("kind", ""))
	var at: Vector3 = r.get("at", Vector3.ZERO)
	if not _batch.is_empty():
		if String(_batch["kind"]) == kind \
				and (_batch["at"] as Vector3).distance_to(at) <= NEAR:
			_merge(r)
			return
		_flush()
	_batch = {
		"kind": kind, "at": at, "seen": 0, "faith": 0.0, "tiers": 0,
		"verb": String(r.get("verb", "")), "opened": _now(), "crossed": [],
	}
	_merge(r)


func _merge(r: Dictionary) -> void:
	var seen: int = int(r.get("seen", 0))
	var was: int = int(_batch["seen"])
	# The centroid, weighted by how many each contributed, so a batch that
	# straddles two clusters lands between them rather than on the last one.
	if seen > 0:
		var at: Vector3 = r.get("at", Vector3.ZERO)
		_batch["at"] = ((_batch["at"] as Vector3) * float(was)
						+ at * float(seen)) / float(was + seen)
	_batch["seen"] = was + seen
	_batch["faith"] = float(_batch["faith"]) + float(r.get("faith", 0.0))
	_batch["tiers"] = int(_batch["tiers"]) + int(r.get("tiers", 0))
	if String(r.get("verb", "")) != "":
		_batch["verb"] = String(r.get("verb", ""))


func _process(_delta: float) -> void:
	# The first line, and it matters: this runs every frame for the whole
	# session and almost always has nothing to do.
	if _batch.is_empty():
		return
	if _now() - float(_batch["opened"]) >= WINDOW:
		_flush()


func _now() -> float:
	return float(village.now) if village != null else 0.0


## THE ESCALATION LADDER. What a result earns depends on how much of the
## village it touched, not on what kind of act it was -- an apple that four
## people saw is a bigger event than a miracle nobody was near.
func _flush() -> void:
	if _batch.is_empty():
		return
	var b := _batch
	_batch = {}
	var seen: int = int(b["seen"])
	var faith: float = float(b["faith"])
	var tiers: int = int(b["tiers"])
	var at: Vector3 = b["at"]

	# Tier 0 -- nobody saw it and nothing was earned. The caller's own click
	# feedback already fired; there is nothing to add and adding it anyway is
	# how a game ends up narrating itself.
	if seen <= 0 and faith < 0.5:
		return

	# Tier 1 -- somebody saw it.
	if floaters != null and seen > 0:
		floaters.puff("pop", "%d saw" % seen, at + Vector3(0, 1.1, 0))

	# Tier 2 -- it was worth something.
	if faith >= 6.0 and floaters != null:
		floaters.spawn("faith", "faith", int(round(faith)), at)

	# Tier 3 -- enough of the village to be worth a line.
	if seen >= 4 or tiers >= 1:
		_line("%s %d saw it." % [String(b["verb"]), seen] if seen > 0
			  else String(b["verb"]), String(b["kind"]))

	# Tier 4 -- somebody's belief actually moved. This is the rare one, and the
	# only progress in the game that cannot be lost.
	if tiers >= 1:
		if fxe != null:
			fxe.burst("bless", at + Vector3(0, 0.5, 0),
					  clampf(0.35 + 0.15 * float(seen), 0.35, 1.0))
		_sound("bless")


func _line(text: String, kind: String) -> void:
	if hud == null or text.strip_edges() == "":
		return
	# AMEND rather than push when the last line was the same kind of thing.
	# `HUD._say` de-dupes on the exact string, and an aggregated line carries a
	# count -- so "3 saw it" and "4 saw it" are different strings and three
	# touches would fill the whole three-deep stack with near-identical lines.
	if kind == _last_line_kind and hud.has_method("amend"):
		hud.amend(text, 4.0)
	else:
		hud._say(text, 4.0)
	_last_line_kind = kind


func _sound(name: String) -> void:
	if sfx == null:
		return
	if _now() - _last_sound < SOUND_GAP:
		return
	_last_sound = _now()
	sfx.play(name)
