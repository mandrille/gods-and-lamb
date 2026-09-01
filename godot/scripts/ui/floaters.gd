extends Control
class_name Floaters

## "+3 wood" lifting off a villager and flying to the wood counter.
##
## This is the only thing that tells the player their village is WORKING. A
## chop played an animation, a number changed in a corner, and nothing joined
## the two -- so the report was "I've seen them interact with trees, but it
## feels like they do nothing". A token that leaves the villager who earned it
## and lands on the counter it changed makes the whole economy legible without
## a single line of text.
##
## Drawn in ONE Control, projecting each token's 3D origin per frame, rather
## than spawning a Label per event. Fifty villagers finishing jobs produce a
## steady trickle of these, and a node each would be a node each.
##
## The token flies on an ARC, not a straight line. A straight lerp between two
## points on screen reads as a UI element sliding; a slight lift at the start
## reads as something being carried.

const LIFE := 1.15
const RISE := 34.0                 ## pixels of arc at the midpoint

var host = null                    ## ValeRoot, for the camera
var hud = null                     ## HUD, for where the counters are

var _font: Font
var _live: Array[Dictionary] = []


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## `icon` is a glyph name from Icons; `key` is the ledger row it flies to.
func spawn(icon: String, key: String, amount: int, at: Vector3) -> void:
	if amount == 0:
		return
	_live.append({"icon": icon, "key": key, "amount": amount,
				  "from": at, "t": 0.0})


## A token with no destination counter -- a satisfied need, say -- which simply
## rises and fades where it happened.
func puff(icon: String, text: String, at: Vector3) -> void:
	_live.append({"icon": icon, "key": "", "text": text,
				  "from": at, "t": 0.0})


func _process(delta: float) -> void:
	if _live.is_empty():
		return
	var kept: Array[Dictionary] = []
	for e in _live:
		e["t"] = float(e["t"]) + delta / LIFE
		if float(e["t"]) < 1.0:
			kept.append(e)
	_live = kept
	queue_redraw()


func _draw() -> void:
	if host == null or host.rig == null or host.rig.cam == null:
		return
	var cam = host.rig.cam
	for e in _live:
		var world: Vector3 = e["from"]
		if cam.is_position_behind(world):
			continue
		var start: Vector2 = cam.unproject_position(world)
		var t: float = float(e["t"])
		var key := String(e["key"])

		var pos := start
		var fade := 1.0
		if key == "":
			# Rise and fade in place.
			pos = start + Vector2(0.0, -46.0 * t)
			fade = 1.0 - t * t
		else:
			var target: Vector2 = hud.ledger_icon_pos(key)
			# Ease-in, so it lingers on the villager for a moment before
			# leaving -- the eye needs to see WHERE it came from.
			var e2: float = t * t
			pos = start.lerp(target, e2)
			pos.y -= sin(t * PI) * RISE
			fade = clampf(1.0 - (t - 0.75) / 0.25, 0.0, 1.0)

		var a := clampf(fade, 0.0, 1.0)
		Icons.draw_icon(self, String(e["icon"]), pos, 20.0 * (1.0 - t * 0.25))
		var label := String(e.get("text", ""))
		if label == "":
			label = "+%d" % int(e["amount"])
		draw_string(_font, pos + Vector2(13.0, 5.0), label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
					Color(1.0, 0.97, 0.86, a))


func live_count() -> int:
	return _live.size()
