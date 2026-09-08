extends RefCounted
class_name Brain

## What a follower wants, what they do about it, and what they become.
##
## Stats are stored as SATISFACTION, not as need: 1.0 is a full green bar and
## 0.0 is an empty red one. That is the opposite of the usual "hunger rises"
## convention and it is chosen deliberately, because the panel shows these
## numbers directly. Storing need and inverting at the UI means every new
## readout is one missed inversion away from telling the player that a starving
## follower is doing fine, and that bug is invisible in code review.
##
## The god cannot give orders (design rule: no build button, no harvest
## button). What the god has instead is FAVOUR -- blessing a follower who just
## chopped a tree makes chopping more attractive to them, punishing makes it
## less. So `favour` is the entire channel through which divine opinion becomes
## village behaviour, and every work action is chosen through it.

## Satisfaction drain per second at personality 1.0. Tuned for an idle game:
## a full bar should last minutes, not seconds, or the village reads as frantic
## and the player never sees anyone finish anything.
const DRAIN := {
	"hunger": 0.0115, "energy": 0.0080, "social": 0.0100,
	"health": 0.0016, "hygiene": 0.0062, "fun": 0.0072,
}

## FAITH IS NOT IN HERE ANY MORE. It was the seventh need, a tank that leaked
## and had to be topped up; it is now a LEVEL that only climbs (see faith_xp).
## Blessing is permanent progress rather than maintenance, which is the whole
## difference between tending a village and watering it.
## What one blessing is worth. Twelve to leave Atheist, so four blessings is a
## first tier and the player sees the mechanic work inside a minute.
const BLESS_FAITH := 3.0

const STAT_ORDER := ["hunger", "energy", "social", "health", "hygiene", "fun"]

const STAT_LABEL := {
	"hunger": "Hunger", "energy": "Energy", "social": "Social",
	"health": "Health", "hygiene": "Hygiene", "fun": "Fun",
}

## Below this a need is worth crossing the island for.
const URGENT := 0.45
## Below this the follower will drop work entirely.
const DESPERATE := 0.20

