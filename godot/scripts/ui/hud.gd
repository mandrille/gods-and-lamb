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
## Up to three lines, newest at the top, each with its own life.
##
## This was ONE slot that every emitter overwrote, and roughly forty places
## emit into it -- a birth, an age, a sin and a wolf landing in the same second
## left the player with whichever fired last. A village that is doing things
## the player cannot see is a village that is not doing them.
const NOTICE_MAX := 3
const NOTICE_LIFE := 4.0
var _notices: Array = []                ## [{text, left, warn}], newest first
var _combo_chain := 0
var _combo_mult := 1.0
var _combo_flash := 0.0            ## counts down after a chain BREAKS
var _aiming := -1                  ## hand index awaiting a target, or -1
var _smiting := false
var _hot := -1                     ## hovered card, or -1
var _hot_hand_reroll := false      ## hovering the hovered card's reroll button

## TEST HOOK ONLY. The probe window runs parked off-screen and unfocused (see
## tools/shot_window.gd), so the real mouse position it reports is meaningless
## garbage -- and _process() re-derives _hot from that garbage every single
## frame, which clobbers a one-shot manual call to _refresh_hot() on the very
## next tick. Setting this makes _process() hover a fixed point every frame
## instead, the same seam MiracleCursor._pointer_override uses for the same
## reason. Left at (-1, -1) it is a no-op.
var _hover_override := Vector2(-1, -1)
var _hot_wrath := false
var _hot_commune := false


func _ready() -> void:
	_font = ThemeDB.fallback_font
	# IGNORE, not STOP: the whole screen is covered by this Control and a
	# filter that accepts input would eat every drag meant for the camera.
	# Clicks are claimed only when they land on something.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	divinity.notice.connect(func(t): _say(t, NOTICE_LIFE))
	divinity.combo_changed.connect(func(chain: int, mult: float):
		# A BREAK is the event worth drawing. The old wiring only reacted at
		# chain >= 2, so losing a chain of five produced nothing at all.
		if chain == 0 and _combo_chain >= 2:
			_combo_flash = 0.6
		_combo_chain = chain
		_combo_mult = mult)


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


func _commune_rect() -> Rect2:
	var r := _wrath_rect()
	return Rect2(r.position.x, r.position.y - 46.0, r.size.x, 40.0)


## --- input ------------------------------------------------------------------

func _process(delta: float) -> void:
	if _combo_flash > 0.0:
		_combo_flash -= delta
	for n in _notices:
		n["left"] = float(n["left"]) - delta
	while not _notices.is_empty() and float(_notices[-1]["left"]) <= 0.0:
		_notices.pop_back()
	var m := (_hover_override if _hover_override.x >= 0.0
			  else get_local_mouse_position())
	_refresh_hot(m)
	# Show WHO can be targeted, for as long as a villager-only aim is live.
	var folk_aim := false
	if _aiming >= 0 and _aiming < divinity.hand.size():
		folk_aim = String(divinity.hand[_aiming]["target"]) == "folk"
	if host != null and host.overhead != null:
		host.overhead.highlight_all = folk_aim
	queue_redraw()


