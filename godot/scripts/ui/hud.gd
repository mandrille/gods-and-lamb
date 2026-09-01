extends Control
class_name HUD

## The god's own screen: Faith, the village ledger, the miracle hand, the land
## for sale, and whatever just happened.
##
## Targeting lives here rather than in Divinity, because it is a UI mode and
## not a rule of the world. A card that needs a spot puts the HUD into
## `_aiming`, the next world click resolves it, and Escape cancels. Divinity
## itself only ever receives finished intentions -- "cast grove at this point"
## -- which keeps the rules testable without a mouse.

const PAD := 14.0
const CARD_W := 118.0
const CARD_H := 62.0

const INK := Color(0.94, 0.95, 0.97)
const DIM := Color(0.70, 0.73, 0.78)
const GOLD := Color(0.98, 0.84, 0.40)
const BACK := Color(0.10, 0.11, 0.14, 0.88)
const WARN := Color(0.95, 0.62, 0.35)

var host = null
var divinity = null
var rig = null

var _font: Font
var _notice := ""
var _notice_left := 0.0
var _aiming := -1                  ## hand index awaiting a target, or -1
var _smiting := false
var _cards: Array[Button] = []
var _buys: Array[Button] = []
var _smite_btn: Button


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_smite_btn = _mk_button("Wrath (%d)" % int(Divinity.SMITE_COST),
							Color(0.55, 0.24, 0.26))
	_smite_btn.pressed.connect(_begin_smite)
	divinity.hand_changed.connect(_rebuild_cards)
	divinity.notice.connect(_on_notice)
	divinity.island_bought.connect(func(_s): _rebuild_buys())
	_rebuild_cards()
	_rebuild_buys()


