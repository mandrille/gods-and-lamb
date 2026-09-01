extends RefCounted
class_name Thoughts

## What a follower is thinking, in words.
##
## Every line has to be CAUSED by something the simulation actually knows --
## a stat that is low, a memory that is still warm, the job in hand, the way
## the god has been treating them. A random line from a big list would read as
## flavour for about a minute and then as noise, because the player would
## notice it never matches what they can see in the panel right above it.
##
## So the generator is a set of sources, each of which either fires with a
## reason or declines. It picks among the ones that fired, weighted by how
## strongly they fired, which means the loudest thing in a follower's life is
## usually but not always what they say. Always picking the loudest would make
## them robots reciting their worst stat.

const NEED_LINES := {
	"hunger": [
		"My stomach will not stop complaining.",
		"I would trade a great deal for a hot meal.",
		"Was I always this hungry, or is it new?",
	],
	"energy": [
		"My legs have opinions about all this walking.",
		"I could sleep standing up.",
		"Just a short rest. That is all I ask.",
	],
	"social": [
		"Nobody has said a word to me all day.",
		"I miss the sound of somebody else talking.",
		"I have started narrating my own chores.",
	],
	"faith": [
		"Is anyone up there listening?",
		"I have not felt watched over in some time.",
		"Perhaps I should pray, if only to be sure.",
	],
	"health": [
		"Something is not right with me.",
		"I ache in places I did not know I had.",
		"I should sit down before I fall down.",
	],
	"hygiene": [
		"I think I stink...",
		"I would not sit next to me either.",
		"There is a river RIGHT THERE, and yet.",
	],
	"fun": [
		"Every day is the same shape.",
		"I would like something to happen. Anything.",
		"I have counted the fence posts twice now.",
	],
}

## Said while a job is actually in hand, so the line and the animation agree.
const WORK_LINES := {
	"eat": ["That is better. That is much better.",
			"Slowly. Make it last."],
	"sleep": ["Do not wake me.", "Five more minutes."],
	"chop": ["One more swing. Maybe two.",
			 "The wood will be worth it.",
			 "My shoulders are going to regret this."],
	"harvest": ["The wheat is coming in well.",
				"Bend, pull, stand. Bend, pull, stand."],
	"build": ["It will stand up. Probably.",
			  "Measure once, hope twice."],
	"wash": ["Cold. Very cold. Worth it.",
			 "That is the smell gone, at least."],
	"pray": ["I am listening, if you are.",
			 "Thank you. I think."],
	"talk": ["Go on, then, tell me the rest.",
			 "I have been waiting all day for this."],
	"play": ["Ha! Again!", "This is the good part of the day."],
}

const IDLE_LINES = [
	"It is a fine day for it.",
	"I should be doing something.",
	"The island is smaller than it looks.",
	"I wonder what is over the water.",
]


## Build one thought. Returns "" only if the follower has literally nothing to
## say, which should not happen -- the idle source always fires.
static func compose(brain, rng: RandomNumberGenerator) -> String:
	var pool: Array[Dictionary] = []

	# 1. The worst need, if it is actually bad. Weighted by how bad, so a
	#    starving follower talks about food far more often than a peckish one.
	var worst := ""
	var worst_lack := 0.0
	for key in brain.stats:
		var lack: float = 1.0 - float(brain.stats[key])
		if lack > worst_lack:
			worst_lack = lack
			worst = key
	if worst != "" and worst_lack > 0.45 and NEED_LINES.has(worst):
		var lines: Array = NEED_LINES[worst]
		pool.append({"w": worst_lack * 3.0,
					 "t": lines[rng.randi_range(0, lines.size() - 1)]})

	# 2. The job in hand.
	if brain.action != "" and WORK_LINES.has(brain.action):
		var wl: Array = WORK_LINES[brain.action]
		pool.append({"w": 1.4, "t": wl[rng.randi_range(0, wl.size() - 1)]})

	# 3. The memory still weighing on them. This is where the complex ones
	#    come from -- a line that names another follower and refers to a thing
	#    that actually happened between them.
	var mem: Dictionary = brain.memories.strongest()
	if not mem.is_empty() and float(mem["heat"]) > 0.25:
		var line := _from_memory(mem, brain, rng)
		if line != "":
			pool.append({"w": float(mem["heat"]) * 2.6, "t": line})

	# 4. How the god has been treating them.
	var standing: float = brain.memories.divine_standing()
	if absf(standing) > 0.3:
		pool.append({"w": absf(standing) * 1.8,
					 "t": _about_god(standing, brain, rng)})

	# 5. Personality, occasionally, so the tags are audible and not just
	#    printed on the panel.
	if not brain.personality.tags.is_empty() and rng.randf() < 0.5:
		var tag: String = brain.personality.tags[
			rng.randi_range(0, brain.personality.tags.size() - 1)]
		var tl := _from_tag(tag, rng)
		if tl != "":
			pool.append({"w": 0.9, "t": tl})

	# 6. Always something.
	pool.append({"w": 0.6,
				 "t": IDLE_LINES[rng.randi_range(0, IDLE_LINES.size() - 1)]})

	return _weighted(pool, rng)


