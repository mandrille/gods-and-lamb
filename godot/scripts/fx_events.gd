extends Node3D
class_name FXEvents

## One-shot effects for things that HAPPEN.
##
## Separate from `fx.gd`, which owns the ambient layer -- chimney smoke, dust
## near the trees -- because the two have opposite shapes. Ambient FX are a
## fixed set of emitters that run forever and are tuned by density. These are
## transient, they happen at a point, and there may be several at once.
##
## EVERY EFFECT HAS ITS OWN SHAPE, not one puff recoloured. The first version
## was six entries that differed only in colour and speed, all drawn as the
## same camera-facing square, and it read as one effect playing over and over
## no matter what had actually happened. What tells a player that rain is rain
## and wrath is wrath is the MESH and the MOTION -- rain is thin vertical
## streaks falling through a wide volume, wrath is tumbling debris thrown
## outward under gravity, a blessing is motes drifting up. Colour is the last
## thing you notice, not the first.
##
## POOLED, and the pool is the whole design. Creating a GPUParticles3D per
## event allocates GPU buffers on the frame the player is watching. The other
## half of the same rule: vary `amount_ratio`, NEVER `amount` -- writing
## `amount` reallocates the particle buffer, the exact cost the pool avoids.

const POOL_PER_KIND := 3

## mesh:    quad | streak | chunk | pellet | ring
## shape:   point | box  (box is a volume -- weather, not an explosion)
## spin:    tumble rate, for anything that should not stay flat to camera
## drag:    damping, so confetti and leaves slow down and litter
const KINDS := {
	"bless": {
		"mesh": "quad", "size": Vector2(0.10, 0.10), "count": 40,
		"colour": Color(1.00, 0.88, 0.42), "add": true,
		"speed": [0.6, 1.4], "spread": 42.0, "up": 1.0, "gravity": -0.55,
		"life": 1.5, "drag": 0.8, "spin": 0.0, "shape": "point",
	},
	"punish": {
		# A streak, driven DOWN hard. Judgement arrives from above; the same
		# particles drifting up would read as a blessing in another colour.
		"mesh": "streak", "size": Vector2(0.05, 0.55), "count": 22,
		"colour": Color(0.92, 0.26, 0.30), "add": true,
		"speed": [5.0, 7.5], "spread": 9.0, "up": -1.0, "gravity": 7.0,
		"life": 0.55, "drag": 0.0, "spin": 0.0, "shape": "point",
	},
	"wrath": {
		# Tumbling chunks, thrown out and falling. Boxes, not billboards: the
		# whole point is that something SOLID came apart.
		"mesh": "chunk", "size": Vector2(0.11, 0.11), "count": 34,
		"colour": Color(0.52, 0.46, 0.42), "add": false,
		"speed": [2.4, 4.4], "spread": 78.0, "up": 0.55, "gravity": 6.5,
		"life": 1.5, "drag": 0.4, "spin": 7.0, "shape": "point",
	},
	"chips": {
		"mesh": "chunk", "size": Vector2(0.045, 0.045), "count": 16,
		"colour": Color(0.74, 0.55, 0.32), "add": false,
		"speed": [1.4, 2.6], "spread": 62.0, "up": 0.8, "gravity": 7.0,
		"life": 0.9, "drag": 0.3, "spin": 9.0, "shape": "point",
	},
	"grove": {
		# Leaves: broad, slow, high drag, tumbling. They should hang and
		# flutter, which is the opposite of every other effect here.
		"mesh": "quad", "size": Vector2(0.13, 0.09), "count": 34,
		"colour": Color(0.44, 0.82, 0.36), "add": false,
		"speed": [1.0, 2.0], "spread": 90.0, "up": 1.3, "gravity": 1.1,
		"life": 2.4, "drag": 2.4, "spin": 4.0, "shape": "point",
	},
	"rain": {
		# WEATHER, so it emits through a wide box overhead rather than from a
		# point. A rain burst that starts at one spot is a splash.
		"mesh": "streak", "size": Vector2(0.022, 0.42), "count": 220,
		"colour": Color(0.68, 0.86, 1.00), "add": true,
		"speed": [5.5, 7.0], "spread": 2.0, "up": -1.0, "gravity": 5.0,
		"life": 1.6, "drag": 0.0, "spin": 0.0, "shape": "box",
		"extents": Vector3(4.0, 0.3, 4.0), "lift": 4.5,
	},
	"feast": {
		# Fruit: round, heavy, thrown up and caught by gravity.
		"mesh": "pellet", "size": Vector2(0.10, 0.10), "count": 26,
		"colour": Color(0.88, 0.24, 0.22), "add": false,
		"speed": [2.6, 4.0], "spread": 55.0, "up": 1.0, "gravity": 6.0,
		"life": 1.7, "drag": 0.2, "spin": 5.0, "shape": "point",
	},
	"bounty": {
		"mesh": "quad", "size": Vector2(0.05, 0.11), "count": 40,
		"colour": Color(0.94, 0.79, 0.34), "add": false,
		"speed": [1.8, 3.2], "spread": 70.0, "up": 1.1, "gravity": 4.0,
		"life": 1.6, "drag": 1.0, "spin": 6.0, "shape": "point",
	},
	"mend": {
		"mesh": "quad", "size": Vector2(0.12, 0.12), "count": 30,
		"colour": Color(0.42, 0.95, 0.55), "add": true,
		"speed": [0.5, 1.1], "spread": 30.0, "up": 1.0, "gravity": -0.9,
		"life": 1.6, "drag": 1.2, "spin": 0.0, "shape": "point",
	},
	"revel": {
		# Confetti. Wide spread, high drag, fast tumble, and the one effect
		# that deliberately uses the whole colour wheel rather than a tint.
		"mesh": "quad", "size": Vector2(0.055, 0.09), "count": 60,
		"colour": Color(1, 1, 1), "add": false, "rainbow": true,
		"speed": [2.2, 4.2], "spread": 100.0, "up": 1.2, "gravity": 2.6,
		"life": 2.3, "drag": 2.0, "spin": 11.0, "shape": "point",
	},
	"calm": {
		# A slow expanding shell rather than a burst: nothing is thrown, the
		# effect simply passes over everyone.
		"mesh": "ring", "size": Vector2(0.5, 0.5), "count": 14,
		"colour": Color(0.72, 0.90, 1.00), "add": true,
		"speed": [1.6, 2.0], "spread": 180.0, "up": 0.0, "gravity": -0.2,
		"life": 2.0, "drag": 1.4, "spin": 0.0, "shape": "point",
	},
	"birth": {
		"mesh": "quad", "size": Vector2(0.10, 0.10), "count": 38,
		"colour": Color(1.0, 0.80, 0.86), "add": true,
		"speed": [0.8, 1.6], "spread": 50.0, "up": 1.2, "gravity": -1.0,
		"life": 1.8, "drag": 1.0, "spin": 0.0, "shape": "point",
	},
	"build": {
		"mesh": "chunk", "size": Vector2(0.07, 0.07), "count": 28,
		"colour": Color(0.80, 0.72, 0.58), "add": false,
		"speed": [1.2, 2.2], "spread": 85.0, "up": 0.9, "gravity": 5.0,
		"life": 1.1, "drag": 0.6, "spin": 7.0, "shape": "point",
	},
}

