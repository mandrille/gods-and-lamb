extends Node3D
class_name MiracleCursor

## A miracle you HOLD, rather than one you drop.
##
## Cards used to be aimed once and resolved in a single instant: click a place,
## every effect lands, done. Which meant position was a formality -- the payout
## was the same wherever you clicked, so there was no reason to look at the
## village while casting.
##
## Now a card becomes a thing in your hand. Rain is a cloud that follows the
## cursor and rains on what is under it; a grove plants itself along the path
## you walk it. Nothing is affected until you actually pass over it, and each
## soul and each patch of ground pays out ONCE, the first time you touch it.
## So a good cast is a swept path across the people who need it, and a lazy one
## parked over an empty field earns almost nothing.
##
## Effects are per-second RATES rather than the old one-shot amounts, because a
## sweep that lingers should do more than a sweep that passes.
##
## EVERY CARD HAS ITS OWN EFFIGY. A first version drew every miracle as the
## same handful of spheres in a different tint, and it read as "a blob" no
## matter what was actually being cast. The rule below is the same one
## fx_events.gd states for particles -- shape and motion carry the idea,
## colour is the last thing anyone notices -- applied to the thing riding the
## cursor: rain is a real cloud with a flattened belly, grove is a tree taller
## than anything in the village, bounty and feast are a tipped basket of
## wheat or fruit, revel is a spinning firework, mend a breathing halo, calm a
## still orb at the centre of its own ripples, upheaval a hard-edged floating
## rock among an otherwise round and organic cast.

signal finished(id: String, touched: int, gain: float)

## How long you hold a miracle before it burns out.
const SECONDS := 7.0
## How fast a need refills while under the effect, per second.
const RATE := 0.55
## How often, in seconds, a growing miracle drops something along the path.
const SOW_EVERY := 0.26
## How high the cursor floats above the ground it is affecting.
const HEIGHT := 2.6
## How often the held miracle throws its OWN particle trail -- rain actually
## raining, leaves actually falling from the tree, grain actually spilling
## from the basket -- while it is out. Independent of SOW_EVERY, which plants
## props; this is purely what the player sees happening every frame.
const TRAIL_EVERY := 0.40

var host = null                          ## ValeRoot
var divinity = null

var id := ""
var left := 0.0
var radius := 4.5
var _sow := 0.0
var _trail := 0.0
var _touched_folk: Dictionary = {}       ## instance id -> true, paid once each
var _touched_cells: Dictionary = {}
var _gain := 0.0
var _cloud: Node3D = null
var _rng := RandomNumberGenerator.new()
var _bob := 0.0

## Per-effigy idle motion, set by whichever _build_* function runs and reset
## before each one. Rather than one hardcoded "spin on Y" for every shape --
## a tree does not spin, it sways; a firework should spin far harder than a
## still, calm orb.
var _sway := false
var _spin_axis := Vector3.UP
var _spin_rate := 0.6
## An optional extra part that gets its OWN independent motion on top of the
## shared one: revel's ring of coloured facets spins much faster than the
## rest of the shape, mend's halo turns steadily around a breathing core.
var _orbit: Node3D = null
## An optional part that breathes -- scales gently in and out -- for a shape
## whose life is in staying still and pulsing rather than spinning.
var _pulse: MeshInstance3D = null

## TEST HOOK ONLY. The probe window runs parked off-screen and unfocused (see
## tools/shot_window.gd) specifically so an automated run never steals the
## user's real cursor -- which also means nothing can warp it there to test
## against. Setting this makes _process() read a fixed point instead of the
## real mouse, so tools/miracle_probe.gd can exercise the ACTUAL _process ->
## ground_at -> global_position chain rather than only the payout math in
## _apply(). Left at (-1, -1), which never happens on a real screen, it is a
## no-op.
var _pointer_override := Vector2(-1, -1)


func _pointer_screen_pos() -> Vector2:
	if _pointer_override.x >= 0.0:
		return _pointer_override
	return host.rig.get_viewport().get_mouse_position()


