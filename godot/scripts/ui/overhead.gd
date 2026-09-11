extends Control
class_name Overhead

## Icons that live above villagers' heads: mood on hover, a speech bubble while
## they are talking.
##
## ONE Control that draws all of them, rather than a Sprite3D or a Label per
## follower. Forty followers with two child nodes each is eighty nodes to
## transform and cull every frame for something that is a dozen circles; this
## projects each head to screen coordinates and draws. It also means the icons
## are always the same size on screen and always face the camera, both of which
## a 3D billboard has to be talked into.
##
## Faces are DRAWN, not typed. Godot's default font has no emoji, so a "🙂" in a
## Label renders as a hollow box -- which is exactly the sort of thing that
## looks fine on the machine with the emoji font installed and ships broken.

signal follower_hovered(who)            ## null when nothing is under the cursor
signal follower_clicked(who)

## Screen pixels around a head that count as "on this villager".
##
## Generous, and it has to be. A villager is about 40 px tall at the play
## camera and MOVING, so a tight radius means the player chases them with the
## cursor and misses -- which was the complaint. This is a soft target the size
## of a fingertip, which is also what makes it work on a phone at all.
##
## The radius is measured from the HEAD, and the body hangs below it, so the
## effective target covers the whole figure rather than a disc floating above.
const PICK_RADIUS := 52.0
const HEAD_HEIGHT := 1.05               ## metres above the follower's origin

const HAPPY := Color(0.36, 0.80, 0.40)
const FLAT := Color(0.94, 0.78, 0.28)
const SAD := Color(0.88, 0.36, 0.34)
const BUBBLE := Color(0.98, 0.98, 0.96)
const INK := Color(0.16, 0.17, 0.20)

## Which glyph names a job. Villager and adventurer are deliberately absent --
## everyone starts as one or the other, so a badge on them would say nothing.
const JOB_ICON := {
	"lumberjack": "axe", "miner": "pick", "builder": "hammer",
	"hunter": "bow", "priest": "cross", "nurse": "bandage", "bard": "lute",
}

var host = null                         ## ValeRoot
var rig = null                          ## CameraRig

## WHO IS LOOKING UP, and until when. `instance id -> {glyph, until}`, keyed on
## the village clock so it survives a time-scale change.
##
## No registration system for one caller: `_draw` is a hard-coded priority chain
## and its order is load-bearing, so a marker kind is a branch in that chain
## plus a draw helper. This one goes ABOVE guilt -- a reaction lasts a second
## and guilt lasts many, so briefly outranking it costs nothing, while losing to
## it would make the reaction invisible on exactly the most interesting people.
var _looking: Dictionary = {}

var hovered = null
var selected = null

## Set while a villager-only miracle is armed: every villager gets a ring, so
## the player can see who the valid targets ARE rather than hunting for them.
var highlight_all := false

var _mouse := Vector2(-1000, -1000)


## HOW MUCH OF THE AUTHORED MOTION SURVIVES, asked at draw time rather than
## pushed in when the setting changes -- so nothing here can be left in a stale
## state and turning motion down lands on the very next frame.
func _beat() -> float:
	if host == null or host.get("comfort") == null:
		return 1.0
	return float(host.comfort.beat())


func _ready() -> void:
	# The icons must never eat a click meant for the ground: panning is a drag
	# on the world, and a full-screen Control that accepts input would swallow
	# it. Hit-testing is done by hand in _gui_input's place, below.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if host == null or rig == null or rig.cam == null:
		return
	# CANVAS space. under() compares against Camera3D.unproject_position, which
	# is in canvas space, so the raw viewport position missed by the stretch
	# factor -- which is most of why villagers were "super hard to click".
	_mouse = get_local_mouse_position()
	var was = hovered
	hovered = under(_mouse)
	if hovered != was:
		follower_hovered.emit(hovered)
	queue_redraw()


