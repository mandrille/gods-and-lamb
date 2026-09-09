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
## Stage 1 uses only `find`, unbanded, so the funnel is provably payout-neutral:
## every caller pays exactly what its own hand-rolled loop paid yesterday. The
## bands and the novelty ledger below are the next stage, and are written here
## so that turning them on is a flag rather than a rewrite.

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
