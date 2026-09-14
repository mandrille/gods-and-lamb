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
## THE STACK HAS TWO LANES, and the reason is arithmetic: sixty-two
## `notice.emit` call sites feed three slots for four seconds each. A birth, a
## death and a prophet being named were typographically identical to "Not
## enough Faith to strike." and evicted by it. That IS the "poor UI and
## feedback" complaint, in miniature.
##
## NEWS holds the things that happened to the village. CHATTER holds everything
## else, which is the default -- nothing had to be re-tagged at 62 call sites
## for this to work, only the fifteen lines worth promoting.
const NOTICE_MAX := 3
const NEWS_SLOTS := 2
const NOTICE_LIFE := 4.0
const NEWS_LIFE := 6.0
const CHATTER_LIFE := 3.0
var _notices: Array = []                ## [{text, left, warn, news, icon}]
var _combo_chain := 0
var _combo_mult := 1.0
var _combo_flash := 0.0            ## counts down after a chain BREAKS
var _level_flash := 0.0            ## counts down after the god levels up
var _aiming := -1                  ## hand index awaiting a target, or -1
var _smiting := false
var _hot := -1                     ## hovered card, or -1
var _hot_reroll := false      ## hovering the reroll-all button

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
var _hot_rail := -1                ## hovered prayer on the rail, or -1
var _rail_open = null              ## the Prayer whose card is open, or null


func _ready() -> void:
	_font = ThemeDB.fallback_font
	# IGNORE, not STOP: the whole screen is covered by this Control and a
	# filter that accepts input would eat every drag meant for the camera.
	# Clicks are claimed only when they land on something.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	divinity.notice.connect(func(t): _say(t, NOTICE_LIFE))
	divinity.news.connect(func(t: String, icon: String): news(t, icon))
	divinity.combo_changed.connect(func(chain: int, mult: float):
		# A BREAK is the event worth drawing. The old wiring only reacted at
		# chain >= 2, so losing a chain of five produced nothing at all.
		if chain == 0 and _combo_chain >= 2:
			_combo_flash = 0.6
		_combo_chain = chain
		_combo_mult = mult)
	divinity.level_up.connect(func(_lv: int): _level_flash = 1.0)


## --- geometry ---------------------------------------------------------------
##
## One place that says where things are, used by both drawing and hit testing.
## Two copies of this arithmetic is how a button ends up looking clickable a
## few pixels away from where it actually is.

func _hand_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	# One rect per STACK, not per card: two Groves in hand are one card on
	# screen with a badge on it, played together as one stronger miracle.
	var n: int = divinity.stacks().size()
	if n == 0:
		return out
	var vp := get_viewport_rect().size
	var total := float(n) * (CARD_W + CARD_GAP) - CARD_GAP
	var x := (vp.x - total) * 0.5
	var y := vp.y - CARD_H - PAD
	for i in n:
		out.append(Rect2(x + float(i) * (CARD_W + CARD_GAP), y, CARD_W, CARD_H))
	return out


## The two standing buttons on the right. 46 px tall, not the 40 they were:
## measured against a phone, a 40 px control is under both Apple's 44 pt and
## Google's 48 dp minimum, and these are the two buttons a player presses most.
const BUTTON_H := 46.0


## NARROW MEANS A PHONE HELD UPRIGHT, and it changes where things go rather
## than only how big they are. Once the UI is dealt out in 400 units (see
## `vale_root._apply_ui_scale`) there is no longer room for a card hand across
## the middle AND a column of buttons beside it -- measured, the wrath button
## started 100 units inside the third card. So on a narrow screen the two
## standing buttons become a row ABOVE the hand instead of a column beside it.
const NARROW := 520.0


func _is_narrow() -> bool:
	return get_viewport_rect().size.x < NARROW


const REROLL_W := 84.0


## On a phone the row above the hand holds THREE buttons -- Commune, Reroll,
## Wrath -- in equal thirds. On a 400-unit screen each is about 117 units wide
## and 46 tall, comfortably over a thumb on both sides.
func _third() -> float:
	var vp := get_viewport_rect().size
	return (vp.x - PAD * 2.0 - 16.0) / 3.0


func _row_y() -> float:
	var vp := get_viewport_rect().size
	return vp.y - CARD_H - PAD - BUTTON_H - 8.0


