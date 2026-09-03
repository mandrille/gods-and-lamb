extends RefCounted
class_name Village

## What the settlement owns, collectively.
##
## Small on purpose. This is a shared ledger, not an economy simulation: it
## exists so that harvesting has a POINT and eating has a COST, which is what
## turns "play the chop animation" into work. Without it, blessing a woodcutter
## produces more chopping and nothing else, and the player has no way to tell
## whether their influence mattered.
##
## Stores are integers. Fractional wheat is a rounding argument nobody needs.

signal changed()
signal depleted(res: String)

## What a full store looks like, per resident. Capacity scales with population
## so a bigger village is not permanently starving on the same granary.
const PER_HEAD := {"food": 6, "wood": 8, "stone": 5}
## What two people wash up on a bare plot with. Deliberately thin: the first
## hut has to be EARNED, because watching them earn it is the whole opening.
## The founding pair arrive with a little in hand.
##
## Starting at nothing meant the first chop landed at 54 s and the first hut at
## 82 s, and a hut costs six wood against a yield of four -- so the opening was
## always two chops long before anything could be built. Three wood makes the
## FIRST chop enough to raise the first roof, which is the moment the whole
## opening is supposed to be about. It is still zero buildings, which is what
## the opening asks for; they simply did not walk in empty-handed.
##
## The stone matters as much as the wood, for a reason that is easy to miss.
## `shortage` reads 1.0 for an EMPTY store, so leaving stone at zero while
## seeding wood handed the opening straight back to the pick: wood scored
## 1 - 3/16 = 0.81 and stone scored a flat 1.0, so the first thing the founders
## did was quarry for a well nobody had asked for. Starting both shelves off
## zero lets purpose -- what the first hut actually needs -- decide.
const START := {"food": 6, "wood": 3, "stone": 3}

## How many of each structure the settlement wants, given its size. This is
## what stops a village raising a third well and what makes the first hut
## urgent -- `shortage` is about resources, this is about buildings.
## `priority` breaks ties. Without it a well and the FIRST ROOF were wanted
## exactly as much -- both "min 1, have 0" -- so an opening village split its
## effort between wood and stone and took 147 s to put up any building at all.
## A settlement builds shelter first and digs a well afterwards.
## `requires` is a NEW, optional gate: {some other building's id: how many
## must be STANDING before this one is wanted at all}. Without it a village of
## two could be found wanting a mansion, which needs a shrine and a tavern it
## has no hope of reaching -- `wants()` returns a flat zero until the
## prerequisite count is met, the same way `_somewhere_to_do` returns a flat
## zero for an unreachable source rather than a discounted one.
const WANTED := {
	"Buildings/hut": {"per_head": 0.5, "min": 1, "priority": 1.0},
	"Buildings/well": {"per_head": 0.0, "min": 1, "priority": 0.55},
	"Buildings/market_stall": {"per_head": 0.0, "min": 1, "priority": 0.45},
	"Buildings/shrine": {"per_head": 0.0, "min": 1, "priority": 0.5,
						 "requires": {"Buildings/hut": 2}},
	"Nature/crop_row": {"per_head": 3.0, "min": 4, "priority": 0.8},
	"Buildings/cottage": {"per_head": 0.2, "min": 0, "priority": 0.35,
						  "requires": {"Buildings/hut": 2}},
	"Buildings/tavern": {"per_head": 0.0, "min": 1, "priority": 0.40,
						 "requires": {"Buildings/hut": 3}},
	"Buildings/mansion": {"per_head": 0.0, "min": 1, "priority": 0.35,
						  "requires": {"Buildings/shrine": 1,
									   "Buildings/tavern": 1}},
	"Buildings/barracks": {"per_head": 0.0, "min": 1, "priority": 0.40,
						   "requires": {"Buildings/hut": 4}},
	"Buildings/hotel": {"per_head": 0.0, "min": 1, "priority": 0.35,
						"requires": {"Buildings/tavern": 1}},
	"Buildings/windmill": {"per_head": 0.0, "min": 1, "priority": 0.40,
						   "requires": {"Buildings/farm": 1}},
	"Buildings/mine": {"per_head": 0.0, "min": 1, "priority": 0.45,
					   "requires": {"Buildings/hut": 2}},
	"Buildings/lumber_camp": {"per_head": 0.0, "min": 1, "priority": 0.45,
							  "requires": {"Buildings/hut": 2}},
	"Buildings/smithy": {"per_head": 0.0, "min": 1, "priority": 0.40,
						 "requires": {"Buildings/hut": 2}},
	"Buildings/farm": {"per_head": 0.0, "min": 1, "priority": 0.45,
					   "requires": {"Buildings/hut": 1}},
}

