extends Node
class_name Prayers

## Who is asking, and whether anybody answered.
##
## Three jobs, and the third is the interesting one:
##
##   1. NOTICE when somebody's need has got bad enough to say something.
##   2. STOP when it is fine again -- however it got fine.
##   3. Work out whether the GOD did it, which is what decides the payout, and
##      answer that from the witness list rather than from timing. `Divinity`
##      already reports exactly who saw each act and what kind of act it was, so
##      "did a FOOD act happen where Mara could see it while she was hungry" is
##      a question the game can already answer precisely.
##
## Rule three is what keeps this honest. A villager who wanders off and finds a
## bush has still had their prayer answered -- by themselves -- and the prayer
## goes away quietly with no reward and no penalty. The player is a god, not
## customer support.

## Never more than this on screen at once. A player looking at twenty prayer
## bubbles is a player reading a task list, and the moment it reads as a task
## list they are obliged to clear it.
const MAX_ACTIVE := 3
## Except for desperate ones, which may exceed it -- somebody actually starving
## should not be silenced because three people are peckish.
const MAX_URGENT_EXTRA := 2

## A villager who has just prayed does not pray again for a while, whatever
## happens. Without this a hunger bar hovering on the threshold produces a
## prayer every few seconds from the same person.
const COOLDOWN := 95.0

## How often one villager is considered. Staggered by instance id so the whole
## village is never evaluated on the same frame.
const EVERY := 2.5

## What answering is worth to the person who asked. Far above a blessing's 3.0,
## and that gap is the point: this is the loop the design wants the player to
## graduate into.
const ANSWERED_FAITH := 22.0
## And a little to everyone who saw it happen, because a god who answers
## prayers is a god worth believing in even if it was not your prayer.
const ANSWERED_WITNESS_RADIUS := 9.0

## WHICH JOBS WANT WHICH THING FROM THE GROUND. The village already sorts
## itself into people who take from the land and people who live off what grows
## on it, and it has never once mattered. This is the seam where it does.
const CLEARERS := ["lumberjack", "miner", "builder"]
const GROWERS := ["adventurer", "hunter", "bard", "nurse", "villager"]

## A feud is rare on purpose. It asks the player to disappoint somebody, and a
## game that asks that every ninety seconds is a game about disappointing
## people. It also needs a village big enough that both camps exist.
const FEUD_EVERY := 240.0
const FEUD_MIN_FOLK := 6
## How far apart the two of them may be and still be arguing about the same
## field. Inside the witness radius, so any act either sees, both see -- which
## is what makes the tag, rather than the aim, the thing that decides it.
const FEUD_NEAR := 8.0
## What taking a side is worth to the one whose side you took. Above an
## ordinary answered prayer: this one cost somebody else something.
const FEUD_FAITH := 30.0

signal opened(prayer: Prayer)
signal closed(prayer: Prayer, answered: bool)
## One side won and the other did not. Separate from `closed` because the
## interesting thing about a feud is not that it ended.
signal took_sides(won: Prayer, lost: Prayer)

var host = null
var village = null
var divinity = null

var active: Array[Prayer] = []
var _next_look: Dictionary = {}    ## instance id -> village time
var _cooldown: Dictionary = {}     ## instance id -> village time
var _rng := RandomNumberGenerator.new()
var _feud_at := -1.0               ## village time of the last argument


func _init() -> void:
	_rng.seed = 20260901


func listen() -> void:
	if divinity != null:
		divinity.witnessed.connect(_saw)


## A divine act resolved. Anybody with a standing prayer who SAW an act of the
## matching kind has had it answered -- stamped here rather than resolved here,
## because the need itself still has to recover. Dropping an apple at somebody's
## feet is not the same as them having eaten it.
func _saw(r: Dictionary) -> void:
	var tags: int = int(r.get("tags", 0))
	if tags == 0:
		return
	for h in (r.get("hits", []) as Array):
		var f = h[0]
		for p in active:
			if p.who == f and tags & int(p.spec().get("tag", 0)) != 0:
				p.touched_by_god = true


