extends Control
class_name DayScreen

## The two ends of a day: the night you close it on, and the morning you come
## back to.
##
## ONE screen with two faces, because they are the same moment seen from either
## side -- what the village did while you were watching, and what it did while
## you were not. Splitting them into two classes would have duplicated the
## panel, the layout and the dismissal for the sake of a different heading.
##
## NIGHT is the payoff for the eight minutes: a count of what was raised, one
## line of the day's drama, and a single choice -- which aura to leave burning
## overnight. That choice is what makes closing the tab a decision rather than
## an abandonment, and it is the thing the away roll reads tomorrow.
##
## MORNING is the reason to have come back: the away log, the Faith it earned,
## and the streak.
##
## Drawn and hit-tested by hand, like boon_draft.gd and villager_panel.gd --
## the same reasons apply and are documented there.

signal aura_chosen(id: String)
signal rested()                    ## "that will do for today"
signal resumed()                   ## straight into the next day

## The panel is 460 units wide, and a phone lays its UI out in 400. Every rect
## in here was measured off that constant, so the whole nightfall screen -- the
## summary, the aura buttons, the two ways to continue -- ran off both edges on
## a handset. `_pw()` is the width that actually fits; PANEL_W is what it wants.
const PANEL_W := 460.0


func _pw() -> float:
	return minf(PANEL_W, size.x - 24.0)
const DIM := Color(0.03, 0.04, 0.07, 0.78)
const PANEL := Color(0.13, 0.15, 0.21, 0.98)
const EDGE := Color(0.44, 0.54, 0.74, 0.85)
const HOT := Color(0.99, 0.84, 0.40, 1.0)
const INK := Color(0.95, 0.96, 0.98)
const SOFT := Color(0.70, 0.74, 0.82)
const GOLD := Color(0.99, 0.84, 0.40)
const BTN := Color(0.24, 0.40, 0.32)
const BTN2 := Color(0.24, 0.26, 0.34)

## Four auras, four different tomorrows. Deliberately not "more of everything":
## a choice where one option is strictly best is not a choice, so each one
## trades the others away.
const AURAS := [
	{"id": "fertility", "name": "Fertility", "icon": "sprout",
	 "desc": "Strangers arrive"},
	{"id": "vigil", "name": "Vigil", "icon": "bow",
	 "desc": "Wolves stay off"},
	{"id": "harvest", "name": "Harvest", "icon": "wheat",
	 "desc": "Fields give more"},
	{"id": "toil", "name": "Toil", "icon": "hammer",
	 "desc": "Work goes on"},
]

var _font: Font
var _mode := ""                    ## "" | "night" | "morning"
var _doc: Dictionary = {}
var _aura := "fertility"
var _hot := -1                     ## aura index under the pointer
var _hot_btn := -1                 ## 0 rest / 1 keep watch


func _ready() -> void:
	_font = ThemeDB.fallback_font
	# Runs while the tree is paused: night STOPS the village, and a screen that
	# pauses the game and then cannot be dismissed is a hang.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fit()
	get_viewport().size_changed.connect(_fit)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## The same trap boon_draft.gd documents: PRESET_FULL_RECT resolves against a
## parent Control and this one's parent is a CanvasLayer, which does no layout,
## so the rect stays (0, 0) and every click misses a screen that looks fine.
func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


func open_night(doc: Dictionary) -> void:
	_doc = doc
	_mode = "night"
	_aura = String(doc.get("aura", _aura))
	_show()


func open_morning(doc: Dictionary) -> void:
	_doc = doc
	_mode = "morning"
	_show()


func _show() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_hot = -1
	_hot_btn = -1
	queue_redraw()


func close() -> void:
	_mode = ""
	_doc = {}
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func is_open() -> bool:
	return visible and _mode != ""


## --- geometry, one source for drawing and hit testing -----------------------

func _panel_rect() -> Rect2:
	# Sized to its contents. A fixed height left a hand's width of empty panel
	# under the drama line on a quiet day, which reads as a screen that failed
	# to load something.
	var h := 366.0
	if _mode != "night":
		var lines: int = (_doc.get("lines", []) as Array).size()
		h = 176.0 + float(lines) * 20.0
		if int(_doc.get("streak", 0)) >= 2:
			h += 22.0
	var w := _pw()
	return Rect2((size.x - w) * 0.5, (size.y - h) * 0.5, w, h)


func _aura_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if _mode != "night":
		return out
	var p := _panel_rect()
	var w := (_pw() - 24.0 * 2.0 - 3.0 * 8.0) / 4.0
	var y := p.position.y + p.size.y - 132.0
	for i in AURAS.size():
		out.append(Rect2(p.position.x + 24.0 + float(i) * (w + 8.0), y, w, 74.0))
	return out


func _button_rects() -> Array[Rect2]:
	var p := _panel_rect()
	var y := p.position.y + p.size.y - 46.0
	if _mode != "night":
		return [Rect2(p.position.x + 24.0, y, _pw() - 48.0, 34.0)]
	var w := (_pw() - 48.0 - 10.0) * 0.5
	return [Rect2(p.position.x + 24.0, y, w, 34.0),
			Rect2(p.position.x + 34.0 + w, y, w, 34.0)]


## --- input ------------------------------------------------------------------

