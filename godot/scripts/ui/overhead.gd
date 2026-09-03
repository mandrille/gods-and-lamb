extends Control
class_name Overhead

## Icons that live above villagers' heads: mood on hover, a speech bubble while
## they are talking.
##
## ONE Control that draws all of them, rather than a Sprite3D or a Label per
## follower. Forty followers with two child nodes each is eighty nodes to
## transform and cull every frame for something that is a dozen circles; this
## projects each head to screen coordinates and draws. It also means the icons
## are always the same size on screen and always face the camera, both of which
## a 3D billboard has to be talked into.
##
## Faces are DRAWN, not typed. Godot's default font has no emoji, so a "🙂" in a
## Label renders as a hollow box -- which is exactly the sort of thing that
## looks fine on the machine with the emoji font installed and ships broken.

signal follower_hovered(who)            ## null when nothing is under the cursor
signal follower_clicked(who)

## Screen pixels around a head that count as "on this villager".
##
## Generous, and it has to be. A villager is about 40 px tall at the play
## camera and MOVING, so a tight radius means the player chases them with the
## cursor and misses -- which was the complaint. This is a soft target the size
## of a fingertip, which is also what makes it work on a phone at all.
##
## The radius is measured from the HEAD, and the body hangs below it, so the
## effective target covers the whole figure rather than a disc floating above.
const PICK_RADIUS := 52.0
const HEAD_HEIGHT := 1.05               ## metres above the follower's origin

const HAPPY := Color(0.36, 0.80, 0.40)
const FLAT := Color(0.94, 0.78, 0.28)
const SAD := Color(0.88, 0.36, 0.34)
const BUBBLE := Color(0.98, 0.98, 0.96)
const INK := Color(0.16, 0.17, 0.20)

## Which glyph names a job. Villager and adventurer are deliberately absent --
## everyone starts as one or the other, so a badge on them would say nothing.
const JOB_ICON := {
	"lumberjack": "axe", "miner": "pick", "builder": "hammer",
	"hunter": "bow", "priest": "cross", "nurse": "bandage", "bard": "lute",
}

var host = null                         ## ValeRoot
var rig = null                          ## CameraRig

var hovered = null
var selected = null

## Set while a villager-only miracle is armed: every villager gets a ring, so
## the player can see who the valid targets ARE rather than hunting for them.
var highlight_all := false

var _mouse := Vector2(-1000, -1000)


func _ready() -> void:
	# The icons must never eat a click meant for the ground: panning is a drag
	# on the world, and a full-screen Control that accepts input would swallow
	# it. Hit-testing is done by hand in _gui_input's place, below.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if host == null or rig == null or rig.cam == null:
		return
	# CANVAS space. under() compares against Camera3D.unproject_position, which
	# is in canvas space, so the raw viewport position missed by the stretch
	# factor -- which is most of why villagers were "super hard to click".
	_mouse = get_local_mouse_position()
	var was = hovered
	hovered = under(_mouse)
	if hovered != was:
		follower_hovered.emit(hovered)
	queue_redraw()


## Followers are picked by SCREEN distance to the head, not by a 3D ray.
##
## They are small, they move, and a ray that has to hit a 40 cm capsule is a
## ray the player misses. A generous screen-space radius is what makes clicking
## a villager feel like clicking a villager. Nearest-to-cursor wins so a crowd
## does not become a lottery.
func under(at: Vector2):
	var best = null
	var best_score := 1.0
	for f in host.folk:
		if not is_instance_valid(f):
			continue
		var feet: Vector3 = f.position
		var head: Vector3 = feet + Vector3(0, HEAD_HEIGHT, 0)
		if rig.cam.is_position_behind(head) or rig.cam.is_position_behind(feet):
			continue
		var ph: Vector2 = rig.cam.unproject_position(head)
		var pf: Vector2 = rig.cam.unproject_position(feet)
		# The target is a CAPSULE from feet to head, widened, not a disc around
		# the head. Zoomed in, a fixed disc covers the hat and misses the body;
		# zoomed out it is larger than the villager. Measuring the figure on
		# screen makes the target the right size at every distance.
		var tall: float = maxf(ph.distance_to(pf), 8.0)
		var radius: float = maxf(PICK_RADIUS, tall * 0.62)
		var d: float = _to_segment(at, pf, ph)
		# Normalised, so the NEAREST villager wins even when their targets are
		# different sizes -- comparing raw distances would favour whoever
		# happens to be closest to the camera.
		var score := d / radius
		if score < 1.0 and score < best_score:
			best_score = score
			best = f
	return best


## Distance from a point to a line segment. Villagers are tall and thin on
## screen, and a point-to-point test against either end leaves a gap in the
## middle of the body -- which is exactly where people aim.
static func _to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Input is taken from _unhandled_input rather than _gui_input so the camera
## still gets drags that start on empty ground. A click on a villager is
## consumed; a click anywhere else is left alone.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	var hit = under(make_input_local(mb).position)
	if hit == null:
		return
	selected = hit
	follower_clicked.emit(hit)
	get_viewport().set_input_as_handled()


