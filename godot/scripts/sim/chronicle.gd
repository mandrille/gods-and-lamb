extends RefCounted
class_name Chronicle

## The history of this village, in its own words.
##
## The game has kept a great deal of state and no history at all. Ages arrive
## and their notice scrolls past in four seconds; a prophet is named and the
## line is gone before the player has looked up; the first roof goes up once,
## ever, and there is nowhere to go and see that it happened. Everything the
## player has built is legible as a SITUATION and none of it is legible as a
## story, which is the difference between a save file and a village you have
## known for a week.
##
## So this is a short, capped, dated list of the things that were worth
## remembering, and it survives between sessions. It is the one thing in the
## game whose entire purpose is to be read rather than acted on.
##
## WHAT GOES IN IS DELIBERATELY NARROW. A chronicle that logged every blessing
## would be a debug console with a serif font on it -- the test is whether a
## person coming back in three days would want to be reminded, which rules out
## anything that happens more than a handful of times an hour.

## How much is kept. Twenty entries is roughly a long session and a bit, which
## is the horizon a returning player actually cares about; beyond that it is
## archaeology.
const CAP := 20

## What may be written. Nothing else can call `add` -- a kind not in here is a
## programming mistake rather than a new feature, and being strict about it is
## what stops this quietly becoming a log of everything.
const KINDS := ["age", "prophet", "prophecy", "disaster", "feud", "first",
				"loss"]

var entries: Array = []            ## [{day, kind, text}], oldest first


func add(kind: String, day: int, text: String) -> void:
	if not (kind in KINDS) or text == "":
		return
	# THE SAME THING TWICE IN A ROW IS ONE THING. Two fires answered in the same
	# minute genuinely are two entries; the same sentence repeated is a bug
	# somewhere upstream, and the chronicle should not amplify it.
	if not entries.is_empty() and String(entries[-1].get("text", "")) == text:
		return
	entries.append({"day": day, "kind": kind, "text": text})
	if entries.size() > CAP:
		entries = entries.slice(entries.size() - CAP, entries.size())


## The most recent few, newest first, for the return screen.
func recent(n: int) -> Array:
	var out: Array = []
	var i: int = entries.size() - 1
	while i >= 0 and out.size() < n:
		out.append(entries[i])
		i -= 1
	return out


func to_doc() -> Array:
	var out: Array = []
	for e in entries:
		out.append({"d": int(e.get("day", 1)), "k": String(e.get("kind", "")),
					"t": String(e.get("text", ""))})
	return out


func from_doc(rows) -> void:
	entries.clear()
	if not (rows is Array):
		return
	for r in (rows as Array):
		if not (r is Dictionary):
			continue
		entries.append({"day": int(r.get("d", 1)), "kind": String(r.get("k", "")),
						"text": String(r.get("t", ""))})
	if entries.size() > CAP:
		entries = entries.slice(entries.size() - CAP, entries.size())


## WHAT IS WAITING FOR YOU RIGHT NOW.
##
## Different from the chronicle and deliberately sitting next to it: the log
## says what happened, and this says what has not finished happening. A player
## coming back to a fire wants to know before they have finished reading about
## last night, and the away log has never once mentioned the present tense.
##
## Read live off the world rather than stored, so it can never be stale.
static func pending(root) -> Array:
	var out: Array = []
	if root == null:
		return out
	var fires: int = (root.calamities as Array).size()
	if fires > 0:
		var kinds: Array = []
		for c in root.calamities:
			kinds.append(String(c.kind))
		out.append("Something is still burning: %s." % ", ".join(kinds))
	if root.prayers != null:
		var asking := 0
		var feuding := 0
		for p in (root.prayers.active as Array):
			if p.feud():
				feuding += 1
			else:
				asking += 1
		if asking == 1:
			out.append("Somebody is praying.")
		elif asking > 1:
			out.append("%d are praying." % asking)
		if feuding >= 2:
			out.append("Two of them are arguing, and want opposite things.")
	if root.divinity != null and root.divinity.prophet != null \
			and root.divinity.prophet.has():
		out.append("%s speaks for you." % root.divinity.prophet.name_of())
	return out
