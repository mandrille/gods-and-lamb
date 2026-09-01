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
const PER_HEAD := {"food": 6, "wood": 5}
const START := {"food": 8, "wood": 4}

var stores: Dictionary = {}
var population := 0
var pop_cap := 5

## Cumulative, for the chronicle and for scoring how the village is doing.
var total_gathered := 0
var total_eaten := 0


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


func has_room() -> bool:
	return population < pop_cap


func summary() -> String:
	return "food %d/%d  wood %d/%d  pop %d/%d" % [
		amount("food"), capacity("food"),
		amount("wood"), capacity("wood"), population, pop_cap]
