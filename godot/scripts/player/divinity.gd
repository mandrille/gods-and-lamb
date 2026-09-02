extends Node
class_name Divinity

## Everything the player can do, and the Faith it costs.
##
## The design rule this whole file exists to respect: THE GOD CANNOT GIVE
## ORDERS. There is no build button and no harvest button. What the god has is
## approval -- bless a follower who just did something and they will do it more,
## punish them and they will do it less -- plus miracles that change the WORLD
## and let the villagers react to it. Every power below is one of those two
## shapes, and anything that would amount to direct control does not belong
## here no matter how convenient it would be.
##
## Faith comes from the villagers, not from a timer. A god with no followers
## earns nothing, which is what makes the population cap a real constraint
## rather than a number on a panel.

signal faith_changed(amount: float)
signal card_drawn(card: Dictionary)
## Emitted whenever the HAND changes for any reason -- drawn, played, spent.
## The HUD listens to this rather than to card_drawn alone, because a card
## played by anything other than its own button would otherwise leave a dead
## button on screen that casts an empty index.
signal hand_changed()
signal miracle_cast(id: String, at: Vector3)
signal judged(who, good: bool)          ## bless or punish landed on a follower
signal smote(at: Vector3, radius: float, destroyed: int)
signal island_bought(slot: Vector2i)
signal notice(text: String)             ## one line for the player, for the HUD
## Faith arrived, and WHERE. The HUD flies a token from there to the counter,
## which is the only thing that makes the economy legible.
signal earned(amount: float, at: Vector3, why: String)
signal combo_changed(chain: int, mult: float)
## Three boons to choose between. The UI shows them; nothing happens until
## `take_boon` is called, so a draft can be left open.
signal draft_offered(options: Array, source: String)
signal boon_taken(id: String, rank: int)
signal age_reached(index: int, name: String)

## Faith per second per follower, scaled by how devout and how content they
## are. Small: the numbers below are balanced against minutes, not seconds.
## Faith is EARNED, and it is earned from things the player can see happen.
##
## The passive trickle is the floor -- an idle player still climbs. Work and
## prayer are the body. A well-timed blessing is the top earner, but only by
## about +70% over a purely passive player: engagement should roughly 1.7x you,
## not 10x you, or the idle half of an idle game stops being a game.
## Measured, then raised. An idle run earned 386 Faith in ten minutes against
## an engaged run's 3837 -- a tenfold spread, where the design called for about
## 1.7x. A tenfold spread means the idle half of an idle game is not a game.
## The floor comes up and the ceiling comes down (see WITNESS_FAITH).
const FAITH_PER_FOLLOWER := 0.42
const CHILD_WEIGHT := 0.35              ## a toddler is not a devotee

## These two were DECLARED AND NEVER USED. The intent to pay Faith for work
## existed from the first draft and was never wired to anything, which is most
## of why the whole first ten minutes earned under 180 Faith.
const PRAYER_BONUS := 6.0
const WORK_BONUS := 1.5
const BUILD_BONUS := 6.0                ## raising something is worth more

## Judgement is FREE. It is the verb, not the purchase -- what it costs is
## attention, and a cooldown is the honest price for that.
const JUDGE_COOLDOWN := 2.5
const WITNESS_WINDOW := 4.0             ## seconds since they finished a job
## Lowered from 4.0 for the same reason. A perfectly-attentive player blessing
## on every 2.5 s cooldown lands ~190 of these in ten minutes, which was
## roughly 40% of the entire economy on its own.
const WITNESS_FAITH := 2.8
const COMBO_WINDOW := 6.0               ## seconds allowed between links
const COMBO_STEP := 0.35
const COMBO_CAP := 6

const SMITE_COST := 14.0

## A new card every this many seconds (item 8).
const DRAW_SECONDS := 10.0
const HAND_MAX := 5
## Both grow with the ages, so they are state rather than constants.
var HAND_MAX_NOW := HAND_MAX
var draw_seconds := DRAW_SECONDS

