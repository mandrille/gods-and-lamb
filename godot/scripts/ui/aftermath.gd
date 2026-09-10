extends Control
class_name Aftermath

## What just happened, and what it was worth.
##
## A calamity used to end in one line of notice text -- "You answered it. 5 gave
## thanks." -- which scrolled past in the same little stack as "No room to grow
## there." The most dramatic sixty seconds the game has were being reported in
## the same voice as a misclick, and the player was never told the two things
## they actually wanted to know: DID ANYONE GET HURT, and did this change how
## they are seen.
##
## So this is deliberately not another notice. It is a card that lands in the
## middle of the screen, holds still long enough to read, and answers the
## question the fire was asking. The design note in the spec is that a correct
## simulation the player cannot perceive is not finished; this is the perceiving
## half of the disaster loop.
##
## It draws itself and owns no state beyond the one report it is showing, so
## nothing has to be torn down when it fades -- it simply stops drawing.

const HOLD := 3.4                  ## seconds fully readable
const FADE := 1.1                  ## and then this long going away
const IN := 0.22                   ## and this long arriving

const W := 268.0
const ROW_H := 26.0
const HEAD_H := 44.0
const PAD := 16.0

const PANEL := Color(0.10, 0.11, 0.15, 0.94)
const INK := Color(0.95, 0.96, 0.98)
const DIM := Color(0.68, 0.71, 0.77)
const GOLD := Color(0.99, 0.84, 0.40)
const GOOD := Color(0.46, 0.82, 0.50)
const BAD := Color(0.86, 0.34, 0.34)

var _font: Font
var _left := 0.0                   ## seconds of life remaining
var _head := ""
var _good := true
var _rows: Array = []              ## [[icon, text, tone], ...]


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 4


## Put one up. Calling again replaces whatever is showing -- two disasters
## resolving together is rare and a queue for it would be a queue that is empty
## for the entire rest of the game.
func show_report(head: String, good: bool, rows: Array) -> void:
	_head = head
	_good = good
	_rows = rows
	_left = HOLD + FADE
	queue_redraw()


func _process(delta: float) -> void:
	if _left <= 0.0:
		return
	# UNSCALED, because this is a message to a person rather than a thing in the
	# world. At time_scale 3 a report that obeyed the game clock would be gone
	# before it was read, and the whole reason it exists is to be read.
	_left -= delta / maxf(0.01, Engine.time_scale)
	# FADED WITH `modulate` RATHER THAN PER-COLOUR, because `Icons.draw_icon`
	# carries its own palette and takes no colour -- an alpha threaded through
	# every draw_rect would have left the glyphs fully opaque over a panel that
	# had gone, which looks like a bug rather than like a fade.
	modulate = Color(1, 1, 1, clampf(_left / FADE, 0.0, 1.0))
	queue_redraw()


func _draw() -> void:
	if _left <= 0.0 or _font == null:
		return
	# And a short rise on the way in, so it reads as arriving rather than as
	# having been there all along and only now noticed.
	var born: float = HOLD + FADE - _left
	var lift: float = 14.0 * (1.0 - clampf(born / IN, 0.0, 1.0))

	# THE VIEWPORT, NOT `size`. A full-rect Control added to a CanvasLayer only
	# learns its size when the parent notifies a resize, and this one is built
	# before the window settles -- so `size` was (0, 0) and the card landed
	# half off the top-left corner reading "NTAINED". The viewport rect is the
	# thing the camera also unprojects into, and it is never a lie.
	var screen: Vector2 = get_viewport_rect().size
	var h: float = HEAD_H + float(_rows.size()) * ROW_H + PAD
	var r := Rect2(Vector2((screen.x - W) * 0.5,
						   screen.y * 0.34 + lift), Vector2(W, h))

	draw_rect(Rect2(r.position + Vector2(0, 5), r.size),
			  Color(0, 0, 0, 0.34), true)
	draw_rect(r, PANEL, true)
	draw_rect(r, Color(1, 1, 1, 0.12), false, 1.0)
	# A colour bar along the top is the fastest possible read: green means it
	# was answered, red means it was not, and that lands before a single word.
	var bar := GOOD if _good else BAD
	draw_rect(Rect2(r.position, Vector2(W, 3.0)), bar, true)

	var hw: float = float(_font.get_string_size(
		_head, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x)
	draw_string(_font, r.position + Vector2((W - hw) * 0.5, 30.0), _head,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK)

	var y: float = r.position.y + HEAD_H + 8.0
	for row in _rows:
		var icon := String(row[0])
		var text := String(row[1])
		var tone: Color = row[2] if row.size() > 2 else DIM
		Icons.draw_icon(self, icon, Vector2(r.position.x + PAD + 9.0, y + 1.0),
						16.0)
		draw_string(_font, Vector2(r.position.x + PAD + 26.0, y + 6.0), text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, tone)
		y += ROW_H
