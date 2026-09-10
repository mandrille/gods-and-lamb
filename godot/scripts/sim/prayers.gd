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

signal opened(prayer: Prayer)
signal closed(prayer: Prayer, answered: bool)

var host = null
var village = null
var divinity = null

var active: Array[Prayer] = []
var _next_look: Dictionary = {}    ## instance id -> village time
var _cooldown: Dictionary = {}     ## instance id -> village time
var _rng := RandomNumberGenerator.new()


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


## --- closing ----------------------------------------------------------------

func _close(now: float) -> void:
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


## THE PAYOUT, and it goes through `Divinity.perform` like everything else so it
## picks up the aggregated feedback, the reputation and the reaction for free.
func _thank(p: Prayer) -> void:
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
	var paid: float = ANSWERED_FAITH * divinity.boons.prayer_payout()
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