## Which effect a miracle plays. Kept here rather than in Divinity so the rules
## layer never names a particle system -- the headless probes run the whole
## simulation with no FX node at all.
const FOR_MIRACLE := {
	"grove": "grove", "bounty": "bounty", "rain": "rain", "feast": "feast",
	"mend": "mend", "fertility": "birth", "revel": "revel", "calm": "calm",
}

var _pool: Dictionary = {}
var _next: Dictionary = {}
var _meshes: Dictionary = {}
var _density := 1.0


func _ready() -> void:
	for kind in KINDS:
		var bucket: Array[GPUParticles3D] = []
		for i in POOL_PER_KIND:
			bucket.append(_make(String(kind)))
		_pool[kind] = bucket
		_next[kind] = 0


## One mesh per SHAPE, shared by every effect that uses it. Six identical
## quads would be six resources and six more state changes for nothing.
func _mesh_for(kind: String, size: Vector2) -> Mesh:
	var key := "%s:%.3f:%.3f" % [kind, size.x, size.y]
	if _meshes.has(key):
		return _meshes[key]
	var m: Mesh
	match kind:
		"chunk":
			var b := BoxMesh.new()
			b.size = Vector3(size.x, size.x, size.x)
			m = b
		"pellet":
			var sp := SphereMesh.new()
			sp.radius = size.x * 0.5
			sp.height = size.x
			# Coarse on purpose: these are 10 cm across on screen and a
			# smooth sphere is thirty times the triangles for no pixels.
			sp.radial_segments = 6
			sp.rings = 3
			m = sp
		"ring":
			var t := TorusMesh.new()
			t.inner_radius = size.x * 0.72
			t.outer_radius = size.x
			t.rings = 12
			t.ring_segments = 5
			m = t
		_:
			var q := QuadMesh.new()
			q.size = size
			m = q
	_meshes[key] = m
	return m