## The catalogue.
##
## `need` names the stat an action refills; work actions have none and are
## chosen by favour instead. `sources` are asset ids the follower must stand
## beside. `anywhere` means it can be done on open ground when no source
## exists -- eating comes out of the shared store and needs no building, and a
## villager with no hut sleeps on the grass rather than never sleeping.
## `builds` places a structure on completion, which is the only way any
## building enters this world.
const ACTIONS := {
	"eat":     {"need": "hunger", "sources": [], "anywhere": true,
				"seconds": 2.5, "anim": "pickup", "refill": 0.85,
				"takes": {"food": 1}, "morality": 0.0, "verb": "eating"},
	"rest":    {"need": "energy", "sources": ["Buildings/hut", "Buildings/hut_b",
											  "Buildings/cottage",
											  "Buildings/cottage_b"],
				"anywhere": true,
				"seconds": 5.0, "anim": "idle", "refill": 0.90,
				"morality": 0.0, "verb": "resting"},
	"wash":    {"need": "hygiene", "sources": ["Buildings/well"],
				"anywhere": true,
				"seconds": 3.0, "anim": "pickup", "refill": 0.85,
				"morality": 0.0, "verb": "washing"},
	# Prayer answers no NEED any more -- faith stopped being a tank that leaks.
	# It is chosen for its own sake at a shrine and pays the villager faith,
	# which is the one thing in the village that can raise itself without the
	# player. A shrine is therefore a slow, automatic congregation.
	"pray":    {"need": "", "sources": ["Buildings/shrine"],
				"seconds": 4.0, "anim": "idle", "refill": 0.0,
				"faith": 3.0, "morality": 0.03, "verb": "praying"},
	"play":    {"need": "fun", "sources": ["Buildings/market_stall"],
				"anywhere": true,
				"seconds": 3.5, "anim": "idle", "refill": 0.70,
				"morality": 0.0, "verb": "idling"},

	# Apple heaps are what the Feast miracle leaves behind, and they are
	# CONSUMED when foraged -- see ValeRoot._wire_follower. That closes the
	# loop: the god drops food, a villager walks over and picks it up, and the
	# food is gone. A heap that stays forever is a permanent free lunch.
	"forage":  {"need": "", "sources": ["Nature/apples", "Nature/bush"],
				"seconds": 3.0, "anim": "pickup", "refill": 0.0,
				"gives": {"food": 3}, "morality": 0.01, "verb": "foraging",
				# Only the apple heap is used up. A bush picked bare would
				# leave the village one bad afternoon from no food at all.
				"consumes_only": ["Nature/apples"]},
	"harvest": {"need": "", "sources": ["Nature/crop_row"],
				"seconds": 3.5, "anim": "pickup", "refill": 0.0,
				"gives": {"food": 5}, "morality": 0.02, "verb": "harvesting",
				"consumes": true},
	# `consumes` removes what was worked on; `leaves` puts something in its
	# place. This is what makes the world change under the villagers rather
	# than them miming at scenery that never moves -- a forest that is still
	# a forest after an hour of chopping is a backdrop, not a resource.
	"chop":    {"need": "", "sources": ["Nature/tree", "Nature/pine"],
				"seconds": 5.0, "anim": "chop", "refill": 0.0,
				"gives": {"wood": 5}, "morality": 0.0, "verb": "chopping",
				"consumes": true, "leaves": "Nature/stump"},
	"quarry":  {"need": "", "sources": ["Nature/rock"],
				"seconds": 5.0, "anim": "chop", "refill": 0.0,
				"gives": {"stone": 3}, "morality": 0.0, "verb": "quarrying",
				"consumes": true},
	"pick":    {"need": "fun", "sources": ["Nature/flowers"],
				"seconds": 2.5, "anim": "pickup", "refill": 0.45,
				"morality": 0.0, "verb": "picking flowers",
				"consumes": true},

	# Building. `wants` names the structure the village is short of, and the
	# village decides that -- a villager will not put up a third well.
	# The quickest build in the game, deliberately. It is the first thing the
	# player ever sees finished, and at 7.0 s the opening was: chop at 24 s,
	# hut standing at 35 s. A first shelter is a lean-to, not a joinery job.
	"build_hut":   {"need": "", "sources": [], "anywhere": true,
					"seconds": 4.5, "anim": "chop", "refill": 0.0,
					"takes": {"wood": 6}, "builds": "Buildings/hut",
					"wants": "Buildings/hut", "clear": 2.0,
					"morality": 0.05, "verb": "building a hut"},
	"build_well":  {"need": "", "sources": [], "anywhere": true,
					"seconds": 4.5, "anim": "chop", "refill": 0.0,
					"takes": {"wood": 4, "stone": 3},
					"builds": "Buildings/well", "wants": "Buildings/well",
					"clear": 2.0, "morality": 0.05, "verb": "digging a well"},
	"build_stall": {"need": "", "sources": [], "anywhere": true,
					"seconds": 4.5, "anim": "chop", "refill": 0.0,
					"takes": {"wood": 6},
					"builds": "Buildings/market_stall",
					"wants": "Buildings/market_stall",
					"clear": 1.6, "morality": 0.04, "verb": "raising a stall"},
	"build_shrine":{"need": "", "sources": [], "anywhere": true,
					"seconds": 6.0, "anim": "chop", "refill": 0.0,
					"takes": {"wood": 5, "stone": 5},
					"builds": "Buildings/shrine", "wants": "Buildings/shrine",
					"clear": 2.0, "morality": 0.10,
					"verb": "raising a shrine"},
	"build_cottage":{"need": "", "sources": [], "anywhere": true,
					"seconds": 8.0, "anim": "chop", "refill": 0.0,
					"takes": {"wood": 8, "stone": 2},
					"builds": "Buildings/cottage",
					"wants": "Buildings/cottage", "clear": 2.4,
					"morality": 0.05, "verb": "raising a cottage"},
	"build_mansion":{"need": "", "sources": [], "anywhere": true,
					"seconds": 10.0, "anim": "chop", "refill": 0.0,
					"takes": {"wood": 10, "stone": 8},
					"builds": "Buildings/mansion",
					"wants": "Buildings/mansion", "clear": 2.6,
					"morality": 0.05, "verb": "raising a mansion"},
	"build_tavern":{"need": "", "sources": [], "anywhere": true,
					"seconds": 8.0, "anim": "chop", "refill": 0.0,
					"takes": {"wood": 8, "stone": 2},
					"builds": "Buildings/tavern",
					"wants": "Buildings/tavern", "clear": 2.2,
					"morality": 0.05, "verb": "raising a tavern"},
	"build_hotel": {"need": "", "sources": [], "anywhere": true,
					"seconds": 9.0, "anim": "chop", "refill": 0.0,
					"takes": {"wood": 10, "stone": 4},
					"builds": "Buildings/hotel",
					"wants": "Buildings/hotel", "clear": 2.4,
					"morality": 0.05, "verb": "raising a hotel"},
	"build_lumber_camp":{"need": "", "sources": [], "anywhere": true,
					"seconds": 8.0, "anim": "chop", "refill": 0.0,
					"takes": {"wood": 8},
					"builds": "Buildings/lumber_camp",
					"wants": "Buildings/lumber_camp", "clear": 2.5,
					"morality": 0.05, "verb": "raising a lumber camp"},
	"build_mine":  {"need": "", "sources": [], "anywhere": true,
					"seconds": 8.0, "anim": "chop", "refill": 0.0,
					"takes": {"wood": 6, "stone": 4},
					"builds": "Buildings/mine",
					"wants": "Buildings/mine", "clear": 2.4,
					"morality": 0.05, "verb": "raising a mine"},
	"build_smithy":{"need": "", "sources": [], "anywhere": true,
					"seconds": 8.0, "anim": "chop", "refill": 0.0,
					"takes": {"wood": 6, "stone": 6},
					"builds": "Buildings/smithy",
					"wants": "Buildings/smithy", "clear": 2.2,
					"morality": 0.05, "verb": "raising a smithy"},
	"build_barracks":{"need": "", "sources": [], "anywhere": true,
					"seconds": 10.0, "anim": "chop", "refill": 0.0,
					"takes": {"wood": 8, "stone": 10},
					"builds": "Buildings/barracks",
					"wants": "Buildings/barracks", "clear": 2.5,
					"morality": 0.05, "verb": "raising barracks"},
	"build_farm":  {"need": "", "sources": [], "anywhere": true,
					"seconds": 8.0, "anim": "chop", "refill": 0.0,
					"takes": {"wood": 8},
					"builds": "Buildings/farm",
					"wants": "Buildings/farm", "clear": 2.6,
					"morality": 0.05, "verb": "raising a farm"},
	"build_windmill":{"need": "", "sources": [], "anywhere": true,
					"seconds": 9.0, "anim": "chop", "refill": 0.0,
					"takes": {"wood": 8, "stone": 6},
					"builds": "Buildings/windmill",
					"wants": "Buildings/windmill", "clear": 2.4,
					"morality": 0.05, "verb": "raising a windmill"},
	# --- sins -------------------------------------------------------------
	#
	# THE MISSING HALF OF JUDGEMENT. Every other action in this table carries a
	# morality of zero or better, so no follower could ever become anything but
	# good -- `morality_label` had "Selfish" and "Wicked" strings that nothing
	# in the game could ever produce, and punishing was a button that hurt
	# somebody for no reason.
	#
	# A sin is the SELFISH SHORTCUT to a need, not a separate evil errand. When
	# the larder is thin an honest villager goes foraging; a greedy one takes a
	# double share out of the store. That is why they answer the same `need`
	# keys as the honest actions and are chosen in the same breath -- see
	# _answer_need.
	"steal":       {"need": "hunger", "sources": [], "anywhere": true,
					"seconds": 2.0, "anim": "pickup", "refill": 0.95,
					"takes": {"food": 2}, "morality": -0.09, "sin": true,
					"verb": "taking more than their share"},
	"shirk":       {"need": "energy", "sources": [], "anywhere": true,
					"seconds": 4.0, "anim": "idle", "refill": 0.55,
					"morality": -0.05, "sin": true,
					"verb": "shirking"},
	"brawl":       {"need": "fun", "sources": [], "anywhere": true,
					"seconds": 3.0, "anim": "chop", "refill": 0.60,
					"morality": -0.14, "sin": true,
					"verb": "picking a fight"},

	"sow":         {"need": "", "sources": [], "anywhere": true,
					"seconds": 4.0, "anim": "pickup", "refill": 0.0,
					"takes": {"food": 1}, "builds": "Nature/crop_row",
					"wants": "Nature/crop_row", "clear": 0.7,
					"morality": 0.02, "verb": "sowing"},

	# --- jobs ---------------------------------------------------------------
	#
	# The "job" key is a HARD gate: choose_action skips any of these for
	# everyone who does not hold that job (see the WORK pool below), so a
	# villager with no priest among them never rolls bless_flock no matter how
	# little else there is to do. `cooldown` (checked in `_demand`, set in
	# `_finish_action`) is what stops one priest looping bless_flock forever --
	# without it the highest-favour job action wins every single decision and
	# a village of one priest and forty villagers spends its whole life being
	# blessed.
	"bless_flock": {"need": "", "sources": ["Buildings/shrine"],
					"seconds": 4.0, "anim": "idle", "refill": 0.0,
					"job": "priest", "cooldown": 30, "morality": 0.05,
					"verb": "blessing the flock"},
	# No `sources` -- the nurse's destination is a PERSON, resolved through
	# `village.host.seek("lowest_health", ...)` rather than an asset id, which
	# is what `seeks` is for.
	"tend":        {"need": "", "seeks": "lowest_health",
					"seconds": 3.0, "anim": "pickup", "refill": 0.0,
					"job": "nurse", "morality": 0.03,
					"verb": "tending the sick"},
	"sing":        {"need": "", "sources": ["Buildings/tavern",
											"Buildings/market_stall"],
					"anywhere": true,
					"seconds": 4.0, "anim": "idle", "refill": 0.0,
					"job": "bard", "cooldown": 20, "morality": 0.02,
					"verb": "singing"},
	# `range` caps how far a hunter will bother crossing the map after a wolf
	# that has probably moved by the time they arrive -- see
	# Brain._somewhere_to_do. It does not change WHERE they stand once they
	# commit; that is still `beside()`, the same as any other seeks action.
	"hunt":        {"need": "", "seeks": "wolf", "range": 10.0,
					"seconds": 2.5, "anim": "chop", "refill": 0.0,
					"job": "hunter", "morality": 0.03, "verb": "hunting"},

	# NOT IN WORK. `flee` is never chosen by favour -- it pre-empts the whole
	# decision in `choose_action` while `flee_from` is set (a wolf came close;
	# see ValeRoot/Wolf) and is never weighed against chopping wood.
	"flee":        {"need": "", "anywhere": true,
					"seconds": 1.4, "anim": "walk", "refill": 0.0,
					"morality": 0.0, "verb": "fleeing"},
}

