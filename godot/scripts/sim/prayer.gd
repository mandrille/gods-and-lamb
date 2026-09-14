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
	"healing": {
		"need": "health",
		"tag": DivineAction.LIFE,
		"icon": "heart",
		"says": "%s is ailing.",
		"desperate": "%s is dying.",
	},
	"cheer": {
		"need": "fun",
		"tag": DivineAction.JOY,
		"icon": "confetti",
		"says": "%s is low.",
		"desperate": "%s has lost heart.",
	},
	# SAFETY IS NOT A STAT, and that is what makes it the interesting one. It
	# is asked when something is burning or blowing through the village near
	# enough to matter, and it is answered when that stops -- however it stops.
	# It is the seam that finally puts disasters inside the loop instead of
	# beside it: a fire now makes people ASK, and answering pays like any other
	# prayer rather than only through the calamity's own thanks.
	# THE FEUD. Two villagers standing in the same field wanting opposite things
	# from it, and the god cannot give them both.
	#
	# Everything above comes out of one villager's private state and is answered
	# by the world getting better, however it gets better. These two are the
	# other thing entirely: neither is a need, neither can resolve itself, and
	# each one's answer is the other one's refusal. What decides it is the TAG
	# of whatever the god does next where they can both see it -- grow something
	# and the forager is answered, break stone and the miner is. There is no
	# button for either; it is the acts the player already makes, read for what
	# they say.
	#
	# `feud` is what marks a prayer as one of these, and `met` never returns
	# true for one on the world's account. That is the whole point: nobody is
	# coming to settle this but you.
	"grove": {
		"need": "",
		"feud": true,
		"tag": DivineAction.NATURE,
		"icon": "tree",
		"says": "%s wants the wood left to grow.",
		"desperate": "%s begs you to spare the wood.",
	},
	"quarry": {
		"need": "",
		"feud": true,
		"tag": DivineAction.STONE,
		"icon": "stone",
		"says": "%s wants the ground broken for stone.",
		"desperate": "%s begs you to open the ground.",
	},
	"safety": {
		"need": "",
		"danger": true,
		"tag": DivineAction.PROTECTION,
		"icon": "cross",
		"says": "%s is afraid.",
		"desperate": "%s is in the fire's path.",
	},
	# THE VILLAGE ASKING AS ONE.
	#
	# Everything above is one person's private state: Mara is hungry. These are
	# the other shape the owner asked for -- "we want more trees" rather than
	# "I want an apple" -- and they come out of village-level state, not out of
	# anybody's stat bars. Nobody in particular is asking, so there is no bubble
	# over a head; they live on the prayer rail at the top of the screen.
	#
	# Answered by a matching act ANYWHERE: the whole village hears about it,
	# so planting trees at the far edge answers "more trees" as well as planting
	# them in the square.
	"trees": {
		"need": "",
		"village": true,
		"tag": DivineAction.NATURE,
		"icon": "tree",
		"says": "The village wants more trees.",
		"desperate": "The village has no trees left.",
	},
	"harvest": {
		"need": "",
		"village": true,
		"tag": DivineAction.FOOD,
		"icon": "wheat",
		"says": "The granary is running low.",
		"desperate": "The granary is empty.",
	},
	"rain": {
		"need": "",
		"village": true,
		"tag": DivineAction.WATER,
		"icon": "rain",
		"says": "The fields are drying. They pray for rain.",
		"desperate": "The land is dying of thirst.",
	},
	"joy": {
		"need": "",
		"village": true,
		"tag": DivineAction.JOY,
		"icon": "confetti",
		"says": "The village is weary.",
		"desperate": "The whole village has lost heart.",
	},
}

## How close a calamity has to be before somebody starts asking about it.
const DANGER_NEAR := 9.0

## Above this the need is met and the prayer is over. Deliberately well clear of
## `Brain.URGENT` (0.45): resolving the instant they cross back over the line
## they prayed at would have people praying again four seconds later.
const SAFE := 0.62

## How long one stands before the villager gives up on it. Long enough to walk
## across the island and do something about it; short enough that a screen full
## of old prayers never happens.
const LIFETIME := 90.0
## A village asking stands longer than a person does: it is slower to fix, and
## the player may need to go and find the thing that answers it.
const GLOBAL_LIFETIME := 240.0