## What a building DOES for the village once it stands. Read through the
## getters below, never written into (the Boons rule: effects are questions the
## systems ask). Each building also EMPLOYS: `jobs` is how many villagers of
## that job it supports, which is what decides a newcomer's job at spawn.
##
## STUB, filled in by the engine pass of the content batch. It exists now so
## every author knows the ids and keys the engine will expect.
const PASSIVES := {
	"Buildings/shrine":      {"faith_per_s": 0.06, "jobs": {"priest": 1}},
	"Buildings/mansion":     {"pop_cap_add": 2, "faith_per_s": 0.02},
	"Buildings/tavern":      {"need_decay": {"fun": 0.7}, "jobs": {"bard": 1}},
	"Buildings/hotel":       {"newcomer_mult": 1.5, "jobs": {"nurse": 1}},
	"Buildings/lumber_camp": {"yield": {"wood": 1.5}, "jobs": {"lumberjack": 2}},
	"Buildings/mine":        {"yield": {"stone": 1.5}, "jobs": {"miner": 2}},
	"Buildings/smithy":      {"build_seconds_mult": 0.75, "jobs": {"builder": 1}},
	"Buildings/barracks":    {"wolf_cap_add": -1, "jobs": {"hunter": 2}},
	"Buildings/farm":        {"yield": {"food": 1.4}, "cap_mult": {"food": 1.5}},
	"Buildings/windmill":    {"cap_mult": {"food": 1.5}, "yield": {"food": 1.25}},
}

var stores: Dictionary = {}
var population := 0
var pop_cap := 5

## Cumulative, for the chronicle and for scoring how the village is doing.
var total_gathered := 0
var total_eaten := 0

## asset id -> how many are standing. Kept as a count the builder refreshes
## rather than recomputed by walking the prop list on every decision: every
## villager asks this several times a second.
var structures: Dictionary = {}

## Building work already under way: asset id -> Array of expiry timestamps.
##
## Without this, every villager who checks "do we want a well?" before the
## first one finishes gets the same answer, and a village of fifty raises four
## wells it wanted one of. Reservations EXPIRE rather than being released,
## because the alternative is tracking which villager holds which claim and
## leaking one every time somebody is despawned mid-job.
var _claims: Dictionary = {}
const CLAIM_SECONDS := 25.0

## Ground somebody is already walking toward with a building in mind.
##
## `_claims` reserves the KIND -- it stops a second well being WANTED. It does
## nothing about two villagers both told to build a hut walking to overlapping
## ground, which is half of why buildings were seen stacked. This reserves the
## CELLS, with the same expiry so a despawned builder cannot leak a claim.
var _sites: Array[Dictionary] = []       ## {cell, radius, expiry}

## How rich each plot still is. Extraction wears it down and time restores it,
## and it NEVER reaches zero -- a worked-out plot pays badly rather than not at
## all, and fresh land starts rich, which is what makes expansion the answer to
## diminishing returns instead of a population cap you bump into.
const RICH_FLOOR := 0.25
const RICH_PER_EXTRACT := 0.02
const RICH_REGROW := 0.01
var _richness: Dictionary = {}           ## Vector2i slot -> float

## Injected: needed to turn a cell into the plot that owns it.
var islands = null
## Injected: ValeRoot, needed to resolve a `seeks` action (Brain._somewhere_to_do,
## Brain.destination_for) to an actual target -- the village ledger has no idea
## where the wolves or the sick are, but the scene root does. Same shape as the
## `islands` injection above.
var host = null

## Consecutive failures to find anywhere to build, so "the land is full" is a
## state that gets ANNOUNCED rather than a silent stall in the decision pool.
## The game clock, in seconds of village time.
##
## One shared clock, because "did this happen recently" is a question the god
## asks about something the villager did, and two objects cannot compare their
## own private timers. Advanced by `tick(delta)`, so it obeys time_scale --
## `Time.get_ticks_msec()` does not, which is how a 25-second claim once
## survived 300 game-seconds.
var now := 0.0