## COORDINATE SPACES.
##
## project.godot stretches with `canvas_items` from a 720x1280 base into
## whatever the window is, so there are TWO mouse positions and they are not
## the same number:
##
##   get_viewport().get_mouse_position()  raw viewport pixels
##   get_local_mouse_position()           canvas space, where Controls live
##
## Everything drawn or laid out here -- get_viewport_rect(), and every
## Camera3D.unproject_position -- is in canvas space, so the raw one is always
## wrong and wrong by a factor that changes with the window size. Symptoms
## were a boon card that could not be clicked, an aiming reticle beside the
## cursor rather than on it, and villagers that were "super hard to click".
##
## An InputEvent carries raw viewport coordinates too, so it goes through
## make_input_local() before being compared with anything.
func _refresh_hot(m: Vector2) -> void:
	_hot_hand_reroll = false
	var was := _hot
	var rects := _hand_rects()
	# STICKY. The reroll button lives in the tooltip, which sits ABOVE the
	# card rather than inside it, so a straight point-in-rect test loses the
	# hover -- and the tooltip along with it -- the instant the mouse leaves
	# the card on its way up to the button it is trying to reach. Holding the
	# previous card hot while the pointer is anywhere over its card OR its
	# tooltip is what makes the button reachable at all.
	if was >= 0 and was < rects.size():
		var r: Rect2 = rects[was]
		r.position.y -= LIFT
		r.size.y += LIFT
		var geo := _tooltip_geo(rects[was], divinity.hand[was])
		if r.has_point(m) or (geo["panel"] as Rect2).has_point(m):
			_hot = was
			_hot_hand_reroll = (geo["reroll"] as Rect2).has_point(m)
			_hot_wrath = _wrath_rect().has_point(m)
			_hot_commune = _commune_rect().has_point(m)
			return
	_hot = -1
	for i in rects.size():
		if rects[i].has_point(m):
			_hot = i
			break
	_hot_wrath = _wrath_rect().has_point(m)
	_hot_commune = _commune_rect().has_point(m)


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
	# Recompute the hover from THIS event rather than trusting _process: a
	# click that arrives in the same frame the pointer moved would otherwise be
	# tested against where the mouse used to be.
	_refresh_hot(make_input_local(mb).position)

	# A click on the hand or the wrath button, first: these sit on top.
	#
	# The reroll button is checked BEFORE playing the card -- it sits in the
	# tooltip above the card, so a click that lands on it is never also a
	# click on the card body, but it shares the sticky `_hot` index and has to
	# be asked about first or it would be swallowed as "play card _hot".
	if _hot_hand_reroll and _hot >= 0:
		if divinity.reroll_card(_hot) and host != null and host.sfx != null:
			host.sfx.play("chat", 1.2)
		get_viewport().set_input_as_handled()
		return
	if _hot >= 0:
		_play_card(_hot)
		get_viewport().set_input_as_handled()
		return
	if _hot_commune:
		divinity.commune()
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
	var cid := String(card["id"])
	# A HELD miracle needs no aiming step at all: it appears on the cursor and
	# the player walks it over whatever they want it to touch. Asking them to
	# click a spot first would be choosing the target twice.
	if MiracleCursor.handles(cid):
		if divinity.play(index):
			_aiming = -1
			_smiting = false
			_say("Sweep it over your people. It fades in %d seconds."
				% int(MiracleCursor.SECONDS), 4.0)
		return
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
	# A repeat refreshes the line it is already on rather than stacking three
	# copies of "Not enough Faith to strike."
	for n in _notices:
		if String(n["text"]) == text:
			n["left"] = secs
			return
	_notices.push_front({"text": text, "left": secs,
						 "warn": _aiming >= 0 or _smiting})
	while _notices.size() > NOTICE_MAX:
		_notices.pop_back()


## --- paint ------------------------------------------------------------------

func _draw() -> void:
	if divinity == null or host == null:
		return
	_ledger()
	_daybar()
	_goal()
	_combo()
	_hand()
	_commune()
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


## Where the village has got to. Roman numerals because "Age 2" reads as a
## debug counter and "Age II" reads as an achievement.
func _age_label() -> String:
	var n: int = divinity.age
	if n <= 0:
		return "-"
	return ["I", "II", "III"][mini(n, 3) - 1]


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
		["saint", _age_label(), GOLD],
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
## ONE SOURCE for the tooltip's geometry, read by both the draw call below
## and the hit test in _refresh_hot / _unhandled_input. Two copies of this
## arithmetic drifting apart is how a button ends up two pixels from where it
## is drawn -- see _card_rects() in boon_draft.gd for the same rule.
func _tooltip_geo(anchor: Rect2, card: Dictionary) -> Dictionary:
	var desc := String(card["desc"])
	var title := String(card["name"])
	var w := maxf(float(_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT,
											  -1, 16).x),
				  float(_font.get_string_size(desc, HORIZONTAL_ALIGNMENT_LEFT,
					-1, 13).x)) + 28.0
	w = maxf(w, 150.0)
	var h := 84.0
	var vp := get_viewport_rect().size
	var x := clampf(anchor.position.x + anchor.size.x * 0.5 - w * 0.5,
					PAD, vp.x - w - PAD)
	var y := anchor.position.y - LIFT - h - 10.0
	var panel := Rect2(x, y, w, h)
	var reroll := Rect2(x + 10.0, y + h - 30.0, w - 20.0, 22.0)
	return {"panel": panel, "reroll": reroll}


