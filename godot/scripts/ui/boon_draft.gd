extends Control
class_name BoonDraft

## Three boons. Take one.
##
## The moment the whole progression hangs on, so it stops the world: the
## overlay dims everything behind it and swallows input while it is open. A
## choice you can make by accident while the camera is panning is not a choice
## the player will remember making.
##
## Drawn and hit-tested by hand, like every other panel here -- hud.gd and
## villager_panel.gd both document why this project does not use Containers and
## Buttons for drawn UI.
##
## Every card carries a SENTENCE for the rank being offered, not for the boon
## in general. "Zeal II" means nothing; "Faith from followers +55%" is a
## decision.

signal chosen(id: String)
signal rerolled()

const CARD_W := 232.0
const CARD_H := 300.0
const GAP := 22.0

const DIM := Color(0.04, 0.05, 0.08, 0.72)
const CARD_BG := Color(0.15, 0.17, 0.24, 0.98)
const CARD_HOT := Color(0.22, 0.27, 0.38, 1.0)
const EDGE := Color(0.44, 0.54, 0.74, 0.9)
const EDGE_HOT := Color(0.99, 0.84, 0.40, 1.0)
const INK := Color(0.95, 0.96, 0.98)
const SOFT := Color(0.70, 0.74, 0.82)
const GOLD := Color(0.99, 0.84, 0.40)

var divinity = null

var _font: Font
var _options: Array = []
var _source := ""
var _hot := -1
var _hot_reroll := false


func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func open(options: Array, source: String) -> void:
	_options = options
	_source = source
	visible = not options.is_empty()
	# STOP while open: the draft owns every click until it is resolved.
	mouse_filter = Control.MOUSE_FILTER_STOP if visible \
		else Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func close() -> void:
	_options = []
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func is_open() -> bool:
	return visible and not _options.is_empty()


## --- geometry, one source for drawing and hit testing -----------------------

func _card_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var n := _options.size()
	if n == 0:
		return out
	var vp := get_viewport_rect().size
	var total := float(n) * (CARD_W + GAP) - GAP
	var x := (vp.x - total) * 0.5
	var y := (vp.y - CARD_H) * 0.5
	for i in n:
		out.append(Rect2(x + float(i) * (CARD_W + GAP), y, CARD_W, CARD_H))
	return out


func _reroll_rect() -> Rect2:
	var vp := get_viewport_rect().size
	return Rect2(vp.x * 0.5 - 90.0, (vp.y + CARD_H) * 0.5 + 22.0, 180.0, 36.0)


func reroll_cost() -> int:
	return maxi(8, int(divinity.commune_cost() * 0.25))


## --- input ------------------------------------------------------------------

func _process(_d: float) -> void:
	if not is_open():
		return
	var m := get_viewport().get_mouse_position()
	var was := _hot
	_hot = -1
	var rects := _card_rects()
	for i in rects.size():
		if rects[i].has_point(m):
			_hot = i
			break
	_hot_reroll = _reroll_rect().has_point(m)
	if _hot != was or true:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not is_open() or not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if _hot >= 0:
		chosen.emit(String(_options[_hot]["id"]))
		accept_event()
		return
	if _hot_reroll and divinity.can_afford(float(reroll_cost())):
		rerolled.emit()
		accept_event()


## --- paint ------------------------------------------------------------------

func _draw() -> void:
	if not is_open():
		return
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), DIM, true)

	var title := "Commune" if _source == "commune" else "A gift"
	# Annotated: Dictionary.get returns Variant, and this project treats
	# inference-from-Variant as an error rather than a warning.
	var sub: String = {
		"commune": "Choose one. It is yours for the rest of this run.",
		"age": "A new age dawns. Choose one.",
		"milestone": "Your village has grown. Choose one.",
		"tutorial": "Your first power. Choose one."}.get(_source, "Choose one.")
	var tw := float(_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT,
										  -1, 30).x)
	var sw := float(_font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT,
										  -1, 15).x)
	var top := (vp.y - CARD_H) * 0.5
	draw_string(_font, Vector2((vp.x - tw) * 0.5, top - 56.0), title,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 30, GOLD)
	draw_string(_font, Vector2((vp.x - sw) * 0.5, top - 30.0), sub,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, SOFT)

	var rects := _card_rects()
	for i in rects.size():
		_card(rects[i], _options[i], i == _hot)

	# Reroll, so a bad hand is not a dead moment.
	var rr := _reroll_rect()
	var cost := reroll_cost()
	var can: bool = divinity.can_afford(float(cost))
	draw_rect(rr, CARD_HOT if (_hot_reroll and can) else CARD_BG, true)
	draw_rect(rr, EDGE if can else Color(1, 1, 1, 0.10), false, 1.0)
	var label := "Reroll  %d" % cost
	var lw := float(_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT,
										  -1, 15).x)
	draw_string(_font, rr.position + Vector2((rr.size.x - lw) * 0.5, 24.0),
				label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
				INK if can else Color(0.55, 0.56, 0.60))


func _card(r: Rect2, opt: Dictionary, hot: bool) -> void:
	if hot:
		r.position.y -= 8.0
	draw_rect(Rect2(r.position + Vector2(0, 6), r.size), Color(0, 0, 0, 0.35),
			  true)
	draw_rect(r, CARD_HOT if hot else CARD_BG, true)
	draw_rect(r, EDGE_HOT if hot else EDGE, false, 2.0 if hot else 1.0)

	Icons.draw_icon(self, String(opt["icon"]),
					r.position + Vector2(r.size.x * 0.5, 78.0), 78.0)

	var name := String(opt["name"])
	var nw := float(_font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT,
										  -1, 22).x)
	draw_string(_font, r.position + Vector2((r.size.x - nw) * 0.5, 150.0), name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK)

	var numeral: String = ["I", "II", "III"][int(opt["rank"]) - 1]
	var rw := float(_font.get_string_size(numeral, HORIZONTAL_ALIGNMENT_LEFT,
										 -1, 16).x)
	draw_string(_font, r.position + Vector2((r.size.x - rw) * 0.5, 172.0),
				numeral, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GOLD)

	# The flavour, then the number. Both, because one without the other is
	# either a poem or a spreadsheet.
	var y := 204.0
	for line in _wrap(String(opt["what"]), 30):
		draw_string(_font, r.position + Vector2(16.0, y), line,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13, SOFT)
		y += 17.0
	y += 8.0
	for line in _wrap(String(opt["blurb"]), 28):
		draw_string(_font, r.position + Vector2(16.0, y), line,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GOLD)
		y += 17.0


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