var _site_misses := 0
signal land_full()


func _init() -> void:
	stores = START.duplicate()


func capacity(res: String) -> int:
	return int(round(float(PER_HEAD.get(res, 5)) * float(maxi(1, population))
		* passive_cap_mult(res)))


## 0 = plenty, 1 = empty. What `Brain._demand` reads to decide whether the job
## is worth doing, so followers drift off harvesting once the granary is full.
func shortage(res: String) -> float:
	var cap := capacity(res)
	if cap <= 0:
		return 1.0
	return clampf(1.0 - float(amount(res)) / float(cap), 0.0, 1.0)


func amount(res: String) -> int:
	return int(stores.get(res, 0))


func can_take(cost: Dictionary) -> bool:
	for res in cost:
		if amount(String(res)) < int(cost[res]):
			return false
	return true


## All or nothing. A partial take would let two followers each half-eat the
## last loaf and both come away fed.
func take(cost: Dictionary) -> bool:
	if not can_take(cost):
		return false
	for res in cost:
		var r := String(res)
		stores[r] = amount(r) - int(cost[res])
		total_eaten += int(cost[res])
		if amount(r) == 0:
			depleted.emit(r)
	changed.emit()
	return true


func give(gain: Dictionary) -> void:
	for res in gain:
		var r := String(res)
		# Capped. An uncapped store means the village hoards forever and every
		# shortage reads as zero, which silently disables the whole demand
		# system that decides what work gets done.
		stores[r] = mini(amount(r) + int(gain[res]), capacity(r))
		total_gathered += int(gain[res])
	changed.emit()


## Refresh the structure census from what is actually standing. Called by the
## host whenever props change -- built, destroyed, or a new plot bought.
func census(placed_props: Array) -> void:
	structures.clear()
	for e in placed_props:
		var aid := String(e.get("id", ""))
		structures[aid] = int(structures.get(aid, 0)) + 1


## A `_b` variant is a colourway, not a different building -- a hut_b is a
## hut. `add_prop` records whichever id it actually placed, so a village with
## three of one and one of the other must still read as four huts to `wants`,
## to every passive that counts shrines or lumber camps, and to `rest`'s
## source list. Folded HERE, once, rather than at each of those call sites.
func count_of(aid: String) -> int:
	var base := aid
	if base.ends_with("_b"):
		base = base.substr(0, base.length() - 2)
	return int(structures.get(base, 0)) + int(structures.get(base + "_b", 0))


## Somebody has started building one of these.
##
## Claims hold a REMAINING TIME counted down by `tick(delta)`, not a wall-clock
## expiry. `Time.get_ticks_msec()` ignores `Engine.time_scale`, so a 25-second
## claim survived 300 game-seconds in a probe running at 12x -- long enough to
## suppress demand for building entirely and make the village look idle. Game
## state should be measured in game time.
func claim(aid: String) -> void:
	if not _claims.has(aid):
		_claims[aid] = []
	(_claims[aid] as Array).append(CLAIM_SECONDS)


## How many are under way right now.
func claimed(aid: String) -> int:
	return (_claims.get(aid, []) as Array).size()


## 0 = we have enough, 1 = we have none and want one. Drives whether building
## is worth a villager's time at all.
## `count_claims` exists for one caller: Brain._needed_for_wants, which asks
## how badly a MATERIAL is wanted.
##
## Counting claims is right for "should I start building one of these" -- it is
## what stops four villagers all raising the same well. It is exactly wrong for
## "should I go and fetch wood", because a claimed hut still needs its six wood
## and has not been built yet. With claims counted, the first claim dropped the
## demand for wood to nothing, nobody chopped, the claim expired unbuilt and it
## began again: measured, one run took 246 s to fell its first tree.
func wants(aid: String, count_claims := true) -> float:
	if not WANTED.has(aid):
		return 0.0
	var spec: Dictionary = WANTED[aid]
	# A prerequisite not yet met makes this a flat zero, the same way an
	# unreachable source makes `_somewhere_to_do` a flat zero rather than a
	# discounted one -- otherwise a two-hut village half-wants a mansion and
	# some fraction of its gathering effort points at a building nobody could
	# possibly finish.
	var requires: Dictionary = spec.get("requires", {})
	for req_aid in requires:
		if count_of(String(req_aid)) < int(requires[req_aid]):
			return 0.0
	var target: float = maxf(float(spec["min"]),
							 float(spec["per_head"]) * float(maxi(1, population)))
	# Standing ones PLUS the ones being built right now.
	var have := float(count_of(aid) + (claimed(aid) if count_claims else 0))
	if have >= target:
		return 0.0
	return (clampf((target - have) / target, 0.0, 1.0)
			* float(spec.get("priority", 1.0)))


