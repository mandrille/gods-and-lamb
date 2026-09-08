extends RefCounted
class_name Away

## What happened while you were gone: a seeded story and a capped payout.
##
## NOT a fast-forward of the simulation, and the reasons are each on their own
## sufficient. The real sim replans A* six villagers a frame and a walk-grid
## rebuild costs ~30 ms, so twelve hours at even 100x is minutes of loading
## screen on a phone. The economy diverges: eating is continuous while
## gathering needs walking, so a fast-forward hands the player back a famine.
## And it is the wrong product -- the Away Log is something you READ in twelve
## seconds, not a number you are handed.
##
## PURE. One function, no nodes, no scene, and the clock is INJECTED rather
## than read from Time. That is what lets away_probe sweep a year of absence
## headless in milliseconds, and it is the whole reason the offline half of
## this game is testable at all.

const AWAY_MIN := 120.0            ## under two minutes is not an absence
const AWAY_CAP := 8.0 * 3600.0     ## hard ceiling on credited seconds
## Away time is worth this much of watched time AT THE MARGIN. Everything else
## about the payout falls out of this number being well under 1.0.
const AWAY_RATE := 0.30
const AWAY_TAU := 2700.0           ## 45 min: where the payout saturates
## And never more than this much of what the player has earned in total, so an
## absence can never buy past a wall they have not reached.
const PROGRESS_BASE := 300.0
const PROGRESS_SHARE := 0.25


## The events, weighted, each gated on the SAVE ALONE so a line can never claim
## something the village could not have done. Names come from the follower
## seed, so the log can talk about Hana without instantiating anybody.
##
## v1 rolls lines and Faith ONLY -- no stores, no population. A log that
## promises a stranger arrived and then shows a village with nobody new is
## worse than a log that only tells you what it saw.
const EVENTS := [
	{"id": "gathered", "w": 30, "needs": "folk2",
	 "line": "%s and %s brought in what wood they could."},
	{"id": "harvest", "w": 25, "needs": "crops",
	 "line": "The fields kept giving while you were away."},
	{"id": "quarried", "w": 15, "needs": "mine",
	 "line": "%s worked the stone all day."},
	{"id": "prayed", "w": 20, "needs": "shrine",
	 "line": "%s kept the shrine lit for you."},
	{"id": "newcomer", "w": 12, "needs": "room",
	 "line": "A stranger came up the road and stayed."},
	{"id": "feast", "w": 8, "needs": "fed",
	 "line": "There was a feast. Nobody went hungry."},
	{"id": "quarrel", "w": 10, "needs": "folk3", "bad": true,
	 "line": "%s and %s are not speaking."},
	{"id": "wolf", "w": 10, "needs": "wolves", "bad": true,
	 "line": "Wolves came out of the trees. The flock is smaller."},
	{"id": "storm", "w": 6, "needs": "", "bad": true,
	 "line": "A storm came through. The stores took it badly."},
	{"id": "hunger", "w": 14, "needs": "starving", "bad": true,
	 "line": "There was little to eat. %s went hungry."},
	{"id": "quiet", "w": 8, "needs": "",
	 "line": "Nothing much happened. They waited for you."},
]

## What an aura pushes on. Chosen at nightfall, so the log is the consequence
## of a decision rather than a slot machine.
const AURA_WEIGHTS := {
	"fertility": {"newcomer": 3.0, "quarrel": 0.5},
	"vigil": {"wolf": 0.0, "quarrel": 0.5},
	"harvest": {"harvest": 3.0, "feast": 2.0, "hunger": 0.3},
	"toil": {"gathered": 2.5, "quarried": 2.5},
}

const NAMES := ["Bram", "Hana", "Odo", "Mira", "Fen", "Sable", "Wren", "Tam",
				"Ivy", "Corb", "Pell", "Nyx", "Rook", "Lys", "Bede", "Ash",
				"Mave", "Tolly", "Grim", "Sorrel"]


## The whole thing. `now_unix` is injected; nothing here reads a clock.
##
## Returns {"seconds": float, "faith": float, "lines": Array[String],
##          "collected": bool}.
static func roll(save: Dictionary, now_unix: int) -> Dictionary:
	var none := {"seconds": 0.0, "faith": 0.0, "lines": [], "collected": false}
	if save.is_empty():
		return none
	var meta: Dictionary = save.get("meta", {})
	var saved_at: int = int(meta.get("saved_at", 0))
	var elapsed: float = float(now_unix - saved_at)

	# A clock that moved BACKWARDS is far more often an NTP correction or a
	# timezone change than a cheat, so it is not an error -- it simply pays
	# nothing. The high-water mark is what closes the forward-then-back trick:
	# the return trip is free of charge.
	if elapsed < 0.0 or now_unix < int(meta.get("max_seen_unix", 0)):
		return none
	if elapsed < AWAY_MIN:
		return none

	var t: float = clampf(elapsed, 0.0, AWAY_CAP)
	var rate: float = float(save.get("divinity", {}).get("income_per_s", 0.0))
	# Saturating, so hour eight is worth a fraction of a percent of hour one,
	# and the player who looks in twice a day beats the one who looks in weekly.
	var effective: float = AWAY_TAU * (1.0 - exp(-t / AWAY_TAU))
	var faith: float = rate * AWAY_RATE * effective
	var earned: float = float(save.get("divinity", {}).get("total_earned", 0.0))
	faith = minf(faith, PROGRESS_BASE + PROGRESS_SHARE * earned)

	return {
		"seconds": elapsed,
		"faith": maxf(0.0, faith),
		"lines": _story(save, t),
		"collected": false,
	}