func _wrath_rect() -> Rect2:
	var vp := get_viewport_rect().size
	if _is_narrow():
		var w := _third()
		return Rect2(PAD + (w + 8.0) * 2.0, _row_y(), w, BUTTON_H)
	return Rect2(vp.x - 132.0 - PAD, vp.y - CARD_H - PAD, 132.0, BUTTON_H)


func _commune_rect() -> Rect2:
	if _is_narrow():
		return Rect2(PAD, _row_y(), _third(), BUTTON_H)
	var r := _wrath_rect()
	return Rect2(r.position.x, r.position.y - BUTTON_H - 6.0, r.size.x,
				 BUTTON_H)


## THE REROLL-ALL BUTTON.
##
## It used to be a 22-unit strip inside each card's hover tooltip, above the
## card, with a dead gap between the two that dropped the hover on the way up
## -- and on a phone the Commune/Wrath row was drawn straight over it. Now it
## is a card-height button standing immediately left of the hand, or the
## middle third of the row above it on a phone. Empty when there is no hand.
func _reroll_rect() -> Rect2:
	if divinity == null or divinity.hand.is_empty():
		return Rect2()
	if _is_narrow():
		var w := _third()
		return Rect2(PAD + w + 8.0, _row_y(), w, BUTTON_H)
	var rects := _hand_rects()
	if rects.is_empty():
		return Rect2()
	var first: Rect2 = rects[0]
	return Rect2(first.position.x - CARD_GAP - REROLL_W, first.position.y,
				 REROLL_W, CARD_H)


## --- input ------------------------------------------------------------------

func _process(delta: float) -> void:
	if _combo_flash > 0.0:
		_combo_flash -= delta
	if _level_flash > 0.0:
		_level_flash -= delta
	for n in _notices:
		n["left"] = float(n["left"]) - delta
	# FILTERED, NOT POPPED FROM THE TAIL.
	#
	# A short line pushed in FRONT of a longer one reached zero while the older
	# one was still alive, so the tail test never reached it: it drew at alpha
	# zero forever and `_toast` still advanced the layout 36 units for it. An
	# invisible gap above the visible text, for up to four and a half seconds.
	_notices = _notices.filter(func(n): return float(n["left"]) > 0.0)
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
	var was := _hot
	var rects := _hand_rects()
	_hot = -1
	# The lifted card keeps its hover over its LIFTED area, or a pointer
	# resting on its raised top edge flickers between hot and not. No longer
	# "sticky" across a tooltip: there is nothing in the tooltip to reach.
	if was >= 0 and was < rects.size():
		var r: Rect2 = rects[was]
		r.position.y -= LIFT
		r.size.y += LIFT
		if r.has_point(m):
			_hot = was
	if _hot < 0:
		for i in rects.size():
			if rects[i].has_point(m):
				_hot = i
				break
	_hot_reroll = _reroll_rect().has_point(m)
	_hot_wrath = _wrath_rect().has_point(m)
	_hot_commune = _commune_rect().has_point(m)
	_hot_rail = _rail_at(m)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# Escape peels one layer at a time: an aim first, then a miracle still
		# riding the cursor, and only then the pause menu. A held miracle had
		# NO way to be let go early -- release() existed and no input path
		# reached it -- so a misfire cost seven seconds of standing still.
		if _aiming >= 0 or _smiting:
			_cancel("Cancelled.")
			get_viewport().set_input_as_handled()
			return
		if host != null and host.cursor != null and host.cursor.is_active():
			host.cursor.release()
			_say("Let go.", 1.5)
			get_viewport().set_input_as_handled()
			return
		if host != null and host.pause_menu != null:
			host.pause_menu.toggle()
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

	# THE PRAYER RAIL, first of all: it is the top of the screen.
	if _hot_rail >= 0:
		_open_rail(_hot_rail)
		get_viewport().set_input_as_handled()
		return
	# A click inside an open prayer card is swallowed; anywhere else closes it
	# and still does what it was going to do -- it is a popover, not a modal.
	if _rail_open != null:
		if _rail_detail_rect().has_point(make_input_local(mb).position):
			get_viewport().set_input_as_handled()
			return
		_rail_open = null

	# A click on the hand or the standing buttons, first: these sit on top.
	if _hot_reroll:
		if divinity.reroll_hand() and host != null and host.sfx != null:
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


