extends RefCounted
class_name Boons

## The god's permanent powers, taken three at a time.
##
## You never buy a named boon off a shelf. You open a draft and are offered
## THREE, and you take one. That is the whole design: a choice with a cost of
## opportunity, made a dozen times a run, is what makes two runs differ and
## what makes the next one worth starting.
##
## PASSIVES ARE NOT BOONS. A church or a lumberyard is something the village
## happened to build -- luck, not agency -- and it lives in Village, not here.
## Mixing the two makes both feel weaker: the choice stops feeling chosen and
## the luck stops feeling lucky.
##
## Per-run. Nothing here survives quitting, because nothing in this project
## serialises and a save system is a different piece of work.

## Effects are resolved by ASKING, never by writing into the systems they
## affect. `Brain.ACTIONS` is a const shared by every mind in the game, and a
## boon that mutated it would make the change permanent, global, and invisible
## to the next run.
const CATALOGUE := {
	"zeal": {
		"name": "Zeal", "icon": "faith",
		"what": "Your followers' devotion feeds you more richly.",
		"ranks": [1.25, 1.55, 1.90],
		"blurb": ["Faith from followers +25%", "+55%", "+90%"],
	},
	"full_hands": {
		"name": "Full Hands", "icon": "wood",
		"what": "Every villager brings back more than they should.",
		"ranks": [1, 2, 3],
		"blurb": ["Gathering yields +1", "+2", "+3"],
	},
	"swift_feet": {
		"name": "Swift Feet", "icon": "sprout",
		"what": "They walk quicker. Most of a villager's life is walking.",
		"ranks": [1.15, 1.32, 1.50],
		"blurb": ["Villagers move 15% faster", "32% faster", "50% faster"],
	},
	"open_hand": {
		"name": "Open Hand", "icon": "bolt",
		"what": "Your judgement spreads to those standing nearby.",
		"ranks": [6.0, 10.0, 10.0],
		"blurb": ["Blessing reaches 6 m around its target",
				  "Reaches 10 m", "Reaches 10 m, and punishing keeps a chain"],
	},
	"witness": {
		"name": "Witness", "icon": "bless",
		"what": "You see more in a finished day's work, and have longer to act.",
		"ranks": [5.5, 7.0, 9.0],
		"blurb": ["Witnessed blessings pay more, and you get 5 s to react",
				  "More again, 6 s, and chains run to eight",
				  "Most of all, 7.5 s, and each link is worth more"],
	},
	"wide_grace": {
		"name": "Wide Grace", "icon": "dove",
		"what": "Miracles reach further, and reward you for who they touch.",
		"ranks": [6.0, 7.5, 9.0],
		"blurb": ["Miracles reach 6 m", "7.5 m", "9 m, and pay more per soul"],
	},
	"kindled_hearth": {
		"name": "Kindled Hearth", "icon": "heart",
		"what": "Hunger, weariness and loneliness come on more slowly.",
		"ranks": [0.88, 0.78, 0.68],
		"blurb": ["Needs grow 12% slower", "22% slower", "32% slower"],
	},
	"gathering": {
		"name": "Gathering", "icon": "pop",
		"what": "Word spreads. Strangers come looking for your village.",
		"ranks": [58.0, 45.0, 34.0],
		"blurb": ["Newcomers arrive sooner", "Sooner again",
				  "Soonest, and they are less fussy about the mood"],
	},
}

const MAX_RANK := 3
const OFFER := 3

var held: Dictionary = {}                ## id -> rank taken, 1..3
var rank3_open := false                  ## opened by the third Age
var rng := RandomNumberGenerator.new()


func _init(seed_value := 20260901) -> void:
	rng.seed = seed_value


func rank(id: String) -> int:
	return int(held.get(id, 0))


func maxed(id: String) -> bool:
	return rank(id) >= MAX_RANK


## Three to choose between.
##
## The rules exist to keep it a CHOICE. Without "at least one you do not own"
## a late draft becomes three copies of the same upgrade; without the rank-3
## gate a player empties one line in minute two and flattens the whole curve.
func offer() -> Array[Dictionary]:
	var pool: Array[String] = []
	for id in CATALOGUE:
		if maxed(id):
			continue
		# Rank 3 is the third Age's reward for getting there.
		if rank(id) >= 2 and not rank3_open:
			continue
		pool.append(String(id))
	if pool.is_empty():
		return []

	var unowned: Array[String] = []
	for id in pool:
		if rank(id) == 0:
			unowned.append(id)

	var picked: Array[String] = []
	# Seed the offer with something NEW when anything new exists.
	if not unowned.is_empty():
		picked.append(unowned[rng.randi_range(0, unowned.size() - 1)])
	while picked.size() < mini(OFFER, pool.size()):
		var id: String = pool[rng.randi_range(0, pool.size() - 1)]
		if not picked.has(id):
			picked.append(id)

	var out: Array[Dictionary] = []
	for id in picked:
		var next := rank(id) + 1
		var spec: Dictionary = CATALOGUE[id]
		out.append({
			"id": id, "name": String(spec["name"]), "icon": String(spec["icon"]),
			"rank": next, "what": String(spec["what"]),
			# The sentence for the rank being OFFERED, not for the boon in
			# general. A number with no sentence beside it is not a choice.
			"blurb": String((spec["blurb"] as Array)[next - 1]),
		})
	return out


func take(id: String) -> bool:
	if not CATALOGUE.has(id) or maxed(id):
		return false
	held[id] = rank(id) + 1
	return true


## --- resolved effects -------------------------------------------------------
##
## Every one of these is a QUESTION the systems ask, so a boon never has to
## reach into anything and nothing has to be un-applied.

func _value(id: String, at_zero: float) -> float:
	var r := rank(id)
	if r <= 0:
		return at_zero
	return float((CATALOGUE[id]["ranks"] as Array)[r - 1])


func zeal() -> float:
	return _value("zeal", 1.0)


func yield_bonus() -> int:
	return int(_value("full_hands", 0.0))


func walk() -> float:
	return _value("swift_feet", 1.0)


func bless_radius() -> float:
	return _value("open_hand", 0.0)


func punish_keeps_chain() -> bool:
	return rank("open_hand") >= 3


func witness_faith() -> float:
	return _value("witness", 4.0)


func witness_window() -> float:
	return [4.0, 5.0, 6.0, 7.5][rank("witness")]


func combo_cap() -> int:
	return 8 if rank("witness") >= 2 else 6


func combo_step() -> float:
	return 0.45 if rank("witness") >= 3 else 0.35


func card_radius() -> float:
	return _value("wide_grace", 4.5)


func card_kick() -> float:
	return [3.0, 3.8, 4.6, 5.5][rank("wide_grace")]


func drain() -> float:
	return _value("kindled_hearth", 1.0)


func newcomer_seconds() -> float:
	return _value("gathering", 75.0)


func mood_gate() -> float:
	return [0.15, 0.12, 0.10, 0.08][rank("gathering")]


func summary() -> String:
	if held.is_empty():
		return "no boons"
	var bits: Array[String] = []
	for id in held:
		bits.append("%s %d" % [String(CATALOGUE[id]["name"]), int(held[id])])
	return ", ".join(bits)
