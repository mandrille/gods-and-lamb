extends RefCounted
class_name Prayer

## Somebody asking you for something.
##
## The village has always had needs and has never had a way to SAY so. That is
## the missing half of the loop: the player could act on the world and be paid
## for it, and the world could never ask them for anything, so nothing the
## villagers felt ever reached the person playing.
##
## A prayer is not a quest and it is deliberately not a task list. It comes out
## of simulation state -- a hunger bar under a threshold -- and it goes away the
## moment that state is fine again, WHETHER OR NOT THE GOD DID ANYTHING. That is
## the whole design: the village must be able to solve its own problems, or the
## game is whack-a-mole with a deity skin on it. What the god gets for helping
## is that it is faster, larger and remembered.

## What each kind is about, and what would make it stop.
##
## `need` is the stat that has to recover; `tag` is the kind of divine act that
## COUNTS as having answered it, checked against the witness list rather than
## against which button was pressed -- so any future miracle that feeds somebody
## answers a food prayer without this table learning about it.
const KINDS := {
	"food": {
		"need": "hunger",
		"tag": DivineAction.FOOD,
		"icon": "food",
		"says": "%s is hungry.",
		"desperate": "%s is starving.",
	},
}

## Above this the need is met and the prayer is over. Deliberately well clear of
## `Brain.URGENT` (0.45): resolving the instant they cross back over the line
## they prayed at would have people praying again four seconds later.
const SAFE := 0.62

## How long one stands before the villager gives up on it. Long enough to walk
## across the island and do something about it; short enough that a screen full
## of old prayers never happens.
const LIFETIME := 90.0

var kind := ""
var who = null                     ## the Follower asking
var born := 0.0                    ## village clock
var urgent := false                ## was it DESPERATE when it started
## Set when a divine act of the right kind happened where this villager could
## see it, at any point while the prayer stood. This is what separates "the god
## answered" from "they sorted it out themselves", and it is answered by the
## witness list rather than by guessing from timing.
var touched_by_god := false


func _init(what: String, asker, now: float, desperate := false) -> void:
	kind = what
	who = asker
	born = now
	urgent = desperate


func spec() -> Dictionary:
	return KINDS.get(kind, {})


func need() -> String:
	return String(spec().get("need", ""))


func icon() -> String:
	return String(spec().get("icon", "faith"))


## What they would say, if they said it out loud.
func says() -> String:
	var name := "Somebody"
	if who != null and is_instance_valid(who) and who.brain != null:
		name = String(who.brain.name)
	var line := String(spec().get("desperate" if urgent else "says", "%s prays."))
	return line % name


func alive(now: float) -> bool:
	return is_instance_valid(who) and who.brain != null \
		and now - born < LIFETIME


## Has the thing they were asking about sorted itself out?
func met() -> bool:
	if not is_instance_valid(who) or who.brain == null:
		return true
	return float(who.brain.stats.get(need(), 1.0)) >= SAFE