## `index` is a STACK on screen. Sweeps and village-wide cards spend every copy
## of that card at once; the old aimed path, which nothing in the deck uses any
## more, still receives a real hand index.
func _play_card(index: int) -> void:
	var st: Array = divinity.stacks()
	if index < 0 or index >= st.size():
		return
	var top: Dictionary = st[index]["card"]
	var cid := String(top["id"])
	var copies: int = int(st[index]["count"])
	# A HELD miracle needs no aiming step at all: it appears on the cursor and
	# the player walks it over whatever they want it to touch.
	if MiracleCursor.handles(cid):
		if divinity.play_stack(cid):
			_aiming = -1
			_smiting = false
			var lead := "x%d. " % copies if copies > 1 else ""
			_say("%sSweep it over your people. It fades in %d seconds."
				% [lead, int(MiracleCursor.SECONDS)], 4.0)
		return
	if String(top["target"]) == "all":
		divinity.play_stack(cid)
		_aiming = -1
		_smiting = false
		return
	index = _first_hand_index(cid)
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


## REWRITE THE TOP LINE. `_say` de-dupes on the exact string, which is enough
## for "Not enough Faith" and useless for an aggregated line: it carries a
## count, so "3 saw it" and "4 saw it" are different strings and three touches
## would fill the whole stack with near-identical lines.
func amend(text: String, secs: float) -> void:
	if _notices.is_empty():
		_say(text, secs)
		return
	_notices[0]["text"] = text
	_notices[0]["left"] = secs


## Something happened to the VILLAGE. Held longer, carries a glyph, and can
## only be pushed out by more news -- never by a misclick.
func news(text: String, icon := "faith", secs := NEWS_LIFE) -> void:
	_say(text, secs, true, icon)


func _say(text: String, secs: float, is_news := false, icon := "") -> void:
	# A repeat refreshes the line it is already on rather than stacking three
	# copies of "Not enough Faith to strike."
	for n in _notices:
		if String(n["text"]) == text:
			n["left"] = secs
			return
	_notices.push_front({"text": text, "left": secs,
						 "warn": _aiming >= 0 or _smiting,
						 "news": is_news, "icon": icon})
	_trim()


## Trim by LANE rather than by age.
##
## News is evicted only by news, and only once there are more than NEWS_SLOTS
## of it. Chatter is evicted by anything. So "Mara and Odo have a child" cannot
## be pushed off the screen by the player tapping a card they cannot afford,
## which is what used to happen.
func _trim() -> void:
	while _notices.size() > NOTICE_MAX:
		var victim := -1
		for i in range(_notices.size() - 1, -1, -1):
			if not bool(_notices[i].get("news", false)):
				victim = i
				break
		if victim < 0:
			victim = _notices.size() - 1
		_notices.remove_at(victim)
	# And news never occupies the whole stack, or the chatter lane -- which is
	# where every refusal the player needs to read lives -- has nowhere to go.
	var newsy := 0
	for n in _notices:
		if bool(n.get("news", false)):
			newsy += 1
	while newsy > NEWS_SLOTS:
		for i in range(_notices.size() - 1, -1, -1):
			if bool(_notices[i].get("news", false)):
				_notices.remove_at(i)
				newsy -= 1
				break


## --- paint ------------------------------------------------------------------

func _draw() -> void:
	if divinity == null or host == null:
		return
	_ledger()
	_godbar()
	_daybar()
	_rail()
	_goal()
	_combo()
	_hand()
	_reroll()
	_commune()
	_wrath()
	_toast()
	_rail_detail()
	_reticle()


## --- the top-left stack -----------------------------------------------------
##
## Four things pile up in the top-left corner -- the ledger, the god's level,
## the goal line and the combo pips -- and each used to carry its own literal
## y offset. That is how the level bar landed exactly on top of the goal line
## the day it was added: two constants, written months apart, that happened to
## describe the same 20 pixels.
##
## One ladder now. Each rung is the one below the last, and on a narrow screen
## the whole ladder starts under the day bar instead of beside it.

const LEDGER_H := 34.0
const GOD_H := 28.0
const DAYBAR_H := 52.0


## Where the ledger's own top edge is. On a phone the day clock takes the full
## width of the first row, because a 268-unit panel centred in 400 units of
## screen sits directly on top of the ledger.
func _stack_top() -> float:
	# On a phone the prayer rail has its own rung under the day clock, and the
	# rung is RESERVED rather than appearing and vanishing: a ladder that jumps
	# whenever somebody starts or stops praying is a ladder nobody can read the
	# ledger off.
	return PAD + (DAYBAR_H + 6.0 + RAIL_SLOT + 12.0 if _is_narrow() else 0.0)