## Work the village does for itself rather than to fill a bar. These are the
## ones favour steers, and the only ones blessing can encourage.
const WORK := ["forage", "harvest", "chop", "quarry",
			   "build_hut", "build_well", "build_stall", "build_shrine",
			   "build_cottage", "build_mansion", "build_tavern", "build_hotel",
			   "build_lumber_camp", "build_mine", "build_smithy",
			   "build_barracks", "build_farm", "build_windmill",
			   "sow", "bless_flock", "tend", "sing", "hunt"]

## How long a child takes to grow up, in seconds of village time. Long enough
## that watching one grow is a thing that happens over a session, short enough
## that a village is not permanently half toddlers.
const ADULT_AT := 240.0

## What a child is allowed to do. They eat, sleep, wash, play and talk; they do
## not fell trees or raise buildings. Without this a newborn walks off with an
## axe, which is funny once.
const CHILD_ACTIONS := ["eat", "rest", "wash", "play", "pick"]

var name := "Someone"
var age := 0.0
var adult := true
## What this villager IS -- see Jobs. "villager" is the default everyone is
## born with; ValeRoot._pick_job assigns the rest at spawn time, once, and it
## never changes afterward (nobody switches trades mid-run).
var job := "villager"
var stats: Dictionary = {}
var personality: Personality
var memories: Memories
var rng := RandomNumberGenerator.new()

## -1 devil .. +1 saint. The RECORD of what they have done, not what the god
## thinks of them -- a follower punished unfairly is still a saint.
## --- faith, as a LEVEL ------------------------------------------------------
##
## Five names rather than a number, because "Devoted" is a thing to be and
## "faith 0.82" is a readout. The bar between them is the only progress in the
## game that cannot be lost: needs leak, stores are eaten, buildings burn, and
## a villager who has been brought to Adept stays Adept.
##
## The curve is deliberately steep at the top. Reaching Believer should happen
## in a first session and feel like the game rewarding attention; reaching
## Devoted should take days, and be why the village is worth coming back to.
const FAITH_TIERS := ["Atheist", "Agnostic", "Believer", "Adept", "Devoted"]
const FAITH_NEEDED := [12.0, 40.0, 110.0, 260.0]   ## to leave each tier

var faith_xp := 0.0
var faith_level := 0                    ## index into FAITH_TIERS


## Grant faith. Returns the number of tiers crossed, so the caller can make a
## noise about it -- a level that passes in silence is a level nobody noticed.
func gain_faith(amount: float) -> int:
	if amount <= 0.0:
		return 0
	faith_xp += amount
	var rose := 0
	while faith_level < FAITH_NEEDED.size() 			and faith_xp >= float(FAITH_NEEDED[faith_level]):
		faith_xp -= float(FAITH_NEEDED[faith_level])
		faith_level += 1
		rose += 1
	if faith_level >= FAITH_NEEDED.size():
		faith_xp = 0.0                  # Devoted is the top; nothing to fill
	return rose


func faith_tier() -> String:
	return String(FAITH_TIERS[clampi(faith_level, 0, FAITH_TIERS.size() - 1)])


## How full the bar to the next tier is, 0..1. Full and flat at the top.
func faith_progress() -> float:
	if faith_level >= FAITH_NEEDED.size():
		return 1.0
	return clampf(faith_xp / float(FAITH_NEEDED[faith_level]), 0.0, 1.0)


## 0..1 across the whole ladder, which is what the economy multiplies by. An
## Atheist is not worthless -- a god with only atheists still earns -- but a
## village of the Devoted earns roughly three times as much.
func devotion() -> float:
	var span := float(FAITH_TIERS.size() - 1)
	return clampf((float(faith_level) + faith_progress()) / span, 0.0, 1.0)


var morality := 0.0
## When they last did something worth punishing, on the village clock. The
## mirror of `last_action_at`, and what makes a punishment land or miss.
var last_sin := ""
var last_sin_at := -999.0

## action id -> multiplier. The god's whole influence, in one dictionary.
var favour: Dictionary = {}

## What they are doing right now, and how far through it they are.
var action := ""
var action_left := 0.0
var target_id := ""
## Where the BODY is, set by the follower before it asks for a decision. The
## brain needs it to answer "can I get there", which it cannot do from the
## grid alone -- see the reachability veto in _somewhere_to_do.
var at_cell := Vector2i(-1, -1)

## Where the current errand is headed. Read by the host when a `builds` action
## finishes, because the BUILDER places the structure -- the brain has no
## business holding a reference to the scene.
var target_cell := Vector2i(-1, -1)

var thought := ""
var thought_log: Array[String] = []
## The number this brain was rolled from. Name and personality derive from it.
var seed_value := 0
var _thought_timer := 0.0

## action id -> the village-clock time it becomes available again. Checked in
## `_demand`, set in `_finish_action`. Only actions carrying a "cooldown" key
## use this at all.
var _cooldowns: Dictionary = {}

