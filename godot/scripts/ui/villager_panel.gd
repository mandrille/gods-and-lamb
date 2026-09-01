extends Control
class_name VillagerPanel

## Everything about one villager, on click.
##
## Drawn rather than built out of nested containers. The panel is a stack of
## bars and short lines that all change every frame; a Container tree would be
## thirty-odd nodes re-laid-out continuously to produce a picture that
## `_draw` makes in one pass. The two Buttons ARE real nodes, because input is
## the one thing custom drawing cannot do well.
##
## The bars show SATISFACTION -- full and green is good. That matches how the
## brain stores them, deliberately, so there is no inversion anywhere between
## the simulation and the player's eye.

signal bless_pressed(who)
signal punish_pressed(who)
signal closed()

const W := 300.0
const PAD := 12.0
const ROW := 19.0
const BAR_H := 9.0

const GOOD := Color(0.36, 0.78, 0.42)
const MID := Color(0.93, 0.76, 0.26)
const BAD := Color(0.88, 0.34, 0.32)
const INK := Color(0.93, 0.94, 0.96)
const DIM := Color(0.66, 0.69, 0.74)
const BACK := Color(0.11, 0.12, 0.15, 0.94)
const TRACK := Color(1, 1, 1, 0.10)
const SAINT := Color(0.98, 0.86, 0.42)
const DEVIL := Color(0.85, 0.30, 0.36)

var who = null
var _font: Font
var _bless: Button
var _punish: Button
var _close: Button


func _ready() -> void:
	_font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(W, 420)
	size = custom_minimum_size
	# The panel itself swallows clicks -- clicking inside it must not also pan
	# the camera underneath -- but it starts hidden.
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bless = _button("Bless", Color(0.30, 0.62, 0.36))
	_punish = _button("Punish", Color(0.62, 0.28, 0.30))
	_close = _button("x", Color(0.28, 0.29, 0.34))
	_bless.pressed.connect(func(): bless_pressed.emit(who))
	_punish.pressed.connect(func(): punish_pressed.emit(who))
	_close.pressed.connect(func(): show_for(null); closed.emit())
	visible = false


