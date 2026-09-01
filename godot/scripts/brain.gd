extends RefCounted
class_name Brain

## What a follower wants, and where that sends it.
##
## The seed of the simulation, deliberately small. It is NOT the god-game's
## follower AI -- there are no traits, no relationships, no moral dilemmas and
## no Faith. It is the one piece those all need underneath them: a follower
## that decides where to go for a REASON, instead of being handed a fixed loop.
##
## The shape is: needs rise over time, the most urgent need names a KIND of
## place, the grid finds the nearest one, and arriving there relieves it. That
## much is already enough to make a village look like it is doing something,
## and it is the hook the real design plugs into -- a Greedy follower steals
## from the apple store because `hunger` sent it to the store and a trait
## decided what it did on arrival.
##
## Everything here is per-follower state. Two followers with the same needs
## must not share an object, or the whole village walks in lockstep.

enum Need { HUNGER, REST, WANDER }

## Rise per second. Slow: a follower that eats every ten seconds reads as
## frantic, and this village is meant to be calm.
const RATES := {Need.HUNGER: 0.028, Need.REST: 0.018}
const SATISFY := 0.85          ## how much arriving takes off the need
const URGENT := 0.55           ## below this, nothing is worth crossing the map
const NEAR_CHOICES := 5        ## how many of the nearest sources to choose among

## Where each need sends a follower. Kept as asset ids because that is what the
## grid indexes; a "kitchen" abstraction on top of two entries would be a layer
## that explains nothing.
const SOURCES := {
	Need.HUNGER: ["Nature/tree", "Nature/crop_row"],
	Need.REST: ["Buildings/hut", "Buildings/cottage"],
}

var hunger := 0.0
var rest := 0.0
var current := Need.WANDER
var rng := RandomNumberGenerator.new()


func _init(seed_value: int) -> void:
	# Seeded per follower and NOT from the clock: the village has to come up
	# the same way twice or a rendering change cannot be told from a different
	# set of errands.
	rng.seed = seed_value
	hunger = rng.randf() * 0.5
	rest = rng.randf() * 0.5


func tick(delta: float) -> void:
	hunger = minf(1.0, hunger + RATES[Need.HUNGER] * delta)
	rest = minf(1.0, rest + RATES[Need.REST] * delta)


func level_of(n: int) -> float:
	match n:
		Need.HUNGER: return hunger
		Need.REST: return rest
		_: return 0.0


## The need that will drive the NEXT errand, or WANDER if nothing is pressing.
func choose() -> int:
	var worst := Need.WANDER
	var worst_level := URGENT
	for n in [Need.HUNGER, Need.REST]:
		var lv := level_of(n)
		if lv > worst_level:
			worst = n
			worst_level = lv
	current = worst
	return worst


## Pick a destination cell for the current need. Returns (-1, -1) if there is
## nowhere to go, which the caller must treat as "wander instead" rather than
## as an error -- the far bank of the river is genuinely unreachable from some
## places, and a follower that insists will stand still forever.
func destination(grid: WalkGrid, from: Vector2i) -> Vector2i:
	var need := choose()
	if need == Need.WANDER:
		return grid.random_cell(rng)

	# Gather the candidates, then pick among the NEAREST FEW rather than the
	# single nearest. Strictly-nearest is a rule, and a village where everyone
	# obeys the same rule from the same starting positions walks in formation:
	# the two followers who share a doorstep pick the same tree every time,
	# forever. Choosing from a short list of near ones keeps the behaviour
	# legible -- nobody crosses the map past three closer trees -- while making
	# the choice that follower's own.
	var ranked: Array = []
	for aid in SOURCES[need]:
		for c in grid.cells_of(aid):
			var cell: Vector2i = c
			ranked.append([absi(cell.x - from.x) + absi(cell.y - from.y), cell])
	if ranked.is_empty():
		return grid.random_cell(rng)
	ranked.sort_custom(func(a, b): return a[0] < b[0])

	for i in mini(NEAR_CHOICES, ranked.size()):
		# Sample without replacement from the head of the list, so a shortage of
		# standing room next to the closest tree falls through to the next one
		# instead of dumping the follower somewhere random across the map.
		var pick: int = rng.randi_range(0, mini(NEAR_CHOICES, ranked.size()) - 1)
		var target: Vector2i = ranked[pick][1]
		var stand: Vector2i = grid.beside(target, rng)
		if stand.x >= 0:
			return stand
		ranked.remove_at(pick)
		if ranked.is_empty():
			break
	return grid.random_cell(rng)


## Arriving relieves whatever sent us. Wandering relieves nothing, which is
## what stops a follower from wandering its hunger away.
func arrived() -> void:
	match current:
		Need.HUNGER: hunger = maxf(0.0, hunger - SATISFY)
		Need.REST: rest = maxf(0.0, rest - SATISFY)


func describe() -> String:
	# Annotated: indexing an untyped Array yields Variant, and `:=` on it is a
	# parse error rather than something that shows up at runtime.
	var label: String = ["hungry", "tired", "wandering"][current]
	return "%s (h %.2f r %.2f)" % [label, hunger, rest]