func _god_y() -> float:
	return _stack_top() + LEDGER_H + 6.0


func _goal_y() -> float:
	return _god_y() + GOD_H + 8.0


func _combo_y() -> float:
	return _goal_y() + 20.0


## The ledger's own box, so the drawing and the layout test read one number.
func _ledger_rect() -> Rect2:
	var total := 0.0
	for e in _ledger_rows():
		total += _row_width(String(e[1]))
	return Rect2(PAD, _stack_top(), total + 20.0, LEDGER_H)


## Where a ledger counter sits on screen, so a resource token can fly to it.
## Computed from the same row table `_ledger` draws from -- a second copy of
## the layout is how a token ends up landing next to the counter it means.
func ledger_icon_pos(key: String) -> Vector2:
	var x := PAD + 12.0
	for e in _ledger_rows():
		if String(e[0]) == key:
			return Vector2(x + 8.0, _stack_top() + 17.0)
		x += _row_width(String(e[1]))
	return Vector2(PAD + 20.0, _stack_top() + 17.0)


## Where the village has got to. Roman numerals because "Age 2" reads as a
## debug counter and "Age II" reads as an achievement.
func _age_label() -> String:
	var n: int = divinity.age
	if n <= 0:
		return "-"
	# Sized from the table rather than a literal list: an age added to AGES
	# used to fall off the end of a three-item array the moment it was reached.
	const NUMERALS := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"]
	return String(NUMERALS[mini(n, NUMERALS.size()) - 1])


## The gap after each counter. 16 is comfortable; 8 is what makes six counters
## fit inside 400 units, which is what a phone has.
func _row_width(text: String) -> float:
	return 22.0 + float(_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
											  -1, 15).x) 		+ (8.0 if _is_narrow() else 16.0)


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
	var box := _ledger_rect()
	var x := PAD + 12.0
	var widths: Array[float] = []
	for e in row:
		widths.append(_row_width(String(e[1])))
	_panel(box)
	var cy := box.position.y + box.size.y * 0.5
	for i in row.size():
		var e: Array = row[i]
		Icons.draw_icon(self, String(e[0]), Vector2(x + 8.0, cy), 19.0)
		draw_string(_font, Vector2(x + 22.0, cy + 5.0), String(e[1]),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15, e[2])
		x += widths[i]


