extends RefCounted
class_name Analytics

## What the game would tell a portal, if a portal were listening.
##
## This game is aimed at CrazyGames and Playgama, and both of them want the same
## handful of things: did the player get past the opening, how long did they
## stay, what did they do, and where did they stop. None of that has ever been
## counted, so every tuning decision in this project has come from a probe
## measuring an ideal player rather than from a real one.
##
## NO NETWORK, and that is the point rather than a limitation. A portal SDK is
## twenty lines of JavaScriptBridge and cannot be written until there is a
## portal build to write it against; what CANNOT be added later is the
## discipline of having named the events, decided what a funnel step means, and
## kept the counting honest. So this is the shape, complete and testable, with
## `sink` as the one seam an SDK attaches to.
##
## PRIVACY BY CONSTRUCTION. Everything here is a count or a duration. There is
## nowhere to put a villager's name, a save file, or anything at all about the
## person playing -- not because a rule says so but because `note` takes a
## string key and a number and has no third argument.

## THE FUNNEL, in order. These are the questions a portal build has to be able
## to answer, and the order matters: a funnel is only a funnel if each step is
## strictly further in than the last.
##
## Chosen so that every one of them is a thing the player DID rather than a
## thing that happened to them -- "survived a fire" is luck, "answered a prayer"
## is a decision, and only the second tells you the game taught them anything.
const FUNNEL := [
	"first_touch",       ## they clicked the ground at all
	"first_building",    ## the village did something with it
	"first_bless",       ## they found the second verb
	"first_prayer_seen", ## somebody asked them for something
	"first_prayer_answered",
	"first_boon",
	"age_1",             ## The First Roof
	"first_disaster_answered",
	"first_prophet",
	"first_prophecy_kept",
]

## Everything else worth counting. Kept as a fixed list for the same reason the
## chronicle keeps one: a metric nobody named is a metric nobody reads, and an
## open dictionary quietly becomes a dumping ground.
const COUNTERS := [
	"touches", "blessings", "miracles", "prayers_opened",
	"prayers_answered", "prayers_lapsed", "feuds_settled",
	"disasters_started", "disasters_answered", "disasters_lost",
	"prophecies_spoken", "prophecies_kept", "prophecies_broken",
	"boons_taken", "births", "deaths", "newcomers", "saves", "wipes",
]

var counts: Dictionary = {}        ## name -> int
var firsts: Dictionary = {}        ## funnel step -> seconds into the session
var started := 0.0                 ## village clock at session start
var now := 0.0                     ## village clock, pushed in by the host

## WHERE IT WOULD GO. Assign a Callable taking (event: String, value: float,
## payload: Dictionary) and every note is forwarded as it happens. Left null in
## every build that is not talking to a portal, which is all of them today.
var sink: Callable = Callable()


func begin(at: float) -> void:
	started = at
	now = at


## Count something. Unknown names are DROPPED rather than created, so a typo is
## a metric that reads zero forever instead of a second metric nobody looks at.
func note(what: String, n := 1) -> void:
	if not (what in COUNTERS):
		return
	counts[what] = int(counts.get(what, 0)) + n
	_push(what, float(n), {})


## Mark a funnel step, the first time it happens and never again. The value is
## SECONDS INTO THE SESSION, which is the number that actually answers "where do
## they stop" -- a step reached at forty seconds and a step reached at eleven
## minutes are different games.
func reach(step: String) -> void:
	if not (step in FUNNEL) or firsts.has(step):
		return
	var t: float = maxf(0.0, now - started)
	firsts[step] = t
	_push("funnel:%s" % step, t, {"step": step})


func _push(event: String, value: float, payload: Dictionary) -> void:
	if sink.is_valid():
		sink.call(event, value, payload)


func count(what: String) -> int:
	return int(counts.get(what, 0))


func reached(step: String) -> bool:
	return firsts.has(step)


## How far in they got: the index of the last funnel step reached, plus one.
## Deliberately the LAST reached rather than the count of steps reached, because
## a player who somehow skipped a step has still got that far.
func depth() -> int:
	var d := 0
	for i in FUNNEL.size():
		if firsts.has(FUNNEL[i]):
			d = i + 1
	return d


## The whole thing, for the debug panel and for whatever ships it.
func to_doc() -> Dictionary:
	return {
		"session": maxf(0.0, now - started),
		"depth": depth(),
		"funnel": firsts.duplicate(),
		"counts": counts.duplicate(),
	}


## One line per funnel step, for reading rather than for parsing.
func lines() -> Array:
	var out: Array = []
	for step in FUNNEL:
		if firsts.has(step):
			out.append("%s  %.0fs" % [step, float(firsts[step])])
		else:
			out.append("%s  --" % step)
	return out
