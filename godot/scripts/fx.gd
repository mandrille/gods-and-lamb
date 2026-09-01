extends Node3D
class_name ValeFX

## Ambient particle FX for the Vale: chimney smoke, canopy dust, falling leaves.
##
## THE SHAPE OF THIS FILE IS THE POINT. There are 256 props today and there
## will be more, so nothing here is per-prop. Each KIND of effect is ONE
## GPUParticles3D with a fixed pool, and every prop that should emit it
## contributes an emission POINT to that one emitter's point texture. Three
## effects, three nodes, three draw calls -- whether the village has 250 props
## or 2500. Giving every cottage its own emitter would have been six nodes
## today and sixty after the village grows, and each one is a draw call, a
## process dispatch and a culling test.
##
## Pool sizes are decided once, in setup(), and never touched again.
## set_density() moves `amount_ratio` and NOTHING else: writing `amount`
## reallocates the GPU particle buffers, which is the exact cost this
## arrangement exists to avoid. `amount_ratio` is clamped to 0..1 by the
## engine, so the pool is allocated at DENSITY_MAX times the authored count and
## sits at ratio 0.5 for authored density -- that is what buys the top half of
## the 0..2 range without a realloc.
##
## Every texture, mesh, gradient and curve is generated in code and cached by
## key on a static table. The entire game is 526 KB against a 9.7 MB engine
## (docs/web-cost.md); a particle sheet would be the single largest asset in
## the project, and it would buy nothing a radial falloff cannot.
##
## GL Compatibility: everything here is an unshaded billboard. No volumetric
## fog (Forward+ only), no light interaction, no depth write.

const DENSITY_MAX := 2.0

## Which prop ids feed which effect. A prop can feed more than one -- a tree is
## both a dust source and a leaf source.
const SMOKE_IDS: PackedStringArray = ["Buildings/cottage", "Buildings/hut"]
const MOTE_IDS: PackedStringArray = ["Nature/tree", "Nature/pine"]
const LEAF_IDS: PackedStringArray = ["Nature/tree"]

## Particles per source, and the clamp that stops a large village becoming a
## fill-rate problem. Counted in setup(), before any GPU buffer exists, so this
## is sizing and not a runtime resize. Once the clamp bites, more chimneys make
## each plume thinner rather than making the frame slower -- which is the right
## trade on a phone.
const BUDGET := {
	"smoke": {"per": 30, "min": 30, "max": 300},
	"motes": {"per": 8, "min": 40, "max": 220},
	"leaves": {"per": 5, "min": 24, "max": 150},
}

## Where the smoke leaves the building, in the prop's own local XZ. The cottage
## value mirrors CHIM_X/CHIM_Y in blender/assets/Buildings/cottage.py, swizzled
## (Blender +Y is Godot -Z). The hut has no stack at all, so its smoke seeps
## from the middle of the thatch ridge.
##
## Only the OFFSET is authored -- x and z across the roof, y as a nudge above
## whatever the roof turns out to be. The height itself is measured off the
## prop's own mesh AABB at setup, so a taller roof or a re-modelled chimney
## moves the plume without anyone remembering to come back here.
##
## The hut is nudged higher than the cottage because it has no stack to clear:
## sitting the plume on the ridge itself put a white blob on the thatch instead
## of a column above it.
const CHIMNEY_OFFSET := {
	"Buildings/cottage": Vector3(-0.40, 0.05, -0.40),
	"Buildings/hut": Vector3(0.0, 0.18, 0.0),
}

## Palette, straight out of `init_materials()` in blender/src/kit.py, in sRGB
## exactly as that file writes it. Smoke is warm off-white sliding to a cool
## grey as it thins -- a neutral grey plume against a blue sky reads as a hole
## in the render, which is the same failure `stone` was retuned for.
const SMOKE_HOT := Color(0.960, 0.925, 0.870)
const SMOKE_COLD := Color(0.760, 0.755, 0.745)
## Motes are lit dust, so they take the sun's own colour (SUN_COLOR in
## vale_light.gd) pushed warmer. Additive, because a speck of backlit dust is
## brighter than what is behind it and nothing else in this renderer says that.
const MOTE_COLOR := Color(1.000, 0.940, 0.760)
## Leaves span the tree's own two greens plus the turning end of the range:
## leaf_light, leaf, thatch.
const LEAF_GREEN := Color(0.395, 0.700, 0.290)
const LEAF_MID := Color(0.230, 0.545, 0.235)
const LEAF_GOLD := Color(0.760, 0.585, 0.265)