func tick(_delta: float) -> void:
	if host == null or village == null:
		return
	var now := float(village.now)
	_close(now)
	_open(now)
	_open_feud(now)


## --- closing ----------------------------------------------------------------

func _close(now: float) -> void:
	# FEUDS FIRST, and separately, because closing one closes two -- walking the
	# ordinary list and erasing a rival out from under it is how a loop like
	# this ends up skipping an entry.
	for p in active.duplicate():
		if not p.feud() or not p.touched_by_god or not active.has(p):
			continue
		_settle(p, now)

	for p in active.duplicate():
		if not p.alive(now):
			# Gave up, or died. No penalty: the design is explicit that
			# ignoring a prayer is a valid thing for a god to do.
			active.erase(p)
			closed.emit(p, false)
			continue
		if not p.met(host):
			continue
		active.erase(p)
		if p.touched_by_god:
			_thank(p)
		closed.emit(p, p.touched_by_god)


## THE GOD TOOK A SIDE.
##
## Both prayers end here. The one whose tag was matched is thanked and paid; the
## other is DENIED, which is not the same as ignored -- ignoring a prayer is a
## thing the design says a god may do, and the villager never knows whether they
## were heard. Being denied means watching the answer go to the person standing
## next to you.
##
## There is no faith penalty for it. The cost is a memory, and the memory is the
## honest cost: their opinion of you drops because of something you did, and it
## is a memory of the god so it does not fade away in ninety seconds like an
## opinion about the weather.
func _settle(won: Prayer, now: float) -> void:
	var lost = won.rival
	active.erase(won)
	won.rival = null
	_thank(won, FEUD_FAITH)
	closed.emit(won, true)

	if lost == null or not active.has(lost):
		return
	active.erase(lost)
	lost.rival = null
	lost.denied = true
	_cooldown[lost.who.get_instance_id()] = now + COOLDOWN
	if is_instance_valid(lost.who) and lost.who.brain != null:
		# -0.5 AND NOT MORE. `divine_standing` SUMS its memories rather than
		# averaging them, so this number lands on their opinion whole -- and at
		# -0.7 a single denial was very nearly `smite`'s -0.8, which is what a
		# villager feels watching you level a wood. Turning somebody down is
		# not that. It should clearly cost something and clearly not be the
		# worst thing you have ever done to them.
		lost.who.brain.memories.add(Memories.KIND_PUNISHMENT,
								    "You heard them, and not me.", -0.5, "",
								    1.0 + lost.who.brain.personality.devotion)
	closed.emit(lost, false)
	took_sides.emit(won, lost)


## --- the argument -----------------------------------------------------------

## Start one, if the village is big enough to have two opinions in it.
func _open_feud(now: float) -> void:
	if _feud_at > 0.0 and now - _feud_at < FEUD_EVERY:
		return
	if host.folk.size() < FEUD_MIN_FOLK:
		return
	for p in active:
		if p.feud():
			return
	var clearer = _pick(CLEARERS, now, null)
	if clearer == null:
		return
	var grower = _pick(GROWERS, now, clearer)
	if grower == null:
		return
	_feud_at = now
	var a := Prayer.new("quarry", clearer, now)
	var b := Prayer.new("grove", grower, now)
	a.rival = b
	b.rival = a
	for p in [a, b]:
		active.append(p)
		_cooldown[p.who.get_instance_id()] = now + COOLDOWN
		opened.emit(p)


## Somebody with one of these jobs, free to speak, and near `beside` if given.
func _pick(jobs: Array, now: float, beside):
	var found: Array = []
	for f in host.folk:
		if not is_instance_valid(f) or f.brain == null or not f.brain.adult:
			continue
		if not (String(f.brain.job) in jobs):
			continue
		if now < float(_cooldown.get(f.get_instance_id(), 0.0)):
			continue
		if _has_prayer(f):
			continue
		if beside != null and f.position.distance_to(beside.position) > FEUD_NEAR:
			continue
		found.append(f)
	if found.is_empty():
		return null
	return found[_rng.randi() % found.size()]