static func _from_memory(mem: Dictionary, brain,
						 rng: RandomNumberGenerator) -> String:
	var who := String(mem["other"])
	var good: bool = float(mem["valence"]) >= 0.0
	var kind := String(mem["kind"])

	if kind == Memories.KIND_SOCIAL and who != "":
		if good:
			return ["I am glad %s came over.",
					"%s is easy to talk to.",
					"I should find %s again later."][rng.randi_range(0, 2)] % who
		# The "I should not have said that" case the design asked for, and its
		# mirror -- whether this follower blames themselves or the other one
		# depends on who they are, which is what kindness is FOR.
		if brain.personality.kindness >= 0.0:
			return ["I should not have said that to %s.",
					"I keep replaying what I said to %s.",
					"%s did not deserve that from me."][rng.randi_range(0, 2)] % who
		return ["%s had that coming.",
				"I have nothing more to say to %s.",
				"%s started it, whatever they claim."][rng.randi_range(0, 2)] % who

	if kind == Memories.KIND_LOSS:
		return ["It was there yesterday. Now it is not.",
				"We lost something we could not spare."][rng.randi_range(0, 1)]

	if kind == Memories.KIND_WORK and good:
		return ["I did good work today.",
				"That was worth the ache."][rng.randi_range(0, 1)]

	return ""


static func _about_god(standing: float, brain,
					   rng: RandomNumberGenerator) -> String:
	if standing > 0.0:
		if brain.personality.devotion > 0.2:
			return ["We are watched over. I am sure of it.",
					"Every good thing lately came from above."][rng.randi_range(0, 1)]
		return ["Something is looking out for us. Odd.",
				"I will take the luck, whoever is sending it."][rng.randi_range(0, 1)]
	if brain.personality.devotion > 0.2:
		return ["What did we do to deserve this?",
				"I must have offended something."][rng.randi_range(0, 1)]
	return ["I do not like the way the sky has been behaving.",
			"Somebody up there has it in for me."][rng.randi_range(0, 1)]


static func _from_tag(tag: String, rng: RandomNumberGenerator) -> String:
	var by_tag := {
		"Greedy": ["That could be mine.", "Nobody would miss just one."],
		"Gentle": ["I hope everyone is alright today.",
				   "There is enough to go round if we are careful."],
		"Lazy": ["Somebody else can do it.",
				 "I will start in a moment. A real moment."],
		"Devout": ["Praise where it is due.", "The shrine could use tending."],
		"Brave": ["I would go over the water, given a boat.",
				  "Nothing out there frightens me."],
		"Gloomy": ["It will probably rain.", "This will end badly, watch."],
		"Cheerful": ["What a morning!", "Things are looking up, I say."],
		"Proud": ["I do it properly or not at all.",
				  "Let them watch how it is done."],
		"Shy": ["I hope nobody asks me anything.",
				"I will just be over here."],
		"Glutton": ["Is it time to eat again? It might be.",
					"I could eat. I could always eat."],
	}
	if not by_tag.has(tag):
		return ""
	var lines: Array = by_tag[tag]
	return lines[rng.randi_range(0, lines.size() - 1)]


static func _weighted(pool: Array[Dictionary],
					  rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for p in pool:
		total += float(p["w"])
	if total <= 0.0:
		return ""
	var roll := rng.randf() * total
	for p in pool:
		roll -= float(p["w"])
		if roll <= 0.0:
			return String(p["t"])
	return String(pool[pool.size() - 1]["t"])