## WHAT THE PLAYER IS, under what the village has.
##
## The village ledger says how the village is doing. This says how the PLAYER is
## doing, and it is the only line on screen that is about them -- everything
## else is about wheat. It sits directly under the ledger because the two are
## read together: "they have twelve wood and I am nearly Level 4."
##
## Drawn as a bar rather than a number because a number that goes up on its own
## is a score, and a bar that is three-quarters full is a reason to keep playing
## for another minute.
func _godbar() -> void:
	var lv: int = int(divinity.god_level)
	# WHAT THEY CALL YOU, when they have made up their minds. One word beside
	# the level and no numbers anywhere -- the whole design note on reputation
	# is that it must not read as a stat sheet.
	var known := String(divinity.reputation.title())
	var label := "Level %d" % lv if known == "" else "Level %d  %s" % [lv, known]
	var w := 34.0 + float(_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT,
												-1, 15).x) + 96.0
	# CLAMPED. The label grows when they have decided what to call you, and this
	# bar is one of the fixed-pixel rects that ran off the right edge of a phone
	# the last time something here got longer.
	w = minf(w, get_viewport_rect().size.x - PAD * 2.0)
	var r := Rect2(PAD, _god_y(), w, GOD_H)
	_panel(r)
	if _level_flash > 0.0:
		draw_rect(r.grow(1.0),
				  Color(GOLD.r, GOLD.g, GOLD.b, 0.85 * _level_flash), false, 2.0)
	var cy := r.position.y + r.size.y * 0.5
	Icons.draw_icon(self, "saint", Vector2(r.position.x + 20.0, cy), 18.0)
	draw_string(_font, Vector2(r.position.x + 34.0, cy + 5.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, GOLD)
	# The bar to the next one. At the last level there is nothing left to fill,
	# so it reads full rather than empty -- an empty bar at the top of the game
	# looks like a bug.
	var track := Rect2(r.position.x + w - 88.0, cy - 3.0, 76.0, 6.0)
	draw_rect(track, Color(1, 1, 1, 0.12), true)
	var lit := track
	lit.size.x = track.size.x * clampf(divinity.level_progress(), 0.0, 1.0)
	draw_rect(lit, GOLD, true)


func _hand() -> void:
	var rects := _hand_rects()
	var st: Array = divinity.stacks()
	var armed_id := ""
	if _aiming >= 0 and _aiming < divinity.hand.size():
		armed_id = String(divinity.hand[_aiming]["id"])
	for i in mini(rects.size(), st.size()):
		var card: Dictionary = st[i]["card"]
		var count: int = int(st[i]["count"])
		var r: Rect2 = rects[i]
		var hot := i == _hot
		var armed := armed_id != "" and String(card["id"]) == armed_id
		if hot or armed:
			r.position.y -= LIFT
		_card(r, card, hot, armed, count)
	if _hot >= 0 and _hot < st.size() and _hot < rects.size():
		_tooltip(rects[_hot], st[_hot]["card"], int(st[_hot]["count"]))


func _card(r: Rect2, card: Dictionary, hot: bool, armed: bool,
		   count := 1) -> void:
	draw_rect(Rect2(r.position + Vector2(0, 4), r.size), Color(0, 0, 0, 0.30),
			  true)
	draw_rect(r, CARD_BG_HOT if (hot or armed) else CARD_BG, true)
	draw_rect(r, GOLD if armed else CARD_EDGE, false, 2.0 if armed else 1.0)
	# THE STACK BADGE. Two or three of the same card are one card on screen,
	# and the badge is what says it will land harder.
	if count > 1:
		var bc := r.position + Vector2(r.size.x - 13.0, 13.0)
		draw_circle(bc, 14.0, GOLD)
		var bt := "x%d" % count
		var bw := float(_font.get_string_size(bt, HORIZONTAL_ALIGNMENT_LEFT,
											  -1, 13).x)
		draw_string(_font, bc + Vector2(-bw * 0.5, 5.0), bt,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.12, 0.09, 0.02))

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
	# WHAT IT ACTUALLY DOES. This read "instant", "on a villager" and "on a
	# spot", and all three were false: every original card is swept over
	# people on the cursor, so the label described a targeting model the game
	# stopped using a long time ago.
	var note: String = "everyone" if kind == "all" else "sweep"
	if count > 1:
		note = "x%d stronger" % count
	var tw := float(_font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT,
										  -1, 11).x)
	draw_string(_font, r.position + Vector2((r.size.x - tw) * 0.5, 102.0), note,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, GOLD if count > 1 else DIM)


func _first_hand_index(card_id: String) -> int:
	for i in divinity.hand.size():
		if String(divinity.hand[i]["id"]) == card_id:
			return i
	return -1


## The explanation, above the card, on hover. ONE SOURCE for its geometry.
func _tooltip_geo(anchor: Rect2, card: Dictionary, count := 1) -> Dictionary:
	var desc := String(card["desc"])
	var title := String(card["name"])
	var extra := _stack_line(count)
	var w := maxf(float(_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT,
											  -1, 16).x),
				  float(_font.get_string_size(desc, HORIZONTAL_ALIGNMENT_LEFT,
											  -1, 13).x))
	if extra != "":
		w = maxf(w, float(_font.get_string_size(extra, HORIZONTAL_ALIGNMENT_LEFT,
												-1, 13).x))
	w = maxf(w + 28.0, 150.0)
	var h := 76.0 if extra != "" else 56.0
	var vp := get_viewport_rect().size
	var x := clampf(anchor.position.x + anchor.size.x * 0.5 - w * 0.5,
					PAD, vp.x - w - PAD)
	var y := anchor.position.y - LIFT - h - 10.0
	return {"panel": Rect2(x, y, w, h)}


func _stack_line(count: int) -> String:
	if count <= 1:
		return ""
	return "%d cards as one: wider, faster, pays more." % count