## THE PAYOUT, and it goes through `Divinity.perform` like everything else so it
## picks up the aggregated feedback, the reputation and the reaction for free.
func _thank(p: Prayer, base := ANSWERED_FAITH) -> void:
	if divinity == null or not is_instance_valid(p.who):
		return
	var a := DivineAction.make("answered", p.who.position, 0.0,
							   ANSWERED_WITNESS_RADIUS)
	a.tags = int(p.spec().get("tag", 0))
	a.verb = "A prayer is answered."
	a.subject = p.who
	a.why = "prayer"
	# The requester's share is paid directly rather than through the witness
	# sweep, because it is not about who was nearby -- it is theirs.
	# WHAT ANSWERING IS WORTH, and the two boons that change it. Mercy is only
	# for the ones that were actually dire -- pulling somebody out of a fire is
	# a different thing from handing somebody an apple, and the boon should
	# know the difference.
	var paid: float = base * divinity.boons.prayer_payout()
	if p.urgent:
		paid *= divinity.boons.mercy()
	p.who.brain.gain_faith(paid)
	p.who.brain.memories.add(Memories.KIND_MIRACLE,
							 "I asked, and it came.", 0.95, "",
							 1.0 + p.who.brain.personality.devotion)
	# A smaller share for the onlookers, via the normal path.
	a.weight = 3.0
	divinity.perform(a)


## --- opening ----------------------------------------------------------------

func _open(now: float) -> void:
	var urgent_count := 0
	for p in active:
		if p.urgent:
			urgent_count += 1
	var room: int = MAX_ACTIVE - active.size()
	var urgent_room: int = MAX_ACTIVE + MAX_URGENT_EXTRA - active.size()
	if urgent_room <= 0:
		return

	for f in host.folk:
		if not is_instance_valid(f) or f.brain == null or not f.brain.adult:
			continue
		var id: int = f.get_instance_id()
		if now < float(_next_look.get(id, 0.0)):
			continue
		# Staggered, so the village is never all evaluated on one frame.
		_next_look[id] = now + EVERY + _rng.randf() * EVERY
		if now < float(_cooldown.get(id, 0.0)):
			continue
		if _has_prayer(f):
			continue
		var made := _consider(f, now, room > 0)
		if made == null:
			continue
		active.append(made)
		_cooldown[id] = now + COOLDOWN
		opened.emit(made)
		if not made.urgent:
			room -= 1
		urgent_room -= 1
		if urgent_room <= 0:
			return


## Would this villager say something? Returns a Prayer or null.
func _consider(f, now: float, has_room: bool) -> Prayer:
	for kind in Prayer.KINDS:
		var row: Dictionary = Prayer.KINDS[kind]
		# Feuds are dealt in pairs by `_open_feud` and never one at a time. A
		# single half of an argument is a prayer with no answer condition at
		# all, which would stand for its full ninety seconds and then lapse.
		if bool(row.get("feud", false)):
			continue
		var desperate := false
		if bool(row.get("danger", false)):
			# NOT A STAT. Somebody standing next to a fire is in trouble
			# whatever their hunger bar says, and this is always desperate --
			# there is no mild version of the treeline being alight.
			if not Prayer.near_danger(f, host):
				continue
			desperate = true
		else:
			var level: float = float(f.brain.stats.get(
				String(row["need"]), 1.0))
			if level >= Brain.URGENT:
				continue
			desperate = level < Brain.DESPERATE
		if not desperate and not has_room:
			continue
		# THE DEVOUT ASK MORE READILY, and a sceptic asks only when it is bad.
		# Same roll `_temptation` already uses for the other direction, so this
		# is characterisation the game had and was not spending.
		var faith: float = f.brain.devotion()
		var lean: float = 0.30 + 0.45 * faith \
			+ 0.25 * f.brain.personality.devotion
		if desperate:
			lean = maxf(lean, 0.85)
		if _rng.randf() > lean:
			continue
		return Prayer.new(String(kind), f, now, desperate)
	return null


func _has_prayer(f) -> bool:
	for p in active:
		if p.who == f:
			return true
	return false


func of(f) -> Prayer:
	for p in active:
		if p.who == f:
			return p
	return null
