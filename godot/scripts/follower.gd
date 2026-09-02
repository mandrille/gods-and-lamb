extends Node3D
class_name Follower

## One villager: a body, a mind, and a small state machine between them.
##
## No physics, no navigation mesh, no character body. The path is a list of
## tile coordinates and the follower lerps between them, turning to face the
## way it is going. That is the whole movement model and it is deliberate: this
## is an idle game where many of these may be on screen at once on a phone, and
## a CharacterBody3D each would spend the entire frame budget on a walk.
##
## The state machine is four states and no more:
##
##   WALK    following a route to somewhere it decided to go
##   WORK    standing at the destination playing a job animation
##   TALK    held in place by the social layer, facing someone
##   IDLE    nothing to do; waits a beat and thinks again
##
## Errands END rather than loop. A hand-authored patrol loops. Treating those
## the same was the bug waiting to happen here: an errand that wraps round to
## its start is a follower that never arrives anywhere, and every action would
## fire forever.

signal arrived_at(action: String)
signal finished(action: String)

enum State { IDLE, WALK, WORK, TALK }

## Metres per second. The walk cycle's stride was authored in Blender; if this
## is faster than the stride the feet skate, and if it is slower they moonwalk.
## STRIDE_PER_CYCLE is measured from the clip, not guessed.
const STRIDE_PER_CYCLE := 0.46     ## metres of ground covered per full cycle
const CYCLE_SECONDS := 1.0         ## 24 frames at 24 fps

const NAMES := ["Bram", "Hana", "Odo", "Pell", "Wren", "Tam", "Gil", "Mira",
				"Corin", "Ysolde", "Fen", "Rook", "Alia", "Dov", "Nell",
				"Sable", "Quill", "Bex", "Tolly", "Marn"]

var speed := STRIDE_PER_CYCLE / CYCLE_SECONDS
var path: Array[Vector3] = []

var grid: WalkGrid = null
var brain: Brain = null
var state: int = State.IDLE

var _idle := 0.0
var _leg := 0
var _t := 0.0
var _anim: AnimationPlayer = null
var _clips: Dictionary = {}        ## logical name -> clip name in the GLB
var _walk_scale := 1.0
## The speed this follower was born with, before any boon. Kept so a boost is
## applied to the original rather than compounding on itself every time the
## god takes another rank.
var _base_walk := 1.0
var _pending := ""                 ## the action to start once we arrive
## How small a newborn is, and how big they end up. Applied to the GLB CHILD
## node rather than to the Follower itself, because the Follower's own
## transform is what the movement code writes every frame -- scaling it there
## would be overwritten, silently, and children would grow up instantly.
const CHILD_SCALE := 0.52
var _body: Node3D = null
var _shown_scale := -1.0
## A hand-authored patrol LOOPS; a brain-chosen errand ENDS. One flag, set at
## the two entry points, rather than inferring it from whether `brain` is null
## -- the perf harness gives followers a brain AND a fixed path.
var _loop := false

## Diagnostics. Cheap counters, read by tools/idle_probe.gd, because "they look
## idle" is a symptom with at least four different causes -- no destination, no
## route, the job refused, or simply a long walk -- and they are indistinguish-
## able from outside.
var n_replans := 0
var n_no_target := 0
var n_no_route := 0
var n_refused := 0
var n_started := 0


## Give the follower a mind and a map and it decides for itself.
func think(walk_grid: WalkGrid, seed_value: int, walk_speed_scale := 1.0,
		   village = null, boons = null) -> void:
	grid = walk_grid
	brain = Brain.new(seed_value)
	brain.name = NAMES[seed_value % NAMES.size()]
	brain.village = village
	brain.grid = walk_grid
	brain.boons = boons
	name = "Follower_%s" % brain.name
	speed = (STRIDE_PER_CYCLE / CYCLE_SECONDS) * walk_speed_scale
	_walk_scale = walk_speed_scale
	_base_walk = walk_speed_scale
	_loop = false
	_body = get_child(0) as Node3D if get_child_count() > 0 else null
	_index_clips()
	_replan()


## HOW MANY VILLAGERS MAY THINK IN ONE FRAME.
##
## A replan runs A* across a ~100x100 grid, and fifty villagers spawned
## together drift into step: their idle timers expire on the same frame, fifty
## paths are solved at once and the frame takes 38 ms instead of 7. The work is
## not too expensive, it is too BUNCHED.
##
## Deferred villagers retry on the very next frame, so at 60 fps the whole
## village still re-decides several times a second and nothing visibly waits.
const REPLAN_BUDGET := 6
static var _replan_frame := -1
static var _replans_now := 0


static func _claim_replan_slot() -> bool:
	var f := int(Engine.get_process_frames())
	if f != _replan_frame:
		_replan_frame = f
		_replans_now = 0
	if _replans_now >= REPLAN_BUDGET:
		return false
	_replans_now += 1
	return true