func _process(_d: float) -> void:
	if not is_open():
		return
	var m := get_local_mouse_position()
	_hot = -1
	var rects := _aura_rects()
	for i in rects.size():
		if rects[i].has_point(m):
			_hot = i
			break
	_hot_btn = -1
	var btns := _button_rects()
	for i in btns.size():
		if btns[i].has_point(m):
			_hot_btn = i
			break
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not is_open():
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var m: Vector2 = make_input_local(event).position
	for i in _aura_rects().size():
		if _aura_rects()[i].has_point(m):
			_aura = String(AURAS[i]["id"])
			aura_chosen.emit(_aura)
			accept_event()
			queue_redraw()
			return
	var btns := _button_rects()
	for i in btns.size():
		if not btns[i].has_point(m):
			continue
		accept_event()
		if _mode == "night" and i == 1:
			resumed.emit()
		else:
			rested.emit()
		return


## --- paint ------------------------------------------------------------------

func _draw() -> void:
	if not is_open():
		return
	draw_rect(Rect2(Vector2.ZERO, size), DIM, true)
	var p := _panel_rect()
	draw_rect(p, PANEL, true)
	draw_rect(p, EDGE, false, 1.5)
	if _mode == "night":
		_draw_night(p)
	else:
		_draw_morning(p)
	_draw_buttons()


func _draw_night(p: Rect2) -> void:
	var x := p.position.x + 24.0
	var y := p.position.y + 40.0
	draw_string(_font, Vector2(x, y), "Night falls on day %d"
		% int(_doc.get("day", 1)), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, INK)
	y += 26.0
	draw_string(_font, Vector2(x, y), "They are asleep. Set your aura before you go.",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, SOFT)
	y += 26.0

	# What the day amounted to, in four numbers with their own icons.
	var stats := [
		["build", "%d raised" % int(_doc.get("built", 0))],
		["pop", "%d arrived" % int(_doc.get("newcomers", 0))],
		["faith", "%d Faith earned" % int(_doc.get("faith", 0.0))],
		["wood", "%d gathered" % int(_doc.get("gathered", 0))],
	]
	for i in stats.size():
		var col: float = x + float(i % 2) * (_pw() * 0.5 - 18.0)
		var row: float = y + float(i / 2) * 28.0
		Icons.draw_icon(self, String(stats[i][0]), Vector2(col + 9.0, row + 6.0), 17.0)
		draw_string(_font, Vector2(col + 24.0, row + 11.0), String(stats[i][1]),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK)
	y += 66.0

	# ONE line of the day's drama. A summary that only counts things reads as a
	# receipt; the village is worth remembering for what went wrong in it.
	var drama := String(_doc.get("drama", ""))
	if drama != "":
		draw_string(_font, Vector2(x, y + 4.0), drama,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GOLD)
	y += 24.0
	draw_string(_font, Vector2(x, y + 6.0), "Leave one blessing on the village:",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, SOFT)

	var rects := _aura_rects()
	for i in rects.size():
		var r := rects[i]
		var picked: bool = String(AURAS[i]["id"]) == _aura
		draw_rect(r, Color(0.18, 0.21, 0.29, 1.0) if not picked
				  else Color(0.24, 0.30, 0.24, 1.0), true)
		draw_rect(r, HOT if (picked or i == _hot) else EDGE, false,
				  2.0 if picked else 1.0)
		Icons.draw_icon(self, String(AURAS[i]["icon"]),
						r.position + Vector2(r.size.x * 0.5, 20.0), 20.0)
		draw_string(_font, r.position + Vector2(6.0, 46.0),
					String(AURAS[i]["name"]), HORIZONTAL_ALIGNMENT_CENTER,
					r.size.x - 12.0, 13, INK if picked else SOFT)
		draw_string(_font, r.position + Vector2(4.0, 62.0),
					String(AURAS[i]["desc"]), HORIZONTAL_ALIGNMENT_CENTER,
					r.size.x - 8.0, 9, SOFT)


func _draw_morning(p: Rect2) -> void:
	var x := p.position.x + 24.0
	var y := p.position.y + 40.0
	draw_string(_font, Vector2(x, y), "While you were away",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 24, INK)
	y += 24.0
	draw_string(_font, Vector2(x, y), String(_doc.get("span", "")),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, SOFT)
	y += 24.0
	for line in (_doc.get("lines", []) as Array):
		draw_string(_font, Vector2(x + 10.0, y + 12.0), "- " + String(line),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)
		y += 20.0
	y += 6.0
	Icons.draw_icon(self, "faith", Vector2(x + 9.0, y + 6.0), 18.0)
	draw_string(_font, Vector2(x + 26.0, y + 12.0),
				"%d Faith gathered in your absence" % int(_doc.get("faith", 0.0)),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GOLD)
	var streak := int(_doc.get("streak", 0))
	if streak >= 2:
		y += 22.0
		draw_string(_font, Vector2(x + 26.0, y + 12.0),
					"Day %d in a row. %s" % [streak, String(_doc.get("gift", ""))],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GOLD)


func _draw_buttons() -> void:
	var labels := (["Rest until tomorrow", "Keep watch"] if _mode == "night"
				   else ["Begin day %d" % int(_doc.get("day", 1))])
	var rects := _button_rects()
	for i in rects.size():
		var r := rects[i]
		var base := BTN if i == 0 else BTN2
		draw_rect(r, base.lightened(0.12) if i == _hot_btn else base, true)
		draw_rect(r, HOT if i == _hot_btn else EDGE, false, 1.0)
		draw_string(_font, r.position + Vector2(0, 23.0), String(labels[i]),
					HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 15, INK)
