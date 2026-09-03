extends Control
class_name MiracleGauge

## The one thing on screen that says "the miracle is HERE, and here is how
## long you have left" -- a bar over the cursor and a ring on the ground
## under it, drawn in the same idiom Overhead uses for a villager's mood
## face and guilt mark: project the 3D point, draw 2D on top.
##
## Two things a held miracle needs to communicate that the cloud mesh alone
## does not: how much time is LEFT (the cloud shrinks for no other reason,
## so a bar is the only legible clock), and exactly which PATCH OF GROUND is
## being touched right now, since sweeping across the right people is the
## entire mechanic. Both answer "reported: the fx doesn't follow the mouse" --
## whatever was or was not true of the cloud itself, this cannot be missed.

var cursor: MiracleCursor
var rig: CameraRig

const BAR_W := 84.0
const BAR_H := 8.0
const RING_SEGMENTS := 28


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if cursor == null or rig == null or rig.cam == null or not cursor.is_active():
		return
	var anchor: Vector3 = cursor.global_position
	if rig.cam.is_position_behind(anchor):
		return

	_ring(anchor - Vector3(0, MiracleCursor.HEIGHT, 0), cursor.radius,
		  _tint())
	# Clearance derived from the cloud's OWN geometry, not guessed. The puffs
	# in _build_cloud sit up to 0.28 m above the cloud's own origin plus their
	# own radius (up to ~1.0 m at `scale` 1.0), scaled by `radius / 4.5` the
	# same way the puffs themselves are -- so this clears the tallest sphere
	# by a small margin at any card radius instead of a constant tuned for
	# one size. A first version scaled off the raw radius rather than that
	# same ratio and overshot badly: the bar landed above the top of a
	# 720-tall frame and was invisible.
	var scale := cursor.radius / 4.5
	var clear := 1.28 * scale + 0.35
	_bar(rig.cam.unproject_position(anchor + Vector3(0, clear, 0)),
		 cursor.time_left_ratio())


func _tint() -> Color:
	var spec: Dictionary = MiracleCursor.LOOK.get(cursor.id, {})
	return spec.get("tint", Color.WHITE)


## The affected patch of ground, drawn flat in world space so it reads
## correctly in perspective rather than as a sticker on the lens -- same
## technique as Overhead._ground_ring, just centred on the cursor instead of
## a villager's feet and sized to the actual radius that is being swept.
func _ring(ground: Vector3, radius: float, tint: Color) -> void:
	var pts := PackedVector2Array()
	for i in RING_SEGMENTS:
		var a := TAU * float(i) / float(RING_SEGMENTS)
		var w := ground + Vector3(cos(a) * radius, 0.04, sin(a) * radius)
		if rig.cam.is_position_behind(w):
			return
		pts.append(rig.cam.unproject_position(w))
	pts.append(pts[0])
	draw_polyline(pts, Color(tint.r, tint.g, tint.b, 0.9), 2.5)
	draw_polyline(pts, Color(0, 0, 0, 0.35), 5.0)
	draw_polyline(pts, Color(tint.r, tint.g, tint.b, 0.9), 2.5)


## A shrinking bar above the cloud. The one clock a player casting a miracle
## actually needs -- everything else about "how long have I got" is buried in
## a mesh that is also moving and rotating.
func _bar(p: Vector2, ratio: float) -> void:
	# Clamped onto the screen as a safety net: the geometry-derived clearance
	# above is an estimate, not a guarantee, and a bar that can drift off the
	# top edge on some camera angle is worse than one that is merely a little
	# close to the cloud.
	var y := clampf(p.y - 10.0, 6.0, get_viewport_rect().size.y - BAR_H - 6.0)
	var r := Rect2(p.x - BAR_W * 0.5, y, BAR_W, BAR_H)
	draw_rect(Rect2(r.position + Vector2(0, 2), r.size),
			  Color(0, 0, 0, 0.35), true)
	draw_rect(r, Color(0.06, 0.07, 0.10, 0.85), true)
	var tint := _tint()
	# Amber in the last quarter, so the player is warned before the cloud
	# simply vanishes mid-sweep.
	var fill := tint if ratio > 0.25 else Color(0.95, 0.62, 0.30)
	if ratio > 0.0:
		draw_rect(Rect2(r.position, Vector2(r.size.x * ratio, r.size.y)),
				  fill, true)
	draw_rect(r, Color(1, 1, 1, 0.5), false, 1.0)