func _replan() -> void:
	if grid == null or brain == null:
		return
	var here := grid.cell_of(position)
	if not grid.is_walkable(here):
		here = grid.beside(here, brain.rng)
		if here.x < 0:
			_wait()
			return
		position = grid.world_of(here)

	n_replans += 1
	# Before the decision, not after: the brain vetoes actions it cannot reach
	# and it can only do that if it knows where the body is standing.
	brain.at_cell = here
	var act := brain.choose_action()
	# "talk" is not a place. The social layer pairs people up when they happen
	# to be near each other, so wanting company means wandering where company
	# is, not walking to a Conversation Building.
	if act == "talk" or act == "":
		_wander()
		return

	# Up to a few tries: a destination can be genuinely unreachable -- the far
	# bank without a bridge in range, or high ground with no ramp -- and
	# treating that as an error would freeze the follower forever.
	var had_target := false
	for attempt in 3:
		var to := brain.destination_for(grid, here, act)
		if to.x < 0:
			break
		had_target = true
		if _route_to(to, act):
			return
	if had_target:
		n_no_route += 1
	else:
		n_no_target += 1
	_wander()


## Drift somewhere NEARBY when there is nothing to do.
##
## This used to be `grid.random_cell()`. On one plot that is ~9 m of pointless
## walking; the moment a second plot is bought it is a 34 m map, and a villager
## with no valid job walks twenty seconds to nowhere and then re-decides. At
## eight villagers that is a village that looks broken, right at the minute the
## player has just spent Faith on the land.
func _wander() -> void:
	var here := grid.cell_of(position)
	_route_to(brain.near_cell(grid, here, 10), "")


func _route_to(to: Vector2i, act: String) -> bool:
	var here := grid.cell_of(position)
	if to.x < 0 or not grid.is_walkable(to):
		return false
	# Already standing where we want to be: skip the walk rather than emitting
	# a one-point path the movement code would treat as "nothing to do".
	if to == here:
		_pending = act
		_begin_work()
		return true
	var route := grid.path_world(here, to)
	if route.size() < 2:
		return false
	path = route
	_leg = 0
	_t = 0.0
	_pending = act
	state = State.WALK
	_play("walk")
	# COMMITTED: hold the ground until we get there, so no one else is sent to
	# the same spot. Claimed here rather than when the site was chosen, because
	# choosing happens far more often than going.
	if act != "" and brain.village != null:
		var spec: Dictionary = Brain.ACTIONS.get(act, {})
		if String(spec.get("builds", "")) != "":
			var radius: int = maxi(1, int(ceil(
				float(spec.get("clear", 2.0)) / grid.tile / 2.0)))
			brain.village.claim_site(to, radius)
	return true


func _begin_work() -> void:
	var act := _pending
	_pending = ""
	path.clear()
	if act == "" or brain == null:
		_wait()
		return
	if not brain.begin_action(act):
		n_refused += 1
		_wait()
		return
	n_started += 1
	state = State.WORK
	var spec: Dictionary = Brain.ACTIONS[act]
	_play(String(spec.get("anim", "idle")))
	arrived_at.emit(act)


func _wait() -> void:
	state = State.IDLE
	path.clear()
	_play("idle")
	_idle = 0.5 + (brain.rng.randf() * 1.6 if brain != null else 1.0)


## Born rather than arrived: start small, and grow over ADULT_AT seconds.
func become_child() -> void:
	if brain == null:
		return
	brain.adult = false
	brain.age = 0.0
	# Children walk shorter strides. Left at the adult speed a toddler skates,
	# because the clip and the ground speed are tied together.
	speed *= 0.72
	_walk_scale *= 0.72
	_apply_growth()


## Scale follows age, so a child visibly becomes an adult instead of popping.
func _apply_growth() -> void:
	if _body == null or brain == null:
		return
	var t: float = 1.0 if brain.adult else clampf(
		brain.age / Brain.ADULT_AT, 0.0, 1.0)
	var want := lerpf(CHILD_SCALE, 1.0, t)
	# Only written when it actually moved. Assigning a scale every frame to
	# every follower dirties a transform that has not changed.
	if absf(want - _shown_scale) < 0.004:
		return
	_shown_scale = want
	_body.scale = Vector3(want, want, want)


func is_child() -> bool:
	return brain != null and not brain.adult


## Swift Feet. BOTH numbers, always: `_play` feeds `_walk_scale` to the clip's
## speed_scale, so writing only `speed` makes the whole village skate.
func set_walk_boost(boost: float) -> void:
	var base: float = _base_walk * boost
	speed = (STRIDE_PER_CYCLE / CYCLE_SECONDS) * base
	_walk_scale = base
	if _anim != null and _anim.current_animation == String(_clips.get("walk", "")):
		_anim.speed_scale = base


## --- the social layer drives these ------------------------------------------

func stop_and_face(at: Vector3) -> void:
	state = State.TALK
	path.clear()
	_play("idle")
	var d := at - position
	d.y = 0.0
	if d.length_squared() > 0.0001:
		rotation.y = atan2(d.x, d.z)


