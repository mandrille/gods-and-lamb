extends RefCounted
class_name Prophet

## The one who tells the others what you meant.
##
## Faith in this game has only ever travelled one way: the god does something, a
## villager is standing close enough to see it, and their belief moves. Nobody
## has ever told anybody anything. A miracle over the north field is worth
## precisely nothing to the four people working the south one, however
## extraordinary it was, and the village has no memory it shares -- only a set
## of private ones that happen to overlap.
##
## A prophet is the seam where that changes. They are not a job the player
## assigns and not a building they raise: whoever believes hardest becomes one,
## and what they do is RETELL. An act they witness reaches people who did not
## see it, at a fraction of its worth, which is exactly what a rumour is.
##
## Two consequences that make it worth having rather than merely flavour:
##
##   1. A crowd is no longer the only way to be seen. Acting where the prophet
##      happens to be standing pays into the whole village.
##   2. The prophet is a person, and people can die, starve or lose faith. What
##      you have built is not a stat -- it is somebody, and they can be lost.
##
## They also NAME you. Reputation has been accruing since stage 4 with nothing
## in the world that ever says it out loud; the prophet is the mouth for it.

## What it takes to be one. Adept, not Devoted: requiring the very top of the
## ladder meant no village had a prophet until it had a shrine and half an hour,
## and the whole point is to have somebody to lose before then.
const NEEDS_LEVEL := 3

## And what it takes to STOP being one, which is lower on purpose. Without a gap
## the title flickers between two villagers a fraction apart, and a prophet who
## changes every few seconds is a label rather than a person.
const KEEPS_LEVEL := 2

## How often the village is reconsidered. Slow: this is a standing, not a
## scoreboard.
const RECONSIDER := 24.0

## THE RUMOUR.
##
## How far word travels, and what it is worth secondhand. The radius is well
## beyond a witness band -- that is the point, it reaches people who could not
## possibly have seen -- and the share is small, because being told about a
## miracle is not the same as watching one.
const RETELL_RADIUS := 16.0
const RETELL_SHARE := 0.22
## Never to somebody who already saw it with their own eyes. Hearing a secondhand
## account of the thing you were standing next to should not pay twice.

var who = null                     ## the Follower, or null
var named := ""                    ## the reputation axis they last spoke of
var _next_look := -1.0


## Reconsider who it is, if it is time. Returns true if the title moved.
func tick(folk: Array, now: float) -> bool:
	if _next_look > 0.0 and now < _next_look:
		return false
	_next_look = now + RECONSIDER
	return choose(folk)


## Who believes hardest, with the incumbent given the benefit of the doubt.
func choose(folk: Array) -> bool:
	var was = who
	if not _still_fit(who):
		who = null
	var best = who
	var best_score: float = _score(who) if who != null else -1.0
	for f in folk:
		if not _eligible(f):
			continue
		var s := _score(f)
		if s > best_score:
			best_score = s
			best = f
	who = best
	if who != was:
		named = ""
	return who != was


func _eligible(f) -> bool:
	return is_instance_valid(f) and f.brain != null and f.brain.adult \
		and int(f.brain.faith_level) >= NEEDS_LEVEL


## An incumbent keeps the title on a lower bar than it took to win it.
func _still_fit(f) -> bool:
	return is_instance_valid(f) and f.brain != null and f.brain.adult \
		and int(f.brain.faith_level) >= KEEPS_LEVEL


func _score(f) -> float:
	if not is_instance_valid(f) or f.brain == null:
		return -1.0
	# Devotion first, and their own bent second -- between two equally devout
	# villagers the one who was always going to believe is the one the others
	# would listen to.
	return float(f.brain.devotion()) \
		+ 0.15 * float(f.brain.personality.devotion)


func has() -> bool:
	return is_instance_valid(who) and who.brain != null


func name_of() -> String:
	return String(who.brain.name) if has() else ""


## Was the prophet among the people who saw this?
static func among(hits: Array, p) -> bool:
	if p == null:
		return false
	for h in hits:
		if h[0] == p:
			return true
	return false


## WHO HEARS ABOUT IT SECONDHAND.
##
## Everybody within earshot of the prophet who was NOT there. Returned rather
## than paid here, so the caller keeps the one place that grants faith and this
## file stays a question rather than a second economy.
func listeners(folk: Array, hits: Array) -> Array:
	if not has():
		return []
	var saw: Dictionary = {}
	for h in hits:
		saw[h[0].get_instance_id()] = true
	var out: Array = []
	for f in folk:
		if not is_instance_valid(f) or f.brain == null or not f.brain.adult:
			continue
		if f == who or saw.has(f.get_instance_id()):
			continue
		if who.position.distance_to(f.position) <= RETELL_RADIUS:
			out.append(f)
	return out


## What they say about you, once, when the village's opinion settles on an axis.
## Returns "" when there is nothing new to say.
func proclaim(title: String, axis: String) -> String:
	if not has() or axis == "" or axis == named:
		return ""
	named = axis
	return "%s says: \"%s is a %s.\"" % [String(who.brain.name), _pronoun(),
										 title]


## The village has no idea what you are, and neither does the game -- there is
## no gender anywhere in it. "The one above" keeps that true and sounds like
## something a person would actually say.
func _pronoun() -> String:
	return "The one above"