## Set by Wolf's trouble radius (see ValeRoot/Wolf) via `frighten()`. While
## non-null, `choose_action` pre-empts everything else and returns "flee";
## consumed and cleared by `destination_for` once it has used it to pick a
## direction to run in.
var flee_from = null

## Set by the social layer while a conversation is running.
var chatting_with := ""

## The last job actually COMPLETED. This is what blessing and punishment
## reinforce, which is why the god has to watch and time it rather than pick
## a behaviour from a menu.
var last_action := ""
## WHEN it finished, on the village clock. A bare string cannot answer "did
## they just do that", and "just" is the whole of the blessing mechanic.
var last_action_at := -999.0

var village = null                       ## Village, injected; may be null
## The map, injected by the body. Needed at CHOOSING time, not only at routing
## time: an action whose source does not exist anywhere is not a choice, it is
## a wasted walk, and the difference is invisible from outside.
var grid = null
## The god's boons, read rather than applied. A boon that wrote into ACTIONS --
## a const shared by every mind in the game -- would make its change permanent,
## global and invisible to the next run.
var boons = null


func _init(value: int) -> void:
	# Seeded per follower and NOT from the clock, so the village comes up the
	# same twice and a rendering change can be told apart from a different set
	# of errands. KEPT, because the save stores this one integer instead of a
	# name and a personality: both are derived from it and cannot drift.
	seed_value = value
	rng.seed = value
	personality = Personality.roll(rng)
	memories = Memories.new()
	for k in STAT_ORDER:
		# Not all full: a village where everyone gets hungry at the same second
		# queues at the same stall and looks scripted.
		stats[k] = rng.randf_range(0.55, 1.0)
	stats["health"] = rng.randf_range(0.8, 1.0)
	for a in ACTIONS:
		favour[a] = 1.0
	_thought_timer = rng.randf_range(2.0, 9.0)


func tick(delta: float) -> void:
	for k in STAT_ORDER:
		stats[k] = maxf(0.0, float(stats[k]) - _drain(k) * delta)

	# Health is downstream of the others. Starving and exhausted follower loses
	# health; a comfortable one slowly recovers it. Without this, Health is a
	# bar that never moves and the player learns to ignore it.
	var strain := 0.0
	if float(stats["hunger"]) < 0.15:
		strain += 0.030
	if float(stats["energy"]) < 0.10:
		strain += 0.018
	if float(stats["hygiene"]) < 0.10:
		strain += 0.010
	if strain > 0.0:
		stats["health"] = maxf(0.0, float(stats["health"]) - strain * delta)
	elif float(stats["hunger"]) > 0.5 and float(stats["energy"]) > 0.4:
		stats["health"] = minf(1.0, float(stats["health"]) + 0.012 * delta)

	age += delta
	if not adult and age >= ADULT_AT:
		adult = true
		think_aloud()

	memories.tick(delta)

	if action_left > 0.0:
		action_left -= delta
		if action_left <= 0.0:
			_finish_action()

	_thought_timer -= delta
	if _thought_timer <= 0.0:
		_thought_timer = rng.randf_range(7.0, 16.0)
		think_aloud()


func _drain(key: String) -> float:
	var base: float = (DRAIN[key] * (boons.drain() if boons != null else 1.0)
		* (village.passive_need_decay(key) if village != null else 1.0))
	match key:
		"hunger": return base * personality.appetite
		"energy": return base / maxf(0.35, personality.vigour)
		"social": return base * personality.sociability
		"hygiene": return base * personality.tidiness
	return base


func think_aloud() -> void:
	var line := Thoughts.compose(self, rng)
	if line == "":
		return
	thought = line
	thought_log.push_front(line)
	if thought_log.size() > 8:
		thought_log.resize(8)


## -1 miserable, 0 coping, +1 content. What the hover icon reads.
##
## Deliberately NOT the plain mean of the stats. One empty bar ruins a day in a
## way four half-full ones do not, so the worst stat is weighted heavily -- a
## follower with everything at 0.6 and nothing at 0 is fine, and a follower
## with one bar at zero is not, and a mean cannot tell those apart.
func mood() -> float:
	var total := 0.0
	var worst := 1.0
	for k in STAT_ORDER:
		var v := float(stats[k])
		total += v
		worst = minf(worst, v)
	var mean := total / float(STAT_ORDER.size())
	var base := mean * 0.55 + worst * 0.45
	# Recent treatment colours it either way.
	base += memories.divine_standing() * 0.12
	return clampf(base * 2.0 - 1.0, -1.0, 1.0)


func mood_face() -> String:
	var m := mood()
	if m > 0.25:
		return "happy"
	if m < -0.25:
		return "sad"
	return "flat"


## The stat that most needs attention, and how badly. Used by the panel and by
## the god's "what does this one want" readout.
func worst_stat() -> Array:
	var key := STAT_ORDER[0]
	var low := 2.0
	for k in STAT_ORDER:
		if float(stats[k]) < low:
			low = float(stats[k])
			key = k
	return [key, low]


## A wolf came close. Drop whatever this villager was doing -- an action
## already committed to (mid-chop, mid-build) does not get to finish, because
## finishing it means standing still next to the thing that just scared them --
## and let the next decision run away instead.
func frighten(at: Vector3) -> void:
	flee_from = at
	action = ""
	action_left = 0.0


## --- deciding what to do ----------------------------------------------------