## The deck.
##
## THERE IS NO FERTILITY CARD. New villagers are not something the god buys:
## they are born to two people who are fed, well and fond of each other, or
## they arrive on their own when the village is worth joining. Both of those
## are things the player causes INDIRECTLY, which is the same rule that says
## the god cannot order a hut built.
##
## `icon` names a glyph in scripts/ui/icons.gd -- NOT an emoji:
## Godot's default font has none, so an emoji card renders as a hollow box on
## any machine without an emoji font installed.
##
## `target` says what the card needs before it can be played:
##   "none"    cast immediately, affects the whole village
##   "ground"  the player picks a spot
##   "folk"    the player picks a villager
const DECK := [
	{"id": "grove", "name": "Grove", "icon": "tree", "target": "ground",
	 "desc": "Trees rise from bare ground."},
	{"id": "bounty", "name": "Bounty", "icon": "wheat", "target": "none",
	 "desc": "The granary fills."},
	{"id": "rain", "name": "Rain", "icon": "rain", "target": "none",
	 "desc": "Everyone is washed clean, and the crops drink."},
	{"id": "feast", "name": "Feast", "icon": "apple", "target": "none",
	 "desc": "Nobody goes hungry tonight."},
	{"id": "mend", "name": "Mend", "icon": "heart", "target": "folk",
	 "desc": "Health and vigour restored."},
	{"id": "revel", "name": "Revel", "icon": "confetti", "target": "none",
	 "desc": "Spirits lift across the island."},
	{"id": "calm", "name": "Calm", "icon": "dove", "target": "none",
	 "desc": "Grudges soften. Old wounds cool."},
	# Stone is the scarcer resource and Grove had no counterpart for it, so a
	# village that quarried itself out had no way back.
	{"id": "upheaval", "name": "Upheaval", "icon": "stone", "target": "ground",
	 "desc": "Stone breaks through the soil."},
]

var faith := 25.0
var hand: Array[Dictionary] = []
var _draw_timer := DRAW_SECONDS
## Said once per full-hand state, not once per attempt.
var _said_full := false

## Judgement state. `bless_radius` is 0 until a boon widens it -- the code path
## is here from the start so the boon is a number and not a new mechanic.
var judge_cd := 0.0
var bless_radius := 0.0
var combo_chain := 0
var combo_left := 0.0
var _combo_last = null                  ## the villager who made the last link
var witnessed_total := 0
var total_earned := 0.0

## The god's permanent powers, and what the next draft costs.
##
## Rising, so early drafts are frequent and late ones are decisions. Land and
## Commune competing for the same Faith is the standing choice of a run.
const COMMUNE_BASE := 55.0
const COMMUNE_GROWTH := 1.5
var boons: Boons
var drafts_taken := 0
var pending_draft: Array = []

## THE AGES.
##
## What gives ten minutes a shape. Each one is a visible arrival -- a lump of
## Faith, a free draft, and something new in the deck -- and each is triggered
## by the village doing something rather than by a clock, so it is earned.
##
## Age I gating the altar is load-bearing: on cost alone a player could afford
## their first boon at t=33 s, which is before they have understood what a
## boon is. Gated on the first building it lands at 70-95 s, right after they
## have watched their villagers earn something.
const AGES := [
	{"name": "The First Roof", "lump": 40.0, "cards": ["grove"],
	 "note": "Your people have a roof. You may Commune."},
	{"name": "The Watched Village", "lump": 90.0, "cards": ["rain", "feast"],
	 "note": "They know they are watched."},
	{"name": "The Shrine Age", "lump": 180.0,
	 "cards": ["mend", "revel", "calm", "upheaval"],
	 "note": "A shrine stands. The deepest gifts are open to you."},
]

## An age must be allowed to LAND before the next one starts.
##
## Two ages arriving in the same second is two lumps, two drafts and two
## notices on top of each other, and the player registers none of them. A
## minimum gap makes each one an event.
const AGE_GAP := 60.0
var _last_age_at := -999.0

var age := 0                             ## how many ages have PASSED
var unlocked_cards: Array[String] = ["bounty"]
var rng := RandomNumberGenerator.new()