## What the world does while this card is held. `tint` colours the duration
## bar and the ground ring (see MiracleGauge); `grows` is what it plants as
## it passes. The particle trail and the landing burst are NOT listed here --
## both now go through FXEvents.miracle(id, ...), which already carries its
## own id -> particle-kind table (FOR_MIRACLE) built for exactly this. A
## SEPARATE "fx" field used to live on each entry here, naming kinds ("grow",
## "cheer") that do not exist anywhere in FXEvents.KINDS -- every held miracle
## has been landing in total silence, because FXEvents.burst() quietly no-ops
## when the kind is not in its pool. Routing through the table that was
## already built for this, rather than a second one invented beside it, is
## the actual fix.
const LOOK := {
	"rain":     {"tint": Color(0.55, 0.70, 0.92), "grows": "Nature/tall_grass"},
	"grove":    {"tint": Color(0.35, 0.68, 0.36), "grows": "Nature/tree"},
	"bounty":   {"tint": Color(0.90, 0.76, 0.36), "grows": "Nature/crop_row"},
	"feast":    {"tint": Color(0.93, 0.55, 0.35), "grows": "Nature/apples"},
	"revel":    {"tint": Color(0.88, 0.48, 0.78), "grows": "Nature/flowers"},
	"mend":     {"tint": Color(0.55, 0.88, 0.72), "grows": ""},
	"calm":     {"tint": Color(0.62, 0.72, 0.90), "grows": ""},
	"upheaval": {"tint": Color(0.62, 0.58, 0.54), "grows": "Nature/rock"},
}


static func handles(card_id: String) -> bool:
	return LOOK.has(card_id)


func _ready() -> void:
	_rng.randomize()
	set_process(false)
	visible = false


func begin(card_id: String, r: float) -> void:
	id = card_id
	radius = r
	left = SECONDS
	_sow = 0.0
	_trail = 0.0             # the first burst of the trail fires almost at once
	_touched_folk.clear()
	_touched_cells.clear()
	_gain = 0.0
	_build_cloud()
	visible = true
	set_process(true)


func is_active() -> bool:
	return left > 0.0 and id != ""


## 1.0 at the moment it is picked up, 0.0 the instant it burns out. What a
## duration bar over the cursor is FOR.
func time_left_ratio() -> float:
	if id == "":
		return 0.0
	return clampf(left / SECONDS, 0.0, 1.0)


## Cut it short -- the player clicked to let go, or something cancelled it.
func release() -> void:
	if is_active():
		_end()


## --- the effigy --------------------------------------------------------------

func _build_cloud() -> void:
	if _cloud != null and is_instance_valid(_cloud):
		_cloud.queue_free()
	_cloud = Node3D.new()
	add_child(_cloud)
	_orbit = null
	_pulse = null
	_sway = false
	_spin_axis = Vector3.UP
	_spin_rate = 0.6

	var sc := radius / 4.5
	match id:
		"rain":
			_build_rain(sc)
		"grove":
			_build_grove(sc)
		"bounty":
			_build_bounty(sc)
		"feast":
			_build_feast(sc)
		"revel":
			_build_revel(sc)
		"mend":
			_build_mend(sc)
		"calm":
			_build_calm(sc)
		"upheaval":
			_build_upheaval(sc)
		_:
			# Safety net for a card that gets added before it has its own
			# effigy -- a plain bright cloud, not a crash.
			_build_rain(sc)