## Explains what the card does, on hover, and offers a way OUT of a card you
## drew and do not want -- drawn rather than left to Godot's tooltip, which
## appears near the cursor after a delay, in the theme's colours, and is the
## single most-ignored widget in any engine.
func _tooltip(anchor: Rect2, card: Dictionary) -> void:
	var geo := _tooltip_geo(anchor, card)
	var panel: Rect2 = geo["panel"]
	var title := String(card["name"])
	_panel(panel)
	draw_string(_font, panel.position + Vector2(14.0, 24.0), title,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GOLD)
	draw_string(_font, panel.position + Vector2(14.0, 44.0), String(card["desc"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)

	# The reroll button. A card you do not want should never be a dead slot --
	# this is the same relief valve the boon draft offers on a bad hand, just
	# per-card instead of per-draft, because a hand is now locked to three and
	# a bad third of it is otherwise stuck for the rest of the run.
	var r: Rect2 = geo["reroll"]
	var cost := int(Divinity.HAND_REROLL_COST)
	var can: bool = divinity.can_afford(float(cost))
	draw_rect(r, CARD_BG_HOT if (_hot_hand_reroll and can) else CARD_BG, true)
	draw_rect(r, GOLD if (can and _hot_hand_reroll) else
			  (CARD_EDGE if can else Color(1, 1, 1, 0.10)), false, 1.0)
	var label := "Reroll  %d" % cost
	var lw := float(_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT,
										  -1, 12).x)
	draw_string(_font, r.position + Vector2((r.size.x - lw) * 0.5, 15.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				INK if can else Color(0.55, 0.56, 0.60))


## The altar. The most important button on the screen, so it sits above Wrath
## and is gold rather than red.
func _commune() -> void:
	var r := _commune_rect()
	var cost: float = divinity.commune_cost()
	var can: bool = divinity.can_afford(cost)
	var bg := Color(0.26, 0.24, 0.14, 0.95)
	if _hot_commune and can:
		bg = Color(0.40, 0.35, 0.16, 0.98)
	draw_rect(Rect2(r.position + Vector2(0, 3), r.size), Color(0, 0, 0, 0.30),
			  true)
	draw_rect(r, bg, true)
	draw_rect(r, GOLD if can else Color(1, 1, 1, 0.12), false,
			  2.0 if can else 1.0)
	Icons.draw_icon(self, "faith", r.position + Vector2(24.0, r.size.y * 0.5),
					24.0)
	draw_string(_font, r.position + Vector2(42.0, r.size.y * 0.5 + 5.0),
				"Commune  %d" % int(cost), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				INK if can else Color(0.62, 0.58, 0.48))


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
	if _notices.is_empty():
		return
	var vp := get_viewport_rect().size
	# Below the day bar, which now owns the top centre.
	var y := PAD + 52.0
	for n in _notices:
		var text := String(n["text"])
		var w := float(_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
											 -1, 15).x) + 34.0
		var r := Rect2((vp.x - w) * 0.5, y, w, 32.0)
		# Fades out over its last second rather than vanishing, so the eye is
		# not caught by something disappearing.
		var a := clampf(float(n["left"]), 0.0, 1.0)
		draw_rect(r, Color(PANEL.r, PANEL.g, PANEL.b, PANEL.a * a), true)
		draw_rect(r, Color(1, 1, 1, 0.10 * a), false, 1.0)
		var tint := WARN if bool(n["warn"]) else INK
		draw_string(_font, r.position + Vector2(17.0, 21.0), text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
					Color(tint.r, tint.g, tint.b, a))
		y += 36.0


## THE DAY, at the top centre, with the sun going down beside it.
##
## The single most important thing on this screen for a player who has never
## seen the game before: it says there is an END, how far off it is, and -- by
## being a countdown rather than a percentage -- that it is worth staying for.
## Eight minutes of anything is a long time to give a stranger without telling
## them what they are waiting for.
func _daybar() -> void:
	if host == null or host.get("daylight") == null:
		return
	var d = host.daylight
	var vp := get_viewport_rect().size
	var w := 268.0
	var r := Rect2((vp.x - w) * 0.5, PAD - 2.0, w, 52.0)
	var dusk: float = d.dusk_amount()

	draw_rect(r, PANEL, true)
	draw_rect(r, PANEL_EDGE, false, 1.0)
	# A warm rim once dusk starts, so the panel itself changes state and not
	# just the text inside it.
	if dusk > 0.0:
		draw_rect(r.grow(1.0), Color(WARN.r, WARN.g, WARN.b, 0.55 * dusk),
				  false, 2.0)

	# The sky, in a box: a bar that fills as the day runs out, warming toward
	# dusk so the colour says the same thing the number does.
	var track := Rect2(r.position + Vector2(58.0, 35.0), Vector2(w - 74.0, 6.0))
	draw_rect(track, Color(1, 1, 1, 0.12), true)
	var lit := track
	lit.size.x = track.size.x * d.fraction()
	draw_rect(lit, GOLD.lerp(Color(0.62, 0.66, 0.92), dusk), true)

	# Day number and the clock, the clock in amber once dusk starts.
	draw_string(_font, r.position + Vector2(58.0, 25.0), "Day %d" % d.day,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK)
	var left: String = d.clock()
	var tint := INK if dusk <= 0.0 else WARN
	# A slow pulse over the last minute. The countdown is the one element on
	# this screen that should get LOUDER as it matters more, and a player who
	# has stopped reading the panel will still catch something breathing.
	if d.seconds_left() <= 60.0:
		var beat: float = 0.72 + 0.28 * sin(float(Time.get_ticks_msec()) * 0.006)
		tint = Color(WARN.r, WARN.g, WARN.b, beat)
	var tw := float(_font.get_string_size(left, HORIZONTAL_ALIGNMENT_LEFT,
										  -1, 24).x)
	draw_string(_font, r.position + Vector2(w - 16.0 - tw, 28.0), left,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 24, tint)
	if dusk > 0.0:
		draw_string(_font, r.position + Vector2(w - 16.0 - tw - 62.0, 27.0),
					"nightfall", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
					Color(WARN.r, WARN.g, WARN.b, 0.55 + 0.45 * dusk))
	_sky_token(r.position + Vector2(30.0, 26.0), d.fraction(), dusk)


## A sun that becomes a moon.
##
## Both are drawn every frame and cross-faded, rather than swapped at a
## threshold: a hard swap reads as a bug the first time a player catches it
## mid-blink, and the whole point of the icon is to show a CHANGE happening.
## The sun also rides an arc across the token, so it is descending rather than
## merely dimming.
func _sky_token(at: Vector2, frac: float, dusk: float) -> void:
	var sun_a: float = 1.0 - dusk
	var moon_a: float = dusk
	# Along a shallow arc: left at dawn, right at dusk, highest at noon.
	var x: float = (frac - 0.5) * 26.0
	var y: float = -7.0 * sin(PI * frac) + 3.5
	var c := at + Vector2(x, y)

	if sun_a > 0.01:
		var warm := Color(1.0, 0.86, 0.36).lerp(Color(1.0, 0.55, 0.28), dusk)
		for i in 8:
			var a := TAU * float(i) / 8.0
			var dir := Vector2(cos(a), sin(a))
			draw_line(c + dir * 9.5, c + dir * 13.5,
					  Color(warm.r, warm.g, warm.b, 0.75 * sun_a), 2.0, true)
		draw_circle(c, 7.5, Color(warm.r, warm.g, warm.b, sun_a))
	if moon_a > 0.01:
		# The same crescent the rest glyph uses, so the two read as one idea:
		# night, and rest.
		var pale := Color(0.93, 0.95, 1.00, moon_a)
		var mr := 10.0
		# A FAT crescent. The bite circle sits further out and is barely wider
		# than the moon, which leaves a thick sickle rather than the fingernail
		# a 0.55/1.15 pair produces -- at this size a thin one reads as a smudge.
		var bd := mr * 0.78
		var br := mr * 1.02
		var hx := (bd * bd - br * br + mr * mr) / (2.0 * bd)
		var hy := sqrt(maxf(mr * mr - hx * hx, 0.0))
		var a1 := atan2(hy, hx)
		var b1 := atan2(hy, hx - bd)
		var pts: Array = []
		for i in 15:
			var a := lerpf(a1, TAU - a1, float(i) / 14.0)
			pts.append(c + Vector2(cos(a), sin(a)) * mr)
		for i in range(1, 14):
			var b := lerpf(TAU - b1, b1, float(i) / 14.0)
			pts.append(c + Vector2(bd + cos(b) * br, sin(b) * br))
		draw_colored_polygon(PackedVector2Array(pts), pale)


## What to aim at, one line under the ledger.## What to aim at, one line under the ledger.
func _goal() -> void:
	if host == null or not host.has_method("next_goal"):
		return
	var text: String = host.next_goal()
	if text == "":
		return
	var at := Vector2(PAD + 12.0, PAD + 46.0)
	# A chevron rather than a bullet: it points forward, which is the whole
	# message.
	var c := at + Vector2(4.0, -4.0)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-3, -5), c + Vector2(3, 0), c + Vector2(-3, 5),
		c + Vector2(-1, 0)]), Color(GOLD.r, GOLD.g, GOLD.b, 0.75))
	draw_string(_font, at + Vector2(14.0, 1.0), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.62))


