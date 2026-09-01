extends Control
class_name HUD

## The god's screen: the ledger, the miracle hand, and whatever just happened.
##
## Everything is DRAWN and hit-tested by hand rather than built from Buttons.
## The first version used Buttons with two lines of text in them, and it had
## three problems that all trace back to the same choice: a Button cannot draw
## a custom icon without a texture, Godot's default tooltip is a grey box that
## appears somewhere else on the screen, and the hand could not lift, dim or
## outline a card because those are the theme's business and not the game's.
## Four rects and a hit test buy all of it back.
##
## Card art is `Icons`, which draws each glyph from polygons -- no emoji (the
## default font has none) and no bitmaps (the entire game is 5% of the web
## download and a sprite sheet would be the first thing to change that).
##
## Buying land is NOT here. Plots are clicked in the world, on the water where
## the ground will appear -- see PlotMarkers.

const PAD := 16.0
const CARD_W := 96.0
const CARD_H := 116.0
const CARD_GAP := 10.0
const LIFT := 10.0                 ## how far a hovered card rises

const INK := Color(0.95, 0.96, 0.98)
const DIM := Color(0.68, 0.71, 0.77)
const GOLD := Color(0.99, 0.84, 0.40)
const PANEL := Color(0.10, 0.11, 0.15, 0.90)
const PANEL_EDGE := Color(1, 1, 1, 0.10)
const CARD_BG := Color(0.17, 0.20, 0.28, 0.96)
const CARD_BG_HOT := Color(0.24, 0.30, 0.42, 0.98)
const CARD_EDGE := Color(0.42, 0.52, 0.70, 0.85)
const WARN := Color(0.97, 0.66, 0.36)
const DANGER := Color(0.86, 0.34, 0.34)

var host = null
var divinity = null
var rig = null

var _font: Font
var _notice := ""
var _notice_left := 0.0
var _aiming := -1                  ## hand index awaiting a target, or -1
var _smiting := false
var _hot := -1                     ## hovered card, or -1
var _hot_wrath := false


func _ready() -> void:
	_font = ThemeDB.fallback_font
	# IGNORE, not STOP: the whole screen is covered by this Control and a
	# filter that accepts input would eat every drag meant for the camera.
	# Clicks are claimed only when they land on something.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	divinity.notice.connect(func(t):
		_notice = t
		_notice_left = 4.0)


## --- geometry ---------------------------------------------------------------
##
## One place that says where things are, used by both drawing and hit testing.
## Two copies of this arithmetic is how a button ends up looking clickable a
## few pixels away from where it actually is.

func _hand_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var n: int = divinity.hand.size()
	if n == 0:
		return out
	var vp := get_viewport_rect().size
	var total := float(n) * (CARD_W + CARD_GAP) - CARD_GAP
	var x := (vp.x - total) * 0.5
	var y := vp.y - CARD_H - PAD
	for i in n:
		out.append(Rect2(x + float(i) * (CARD_W + CARD_GAP), y, CARD_W, CARD_H))
	return out


func _wrath_rect() -> Rect2:
	var vp := get_viewport_rect().size
	return Rect2(vp.x - 132.0 - PAD, vp.y - CARD_H - PAD, 132.0, 40.0)


## --- input ------------------------------------------------------------------

func _process(delta: float) -> void:
	if _notice_left > 0.0:
		_notice_left -= delta
	var m := get_viewport().get_mouse_position()
	var was := _hot
	_hot = -1
	var rects := _hand_rects()
	for i in rects.size():
		# Hovered cards rise, so the hit box has to rise with them or the top
		# strip of a lifted card is decoration you cannot click.
		var r: Rect2 = rects[i]
		if i == was:
			r.position.y -= LIFT
			r.size.y += LIFT
		if r.has_point(m):
			_hot = i
			break
	_hot_wrath = _wrath_rect().has_point(m)
	# Show WHO can be targeted, for as long as a villager-only aim is live.
	var folk_aim := false
	if _aiming >= 0 and _aiming < divinity.hand.size():
		folk_aim = String(divinity.hand[_aiming]["target"]) == "folk"
	if host != null and host.overhead != null:
		host.overhead.highlight_all = folk_aim
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and (_aiming >= 0 or _smiting):
		_cancel("Cancelled.")
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return

	# A click on the hand or the wrath button, first: these sit on top.
	if _hot >= 0:
		_play_card(_hot)
		get_viewport().set_input_as_handled()
		return
	if _hot_wrath:
		_smiting = true
		_aiming = -1
		_say("Pick a place to destroy. Escape to cancel.", 6.0)
		get_viewport().set_input_as_handled()
		return

	# Otherwise, a click in the WORLD resolves whatever is being aimed.
	if _aiming < 0 and not _smiting:
		return

	if _smiting:
		var ground: Variant = rig.ground_at(mb.position)
		if ground == null:
			return
		divinity.smite(ground)
		_smiting = false
		get_viewport().set_input_as_handled()
		return

	var card: Dictionary = {}
	if _aiming < divinity.hand.size():
		card = divinity.hand[_aiming]
	if not card.is_empty() and String(card["target"]) == "folk":
		# VILLAGERS ONLY, and the aim STAYS ARMED on a miss rather than being
		# spent on empty grass. Losing a miracle to a slightly-off click is the
		# worst thing this screen could do.
		var who = host.overhead.under(mb.position)
		if who == null:
			_say("Aim at a villager.", 2.0)
			get_viewport().set_input_as_handled()
			return
		host.overhead.selected = who
		divinity.play(_aiming, who.position, who)
		_aiming = -1
		get_viewport().set_input_as_handled()
		return

	var hit: Variant = rig.ground_at(mb.position)
	if hit == null:
		return
	divinity.play(_aiming, hit, null)
	_aiming = -1
	get_viewport().set_input_as_handled()


