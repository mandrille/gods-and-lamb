extends RefCounted
class_name Prophecy

## Something to be doing for the next five minutes.
##
## The game has ages, and an age is an hour. It has prayers, and a prayer is
## ninety seconds. Between those two there has been nothing at all -- no reason
## to sit down for one session rather than another, and nothing that makes THIS
## twenty minutes different from the last twenty. A player who has nothing to
## aim at plays until they are bored rather than until they are finished, and
## those are very different lengths.
##
## A prophecy is the middle rung. It is spoken by the prophet, which is what
## makes it part of the world rather than a quest log: the village has somebody
## who claims to know what is coming, and either they were right or they were
## not.
##
## FAILING ONE COSTS NOTHING. There is no penalty anywhere in this game for not
## doing something, and this is not the place to start -- a timer you are
## punished for missing turns an idle game into a job. What you get for
## fulfilling one is a gift; what you get for missing one is a prophet who was
## wrong, which the village finds interesting either way.

## Every kind is "reach this number", measured absolutely off state the game
## already keeps. `step` is how far beyond WHERE YOU ARE the target is set when
## it is spoken, so a prophecy is always a genuine advance rather than a thing
## that was already true.
const KINDS := {
	"faithful": {
		"step": 2, "icon": "faith",
		"says": "%s foretells %d who truly believe.",
		"short": "%d/%d believers",
	},
	"souls": {
		"step": 2, "icon": "pop",
		"says": "%s foretells a village of %d.",
		"short": "%d/%d villagers",
	},
	"trees": {
		"step": 6, "icon": "tree",
		"says": "%s foretells %d trees standing.",
		"short": "%d/%d trees",
	},
	"food": {
		"step": 14, "icon": "food",
		"says": "%s foretells storehouses holding %d.",
		"short": "%d/%d food",
	},
	"roofs": {
		"step": 2, "icon": "hammer",
		"says": "%s foretells %d roofs raised.",
		"short": "%d/%d buildings",
	},
}

## Long enough to be a session and short enough to be a session. Below about
## three minutes every kind becomes a scramble; much above six and it stops
## being a thing you are doing and becomes a thing that is happening.
const WINDOW := 300.0

## What being right is worth. Paid as a gift rather than as income: the boon
## draft is the reward the game already uses for a milestone, and a prophecy is
## a milestone the player chose to chase.
const FAITH := 60.0

var kind := ""
var need := 0                      ## the absolute number to reach
var born := 0.0
var spoken := ""                   ## the line the prophet said


func _init(what: String, target: int, now: float) -> void:
	kind = what
	need = target
	born = now


func spec() -> Dictionary:
	return KINDS.get(kind, {})


func icon() -> String:
	return String(spec().get("icon", "faith"))


func left(now: float) -> float:
	return maxf(0.0, WINDOW - (now - born))


func expired(now: float) -> bool:
	return now - born >= WINDOW


## Where the village stands against it right now.
##
## Every branch reads state that already existed for its own reasons -- the
## faith ladder, the census, the store, the prop list. Nothing here is counted
## FOR the prophecy, which is what keeps a prophecy from being able to lie: it
## is measuring the game rather than a number the game keeps for it.
static func read(what: String, root) -> int:
	if root == null:
		return 0
	match what:
		"faithful":
			var n := 0
			for f in root.folk:
				if is_instance_valid(f) and f.brain != null \
						and f.brain.adult and int(f.brain.faith_level) >= 2:
					n += 1
			return n
		"souls":
			return int(root.village.population)
		"trees":
			var n := 0
			for e in root.builder.placed_props:
				if String(e.get("id", "")).begins_with("Nature/tree") \
						and not bool(e.get("gone", false)) \
						and is_instance_valid(e.get("node")):
					n += 1
			return n
		"food":
			return int(root.village.amount("food"))
		"roofs":
			var n := 0
			for e in root.builder.placed_props:
				if String(e.get("id", "")).begins_with("Buildings/") \
						and not bool(e.get("gone", false)) \
						and is_instance_valid(e.get("node")):
					n += 1
			return n
	return 0


func at(root) -> int:
	return read(kind, root)


func done(root) -> bool:
	return at(root) >= need


## The line under the goal, with the count and the clock.
func short(root, now: float) -> String:
	var text := String(spec().get("short", "%d/%d"))
	return "%s  %s" % [text % [mini(at(root), need), need], _clock(now)]


func _clock(now: float) -> String:
	var s := int(left(now))
	return "%d:%02d" % [s / 60, s % 60]