## The blessing chain, as pips beside the Faith counter.
##
## `combo_chain` and `combo_left` drove the biggest multiplier in the game and
## were drawn nowhere at all -- the player could not tell a chain of five from
## a chain of one, or notice the moment one broke.
func _combo() -> void:
	if divinity == null:
		return
	var chain: int = divinity.combo_chain
	if chain < 2 and _combo_flash <= 0.0:
		return
	var at := Vector2(PAD + 12.0, PAD + 66.0)
	if _combo_flash > 0.0 and chain == 0:
		# The break, in the red the punish button uses, fading out.
		var a := clampf(_combo_flash / 0.6, 0.0, 1.0)
		draw_string(_font, at, "chain lost", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
					Color(0.88, 0.36, 0.34, a))
		return
	# One pip per link, plus the multiplier the player is actually earning.
	var left: float = clampf(divinity.combo_left / divinity.COMBO_WINDOW,
							 0.0, 1.0)
	for i in chain:
		var c := at + Vector2(6.0 + float(i) * 13.0, -4.0)
		draw_circle(c, 4.5, Color(GOLD.r, GOLD.g, GOLD.b, 0.30 + 0.70 * left))
	draw_string(_font, at + Vector2(14.0 + float(chain) * 13.0, 1.0),
				"x%.2f" % _combo_mult, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
				Color(GOLD.r, GOLD.g, GOLD.b, 0.85))


## An aiming reticle, so a mode the player is IN is visible on screen and not
## only in a line of text that has already faded.
func _reticle() -> void:
	if _aiming < 0 and not _smiting:
		return
	# Canvas space, or the reticle is drawn beside the cursor instead of on it.
	var m := get_local_mouse_position()
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