## Injected by the scene root. Untyped because Divinity is built before some of
## them exist and a typed null is not more honest than an untyped one.
var host = null                          ## ValeRoot
var village = null
var islands = null
var builder = null
var grid = null


func _init() -> void:
	rng.seed = 20260901
	boons = Boons.new(20260901)


func _process(delta: float) -> void:
	if host == null:
		return
	var folk: Array = host.folk
	# Faith is EARNED, per follower, weighted by their own faith and mood. A
	# miserable village is a poor one, which is the pressure that makes
	# blessing worth spending on.
	var income := 0.0
	for f in folk:
		if not is_instance_valid(f) or f.brain == null:
			continue
		var devotion: float = float(f.brain.stats["faith"])
		var mood: float = (f.brain.mood() + 1.0) * 0.5
		var weight: float = 1.0 if f.brain.adult else CHILD_WEIGHT
		income += (FAITH_PER_FOLLOWER * boons.zeal() * weight
			* (0.35 + devotion * 0.65) * (0.4 + mood * 0.6))
	if income > 0.0:
		add_faith(income * delta)

	judge_cd = maxf(0.0, judge_cd - delta)
	if combo_left > 0.0:
		combo_left -= delta
		if combo_left <= 0.0:
			_break_combo()

	_check_age()
	# No cards before the first roof. At minute zero the only thing to do with
	# the hand would be to learn it, and there is already a village to watch.
	if age == 0:
		return
	_draw_timer -= delta
	if _draw_timer <= 0.0:
		# HOLD the draw, do not destroy it. The timer used to be reset before
		# the attempt, and draw_card bails on a full hand -- so a player
		# concentrating on the village lost a card every ten seconds and was
		# told about it six times a minute. Now the card arrives the instant a
		# slot opens.
		if hand.size() >= HAND_MAX_NOW:
			_draw_timer = 0.0
			if not _said_full:
				_said_full = true
				notice.emit("Your hand is full.")
		else:
			_draw_timer = draw_seconds
			_said_full = false
			draw_card()


func add_faith(amount: float) -> void:
	# GUARDED on positive: this is also called with negatives to pay for
	# things, and a lifetime-earned counter that costs count against it would
	# never reach an age threshold.
	if amount > 0.0:
		total_earned += amount
	faith = maxf(0.0, faith + amount)
	faith_changed.emit(faith)


## Faith for a completed job, scaled by effort and by how devout they are --
## an eight-second shrine build should outpay a three-second forage.
##
## Only WORK actions pay. If eating and resting paid, the need treadmill would
## become the economy and blessing would be rewarding nothing.
func on_work_done(who, act: String, spec: Dictionary) -> void:
	if not (act in Brain.WORK):
		return
	var devotion: float = float(who.brain.stats["faith"])
	var gain: float = (WORK_BONUS
		* (float(spec.get("seconds", 4.0)) / 4.0)
		* (0.6 + devotion * 0.8))
	if String(spec.get("builds", "")).begins_with("Buildings/"):
		gain += BUILD_BONUS
	add_faith(gain)
	earned.emit(gain, who.position, "work")


## A completed prayer. The direct payment is the smaller half -- praying lifts
## the faith stat, which is 65% of the passive multiplier, so a village that
## prays earns about a third more from everything else it does.
func on_prayer_done(who) -> void:
	var gain: float = PRAYER_BONUS * (0.7 + who.brain.personality.devotion * 0.6)
	add_faith(gain)
	earned.emit(gain, who.position, "prayer")


func can_afford(cost: float) -> bool:
	return faith >= cost


## --- cards ------------------------------------------------------------------

