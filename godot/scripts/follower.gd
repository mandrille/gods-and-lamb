extends Node3D
class_name Follower

## A follower walking a looped path.
##
## No physics, no navigation mesh, no character body. The path is a list of tile
## coordinates and the follower lerps between them, turning to face the way it
## is going. That is the whole movement model and it is deliberate: this is an
## idle game where a hundred of these may be on screen at once on a phone, and a
## CharacterBody3D each would spend the entire frame budget on a walk.
##
## The WALK CLIP is what makes it read. The rig is seven bones and one 24-frame
## cycle, exported in the same GLB as the mesh; the clip plays on loop the whole
## time and the tween supplies the ground speed. Getting those two to agree is
## the one thing that matters here -- see `speed`.

## Metres per second. The walk cycle's stride was authored in Blender; if this
## is faster than the stride the feet skate, and if it is slower they moonwalk.
## STRIDE_PER_CYCLE is measured from the clip, not guessed.
const STRIDE_PER_CYCLE := 0.46     ## metres of ground covered per full cycle
const CYCLE_SECONDS := 1.0         ## 24 frames at 24 fps

var speed := STRIDE_PER_CYCLE / CYCLE_SECONDS
var path: Array[Vector3] = []

## Set these and the follower runs its own errands: it asks the brain where to
## go, asks the grid how to get there, walks it, and asks again on arrival.
## Left null it falls back to the fixed loop it was given, which is what the
## perf harness and any hand-authored patrol want.
var grid: WalkGrid = null
var brain: Brain = null
var _idle := 0.0
var _leg := 0
var _t := 0.0
var _anim: AnimationPlayer = null


## Give the follower a brain and a map and it decides for itself.
##
## The path is REPLANNED on arrival rather than being a loop, which is the
## whole difference between a patrol and a villager: where it goes next depends
## on what it wants next, and two followers with the same needs at different
## times take different errands.
func think(walk_grid: WalkGrid, seed_value: int, walk_speed_scale := 1.0) -> void:
	grid = walk_grid
	brain = Brain.new(seed_value)
	speed = (STRIDE_PER_CYCLE / CYCLE_SECONDS) * walk_speed_scale
	_start_anim(walk_speed_scale)
	_replan()


func _replan() -> void:
	if grid == null or brain == null:
		return
	var here := grid.cell_of(position)
	if not grid.is_walkable(here):
		here = grid.beside(here)
		if here.x < 0:
			return
		position = grid.world_of(here)
	# Up to a few tries: a destination can be genuinely unreachable -- the far
	# bank without a bridge in range, or the hill, which has no ramp at all --
	# and treating that as an error would freeze the follower forever.
	for attempt in 4:
		var to := brain.destination(grid, here)
		if to.x < 0:
			continue
		var route := grid.path_world(here, to)
		if route.size() >= 2:
			path = route
			_leg = 0
			_t = 0.0
			return
	path.clear()
	_idle = 1.0 + brain.rng.randf() * 2.0


func setup(points: Array, walk_speed_scale := 1.0) -> void:
	path.clear()
	for p in points:
		path.append(p as Vector3)
	speed = (STRIDE_PER_CYCLE / CYCLE_SECONDS) * walk_speed_scale
	_start_anim(walk_speed_scale)


func _start_anim(walk_speed_scale: float) -> void:
	_anim = _find_anim(self)
	if _anim == null:
		push_warning("Follower: no AnimationPlayer in the GLB -- it will slide")
		return
	var name := _walk_clip(_anim)
	if name == "":
		push_warning("Follower: no walk clip; have %s"
			% ", ".join(_anim.get_animation_list()))
		return
	# The clip loops. A one-shot clip on a walking character stops mid-stride
	# and the follower slides the rest of the way with its legs still.
	var clip := _anim.get_animation(name)
	clip.loop_mode = Animation.LOOP_LINEAR
	_anim.play(name)
	# Speed scale, so the cycle keeps pace with the ground. Same reason as
	# above: the tween and the clip have to agree or the feet lie.
	_anim.speed_scale = walk_speed_scale
	# Start each follower at a different point in the cycle. Otherwise a crowd
	# marches in lockstep, which reads as one animation on many bodies.
	_anim.seek(randf() * clip.length, true)


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var found := _find_anim(c)
		if found != null:
			return found
	return null


func _walk_clip(ap: AnimationPlayer) -> String:
	for n in ap.get_animation_list():
		if "walk" in String(n).to_lower():
			return n
	var all := ap.get_animation_list()
	return all[0] if all.size() > 0 else ""


func _process(delta: float) -> void:
	if brain != null:
		brain.tick(delta)
	if path.size() < 2:
		# Nothing to walk. If a brain is driving, wait a moment and think
		# again rather than spinning on a replan every frame.
		if brain != null:
			_idle -= delta
			if _idle <= 0.0:
				_replan()
		return
	var a: Vector3 = path[_leg]
	var b: Vector3 = path[(_leg + 1) % path.size()]
	var span := a.distance_to(b)
	if span < 0.001:
		_leg = (_leg + 1) % path.size()
		return
	_t += (speed * delta) / span
	while _t >= 1.0:
		_t -= 1.0
		_leg += 1
		# A brain-driven route ENDS. A hand-authored patrol loops. Treating the
		# two the same was the bug waiting to happen here: an errand that wraps
		# round to its start is a follower that never arrives anywhere.
		if brain != null and _leg >= path.size() - 1:
			position = path[path.size() - 1]
			brain.arrived()
			_idle = 0.4 + brain.rng.randf() * 1.2
			path.clear()
			return
		_leg = _leg % path.size()
		a = path[_leg]
		b = path[(_leg + 1) % path.size()]
		span = max(a.distance_to(b), 0.001)
	position = a.lerp(b, _t)

	# Face the way we are going.
	#
	# The mesh fronts +Z in Godot, NOT -Z, and getting that backwards is what
	# had every villager moonwalking. glTF Y-up maps Blender (x, y, z) to
	# (x, z, -y), so Blender's -Y front becomes +Z here -- the opposite of the
	# -Z that Godot's own `look_at` and every tutorial assume.
	#
	# With +Z forward the yaw is plain atan2 of the heading and nothing else.
	# The half-turn that used to be here was correcting for a convention this
	# mesh does not follow.
	var heading := b - a
	heading.y = 0.0
	if heading.length_squared() > 0.000001:
		rotation.y = atan2(heading.x, heading.z)
