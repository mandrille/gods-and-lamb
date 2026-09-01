extends RefCounted
class_name Icons

## Every glyph in the interface, drawn from primitives.
##
## Not emoji and not textures. Godot's default font has no emoji, so a "🌳" in
## a Label renders as a hollow box -- fine on the machine with the emoji font
## installed, broken everywhere else. And a set of PNGs would be the first
## bitmaps in a project whose entire game content is 5% of its web download,
## for pictures that are a dozen polygons each.
##
## Each function draws into `ci` centred on `at`, scaled so the glyph fits a
## box of `s` pixels. Callers never need to know how big any individual icon
## "really" is, which is what lets the same glyph sit in a 14 px resource row
## and a 34 px card without a second set of numbers.

const GOLD := Color(0.99, 0.83, 0.36)
const LEAF := Color(0.42, 0.78, 0.38)
const LEAF_DARK := Color(0.28, 0.58, 0.30)
const WOOD := Color(0.62, 0.44, 0.26)
const WOOD_DARK := Color(0.44, 0.30, 0.18)
const STONE := Color(0.66, 0.68, 0.72)
const SKIN := Color(0.92, 0.76, 0.60)
const APPLE := Color(0.86, 0.25, 0.24)
const WHEAT := Color(0.93, 0.78, 0.34)
const WATER := Color(0.55, 0.80, 0.98)
const CLOUD := Color(0.86, 0.89, 0.94)
const ROSE := Color(0.96, 0.55, 0.66)
const FLAME := Color(0.95, 0.45, 0.25)

## Typed. A bare array literal yields Variant elements, and every bit of
## arithmetic off one is then Variant too -- which this project treats as an
## error rather than a warning.
const THIRDS: Array[float] = [-1.0, 0.0, 1.0]
const RAYS: Array[float] = [-1.0, -0.4, 0.4, 1.0]
const SIDES: Array[float] = [-1.0, 1.0]
const SPOTS: Array[Vector2] = [
	Vector2(-0.32, -0.30), Vector2(0.10, -0.40), Vector2(0.36, -0.06),
	Vector2(-0.16, 0.06), Vector2(0.20, 0.30), Vector2(-0.36, 0.32)]


## Dispatch by name, so callers can hold a string and the card table can name
## its own icon. Unknown names draw a neutral disc rather than nothing: a
## missing glyph should look like a placeholder, not like a broken layout.
static func draw_icon(ci: CanvasItem, name: String, at: Vector2, s: float) -> void:
	match name:
		"faith": _faith(ci, at, s)
		"food": _apple(ci, at, s)
		"wood": _log(ci, at, s)
		"stone": _stone(ci, at, s)
		"pop": _person(ci, at, s)
		"tree": _tree(ci, at, s)
		"wheat": _wheat(ci, at, s)
		"rain": _rain(ci, at, s)
		"apple": _apple(ci, at, s)
		"heart": _heart(ci, at, s)
		"sprout": _sprout(ci, at, s)
		"confetti": _confetti(ci, at, s)
		"dove": _dove(ci, at, s)
		"bolt": _bolt(ci, at, s)
		"hunger": _apple(ci, at, s)
		"energy": _moon(ci, at, s)
		"social": _two(ci, at, s)
		"health": _heart(ci, at, s)
		"hygiene": _drop(ci, at, s)
		"fun": _confetti(ci, at, s)
		"devil": _horns(ci, at, s)
		"saint": _halo(ci, at, s)
		"bless": _hand(ci, at, s, GOLD)
		"punish": _bolt(ci, at, s)
		_: ci.draw_circle(at, s * 0.34, Color(0.55, 0.58, 0.64))


static func _poly(ci: CanvasItem, pts: Array, c: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array(pts), c)


## An eight-point star with a bright core: light, which is what Faith buys.
static func _faith(ci: CanvasItem, at: Vector2, s: float) -> void:
	var r := s * 0.46
	var pts: Array = []
	for i in 16:
		var a := TAU * float(i) / 16.0 - PI * 0.5
		var rad := r if i % 2 == 0 else r * 0.42
		pts.append(at + Vector2(cos(a), sin(a)) * rad)
	_poly(ci, pts, GOLD)
	ci.draw_circle(at, s * 0.15, Color(1, 1, 0.92))


static func _apple(ci: CanvasItem, at: Vector2, s: float) -> void:
	var r := s * 0.30
	# Two overlapping discs make the lobed shape a single circle cannot.
	ci.draw_circle(at + Vector2(-r * 0.42, r * 0.10), r * 0.86, APPLE)
	ci.draw_circle(at + Vector2(r * 0.42, r * 0.10), r * 0.86, APPLE)
	ci.draw_circle(at + Vector2(0, r * 0.46), r * 0.80, APPLE)
	ci.draw_line(at + Vector2(0, -r * 0.55), at + Vector2(r * 0.16, -s * 0.46),
				 WOOD_DARK, maxf(1.0, s * 0.07))
	_poly(ci, [at + Vector2(r * 0.10, -s * 0.40),
			   at + Vector2(s * 0.40, -s * 0.46),
			   at + Vector2(r * 0.16, -s * 0.24)], LEAF)