func draw_card() -> void:
	if hand.size() >= HAND_MAX_NOW:
		# A full hand stops drawing rather than discarding the oldest. Silently
		# binning a card the player was saving is the kind of thing they notice
		# only as "the game ate my miracle". The TIMER announces this now, once
		# per full-hand state -- saying it here said it on every attempt.
		return
	# From the UNLOCKED pool only, and rerolled once if it would be a third
	# copy of something already in hand -- a two-card pool otherwise deals the
	# same card five times and looks broken.
	var pool: Array[Dictionary] = []
	for c in DECK:
		if String(c["id"]) in unlocked_cards:
			pool.append(c)
	if pool.is_empty():
		return
	var card: Dictionary = pool[rng.randi_range(0, pool.size() - 1)].duplicate()
	var same := 0
	for h in hand:
		if String(h["id"]) == String(card["id"]):
			same += 1
	if same >= 2 and pool.size() > 1:
		card = pool[rng.randi_range(0, pool.size() - 1)].duplicate()
	hand.append(card)
	card_drawn.emit(card)
	hand_changed.emit()


## Play `index` from the hand. `at` is a world point for "ground" cards and
## `who` a Follower for "folk" cards; both are ignored otherwise.
func play(index: int, at := Vector3.ZERO, who = null) -> bool:
	if index < 0 or index >= hand.size():
		return false
	var card: Dictionary = hand[index]
	var kind := String(card["target"])
	if kind == "folk" and (who == null or not is_instance_valid(who)):
		notice.emit("%s needs a villager." % card["name"])
		return false
	if not _cast(String(card["id"]), at, who):
		return false
	hand.remove_at(index)
	_said_full = false
	hand_changed.emit()
	miracle_cast.emit(String(card["id"]), at)
	return true


func _cast(id: String, at: Vector3, who) -> bool:
	match id:
		"upheaval":
			var rocks := _scatter_prop("Nature/rock", at, 4)
			if rocks == 0:
				notice.emit("No open ground there.")
				return false
			_remember_all("The ground itself gave up stone.", 0.45)
			notice.emit("Stone breaks through.")
		"grove":
			var n := _grow_trees(at, 3)
			if n == 0:
				notice.emit("No open ground there.")
				return false
			_remember_all("The trees came from nowhere.", 0.5)
			notice.emit("A grove rises.")
		"bounty":
			village.give({"food": 8, "wood": 4})
			_remember_all("The stores filled themselves.", 0.55)
			notice.emit("The granary fills.")
		"rain":
			for f in host.folk:
				f.brain.stats["hygiene"] = 1.0
				f.brain.stats["health"] = minf(1.0,
					float(f.brain.stats["health"]) + 0.2)
			village.give({"food": 4})
			_remember_all("Rain, exactly when it was needed.", 0.45)
			notice.emit("Rain falls.")
		"feast":
			for f in host.folk:
				f.brain.stats["hunger"] = 1.0
				f.brain.stats["fun"] = minf(1.0,
					float(f.brain.stats["fun"]) + 0.3)
			# And it LEAVES something. A miracle that only plays a particle
			# burst is one the player has to take on trust; heaps of fruit on
			# the grass, which villagers then walk over and pick up, is one
			# they can watch work.
			var heaps := _scatter_prop("Nature/apples", at, 5)
			_remember_all("We ate until we could not.", 0.7)
			notice.emit("A feast. %d baskets left over." % heaps
						if heaps > 0 else "A feast.")
		"mend":
			who.brain.stats["health"] = 1.0
			who.brain.stats["energy"] = 1.0
			who.brain.memories.add(Memories.KIND_MIRACLE,
				"I was made whole again.", 0.9, "", 1.4)
			who.brain.think_aloud()
			notice.emit("%s is mended." % who.brain.name)
		"revel":
			for f in host.folk:
				f.brain.stats["fun"] = 1.0
				f.brain.stats["social"] = minf(1.0,
					float(f.brain.stats["social"]) + 0.5)
			_remember_all("What a night that was.", 0.6)
			notice.emit("The island celebrates.")
		"calm":
			# Cools every grudge without erasing the events. Memories are the
			# record; heat is how much they still sting. Deleting the entries
			# would rewrite history, and the panel would suddenly claim two
			# people who fought this morning had never met.
			for f in host.folk:
				for e in f.brain.memories.entries:
					if float(e["valence"]) < 0.0:
						e["heat"] = float(e["heat"]) * 0.25
			notice.emit("Old wounds cool.")
		_:
			return false
	return true