## One mesh, one colour, one child of `_cloud` (or `parent`, when a shape
## needs an inner node it can spin independently -- see revel). Every bespoke
## effigy below is composed from a handful of these, which is what "no asset,
## no import, no download" means for a cursor effect: nothing here is loaded
## from disk, it is built from Godot's own primitive meshes.
func _part(mesh: Mesh, pos: Vector3, color: Color, rot_deg := Vector3.ZERO,
		  scale_v := Vector3.ONE, energy := 0.0,
		  parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if energy > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = energy
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scale_v
	(parent if parent != null else _cloud).add_child(mi)
	return mi


func _sphere(sphere_radius: float, seg: int, rings: int) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = sphere_radius
	m.height = sphere_radius * 2.0
	m.radial_segments = seg
	m.rings = rings
	return m


## RAIN. A real cloud -- flat-bellied, brighter on top where the light
## catches it, a darker grey-blue underside where the rain is about to fall.
func _build_rain(sc: float) -> void:
	var top := Color(0.90, 0.94, 1.0)
	var belly := Color(0.52, 0.60, 0.72)
	_part(_sphere(1.15 * sc, 12, 6), Vector3(0, -0.15 * sc, 0), belly,
		  Vector3.ZERO, Vector3(1.0, 0.55, 1.0), 0.30)
	for i in 6:
		var r := _rng.randf_range(0.55, 0.85) * sc
		var a := TAU * float(i) / 6.0
		_part(_sphere(r, 10, 6),
			  Vector3(cos(a) * 0.75 * sc,
					  0.30 * sc + _rng.randf_range(-0.05, 0.10) * sc,
					  sin(a) * 0.75 * sc),
			  top, Vector3.ZERO, Vector3.ONE, 0.55)
	_spin_rate = 0.35


## GROVE. A magnificently oversized tree -- taller than anything already
## standing in the village, so dragging it across the map reads as carrying
## an act of creation, not a gardening tool. Sways rather than spins.
##
## A first pass placed the lobes too close together and too small: from the
## game's steep, oblique camera it read as one smooth ball on a stick, no
## different in size from an ordinary prop tree. FIVE lobes now, pushed
## further out in every direction (not just left-right, which this camera
## angle mostly hides), on a taller trunk, with more value contrast between
## them so the lobing reads through shading even where the silhouettes touch.
func _build_grove(sc: float) -> void:
	var bark := Color(0.34, 0.22, 0.13)
	var canopy_deep := Color(0.16, 0.42, 0.16)
	var canopy_mid := Color(0.26, 0.56, 0.24)
	var canopy_light := Color(0.50, 0.80, 0.36)

	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.15 * sc
	trunk.bottom_radius = 0.24 * sc
	trunk.height = 1.75 * sc
	trunk.radial_segments = 8
	_part(trunk, Vector3(0, 0.88 * sc, 0), bark)

	# The core mass, then four lobes thrown well clear of it -- left, right,
	# forward and back -- so at least three are always visible as distinct
	# bumps no matter which way the tree is facing as it sways.
	_part(_sphere(1.10 * sc, 10, 7), Vector3(0, 2.10 * sc, 0), canopy_mid)
	_part(_sphere(0.78 * sc, 8, 6), Vector3(-0.95 * sc, 1.75 * sc, 0.30 * sc),
		  canopy_deep)
	_part(_sphere(0.78 * sc, 8, 6), Vector3(0.95 * sc, 1.75 * sc, -0.30 * sc),
		  canopy_deep)
	_part(_sphere(0.68 * sc, 8, 6), Vector3(0.15 * sc, 1.70 * sc, 0.95 * sc),
		  canopy_deep)
	_part(_sphere(0.62 * sc, 8, 6), Vector3(-0.20 * sc, 1.65 * sc, -0.90 * sc),
		  canopy_mid)
	_part(_sphere(0.60 * sc, 8, 6), Vector3(0, 2.85 * sc, 0), canopy_light,
		  Vector3.ZERO, Vector3.ONE, 0.18)

	_sway = true


## BOUNTY. A basket tipped forward, sheaves fanning out like a bouquet --
## "the granary fills" is a promise, and this is the shape of the promise
## rather than the granary itself.
func _build_bounty(sc: float) -> void:
	var wicker := Color(0.52, 0.34, 0.17)
	var gold := Color(0.88, 0.72, 0.26)
	var gold_bright := Color(0.96, 0.84, 0.40)

	var basket := CylinderMesh.new()
	basket.top_radius = 0.58 * sc
	basket.bottom_radius = 0.32 * sc
	basket.height = 0.58 * sc
	basket.radial_segments = 10
	var b := _part(basket, Vector3.ZERO, wicker)
	b.rotation_degrees = Vector3(18, 0, 0)

	# Fewer, fatter sheaves than the first pass. Thin cylinders (radius under
	# 6 cm) read fine up close but blur into one soft cone at the game's
	# default play distance -- five thick, well-separated spikes hold their
	# shape as recognisably "wheat" from thirty metres up, where seven thin
	# ones did not.
	for i in 5:
		var a := -50.0 + 100.0 * float(i) / 4.0
		var sheaf := CylinderMesh.new()
		sheaf.top_radius = 0.03 * sc
		sheaf.bottom_radius = 0.10 * sc
		sheaf.height = 0.85 * sc
		sheaf.radial_segments = 6
		var s := _part(sheaf,
			Vector3(sin(deg_to_rad(a)) * 0.28 * sc, 0.54 * sc,
					-cos(deg_to_rad(a)) * 0.08 * sc),
			gold if i % 2 == 0 else gold_bright)
		s.rotation_degrees = Vector3(-58, a, 0)

	for i in 5:
		_part(_sphere(0.055 * sc, 6, 4),
			  Vector3(_rng.randf_range(-0.4, 0.4) * sc,
					  0.18 * sc + _rng.randf_range(-0.05, 0.10) * sc,
					  _rng.randf_range(-0.05, 0.35) * sc),
			  gold_bright, Vector3.ZERO, Vector3.ONE, 0.2)

	_spin_rate = 0.25


## FEAST. The same basket family as Bounty -- both are "abundance" cards --
## heaped instead with fruit, so the two read as siblings rather than
## unrelated ideas that happen to share a colour palette.
func _build_feast(sc: float) -> void:
	var wood := Color(0.46, 0.28, 0.15)
	var red_a := Color(0.78, 0.18, 0.16)
	var red_b := Color(0.86, 0.30, 0.20)
	var citrus := Color(0.90, 0.55, 0.14)
	var gold := Color(0.92, 0.74, 0.20)

	var basket := CylinderMesh.new()
	basket.top_radius = 0.62 * sc
	basket.bottom_radius = 0.38 * sc
	basket.height = 0.55 * sc
	basket.radial_segments = 10
	_part(basket, Vector3.ZERO, wood)

	var spots: Array[Vector3] = [
		Vector3(0, 0.55, 0), Vector3(0.32, 0.45, 0.20),
		Vector3(-0.32, 0.45, -0.15), Vector3(0.10, 0.78, -0.20),
		Vector3(-0.22, 0.72, 0.18), Vector3(0.30, 0.40, -0.32),
	]
	var cols := [red_a, citrus, gold, red_b, citrus, red_a]
	for i in spots.size():
		var r := 0.24 * sc * _rng.randf_range(0.9, 1.15)
		_part(_sphere(r, 8, 6), spots[i] * sc, cols[i])

	_spin_rate = 0.3


## REVEL. A little firework held in mid-burst: a bright emissive core with
## six coloured facets flung out on a ring that spins far harder than
## anything else on this list -- built under `_orbit` so it can be spun
## independently of the shared idle motion.
func _build_revel(sc: float) -> void:
	_part(_sphere(0.32 * sc, 10, 6), Vector3.ZERO, Color(1.0, 0.94, 0.78),
		  Vector3.ZERO, Vector3.ONE, 1.3)

	var wrap := Node3D.new()
	_cloud.add_child(wrap)
	_orbit = wrap
	var hues := [Color(0.92, 0.24, 0.24), Color(0.96, 0.56, 0.16),
				 Color(0.96, 0.84, 0.20), Color(0.34, 0.78, 0.30),
				 Color(0.30, 0.56, 0.94), Color(0.68, 0.32, 0.86)]
	for i in hues.size():
		var a := TAU * float(i) / float(hues.size())
		var box := BoxMesh.new()
		box.size = Vector3.ONE * 0.20 * sc
		_part(box, Vector3(cos(a), 0, sin(a)) * 0.78 * sc, hues[i],
			  Vector3(30, rad_to_deg(a) * 1.3, 20), Vector3.ONE, 0.9, wrap)

	_spin_rate = 0.25


## MEND. A healing halo: a soft green core that BREATHES (`_pulse`), standing
## inside a slow steady ring -- the shape a KIND_MIRACLE memory of "I was made
## whole again" deserves.
func _build_mend(sc: float) -> void:
	_pulse = _part(_sphere(0.30 * sc, 10, 6), Vector3.ZERO,
				   Color(0.62, 0.95, 0.75), Vector3.ZERO, Vector3.ONE, 0.9)

	var ring := TorusMesh.new()
	ring.inner_radius = 0.58 * sc
	ring.outer_radius = 0.72 * sc
	ring.rings = 6
	ring.ring_segments = 16
	_orbit = _part(ring, Vector3(0, 0.05 * sc, 0), Color(0.95, 1.0, 0.97),
				   Vector3(90, 0, 0), Vector3.ONE, 0.5)

	_spin_rate = 0.5


## CALM. A still, pale orb -- just a breathing light, nothing thrown or
## spinning around it. A first version stood two flat rings around the core
## for a "ripple" silhouette, and from the game's shallow, oblique camera they
## collapsed into a solid plate under the sphere -- read as a flying saucer,
## not ripples. The actual rippling is left entirely to the 'calm' PARTICLE
## kind, which is already an expanding, fading ring (see FXEvents.KINDS) and
## is animated, where a static mesh ring could only ever fake it.
func _build_calm(sc: float) -> void:
	_pulse = _part(_sphere(0.40 * sc, 10, 7), Vector3.ZERO,
				   Color(0.86, 0.93, 1.0), Vector3.ZERO, Vector3.ONE, 0.6)

	_spin_rate = 0.12


## UPHEAVAL. A cluster of raw, hard-edged blocks -- every other effigy on this
## list is rounded and organic, so a jagged floating rock is the one shape
## here that could not be mistaken for anything else. Tumbles on an off-axis
## rather than spinning flat on Y, for the same reason.
func _build_upheaval(sc: float) -> void:
	var rock_dark := Color(0.34, 0.31, 0.29)
	var rock_mid := Color(0.46, 0.42, 0.38)
	var rock_light := Color(0.58, 0.53, 0.46)
	var chunks := [
		[Vector3(0, 0, 0), 0.62, rock_mid, Vector3(18, 30, 8)],
		[Vector3(0.35, 0.10, 0.15), 0.42, rock_light, Vector3(-15, 60, 25)],
		[Vector3(-0.30, -0.08, -0.20), 0.38, rock_dark, Vector3(30, -40, -10)],
		[Vector3(0.05, 0.30, -0.25), 0.30, rock_mid, Vector3(50, 15, 40)],
	]
	for c in chunks:
		var box := BoxMesh.new()
		box.size = Vector3.ONE * (float(c[1]) * sc)
		_part(box, (c[0] as Vector3) * sc, c[2], c[3])

	_spin_axis = Vector3(0.4, 1.0, 0.2).normalized()
	_spin_rate = 0.22


## --- moving, casting, ending -------------------------------------------------

func _process(delta: float) -> void:
	if not is_active():
		return
	# FOLLOW THE CURSOR. The ground point under the mouse is the same query the
	# camera uses to drag the map, so the effigy sits where the player is
	# pointing at any zoom and at any camera angle.
	if host != null and host.rig != null:
		var hit: Variant = host.rig.ground_at(_pointer_screen_pos())
		if hit != null:
			# GLOBAL, not local. `position` is relative to this node's
			# parent, and every effect below (folk distance, the plant point,
			# the burst on release) reasons in WORLD space -- writing through
			# `global_position` means the two can never quietly disagree about
			# where "here" is, even if a parent ever gains its own transform.
			global_position = (hit as Vector3) + Vector3(0, HEIGHT, 0)
		# If the ray misses (pointer off the map, or over sky at the edge of
		# the bounds) the effigy HOLDS where it last was rather than snapping
		# to the origin -- losing the ray for one frame should never look like
		# the miracle teleporting.

	_bob += delta
	if _cloud != null and is_instance_valid(_cloud):
		if _sway:
			_cloud.rotation.z = sin(_bob * 0.9) * 0.09
			_cloud.rotation.y = sin(_bob * 0.35) * 0.12
		else:
			_cloud.rotate(_spin_axis, delta * _spin_rate)
		_cloud.position.y = sin(_bob * 1.6) * 0.10
	if _orbit != null and is_instance_valid(_orbit):
		_orbit.rotation.y += delta * 3.2
	if _pulse != null and is_instance_valid(_pulse):
		var k := 1.0 + sin(_bob * 3.2) * 0.10
		_pulse.scale = Vector3.ONE * k

	# THE TRAIL. The particle language each card already speaks at the moment
	# it lands (FXEvents.FOR_MIRACLE) is the same one it speaks continuously
	# while it is held -- rain actually rains, leaves actually fall from the
	# tree, grain actually spills from the basket -- rather than a mesh that
	# sits there being looked at.
	_trail -= delta
	if _trail <= 0.0 and host != null and host.fxe != null:
		_trail = TRAIL_EVERY
		host.fxe.miracle(id, global_position - Vector3(0, HEIGHT, 0))

	left -= delta
	_apply(delta)
	if left <= 0.0:
		_end()


func _apply(delta: float) -> void:
	var ground := global_position - Vector3(0, HEIGHT, 0)
	for f in host.folk:
		if not is_instance_valid(f) or f.brain == null:
			continue
		if f.position.distance_to(ground) > radius:
			continue
		_touch_folk(f, delta)

	var grows := String((LOOK.get(id, {}) as Dictionary).get("grows", ""))
	if grows == "":
		return
	_sow -= delta
	if _sow > 0.0:
		return
	_sow = SOW_EVERY
	_plant(grows, ground)


func _touch_folk(f, delta: float) -> void:
	var b = f.brain
	match id:
		"rain":
			b.stats["hygiene"] = minf(1.0,
				float(b.stats["hygiene"]) + RATE * delta)
			b.stats["health"] = minf(1.0,
				float(b.stats["health"]) + RATE * 0.5 * delta)
		"feast":
			b.stats["hunger"] = minf(1.0,
				float(b.stats["hunger"]) + RATE * delta)
		"revel":
			b.stats["fun"] = minf(1.0, float(b.stats["fun"]) + RATE * delta)
			b.stats["social"] = minf(1.0,
				float(b.stats["social"]) + RATE * delta)
		"mend":
			b.stats["health"] = minf(1.0,
				float(b.stats["health"]) + RATE * delta)
			b.stats["energy"] = minf(1.0,
				float(b.stats["energy"]) + RATE * delta)
		"calm":
			# Cools grudges without erasing them. The memories are the record;
			# heat is only how much they still sting.
			for e in b.memories.entries:
				if float(e["valence"]) < 0.0:
					e["heat"] = float(e["heat"]) * (1.0 - 0.6 * delta)
		_:
			# Grove, bounty and upheaval change the LAND, not the people. They
			# still gladden anyone caught under them, so a cast through the
			# village is worth more than one out in the wilds.
			b.stats["fun"] = minf(1.0,
				float(b.stats["fun"]) + RATE * 0.3 * delta)

	# PAID ONCE EACH. Parking the cloud on one villager for seven seconds pays
	# for one villager; sweeping it across eight pays for eight. That is the
	# entire reason the miracle moves.
	var key: int = f.get_instance_id()
	if _touched_folk.has(key):
		return
	_touched_folk[key] = true
	b.gain_faith(1.2)          # a miracle passing over you is a small sermon
	b.memories.add(Memories.KIND_MIRACLE, "The sky opened over me.", 0.7, "",
				   1.0 + b.personality.devotion)
	var gain: float = divinity.boons.card_kick() * 0.55
	_gain += gain
	divinity.add_faith(gain)
	divinity.earned.emit(gain, f.position + Vector3(0, 0.9, 0), "miracle")


## Drop something on open ground under the effigy, at most once per cell.
func _plant(aid: String, ground: Vector3) -> void:
	var grid = host.grid
	if grid == null:
		return
	var centre: Vector2i = grid.cell_of(ground)
	var span := maxi(1, int(radius / maxf(grid.tile, 0.01) * 0.6))
	for attempt in 10:
		var c := centre + Vector2i(_rng.randi_range(-span, span),
								   _rng.randi_range(-span, span))
		if _touched_cells.has(c) or not grid.is_walkable(c):
			continue
		_touched_cells[c] = true
		if host.builder.add_prop(aid, c.x, c.y,
								 _rng.randf_range(0.0, 360.0)):
			host.queue_grid_rebuild()
			return


func _end() -> void:
	var n := _touched_folk.size() + _touched_cells.size()
	if host != null and host.fxe != null:
		host.fxe.miracle(id, global_position - Vector3(0, 2.0, 0))
	var was := id
	id = ""
	left = 0.0
	visible = false
	set_process(false)
	if _cloud != null and is_instance_valid(_cloud):
		_cloud.queue_free()
		_cloud = null
	finished.emit(was, n, _gain)