## Followers are picked by SCREEN distance to the head, not by a 3D ray.
##
## They are small, they move, and a ray that has to hit a 40 cm capsule is a
## ray the player misses. A generous screen-space radius is what makes clicking
## a villager feel like clicking a villager. Nearest-to-cursor wins so a crowd
## does not become a lottery.
## Mark somebody as having noticed something, for `secs` of village time.
func mark(f, secs := 1.2) -> void:
	if f == null or host == null or host.village == null:
		return
	_looking[f.get_instance_id()] = float(host.village.now) + secs


func under(at: Vector2):
	var best = null
	var best_score := 1.0
	for f in host.folk:
		if not is_instance_valid(f):
			continue
		var feet: Vector3 = f.position
		var head: Vector3 = feet + Vector3(0, HEAD_HEIGHT, 0)
		if rig.cam.is_position_behind(head) or rig.cam.is_position_behind(feet):
			continue
		var ph: Vector2 = rig.cam.unproject_position(head)
		var pf: Vector2 = rig.cam.unproject_position(feet)
		# The target is a CAPSULE from feet to head, widened, not a disc around
		# the head. Zoomed in, a fixed disc covers the hat and misses the body;
		# zoomed out it is larger than the villager. Measuring the figure on
		# screen makes the target the right size at every distance.
		var tall: float = maxf(ph.distance_to(pf), 8.0)
		var radius: float = maxf(PICK_RADIUS, tall * 0.62)
		var d: float = _to_segment(at, pf, ph)
		# Normalised, so the NEAREST villager wins even when their targets are
		# different sizes -- comparing raw distances would favour whoever
		# happens to be closest to the camera.
		var score := d / radius
		if score < 1.0 and score < best_score:
			best_score = score
			best = f
	return best


## Distance from a point to a line segment. Villagers are tall and thin on
## screen, and a point-to-point test against either end leaves a gap in the
## middle of the body -- which is exactly where people aim.
static func _to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Input is taken from _unhandled_input rather than _gui_input so the camera
## still gets drags that start on empty ground. A click on a villager is
## consumed; a click anywhere else is left alone.
## A FINGER COUNTS TOO. This handled InputEventMouseButton only, which meant
## that on a phone -- the shipping target, in the orientation the project is
## already configured for -- a villager could not be selected or blessed at all.
## The project turns on emulate_mouse_from_touch, and that is what hid it: the
## emulation drives the HUD and the camera, so everything else responded to a
## tap and this one thing quietly did not.
func _unhandled_input(event: InputEvent) -> void:
	var at := Vector2(-9999, -9999)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
			return
		at = make_input_local(mb).position
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		# The FIRST finger only: the second one is a pinch, and a pinch that
		# also selected whoever was under the far thumb would be maddening.
		if not st.pressed or st.index != 0:
			return
		at = make_input_local(st).position
	else:
		return
	var hit = under(at)
	if hit == null:
		return
	selected = hit
	follower_clicked.emit(hit)
	get_viewport().set_input_as_handled()


## A struck exclamation on the same dark disc the job badge uses. Drawn from
## polygons rather than typed as a character -- the default font has no emoji
## and renders one as a hollow box, which is the note at the top of this file.
func _wonder(at: Vector2) -> void:
	var beat: float = 1.0 + 0.10 * _beat() 		* sin(float(Time.get_ticks_msec()) * 0.010)
	var c := at + Vector2(0, -20)
	draw_circle(c, 12.0 * beat, Color(0.08, 0.09, 0.12, 0.72))
	draw_arc(c, 12.0 * beat, 0.0, TAU, 20, Color(0.99, 0.84, 0.40, 0.55),
			 1.5, true)
	var g := Color(0.99, 0.90, 0.55)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-1.6, -6.5), c + Vector2(1.6, -6.5),
		c + Vector2(1.0, 1.5), c + Vector2(-1.0, 1.5)]), g)
	draw_circle(c + Vector2(0, 4.6), 1.7, g)


