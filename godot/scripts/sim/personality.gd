extends RefCounted
class_name Personality

## Who a follower is, as a handful of numbers that bend everything else.
##
## Traits are NOT a label on a nameplate. Each one has to change a decision
## somewhere or it is decoration, so every trait here is read by at least two
## of: how fast a need rises, which action wins a tie, how a memory is scored,
## and what a thought sounds like. A trait that only ever prints its own name
## is worse than no trait at all -- it promises depth the simulation does not
## have.
##
## Two axes and a small set of tags, rather than a big grid of independent
## sliders. The axes drive arithmetic; the tags drive text and tie-breaks.

## Signed, -1 .. +1. These are the two that actually steer behaviour.
##   `kindness`  positive means social acts are cheap and cruelty is costly
##   `devotion`  positive means Faith matters and miracles land harder
var kindness := 0.0
var devotion := 0.0

## Unsigned 0 .. 1 dials on the need rates, so two followers wear the same day
## differently.
var appetite := 1.0        ## how fast Hunger drains
var vigour := 1.0          ## how slowly Energy drains
var sociability := 1.0     ## how fast Social drains
var tidiness := 1.0        ## how much Hygiene bothers them

## Flavour tags, at most two. They break ties between equally-urgent needs and
## they are what makes a thought sound like a person rather than a status line.
var tags: Array[String] = []

const ALL_TAGS := ["Greedy", "Gentle", "Lazy", "Devout", "Brave", "Gloomy",
				   "Cheerful", "Proud", "Shy", "Glutton"]

## Tags that pull the two signed axes with them, so a Gentle follower is not
## secretly a monster and the panel never contradicts the behaviour.
const TAG_BIAS := {
	"Gentle": {"kindness": 0.45},
	"Greedy": {"kindness": -0.35},
	"Devout": {"devotion": 0.50},
	"Proud": {"kindness": -0.20},
	"Shy": {"kindness": 0.10},
	"Cheerful": {"kindness": 0.25},
	"Gloomy": {"kindness": -0.10},
	"Brave": {"devotion": 0.15},
}


static func roll(rng: RandomNumberGenerator) -> Personality:
	var p := Personality.new()
	p.kindness = rng.randf_range(-0.6, 0.6)
	p.devotion = rng.randf_range(-0.4, 0.6)
	p.appetite = rng.randf_range(0.75, 1.35)
	p.vigour = rng.randf_range(0.75, 1.30)
	p.sociability = rng.randf_range(0.65, 1.40)
	p.tidiness = rng.randf_range(0.60, 1.40)

	var pool := ALL_TAGS.duplicate()
	var count := 1 if rng.randf() < 0.45 else 2
	for i in count:
		var pick: String = pool[rng.randi_range(0, pool.size() - 1)]
		pool.erase(pick)
		p.tags.append(pick)
		var bias: Dictionary = TAG_BIAS.get(pick, {})
		p.kindness += float(bias.get("kindness", 0.0))
		p.devotion += float(bias.get("devotion", 0.0))

	# Tags nudge the dials they clearly imply. Otherwise a "Glutton" who eats
	# no faster than anyone else is a lie the panel tells the player.
	if p.has("Glutton"):
		p.appetite *= 1.5
	if p.has("Lazy"):
		p.vigour *= 0.7
	if p.has("Shy"):
		p.sociability *= 0.6
	if p.has("Cheerful"):
		p.sociability *= 1.3
	if p.has("Proud"):
		p.tidiness *= 1.4

	p.kindness = clampf(p.kindness, -1.0, 1.0)
	p.devotion = clampf(p.devotion, -1.0, 1.0)
	return p


func has(tag: String) -> bool:
	return tags.has(tag)


func describe() -> String:
	return ", ".join(tags) if not tags.is_empty() else "Ordinary"


## How strongly this follower weights a bond, good or bad. A kind follower
## forgives faster and treasures a kindness longer; a cruel one nurses a
## grudge. Used when a memory is written, not when it is read, so the bias is
## baked into the record rather than re-applied every time it is looked at.
func memory_weight(valence: float) -> float:
	if valence >= 0.0:
		return 1.0 + kindness * 0.4
	return 1.0 - kindness * 0.4


func to_dict() -> Dictionary:
	return {"kindness": kindness, "devotion": devotion, "appetite": appetite,
			"vigour": vigour, "sociability": sociability,
			"tidiness": tidiness, "tags": tags}