var kind := ""
var who = null                     ## the Follower asking
var born := 0.0                    ## village clock
var urgent := false                ## was it DESPERATE when it started
## Set when a divine act of the right kind happened where this villager could
## see it, at any point while the prayer stood. This is what separates "the god
## answered" from "they sorted it out themselves", and it is answered by the
## witness list rather than by guessing from timing.
var touched_by_god := false
## The prayer this one is arguing with, or null. Set in pairs and cleared in
## pairs; a feud with one side left standing is just a prayer nobody can answer.
var rival = null
## Closed because the god took the other side, rather than because it lapsed.
## Kept so the villager can be told, and so the probe can tell the difference
## between a refusal and a shrug.
var denied := false


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
	if village_wide():
		return String(spec().get("desperate" if urgent else "says",
								 "The village prays."))
	var name := "Somebody"
	if who != null and is_instance_valid(who) and who.brain != null:
		name = String(who.brain.name)
	var line := String(spec().get("desperate" if urgent else "says", "%s prays."))
	return line % name


func alive(now: float) -> bool:
	# Nobody in particular is asking, so nobody can die and take it with them.
	if village_wide():
		return now - born < GLOBAL_LIFETIME
	return is_instance_valid(who) and who.brain != null \
		and now - born < LIFETIME


## Is this one about a danger rather than a need?
func danger() -> bool:
	return bool(spec().get("danger", false))


## Is this one half of an argument?
func feud() -> bool:
	return bool(spec().get("feud", false))


## Is this the whole village asking, rather than one person?
func village_wide() -> bool:
	return bool(spec().get("village", false))


## Has the thing they were asking about sorted itself out?
##
## `host` is only needed for the danger kinds, which have to look at the world
## rather than at a stat -- the stat kinds ignore it.
func met(host = null) -> bool:
	# Checked FIRST: a village prayer has no villager, and the line below would
	# otherwise call it settled the instant it was opened.
	if village_wide():
		return village_met(kind, host)
	if not is_instance_valid(who) or who.brain == null:
		return true
	# A FEUD IS NEVER SETTLED BY THE WORLD. There is no stat that gets better
	# and no danger that passes -- if this returned true on its own the whole
	# choice would evaporate while the player was looking elsewhere.
	if feud():
		return false
	if danger():
		return not near_danger(who, host)
	return float(who.brain.stats.get(need(), 1.0)) >= SAFE


## Is anything burning, drying or blowing near this villager right now?
static func near_danger(f, host) -> bool:
	if host == null or f == null or not is_instance_valid(f):
		return false
	for c in (host.calamities as Array):
		if host.grid.world_of(c.cell).distance_to(f.position) <= DANGER_NEAR:
			return true
	return false


## --- the village asking -----------------------------------------------------
##
## Each kind has an opening line and a settling line, and the settling line is
## set well past the opening one -- a village hovering on the edge would
## otherwise ask, stop, and ask again every few seconds.

static func trees_wanted(host) -> int:
	return maxi(4, int(host.folk.size()) + 2)


static func tree_count(host) -> int:
	var n := 0
	for e in host.builder.placed_props:
		if String(e.get("id", "")).begins_with("Nature/tree") \
				and not bool(e.get("gone", false)) \
				and is_instance_valid(e.get("node")):
			n += 1
	return n


static func mean_fun(host) -> float:
	var total := 0.0
	var n := 0
	for f in host.folk:
		if is_instance_valid(f) and f.brain != null:
			total += float(f.brain.stats.get("fun", 1.0))
			n += 1
	return total / float(n) if n > 0 else 1.0


static func drought_running(host) -> bool:
	for c in (host.calamities as Array):
		if String(c.kind) == "drought":
			return true
	return false


## Should the village start asking for this?
static func village_wants(what: String, host) -> bool:
	if host == null:
		return false
	match what:
		"trees":
			return tree_count(host) < trees_wanted(host)
		"harvest":
			return int(host.village.amount("food")) < int(host.folk.size()) * 2
		"rain":
			return drought_running(host)
		"joy":
			return mean_fun(host) < 0.40
	return false


## Has it sorted itself out?
static func village_met(what: String, host) -> bool:
	if host == null:
		return true
	match what:
		"trees":
			return tree_count(host) >= trees_wanted(host) + 2
		"harvest":
			return int(host.village.amount("food")) >= int(host.folk.size()) * 4
		"rain":
			return not drought_running(host)
		"joy":
			return mean_fun(host) >= 0.60
	return true


static func village_desperate(what: String, host) -> bool:
	if host == null:
		return false
	match what:
		"trees":
			return tree_count(host) == 0
		"harvest":
			return int(host.village.amount("food")) == 0
		"rain":
			return drought_running(host)
		"joy":
			return mean_fun(host) < 0.20
	return false