## A thought bubble with what they want in it.
##
## The icon IS the message -- an apple means hungry -- because the player is
## meant to be looking at the village rather than reading it. Urgency is a
## faster pulse and a warmer rim, not a second icon and not a number, so a
## screenful of these still reads at a glance.
## A PRAYER HAS TO CARRY ACROSS THE WHOLE ISLAND.
##
## This was 13 px of near-black disc with a pale grey rim. Photographed at the
## default camera distance with two villagers genuinely praying, it was two
## specks of grey on grey -- present, correct, and completely invisible. The
## guilt mark next door has always been hot orange and pulsing for exactly this
## reason and nobody carried that lesson across.
##
## Bigger, warm, and with a halo behind it so it is never read against the
## terrain -- a mark whose legibility depends on what it happens to be standing
## on is a mark that disappears over the ploughed field.
const PRAY_R := 19.0
const PRAY_WARM := Color(0.99, 0.84, 0.44)
const PRAY_HOT := Color(0.99, 0.55, 0.30)


func _prayer(at: Vector2, pr) -> void:
	var speed: float = 0.011 if pr.urgent else 0.005
	var beat: float = 1.0 + (0.13 if pr.urgent else 0.06) * _beat() 		* sin(float(Time.get_ticks_msec()) * speed)
	var c := at + Vector2(0, -28)
	var rim: Color = PRAY_HOT if pr.urgent else PRAY_WARM
	var r: float = PRAY_R * beat
	# The halo first: a soft wash of the rim colour that separates the whole
	# mark from whatever it is standing over.
	draw_circle(c, r + 5.0, Color(rim.r, rim.g, rim.b, 0.20))
	draw_circle(c, r, Color(0.08, 0.09, 0.12, 0.92))
	draw_arc(c, r, 0.0, TAU, 26, rim, 2.4, true)
	# The little tail, so it reads as a thought rather than a badge.
	draw_circle(at + Vector2(-1.0, -11.0), 3.4, Color(0.08, 0.09, 0.12, 0.92))
	Icons.draw_icon(self, pr.icon(), c, 22.0)