func _remember_all(text: String, valence: float) -> void:
	for f in host.folk:
		if is_instance_valid(f) and f.brain != null:
			f.brain.memories.add(Memories.KIND_MIRACLE, text, valence, "",
				1.0 + f.brain.personality.devotion)


## --- judgement --------------------------------------------------------------

## Approve of what this follower just did. The ONLY way the god steers work.
##
## FREE, and gated by a cooldown rather than by Faith. Blessing is the verb of
## this game; charging for the verb meant a player made about three of them in
## the first ten minutes. What it costs is ATTENTION.
##
## WITNESSED is the whole mechanic: blessing someone within WITNESS_WINDOW of
## them FINISHING a job pays Faith and extends a chain. Blessing someone idle
## still warms them -- favour, faith, a memory -- but pays nothing and breaks
## the chain. That is the difference between watching your village and clicking
## on it.
func bless(who) -> bool:
	if who == null or not is_instance_valid(who) or who.brain == null:
		return false
	if judge_cd > 0.0:
		return false
	judge_cd = JUDGE_COOLDOWN

	bless_radius = boons.bless_radius()
	var caught := _judge_area(who)
	var witnessed := 0
	for f in caught:
		if _is_witnessed(f):
			witnessed += 1
		f.brain.bless(1.0 if f == who else 0.6)

	if witnessed > 0:
		_extend_combo(who)
		# Scaled by how many of the caught had actually just DONE something,
		# with the exponent stopping a blob from printing Faith.
		var mult := 1.0 + boons.combo_step() * float(combo_chain - 1)
		var gain: float = (boons.witness_faith()
						   * pow(float(witnessed), 0.75) * mult)
		witnessed_total += witnessed
		add_faith(gain)
		earned.emit(gain, who.position + Vector3(0, 0.9, 0), "bless")
		notice.emit("%s is blessed for %s.%s"
			% [who.brain.name, who.brain.last_action,
			   "" if combo_chain < 2 else "  x%.2f" % mult])
	else:
		# Said plainly, because the lesson is TIMING and a silent nothing
		# teaches it slowly.
		_break_combo()
		notice.emit("%s felt the warmth, but had done nothing to earn it."
			% who.brain.name)
	judged.emit(who, true)
	return true


func punish(who) -> bool:
	if who == null or not is_instance_valid(who) or who.brain == null:
		return false
	if judge_cd > 0.0:
		return false
	judge_cd = JUDGE_COOLDOWN
	bless_radius = boons.bless_radius()
	for f in _judge_area(who):
		f.brain.punish(1.0 if f == who else 0.6)
	# Punishment never pays. It normally breaks the chain too -- a steering
	# tool with a real cost, not a second way to earn -- until Open Hand's
	# third rank, which makes correction part of the rhythm rather than an
	# interruption of it.
	if not boons.punish_keeps_chain():
		_break_combo()
	notice.emit("%s is struck down%s." % [who.brain.name,
		"" if who.brain.last_action == "" else " for " + who.brain.last_action])
	judged.emit(who, false)
	return true


## Everyone a judgement lands on. Just the target until a boon widens it, and
## the code path exists from the start so the boon is a number, not a mechanic.
func _judge_area(who) -> Array:
	var out: Array = [who]
	if bless_radius <= 0.0:
		return out
	for f in host.folk:
		if f == who or not is_instance_valid(f) or f.brain == null:
			continue
		if f.position.distance_to(who.position) <= bless_radius:
			out.append(f)
	return out


func _is_witnessed(f) -> bool:
	if f.brain.last_action == "" or village == null:
		return false
	return (float(village.now) - float(f.brain.last_action_at)
			<= boons.witness_window())


