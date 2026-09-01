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
	"hunger": 0.0115, "energy": 0.0080, "social": 0.0100, "faith": 0.0050,
	"health": 0.0016, "hygiene": 0.0062, "fun": 0.0072,
}

const STAT_ORDER := ["hunger", "energy", "social", "faith", "health",
					 "hygiene", "fun"]

const STAT_LABEL := {
	"hunger": "Hunger", "energy": "Energy", "social": "Social",
	"faith": "Faith", "health": "Health", "hygiene": "Hygiene", "fun": "Fun",
}

## Below this a need is worth crossing the island for.
const URGENT := 0.45
## Below this the follower will drop work entirely.
const DESPERATE := 0.20

## The catalogue. `need` names the stat an action refills; work actions have
## none and are chosen by favour instead. `sources` are asset ids the follower
## has to stand beside. `gives`/`takes` move village stores.
const ACTIONS := {
	"eat":     {"need": "hunger", "sources": ["Buildings/market_stall",
											  "Buildings/hut",
											  "Buildings/cottage"],
				"seconds": 3.0, "anim": "pickup", "refill": 0.85,
				"takes": {"food": 1}, "morality": 0.0, "verb": "eating"},
	"sleep":   {"need": "energy", "sources": ["Buildings/hut",
											  "Buildings/cottage"],
				"seconds": 5.0, "anim": "idle", "refill": 0.90,
				"morality": 0.0, "verb": "sleeping"},
	"pray":    {"need": "faith", "sources": ["Buildings/shrine"],
				"seconds": 4.0, "anim": "idle", "refill": 0.80,
				"morality": 0.03, "verb": "praying"},
	"wash":    {"need": "hygiene", "sources": ["Buildings/well"],
				"seconds": 3.0, "anim": "pickup", "refill": 0.85,
				"morality": 0.0, "verb": "washing"},
	"play":    {"need": "fun", "sources": ["Buildings/market_stall",
										   "Nature/flowers"],
				"seconds": 3.5, "anim": "idle", "refill": 0.70,
				"morality": 0.0, "verb": "idling"},
	"harvest": {"need": "", "sources": ["Nature/crop_row"],
				"seconds": 4.0, "anim": "pickup", "refill": 0.0,
				"gives": {"food": 2}, "morality": 0.02, "verb": "harvesting"},
	"chop":    {"need": "", "sources": ["Nature/tree", "Nature/pine"],
				"seconds": 5.0, "anim": "chop", "refill": 0.0,
				"gives": {"wood": 2}, "morality": 0.0, "verb": "chopping"},
	"forage":  {"need": "", "sources": ["Nature/bush"],
				"seconds": 3.0, "anim": "pickup", "refill": 0.0,
				"gives": {"food": 1}, "morality": 0.01, "verb": "foraging"},
}

## Work the village does for itself rather than to fill a bar. These are the
## ones favour steers, and the only ones blessing can encourage.
const WORK := ["harvest", "chop", "forage"]

var name := "Someone"
var stats: Dictionary = {}
var personality: Personality
var memories: Memories
var rng := RandomNumberGenerator.new()

## -1 devil .. +1 saint. The RECORD of what they have done, not what the god
## thinks of them -- a follower punished unfairly is still a saint.
var morality := 0.0

## action id -> multiplier. The god's whole influence, in one dictionary.
var favour: Dictionary = {}

## What they are doing right now, and how far through it they are.
var action := ""
var action_left := 0.0
var target_id := ""

var thought := ""
var thought_log: Array[String] = []
var _thought_timer := 0.0

## Set by the social layer while a conversation is running.
var chatting_with := ""

## The last job actually COMPLETED. This is what blessing and punishment
## reinforce, which is why the god has to watch and time it rather than pick
## a behaviour from a menu.
var last_action := ""

var village = null                       ## Village, injected; may be null


func _init(seed_value: int) -> void:
	# Seeded per follower and NOT from the clock, so the village comes up the
	# same twice and a rendering change can be told apart from a different set
	# of errands.
	rng.seed = seed_value
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
	var base: float = DRAIN[key]
	match key:
		"hunger": return base * personality.appetite
		"energy": return base / maxf(0.35, personality.vigour)
		"social": return base * personality.sociability
		"hygiene": return base * personality.tidiness
		"faith": return base * (1.0 + personality.devotion * 0.5)
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