func _draw() -> void:
	if host == null or rig == null or rig.cam == null:
		return
	_feuds()
	for f in host.folk:
		if not is_instance_valid(f) or f.brain == null:
			continue
		var head: Vector3 = f.position + Vector3(0, HEAD_HEIGHT, 0)
		if rig.cam.is_position_behind(head):
			continue
		var p: Vector2 = rig.cam.unproject_position(head)

		# THE GROUND RING AND THE MOOD FACE COME FIRST, outside the chain.
		#
		# They used to sit at the BOTTOM of a chain of `continue`s, which meant
		# that tapping a villager who was praying, guilty, blessable or talking
		# gave no selection ring at their feet and no face -- the four states
		# where the player is most likely to be tapping somebody on purpose.
		# A ring on the ground cannot collide with a mark above a head, so it
		# should never have been in the chain at all.
		if highlight_all and f != hovered and f != selected:
			_ground_ring(f, false)
		if f == hovered or f == selected:
			_ground_ring(f, f == selected)
			_face(p, f.brain.mood_face(), f == selected)

		# THE PROPHET IS ALWAYS MARKED.
		#
		# Unlike the job badge below, which only appears on hover: the whole
		# point of a prophet is that you can lose one, and a person you cannot
		# pick out of a crowd is a person whose loss you will never notice.
		# Drawn as a ring above the head rather than a glyph on it, so it reads
		# at play distance and never fights the prayer bubble for the same spot.
		if host.divinity != null and host.divinity.prophet != null 				and host.divinity.prophet.who == f:
			_halo(p)

		# A JOB BADGE, only while the player is already looking at this one --
		# permanently visible on forty followers would be forty small icons
		# competing with everything else on screen.
		if (f == hovered or f == selected or highlight_all) \
				and JOB_ICON.has(f.brain.job):
			# On a dark disc, and bigger: a 14 px glyph drawn straight onto
			# bright grass was invisible at play distance, so the badge that
			# tells a miner from a bard told nobody anything.
			var badge := p + Vector2(15, -11)
			draw_circle(badge, 11.0, Color(0.08, 0.09, 0.12, 0.72))
			draw_arc(badge, 11.0, 0.0, TAU, 20, Color(1, 1, 1, 0.35), 1.5, true)
			Icons.draw_icon(self, String(JOB_ICON[f.brain.job]), badge, 17.0)

		# THE SPUR, beside the head rather than above it.
		#
		# A villager who is praying AND has an open witness window is the most
		# valuable target in the game -- the prayer pays, the blessing pays,
		# and the chain pays -- and the old chain hid that overlap by showing
		# whichever came first. The dial moves to its own anchor instead, a
		# little smaller and with no pulse, so only one thing on a given head
		# is ever moving. In a crowd of forty that is the whole difference
		# between readable and strobing.
		var spur := false
		if host.divinity != null:
			var window: float = host.divinity.witness_left(f)
			if window > 0.0 and _mark_taken(f):
				_blessable(p + Vector2(-17, 4), window, true)
				spur = true

		# WHAT SITS ABOVE THE HEAD, highest priority first. One only: two
		# glyphs in the same place is worse than the lower one being missed.
		# LOOKING UP, above everything: it is the shortest-lived mark there is.
		if _looking.has(f.get_instance_id()):
			if float(_looking[f.get_instance_id()]) > float(host.village.now):
				_wonder(p)
				continue
			_looking.erase(f.get_instance_id())

		# ASKING. Above guilt because a prayer is the thing the player is meant
		# to act on and guilt is the thing they may ignore, and because a prayer
		# stands for a minute and a half where guilt is a few seconds.
		if host.prayers != null:
			var pr = host.prayers.of(f)
			if pr != null:
				_prayer(p, pr)
				continue

		if host.divinity != null and host.divinity._is_guilty(f):
			_guilt(p)
			continue
		# BLESSABLE, and how long is left of it.
		#
		# The mirror of the guilt mark, and it should have existed first: a
		# blessing only pays inside the witness window, so this ring IS the
		# mechanic. Drawn for everyone for the same reason guilt is -- a cue
		# you only see by hovering is a cue you never see -- and it depletes,
		# so the player learns the window's length by watching it close.
		if not spur and host.divinity != null:
			var left: float = host.divinity.witness_left(f)
			if left > 0.0:
				_blessable(p, left)
				continue
		if f.brain.chatting_with != "":
			_speech(p)

	_edges()


## Is something already claiming the space above this head?
##
## Kept beside the chain it mirrors: if a mark is added there and not here, the
## dial quietly starts drawing underneath it again.
func _mark_taken(f) -> bool:
	if _looking.has(f.get_instance_id()) 			and float(_looking[f.get_instance_id()]) > float(host.village.now):
		return true
	if host.prayers != null and host.prayers.of(f) != null:
		return true
	if host.divinity != null and host.divinity._is_guilty(f):
		return true
	return false


## DRAW THE ARGUMENT, not just the two people having it.
##
## Two prayer bubbles a few metres apart are two prayers. What makes a feud
## legible is the line between them: it says these are one thing, it says you
## cannot have both, and it says it before a word of text is read. Drawn under
## everything, so it never sits on top of the bubbles it is joining.
const FEUD_LINE := Color(0.97, 0.66, 0.36, 0.55)