func _make(kind: String) -> GPUParticles3D:
	var spec: Dictionary = KINDS[kind]
	var shape := String(spec["mesh"])
	var p := GPUParticles3D.new()
	p.name = "FX_%s" % kind
	p.emitting = false
	p.one_shot = true
	# Weather trickles; everything else is a burst. A single explosiveness for
	# all of them made the rain arrive as one slab of water.
	p.explosiveness = 0.25 if String(spec["shape"]) == "box" else 0.9
	p.lifetime = float(spec["life"])
	p.amount = int(spec["count"])       ## set ONCE, never at play time
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.local_coords = false

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, float(spec["up"]), 0)
	mat.spread = float(spec["spread"])
	var speed: Array = spec["speed"]
	mat.initial_velocity_min = float(speed[0])
	mat.initial_velocity_max = float(speed[1])
	mat.gravity = Vector3(0, -float(spec["gravity"]), 0)
	mat.damping_min = float(spec["drag"]) * 0.5
	mat.damping_max = float(spec["drag"])
	mat.scale_min = 0.75
	mat.scale_max = 1.15
	var spin := float(spec["spin"])
	if spin > 0.0:
		# Tumble in 3D. A flat billboard cannot tumble, so anything with spin
		# is drawn as real geometry facing where it is going.
		mat.angular_velocity_min = -spin
		mat.angular_velocity_max = spin
	if String(spec["shape"]) == "box":
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		mat.emission_box_extents = spec.get("extents", Vector3.ONE)
	else:
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		mat.emission_sphere_radius = 0.2

	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	if bool(spec.get("rainbow", false)):
		# Confetti gets its colour from the particle ramp's HUE, which is the
		# only way to get many colours out of ONE emitter.
		ramp.add_point(0.34, Color(1.0, 0.45, 0.45, 1.0))
		ramp.add_point(0.67, Color(0.45, 0.7, 1.0, 1.0))
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	mat.color_ramp = tex
	p.process_material = mat

	var draw := StandardMaterial3D.new()
	draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if bool(spec["add"]) \
					  else BaseMaterial3D.BLEND_MODE_MIX
	# Only flat billboards face the camera. Anything with tumble is meant to
	# be seen turning, and billboarding it throws that away.
	if spin <= 0.0 and shape in ["quad", "streak"]:
		draw.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw.vertex_color_use_as_albedo = true
	var tint: Color = spec["colour"]
	tint.a = 0.85
	draw.albedo_color = tint
	draw.disable_receive_shadows = true
	draw.cull_mode = BaseMaterial3D.CULL_DISABLED
	p.draw_pass_1 = _mesh_for(shape, spec["size"])
	p.material_override = draw
	add_child(p)
	return p


## Fire one. Silently does nothing for an unknown kind rather than crashing:
## these are called from gameplay code on events, and a typo in an effect name
## must not take the game down mid-miracle.
func burst(kind: String, at: Vector3, scale_v := 1.0) -> void:
	if not _pool.has(kind) or _density <= 0.0:
		return
	var bucket: Array = _pool[kind]
	var i: int = int(_next[kind]) % bucket.size()
	_next[kind] = i + 1
	var p: GPUParticles3D = bucket[i]
	# Weather emits from a volume overhead, so it is placed above the point it
	# was aimed at rather than on it.
	p.global_position = at + Vector3(0, float(KINDS[kind].get("lift", 0.0)), 0)
	p.amount_ratio = clampf(_density * scale_v, 0.05, 1.0)
	p.restart()
	p.emitting = true


## The effect a miracle plays, by miracle id.
func miracle(id: String, at: Vector3) -> void:
	burst(String(FOR_MIRACLE.get(id, "bless")), at)


## A ring of bursts, for something that happens over an AREA rather than at a
## point. Cheaper and more legible than one enormous emitter, because the shape
## of the effect then matches the shape of the damage.
func ring(kind: String, at: Vector3, radius: float, points := 6) -> void:
	burst(kind, at, 1.0)
	for i in points:
		var a := TAU * float(i) / float(points)
		burst(kind, at + Vector3(cos(a), 0.0, sin(a)) * radius * 0.7, 0.6)


func set_density(scale_v: float) -> void:
	_density = clampf(scale_v, 0.0, 1.0)


func active_count() -> int:
	var n := 0
	for bucket in _pool.values():
		for p in bucket:
			if p.emitting:
				n += 1
	return n