## A link needs a DIFFERENT villager than the last one. Otherwise the player
## parks on one worker and the mechanic is a metronome, not a search.
func _extend_combo(who) -> void:
	if who == _combo_last:
		combo_chain = maxi(1, combo_chain)
	else:
		combo_chain = mini(boons.combo_cap(), combo_chain + 1)
	_combo_last = who
	combo_left = COMBO_WINDOW
	combo_changed.emit(combo_chain,
					   1.0 + boons.combo_step() * float(combo_chain - 1))


func _break_combo() -> void:
	if combo_chain == 0:
		return
	combo_chain = 0
	combo_left = 0.0
	_combo_last = null
	combo_changed.emit(0, 1.0)


## --- wrath ------------------------------------------------------------------

## Destroy what stands in a circle: burn the trees, flatten the buildings.
##
## Area punishment (item 10). Everyone who can see it remembers it, and their
## opinion of the god drops whether or not they were the target -- which is the
## point. A god who levels a wood to make a point has made it to everybody.
func smite(at: Vector3, radius := 2.5) -> bool:
	if not can_afford(SMITE_COST):
		notice.emit("Not enough Faith to strike.")
		return false
	add_faith(-SMITE_COST)
	var destroyed := 0
	for entry in builder.placed_props.duplicate():
		var node = entry.get("node")
		if not is_instance_valid(node):
			continue
		var aid := String(entry["id"])
		# Bridges are spared on purpose: destroying one can strand an island
		# with villagers on it, and "the game let me make part of the map
		# unreachable" is a bug the player experiences as a bug.
		if aid == "Buildings/bridge":
			continue
		if node.position.distance_to(at) > radius:
			continue
		builder.remove_prop(entry)
		destroyed += 1
	if destroyed == 0:
		notice.emit("Nothing there to destroy.")
	else:
		notice.emit("%d things are destroyed." % destroyed)
		for f in host.folk:
			if not is_instance_valid(f) or f.brain == null:
				continue
			var near: bool = f.position.distance_to(at) < radius * 4.0
			f.brain.memories.add(Memories.KIND_LOSS,
				"I saw it all torn apart." if near
					else "Something was destroyed today.",
				-0.8 if near else -0.4, "",
				1.0 + f.brain.personality.devotion)
			f.brain.stats["faith"] = maxf(0.0,
				float(f.brain.stats["faith"]) - (0.35 if near else 0.15))
			f.brain.think_aloud()
	smote.emit(at, radius, destroyed)
	# The grid changes when props do: a felled tree opens a tile, and a
	# flattened cottage opens seven by seven of them.
	host.rebuild_grid()
	return true


## Drop `count` of something onto open ground near `at`. Returns how many
## landed, which may be fewer -- the caller says so rather than pretending.
func _scatter_prop(aid: String, at: Vector3, count: int) -> int:
	var origin: Vector3 = at
	if origin == Vector3.ZERO and host.folk.size() > 0:
		origin = host.folk[0].position
	var cell: Vector2i = grid.cell_of(origin)
	var made := 0
	for attempt in count * 20:
		if made >= count:
			break
		var c: Vector2i = cell + Vector2i(rng.randi_range(-5, 5),
										  rng.randi_range(-5, 5))
		if not grid.is_walkable(c):
			continue
		if builder.add_prop(aid, c.x, c.y, rng.randf_range(0.0, 360.0)):
			made += 1
	if made > 0:
		# Grid rebuild, so the new heaps are indexed and villagers can find
		# them. Skipping it leaves fruit nobody is able to notice.
		host.rebuild_grid()
	return made


func _grow_trees(at: Vector3, count: int) -> int:
	# Annotated: `grid` is injected untyped (Divinity is built before the grid
	# is rebuilt for the first time), so everything off it is Variant.
	var cell: Vector2i = grid.cell_of(at)
	var made := 0
	for attempt in count * 25:
		if made >= count:
			break
		var c: Vector2i = cell + Vector2i(rng.randi_range(-3, 3),
										  rng.randi_range(-3, 3))
		if not grid.is_walkable(c):
			continue
		var kind := "Nature/tree" if rng.randf() < 0.7 else "Nature/pine"
		if builder.add_prop(kind, c.x, c.y, rng.randf_range(0.0, 360.0)):
			made += 1
	if made > 0:
		host.rebuild_grid()
	return made


