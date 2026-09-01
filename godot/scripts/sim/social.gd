extends RefCounted
class_name Social

## Followers stopping to talk to each other.
##
## The visible half is small -- two of them stand still, face each other and
## show a speech icon -- but it is the only place in the game where followers
## affect each OTHER, so it is where relationships come from. A conversation
## writes a memory into both parties, and the memory it writes depends on who
## they are and what they already think of one another.
##
## Pairing is done centrally rather than by each follower looking around,
## because two followers independently deciding to talk to each other is a
## race: both walk over, both wait for the other to start, neither does. One
## matchmaker per frame owns the decision and hands each pair the same verdict.

signal chat_started(a, b)
## Two villagers who are well, fed and fond of each other. The HOST decides
## whether there is room and where the child stands -- the social layer knows
## about people, not about the map.
signal child_wanted(a, b)
signal chat_ended(a, b, verdict: String)

const RANGE := 2.2               ## metres; roughly two tiles
const DURATION := 4.5
const COOLDOWN := 26.0            ## before the same follower will chat again
## Per good conversation between two willing parents. Low: this fires often
## enough to matter over a session and rarely enough that a happy village does
## not double in a minute.
const BIRTH_CHANCE := 0.18

## A conversation goes one of three ways, and which one is not random -- it is
## the two personalities plus their history. That is the whole point: a cruel
## follower and someone who already resents them will not have a nice time.
const GOOD := "good"
const DULL := "dull"
const BAD := "bad"

var pairs: Array[Dictionary] = []      ## [{a, b, left, verdict}]
var _cool: Dictionary = {}             ## follower -> seconds until available
var rng := RandomNumberGenerator.new()


func _init(seed_value := 4242) -> void:
	rng.seed = seed_value


## `folk` is an Array of Follower nodes. Called once per frame by the host.
func tick(delta: float, folk: Array) -> void:
	for k in _cool.keys():
		_cool[k] = float(_cool[k]) - delta
		if float(_cool[k]) <= 0.0:
			_cool.erase(k)

	var still_going: Array[Dictionary] = []
	for p in pairs:
		p["left"] = float(p["left"]) - delta
		var a = p["a"]
		var b = p["b"]
		if not is_instance_valid(a) or not is_instance_valid(b):
			continue
		if float(p["left"]) > 0.0:
			# Hold them facing each other for the duration. POSITIONS, not
			# nodes: _face takes a point, and passing the node typed-errors
			# once per pair per frame -- loud, but only at runtime.
			_face(a, b.position)
			_face(b, a.position)
			still_going.append(p)
		else:
			_resolve(p)
	pairs = still_going

	_match(folk)


func _match(folk: Array) -> void:
	for i in folk.size():
		var a = folk[i]
		if not _available(a):
			continue
		for j in range(i + 1, folk.size()):
			var b = folk[j]
			if not _available(b):
				continue
			if a.position.distance_to(b.position) > RANGE:
				continue
			# BOTH have to want it, not either. With fifty villagers on one
			# plot somebody always wanted a chat, and conversation took a fifth
			# of the whole village's day -- an `or` here is effectively "stop
			# every pair that passes".
			if not (_wants(a) and _wants(b)):
				continue
			_start(a, b)
			break


func _available(f) -> bool:
	if not is_instance_valid(f) or f.brain == null:
		return false
	if f.brain.chatting_with != "":
		return false
	if _cool.has(f):
		return false
	# Not while mid-job: interrupting a chop to gossip loses the work and looks
	# like the animation glitched.
	return f.brain.action == ""


func _wants(f) -> bool:
	return float(f.brain.stats["social"]) < 0.55


func _start(a, b) -> void:
	a.brain.chatting_with = b.brain.name
	b.brain.chatting_with = a.brain.name
	a.stop_and_face(b.position)
	b.stop_and_face(a.position)
	pairs.append({"a": a, "b": b, "left": DURATION,
				  "verdict": _verdict(a.brain, b.brain)})
	chat_started.emit(a, b)


## Which way it goes. Kindness makes a good conversation likely; an existing
## grudge makes a bad one likelier still, which is how feuds sustain themselves
## without anything in the code being called "a feud".
func _verdict(x, y) -> String:
	# Annotated, not inferred: `x` and `y` are untyped (they are Brains reached
	# through untyped Follower refs), so every expression off them is Variant
	# and `:=` on it is a parse error rather than something found at runtime.
	var warmth: float = (float(x.personality.kindness)
						 + float(y.personality.kindness)) * 0.5
	var history: float = (float(x.memories.opinion_of(y.name))
						  + float(y.memories.opinion_of(x.name))) * 0.5
	var score: float = (warmth * 0.6 + history * 0.8
						+ rng.randf_range(-0.45, 0.45))
	if score > 0.22:
		return GOOD
	if score < -0.25:
		return BAD
	return DULL


func _resolve(p: Dictionary) -> void:
	var a = p["a"]
	var b = p["b"]
	if not is_instance_valid(a) or not is_instance_valid(b):
		return
	var verdict := String(p["verdict"])
	_apply(a.brain, b.brain, verdict)
	_apply(b.brain, a.brain, verdict)
	a.brain.chatting_with = ""
	b.brain.chatting_with = ""
	_cool[a] = COOLDOWN
	_cool[b] = COOLDOWN
	a.resume()
	b.resume()
	chat_ended.emit(a, b, verdict)
	# A child comes out of a GOOD conversation between two people in a state to
	# raise one. This is the only way the population grows from inside, and it
	# is deliberately downstream of everything else: a hungry, miserable or
	# lonely village does not have children, so growth is a SYMPTOM of the
	# player looking after them rather than a button.
	if verdict == GOOD and a.brain.can_parent() and b.brain.can_parent() 			and rng.randf() < BIRTH_CHANCE:
		child_wanted.emit(a, b)


func _apply(me, them, verdict: String) -> void:
	match verdict:
		GOOD:
			me.stats["social"] = minf(1.0, float(me.stats["social"]) + 0.55)
			me.stats["fun"] = minf(1.0, float(me.stats["fun"]) + 0.18)
			me.memories.add(Memories.KIND_SOCIAL,
				"A good talk with %s." % them.name, 0.6, them.name,
				me.personality.memory_weight(0.6))
			me.shift_morality(0.01)
		DULL:
			me.stats["social"] = minf(1.0, float(me.stats["social"]) + 0.30)
			me.memories.add(Memories.KIND_SOCIAL,
				"Passed the time with %s." % them.name, 0.12, them.name,
				me.personality.memory_weight(0.12))
		BAD:
			me.stats["social"] = minf(1.0, float(me.stats["social"]) + 0.12)
			me.stats["fun"] = maxf(0.0, float(me.stats["fun"]) - 0.15)
			me.memories.add(Memories.KIND_SOCIAL,
				"Words with %s." % them.name, -0.55, them.name,
				me.personality.memory_weight(-0.55))
			# A cruel word costs the SPEAKER their standing, not the target's.
			# Unkind followers drift toward the devil end on their own.
			me.shift_morality(-0.03 if me.personality.kindness < 0.0 else -0.01)
	me.think_aloud()


func _face(who, at: Vector3) -> void:
	# Annotated: `who` is untyped, so `who.position` is Variant and the
	# subtraction has no static type.
	var d: Vector3 = at - who.position
	d.y = 0.0
	if d.length_squared() > 0.0001:
		# +Z forward, matching the mesh convention -- see Follower.
		who.rotation.y = atan2(d.x, d.z)


func active_count() -> int:
	return pairs.size()