## Choose an action id, or "" to wander.
##
## Needs first, but only real ones; then work, weighted by favour and by what
## the village is short of. The ordering is the design: a follower will not
## chop wood while starving, and the god cannot make them, which is what keeps
## blessing an influence rather than a command.
func choose_action() -> String:
	# A wolf came close. This pre-empts everything else -- needs, sin, work,
	# even a child's play -- because nothing else matters while something is
	# actively hunting the village. Not cleared here: `destination_for` reads
	# `flee_from` to pick a direction and clears it once it has, so the
	# direction is still available the one time it is needed.
	if flee_from != null:
		return "flee"

	# The worst stat that something can actually be DONE about.
	#
	# Not simply the worst stat. Health has no action -- it recovers on its own
	# once a follower is fed and rested -- so a sick follower's worst stat is
	# permanently Health, `_action_for_need` permanently returns "", and every
	# branch below falls through to work. The symptom was not an error: nobody
	# ever slept, washed or prayed, those three bars sat at zero for the whole
	# run, and the village merely looked miserable.
	var pair: Array = _worst_actionable()
	var key: String = pair[0]
	var level: float = pair[1]
	if level < DESPERATE:
		var forced := _answer_need(key, level)
		if forced != "" and (adult or CHILD_ACTIONS.has(forced)):
			return forced

	# Social is answered by the social layer -- by being NEAR someone -- so it
	# has no destination and cannot go through the branch below.
	#
	# It has to COMPETE, though, rather than pre-empt. Checked first, this
	# branch fired whenever Social was merely below URGENT, and since Social
	# drains fast and only refills when another villager happens to wander
	# past, a lonely villager wandered permanently and never got round to
	# sleeping, washing or praying. Now it wins only when loneliness is
	# genuinely the worst thing in their life.
	var lonely: float = float(stats["social"])
	if lonely < URGENT and lonely <= level and rng.randf() < 0.7:
		return "talk"

	if level < URGENT:
		var want := _answer_need(key, level)
		if (want != "" and (adult or CHILD_ACTIONS.has(want))
				and rng.randf() < 0.85):
			return want

	if not adult:
		# A child with nothing pressing plays. They are not idle labour.
		return "play" if rng.randf() < 0.7 else ""

	# Work. Weighted by favour (the god's influence) times village demand, so
	# a blessed woodcutter chops more AND the village still eats.
	var pool: Array[Dictionary] = []
	for a in WORK:
		# A job action belongs ONLY to its job -- a village of villagers must
		# never roll bless_flock just because favour on it happens to be high.
		# Jobless actions (chop, forage, the plain build_* set) carry no "job"
		# key at all and stay open to everyone, same as always.
		var want_job := String(ACTIONS[a].get("job", ""))
		if want_job != "" and want_job != job:
			continue
		var w: float = (float(favour.get(a, 1.0)) * _demand(a)
			* Jobs.mult(job, a))
		if w > 0.01:
			pool.append({"a": a, "w": w})
	if pool.is_empty():
		return ""
	var total := 0.0
	for p in pool:
		total += float(p["w"])
	var roll := rng.randf() * total
	for p in pool:
		roll -= float(p["w"])
		if roll <= 0.0:
			return String(p["a"])
	return String(pool[pool.size() - 1]["a"])


## The honest answer to a need, or the selfish one.
##
## Children never sin -- a toddler taking a second helping is not a moral event
## and the god should not be smiting them for it.
func _answer_need(key: String, level: float) -> String:
	var honest := _action_for_need(key)
	if not adult:
		return honest
	var sin := _sin_for_need(key)
	if sin == "":
		return honest
	if rng.randf() < _temptation(level, honest):
		return sin
	return honest


## The sin that answers this need, if there is one and it can be done.
func _sin_for_need(key: String) -> String:
	for a in ACTIONS:
		var spec: Dictionary = ACTIONS[a]
		if not bool(spec.get("sin", false)):
			continue
		if String(spec.get("need", "")) != key:
			continue
		# Even a thief cannot take from an empty larder.
		if village != null:
			var takes: Dictionary = spec.get("takes", {})
			if not takes.is_empty() and not village.can_take(takes):
				return ""
		return String(a)
	return ""


## How likely this follower is to take the shortcut, 0 .. 0.85.
##
## Three things, and they multiply rather than add up to a constant: WHO they
## are, what they have already done, and how badly they need it. A kind
## follower in comfort never sins; a greedy one who has sinned before and is
## starving nearly always does. The middle is where it is interesting.
func _temptation(level: float, honest: String) -> float:
	var selfish := clampf(-personality.kindness, 0.0, 1.0)
	# Wickedness compounds: each sin makes the next one cheaper, which is what
	# turns one bad afternoon into a villager the player has to deal with.
	var wicked := clampf(-morality, 0.0, 1.0)
	var pressure := clampf((URGENT - level) / maxf(URGENT, 0.01), 0.0, 1.0)
	# The weights are deliberately generous. At half these values a lean
	# eighteen-person village produced TWO sins in four minutes, which is a
	# mechanic the player would never meet -- and an unseen wrongdoer leaves
	# punishment exactly as pointless as it was before. The spread is what
	# matters more than the average: a Greedy follower (kindness near -0.95)
	# sits around 0.75 and steals whenever they are hungry, an ordinary one
	# around 0.2, and a Gentle one almost never.
	var base := selfish * 0.75 + wicked * 0.45
	# Nobody is incorruptible. A small floor means even a decent village throws
	# up the occasional bad afternoon, which is what keeps the player watching.
	base += 0.05
	# THE STRONGEST PUSH IS HAVING NO HONEST OPTION. A hungry villager standing
	# in front of a larder they are not allowed to touch is exactly who steals.
	if honest == "":
		base += 0.40
	return clampf(base * (0.30 + 0.70 * pressure), 0.0, 0.85)


## Did they do something worth punishing, recently enough to punish them for?
func recently_sinned(now: float, window: float) -> bool:
	return last_sin != "" and (now - last_sin_at) <= window


## The lowest stat that has an action attached, and its level.
func _worst_actionable() -> Array:
	var key := ""
	var low := 2.0
	for k in STAT_ORDER:
		if _action_for_need(k) == "":
			continue
		if float(stats[k]) < low:
			low = float(stats[k])
			key = k
	return [key, low] if key != "" else ["", 1.0]


## The action that answers a need -- but only if it can actually be DONE.
##
## Affordability is checked HERE, at the moment of choosing, not on arrival.
## With fifty villagers and an empty granary, every one of them chose `eat`,
## walked across the map, was refused at the larder, waited, and chose `eat`
## again: 1160 of 1906 decisions ended in a refusal and only 13% produced any
## work at all. From outside that is a village standing around doing nothing,
## and the cause is not idleness -- it is a queue for food that does not exist.
##
## Returning "" when the store is empty makes hunger a NON-actionable need, so
## `_worst_actionable` moves on, and the work branch below picks up foraging
## with a shortage of 1.0 behind it. Hungry villagers go and find food instead
## of queueing for it.
func _action_for_need(key: String) -> String:
	for a in ACTIONS:
		var spec: Dictionary = ACTIONS[a]
		if String(spec.get("need", "")) != key:
			continue
		if village != null:
			var takes: Dictionary = spec.get("takes", {})
			if not takes.is_empty() and not village.can_take(takes):
				return ""
		# And the PLACE has to exist. Praying needs a shrine; with none built,
		# every villager whose Faith ran low chose `pray`, found no
		# destination, wandered, and chose it again -- 2473 dead decisions in
		# one run, which from outside is a village milling about.
		if not _somewhere_to_do(spec):
			return ""
		return a
	return ""