## --- ages -------------------------------------------------------------------

## Has the village earned the next age?
##
## Triggers are things the village DID, never a clock, so an age is an arrival
## and not a timer going off.
func _check_age() -> void:
	if age >= AGES.size() or village == null or host == null:
		return
	if float(village.now) - _last_age_at < AGE_GAP:
		return
	var ready := false
	match age:
		0:
			# Any building at all. The first roof.
			for aid in village.structures:
				if String(aid).begins_with("Buildings/") 						and String(aid) != "Buildings/bridge":
					ready = true
					break
		1:
			# Either way -- attention or growth. Both land in the same window,
			# which is what an OR is for.
			ready = witnessed_total >= 20 or host.folk.size() >= 4
		2:
			ready = (village.count_of("Buildings/shrine") > 0
					 and total_earned >= 500.0)
	if not ready:
		return

	var spec: Dictionary = AGES[age]
	age += 1
	_last_age_at = float(village.now)
	add_faith(float(spec["lump"]))
	for c in spec["cards"]:
		if not (String(c) in unlocked_cards):
			unlocked_cards.append(String(c))
	if age == 2:
		HAND_MAX_NOW = 6
		draw_seconds = 8.0
	if age == 3:
		boons.rank3_open = true
	notice.emit("%s. %s" % [String(spec["name"]), String(spec["note"])])
	age_reached.emit(age, String(spec["name"]))
	# An age is worth a gift, and the gift is the same three-card moment.
	grant_draft("age")


## --- boons ------------------------------------------------------------------

func commune_cost() -> float:
	return COMMUNE_BASE * pow(COMMUNE_GROWTH, float(drafts_taken))


## Open a draft the player paid for.
func commune() -> bool:
	if age == 0:
		notice.emit("Your people have nothing yet. Watch them a while.")
		return false
	var cost := commune_cost()
	if not can_afford(cost):
		notice.emit("Communing costs %d Faith." % int(cost))
		return false
	if not pending_draft.is_empty():
		# Was a SILENT false. Every other refusal here explains itself, and a
		# button that does nothing and says nothing reads as broken -- the more
		# so because the draft that is blocking it is usually a free one the
		# player has not noticed arriving.
		notice.emit("A gift is already waiting. Choose it first.")
		return false
	var options := boons.offer()
	if options.is_empty():
		notice.emit("There is nothing left to grant you.")
		return false
	add_faith(-cost)
	pending_draft = options
	draft_offered.emit(options, "commune")
	return true


## A draft that was EARNED -- an age, a population milestone, the tutorial.
## Same three-card moment, so the mechanic is learned once. `source` is carried
## through so a quest system can call this later without changing anything.
func grant_draft(source: String) -> bool:
	if not pending_draft.is_empty():
		return false
	var options := boons.offer()
	if options.is_empty():
		return false
	pending_draft = options
	draft_offered.emit(options, source)
	return true


func take_boon(id: String) -> bool:
	if pending_draft.is_empty() or not boons.take(id):
		return false
	drafts_taken += 1
	pending_draft = []
	var r := boons.rank(id)
	boon_taken.emit(id, r)
	notice.emit("%s %s." % [String(Boons.CATALOGUE[id]["name"]),
							["I", "II", "III"][r - 1]])
	if host != null and host.has_method("apply_boons"):
		host.apply_boons()
	return true


## --- land -------------------------------------------------------------------

func buy_island(slot: Vector2i) -> bool:
	var price := float(islands.price_next())
	if not can_afford(price):
		notice.emit("That ground costs %d Faith." % int(price))
		return false
	if not islands.unlock(slot):
		notice.emit("That ground does not touch yours.")
		return false
	add_faith(-price)
	host.rebuild_world()
	village.pop_cap = islands.pop_cap()
	_remember_all("The land goes further than it did.", 0.5)
	notice.emit("The land extends. Room for %d." % village.pop_cap)
	island_bought.emit(slot)
	return true
