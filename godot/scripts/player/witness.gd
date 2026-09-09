extends RefCounted
class_name Witness

## Who saw it, and how much it was worth to them.
##
## Owned by `Divinity` and built in its `_init`, exactly the way `Boons` is: a
## small piece of state plus pure functions that everyone else ASKS rather than
## a system that reaches into anything. It is not an autoload and not a static,
## and both of those are deliberate -- `save_probe` tears the scene down and
## rebuilds it twice in one process, so any state that outlived a `queue_free`
## would let the second run be measured against the first one's leftovers.
##
## It answers two questions. WHO SAW IT, thinned by how close they were; and
## HOW TIRED THEY ARE OF IT, which is the thing that stops the world's ground
## being a faith vending machine.

## Distance bands, as fractions of the action's radius. Straight from the
## design: standing in it is worth more than watching from the treeline.
const BAND_NEAR := 0.25
const BAND_MID := 0.60
const WEIGHT_NEAR := 1.0
const WEIGHT_MID := 0.75
const WEIGHT_FAR := 0.4

## The mean weight over a uniformly-filled disc, which is what banding costs:
## the three annuli are 6.25%, 29.75% and 64% of the area, so a crowd spread
## evenly pays 0.583 of the flat rate. Turning bands on therefore has to raise
## the base rate in the same commit, or the change reads as a nerf that nobody
## chose. Recorded here because the arithmetic is not obvious and someone will
## otherwise measure the two together and blame the wrong one.
const BAND_MEAN := 0.583

## --- novelty ----------------------------------------------------------------
##
## THE TWENTIETH APPLE IS NOT A MIRACLE.
##
## Repeating the same trivial act should stop impressing anybody, and the reason
## this matters here is specific: greening is on a 0.45 s shared cooldown and an
## engaged player touches on nearly every one of them, so without this the
## cheapest possible action is also the best faith-per-second in the game. The
## design asks for the player to graduate from the ground to the people, and
## this is the lever that makes that happen by itself.
##
## What decays is ONLY how impressed a villager is. Not the goods, not the
## greening, not the FX -- the world must never stop answering. WorldTouch's own
## rule that every touch is free and does something stays literally true.
const NOVELTY_FLOOR := 0.20
## The multiplicative bite each use takes out of what is left.
const NOVELTY_COST := 0.18
## Village-seconds to recover half the remaining gap back to 1.0.
const NOVELTY_HALF := 45.0

## key -> {"n": float, "at": float}. NOT SAVED, and that is a decision rather
## than an omission: a 45-second half-life is far shorter than the gap between
## any two sessions, so the correct value after a real absence is "fresh" --
## which an empty ledger already gives. Saving it would buy nothing anyone could
## perceive and cost a schema field plus a rebasing rule, because `village.now`
## is restored while `Away` adds real elapsed time separately and an absolute
## stamp would be wrong in both directions.
var _seen: Dictionary = {}


## How impressive this kind of act still is, 0.20 .. 1.0.
##
## Computed lazily from the clock rather than ticked, which costs nothing on the
## frames where nothing happens and is automatically correct under
## `Engine.time_scale` -- a decay that ran off a timer would drift every time a
## probe sped the world up.
func novelty(key: String, now: float) -> float:
	if key == "":
		return 1.0
	var e: Dictionary = _seen.get(key, {})
	if e.is_empty():
		return 1.0
	var gap: float = maxf(0.0, now - float(e["at"]))
	var n: float = float(e["n"])
	return 1.0 - (1.0 - n) * pow(0.5, gap / NOVELTY_HALF)


## Use it up a little.
func spend(key: String, now: float) -> void:
	if key == "":
		return
	_seen[key] = {"n": maxf(NOVELTY_FLOOR,
							novelty(key, now) * (1.0 - NOVELTY_COST)),
				  "at": now}


func forget() -> void:
	_seen.clear()


## Everyone who could see it, with what it is worth to each.
## Returns [[follower, weight], ...].
static func find(folk: Array, a: DivineAction) -> Array:
	var out: Array = []
	for f in folk:
		if not is_instance_valid(f) or f.brain == null:
			continue
		# radius 0 means "everyone, everywhere" -- relief from a disaster is
		# felt by the whole village, not by whoever happened to be standing
		# near the fire.
		if a.radius > 0.0:
			var d: float = f.position.distance_to(a.at)
			if d > a.radius:
				continue
			out.append([f, _band(d / a.radius) if a.bands else 1.0])
		else:
			out.append([f, 1.0])
	return out


static func _band(t: float) -> float:
	if t <= BAND_NEAR:
		return WEIGHT_NEAR
	if t <= BAND_MID:
		return WEIGHT_MID
	return WEIGHT_FAR