## --- building sites ---------------------------------------------------------

func claim_site(cell: Vector2i, radius: int) -> void:
	_sites.append({"cell": cell, "radius": radius, "left": CLAIM_SECONDS})


func site_claimed(cell: Vector2i, radius: int) -> bool:
	for e in _sites:
		var c: Vector2i = e["cell"]
		var reach: int = int(e["radius"]) + radius
		if absi(cell.x - c.x) <= reach and absi(cell.y - c.y) <= reach:
			return true
	return false


func note_site(found: bool) -> void:
	if found:
		_site_misses = 0
		return
	_site_misses += 1
	# Enough villagers in a row failing means it is the LAND, not luck.
	if _site_misses == 8:
		land_full.emit()


## --- richness ---------------------------------------------------------------

func richness_at(cell: Vector2i) -> float:
	if islands == null:
		return 1.0
	var slot: Vector2i = islands.slot_of_cell(cell)
	if slot.x < 0:
		return 1.0
	return float(_richness.get(slot, 1.0))


func extract_at(cell: Vector2i) -> void:
	if islands == null:
		return
	var slot: Vector2i = islands.slot_of_cell(cell)
	if slot.x < 0:
		return
	_richness[slot] = maxf(RICH_FLOOR,
						   float(_richness.get(slot, 1.0)) - RICH_PER_EXTRACT)


## Land recovers on its own. Called once per frame by the host.
func tick(delta: float) -> void:
	now += delta
	# Claims age in GAME time, so they behave the same however fast the world
	# is running.
	for aid in _claims.keys():
		var live: Array = []
		for t in _claims[aid]:
			var left: float = float(t) - delta
			if left > 0.0:
				live.append(left)
		if live.is_empty():
			_claims.erase(aid)
		else:
			_claims[aid] = live
	var sites: Array[Dictionary] = []
	for e in _sites:
		e["left"] = float(e["left"]) - delta
		if float(e["left"]) > 0.0:
			sites.append(e)
	_sites = sites

	for slot in _richness:
		var v: float = float(_richness[slot])
		if v < 1.0:
			_richness[slot] = minf(1.0, v + RICH_REGROW * delta)


## Scale a yield by how tired the ground is. Never returns 0 for a positive
## input -- that is the whole promise of the richness model.
func scaled_gives(gives: Dictionary, cell: Vector2i) -> Dictionary:
	var r := richness_at(cell)
	var out := {}
	for res in gives:
		out[res] = maxi(1, int(round(float(gives[res]) * r)))
	return out


func has_room() -> bool:
	return population < pop_cap


func summary() -> String:
	return "food %d/%d  wood %d/%d  stone %d/%d  pop %d/%d" % [
		amount("food"), capacity("food"),
		amount("wood"), capacity("wood"),
		amount("stone"), capacity("stone"), population, pop_cap]


## --- passives ----------------------------------------------------------------
##
## What a building DOES, read by asking rather than by the building reaching
## out and changing something. Same rule Boons.gd states for the god's own
## powers: an effect that mutated Brain.ACTIONS or Divinity directly would be
## permanent, global, and invisible to whoever removed the building.
##
## STACKING IS CAPPED at 3 standing instances of a kind. A village with nine
## shrines earning nine times the Faith of one is not a richer village, it is
## a number that stopped meaning anything -- the cap is what keeps a passive a
## nice-to-have instead of the entire game.
const PASSIVE_STACK_CAP := 3


func _stacks(aid: String) -> int:
	return mini(count_of(aid), PASSIVE_STACK_CAP)