## Fallback bounds for a prop whose mesh cannot be measured. Never expected to
## fire; a plume at the wrong height is a better failure than no plume.
const AABB_FALLBACK := AABB(Vector3(-0.6, 0.0, -0.6), Vector3(1.2, 1.6, 1.2))

## Procedural resources, shared by every instance for the whole run. Textures
## are the expensive ones to rebuild; the gradients and curves are cached in
## the same table because a second copy of them is a second uniform upload.
static var _cache: Dictionary = {}

var _emitters: Array[GPUParticles3D] = []
var _density := 1.0
var _sources: Dictionary = {}      ## kind -> how many props feed it


## Build one emitter per effect kind from the placed props.
##
## `props` is an Array of {"id": String, "node": Node3D, "pos": Vector3}, one
## per placed prop, `pos` already in world space. Safe to call again: the old
## emitters are dropped and rebuilt, which is what a rebuilt village needs.
func setup(props: Array) -> void:
	for e in _emitters:
		# remove_child BEFORE queue_free: the free is deferred to the end of the
		# frame, so an emitter that is only queued is still a child, still
		# drawn and still counted by anything inspecting get_children(). On a
		# rebuild that reads as a doubled pool.
		remove_child(e)
		e.queue_free()
	_emitters.clear()
	_sources = {"smoke": 0, "motes": 0, "leaves": 0}

	var pts := {
		"smoke": PackedVector3Array(),
		"motes": PackedVector3Array(),
		"leaves": PackedVector3Array(),
	}
	# Seeded, so two runs of the shot tool scatter the motes identically. A
	# screenshot diff that moves for no reason is a screenshot diff nobody
	# reads.
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EED_1A3B

	for p in props:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var id := String(p.get("id", ""))
		var node := p.get("node", null) as Node3D
		var pos: Vector3 = p.get("pos", Vector3.ZERO)
		var xform := _prop_xform(node, pos)
		var box := _prop_aabb(node)

		if SMOKE_IDS.has(id):
			_smoke_points(pts["smoke"], id, xform, box, rng)
			_sources["smoke"] += 1
		if MOTE_IDS.has(id):
			_mote_points(pts["motes"], xform, box, rng)
			_sources["motes"] += 1
		if LEAF_IDS.has(id):
			_leaf_points(pts["leaves"], xform, box, rng)
			_sources["leaves"] += 1

	for kind in ["smoke", "motes", "leaves"]:
		var kp: PackedVector3Array = pts[kind]
		if kp.is_empty():
			continue
		_emitters.append(_make_emitter(kind, kp, _budget_of(kind)))

	set_density(_density)
	var live := 0
	for e in _emitters:
		live += e.amount
	print("[FX] %d emitters, %d particles pooled (%d smoke src, %d canopy src)"
		% [_emitters.size(), live, _sources["smoke"], _sources["motes"]])


## 0.0 .. 2.0, where 1.0 is the authored look. Moves `amount_ratio` only --
## `amount` is never written after setup(). At exactly zero the emitters are
## switched off as well, so the process pass stops costing anything instead of
## running over an empty pool.
func set_density(scale: float) -> void:
	_density = clampf(scale, 0.0, DENSITY_MAX)
	var ratio := _density / DENSITY_MAX
	for e in _emitters:
		e.amount_ratio = ratio
		e.emitting = _density > 0.0


## Particles currently budgeted across every live emitter -- the thing
## set_density() actually moves, and therefore the thing worth asserting on.
func active_count() -> int:
	var n := 0
	for e in _emitters:
		if e.emitting:
			n += int(round(float(e.amount) * e.amount_ratio))
	return n