func _button(text: String, tint: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = tint
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	b.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = tint.lightened(0.15)
	b.add_theme_stylebox_override("hover", hover)
	var press := sb.duplicate() as StyleBoxFlat
	press.bg_color = tint.darkened(0.2)
	b.add_theme_stylebox_override("pressed", press)
	add_child(b)
	return b


func show_for(f) -> void:
	who = f
	visible = f != null and is_instance_valid(f)
	_bless.visible = visible
	_punish.visible = visible
	_close.visible = visible
	queue_redraw()


func _process(_d: float) -> void:
	if not visible:
		return
	# The subject can die, be despawned by a stress-test clear, or be freed by
	# a rebuild while the panel is open. Checking every frame is cheaper than
	# every reader of `who` guarding for itself.
	if who == null or not is_instance_valid(who) or who.brain == null:
		show_for(null)
		return
	queue_redraw()


func _draw() -> void:
	if who == null or not is_instance_valid(who) or who.brain == null:
		return
	var b = who.brain
	var y := PAD

	draw_rect(Rect2(Vector2.ZERO, size), BACK, true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.10), false, 1.0)

	# Name and who they are.
	draw_string(_font, Vector2(PAD, y + 13), String(b.name),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK)
	y += 22
	draw_string(_font, Vector2(PAD, y + 10),
				"%s  -  %s" % [b.personality.describe(), b.morality_label()],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)
	y += 20

	# Devil <-> saint (item 4). A marker on a two-colour track, with the ends
	# labelled, because a bare bar does not say which direction is which.
	y = _morality(y, float(b.morality))

	# What they are doing right now, so the bars have context.
	var doing := "idle"
	if b.action != "":
		doing = String(Brain.ACTIONS[b.action].get("verb", b.action))
	elif b.chatting_with != "":
		doing = "talking to %s" % b.chatting_with
	draw_string(_font, Vector2(PAD, y + 10), "Currently: " + doing,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)
	y += 22

	# The bars (item 2).
	for k in Brain.STAT_ORDER:
		y = _stat_row(y, String(Brain.STAT_LABEL[k]), float(b.stats[k]))
	y += 6

	# Thoughts (item 3).
	draw_string(_font, Vector2(PAD, y + 10), "Thoughts",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
	y += 18
	var shown := 0
	for line in b.thought_log:
		if shown >= 4:
			break
		# Wrapped by hand at the panel width. A long thought that runs off the
		# edge is the difference between "this villager is a person" and "this
		# UI is broken".
		for chunk in _wrap(String(line), 44):
			draw_string(_font, Vector2(PAD + 6, y + 10), chunk,
						HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)
			y += 15
		shown += 1
		y += 3
	if shown == 0:
		draw_string(_font, Vector2(PAD + 6, y + 10), "(nothing yet)",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
		y += 16

	# Who they care about (item 16's visible half).
	var bonds: Array = b.memories.bonds()
	if not bonds.is_empty():
		y += 4
		draw_string(_font, Vector2(PAD, y + 10), "Feelings",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
		y += 18
		for i in mini(3, bonds.size()):
			var e: Dictionary = bonds[i]
			var score := float(e["score"])
			var word := "likes" if score > 0.08 else \
						("resents" if score < -0.08 else "knows")
			draw_string(_font, Vector2(PAD + 6, y + 10),
						"%s %s" % [word, String(e["who"])],
						HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
						GOOD if score > 0.08 else (BAD if score < -0.08 else DIM))
			y += 15

	# Buttons last, so the panel grows to fit whatever was above them.
	var bh := 26.0
	var bw := (W - PAD * 2 - 8.0) * 0.5
	_bless.position = Vector2(PAD, y + 10)
	_bless.size = Vector2(bw, bh)
	_punish.position = Vector2(PAD + bw + 8.0, y + 10)
	_punish.size = Vector2(bw, bh)
	_close.position = Vector2(W - PAD - 20.0, PAD - 4.0)
	_close.size = Vector2(20, 20)
	var wanted := y + 10 + bh + PAD
	if absf(size.y - wanted) > 1.0:
		size.y = wanted
		custom_minimum_size.y = wanted


func _stat_row(y: float, label: String, v: float) -> float:
	draw_string(_font, Vector2(PAD, y + 9), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)
	var x := PAD + 66.0
	var w := W - x - PAD - 34.0
	draw_rect(Rect2(x, y, w, BAR_H), TRACK, true)
	draw_rect(Rect2(x, y, w * clampf(v, 0.0, 1.0), BAR_H), _tint(v), true)
	draw_string(_font, Vector2(x + w + 6.0, y + 9), "%d%%" % int(round(v * 100.0)),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, DIM)
	return y + ROW


## Full is green, middling is yellow, low is red (item 2). Thresholds, not a
## gradient: a smooth ramp means every bar is a slightly different colour and
## none of them says anything at a glance.
func _tint(v: float) -> Color:
	if v >= 0.6:
		return GOOD
	if v >= 0.3:
		return MID
	return BAD


func _morality(y: float, m: float) -> float:
	var x := PAD + 22.0
	var w := W - PAD * 2 - 44.0
	draw_string(_font, Vector2(PAD, y + 10), "D", HORIZONTAL_ALIGNMENT_LEFT,
				-1, 13, DEVIL)
	draw_string(_font, Vector2(W - PAD - 14.0, y + 10), "S",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, SAINT)
	draw_rect(Rect2(x, y + 2.0, w, BAR_H), TRACK, true)
	# Two halves growing out from the centre, so the bar reads as an AXIS
	# rather than as a meter that happens to start in the middle.
	var mid := x + w * 0.5
	var half := w * 0.5 * clampf(absf(m), 0.0, 1.0)
	if m >= 0.0:
		draw_rect(Rect2(mid, y + 2.0, half, BAR_H), SAINT, true)
	else:
		draw_rect(Rect2(mid - half, y + 2.0, half, BAR_H), DEVIL, true)
	draw_line(Vector2(mid, y), Vector2(mid, y + BAR_H + 4.0),
			  Color(1, 1, 1, 0.5), 1.0)
	return y + 26.0


## Break a line into chunks of at most `n` characters, on spaces where it can.
func _wrap(text: String, n: int) -> Array[String]:
	var out: Array[String] = []
	var line := ""
	for word in text.split(" "):
		var w := String(word)
		if line == "":
			line = w
		elif line.length() + 1 + w.length() <= n:
			line += " " + w
		else:
			out.append(line)
			line = w
	if line != "":
		out.append(line)
	return out