func _play_card(index: int) -> void:
	if index < 0 or index >= divinity.hand.size():
		return
	var card: Dictionary = divinity.hand[index]
	var kind := String(card["target"])
	if kind == "none":
		divinity.play(index)
		return
	# A villager is already CHOSEN, so use it on them. Making the player pick
	# again, on someone they have open on screen with a ring at their feet, is
	# a second click that answers a question already answered.
	if kind == "folk":
		var chosen = host.overhead.selected
		if chosen != null and is_instance_valid(chosen):
			divinity.play(index, chosen.position, chosen)
			return
	_aiming = index
	_smiting = false
	_say("Pick a %s for %s. Escape to cancel." % [
		"villager" if kind == "folk" else "spot", String(card["name"])], 6.0)


func _cancel(msg: String) -> void:
	_aiming = -1
	_smiting = false
	_say(msg, 2.0)


func _say(text: String, secs: float) -> void:
	_notice = text
	_notice_left = secs


## --- paint ------------------------------------------------------------------

func _draw() -> void:
	if divinity == null or host == null:
		return
	_ledger()
	_hand()
	_wrath()
	_toast()
	_reticle()


## Where a ledger counter sits on screen, so a resource token can fly to it.
## Computed from the same row table `_ledger` draws from -- a second copy of
## the layout is how a token ends up landing next to the counter it means.
func ledger_icon_pos(key: String) -> Vector2:
	var x := PAD + 12.0
	for e in _ledger_rows():
		if String(e[0]) == key:
			return Vector2(x + 8.0, PAD + 17.0)
		x += _row_width(String(e[1]))
	return Vector2(PAD + 20.0, PAD + 17.0)


func _row_width(text: String) -> float:
	return 22.0 + float(_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
											  -1, 15).x) + 16.0


func _ledger_rows() -> Array:
	var v = host.village
	return [
		["faith", "%d" % int(divinity.faith), GOLD],
		["food", "%d/%d" % [v.amount("food"), v.capacity("food")], INK],
		["wood", "%d/%d" % [v.amount("wood"), v.capacity("wood")], INK],
		["stone", "%d/%d" % [v.amount("stone"), v.capacity("stone")], INK],
		["pop", "%d/%d" % [v.population, v.pop_cap], INK],
	]


## Resources as ICONS with numbers, in one row. The old version was three lines
## of "Food 8 / 24" and read as a debug printout.
func _ledger() -> void:
	var row := _ledger_rows()
	var h := 34.0
	var x := PAD + 12.0
	var widths: Array[float] = []
	for e in row:
		widths.append(_row_width(String(e[1])))
	var total := 0.0
	for w in widths:
		total += w
	_panel(Rect2(PAD, PAD, total + 20.0, h))
	var cy := PAD + h * 0.5
	for i in row.size():
		var e: Array = row[i]
		Icons.draw_icon(self, String(e[0]), Vector2(x + 8.0, cy), 19.0)
		draw_string(_font, Vector2(x + 22.0, cy + 5.0), String(e[1]),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15, e[2])
		x += widths[i]


func _hand() -> void:
	var rects := _hand_rects()
	for i in rects.size():
		var card: Dictionary = divinity.hand[i]
		var r: Rect2 = rects[i]
		var hot := i == _hot
		var armed := i == _aiming
		if hot or armed:
			r.position.y -= LIFT
		_card(r, card, hot, armed)
	if _hot >= 0:
		_tooltip(rects[_hot], divinity.hand[_hot])