## The log. Seeded from `away_seed`, which was drawn at SAVE time -- so
## reloading cannot reroll it, and waiting appends to the tail without ever
## changing the first three lines. Waiting is never a strategy.
static func _story(save: Dictionary, t: float) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(save.get("meta", {}).get("away_seed", 1))
	var want: int = clampi(3 + int(t / 3600.0), 3, 6)
	var aura: String = String(save.get("meta", {}).get("aura", ""))
	var weights: Dictionary = AURA_WEIGHTS.get(aura, {})

	var pool: Array = []
	for e in EVENTS:
		if not _allows(save, String(e["needs"])):
			continue
		var w: float = float(e["w"]) * float(weights.get(String(e["id"]), 1.0))
		if w > 0.0:
			pool.append({"e": e, "w": w})

	# An absence must not read as a punishment -- but leaving a starving
	# village must cost something, or the player learns that closing the tab is
	# how you solve a famine.
	var bad_left: int = 2 if _allows(save, "starving") else 1
	var out: Array = []
	while out.size() < want and not pool.is_empty():
		var total := 0.0
		for c in pool:
			total += float(c["w"])
		var pick: float = rng.randf() * total
		var chosen := -1
		for i in pool.size():
			pick -= float(pool[i]["w"])
			if pick <= 0.0:
				chosen = i
				break
		if chosen < 0:
			chosen = pool.size() - 1
		var e: Dictionary = pool[chosen]["e"]
		pool.remove_at(chosen)
		# "Nothing much happened" is a whole log, not a line in one. Drawn
		# alongside five other events it contradicts every one of them -- the
		# first run of return_probe came back with a stranger arriving, a feast,
		# a quarrel AND nothing much happening.
		if String(e["id"]) == "quiet" and not out.is_empty():
			continue
		if bool(e.get("bad", false)):
			if bad_left <= 0:
				continue
			bad_left -= 1
		out.append(_fill(String(e["line"]), save, rng))
	return out


## Whether the saved village could have produced this event.
static func _allows(save: Dictionary, needs: String) -> bool:
	if needs == "":
		return true
	var folk: Array = save.get("folk", [])
	var v: Dictionary = save.get("village", {})
	var stores: Dictionary = v.get("stores", {})
	match needs:
		"folk2":
			return folk.size() >= 2
		"folk3":
			return folk.size() >= 3
		"room":
			return folk.size() >= 1 and float(stores.get("food", 0)) > 0.0
		"fed":
			return float(stores.get("food", 0)) >= 12.0
		"starving":
			return float(stores.get("food", 0)) <= 0.0
		"wolves":
			return (int(save.get("divinity", {}).get("age", 0)) >= 2
					and (save.get("beasts", []) as Array).size() > 0)
		"crops":
			return _has_prop(save, "Nature/crop_row")
		"mine":
			return _has_prop(save, "Buildings/mine")
		"shrine":
			return _has_prop(save, "Buildings/shrine")
	return true


static func _has_prop(save: Dictionary, id: String) -> bool:
	for p in (save.get("world", {}).get("props", []) as Array):
		if String(p.get("id", "")) == id:
			return true
	return false


## Names, from the follower seeds the save already holds.
static func _fill(line: String, save: Dictionary, rng: RandomNumberGenerator) -> String:
	var n: int = line.count("%s")
	if n <= 0:
		return line
	var pool: Array = []
	for f in (save.get("folk", []) as Array):
		pool.append(NAMES[int(f.get("seed", 0)) % NAMES.size()])
	if pool.is_empty():
		pool = ["Someone"]
	# DISTINCT names when the line needs two. "Mira and Mira are not speaking"
	# is funnier than it is good, and it is the kind of thing a player screenshots.
	var picked: Array = []
	for i in n:
		var name := String(pool[rng.randi() % pool.size()])
		for _try in 8:
			if not picked.has(name):
				break
			name = String(pool[rng.randi() % pool.size()])
		picked.append(name)
	if n == 1:
		return line % picked[0]
	return line % picked
