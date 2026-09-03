extends Critter
class_name Wolf

## The one predator in the vale.
##
## A Wolf IS a Critter -- `setup`, the clip indexing, `kind`, `village`, `host`
## and `grid` are all inherited -- but it does not use Critter's own endless
## wander/graze loop. It HUNTS: WANDER until something worth eating comes
## close enough, HUNT it down, EAT it, sit SATED for a while, then WANDER
## again. And simply standing near one costs the village something whether it
## ever catches anything or not -- Trouble is the whole reason a wolf at the
## edge of the map is a thing worth looking at rather than a stat.
##
## `_process` is overridden wholesale rather than layered on top of Critter's.
## The state machine has no analogue in the parent, and Critter's `_amble`
## reads its own `SPEED` unqualified -- GDScript resolves a bare `const` at
## the class where the METHOD is written, not virtually the way a method call
## is, so overriding `const SPEED` here would silently do nothing to
## `Critter._amble`. Movement is reimplemented in `_step` for exactly that
## reason; `_wander()` and `_graze()` stay inherited because those ARE method
## calls and dispatch to whichever override the instance actually has.

enum State { WANDER, HUNT, EAT, SATED }

const WOLF_SPEED := 0.9                 ## quicker than a Critter's SPEED (0.55)
const EAT_SECONDS := 3.0
const SATED_SECONDS := 40.0
const HUNT_RANGE := 12.0
const EAT_RANGE := 0.5
const TROUBLE_RANGE := 3.0
const TROUBLE_EVERY := 0.5
const TROUBLE_FUN := 0.05
const TROUBLE_HEALTH := 0.02

var hp := 3
var state: int = State.WANDER

var _prey = null                        ## the Critter being hunted or eaten
var _state_t := 0.0
var _trouble_t := 0.0


func _process(delta: float) -> void:
	_trouble_t -= delta
	if _trouble_t <= 0.0:
		_trouble_t = TROUBLE_EVERY
		_cause_trouble()

	match state:
		State.WANDER:
			_run_wander(delta)
		State.HUNT:
			_run_hunt(delta)
		State.EAT:
			_state_t -= delta
			if _state_t <= 0.0:
				_finish_eating()
		State.SATED:
			_state_t -= delta
			if _state_t <= 0.0:
				state = State.WANDER
				return
			_run_wander(delta)


## The ordinary amble, plus a check each time it settles on where to go next:
## is there something worth hunting nearby? Only asked from genuine WANDER --
## called again from SATED for the idle movement, and a sated wolf must not
## start a second hunt on top of a meal it is still digesting.
func _run_wander(delta: float) -> void:
	if _walking:
		_step(delta)
		return
	if state == State.WANDER:
		var prey := _nearest_prey()
		if prey != null:
			_prey = prey
			state = State.HUNT
			return
	_wait -= delta
	if _wait <= 0.0:
		_wander()


func _run_hunt(delta: float) -> void:
	if not is_instance_valid(_prey) or host == null or not host.beasts.has(_prey):
		_prey = null
		state = State.WANDER
		_wait = 0.0
		return
	var d: float = position.distance_to(_prey.position)
	if d > HUNT_RANGE:
		_prey = null
		state = State.WANDER
		_wait = 0.0
		return
	if d <= EAT_RANGE:
		_walking = false
		state = State.EAT
		_state_t = EAT_SECONDS
		_play("idle")
		return
	_to = _prey.position
	_walking = true
	_play("walk")
	_step(delta)


func _finish_eating() -> void:
	if is_instance_valid(_prey) and host != null:
		host.remove_beast(_prey)
		if host.divinity != null:
			host.divinity.notice.emit("A wolf took a sheep.")
		if host.fxe != null:
			host.fxe.burst("punish", position + Vector3(0, 0.5, 0))
		if host.sfx != null:
			host.sfx.play("punish")
	_prey = null
	state = State.SATED
	_state_t = SATED_SECONDS
	_wait = 0.0


## The nearest thing worth hunting -- any beast that is not another wolf.
func _nearest_prey() -> Node:
	if host == null:
		return null
	var best = null
	var best_d := HUNT_RANGE
	for b in host.beasts:
		if not is_instance_valid(b) or b == self or b.kind == "Animals/wolf":
			continue
		var d: float = b.position.distance_to(position)
		if d < best_d:
			best_d = d
			best = b
	return best


## Same shape as Critter._amble, at THIS class's own SPEED -- see the class
## comment for why the inherited one cannot simply be reused.
func _step(delta: float) -> void:
	var flat := Vector3(_to.x, position.y, _to.z)
	var step := WOLF_SPEED * delta
	if position.distance_to(flat) <= step:
		position = flat
		_walking = false
		return
	var dir := (flat - position).normalized()
	position += dir * step
	var want := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, want, minf(1.0, delta * 6.0))


## A wolf with no clip named "graze" would otherwise fall back to whatever
## Critter._graze finds -- and the batch spec is explicit that graze is never
## meant to play on this rig at all, so idle stands in for it.
func _graze() -> void:
	_walking = false
	_wait = _rng.randf_range(GRAZE_MIN, GRAZE_MAX)
	_play("idle")


## Everyone near a wolf pays for it, hunting or not -- a wolf sitting at the
## edge of the village doing nothing is still the reason people are afraid.
## The 0.05 health floor mirrors Brain.tick's own strain floor: nobody dies of
## fright, but nobody is unaffected by it either.
func _cause_trouble() -> void:
	if host == null:
		return
	for f in host.folk:
		if not is_instance_valid(f) or f.brain == null:
			continue
		if f.position.distance_to(position) > TROUBLE_RANGE:
			continue
		f.brain.stats["fun"] = maxf(0.0, float(f.brain.stats["fun"]) - TROUBLE_FUN)
		f.brain.stats["health"] = maxf(0.05,
			float(f.brain.stats["health"]) - TROUBLE_HEALTH)
		f.brain.frighten(position)