func resume() -> void:
	if state == State.TALK:
		_wait()


## --- animation --------------------------------------------------------------
##
## Clips are matched by SUBSTRING against whatever the GLB actually contains,
## and the map is built once. Keying on an exact clip name would break the day
## an artist renames "walk" to "Walk_01", and keying on index would break the
## day one is inserted. A missing clip falls back rather than to nothing,
## because a follower frozen in T-pose reads as a crash.

func _index_clips() -> void:
	_anim = _find_anim(self)
	if _anim == null:
		push_warning("Follower: no AnimationPlayer in the GLB -- it will slide")
		return
	var have := _anim.get_animation_list()
	for want in ["walk", "idle", "pickup", "chop"]:
		for n in have:
			if want in String(n).to_lower():
				_clips[want] = String(n)
				break
	if not _clips.has("walk") and have.size() > 0:
		_clips["walk"] = String(have[0])
	for n in _clips.values():
		var clip := _anim.get_animation(String(n))
		if clip != null:
			clip.loop_mode = Animation.LOOP_LINEAR


func _play(which: String) -> void:
	if _anim == null:
		return
	var fallback: String = String(_clips.get("idle", _clips.get("walk", "")))
	var clip_name := String(_clips.get(which, fallback))
	if clip_name == "":
		return
	if _anim.current_animation == clip_name:
		return
	_anim.play(clip_name)
	# Only the walk has to keep pace with the ground. A chop played at 1.3x
	# because this follower happens to walk fast just looks wrong.
	_anim.speed_scale = _walk_scale if which == "walk" else 1.0
	# Start at a different point in the cycle, or a crowd marches in lockstep
	# and reads as one animation on many bodies. Not the chop: a swing that
	# starts halfway through begins with the axe already coming down.
	var clip := _anim.get_animation(clip_name)
	if clip != null and which != "chop":
		_anim.seek(randf() * clip.length, true)


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var found := _find_anim(c)
		if found != null:
			return found
	return null


## --- the loop ---------------------------------------------------------------

func _process(delta: float) -> void:
	if brain == null:
		return
	var was := brain.action
	brain.tick(delta)
	if not brain.adult or _shown_scale < 1.0:
		_apply_growth()
	# The brain owns the job timer, so the body learns the job is done by
	# watching it clear. One clock, not two, or the animation and the payout
	# drift apart.
	if was != "" and brain.action == "" and state == State.WORK:
		finished.emit(was)
		_wait()
		return

	match state:
		State.WALK:
			_advance(delta)
		State.IDLE:
			_idle -= delta
			if _idle <= 0.0:
				if _claim_replan_slot():
					_replan()
				else:
					_idle = 0.001      # somebody else is thinking; next frame
		State.WORK, State.TALK:
			pass


## Move to the next leg. Returns true if the route ENDED and the caller must
## stop touching `path` -- which it must, because arriving starts a job that
## clears it.
func _step_leg() -> bool:
	_leg += 1
	if _leg < path.size() - 1:
		return false
	if _loop:
		_leg = _leg % path.size()
		return false
	position = path[path.size() - 1]
	_begin_work()
	return true


func _advance(delta: float) -> void:
	if path.size() < 2:
		_begin_work()
		return
	var a: Vector3 = path[_leg]
	var b: Vector3 = path[(_leg + 1) % path.size()]
	var span := a.distance_to(b)
	if span < 0.001:
		if _step_leg():
			return
		return
	_t += (speed * delta) / span
	while _t >= 1.0:
		_t -= 1.0
		if _step_leg():
			return
		a = path[_leg]
		b = path[(_leg + 1) % path.size()]
		span = maxf(a.distance_to(b), 0.001)
	position = a.lerp(b, _t)

	# Face the way we are going.
	#
	# The mesh fronts +Z in Godot, NOT -Z, and getting that backwards is what
	# had every villager moonwalking. glTF Y-up maps Blender (x, y, z) to
	# (x, z, -y), so Blender's -Y front becomes +Z here -- the opposite of the
	# -Z that Godot's own `look_at` and every tutorial assume.
	var heading := b - a
	heading.y = 0.0
	if heading.length_squared() > 0.000001:
		rotation.y = atan2(heading.x, heading.z)


## Kept for the perf harness and any hand-authored patrol, which want a fixed
## loop and no mind at all.
func setup(points: Array, walk_speed_scale := 1.0) -> void:
	path.clear()
	for p in points:
		path.append(p as Vector3)
	speed = (STRIDE_PER_CYCLE / CYCLE_SECONDS) * walk_speed_scale
	_walk_scale = walk_speed_scale
	_loop = true
	_index_clips()
	if path.size() >= 2:
		state = State.WALK
		_play("walk")


## What the hover icon and the panel ask for.
func mood_face() -> String:
	return brain.mood_face() if brain != null else "flat"


func is_chatting() -> bool:
	return brain != null and brain.chatting_with != ""