## Debug/report only: how many nodes (and therefore draw calls) the whole
## village costs.
func emitter_count() -> int:
	return _emitters.size()


# --- emission points ---------------------------------------------------------

## Three points in a 4 cm huddle rather than one, so the plume has a throat
## instead of a single pixel-wide seam of overlapping quads.
func _smoke_points(out: PackedVector3Array, id: String, xform: Transform3D,
		box: AABB, rng: RandomNumberGenerator) -> void:
	var off: Vector3 = CHIMNEY_OFFSET.get(id, Vector3.ZERO)
	var top := box.position.y + box.size.y + off.y
	for i in 3:
		var local := Vector3(
			off.x + rng.randf_range(-0.04, 0.04),
			top + rng.randf_range(-0.02, 0.03),
			off.z + rng.randf_range(-0.04, 0.04))
		out.append(xform * local)


## Motes ring the canopy rather than filling it. The first version scattered
## them through the canopy VOLUME, which is the physically sensible thing and
## was almost entirely invisible: these canopies are solid boxes, depth test is
## on, and a mote inside one is behind it. So they sit in a shell just outside
## the silhouette, where they read against the dark leaf colour.
func _mote_points(out: PackedVector3Array, xform: Transform3D, box: AABB,
		rng: RandomNumberGenerator) -> void:
	var mid := box.position.y + box.size.y * 0.60
	var ry := box.size.y * 0.20
	var span := maxf(box.size.x, box.size.z)
	for i in 6:
		var a := rng.randf_range(0.0, TAU)
		var r := span * rng.randf_range(0.52, 0.66)
		var local := Vector3(
			box.position.x + box.size.x * 0.5 + cos(a) * r,
			mid + rng.randf_range(-ry, ry),
			box.position.z + box.size.z * 0.5 + sin(a) * r)
		out.append(xform * local)


## Leaves come off the outside of the canopy, high up, where a leaf that is
## about to fall actually is.
func _leaf_points(out: PackedVector3Array, xform: Transform3D, box: AABB,
		rng: RandomNumberGenerator) -> void:
	var top := box.position.y + box.size.y * 0.80
	var r := maxf(box.size.x, box.size.z) * 0.46
	for i in 4:
		var a := rng.randf_range(0.0, TAU)
		var local := Vector3(
			box.position.x + box.size.x * 0.5 + cos(a) * r,
			top + rng.randf_range(-0.12, 0.06),
			box.position.z + box.size.z * 0.5 + sin(a) * r)
		out.append(xform * local)


## The prop's world transform. `pos` is the contract, but a node already in the
## tree knows better -- and its BASIS is the only place the yaw and scale the
## builder applied can be read from.
func _prop_xform(node: Node3D, pos: Vector3) -> Transform3D:
	if node == null:
		return Transform3D(Basis(), pos)
	if node.is_inside_tree():
		return node.global_transform
	return Transform3D(node.transform.basis, pos)


## Merged mesh bounds in the prop root's OWN space. Measured, never derived:
## these GLBs are script-generated and their real extents are routinely not
## what the builder's arithmetic suggests.
func _prop_aabb(node: Node3D) -> AABB:
	if node == null:
		return AABB_FALLBACK
	var out := AABB()
	var got := false
	for n in _walk(node):
		if not (n is VisualInstance3D):
			continue
		var vi := n as VisualInstance3D
		var box: AABB = _rel_xform(vi, node) * vi.get_aabb()
		out = box if not got else out.merge(box)
		got = true
	return out if got else AABB_FALLBACK


## Transform of `from` relative to `root`, walked by hand rather than through
## global_transform: setup() may run before anything is in the tree.
func _rel_xform(from: Node3D, root: Node3D) -> Transform3D:
	var x := Transform3D()
	var n: Node = from
	while n != null and n != root:
		if n is Node3D:
			x = (n as Node3D).transform * x
		n = n.get_parent()
	return x


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out