func _feuds() -> void:
	if host.prayers == null:
		return
	var drawn: Dictionary = {}
	for pr in (host.prayers.active as Array):
		if not pr.feud() or pr.rival == null:
			continue
		# Once per pair, not once per end of it.
		if drawn.has(pr.rival.get_instance_id()):
			continue
		drawn[pr.get_instance_id()] = true
		var a = pr.who
		var b = pr.rival.who
		if not is_instance_valid(a) or not is_instance_valid(b):
			continue
		var ha: Vector3 = a.position + Vector3(0, HEAD_HEIGHT, 0)
		var hb: Vector3 = b.position + Vector3(0, HEAD_HEIGHT, 0)
		if rig.cam.is_position_behind(ha) or rig.cam.is_position_behind(hb):
			continue
		# THEY WALK. The pair are picked standing together, and nothing pins
		# them there -- one wanders off to eat and the line becomes a rope
		# stretched across the entire island, joining a villager on screen to
		# somebody the player cannot see. A line that long says nothing except
		# that the interface is confused.
		if a.position.distance_to(b.position) > Prayers.FEUD_NEAR * 1.6:
			continue
		var pa: Vector2 = rig.cam.unproject_position(ha) + Vector2(0, -22)
		var pb: Vector2 = rig.cam.unproject_position(hb) + Vector2(0, -22)
		# And both ends have to be on screen, or it is an arrow pointing off
		# the edge that never says what it is pointing at.
		var view := Rect2(Vector2.ZERO, get_viewport_rect().size)
		if not view.has_point(pa) or not view.has_point(pb):
			continue
		draw_line(pa, pb, FEUD_LINE, 2.0, true)
		# A break in the middle, because the point of the line is that it does
		# not join up.
		var mid: Vector2 = (pa + pb) * 0.5
		draw_circle(mid, 7.0, Color(0.08, 0.09, 0.12, 0.85))
		draw_arc(mid, 7.0, 0.0, TAU, 16, FEUD_LINE, 1.6, true)


## POINT AT THE DISASTER THE PLAYER CANNOT SEE.
##
## A fire has sixty seconds and a specific answer, and both of those are wasted
## if it starts on the far side of the island while the camera is somewhere
## else. The player was told "Fire in the trees." and given no way at all to
## find WHICH trees -- the honest version of that message is an arrow.
##
## Only for what is off screen. An on-screen fire is already pointing at itself
## in orange, and a marker on top of it would be the interface explaining
## something the world had already said.
## BIG ENOUGH TO FIND WITHOUT LOOKING FOR IT. The first version was a 15 px
## chevron sitting 44 px in, and in a screenshot it read as a speck of dirt on
## the grass -- which is a marker that costs a draw call and saves nobody.
const EDGE_INSET := 54.0           ## how far in from the frame the arrow sits
const EDGE_R := 22.0

const TINTS := {
	"ember": Color(0.98, 0.48, 0.22),
	"sand": Color(0.92, 0.79, 0.42),
	"slate": Color(0.66, 0.72, 0.82),
}


func _edges() -> void:
	if host.grid == null:
		return
	# THE VIEWPORT RECT, NOT `size`: this Control's own size is (0, 0) until the
	# parent notifies a resize, and a zero frame contains no point at all -- so
	# every calamity counted as off-screen and its arrow was drawn around the
	# top-left corner. The camera unprojects into the viewport, so this is the
	# same space the projected point is already in.
	var screen: Vector2 = get_viewport_rect().size
	var frame := Rect2(Vector2(EDGE_INSET, EDGE_INSET),
					   screen - Vector2(EDGE_INSET, EDGE_INSET) * 2.0)
	if frame.size.x <= 0.0 or frame.size.y <= 0.0:
		return
	# SOMEBODY ASKING FROM OFF SCREEN, for the same reason a fire off screen
	# gets one: a prayer stands for a median of twelve seconds, and twelve
	# seconds is not long enough to find somebody by panning at random.
	if host.prayers != null:
		for pr in (host.prayers.active as Array):
			if not is_instance_valid(pr.who):
				continue
			_point_at(pr.who.position + Vector3(0, 1.2, 0), frame, screen,
					  PRAY_HOT if pr.urgent else PRAY_WARM)

	if host.get("calamities") == null:
		return
	for c in (host.calamities as Array):
		_point_at(host.grid.world_of(c.cell) + Vector3(0, 0.8, 0), frame,
				  screen, TINTS.get(String(c.look().get("tint", "ember")),
									TINTS["ember"]))


