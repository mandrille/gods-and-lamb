extends RefCounted
class_name Comfort

## Three switches that decide how loud the game is allowed to be.
##
## The project has accumulated a lot of motion without anybody deciding how much
## motion there should be. Guilt pulses, the blessable dial depletes, prayer
## bubbles beat, the prophet's ring bobs, the edge arrow throbs, particles burst
## on every act -- each one was the right call in isolation and nobody has ever
## looked at the total. For a player who gets motion sickness, or who is playing
## on a phone that is already working hard, the total is the only thing that
## matters.
##
## READ, NEVER PUSHED. Nothing subscribes to these and nothing is reconfigured
## when they change: every pulse in the game asks `beat()` for its own amplitude
## at the moment it draws, so turning motion down takes effect on the next frame
## with no wiring at all and nothing can be left in a stale state. Same shape as
## boons.gd, and for the same reason.

const KEY_MOTION := "comfort_motion"
const KEY_EFFECTS := "comfort_effects"
const KEY_BIG_TEXT := "comfort_big_text"

## How much of the authored motion survives when it is turned down. Not zero:
## the guilt mark and the edge arrow are FINDING aids, and a mark that does not
## move at all is one a player genuinely cannot pick out of a busy field. A
## fifth of the amplitude is still visible as a change and is nowhere near
## enough to read as a throb.
const DAMPED := 0.2

## And how much of the particle work survives. Chosen against the pool rather
## than by feel: FxEvents keeps three of each kind, so a density much under a
## third starts making individual bursts invisible rather than merely thinner.
const THIN := 0.4

var motion := true                 ## pulses, bobs, slides
var effects := true                ## particle density
var big_text := false              ## larger UI at the cost of screen space


func load_from(settings) -> void:
	if settings == null:
		return
	motion = bool(settings.get_value(KEY_MOTION, true))
	effects = bool(settings.get_value(KEY_EFFECTS, true))
	big_text = bool(settings.get_value(KEY_BIG_TEXT, false))


func store_in(settings) -> void:
	if settings == null:
		return
	settings.set_value(KEY_MOTION, motion)
	settings.set_value(KEY_EFFECTS, effects)
	settings.set_value(KEY_BIG_TEXT, big_text)
	settings.save_all()


## The multiplier every pulse in the game runs its amplitude through.
func beat() -> float:
	return 1.0 if motion else DAMPED


## The particle density the FX pool should run at.
func density() -> float:
	return 1.0 if effects else THIN


## How many UI units wide the screen should be dealt out in. Fewer units means
## everything is bigger, which is the entire mechanism -- and it is why this is
## a trade rather than a free win: at 320 the buttons are large and there is
## less room for the world behind them.
func ui_units(normal: float) -> float:
	return normal * 0.80 if big_text else normal