static func _log(ci: CanvasItem, at: Vector2, s: float) -> void:
	var w := s * 0.46
	var h := s * 0.26
	ci.draw_rect(Rect2(at.x - w, at.y - h, w * 2.0, h * 2.0), WOOD, true)
	# End grain, so it reads as a cut log and not as a brown brick.
	ci.draw_circle(at + Vector2(-w, 0), h, WOOD_DARK)
	ci.draw_circle(at + Vector2(-w, 0), h * 0.55, WOOD)
	ci.draw_circle(at + Vector2(-w, 0), h * 0.22, WOOD_DARK)


static func _stone(ci: CanvasItem, at: Vector2, s: float) -> void:
	_poly(ci, [at + Vector2(-s * 0.44, s * 0.26),
			   at + Vector2(-s * 0.30, -s * 0.22),
			   at + Vector2(s * 0.06, -s * 0.42),
			   at + Vector2(s * 0.44, -s * 0.06),
			   at + Vector2(s * 0.34, s * 0.30)], STONE)
	_poly(ci, [at + Vector2(-s * 0.30, -s * 0.22),
			   at + Vector2(s * 0.06, -s * 0.42),
			   at + Vector2(-s * 0.02, -s * 0.06)], STONE.lightened(0.22))


static func _person(ci: CanvasItem, at: Vector2, s: float) -> void:
	ci.draw_circle(at + Vector2(0, -s * 0.24), s * 0.18, SKIN)
	_poly(ci, [at + Vector2(-s * 0.24, s * 0.42),
			   at + Vector2(-s * 0.17, -s * 0.02),
			   at + Vector2(s * 0.17, -s * 0.02),
			   at + Vector2(s * 0.24, s * 0.42)], Color(0.36, 0.60, 0.44))


static func _tree(ci: CanvasItem, at: Vector2, s: float) -> void:
	ci.draw_rect(Rect2(at.x - s * 0.07, at.y + s * 0.04,
					   s * 0.14, s * 0.42), WOOD_DARK, true)
	# Rounded-cube canopy, echoing the actual art rather than a generic blob.
	ci.draw_rect(Rect2(at.x - s * 0.36, at.y - s * 0.44,
					   s * 0.72, s * 0.50), LEAF, true)
	ci.draw_rect(Rect2(at.x - s * 0.36, at.y - s * 0.44,
					   s * 0.72, s * 0.16), LEAF.lightened(0.16), true)


static func _wheat(ci: CanvasItem, at: Vector2, s: float) -> void:
	for k in THIRDS:
		var x := at.x + k * s * 0.24
		var top := at.y - s * 0.38 + absf(k) * s * 0.10
		ci.draw_line(Vector2(x, at.y + s * 0.44), Vector2(x, top),
					 WHEAT.darkened(0.25), maxf(1.0, s * 0.055))
		for g in 3:
			var gy := top + float(g) * s * 0.13
			ci.draw_circle(Vector2(x - s * 0.07, gy), s * 0.055, WHEAT)
			ci.draw_circle(Vector2(x + s * 0.07, gy), s * 0.055, WHEAT)


static func _rain(ci: CanvasItem, at: Vector2, s: float) -> void:
	var cy := at.y - s * 0.16
	ci.draw_circle(Vector2(at.x - s * 0.18, cy), s * 0.17, CLOUD)
	ci.draw_circle(Vector2(at.x + s * 0.14, cy), s * 0.21, CLOUD)
	ci.draw_circle(Vector2(at.x - s * 0.02, cy - s * 0.10), s * 0.19, CLOUD)
	ci.draw_rect(Rect2(at.x - s * 0.30, cy, s * 0.58, s * 0.14), CLOUD, true)
	for k in THIRDS:
		var x := at.x + k * s * 0.20
		ci.draw_line(Vector2(x, at.y + s * 0.10),
					 Vector2(x - s * 0.05, at.y + s * 0.44),
					 WATER, maxf(1.0, s * 0.07))


static func _heart(ci: CanvasItem, at: Vector2, s: float) -> void:
	var r := s * 0.24
	ci.draw_circle(at + Vector2(-r * 0.82, -r * 0.30), r, LEAF)
	ci.draw_circle(at + Vector2(r * 0.82, -r * 0.30), r, LEAF)
	_poly(ci, [at + Vector2(-r * 1.76, -r * 0.06),
			   at + Vector2(r * 1.76, -r * 0.06),
			   at + Vector2(0, s * 0.46)], LEAF)


static func _sprout(ci: CanvasItem, at: Vector2, s: float) -> void:
	ci.draw_line(at + Vector2(0, s * 0.44), at + Vector2(0, -s * 0.10),
				 LEAF_DARK, maxf(1.0, s * 0.08))
	for side in SIDES:
		_poly(ci, [at + Vector2(0, -s * 0.02),
				   at + Vector2(side * s * 0.40, -s * 0.30),
				   at + Vector2(side * s * 0.10, -s * 0.34)], LEAF)
	ci.draw_circle(at + Vector2(0, -s * 0.28), s * 0.08, ROSE)


