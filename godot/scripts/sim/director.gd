extends RefCounted
class_name Director

## Makes sure something is always about to happen.
##
## The village already produces births, wolves, fires, newcomers and prayers,
## and every one of them runs on its OWN independent timer. That is fine on
## average and bad in the moment: four things can land in the same ten seconds
## and then nothing at all for three minutes, and the three minutes are what a
## player quits during.
##
## This does not replace any of those timers and does not take their decisions
## away. It watches, and when the village has been quiet too long it leans on
## whichever of them is eligible. The systems stay in charge of HOW; this is
## only in charge of WHEN-AT-THE-LATEST.
##
## PRESSURE IS NEVER SHOWN. It is a pacing variable, and a pacing variable on
## screen becomes a resource the player manages -- which is the opposite of what
## it is for.

## Village-seconds of quiet before the director starts insisting. The design
## asks for something worth watching every thirty to sixty seconds; this is the
## outer edge of that, because the village's own timers fill most of it and this
## should be a floor rather than a metronome.
const QUIET := 55.0
## Never twice in a row without a breath between. Two crises back to back is not
## twice the drama, it is noise.
const AFTER := 25.0
## And it stays out of the way entirely until the village is worth disturbing.
const MIN_FOLK := 4

## THE DIRECTOR MAY NOT MAKE THE OPENING HARDER.
##
## Measured, and it is the reason this constant exists: with the calamity rung
## open to a young village the director pulled fires and droughts forward into
## the first five minutes, and since a drought reverts grass to dirt it was
## undoing the ground the player had just made. The opening went from 212 tiles
## greened and seven buildings to 35 tiles and two -- a village that never got
## started, because the pacing system decided it was bored.
##
## The village's own calamity timer is untouched and still fires on its own
## schedule. This only says the director may not ACCELERATE that particular
## rung until there is a village solid enough to lose something.
const CALAMITY_FOLK := 10

## What the director may reach for, worst-first: it would rather add somebody to
## the village than set fire to it, and only escalates if the calm has gone on
## and the gentler options are unavailable.
const LADDER := ["newcomer", "wolf", "calamity"]

var pressure := 0.0                ## 0..1, hidden
## THE QUIET CLOCK STARTS WHEN THE DIRECTOR DOES, NOT AT THE DAWN OF TIME.
##
## This began as -999, meaning "nothing has ever happened", and that read as
## nine hundred and ninety-nine seconds of silence -- so on the first frame of
## every single load the director decided the village was bored and shoved a
## stranger into it. A saved village that gains a newcomer the instant you open
## it is not pacing, it is a bug with a personality.
##
## Unset until the first tick, which is the only moment the director can know
## what time it is.
var _last_event := INF
var _last_kind := ""


## Something happened -- from any source, the director's own or the village's.
## Pressure is the time since the last interesting thing, so this is the only
## thing that resets it.
func mark(kind: String, now: float) -> void:
	_last_event = now
	_last_kind = kind
	pressure = 0.0


func tick(now: float) -> void:
	if _last_event == INF:
		# First sight of the clock. The village starts calm, and it gets its
		# full quiet allowance before anything is forced on it.
		_last_event = now
	pressure = clampf((now - _last_event) / QUIET, 0.0, 1.0)


## What the director wants to happen, or "" for nothing.
##
## `can` answers whether each rung is currently possible; the director never
## learns why. Passing that in rather than reaching into the world is what keeps
## this file testable without a village.
func wants(now: float, can: Dictionary) -> String:
	if _last_event == INF or pressure < 1.0 or now - _last_event < AFTER:
		return ""
	for kind in LADDER:
		if not bool(can.get(kind, false)):
			continue
		# NOT THE SAME THING TWICE. A village that gets wolves, then wolves,
		# then wolves has weather rather than events.
		if kind == _last_kind and _has_another(can):
			continue
		return kind
	return ""


func _has_another(can: Dictionary) -> bool:
	for kind in LADDER:
		if kind != _last_kind and bool(can.get(kind, false)):
			return true
	return false
