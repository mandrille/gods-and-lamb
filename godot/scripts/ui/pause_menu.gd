extends Control
class_name PauseMenu

## Escape, and what it should have done all along.
##
## Escape opened the DEBUG PANEL. In a shipped web build that is a developer
## console one keypress away from anybody who presses the most obvious key on
## the keyboard, and there was no other way to pause, mute or start over --
## three things a portal player expects and one thing (mute) that portals ask
## for outright.
##
## Debug moves to F3. Escape now stops the village and offers the three.

signal resumed()
signal restarted()
signal muted_changed(on: bool)

const PANEL_W := 300.0
const DIM := Color(0.03, 0.04, 0.07, 0.72)
const PANEL := Color(0.13, 0.15, 0.21, 0.98)
const EDGE := Color(0.44, 0.54, 0.74, 0.85)
const HOT := Color(0.99, 0.84, 0.40, 1.0)
const INK := Color(0.95, 0.96, 0.98)
const SOFT := Color(0.70, 0.74, 0.82)
const BTN := Color(0.24, 0.26, 0.34)

var muted := false

var _font: Font
var _hot := -1
var _confirm := false              ## restart asks once, because it is final


func _ready() -> void:
	_font = ThemeDB.fallback_font
	# A pause menu that is itself paused cannot unpause anything.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fit()
	get_viewport().size_changed.connect(_fit)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	visible = true
	_confirm = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	get_tree().paused = true
	queue_redraw()


func close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().paused = false
	resumed.emit()
	queue_redraw()


func is_open() -> bool:
	return visible


func _labels() -> Array:
	return ["Resume",
			"Sound: off" if muted else "Sound: on",
			"Start over" if not _confirm else "Start over -- are you sure?"]


func _button_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var h := 44.0 * 3.0 + 16.0 * 2.0 + 96.0
	var p := Rect2((size.x - PANEL_W) * 0.5, (size.y - h) * 0.5, PANEL_W, h)
	for i in 3:
		out.append(Rect2(p.position.x + 24.0, p.position.y + 76.0
						 + float(i) * 60.0, PANEL_W - 48.0, 44.0))
	return out


func _panel_rect() -> Rect2:
	var h := 44.0 * 3.0 + 16.0 * 2.0 + 96.0
	return Rect2((size.x - PANEL_W) * 0.5, (size.y - h) * 0.5, PANEL_W, h)


func _process(_d: float) -> void:
	if not visible:
		return
	var m := get_local_mouse_position()
	_hot = -1
	var rects := _button_rects()
	for i in rects.size():
		if rects[i].has_point(m):
			_hot = i
			break
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var m: Vector2 = make_input_local(event).position
	var rects := _button_rects()
	for i in rects.size():
		if not rects[i].has_point(m):
			continue
		accept_event()
		match i:
			0:
				close()
			1:
				muted = not muted
				muted_changed.emit(muted)
				queue_redraw()
			2:
				# Twice, because there is no undo and the button sits directly
				# under the one people click to leave.
				if not _confirm:
					_confirm = true
					queue_redraw()
				else:
					restarted.emit()
		return


func _draw() -> void:
	if not visible:
		return
	draw_rect(Rect2(Vector2.ZERO, size), DIM, true)
	var p := _panel_rect()
	draw_rect(p, PANEL, true)
	draw_rect(p, EDGE, false, 1.5)
	draw_string(_font, p.position + Vector2(24.0, 44.0), "Paused",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 24, INK)
	var rects := _button_rects()
	var labels := _labels()
	for i in rects.size():
		var r := rects[i]
		draw_rect(r, BTN.lightened(0.12) if i == _hot else BTN, true)
		draw_rect(r, HOT if i == _hot else EDGE, false, 1.0)
		draw_string(_font, r.position + Vector2(0, 28.0), String(labels[i]),
					HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 15,
					INK if i != 2 or not _confirm else HOT)
	draw_string(_font, p.position + Vector2(0, p.size.y - 14.0),
				"Escape closes this. F3 is the debug panel.",
				HORIZONTAL_ALIGNMENT_CENTER, p.size.x, 11, SOFT)