## Explains what the card does. There is no button in it any more: a control
## you have to chase the hover up to is a control nobody presses. See _reroll.
func _tooltip(anchor: Rect2, card: Dictionary, count := 1) -> void:
	var panel: Rect2 = _tooltip_geo(anchor, card, count)["panel"]
	_panel(panel)
	draw_string(_font, panel.position + Vector2(14.0, 24.0), String(card["name"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GOLD)
	draw_string(_font, panel.position + Vector2(14.0, 44.0), String(card["desc"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)
	var extra := _stack_line(count)
	if extra != "":
		draw_string(_font, panel.position + Vector2(14.0, 64.0), extra,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GOLD)


## Reroll every card in the hand, beside the hand, for a flat price.
func _reroll() -> void:
	var r := _reroll_rect()
	if r.size.x <= 0.0:
		return
	var cost := int(Divinity.HAND_REROLL_COST)
	var can: bool = divinity.can_afford(float(cost))
	var hot := _hot_reroll and can
	draw_rect(Rect2(r.position + Vector2(0, 4), r.size), Color(0, 0, 0, 0.30),
			  true)
	draw_rect(r, CARD_BG_HOT if hot else CARD_BG, true)
	draw_rect(r, GOLD if hot else (CARD_EDGE if can else Color(1, 1, 1, 0.10)),
			  false, 2.0 if hot else 1.0)
	var ink := INK if can else Color(0.55, 0.56, 0.60)
	if _is_narrow():
		var label := "Reroll  %d" % cost
		var lw := float(_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT,
											  -1, 15).x)
		draw_string(_font, r.position + Vector2((r.size.x - lw) * 0.5, 29.0),
					label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ink)
		return
	# A drawn circular arrow: the one glyph everybody reads as "again".
	var c := r.position + Vector2(r.size.x * 0.5, 42.0)
	draw_arc(c, 17.0, -PI * 0.10, PI * 1.45, 26, ink, 3.2, true)
	var tip := c + Vector2(cos(-PI * 0.10), sin(-PI * 0.10)) * 17.0
	draw_colored_polygon(PackedVector2Array([tip + Vector2(-8.0, -2.0),
											 tip + Vector2(6.0, -7.0),
											 tip + Vector2(3.0, 7.0)]), ink)
	for pair in [["Reroll", 84.0, 15, ink], ["%d Faith" % cost, 103.0, 12,
			GOLD if can else Color(0.55, 0.56, 0.60)]]:
		var t := String(pair[0])
		var tw := float(_font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT,
											  -1, int(pair[2])).x)
		draw_string(_font, r.position + Vector2((r.size.x - tw) * 0.5,
					float(pair[1])), t, HORIZONTAL_ALIGNMENT_LEFT, -1,
					int(pair[2]), pair[3])


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


## Where the notice stack starts: the last rung of the left ladder on a phone.
##
## It used to start at PAD + 52 = 68, centred. On a narrow screen `_stack_top`
## is 74, so the ledger occupied y 74-108 and the first notice y 68-100 -- and
## `_toast` draws AFTER `_ledger`, so every message painted over the village's
## own resource counts. `phone_probe` never caught it because its overlap check
## only registered the hand, Commune and Wrath.
func _notice_y() -> float:
	return _combo_y() + 20.0 if _is_narrow() else PAD + 52.0


func _toast() -> void:
	if _notices.is_empty():
		return
	var vp := get_viewport_rect().size
	var narrow := _is_narrow()
	var y := _notice_y()
	for n in _notices:
		var a := clampf(float(n["left"]), 0.0, 1.0)
		# NOTHING ADVANCES THE LAYOUT THAT DID NOT DRAW. Belt and braces with
		# the filter in `_process`: a row at zero alpha must not leave a hole.
		if a <= 0.0:
			continue
		var text := String(n["text"])
		var icon := String(n.get("icon", ""))
		var lead := 34.0 + (16.0 if icon != "" else 0.0)
		var w := float(_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
											 -1, 15).x) + lead
		# Left-aligned in the ladder on a phone; centred where there is room.
		var r := Rect2(PAD if narrow else (vp.x - w) * 0.5, y, w, 32.0)
		draw_rect(r, Color(PANEL.r, PANEL.g, PANEL.b, PANEL.a * a), true)
		draw_rect(r, Color(1, 1, 1, 0.10 * a), false, 1.0)
		var x := r.position.x + 17.0
		# A GLYPH IS THE OTHER HALF. A birth and a misclick reading identically
		# is the complaint; the icon separates them before a word is read.
		if icon != "":
			Icons.draw_icon(self, icon, Vector2(x + 1.0, y + 16.0), 15.0)
			x += 17.0
		var tint := WARN if bool(n["warn"]) else INK
		draw_string(_font, Vector2(x, y + 21.0), text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
					Color(tint.r, tint.g, tint.b, a))
		y += 36.0


## --- the prayer rail ---------------------------------------------------------
##
## WHO IS ASKING, AT THE TOP OF THE SCREEN, AS SOMETHING YOU CAN PRESS.
##
## A prayer used to exist only as a bubble over a head -- invisible the moment
## the camera looked elsewhere -- and a four-second line of text. The owner
## asked for them at the top, as icons, that say what they want when clicked.
## The village's own prayers sit first, on a square gold plate; a person's sit
## after, on the same warm disc as the bubble over their head, so the rail and
## the world visibly agree.
const RAIL_SLOT := 46.0
const RAIL_GAP := 8.0
const DETAIL_W := 310.0
const DETAIL_H := 88.0


func _rail_y() -> float:
	if _is_narrow():
		return PAD + DAYBAR_H + 6.0
	return PAD - 2.0


## How many slots fit: a phone's full row, or the space right of the day clock.
func _rail_cap() -> int:
	var vp := get_viewport_rect().size
	if _is_narrow():
		return maxi(1, int(floor((vp.x - PAD * 2.0 + RAIL_GAP)
								 / (RAIL_SLOT + RAIL_GAP))))
	var day_right := (vp.x + 268.0) * 0.5
	return maxi(1, int(floor((vp.x - PAD - day_right - 8.0 + RAIL_GAP)
							 / (RAIL_SLOT + RAIL_GAP))))


## The prayers the rail shows: the village first, then the desperate, then the rest.
func _rail_prayers() -> Array:
	if host == null or host.get("prayers") == null or host.prayers == null:
		return []
	var out: Array = []
	for p in host.prayers.active:
		if p.village_wide():
			out.append(p)
	for p in host.prayers.active:
		if not p.village_wide() and p.urgent:
			out.append(p)
	for p in host.prayers.active:
		if not p.village_wide() and not p.urgent:
			out.append(p)
	var cap := _rail_cap()
	if out.size() > cap:
		out = out.slice(0, cap)
	return out


## ONE SOURCE for the slots, read by both the drawing and the hit test.
func _rail_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var n := _rail_prayers().size()
	var vp := get_viewport_rect().size
	var y := _rail_y()
	for i in n:
		var x: float
		if _is_narrow():
			x = PAD + float(i) * (RAIL_SLOT + RAIL_GAP)
		else:
			x = vp.x - PAD - RAIL_SLOT - float(i) * (RAIL_SLOT + RAIL_GAP)
		out.append(Rect2(x, y, RAIL_SLOT, RAIL_SLOT))
	return out


func _rail_at(m: Vector2) -> int:
	var rects := _rail_rects()
	for i in rects.size():
		if rects[i].has_point(m):
			return i
	return -1


## Open the card, and TAKE THE PLAYER THERE when it is a person asking.
func _open_rail(i: int) -> void:
	var list := _rail_prayers()
	if i < 0 or i >= list.size():
		return
	var p = list[i]
	if _rail_open == p:
		_rail_open = null
		return
	_rail_open = p
	if p.village_wide() or not is_instance_valid(p.who) or host == null:
		return
	if host.rig != null:
		host.rig.focus = p.who.position
		host.rig._place()
	if host.overhead != null:
		host.overhead.selected = p.who
	if host.panel != null:
		host.panel.show_for(p.who)


func _rail() -> void:
	var list := _rail_prayers()
	var rects := _rail_rects()
	if list.is_empty():
		# On a phone the rung is reserved, so an empty one says why it is empty
		# rather than reading as a hole in the layout.
		if _is_narrow():
			draw_string(_font, Vector2(PAD + 4.0, _rail_y() + 28.0),
						"Nobody is praying right now.",
						HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
		return
	var now: float = float(host.village.now) if host.village != null else 0.0
	for i in mini(list.size(), rects.size()):
		var p = list[i]
		var r: Rect2 = rects[i]
		var c := r.get_center()
		var hot: bool = i == _hot_rail or p == _rail_open
		var rim: Color = Overhead.PRAY_HOT if p.urgent else Overhead.PRAY_WARM
		if p.village_wide():
			draw_rect(r, Color(0.30, 0.24, 0.08, 0.95), true)
			draw_rect(r, GOLD, false, 3.0 if hot else 2.0)
		else:
			draw_circle(c, RAIL_SLOT * 0.5, Color(0.08, 0.09, 0.12, 0.92))
			draw_arc(c, RAIL_SLOT * 0.5 - 1.5, 0.0, TAU, 28, rim,
					 3.4 if hot else 2.4, true)
		if hot:
			draw_rect(r.grow(3.0), Color(1, 1, 1, 0.35), false, 1.5)
		Icons.draw_icon(self, p.icon(), c, 26.0)
		var life: float = Prayer.GLOBAL_LIFETIME if p.village_wide() \
			else Prayer.LIFETIME
		var left := clampf(1.0 - (now - float(p.born)) / life, 0.0, 1.0)
		draw_rect(Rect2(r.position.x + 4.0, r.end.y + 3.0,
						(r.size.x - 8.0) * left, 3.0), rim, true)


func _rail_detail_rect() -> Rect2:
	if _rail_open == null:
		return Rect2()
	var vp := get_viewport_rect().size
	var y := _rail_y() + RAIL_SLOT + 12.0
	if _is_narrow():
		return Rect2(PAD, y, vp.x - PAD * 2.0, DETAIL_H)
	return Rect2(vp.x - PAD - DETAIL_W, y, DETAIL_W, DETAIL_H)


## What counts as an answer, said in the player's own verbs.
func _hint_for(tag: int) -> String:
	match tag:
		DivineAction.FOOD:
			return "an apple from a tree, Feast, or Plenty"
		DivineAction.LIFE:
			return "a blessing, Mend, or Cleanse"
		DivineAction.JOY:
			return "Revel, Vision, or Gathering"
		DivineAction.NATURE:
			return "growing grass and trees, or Grove"
		DivineAction.STONE:
			return "breaking a rock, or Upheaval"
		DivineAction.WATER:
			return "Rain, or Cleanse"
		DivineAction.PROTECTION:
			return "Calm, or ending the danger"
	return "any act of the right kind"


func _rail_detail() -> void:
	if _rail_open == null:
		return
	if host == null or host.prayers == null \
			or not host.prayers.active.has(_rail_open):
		_rail_open = null
		return
	var p = _rail_open
	var r := _rail_detail_rect()
	_panel(r)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 3.0)),
			  Overhead.PRAY_HOT if p.urgent else GOLD, true)
	Icons.draw_icon(self, p.icon(), r.position + Vector2(24.0, 26.0), 24.0)
	draw_string(_font, r.position + Vector2(46.0, 31.0), p.says(),
				HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 58.0, 15,
				Overhead.PRAY_HOT if p.urgent else INK)
	var whose := "The whole village is asking."
	if not p.village_wide() and is_instance_valid(p.who) and p.who.brain != null:
		whose = "%s is asking you directly." % String(p.who.brain.name)
	draw_string(_font, r.position + Vector2(14.0, 55.0), whose,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
	draw_string(_font, r.position + Vector2(14.0, 75.0),
				"Answer with " + _hint_for(int(p.spec().get("tag", 0))) + ".",
				HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 28.0, 12, GOLD)


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
	# Full width on a phone. Centred, a 268-unit panel in 400 units of screen
	# lands squarely on the ledger; there is no third place for it to go.
	var w := 268.0
	var r := Rect2((vp.x - w) * 0.5, PAD - 2.0, w, DAYBAR_H)
	if _is_narrow():
		w = vp.x - PAD * 2.0
		r = Rect2(PAD, PAD - 2.0, w, DAYBAR_H)
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
	var at := Vector2(PAD + 12.0, _goal_y() + 14.0)
	# A chevron rather than a bullet: it points forward, which is the whole
	# message.
	var c := at + Vector2(4.0, -4.0)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-3, -5), c + Vector2(3, 0), c + Vector2(-3, 5),
		c + Vector2(-1, 0)]), Color(GOLD.r, GOLD.g, GOLD.b, 0.75))
	draw_string(_font, at + Vector2(14.0, 1.0), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.62))
	_prophecy(at + Vector2(0.0, 18.0))


## WHAT THE PROPHET SAID IS COMING, under the standing goal rather than instead
## of it. The two are different things and the difference matters: the goal is
## what the game always wants next, and it never runs out; a prophecy is a thing
## somebody in the village claimed, it has a clock on it, and it can be missed
## with no consequence at all. Drawn in the prophet's gold so the two lines are
## not read as one list.
func _prophecy(at: Vector2) -> void:
	if host == null or host.get("prophecies") == null:
		return
	var p = host.prophecies.current
	if p == null or host.village == null:
		return
	var text: String = host.prophecies.line(float(host.village.now))
	if text == "":
		return
	Icons.draw_icon(self, p.icon(), at + Vector2(5.0, -3.0), 14.0)
	draw_string(_font, at + Vector2(14.0, 1.0), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				Color(GOLD.r, GOLD.g, GOLD.b, 0.78))


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
	var at := Vector2(PAD + 12.0, _combo_y() + 14.0)
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