static func _confetti(ci: CanvasItem, at: Vector2, s: float) -> void:
	var tints := [APPLE, WHEAT, WATER, LEAF, ROSE]
	# Fixed offsets, not random: an icon that changes every frame is noise.
	for i in SPOTS.size():
		var p: Vector2 = at + SPOTS[i] * s
		var w := s * 0.13
		ci.draw_rect(Rect2(p.x - w * 0.5, p.y - w * 0.35, w, w * 0.7),
					 tints[i % tints.size()], true)


static func _dove(ci: CanvasItem, at: Vector2, s: float) -> void:
	_poly(ci, [at + Vector2(-s * 0.42, s * 0.12),
			   at + Vector2(s * 0.06, -s * 0.16),
			   at + Vector2(s * 0.40, s * 0.06),
			   at + Vector2(-s * 0.04, s * 0.34)], Color(0.96, 0.97, 1.0))
	_poly(ci, [at + Vector2(-s * 0.06, -s * 0.12),
			   at + Vector2(s * 0.18, -s * 0.44),
			   at + Vector2(s * 0.26, -s * 0.04)], Color(0.86, 0.90, 0.98))
	ci.draw_circle(at + Vector2(s * 0.34, s * 0.02), s * 0.05,
				   Color(0.25, 0.28, 0.34))


static func _bolt(ci: CanvasItem, at: Vector2, s: float) -> void:
	_poly(ci, [at + Vector2(s * 0.10, -s * 0.46),
			   at + Vector2(-s * 0.30, s * 0.06),
			   at + Vector2(-s * 0.02, s * 0.06),
			   at + Vector2(-s * 0.14, s * 0.46),
			   at + Vector2(s * 0.30, -s * 0.08),
			   at + Vector2(s * 0.00, -s * 0.08)], FLAME)


static func _hand(ci: CanvasItem, at: Vector2, s: float, c: Color) -> void:
	# A downward blessing: rays from above onto a small figure.
	for k in RAYS:
		ci.draw_line(at + Vector2(k * s * 0.28, -s * 0.46),
					 at + Vector2(k * s * 0.16, -s * 0.06),
					 c, maxf(1.0, s * 0.06))
	ci.draw_circle(at + Vector2(0, s * 0.14), s * 0.18, c)


## --- stat glyphs ------------------------------------------------------------

static func _moon(ci: CanvasItem, at: Vector2, s: float) -> void:
	# Rest. A crescent made by punching one disc out of another with the
	# background colour would need to know the background, so it is drawn as a
	# filled arc band instead and works on anything.
	var pts: Array = []
	var r := s * 0.40
	for i in 13:
		var a := lerpf(PI * 0.35, PI * 1.65, float(i) / 12.0)
		pts.append(at + Vector2(cos(a), sin(a)) * r)
	for i in 13:
		var a := lerpf(PI * 1.65, PI * 0.35, float(i) / 12.0)
		pts.append(at + Vector2(cos(a) * r * 1.25 + r * 0.55, sin(a) * r * 0.92))
	_poly(ci, pts, Color(0.86, 0.88, 0.96))


static func _two(ci: CanvasItem, at: Vector2, s: float) -> void:
	for k in SIDES:
		var o := Vector2(k * s * 0.19, 0)
		ci.draw_circle(at + o + Vector2(0, -s * 0.20), s * 0.14, SKIN)
		_poly(ci, [at + o + Vector2(-s * 0.17, s * 0.38),
				   at + o + Vector2(-s * 0.12, s * 0.00),
				   at + o + Vector2(s * 0.12, s * 0.00),
				   at + o + Vector2(s * 0.17, s * 0.38)],
			  Color(0.42, 0.62, 0.86) if k < 0.0 else Color(0.86, 0.54, 0.60))


static func _drop(ci: CanvasItem, at: Vector2, s: float) -> void:
	_poly(ci, [at + Vector2(0, -s * 0.46),
			   at + Vector2(s * 0.30, s * 0.10),
			   at + Vector2(-s * 0.30, s * 0.10)], WATER)
	ci.draw_circle(at + Vector2(0, s * 0.10), s * 0.30, WATER)
	ci.draw_circle(at + Vector2(-s * 0.10, s * 0.12), s * 0.09,
				   Color(1, 1, 1, 0.65))


static func _horns(ci: CanvasItem, at: Vector2, s: float) -> void:
	var c := Color(0.86, 0.32, 0.36)
	ci.draw_circle(at + Vector2(0, s * 0.06), s * 0.30, c)
	for k in SIDES:
		_poly(ci, [at + Vector2(k * s * 0.30, -s * 0.10),
				   at + Vector2(k * s * 0.46, -s * 0.46),
				   at + Vector2(k * s * 0.12, -s * 0.24)], c)


static func _halo(ci: CanvasItem, at: Vector2, s: float) -> void:
	ci.draw_circle(at + Vector2(0, s * 0.10), s * 0.28, Color(0.98, 0.90, 0.60))
	ci.draw_arc(at + Vector2(0, -s * 0.28), s * 0.26, 0.0, TAU, 20,
				GOLD, maxf(1.5, s * 0.08))
