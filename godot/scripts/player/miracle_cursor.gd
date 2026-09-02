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

signal finished(id: String, touched: int, gain: float)

## How long you hold a miracle before it burns out.
const SECONDS := 7.0
## How fast a need refills while under the effect, per second.
const RATE := 0.55
## How often, in seconds, a growing miracle drops something along the path.
const SOW_EVERY := 0.26
## How high the cloud floats above the ground it is affecting.
const HEIGHT := 2.6

var host = null                          ## ValeRoot
var divinity = null

var id := ""
var left := 0.0
var radius := 4.5
var _sow := 0.0
var _touched_folk: Dictionary = {}       ## instance id -> true, paid once each
var _touched_cells: Dictionary = {}
var _gain := 0.0
var _cloud: Node3D = null
var _rng := RandomNumberGenerator.new()

## Colour and behaviour per card. `grows` is what it plants as it passes.
const LOOK := {
	"rain":     {"tint": Color(0.55, 0.70, 0.92), "fx": "grow",
				 "grows": "Nature/tall_grass"},
	"grove":    {"tint": Color(0.35, 0.68, 0.36), "fx": "grow",
				 "grows": "Nature/tree"},
	"bounty":   {"tint": Color(0.90, 0.76, 0.36), "fx": "grow",
				 "grows": "Nature/crop_row"},
	"feast":    {"tint": Color(0.93, 0.55, 0.35), "fx": "grow",
				 "grows": "Nature/apples"},
	"revel":    {"tint": Color(0.88, 0.48, 0.78), "fx": "cheer",
				 "grows": "Nature/flowers"},
	"mend":     {"tint": Color(0.55, 0.88, 0.72), "fx": "bless", "grows": ""},
	"calm":     {"tint": Color(0.62, 0.72, 0.90), "fx": "bless", "grows": ""},
	"upheaval": {"tint": Color(0.62, 0.58, 0.54), "fx": "wrath",
				 "grows": "Nature/rock"},
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
	_touched_folk.clear()
	_touched_cells.clear()
	_gain = 0.0
	_build_cloud()
	visible = true
	set_process(true)


func is_active() -> bool:
	return left > 0.0 and id != ""


## Cut it short -- the player clicked to let go, or something cancelled it.
func release() -> void:
	if is_active():
		_end()


## The cloud is BUILT rather than loaded: a few squashed spheres, tinted per
## card, reads as "the miracle is here" from thirty metres up and costs no
## asset, no import and no download.
func _build_cloud() -> void:
	if _cloud != null and is_instance_valid(_cloud):
		_cloud.queue_free()
	_cloud = Node3D.new()
	add_child(_cloud)
	var spec: Dictionary = LOOK.get(id, {})
	var tint: Color = spec.get("tint", Color.WHITE)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 0.4
	for i in 7:
		var puff := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = _rng.randf_range(0.5, 0.95) * (radius / 4.5)
		sphere.height = sphere.radius * 1.25
		puff.mesh = sphere
		puff.material_override = mat
		var a := TAU * float(i) / 7.0
		puff.position = Vector3(cos(a) * radius * 0.40,
								_rng.randf_range(-0.10, 0.22),
								sin(a) * radius * 0.40)
		_cloud.add_child(puff)


func _process(delta: float) -> void:
	if not is_active():
		return
	# FOLLOW THE CURSOR. The ground point under the mouse is the same query the
	# camera uses to drag the map, so the cloud sits where the player is
	# pointing at any zoom and at any camera angle.
	if host != null and host.rig != null:
		var hit: Variant = host.rig.ground_at(
			host.rig.get_viewport().get_mouse_position())
		if hit != null:
			position = (hit as Vector3) + Vector3(0, HEIGHT, 0)

	if _cloud != null and is_instance_valid(_cloud):
		_cloud.rotation.y += delta * 0.6

	left -= delta
	_apply(delta)
	if left <= 0.0:
		_end()


func _apply(delta: float) -> void:
	var ground := position - Vector3(0, HEIGHT, 0)
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
	b.stats["faith"] = minf(1.0, float(b.stats["faith"]) + 0.35)
	b.memories.add(Memories.KIND_MIRACLE, "The sky opened over me.", 0.7, "",
				   1.0 + b.personality.devotion)
	var gain: float = divinity.boons.card_kick() * 0.55
	_gain += gain
	divinity.add_faith(gain)
	divinity.earned.emit(gain, f.position + Vector3(0, 0.9, 0), "miracle")


## Drop something on open ground under the cloud, at most once per cell.
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
	var spec: Dictionary = LOOK.get(id, {})
	if host != null and host.fxe != null:
		host.fxe.burst(String(spec.get("fx", "bless")),
					   position - Vector3(0, 2.0, 0), 1.0)
	var was := id
	id = ""
	left = 0.0
	visible = false
	set_process(false)
	if _cloud != null and is_instance_valid(_cloud):
		_cloud.queue_free()
		_cloud = null
	finished.emit(was, n, _gain)
