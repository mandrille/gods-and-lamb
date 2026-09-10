extends RefCounted
class_name Calamity

## Fire, wind and drought: the things that take the world back.
##
## Until now nothing could undo what the village built. Wolves ate a sheep and
## frightened people, and that was the whole of the pressure -- so a player who
## had greened a hillside could stop looking at it forever. A world you can
## only add to is a world that stops asking for you.
##
## Each of these EATS what the player made, slowly enough to be answered and
## fast enough to matter, and each has a specific answer that is already in the
## deck. That pairing is the point: a disaster with no counter is a tax, and a
## counter with no disaster is a card nobody plays.
##
##   fire     spreads tree to tree and leaves scorched dirt   <- Rain
##   drought  turns grass back to dirt, from the edges in     <- Rain, Grove
##   tornado  walks a line and flattens whatever it crosses   <- Calm
##
## Solving one pays FAITH FROM EVERY VILLAGER, which is the other half of the
## design: the village should thank you, and a crisis should leave the place
## more devout than it found it.

## NOT SAVED, and that is a decision rather than an omission. A calamity is a
## sixty-second thing that wants answering while you are watching; restoring one
## on load would mean opening the game to a fire already half through the trees,
## with no chance to have caught it early. Closing the tab puts it out. The
## ground it already ate stays eaten, which is the part that should persist.
const KINDS := ["fire", "drought", "tornado"]

## What answers what. A miracle whose id is in here, cast within reach, ends
## the calamity outright rather than merely slowing it.
const ANSWERS := {
	"fire": ["rain"],
	"drought": ["rain", "grove"],
	"tornado": ["calm"],
}

const LOOK := {
	"fire": {"fx": "punish", "sfx": "wrath", "tint": "ember",
			 "notice": "Fire in the trees."},
	"drought": {"fx": "chips", "sfx": "deny", "tint": "sand",
				"notice": "The ground is going dry."},
	"tornado": {"fx": "wrath", "sfx": "wrath", "tint": "slate",
				"notice": "A wind is walking the valley."},
}

## Seconds between one bite and the next. Slow: a calamity is a thing to
## notice and answer, not a reflex test.
const BITE := 3.0
## How long one runs if nobody answers it. It stops on its own rather than
## eating a village whole -- being unable to look away is not the same as
## being unable to lose.
const LIFETIME := 60.0
## Faith per villager for solving one, scaled by how much was left to save.
const THANKS := 6.0

var kind := ""
var cell := Vector2i.ZERO
var age := 0.0
var bites := 0
var eaten := 0                     ## what it has taken so far
var dir := Vector2i(1, 0)          ## tornadoes walk

## WHO THIS EVER PUT IN DANGER, by instance id.
##
## Counted while it runs rather than when it ends, because when it ends nobody
## is in danger any more -- that is the whole point -- and a rescue nobody can
## count is a rescue the player never hears about. This is the number behind
## "3 saved", and it is a set rather than a tally so somebody who walks in and
## out of the treeline four times is still one person.
var endangered: Dictionary = {}


## Anybody near enough right now joins the list and stays on it.
func watch(folk: Array, world: Callable) -> void:
	var here: Vector3 = world.call(cell)
	for f in folk:
		if not is_instance_valid(f) or f.brain == null:
			continue
		if here.distance_to(f.position) <= Prayer.DANGER_NEAR:
			endangered[f.get_instance_id()] = true


## Of the people it endangered, how many are still standing.
func saved(folk: Array) -> int:
	var n := 0
	for f in folk:
		if is_instance_valid(f) and endangered.has(f.get_instance_id()):
			n += 1
	return n


func _init(what: String, at: Vector2i, heading := Vector2i(1, 0)) -> void:
	kind = what
	cell = at
	dir = heading


func look() -> Dictionary:
	return LOOK.get(kind, LOOK["fire"])


func answered_by(card: String) -> bool:
	return card in (ANSWERS.get(kind, []) as Array)


func expired() -> bool:
	return age >= LIFETIME


## How much thanks solving this is worth per villager. A fire caught early is
## worth more than one caught when there is nothing left to burn -- otherwise
## the best play is to let it run and put it out at the end.
func thanks() -> float:
	return THANKS * clampf(1.0 - float(eaten) * 0.08, 0.25, 1.0)
