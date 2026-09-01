extends RefCounted
class_name Memories

## What a follower remembers, and how much they still care.
##
## A memory is an EVENT plus a feeling about it, and the feeling fades while
## the event does not. That split is the whole design: "Hana shoved me" stays
## true forever, but after long enough it stops changing how this follower acts
## around Hana. Storing only a running opinion score would lose the event and
## leave the panel with nothing to show; storing only events would leave the
## simulation with nothing to read.
##
## Bounded on purpose. A follower keeps the STRONGEST memories, not the most
## recent ones, so being struck by lightning is not forgotten because six
## people said hello afterwards. Unbounded lists in an idle game that runs for
## hours are a leak with extra steps.

const CAP := 14
const FADE_PER_SEC := 0.011      ## a strong memory matters for a few minutes

## kind: what happened. Used for text, for grouping, and by the divine layer
## to decide whether a miracle is remembered as a gift or a judgement.
const KIND_SOCIAL := "social"
const KIND_BLESSING := "blessing"
const KIND_PUNISHMENT := "punishment"
const KIND_MIRACLE := "miracle"
const KIND_WORK := "work"
const KIND_LOSS := "loss"

var entries: Array[Dictionary] = []


## Record something. `valence` is signed: positive was good for this follower.
##
## `other` is the NAME of another follower or "" -- a name rather than a
## reference on purpose, because a memory has to survive the thing it is about.
## Holding a node here would either keep a freed follower alive or leave a
## dangling reference the panel would crash on.
func add(kind: String, text: String, valence: float, other := "",
		 weight := 1.0) -> void:
	entries.append({
		"kind": kind, "text": text, "other": other,
		"valence": clampf(valence, -1.0, 1.0),
		"heat": clampf(absf(valence) * weight, 0.0, 1.0),
		"age": 0.0,
	})
	_trim()


func tick(delta: float) -> void:
	for e in entries:
		e["age"] = float(e["age"]) + delta
		e["heat"] = maxf(0.0, float(e["heat"]) - FADE_PER_SEC * delta)
	# Cold memories are dropped rather than kept at zero. A list that only
	# grows is the same leak whether or not the entries still do anything.
	var kept: Array[Dictionary] = []
	for e in entries:
		if float(e["heat"]) > 0.02:
			kept.append(e)
	entries = kept


## How this follower feels about someone, right now: the sum of what is still
## warm between them. Zero means neutral OR forgotten, and those are the same
## thing as far as behaviour is concerned.
func opinion_of(other: String) -> float:
	var total := 0.0
	for e in entries:
		if String(e["other"]) == other:
			total += float(e["valence"]) * float(e["heat"])
	return clampf(total, -1.0, 1.0)


## Everyone this follower currently has feelings about, strongest first.
func bonds() -> Array[Dictionary]:
	var by_name := {}
	for e in entries:
		var who := String(e["other"])
		if who == "":
			continue
		by_name[who] = float(by_name.get(who, 0.0)) \
			+ float(e["valence"]) * float(e["heat"])
	var out: Array[Dictionary] = []
	for who in by_name:
		out.append({"who": who, "score": clampf(by_name[who], -1.0, 1.0)})
	out.sort_custom(func(a, b): return absf(a["score"]) > absf(b["score"]))
	return out


## The memory still weighing on them most, or {} if nothing is.
func strongest() -> Dictionary:
	var best := {}
	var best_heat := 0.0
	for e in entries:
		if float(e["heat"]) > best_heat:
			best_heat = float(e["heat"])
			best = e
	return best


func recent(limit := 5) -> Array[Dictionary]:
	var sorted := entries.duplicate()
	sorted.sort_custom(func(a, b): return float(a["age"]) < float(b["age"]))
	return sorted.slice(0, limit)


## Running tally of divine treatment, which the miracle layer reads to decide
## whether this follower trusts the god. Kept as a derived query rather than a
## stored counter so it fades with the memories it is made of -- a god who was
## cruel an hour ago and generous since should not be feared forever.
func divine_standing() -> float:
	var total := 0.0
	for e in entries:
		var k := String(e["kind"])
		if k == KIND_BLESSING or k == KIND_PUNISHMENT or k == KIND_MIRACLE:
			total += float(e["valence"]) * float(e["heat"])
	return clampf(total, -1.0, 1.0)


func _trim() -> void:
	if entries.size() <= CAP:
		return
	# Drop the COLDEST, not the oldest. An old wound that still aches is more
	# a part of this person than a warm greeting from a minute ago.
	entries.sort_custom(func(a, b): return float(a["heat"]) > float(b["heat"]))
	entries = entries.slice(0, CAP)