## One arrow at the frame edge, if this world point is not already on screen.
##
## Shared by the fires and the prayers rather than written twice, because the
## awkward half is the same for both: a point BEHIND the camera unprojects to a
## mirrored position, which would send the arrow to the opposite edge from the
## thing it is pointing at. Flipping the direction around the screen centre puts
## it back on the side the thing is actually on.
func _point_at(at: Vector3, frame: Rect2, screen: Vector2, tint: Color) -> void:
	var behind: bool = rig.cam.is_position_behind(at)
	var p: Vector2 = rig.cam.unproject_position(at)
	if not behind and frame.has_point(p):
		return
	var mid: Vector2 = screen * 0.5
	var dir: Vector2 = (mid - p) if behind else (p - mid)
	if dir.length() < 0.001:
		return
	_arrow(mid + dir.normalized() * _reach(dir.normalized(), frame),
		   dir.angle(), tint)


## How far from the centre the frame is, in this direction.
func _reach(d: Vector2, frame: Rect2) -> float:
	var half: Vector2 = frame.size * 0.5
	var tx: float = 1e9 if absf(d.x) < 0.001 else half.x / absf(d.x)
	var ty: float = 1e9 if absf(d.y) < 0.001 else half.y / absf(d.y)
	return minf(tx, ty)


func _arrow(at: Vector2, angle: float, tint: Color) -> void:
	var pulse: float = 1.0 		+ sin(float(Time.get_ticks_msec()) * 0.005) * 0.12 * _beat()
	var r: float = EDGE_R * pulse
	draw_circle(at, r + 3.0, Color(0.06, 0.07, 0.10, 0.70))
	var tip: Vector2 = at + Vector2(r, 0).rotated(angle)
	var a: Vector2 = at + Vector2(-r * 0.55, -r * 0.72).rotated(angle)
	var b: Vector2 = at + Vector2(-r * 0.55, r * 0.72).rotated(angle)
	draw_colored_polygon(PackedVector2Array([tip, a, b]), tint)
	draw_arc(at, r + 3.0, 0.0, TAU, 22, Color(tint.r, tint.g, tint.b, 0.45),
			 1.5, true)


## The mark of the one who speaks for you.
const HALO := Color(0.99, 0.86, 0.48)


func _halo(p: Vector2) -> void:
	var t := float(Time.get_ticks_msec()) * 0.0022
	var c := p + Vector2(0, -30.0 - sin(t) * 1.6 * _beat())
	# An open ring, tilted, so it reads as sitting above them rather than as
	# another badge stuck to them.
	draw_arc(c, 10.0, 0.0, TAU, 24, Color(0.06, 0.07, 0.10, 0.55), 4.0, true)
	draw_arc(c, 10.0, 0.0, TAU, 24, HALO, 2.0, true)


## A hot mark over a wrongdoer, pulsing so the eye finds it in a crowd.
func _guilt(p: Vector2) -> void:
	var t := float(Time.get_ticks_msec()) * 0.006
	var pulse := 1.0 + sin(t) * 0.14 * _beat()
	var r := 11.0 * pulse
	var hot := Color(1.0, 0.35, 0.28)
	draw_circle(p + Vector2(0, -2), r + 3.0, Color(0.10, 0.02, 0.02, 0.55))
	draw_circle(p + Vector2(0, -2), r, hot)
	# A bolt, the same glyph the punish button uses, so the two read as one
	# idea: this is the thing that button is for.
	var c := p + Vector2(0, -2)
	var pts := PackedVector2Array([
		c + Vector2(-1.0, -6.5) * pulse, c + Vector2(3.2, -1.2) * pulse,
		c + Vector2(0.4, -1.2) * pulse, c + Vector2(1.6, 6.5) * pulse,
		c + Vector2(-2.8, 0.6) * pulse, c + Vector2(0.0, 0.6) * pulse])
	draw_colored_polygon(pts, Color(0.16, 0.05, 0.05))


