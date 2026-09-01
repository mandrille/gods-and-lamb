extends RefCounted
class_name Village

## What the settlement owns, collectively.
##
## Small on purpose. This is a shared ledger, not an economy simulation: it
## exists so that harvesting has a POINT and eating has a COST, which is what
## turns "play the chop animation" into work. Without it, blessing a woodcutter
## produces more chopping and nothing else, and the player has no way to tell
## whether their influence mattered.
##
## Stores are integers. Fractional wheat is a rounding argument nobody needs.

signal changed()
signal depleted(res: String)

## What a full store looks like, per resident. Capacity scales with population
## so a bigger village is not permanently starving on the same granary.
const PER_HEAD := {"food": 6, "wood": 8, "stone": 5}
## What two people wash up on a bare plot with. Deliberately thin: the first
## hut has to be EARNED, because watching them earn it is the whole opening.
const START := {"food": 3, "wood": 0, "stone": 0}

## How many of each structure the settlement wants, given its size. This is
## what stops a village raising a third well and what makes the first hut
## urgent -- `shortage` is about resources, this is about buildings.
const WANTED := {
	"Buildings/hut": {"per_head": 0.5, "min": 1},
	"Buildings/well": {"per_head": 0.0, "min": 1},
	"Buildings/market_stall": {"per_head": 0.0, "min": 1},
	"Buildings/shrine": {"per_head": 0.0, "min": 1},
	"Nature/crop_row": {"per_head": 3.0, "min": 4},
}

var stores: Dictionary = {}
var population := 0
var pop_cap := 5

## Cumulative, for the chronicle and for scoring how the village is doing.
var total_gathered := 0
var total_eaten := 0

## asset id -> how many are standing. Kept as a count the builder refreshes
## rather than recomputed by walking the prop list on every decision: every
## villager asks this several times a second.
var structures: Dictionary = {}

## Building work already under way: asset id -> Array of expiry timestamps.
##
## Without this, every villager who checks "do we want a well?" before the
## first one finishes gets the same answer, and a village of fifty raises four
## wells it wanted one of. Reservations EXPIRE rather than being released,
## because the alternative is tracking which villager holds which claim and
## leaking one every time somebody is despawned mid-job.
var _claims: Dictionary = {}
const CLAIM_SECONDS := 25.0


func _init() -> void:
	stores = START.duplicate()


func capacity(res: String) -> int:
	return int(PER_HEAD.get(res, 5)) * maxi(1, population)


## 0 = plenty, 1 = empty. What `Brain._demand` reads to decide whether the job
## is worth doing, so followers drift off harvesting once the granary is full.
func shortage(res: String) -> float:
	var cap := capacity(res)
	if cap <= 0:
		return 1.0
	return clampf(1.0 - float(amount(res)) / float(cap), 0.0, 1.0)


func amount(res: String) -> int:
	return int(stores.get(res, 0))


func can_take(cost: Dictionary) -> bool:
	for res in cost:
		if amount(String(res)) < int(cost[res]):
			return false
	return true


## All or nothing. A partial take would let two followers each half-eat the
## last loaf and both come away fed.
func take(cost: Dictionary) -> bool:
	if not can_take(cost):
		return false
	for res in cost:
		var r := String(res)
		stores[r] = amount(r) - int(cost[res])
		total_eaten += int(cost[res])
		if amount(r) == 0:
			depleted.emit(r)
	changed.emit()
	return true


func give(gain: Dictionary) -> void:
	for res in gain:
		var r := String(res)
		# Capped. An uncapped store means the village hoards forever and every
		# shortage reads as zero, which silently disables the whole demand
		# system that decides what work gets done.
		stores[r] = mini(amount(r) + int(gain[res]), capacity(r))
		total_gathered += int(gain[res])
	changed.emit()


## Refresh the structure census from what is actually standing. Called by the
## host whenever props change -- built, destroyed, or a new plot bought.
func census(placed_props: Array) -> void:
	structures.clear()
	for e in placed_props:
		var aid := String(e.get("id", ""))
		structures[aid] = int(structures.get(aid, 0)) + 1


func count_of(aid: String) -> int:
	return int(structures.get(aid, 0))


## Somebody has started building one of these.
func claim(aid: String) -> void:
	if not _claims.has(aid):
		_claims[aid] = []
	(_claims[aid] as Array).append(Time.get_ticks_msec() * 0.001
								   + CLAIM_SECONDS)


## How many are under way right now, dropping any that have gone stale.
func claimed(aid: String) -> int:
	if not _claims.has(aid):
		return 0
	var now := Time.get_ticks_msec() * 0.001
	var live: Array = []
	for t in _claims[aid]:
		if float(t) > now:
			live.append(t)
	_claims[aid] = live
	return live.size()


## 0 = we have enough, 1 = we have none and want one. Drives whether building
## is worth a villager's time at all.
func wants(aid: String) -> float:
	if not WANTED.has(aid):
		return 0.0
	var spec: Dictionary = WANTED[aid]
	var target: float = maxf(float(spec["min"]),
							 float(spec["per_head"]) * float(maxi(1, population)))
	# Standing ones PLUS the ones being built right now.
	var have := float(count_of(aid) + claimed(aid))
	if have >= target:
		return 0.0
	return clampf((target - have) / target, 0.0, 1.0)


func has_room() -> bool:
	return population < pop_cap


func summary() -> String:
	return "food %d/%d  wood %d/%d  stone %d/%d  pop %d/%d" % [
		amount("food"), capacity("food"),
		amount("wood"), capacity("wood"),
		amount("stone"), capacity("stone"), population, pop_cap]