## --- deciding what to do ----------------------------------------------------

## Choose an action id, or "" to wander.
##
## Needs first, but only real ones; then work, weighted by favour and by what
## the village is short of. The ordering is the design: a follower will not
## chop wood while starving, and the god cannot make them, which is what keeps
## blessing an influence rather than a command.
func choose_action() -> String:
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
		var forced := _action_for_need(key)
		if forced != "":
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
		var want := _action_for_need(key)
		if want != "" and rng.randf() < 0.85:
			return want

	# Work. Weighted by favour (the god's influence) times village demand, so
	# a blessed woodcutter chops more AND the village still eats.
	var pool: Array[Dictionary] = []
	for a in WORK:
		var w: float = float(favour.get(a, 1.0)) * _demand(a)
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


func _action_for_need(key: String) -> String:
	for a in ACTIONS:
		if String(ACTIONS[a].get("need", "")) == key:
			return a
	return ""


## How much the village wants this work done. Keeps the economy honest: with a
## full granary, harvesting is nearly pointless and the followers drift to
## something else on their own.
func _demand(a: String) -> float:
	if village == null:
		return 1.0
	var gives: Dictionary = ACTIONS[a].get("gives", {})
	var want := 0.0
	for res in gives:
		want = maxf(want, village.shortage(String(res)))
	return 0.15 + want


## Where to go for `act`, as a walkable cell, or (-1,-1) if there is nowhere.
func destination_for(grid, from: Vector2i, act: String) -> Vector2i:
	if not ACTIONS.has(act):
		return grid.random_cell(rng)
	var sources: Array = ACTIONS[act]["sources"]
	var ranked: Array = []
	for aid in sources:
		for c in grid.cells_of(String(aid)):
			var cell: Vector2i = c
			ranked.append([absi(cell.x - from.x) + absi(cell.y - from.y), cell,
						   String(aid)])
	if ranked.is_empty():
		return Vector2i(-1, -1)
	ranked.sort_custom(func(a, b): return a[0] < b[0])

	# Among the nearest few, not the single nearest: two followers who share a
	# doorstep must not pick the same tree every time, forever.
	var span: int = mini(5, ranked.size())
	for i in span:
		var pick: int = rng.randi_range(0, mini(span, ranked.size()) - 1)
		var stand: Vector2i = grid.beside(ranked[pick][1], rng)
		if stand.x >= 0:
			target_id = String(ranked[pick][2])
			return stand
		ranked.remove_at(pick)
		if ranked.is_empty():
			break
	return Vector2i(-1, -1)


## Kept for the movement layer, which only wants somewhere to walk.
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
	action_left = float(spec["seconds"])
	return true


func _finish_action() -> void:
	var act := action
	action = ""
	if not ACTIONS.has(act):
		return
	var spec: Dictionary = ACTIONS[act]

	if village != null:
		var takes: Dictionary = spec.get("takes", {})
		if not takes.is_empty() and not village.take(takes):
			return                     # someone else got the last loaf
		var gives: Dictionary = spec.get("gives", {})
		if not gives.is_empty():
			village.give(gives)

	var need := String(spec.get("need", ""))
	if need != "":
		stats[need] = minf(1.0, float(stats[need]) + float(spec["refill"]))
	# Any completed job is a small comfort, which is why a busy village drifts
	# happier than an idle one even when nobody's bars are full.
	stats["fun"] = minf(1.0, float(stats["fun"]) + 0.06)

	var m := float(spec.get("morality", 0.0))
	if m != 0.0:
		shift_morality(m)
		memories.add(Memories.KIND_WORK, "Did honest work.", 0.35)
	last_action = act


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
		favour[act] = clampf(float(favour[act]) * (1.0 + 0.45 * strength),
							 0.15, 6.0)
	stats["faith"] = minf(1.0, float(stats["faith"]) + 0.45 * strength)
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
	stats["faith"] = maxf(0.0, float(stats["faith"]) - 0.25 * strength)
	stats["health"] = maxf(0.05, float(stats["health"]) - 0.30 * strength)
	stats["fun"] = maxf(0.0, float(stats["fun"]) - 0.3 * strength)
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


func describe() -> String:
	var w: Array = worst_stat()
	return "%s (%s, %s) %s" % [name, personality.describe(),
		morality_label(), "%s %.0f%%" % [STAT_LABEL[w[0]], float(w[1]) * 100.0]]
