extends RefCounted
class_name Daylight

## The day, and how much of it is left.
##
## A session had no shape at all: the player closed the tab at an arbitrary
## moment, so there was never a payoff for the eight minutes they had just
## spent and never a reason to come back tomorrow. A day gives the session a
## beginning, a middle and an END -- and the END is the thing worth building,
## because that is where a summary, an overnight choice and a save belong.
##
## The clock runs on GAME time, ticked beside `Village.tick`, so it obeys
## `Engine.time_scale` and a probe can run a whole day in seconds. It never
## reads the wall clock; that is `Away`'s job and its boundary is deliberate.

## Eight minutes, which is the session the game is being aimed at. Long enough
## to raise a village and short enough to finish on a phone at a bus stop.
const DAY_SECONDS := 480.0

## The last stretch, when the light goes warm and the countdown turns amber.
## Dusk is a WARNING, not a state change: everything still works, but the
## player can see the day closing and choose what to spend it on.
const DUSK_FRACTION := 0.18

signal night_fell(day: int)

var day := 1
var t := 0.0                        ## seconds into the current day


func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	t += delta
	if t < DAY_SECONDS:
		return
	# Roll over exactly once however large the frame was. A probe at 20x can
	# step past a whole day in one tick, and a day that silently ate its own
	# nightfall would be a day the player was never told about.
	while t >= DAY_SECONDS:
		t -= DAY_SECONDS
		day += 1
		night_fell.emit(day - 1)


## 0 at dawn, 1 at nightfall.
func fraction() -> float:
	return clampf(t / DAY_SECONDS, 0.0, 1.0)


func seconds_left() -> float:
	return maxf(0.0, DAY_SECONDS - t)


## "6:12" -- minutes and seconds, because a bare percentage is not a countdown
## and "0.34 of a day" is not something anybody feels.
func clock() -> String:
	var s := int(ceilf(seconds_left()))
	return "%d:%02d" % [s / 60, s % 60]


func is_dusk() -> bool:
	return fraction() >= 1.0 - DUSK_FRACTION


## How far into dusk, 0..1. Drives the sun-to-moon crossfade and the light.
func dusk_amount() -> float:
	if not is_dusk():
		return 0.0
	return clampf((fraction() - (1.0 - DUSK_FRACTION)) / DUSK_FRACTION,
				  0.0, 1.0)


func to_doc() -> Dictionary:
	return {"day": day, "t": t}


func from_doc(doc: Dictionary) -> void:
	day = maxi(1, int(doc.get("day", 1)))
	t = clampf(float(doc.get("t", 0.0)), 0.0, DAY_SECONDS - 0.01)