func _budget_of(kind: String) -> int:
	var b: Dictionary = BUDGET[kind]
	var n: int = _sources[kind]
	return clampi(int(b["per"]) * n, int(b["min"]), int(b["max"]))


# --- emitters ----------------------------------------------------------------

func _make_emitter(kind: String, pts: PackedVector3Array, authored: int) -> GPUParticles3D:
	var e := GPUParticles3D.new()
	e.name = "FX_" + kind
	# The pool. Allocated at DENSITY_MAX x authored so set_density(2.0) has
	# somewhere to go; authored density then sits at amount_ratio 0.5.
	e.amount = int(round(float(authored) * DENSITY_MAX))
	e.amount_ratio = 1.0 / DENSITY_MAX
	e.local_coords = false
	# The emission points are WORLD positions, and an emitter transforms them by
	# its own global transform when it spawns. top_level cuts the emitter off
	# from whatever ValeFX ends up parented to, so the plumes stay on the roofs
	# no matter where the node is hung in the scene.
	e.top_level = true
	e.fixed_fps = 24          ## these drift; 24 is invisible and a third cheaper
	e.interpolate = true
	e.draw_pass_1 = _quad_for(kind)
	e.process_material = _process_for(kind, pts)

	match kind:
		"smoke":
			e.lifetime = 4.6
			# Start with the plumes already established. Without this the first
			# five seconds of every session -- and every screenshot taken
			# before frame 300 -- show six stubs growing out of six roofs.
			e.preprocess = e.lifetime
			e.randomness = 1.0
		"motes":
			e.lifetime = 7.0
			e.preprocess = e.lifetime
			e.randomness = 1.0
		"leaves":
			e.lifetime = 6.0
			e.preprocess = e.lifetime
			e.randomness = 1.0

	# One emitter spans the whole village, so its bounds have to as well or the
	# engine culls every plume the moment the emitter ORIGIN leaves frame --
	# which, at world origin under a camera looking at one corner, is most of
	# the time.
	e.visibility_aabb = _bounds_of(pts).grow(6.0)
	add_child(e)
	return e


func _quad_for(kind: String) -> QuadMesh:
	var key := "quad:" + kind
	if _cache.has(key):
		return _cache[key]
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = _material_for(kind)
	_cache[key] = q
	return q