## Is there anywhere in the world to perform this action?
func _somewhere_to_do(spec: Dictionary) -> bool:
	if bool(spec.get("anywhere", false)):
		return true
	if grid == null:
		return true                    # no map yet; do not veto on ignorance

	# A SEEKS action's destination is a MOVING THING -- the sickest villager,
	# the nearest wolf -- resolved through the host rather than named as an
	# asset id. `range`, when the action carries one, caps how far this is
	# worth walking for: a hunter should not cross the whole map after a wolf
	# it will have lost by the time it arrives.
	var seeks := String(spec.get("seeks", ""))
	if seeks != "":
		if village == null or village.host == null:
			return false
		var origin: Vector3 = grid.world_of(at_cell)
		var target = village.host.seek(seeks, origin)
		if target == null or not is_instance_valid(target):
			return false
		var range_m: float = float(spec.get("range", 0.0))
		if range_m > 0.0 and origin.distance_to(target.position) > range_m:
			return false
		return grid.reachable(at_cell, grid.cell_of(target.position))

	# REACHABLE, not merely existing.
	#
	# This asked whether the world contained a tree, and a villager on the far
	# side of an unbridged river would answer yes forever: choose `chop`, find
	# the nearest tree, fail to route, wander, choose `chop` again. Measured at
	# 620 of 1078 decisions ending in "no route" -- 57% of everything the
	# village decided to do. The existing veto pattern is to refuse an action
	# at CHOICE time rather than discover it on arrival, and this is the same
	# rule applied to distance instead of to supply.
	for aid in spec.get("sources", []):
		for c in grid.cells_of(String(aid)):
			if grid.reachable(at_cell, c):
				return true
	return false


## How badly this resource is wanted BY SOMETHING THE VILLAGE IS TRYING TO
## BUILD, as opposed to being merely absent from the store.
##
## `Village.shortage` treats every empty store as equally urgent, so an opening
## village with nothing at all rated wood and stone the same and spent its
## first minute quarrying. Measured: first quarry at 12 s, first chop at 47 s,
## first building at 147 s -- with stone at 6/10 and wood at 4/16, while the
## only thing anyone wanted was a hut, which needs no stone whatsoever.
##
## Returns 0 when nothing wanted needs this, so it can only ever promote the
## material that is actually standing in the way of the next building.
func _needed_for_wants(res: String) -> float:
	if village == null:
		return 0.0
	var worst := 0.0
	for a in ACTIONS:
		var spec: Dictionary = ACTIONS[a]
		var aid := String(spec.get("wants", ""))
		if aid == "":
			continue
		# Claims deliberately NOT counted -- see Village.wants.
		var want: float = village.wants(aid, false)
		if want <= 0.0:
			continue
		var takes: Dictionary = spec.get("takes", {})
		if not takes.has(res):
			continue
		var need := float(takes[res])
		if need <= 0.0:
			continue
		var missing := clampf((need - float(village.amount(res))) / need,
							  0.0, 1.0)
		worst = maxf(worst, want * missing)
	return worst


## How much the village wants this work done.
##
## Two different questions behind one number. For gathering it is "are we short
## of the stuff this produces"; for building it is "are we short of this
## STRUCTURE, and can we pay for it". Building something the village already
## has, or cannot afford, must score zero -- otherwise villagers queue up to
## start a hut nobody can finish.
func _demand(a: String) -> float:
	if village == null:
		return 1.0
	var spec: Dictionary = ACTIONS[a]

	# On cooldown -- a flat zero, not a discount, or the pool still ranks it
	# above everything else the instant it is even slightly affordable and a
	# lone priest spends its whole life re-rolling bless_flock the second the
	# clock allows a fraction of it.
	var cd: float = float(spec.get("cooldown", 0.0))
	if cd > 0.0 and float(village.now) < float(_cooldowns.get(a, -999.0)):
		return 0.0

	var wants := String(spec.get("wants", ""))
	if wants != "":
		var need: float = village.wants(wants)
		if need <= 0.0:
			return 0.0
		# Affordable NOW, from the shared store. A villager who cannot pay
		# walks to the site, fails, and wanders -- which reads as them
		# dithering and is really an accounting error.
		if not village.can_take(spec.get("takes", {})):
			return 0.0
		# Wanted structures outrank ordinary gathering: a village with no hut
		# should build one rather than keep stacking wood.
		return 0.6 + need * 2.2

	if not _somewhere_to_do(spec):
		return 0.0
	var gives: Dictionary = spec.get("gives", {})
	var want := 0.0
	for res in gives:
		want = maxf(want, village.shortage(String(res)))
		# Gathering for a PURPOSE beats gathering because a bar is low. This is
		# what puts an axe in the first villager's hands instead of a pick.
		#
		# The multiplier clears 1.0, because `shortage` reads 1.0 for ANY empty
		# store, so without a margin stone ties with wood on an opening plot
		# and a founder spends the first minute quarrying for a well nobody
		# asked for. It is deliberately a SMALL margin: pushed to 2.2 the
		# village became unstable -- work piled onto whatever was momentarily
		# scarcest and the openings measured worse across four runs (pop 3-4
		# and 3-5 buildings at five minutes, against 5-6 and 5-6 at 1.35).
		# Raising this term rather than lowering `shortage` keeps food -- which
		# no building needs, and is therefore purely shortage-driven -- exactly
		# as urgent as it was.
		want = maxf(want, _needed_for_wants(String(res)) * 1.35)
		# Gathering pulls TOWARD what the village is trying to build. Without
		# this, wanting a hut makes hut-building attractive and does nothing
		# about the wood -- so two villagers stand around at six wood, needing
		# eight, with chopping no more appealing than it was before anyone
		# wanted a hut. Villagers who gather with a purpose read as villagers.
		want += _needed_for_projects(String(res)) * 1.4
	return 0.15 + want


## How badly some structure we lack, and cannot yet afford, wants `res`.
func _needed_for_projects(res: String) -> float:
	var worst := 0.0
	for a in WORK:
		var spec: Dictionary = ACTIONS[a]
		var wants := String(spec.get("wants", ""))
		if wants == "":
			continue
		var takes: Dictionary = spec.get("takes", {})
		if not takes.has(res):
			continue
		var need: float = village.wants(wants)
		if need <= 0.0 or village.can_take(takes):
			continue                 # not wanted, or already affordable
		var have := float(village.amount(res))
		var cost := float(takes[res])
		worst = maxf(worst, need * clampf(1.0 - have / maxf(cost, 1.0), 0.0, 1.0))
	return worst