## A gold ring that empties over the witness window: they just finished a job
## and a blessing lands NOW.
##
## An arc rather than a filled disc so it reads as a clock, and quieter than
## the guilt bolt on purpose -- guilt is a demand, this is an opportunity.
## `quiet` is the SPUR form: smaller and dimmer, for when this is the second
## mark on a head and something louder already owns the space above it.
func _blessable(p: Vector2, left: float, quiet := false) -> void:
	var c := p + Vector2(0, -2)
	var r := 7.0 if quiet else 10.0
	var gold := Color(1.0, 0.84, 0.36)
	if quiet:
		gold.a = 0.72
	draw_circle(c, r + 2.0, Color(0.12, 0.09, 0.02, 0.42))
	# The remaining arc, wound clockwise from the top so it closes like a dial.
	var start := -PI * 0.5
	draw_arc(c, r, start, start + TAU * left, 24, gold, 2.6, true)
	# A small solid core, so a nearly-expired window is still findable.
	draw_circle(c, 3.2, gold.lerp(Color(1, 1, 1), 0.35))


## A ring on the ground at the villager's feet, projected from four points of
## a circle in WORLD space so it sits flat in perspective. A screen-space
## circle under the feet reads as a sticker on the lens.
func _ground_ring(f, strong: bool) -> void:
	var pts := PackedVector2Array()
	var r := 0.34
	for i in 20:
		var a := TAU * float(i) / 20.0
		var w: Vector3 = f.position + Vector3(cos(a) * r, 0.03, sin(a) * r)
		if rig.cam.is_position_behind(w):
			return
		pts.append(rig.cam.unproject_position(w))
	pts.append(pts[0])
	draw_polyline(pts, Color(1, 1, 1, 0.85 if strong else 0.45),
				  2.5 if strong else 1.8)


func _face(at: Vector2, kind: String, ring: bool) -> void:
	var r := 13.0
	var tint := FLAT
	match kind:
		"happy": tint = HAPPY
		"sad": tint = SAD
	draw_circle(at, r + 2.0, Color(0, 0, 0, 0.28))
	draw_circle(at, r, tint)
	if ring:
		draw_arc(at, r + 4.0, 0.0, TAU, 28, Color(1, 1, 1, 0.85), 2.0)

	var eye := Vector2(4.6, -3.4)
	draw_circle(at + Vector2(-eye.x, eye.y), 1.9, INK)
	draw_circle(at + Vector2(eye.x, eye.y), 1.9, INK)

	# The mouth carries the whole reading, so it is three distinct shapes
	# rather than one arc with a changing sign -- a flat mouth drawn as a very
	# shallow curve reads as "slightly happy", which is a different answer.
	match kind:
		"happy":
			draw_arc(at + Vector2(0, -1.0), 6.4, deg_to_rad(25),
					 deg_to_rad(155), 18, INK, 2.0)
		"sad":
			draw_arc(at + Vector2(0, 7.0), 6.4, deg_to_rad(205),
					 deg_to_rad(335), 18, INK, 2.0)
		_:
			draw_line(at + Vector2(-5.0, 3.4), at + Vector2(5.0, 3.4), INK, 2.0)


## A little rounded bubble with three dots: the "they are talking" tell the
## design asks for (item 15).
func _speech(at: Vector2) -> void:
	var w := 26.0
	var h := 17.0
	var box := Rect2(at.x - w * 0.5, at.y - h - 6.0, w, h)
	draw_rect(Rect2(box.position + Vector2(0, 2), box.size),
			  Color(0, 0, 0, 0.25), true)
	draw_rect(box, BUBBLE, true)
	# Tail.
	var tip := Vector2(at.x, at.y + 2.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(at.x - 4.0, box.position.y + h),
		Vector2(at.x + 4.0, box.position.y + h), tip]), BUBBLE)
	for i in 3:
		draw_circle(Vector2(box.position.x + 7.0 + i * 6.0,
							box.position.y + h * 0.5), 1.7, INK)