func _material_for(kind: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	# Unshaded: there is one directional light and a sky, and a lit billboard
	# under it goes grey on the shadow side, which on a puff of smoke reads as
	# a dirty smear rather than as volume. The colour ramp does the shading.
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.vertex_color_use_as_albedo = true
	# BILLBOARD_PARTICLES, not BILLBOARD_ENABLED: it is the mode that lets the
	# per-particle angle through, and without a random angle per puff the plume
	# is one texture stamped forty times and reads as a pattern.
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.disable_receive_shadows = true
	m.disable_ambient_light = true
	match kind:
		"smoke":
			m.albedo_texture = _tex_puff()
		"motes":
			m.albedo_texture = _tex_dot()
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		"leaves":
			m.albedo_texture = _tex_leaf()
	return m


func _process_for(kind: String, pts: PackedVector3Array) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	pm.emission_point_count = pts.size()
	pm.emission_point_texture = _points_texture(pts)

	match kind:
		"smoke":
			pm.direction = Vector3(0, 1, 0)
			pm.spread = 6.0
			pm.initial_velocity_min = 0.46
			pm.initial_velocity_max = 0.64
			# Buoyancy first, drift second. The first tuning had this the other
			# way round -- 0.13 sideways against 0.03 up, with heavy damping --
			# and the plume left the chimney at 45 degrees and stayed there. A
			# chimney that smokes SIDEWAYS reads as a lens smear on the render,
			# not as smoke, and that is exactly how it looked.
			pm.gravity = Vector3(0.035, 0.14, -0.02)
			pm.damping_min = 0.03
			pm.damping_max = 0.08
			pm.angle_min = -180.0
			pm.angle_max = 180.0
			pm.angular_velocity_min = -14.0
			pm.angular_velocity_max = 14.0
			pm.scale_min = 0.62
			pm.scale_max = 1.05
			pm.scale_curve = _curve("smoke_scale",
				[Vector2(0.0, 0.20), Vector2(0.35, 0.64), Vector2(1.0, 1.0)])
			# Peak alpha 0.70, not 0.46. Judged at the PLAY camera, where a
			# plume is forty pixels tall: the first tuning was legible in a
			# close-up and completely gone at seventeen metres, which is the
			# only distance the player ever sees it from.
			pm.color_ramp = _gradient("smoke_ramp", [
				[0.00, Color(SMOKE_HOT, 0.00)],
				[0.08, Color(SMOKE_HOT, 0.72)],
				[0.50, Color(SMOKE_HOT.lerp(SMOKE_COLD, 0.5), 0.50)],
				[0.82, Color(SMOKE_COLD, 0.26)],
				[1.00, Color(SMOKE_COLD, 0.00)],
			])
			pm.turbulence_enabled = true
			# Strength stays low and the noise stays FINE. At 0.18/1.5 the whole
			# plume sat inside one noise cell, so the turbulence stopped being
			# turbulence and became a coherent wind: every plume in the village
			# leaned the same way at the same moment.
			pm.turbulence_noise_strength = 0.10
			pm.turbulence_noise_scale = 3.4
			pm.turbulence_noise_speed = Vector3(0.10, 0.02, 0.06)
		"motes":
			pm.direction = Vector3(0, 1, 0)
			pm.spread = 180.0
			pm.initial_velocity_min = 0.015
			pm.initial_velocity_max = 0.060
			pm.gravity = Vector3(0.012, -0.004, 0.010)
			# 2.8 cm to 6 cm. Below about 2.5 cm a mote is under one pixel at
			# the play camera and mipmaps average it out of existence; above
			# about 7 it stops being dust and becomes a firefly, which is a
			# different game.
			pm.scale_min = 0.028
			pm.scale_max = 0.060
			pm.color_ramp = _gradient("mote_ramp", [
				[0.00, Color(MOTE_COLOR, 0.00)],
				[0.22, Color(MOTE_COLOR, 0.62)],
				[0.70, Color(MOTE_COLOR, 0.44)],
				[1.00, Color(MOTE_COLOR, 0.00)],
			])
		"leaves":
			pm.direction = Vector3(0, -1, 0)
			pm.spread = 45.0
			pm.initial_velocity_min = 0.05
			pm.initial_velocity_max = 0.16
			# Tuned so a leaf runs out of lifetime near the ground rather than
			# through it: ~1.9 m of fall over 6 s from a canopy about that high.
			pm.gravity = Vector3(0.05, -0.075, -0.035)
			pm.damping_min = 0.02
			pm.damping_max = 0.06
			pm.angle_min = -180.0
			pm.angle_max = 180.0
			pm.angular_velocity_min = -95.0
			pm.angular_velocity_max = 95.0
			pm.scale_min = 0.070
			pm.scale_max = 0.115
			pm.color_ramp = _gradient("leaf_ramp", [
				[0.00, Color(1, 1, 1, 0.0)],
				[0.08, Color(1, 1, 1, 1.0)],
				[0.85, Color(1, 1, 1, 1.0)],
				[1.00, Color(1, 1, 1, 0.0)],
			])
			# Per-particle, not over-lifetime: this one is sampled once at
			# birth, so it is leaf VARIETY rather than a leaf changing colour
			# in mid-air.
			pm.color_initial_ramp = _gradient("leaf_tint", [
				[0.00, LEAF_GREEN],
				[0.45, LEAF_MID],
				[0.75, LEAF_GREEN.lerp(LEAF_GOLD, 0.6)],
				[1.00, LEAF_GOLD],
			])
	return pm


func _bounds_of(pts: PackedVector3Array) -> AABB:
	var box := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		box = box.expand(p)
	return box


# --- procedural resources ----------------------------------------------------

## Emission points as a 1-pixel-tall RGBF strip, which is what
## EMISSION_SHAPE_POINTS samples. This is why one emitter can serve the whole
## village: the scatter lives in a texture, not in a node per source.
func _points_texture(pts: PackedVector3Array) -> ImageTexture:
	var img := Image.create_empty(pts.size(), 1, false, Image.FORMAT_RGBF)
	for i in pts.size():
		img.set_pixel(i, 0, Color(pts[i].x, pts[i].y, pts[i].z))
	return ImageTexture.create_from_image(img)


## A soft round falloff. Everything additive uses this one.
func _tex_dot() -> ImageTexture:
	if _cache.has("tex:dot"):
		return _cache["tex:dot"]
	var n := 64
	var img := Image.create_empty(n, n, true, Image.FORMAT_RGBA8)
	var c := float(n - 1) * 0.5
	for y in n:
		for x in n:
			var r := Vector2(float(x) - c, float(y) - c).length() / c
			img.set_pixel(x, y, Color(1, 1, 1, smoothstep(1.0, 0.28, r)))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache["tex:dot"] = t
	return t


## The smoke puff: the same falloff with a little noise bitten out of it. A
## plain disc stacks into something that reads as bubbles; the broken edge is
## what turns forty overlapping quads into one volume. Two octaves is enough at
## the play camera, where a puff is maybe thirty pixels across.
func _tex_puff() -> ImageTexture:
	if _cache.has("tex:puff"):
		return _cache["tex:puff"]
	var n := 64
	var noise := FastNoiseLite.new()
	noise.seed = 20260901
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.055
	noise.fractal_octaves = 2
	var img := Image.create_empty(n, n, true, Image.FORMAT_RGBA8)
	var c := float(n - 1) * 0.5
	for y in n:
		for x in n:
			var r := Vector2(float(x) - c, float(y) - c).length() / c
			# Solid out to 42% of the radius. A falloff that starts at the
			# very centre has an average alpha so low that the whole plume
			# needs an opacity that then blows out where two puffs cross.
			var base := smoothstep(1.0, 0.42, r)
			var v := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			# The core stays solid and only the outer half gets chewed, or the
			# puff turns into lace and loses its silhouette.
			var bite: float = lerpf(1.0, 0.42 + 0.58 * v, clampf(r * 1.35, 0.0, 1.0))
			img.set_pixel(x, y, Color(1, 1, 1, base * bite))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache["tex:puff"] = t
	return t


## A leaf: an ellipse with one pointed end. At 6 cm it is about four pixels on
## a phone, so it is a silhouette and nothing else -- no midrib, no shading.
func _tex_leaf() -> ImageTexture:
	if _cache.has("tex:leaf"):
		return _cache["tex:leaf"]
	var n := 32
	var img := Image.create_empty(n, n, true, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (float(x) + 0.5) / float(n) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(n) * 2.0 - 1.0
			# Waist that narrows toward +v: a teardrop, not a pill.
			var w: float = 0.52 * (1.0 - 0.65 * clampf(v, 0.0, 1.0))
			var d := sqrt((u / maxf(w, 0.06)) * (u / maxf(w, 0.06)) + (v / 0.92) * (v / 0.92))
			img.set_pixel(x, y, Color(1, 1, 1, smoothstep(1.0, 0.72, d)))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache["tex:leaf"] = t
	return t


func _gradient(key: String, stops: Array) -> GradientTexture1D:
	var ck := "grad:" + key
	if _cache.has(ck):
		return _cache[ck]
	# Written as two whole arrays rather than add_point()'d: a fresh Gradient
	# already carries two default stops, and adding on top of them leaves a
	# black point at 0 that shows up as a dark flash on every particle's first
	# frame.
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(float(s[0]))
		cols.append(s[1])
	var g := Gradient.new()
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 64
	_cache[ck] = t
	return t


func _curve(key: String, pts: Array) -> CurveTexture:
	var ck := "curve:" + key
	if _cache.has(ck):
		return _cache[ck]
	var c := Curve.new()
	for p in pts:
		c.add_point(p)
	var t := CurveTexture.new()
	t.curve = c
	t.width = 64
	_cache[ck] = t
	return t