func _draw() -> void:
	if host == null or rig == null or rig.cam == null:
		return
	for f in host.folk:
		if not is_instance_valid(f) or f.brain == null:
			continue
		var head: Vector3 = f.position + Vector3(0, HEAD_HEIGHT, 0)
		if rig.cam.is_position_behind(head):
			continue
		var p: Vector2 = rig.cam.unproject_position(head)

		# A JOB BADGE, only while the player is already looking at this one --
		# permanently visible on forty followers would be forty small icons
		# competing with everything else on screen.
		if (f == hovered or f == selected or highlight_all) \
				and JOB_ICON.has(f.brain.job):
			Icons.draw_icon(self, String(JOB_ICON[f.brain.job]),
							p + Vector2(14, -10), 14.0)

		# GUILT IS THE ONE THING ALWAYS WORTH DRAWING.
		#
		# It is drawn for everyone, unhovered and unselected, because it is the
		# player's cue to act and it expires in a few seconds -- a mark you
		# only see by hovering is a mark you never see. It sits above the chat
		# bubble in priority for the same reason.
		if host.divinity != null and host.divinity._is_guilty(f):
			_guilt(p)
			continue
		if f.brain.chatting_with != "":
			_speech(p)
			continue
		# The mood face is a hover affordance (item 1), plus a permanent one on
		# whoever is selected so the open panel and the world agree.
		if highlight_all and f != hovered and f != selected:
			_ground_ring(f, false)
		if f == hovered or f == selected:
			_ground_ring(f, f == selected)
			_face(p, f.brain.mood_face(), f == selected)


## A hot mark over a wrongdoer, pulsing so the eye finds it in a crowd.
func _guilt(p: Vector2) -> void:
	var t := float(Time.get_ticks_msec()) * 0.006
	var pulse := 1.0 + sin(t) * 0.14
	var r := 11.0 * pulse
	var hot := Color(1.0, 0.35, 0.28)
	draw_circle(p + Vector2(0, -2), r + 3.0, Color(0.10, 0.02, 0.02, 0.55))
	draw_circle(p + Vector2(0, -2), r, hot)
	# A bolt, the same glyph the punish button uses, so the two read as one
	# idea: this is the thing that button is for.
	var c := p + Vector2(0, -2)
	var pts := PackedVector2Array([
		c + Vector2(-1.0, -6.5) * pulse, c + Vector2(3.2, -1.2) * pulse,
		c + Vector2(0.4, -1.2) * pulse, c + Vector2(1.6, 6.5) * pulse,
		c + Vector2(-2.8, 0.6) * pulse, c + Vector2(0.0, 0.6) * pulse])
	draw_colored_polygon(pts, Color(0.16, 0.05, 0.05))


## A ring on the ground at the villager's feet, projected from four points of
## a circle in WORLD space so it sits flat in perspective. A screen-space
## circle under the feet reads as a sticker on the lens.
func _ground_ring(f, strong: bool) -> void:
	var pts := PackedVector2Array()
	var r := 0.34
	for i in 20:
		var a := TAU * float(i) / 20.0
		var w: Vector3 = f.position + Vector3(cos(a) * r, 0.03, sin(a) * r)
		if rig.cam.is_position_behind(w):
			return
		pts.append(rig.cam.unproject_position(w))
	pts.append(pts[0])
	draw_polyline(pts, Color(1, 1, 1, 0.85 if strong else 0.45),
				  2.5 if strong else 1.8)


func _face(at: Vector2, kind: String, ring: bool) -> void:
	var r := 13.0
	var tint := FLAT
	match kind:
		"happy": tint = HAPPY
		"sad": tint = SAD
	draw_circle(at, r + 2.0, Color(0, 0, 0, 0.28))
	draw_circle(at, r, tint)
	if ring:
		draw_arc(at, r + 4.0, 0.0, TAU, 28, Color(1, 1, 1, 0.85), 2.0)

	var eye := Vector2(4.6, -3.4)
	draw_circle(at + Vector2(-eye.x, eye.y), 1.9, INK)
	draw_circle(at + Vector2(eye.x, eye.y), 1.9, INK)

	# The mouth carries the whole reading, so it is three distinct shapes
	# rather than one arc with a changing sign -- a flat mouth drawn as a very
	# shallow curve reads as "slightly happy", which is a different answer.
	match kind:
		"happy":
			draw_arc(at + Vector2(0, -1.0), 6.4, deg_to_rad(25),
					 deg_to_rad(155), 18, INK, 2.0)
		"sad":
			draw_arc(at + Vector2(0, 7.0), 6.4, deg_to_rad(205),
					 deg_to_rad(335), 18, INK, 2.0)
		_:
			draw_line(at + Vector2(-5.0, 3.4), at + Vector2(5.0, 3.4), INK, 2.0)


## A little rounded bubble with three dots: the "they are talking" tell the
## design asks for (item 15).
func _speech(at: Vector2) -> void:
	var w := 26.0
	var h := 17.0
	var box := Rect2(at.x - w * 0.5, at.y - h - 6.0, w, h)
	draw_rect(Rect2(box.position + Vector2(0, 2), box.size),
			  Color(0, 0, 0, 0.25), true)
	draw_rect(box, BUBBLE, true)
	# Tail.
	var tip := Vector2(at.x, at.y + 2.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(at.x - 4.0, box.position.y + h),
		Vector2(at.x + 4.0, box.position.y + h), tip]), BUBBLE)
	for i in 3:
		draw_circle(Vector2(box.position.x + 7.0 + i * 6.0,
							box.position.y + h * 0.5), 1.7, INK)