## Where to go for `act`, as a walkable cell, or (-1,-1) if there is nowhere.
##
## Three shapes of destination, in order:
##   a BUILD SITE -- open ground with room around it, near the settlement
##   a SOURCE     -- stand beside one of the named assets
##   ANYWHERE     -- a few steps from here, for things needing no place at all
func destination_for(grid, from: Vector2i, act: String) -> Vector2i:
	if not ACTIONS.has(act):
		return grid.random_cell(rng)
	var spec: Dictionary = ACTIONS[act]

	if act == "flee":
		var spot := _flee_spot(grid, from)
		target_cell = spot
		return spot

	if String(spec.get("builds", "")) != "":
		var spot: Vector2i = _open_spot(grid, from, float(spec.get("clear", 2.0)))
		target_cell = spot
		return spot

	var seeks := String(spec.get("seeks", ""))
	if seeks != "":
		if village == null or village.host == null:
			return Vector2i(-1, -1)
		var target = village.host.seek(seeks, grid.world_of(from))
		if target == null or not is_instance_valid(target):
			return Vector2i(-1, -1)
		var tcell: Vector2i = grid.cell_of(target.position)
		var stand: Vector2i = grid.beside(tcell, rng)
		if stand.x < 0 or not grid.reachable(from, stand):
			return Vector2i(-1, -1)
		target_id = seeks
		target_cell = stand
		return stand

	var sources: Array = spec.get("sources", [])
	var ranked: Array = []
	for aid in sources:
		for c in grid.cells_of(String(aid)):
			var cell: Vector2i = c
			# Same region as the villager, or the walk cannot happen. Sorting
			# by distance alone put the nearest tree across the river at the
			# top of the list every single time.
			if not grid.reachable(from, cell):
				continue
			ranked.append([absi(cell.x - from.x) + absi(cell.y - from.y), cell,
						   String(aid)])
	if not ranked.is_empty():
		ranked.sort_custom(func(a, b): return a[0] < b[0])
		# Among the nearest few, not the single nearest: two villagers who
		# share a doorstep must not pick the same tree every time, forever.
		var span: int = mini(5, ranked.size())
		for i in span:
			var pick: int = rng.randi_range(0, mini(span, ranked.size()) - 1)
			var stand: Vector2i = grid.beside(ranked[pick][1], rng)
			# The TREE being reachable is not the same as the patch of grass
			# beside it being reachable: `reachable` passes a prop if ANY of
			# its neighbours shares the villager's region, and `beside` is free
			# to hand back a different one -- across the river, or inside a
			# courtyard walled off by huts. One run in three still ended with
			# over a thousand dead routes because of exactly that gap.
			if stand.x >= 0 and not grid.reachable(from, stand):
				stand = Vector2i(-1, -1)
			if stand.x >= 0:
				target_id = String(ranked[pick][2])
				target_cell = stand
				return stand
			ranked.remove_at(pick)
			if ranked.is_empty():
				break

	if bool(spec.get("anywhere", false)):
		# No source in the world, and none needed. Eating comes out of the
		# shared store; a villager with no hut sleeps on the grass. Without
		# this the opening -- a bare plot with no buildings at all -- would
		# have nobody able to eat or sleep until the first hut went up.
		target_cell = _near(grid, from, 5)
		return target_cell
	return Vector2i(-1, -1)


## A cell roughly 4 m away from `flee_from`, in the direction away from it.
## Clears `flee_from` once used: the fear is consumed the instant a direction
## is chosen, so the next replan makes an ordinary decision again rather than
## fleeing in a loop forever.
func _flee_spot(grid, from: Vector2i) -> Vector2i:
	var origin: Variant = flee_from
	flee_from = null
	if origin == null:
		return _near(grid, from, 5)
	var origin_cell: Vector2i = grid.cell_of(origin as Vector3)
	var away := Vector2(float(from.x - origin_cell.x), float(from.y - origin_cell.y))
	if away.length_squared() < 0.01:
		away = Vector2(1.0, 0.0)
	away = away.normalized()
	var span: int = maxi(1, int(round(4.0 / grid.tile)))
	var target := from + Vector2i(int(round(away.x * float(span))),
								  int(round(away.y * float(span))))
	if grid.is_walkable(target):
		return target
	return _near(grid, from, span)


## Open ground with `clear` metres of room, biased toward where the village
## already is so a settlement grows as a settlement instead of scattering one
## building per corner of the plot.
func _open_spot(grid, from: Vector2i, clear: float) -> Vector2i:
	var radius: int = maxi(1, int(ceil(clear / grid.tile / 2.0)))
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for attempt in 90:
		var c: Vector2i = _near(grid, from, 14)
		if c.x < 0 or not _has_room(grid, c, radius):
			continue
		# Somebody is already walking here with a building in mind. Two
		# villagers sent to overlapping ground is half of why buildings ended
		# up stacked -- the kind was claimed, the SITE was not.
		if village != null and village.site_claimed(c, radius):
			continue
		var d: int = absi(c.x - from.x) + absi(c.y - from.y)
		if d < best_d:
			best_d = d
			best = c
	# NOTE the outcome, but do NOT claim here.
	#
	# `_open_spot` runs at DECISION time, up to three times per replan, for
	# every villager who merely considers building. Claiming here meant forty
	# villagers blanketed the map in 25-second reservations within seconds and
	# then none of them could find anywhere to build -- forty builders with
	# unlimited materials raised two buildings in a whole run. The claim
	# belongs where the villager COMMITS, in Follower._route_to.
	if village != null:
		village.note_site(best.x >= 0)
	return best


## Room for a building: grass all the way round, and clear of other buildings.
##
## `is_walkable` is true of the road, the field and the bank -- a site test on
## it put huts across the highway. But `is_plain` was too strict in the other
## direction: it also refuses any cell holding a tree, and with scatter across
## the whole plot a 7x7 hut site had ZERO valid centres on the starting map.
## `is_buildable` asks the right question, and the trees get cleared.
func _has_room(grid, centre: Vector2i, radius: int) -> bool:
	for i in range(-radius, radius + 1):
		for j in range(-radius, radius + 1):
			if not grid.is_buildable(centre + Vector2i(i, j)):
				return false
	return true


## A walkable cell within `span` tiles of `from`. Public: the body calls this
## when it has nothing to do and should drift locally rather than cross the map.
func near_cell(grid, from: Vector2i, span: int) -> Vector2i:
	return _near(grid, from, span)


func _near(grid, from: Vector2i, span: int) -> Vector2i:
	for attempt in 40:
		var c: Vector2i = from + Vector2i(rng.randi_range(-span, span),
										  rng.randi_range(-span, span))
		if grid.is_walkable(c):
			return c
	return from if grid.is_walkable(from) else grid.random_cell(rng)


## Kept for the movement layer## Kept for the movement layer, which only wants somewhere to walk.
func destination(grid, from: Vector2i) -> Vector2i:
	var act := choose_action()
	if act == "" or act == "talk":
		return grid.random_cell(rng)
	var d := destination_for(grid, from, act)
	return d if d.x >= 0 else grid.random_cell(rng)


## --- doing it ---------------------------------------------------------------

