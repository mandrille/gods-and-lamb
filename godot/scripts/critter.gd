extends Node3D
class_name Critter

## A sheep or a cow: it wanders, it grazes, and it gives something back.
##
## Deliberately NOT a Follower. A Follower carries seven needs, a personality, a
## memory, a morality, a job queue and a pathfinder, and an animal wants none of
## it -- a sheep that can be lonely, blessed, tempted into theft and offered a
## boon is a worse sheep, not a richer one. This is a hundred lines that walk
## somewhere, chew, and top the stores up.
##
## They also do not path. A Follower uses AStarGrid2D because it has an errand
## and must arrive; livestock only need to end up somewhere near, so they pick
## an adjacent walkable cell and amble to it. That keeps a herd off the
## pathfinder entirely, which matters because there are more of them than there
## are people.

## Seconds between one yield and the next, before any variation.
const PRODUCE_EVERY := 26.0
## How long they stand and graze between walks.
const GRAZE_MIN := 3.0
const GRAZE_MAX := 8.0
const SPEED := 0.55

## What each kind is worth when it produces. Milk and wool are both `food`
## because that is the only produce this village actually models -- inventing a
## `wool` store nothing consumes would be a counter that never moves.
const YIELD := {
	"Animals/cow": {"amount": 3, "label": "milk"},
	"Animals/sheep": {"amount": 2, "label": "wool"},
}

var grid = null
var village = null
var host = null
var kind := ""

var _to := Vector3.ZERO
var _walking := false
var _wait := 0.0
var _clock := 0.0
var _anim: AnimationPlayer = null
var _clips: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func setup(asset_id: String, at: Vector3, g, v, h) -> void:
	kind = asset_id
	grid = g
	village = v
	host = h
	position = at
	_rng.randomize()
	# Spread the first yield out, or a herd bought together pays in one lump
	# every twenty-six seconds forever and reads as a machine rather than a
	# field of animals.
	_clock = _rng.randf_range(0.0, PRODUCE_EVERY)
	_index_clips()
	_graze()


func _index_clips() -> void:
	_anim = _find_anim(self)
	if _anim == null:
		return
	for name in _anim.get_animation_list():
		var n := String(name)
		var low := n.to_lower()
		for want in ["walk", "idle", "graze"]:
			if low.contains(want) and not _clips.has(want):
				_clips[want] = n


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var found := _find_anim(c)
		if found != null:
			return found
	return null


func _play(which: String) -> void:
	if _anim == null:
		return
	var clip := String(_clips.get(which, _clips.get("idle", "")))
	if clip == "" or _anim.current_animation == clip:
		return
	_anim.play(clip)
	var a := _anim.get_animation(clip)
	if a != null:
		_anim.seek(_rng.randf() * a.length, true)


func _process(delta: float) -> void:
	_produce(delta)
	if _walking:
		_amble(delta)
		return
	_wait -= delta
	if _wait <= 0.0:
		_wander()


func _produce(delta: float) -> void:
	if village == null:
		return
	_clock -= delta
	if _clock > 0.0:
		return
	_clock = PRODUCE_EVERY * _rng.randf_range(0.85, 1.15)
	var spec: Dictionary = YIELD.get(kind, {})
	if spec.is_empty():
		return
	var amount := int(spec["amount"])
	village.give({"food": amount})
	# Said where it happened. A trickle the player cannot see is a number in a
	# spreadsheet, and the whole reason to put animals in the field rather than
	# a bonus in a menu is that you can watch them earn it.
	if host != null and host.floaters != null:
		host.floaters.spawn("food", "food", amount,
							position + Vector3(0, 0.7, 0))


func _wander() -> void:
	if grid == null:
		_wait = 2.0
		return
	var here: Vector2i = grid.cell_of(position)
	for attempt in 12:
		var c := here + Vector2i(_rng.randi_range(-4, 4),
								 _rng.randi_range(-4, 4))
		if not grid.is_walkable(c):
			continue
		# Same region, or the sheep walks into the river trying to reach a
		# meadow it can see and cannot get to.
		if not grid.reachable(here, c):
			continue
		_to = grid.world_of(c)
		_walking = true
		_play("walk")
		return
	_graze()


func _amble(delta: float) -> void:
	var flat := Vector3(_to.x, position.y, _to.z)
	var step := SPEED * delta
	if position.distance_to(flat) <= step:
		position = flat
		_graze()
		return
	var dir := (flat - position).normalized()
	position += dir * step
	# Face the way they are going. The mesh fronts +Z in Godot, the same
	# convention the followers use.
	var want := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, want, minf(1.0, delta * 6.0))


func _graze() -> void:
	_walking = false
	_wait = _rng.randf_range(GRAZE_MIN, GRAZE_MAX)
	_play("graze")
