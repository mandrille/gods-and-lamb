extends Node3D
class_name CameraRig

## Pan and zoom over the Vale, mouse and touch, one code path for both.
##
## The camera keeps a FIXED angle and orbits nothing: it sits at a constant
## direction from a focus point on the ground and only that focus moves. A god
## game is read from above and a free orbit would let the player look at the
## underside of the world, which is a lot of geometry nobody authored.
##
## Panning is GRAB-THE-GROUND, not "move by mouse delta times a magic number".
## The ray under the cursor is intersected with the ground plane on press, and
## every frame after that the focus moves so that same world point stays under
## the cursor. It costs one plane intersection and it is the difference between
## a map that feels dragged and a map that feels nudged.

signal focus_changed(focus: Vector3)

const DIR := Vector3(-0.72, 0.88, 1.00)   ## Blender's hero angle; -Y is +Z here
const LENS := 35.0                        ## mm on a 36 mm frame

@export var dist := 30.0        ## the map is 48 x 36 m; 17 was a close-up
@export var dist_min := 4.0
@export var dist_max := 70.0
@export var zoom_step := 1.12             ## per wheel notch, multiplicative

## YAW ONLY, and deliberately so.
##
## The fixed angle above is still the rule -- the pitch never changes, so the
## player cannot get under the world or look at geometry nobody authored. What
## right-drag adds is turning ON THE SPOT, which is what you actually want when
## a hut is hiding what is behind it.
var yaw := 0.0
var _turning := false
const TURN_PER_PIXEL := 0.006

var focus := Vector3.ZERO
var bounds_min := Vector3(-24, 0, -18)
var bounds_max := Vector3(24, 0, 18)

var cam: Camera3D
## THE HEIGHT OF THE GROUND THE PLAYER IS LOOKING AT.
##
## This was 0.0 while the walkable surface has always been at `lift` -- 0.5 m,
## the top of a ground tile -- so every ray cast against it landed half a metre
## BELOW the surface, and at this camera's fixed 35.5 degree pitch that
## projects to 0.5 / tan(35.5) = 0.70 m of horizontal error. Tiles are 0.5 m.
## Every ground click was therefore about one and a half tiles short of where
## the player was pointing, consistently, in the same direction.
##
## It reads as two different bugs at once: clicking feels inaccurate, and a
## tree "grows in the wrong place" -- often on a tile at the island's edge or
## under a cliff, where it looks like it spawned underground. Dragging the map
## drifted for the same reason.
var ground_y := 0.0:
	set(value):
		ground_y = value
		_plane = Plane(Vector3.UP, value)
var _plane := Plane(Vector3.UP, 0.0)
var _dragging := false
var _grab := Vector3.ZERO                 ## the world point held under the cursor
var _touches := {}                        ## index -> position
var _pinch_start := 0.0
var _pinch_dist := 0.0


func _ready() -> void:
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.current = true
	cam.near = 0.05
	cam.far = 400.0
	add_child(cam)
	_apply_aspect()
	get_viewport().size_changed.connect(_apply_aspect)
	_place()


## Portrait and landscape want different things from the same lens. In
## landscape the width is the interesting axis; in portrait, holding width
## fixed would crop the world to a letterbox slot, so height leads instead.
func _apply_aspect() -> void:
	var vp := get_viewport().get_visible_rect().size
	var portrait := vp.y > vp.x
	cam.keep_aspect = Camera3D.KEEP_HEIGHT if portrait else Camera3D.KEEP_WIDTH
	var half := 18.0 / LENS
	cam.fov = 2.0 * rad_to_deg(atan(half if not portrait else half * vp.y / max(vp.x, 1.0)))


func set_bounds(lo: Vector3, hi: Vector3) -> void:
	bounds_min = lo
	bounds_max = hi
	_place()


func _place() -> void:
	focus.x = clamp(focus.x, bounds_min.x, bounds_max.x)
	focus.z = clamp(focus.z, bounds_min.z, bounds_max.z)
	focus.y = 0.0
	cam.position = focus + DIR.normalized().rotated(Vector3.UP, yaw) * dist
	cam.look_at(focus, Vector3.UP)
	focus_changed.emit(focus)


## Where the ray through `screen_pos` meets the ground plane, or `null`.
func ground_at(screen_pos: Vector2) -> Variant:
	if cam == null:
		return null
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	return _plane.intersects_ray(from, dir)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(1.0 / zoom_step, mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(zoom_step, mb.position)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_begin_drag(mb.position)
			else:
				_dragging = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_turning = mb.pressed
			# Turning and grabbing the ground at once fights itself: the point
			# under the cursor moves because the camera moved.
			if mb.pressed:
				_dragging = false
	elif event is InputEventMouseMotion and _turning:
		yaw += (event as InputEventMouseMotion).relative.x * TURN_PER_PIXEL
		yaw = wrapf(yaw, -PI, PI)
		_place()
	elif event is InputEventMouseMotion and _dragging:
		_drag_to((event as InputEventMouseMotion).position)

	# Touch. One finger pans, two pinch. The same grab-the-ground code runs for
	# a finger as for the mouse, so the map cannot feel different on a phone.
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			if _touches.size() == 1:
				_begin_drag(st.position)
			elif _touches.size() == 2:
				_dragging = false
				_pinch_dist = _touch_spread()
				_pinch_start = dist
		else:
			_dragging = false
			if _touches.size() == 1:
				_begin_drag(_touches.values()[0])
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if _touches.size() == 1 and _dragging:
			_drag_to(sd.position)
		elif _touches.size() == 2:
			var now := _touch_spread()
			if _pinch_dist > 1.0 and now > 1.0:
				dist = clamp(_pinch_start * (_pinch_dist / now), dist_min, dist_max)
				_place()


## HOW MANY FINGERS ARE DOWN IS NOT A GESTURE, so it is counted here in
## `_input` -- which runs before anything can consume an event -- rather than
## in `_unhandled_input`, which is where the gestures themselves are decided.
##
## Measured: tapping a villager consumes that press (Overhead selects them and
## calls set_input_as_handled). With the bookkeeping down in _unhandled_input
## the rig never learned about that finger, so putting a second one down looked
## like a one-finger pan and PINCH SIMPLY DID NOT WORK if the first finger had
## landed on a person -- which on a village-shaped screen is most of the time.
## Splitting the two also guarantees the release is seen, so a consumed press
## can no longer leave a phantom finger held down forever.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touches[sd.index] = sd.position


func _touch_spread() -> float:
	var v: Array = _touches.values()
	if v.size() < 2:
		return 0.0
	return (v[0] as Vector2).distance_to(v[1] as Vector2)


func _begin_drag(screen_pos: Vector2) -> void:
	var hit: Variant = ground_at(screen_pos)
	if hit == null:
		return
	_grab = hit
	_dragging = true


func _drag_to(screen_pos: Vector2) -> void:
	var hit: Variant = ground_at(screen_pos)
	if hit == null:
		return
	# Move the focus by the error between where the grabbed point IS and where
	# the cursor now points. Solving it this way rather than integrating a
	# delta means the grabbed point cannot drift away over a long drag.
	focus -= (hit as Vector3) - _grab
	_place()


## Zoom toward the cursor rather than toward the middle of the screen: a zoom
## that ignores where you are pointing walks the thing you were looking at off
## the edge of the frame.
func _zoom(factor: float, at: Vector2) -> void:
	var before: Variant = ground_at(at)
	dist = clamp(dist * factor, dist_min, dist_max)
	_place()
	var after: Variant = ground_at(at)
	if before != null and after != null:
		focus -= (after as Vector3) - (before as Vector3)
		_place()