func _mk_button(text: String, tint: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = tint if state == "normal" else (
			tint.lightened(0.16) if state == "hover" else tint.darkened(0.22))
		sb.corner_radius_top_left = 5
		sb.corner_radius_top_right = 5
		sb.corner_radius_bottom_left = 5
		sb.corner_radius_bottom_right = 5
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_font_size_override("font_size", 12)
	add_child(b)
	return b


func _on_notice(text: String) -> void:
	_notice = text
	_notice_left = 4.0


## --- the hand ---------------------------------------------------------------

func _rebuild_cards() -> void:
	for b in _cards:
		b.queue_free()
	_cards.clear()
	for i in divinity.hand.size():
		var card: Dictionary = divinity.hand[i]
		var b := _mk_button("%s\n%s" % [String(card["name"]),
						  String(card["target"]).capitalize()],
						  Color(0.22, 0.30, 0.44))
		b.tooltip_text = String(card["desc"])
		b.pressed.connect(_play_card.bind(i))
		_cards.append(b)
	_layout()


func _play_card(index: int) -> void:
	if index < 0 or index >= divinity.hand.size():
		return
	var card: Dictionary = divinity.hand[index]
	var kind := String(card["target"])
	if kind == "none":
		divinity.play(index)
		return
	# Needs a target: arm, and let the next world click finish it.
	_aiming = index
	_smiting = false
	_notice = "Pick a %s for %s. Escape to cancel." % [
		"villager" if kind == "folk" else "spot", String(card["name"])]
	_notice_left = 6.0


func _begin_smite() -> void:
	_smiting = true
	_aiming = -1
	_notice = "Pick a place to destroy. Escape to cancel."
	_notice_left = 6.0


## --- land -------------------------------------------------------------------

func _rebuild_buys() -> void:
	for b in _buys:
		b.queue_free()
	_buys.clear()
	var price: int = host.islands.price_next()
	for slot in host.islands.buyable():
		var b := _mk_button("%s  %d" % [_compass(slot), price],
							Color(0.24, 0.36, 0.30))
		b.tooltip_text = "Buy the island to the %s for %d Faith." % [
			_compass(slot).to_lower(), price]
		b.pressed.connect(func():
			if divinity.buy_island(slot):
				_rebuild_buys())
		_buys.append(b)
	_layout()


func _compass(slot: Vector2i) -> String:
	var mid := Islands.GRID / 2
	var dx := slot.x - mid
	var dy := slot.y - mid
	var s := ""
	if dy < 0:
		s += "N"
	elif dy > 0:
		s += "S"
	if dx < 0:
		s += "W"
	elif dx > 0:
		s += "E"
	return s if s != "" else "Home"


## --- input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and (_aiming >= 0 or _smiting):
		_aiming = -1
		_smiting = false
		_notice = "Cancelled."
		_notice_left = 2.0
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if _aiming < 0 and not _smiting:
		return
	var hit: Variant = rig.ground_at(mb.position)
	if hit == null:
		return
	var at: Vector3 = hit
	if _smiting:
		divinity.smite(at)
		_smiting = false
	else:
		var card: Dictionary = divinity.hand[_aiming] if \
			_aiming < divinity.hand.size() else {}
		var who = null
		if not card.is_empty() and String(card["target"]) == "folk":
			who = host.overhead._under(mb.position)
			if who == null:
				_notice = "No villager there."
				_notice_left = 2.5
				get_viewport().set_input_as_handled()
				return
		divinity.play(_aiming, at, who)
		_aiming = -1
	get_viewport().set_input_as_handled()


## --- layout and paint -------------------------------------------------------

func _process(delta: float) -> void:
	if _notice_left > 0.0:
		_notice_left -= delta
	_layout()
	queue_redraw()


func _layout() -> void:
	var vp := get_viewport_rect().size
	# Hand along the bottom, centred: this is the "hotbar" the reference art
	# uses and where a phone's thumbs already are.
	var total := _cards.size() * (CARD_W + 8.0) - 8.0
	var x := (vp.x - total) * 0.5
	var y := vp.y - CARD_H - PAD
	for b in _cards:
		b.position = Vector2(x, y)
		b.size = Vector2(CARD_W, CARD_H)
		x += CARD_W + 8.0

	if _smite_btn != null:
		_smite_btn.position = Vector2(vp.x - 120.0 - PAD, y - 34.0)
		_smite_btn.size = Vector2(120.0, 26.0)
	var by := y - 34.0
	for b in _buys:
		by -= 30.0
		b.position = Vector2(vp.x - 120.0 - PAD, by)
		b.size = Vector2(120.0, 26.0)


func _draw() -> void:
	if divinity == null or host == null:
		return
	# Ledger, top left.
	var box := Rect2(PAD, PAD, 220, 74)
	draw_rect(box, BACK, true)
	draw_rect(box, Color(1, 1, 1, 0.08), false, 1.0)
	draw_string(_font, Vector2(PAD + 12, PAD + 26),
				"%d Faith" % int(divinity.faith),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, GOLD)
	var v = host.village
	draw_string(_font, Vector2(PAD + 12, PAD + 46),
				"Food %d / %d      Wood %d / %d" % [v.amount("food"),
					v.capacity("food"), v.amount("wood"), v.capacity("wood")],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)
	draw_string(_font, Vector2(PAD + 12, PAD + 64),
				"Villagers %d / %d      Islands %d" % [v.population, v.pop_cap,
					host.islands.count()],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)

	# Whatever just happened, centred under the ledger so the eye finds it.
	if _notice_left > 0.0 and _notice != "":
		var vp := get_viewport_rect().size
		var w := float(_font.get_string_size(_notice, HORIZONTAL_ALIGNMENT_LEFT,
											 -1, 14).x) + 26.0
		var nb := Rect2((vp.x - w) * 0.5, PAD, w, 28)
		draw_rect(nb, BACK, true)
		draw_string(_font, Vector2(nb.position.x + 13, nb.position.y + 19),
					_notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
					WARN if (_aiming >= 0 or _smiting) else INK)

	# An aiming reticle, so a mode the player is IN is visible on screen and
	# not only in a line of text that has already faded.
	if _aiming >= 0 or _smiting:
		var m := get_viewport().get_mouse_position()
		var tint := Color(0.95, 0.40, 0.36) if _smiting else GOLD
		draw_arc(m, 26.0, 0.0, TAU, 40, tint, 2.0)
		draw_arc(m, 8.0, 0.0, TAU, 20, tint, 1.5)