func begin_action(act: String) -> bool:
	if not ACTIONS.has(act):
		return false
	var spec: Dictionary = ACTIONS[act]
	# Stores are checked BEFORE the animation starts, so a follower never mimes
	# eating out of an empty granary.
	var takes: Dictionary = spec.get("takes", {})
	if village != null and not takes.is_empty() and not village.can_take(takes):
		return false
	action = act
	var seconds := float(spec["seconds"])
	# A smithy's `build_seconds_mult` applies only to BUILDING -- a build
	# action is the one with a `builds` id -- never to chopping or foraging,
	# which have no `build_seconds_mult` reason to run any faster.
	if village != null and String(spec.get("builds", "")) != "":
		seconds *= village.passive_mult("build_seconds_mult")
	action_left = seconds
	# Claim the structure so nobody else starts a second one meanwhile.
	var raises := String(spec.get("builds", ""))
	if raises != "" and village != null:
		village.claim(raises)
	return true


func _finish_action() -> void:
	var act := action
	action = ""
	if not ACTIONS.has(act):
		return
	var spec: Dictionary = ACTIONS[act]

	var cd: float = float(spec.get("cooldown", 0.0))
	if cd > 0.0 and village != null:
		_cooldowns[act] = float(village.now) + cd

	if village != null:
		var takes: Dictionary = spec.get("takes", {})
		if not takes.is_empty() and not village.take(takes):
			return                     # someone else got the last loaf
		var gives: Dictionary = spec.get("gives", {})
		if not gives.is_empty():
			# Scaled by how tired this ground is, and the ground is worn a
			# little by the taking. Never reaches zero -- a worked-out plot
			# pays badly, which is what sends the village looking for new land
			# instead of stopping dead.
			#
			# A COPY, never the const table: ACTIONS is shared by every brain
			# in the game and mutating it would make the change permanent and
			# global.
			# A COPY, never the const table.
			var paid: Dictionary = village.scaled_gives(gives, target_cell)
			# Passives (a lumber camp, a mine) scale the yield BEFORE the
			# boon bonus, which is a flat add-on and must land on top of
			# whatever the building already multiplied, not be folded into it.
			for res in paid:
				var r := String(res)
				paid[r] = maxi(1, int(round(
					float(paid[r]) * village.passive_yield(r))))
			var bonus: int = int(boons.yield_bonus()) if boons != null else 0
			if bonus > 0:
				for res in paid:
					paid[res] = int(paid[res]) + bonus
			village.give(paid)
			village.extract_at(target_cell)

	var need := String(spec.get("need", ""))
	if need != "":
		stats[need] = minf(1.0, float(stats[need]) + float(spec["refill"]))
	# An action can pay FAITH instead of, or as well as, filling a need. Only
	# prayer does today, and it is the one way a village raises itself while
	# nobody is watching.
	var faith := float(spec.get("faith", 0.0))
	if faith > 0.0:
		gain_faith(faith)
	# Any completed job is a small comfort, which is why a busy village drifts
	# happier than an idle one even when nobody's bars are full.
	stats["fun"] = minf(1.0, float(stats["fun"]) + 0.06)

	var m := float(spec.get("morality", 0.0))
	if m < 0.0:
		shift_morality(m)
		last_sin = act
		last_sin_at = float(village.now) if village != null else 0.0
		memories.add(Memories.KIND_WORK,
					 "I took the easy way. Nobody saw.", -0.4)
	elif m > 0.0:
		shift_morality(m)
		memories.add(Memories.KIND_WORK, "Did honest work.", 0.35)
	last_action = act
	last_action_at = float(village.now) if village != null else 0.0


func shift_morality(delta: float) -> void:
	morality = clampf(morality + delta, -1.0, 1.0)


func morality_label() -> String:
	if morality > 0.5:
		return "Saintly"
	if morality > 0.15:
		return "Kind"
	if morality < -0.5:
		return "Wicked"
	if morality < -0.15:
		return "Selfish"
	return "Ordinary"


## --- the god's influence ----------------------------------------------------

## Blessing and punishment do not command; they REWEIGHT. The action being
## reinforced is whatever the follower most recently completed, which is why
## the player has to watch and time it rather than pick from a menu.
func bless(strength := 1.0) -> void:
	var act := last_action
	if act != "" and favour.has(act):
		# DIMINISHING, and a higher ceiling. Flat x1.45 with a 6.0 clamp meant
		# five blesses maxed an action out -- and once blessing is free that is
		# thirteen seconds, after which the steering half of the mechanic is
		# over and further blessing only pays. Now it always does something and
		# never hits a wall.
		var f: float = float(favour[act])
		favour[act] = clampf(f * (1.0 + 0.45 * strength * (1.0 - f / 8.0)),
							 0.15, 8.0)
	# THE BLESSING IS THE XP. This is the only source of faith a villager has,
	# which is what makes the player's attention the thing that raises them.
	gain_faith(BLESS_FAITH * strength)
	stats["fun"] = minf(1.0, float(stats["fun"]) + 0.2 * strength)
	memories.add(Memories.KIND_BLESSING,
				 "I was blessed%s." % ("" if act == "" else " for " + act),
				 0.85 * strength, "",
				 personality.memory_weight(1.0) * (1.0 + personality.devotion))
	think_aloud()


func punish(strength := 1.0) -> void:
	var act := last_action
	if act != "" and favour.has(act):
		favour[act] = clampf(float(favour[act]) * (1.0 - 0.40 * strength),
							 0.15, 6.0)
	stats["health"] = maxf(0.05, float(stats["health"]) - 0.30 * strength)
	stats["fun"] = maxf(0.0, float(stats["fun"]) - 0.3 * strength)
	# Caught. The account is SETTLED -- they cannot be punished twice for the
	# same theft -- and being caught pushes them back toward decency, which is
	# what makes punishing a correction rather than just damage.
	if last_sin != "":
		shift_morality(0.22 * strength)
		last_sin = ""
	memories.add(Memories.KIND_PUNISHMENT,
				 "I was struck down%s." % ("" if act == "" else " for " + act),
				 -0.9 * strength, "",
				 personality.memory_weight(-1.0) * (1.0 + personality.devotion))
	think_aloud()


func favoured_action() -> String:
	var best := ""
	var top := 1.0001
	for a in favour:
		if float(favour[a]) > top:
			top = float(favour[a])
			best = String(a)
	return best


## Are they in a state to raise a child? Fed, well and not miserable. Checked
## on BOTH parents, so a village that is barely coping does not grow itself
## into a famine.
func can_parent() -> bool:
	return (adult and age > ADULT_AT * 0.25
			and float(stats["hunger"]) > 0.5
			and float(stats["health"]) > 0.6
			and mood() > -0.1)


func describe() -> String:
	var w: Array = worst_stat()
	return "%s (%s, %s) %s" % [name, personality.describe(),
		morality_label(), "%s %.0f%%" % [STAT_LABEL[w[0]], float(w[1]) * 100.0]]