func passive_faith() -> float:
	var total := 0.0
	for aid in PASSIVES:
		var n := _stacks(aid)
		if n <= 0:
			continue
		total += float((PASSIVES[aid] as Dictionary).get("faith_per_s", 0.0)) \
			* float(n)
	return total


## Multiplicative, and each stacked instance multiplies again -- two lumber
## camps at x1.5 pay x2.25, not x3.0, the same diminishing shape `richness`
## already uses for worked land.
func passive_yield(res: String) -> float:
	var mult := 1.0
	for aid in PASSIVES:
		var n := _stacks(aid)
		if n <= 0:
			continue
		var y: Dictionary = (PASSIVES[aid] as Dictionary).get("yield", {})
		if not y.has(res):
			continue
		var per: float = float(y[res])
		for i in n:
			mult *= per
	return mult


func passive_cap_mult(res: String) -> float:
	var mult := 1.0
	for aid in PASSIVES:
		var n := _stacks(aid)
		if n <= 0:
			continue
		var c: Dictionary = (PASSIVES[aid] as Dictionary).get("cap_mult", {})
		if not c.has(res):
			continue
		var per: float = float(c[res])
		for i in n:
			mult *= per
	return mult


## `build_seconds_mult`, `newcomer_mult` -- any multiplicative passive keyed by
## name rather than by resource. Default 1.0: no building, no change.
func passive_mult(key: String) -> float:
	var mult := 1.0
	for aid in PASSIVES:
		var n := _stacks(aid)
		if n <= 0:
			continue
		var spec: Dictionary = PASSIVES[aid]
		if not spec.has(key):
			continue
		var per: float = float(spec[key])
		for i in n:
			mult *= per
	return mult


## `pop_cap_add`, `wolf_cap_add` -- additive, default 0. Barracks' `wolf_cap_add`
## is NEGATIVE by design (see PASSIVES): hunters thin the pack the wolf spawner
## is allowed to grow.
func passive_add(key: String) -> int:
	var total := 0
	for aid in PASSIVES:
		var n := _stacks(aid)
		if n <= 0:
			continue
		var spec: Dictionary = PASSIVES[aid]
		if not spec.has(key):
			continue
		total += int(spec[key]) * n
	return total


func passive_jobs(job: String) -> int:
	var total := 0
	for aid in PASSIVES:
		var n := _stacks(aid)
		if n <= 0:
			continue
		var jobs: Dictionary = (PASSIVES[aid] as Dictionary).get("jobs", {})
		if jobs.has(job):
			total += int(jobs[job]) * n
	return total


func passive_need_decay(stat: String) -> float:
	var mult := 1.0
	for aid in PASSIVES:
		var n := _stacks(aid)
		if n <= 0:
			continue
		var d: Dictionary = (PASSIVES[aid] as Dictionary).get("need_decay", {})
		if not d.has(stat):
			continue
		var per: float = float(d[stat])
		for i in n:
			mult *= per
	return mult


## --- job assignment ------------------------------------------------------------

## How many ADULT folk currently hold each job. Children never hold one --
## see Brain.CHILD_ACTIONS and the WORK gate in choose_action -- so counting
## them would understate how much slack an employer building actually has.
func job_counts(folk: Array) -> Dictionary:
	var out := {}
	for f in folk:
		if not is_instance_valid(f) or f.brain == null or not f.brain.adult:
			continue
		var j := String(f.brain.job)
		out[j] = int(out.get(j, 0)) + 1
	return out


## The job with the largest deficit between what its employer can support and
## how many villagers already hold it. "" when nothing is standing to employ
## anyone -- nobody is born a lumberjack in a village with no lumber camp, and
## the caller falls back to the old villager/adventurer split.
func job_for_newcomer(counts: Dictionary) -> String:
	var best := ""
	var best_deficit := 0
	for job in Jobs.JOBS:
		var spec: Dictionary = Jobs.JOBS[job]
		var employer := String(spec.get("employer", ""))
		if employer == "":
			continue
		var per: int = int((PASSIVES.get(employer, {}) as Dictionary
			).get("jobs", {}).get(job, 0))
		if per <= 0:
			continue
		var slots: int = count_of(employer) * per
		var held: int = int(counts.get(String(job), 0))
		var deficit := slots - held
		if deficit > best_deficit:
			best_deficit = deficit
			best = String(job)
	return best
