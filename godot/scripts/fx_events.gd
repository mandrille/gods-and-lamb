extends Node3D
class_name FXEvents

## One-shot effects for things that HAPPEN: a blessing, a punishment, wrath,
## a miracle, an axe hitting wood.
##
## Separate from `fx.gd`, which owns the ambient layer -- chimney smoke, dust
## near the trees -- because the two have opposite shapes. Ambient FX are a
## fixed set of emitters that run forever and are tuned by density. These are
## transient, they happen at a point, and there may be several at once.
##
## POOLED, and the pool is the whole design. Creating a GPUParticles3D per
## event allocates GPU buffers on the frame the player is watching, and freeing
## it does the same a second later; the pool pays that once at startup. The
## other half of the same rule: vary `amount_ratio`, NEVER `amount` -- writing
## `amount` reallocates the particle buffer, which is exactly the cost the pool
## exists to avoid.

const POOL_PER_KIND := 4
const LIFETIME := 1.1

## Each kind is a colour, a size, a speed and a direction. Kept as data rather
## than as five nearly-identical setup functions, so adding one is a line.
const KINDS := {
	"bless":   {"colour": Color(1.0, 0.90, 0.45), "count": 26, "speed": 1.7,
				"up": 1.0, "size": 0.055, "gravity": -0.5},
	"punish":  {"colour": Color(0.85, 0.25, 0.30), "count": 30, "speed": 2.3,
				"up": -0.4, "size": 0.060, "gravity": 3.0},
	"wrath":   {"colour": Color(0.55, 0.50, 0.46), "count": 46, "speed": 3.2,
				"up": 0.5, "size": 0.085, "gravity": 4.0},
	"miracle": {"colour": Color(0.72, 0.92, 1.0), "count": 34, "speed": 2.0,
				"up": 1.2, "size": 0.062, "gravity": -0.8},
	"chips":   {"colour": Color(0.72, 0.54, 0.32), "count": 14, "speed": 1.5,
				"up": 0.6, "size": 0.038, "gravity": 5.0},
	"grow":    {"colour": Color(0.45, 0.85, 0.42), "count": 28, "speed": 1.4,
				"up": 1.4, "size": 0.058, "gravity": -1.2},
}

var _pool: Dictionary = {}          ## kind -> Array[GPUParticles3D]
var _next: Dictionary = {}          ## kind -> round-robin index
var _mesh: QuadMesh
var _density := 1.0


func _ready() -> void:
	# One shared quad for every particle in the game. A mesh per kind would be
	# six identical resources and six more draw-call state changes.
	_mesh = QuadMesh.new()
	_mesh.size = Vector2.ONE
	for kind in KINDS:
		var bucket: Array[GPUParticles3D] = []
		for i in POOL_PER_KIND:
			bucket.append(_make(String(kind)))
		_pool[kind] = bucket
		_next[kind] = 0


func _make(kind: String) -> GPUParticles3D:
	var spec: Dictionary = KINDS[kind]
	var p := GPUParticles3D.new()
	p.name = "FX_%s" % kind
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.92          ## a burst, not a trickle
	p.lifetime = LIFETIME
	p.amount = int(spec["count"])   ## set ONCE, here, never at play time
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.local_coords = false

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, float(spec["up"]), 0)
	mat.spread = 55.0
	mat.initial_velocity_min = float(spec["speed"]) * 0.5
	mat.initial_velocity_max = float(spec["speed"])
	mat.gravity = Vector3(0, -float(spec["gravity"]), 0)
	mat.scale_min = float(spec["size"]) * 0.6
	mat.scale_max = float(spec["size"])
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.22
	# Fade out over life, so nothing ever pops off screen.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	mat.color_ramp = tex
	p.process_material = mat

	var draw := StandardMaterial3D.new()
	draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Additive for the bright, magical ones; mixed for anything meant to
	# read as MATTER -- dust and wood chips. Additive dust turns a
	# destruction effect into a white flare, which says the opposite of
	# what it should.
	var mixed: bool = kind in ["wrath", "chips"]
	draw.blend_mode = BaseMaterial3D.BLEND_MODE_MIX if mixed else BaseMaterial3D.BLEND_MODE_ADD
	draw.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw.vertex_color_use_as_albedo = true
	# Held below full alpha on purpose. Several bursts can overlap -- a
	# blessing landing inside a wrath ring -- and at full strength the
	# additive ones stack into a white hole with no shape left in it.
	var tint: Color = spec["colour"]
	tint.a = 0.72
	draw.albedo_color = tint
	draw.disable_receive_shadows = true
	p.draw_pass_1 = _mesh
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
	p.global_position = at
	# amount_ratio, not amount. See the header.
	p.amount_ratio = clampf(_density * scale_v, 0.05, 1.0)
	p.restart()
	p.emitting = true


## A ring of bursts, for something that happens over an AREA rather than at a
## point -- wrath, mostly. Cheaper and more legible than one enormous emitter,
## because the shape of the effect then matches the shape of the damage.
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