func _card(r: Rect2, card: Dictionary, hot: bool, armed: bool) -> void:
	draw_rect(Rect2(r.position + Vector2(0, 4), r.size), Color(0, 0, 0, 0.30),
			  true)
	draw_rect(r, CARD_BG_HOT if (hot or armed) else CARD_BG, true)
	draw_rect(r, GOLD if armed else CARD_EDGE, false, 2.0 if armed else 1.0)

	Icons.draw_icon(self, String(card.get("icon", "")),
					r.position + Vector2(r.size.x * 0.5, 44.0), 46.0)
	var name := String(card["name"])
	var nw := float(_font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT,
										  -1, 15).x)
	draw_string(_font, r.position + Vector2((r.size.x - nw) * 0.5, 84.0), name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, INK)

	# What it needs, said on the card rather than only in the tooltip -- this
	# is what the player scans when deciding, and it is the difference between
	# "pick one" and "pick one and find out".
	var kind := String(card["target"])
	# Annotated: Dictionary.get() returns Variant, and `:=` on it is a parse
	# error in this project (inference-from-Variant is treated as an error).
	var note: String = {"none": "instant", "folk": "on a villager",
						"ground": "on a spot"}.get(kind, kind)
	var tw := float(_font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT,
										  -1, 11).x)
	draw_string(_font, r.position + Vector2((r.size.x - tw) * 0.5, 102.0), note,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)


## The explanation, above the card, on hover. Drawn rather than left to
## Godot's tooltip: that one appears near the cursor after a delay, in the
## theme's colours, and is the single most-ignored widget in any engine.
func _tooltip(anchor: Rect2, card: Dictionary) -> void:
	var lines: Array[String] = [String(card["desc"])]
	var title := String(card["name"])
	var w := maxf(float(_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT,
											  -1, 16).x),
				  float(_font.get_string_size(lines[0],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x)) + 28.0
	var h := 56.0
	var vp := get_viewport_rect().size
	var x := clampf(anchor.position.x + anchor.size.x * 0.5 - w * 0.5,
					PAD, vp.x - w - PAD)
	var y := anchor.position.y - LIFT - h - 10.0
	_panel(Rect2(x, y, w, h))
	draw_string(_font, Vector2(x + 14.0, y + 24.0), title,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GOLD)
	draw_string(_font, Vector2(x + 14.0, y + 44.0), lines[0],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)


func _wrath() -> void:
	var r := _wrath_rect()
	var afford: bool = divinity.can_afford(Divinity.SMITE_COST)
	var bg := Color(0.42, 0.18, 0.20, 0.95)
	if _smiting:
		bg = Color(0.66, 0.24, 0.26, 0.98)
	elif _hot_wrath and afford:
		bg = Color(0.54, 0.22, 0.24, 0.98)
	draw_rect(Rect2(r.position + Vector2(0, 3), r.size), Color(0, 0, 0, 0.30),
			  true)
	draw_rect(r, bg, true)
	draw_rect(r, DANGER if _smiting else Color(1, 1, 1, 0.14), false,
			  2.0 if _smiting else 1.0)
	Icons.draw_icon(self, "bolt", r.position + Vector2(24.0, r.size.y * 0.5),
					24.0)
	draw_string(_font, r.position + Vector2(42.0, r.size.y * 0.5 + 5.0),
				"Wrath  %d" % int(Divinity.SMITE_COST),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				INK if afford else Color(0.7, 0.55, 0.55))


func _toast() -> void:
	if _notice_left <= 0.0 or _notice == "":
		return
	var vp := get_viewport_rect().size
	var w := float(_font.get_string_size(_notice, HORIZONTAL_ALIGNMENT_LEFT,
										 -1, 15).x) + 34.0
	var r := Rect2((vp.x - w) * 0.5, PAD + 4.0, w, 32.0)
	# Fades out over its last second rather than vanishing, so the eye is not
	# caught by something disappearing.
	var a := clampf(_notice_left, 0.0, 1.0)
	draw_rect(r, Color(PANEL.r, PANEL.g, PANEL.b, PANEL.a * a), true)
	draw_rect(r, Color(1, 1, 1, 0.10 * a), false, 1.0)
	var tint := WARN if (_aiming >= 0 or _smiting) else INK
	draw_string(_font, r.position + Vector2(17.0, 21.0), _notice,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(tint.r, tint.g,
														 tint.b, a))


## An aiming reticle, so a mode the player is IN is visible on screen and not
## only in a line of text that has already faded.
func _reticle() -> void:
	if _aiming < 0 and not _smiting:
		return
	var m := get_viewport().get_mouse_position()
	var tint := DANGER if _smiting else GOLD
	var t := float(Time.get_ticks_msec()) * 0.004
	draw_arc(m, 26.0 + sin(t) * 2.0, 0.0, TAU, 40, tint, 2.0)
	draw_arc(m, 9.0, 0.0, TAU, 20, tint, 1.5)
	for k in 4:
		var a := TAU * float(k) / 4.0 + t * 0.4
		var d := Vector2(cos(a), sin(a))
		draw_line(m + d * 15.0, m + d * 21.0, tint, 2.0)


func _panel(r: Rect2) -> void:
	draw_rect(r, PANEL, true)
	draw_rect(r, PANEL_EDGE, false, 1.0)
