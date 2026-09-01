extends SceneTree
## Does a folded folk mesh still look like the folk mesh?
##
## The surface fold moves each material's albedo into COLOR_0 and leaves one
## white material behind. In theory that is the same product: glTF defines
## COLOR_0 as multiplying into base colour and Godot turns it into
## `vertex_color_use_as_albedo`. In practice the whole art direction rests on
## whether Godot treats COLOR_0 as LINEAR, and the AO bake would never have
## caught a mistake there -- AO is near-white, so an sRGB/linear confusion
## shifts it by a rounding error. A saturated red moves a long way.
##
## So this renders the villager and the adventurer alone, close, on a flat
## background, under the game's own light rig, and prints the mean colour of
## the subject pixels. Run it before and after the fold and compare.
##
## It deliberately does NOT assert a threshold. The comparison is between two
## runs of this tool, and hard-coding what "correct" looks like would just be
## writing today's numbers down and calling them a check.
const ShotWindowRef := preload("res://tools/shot_window.gd")
const LightRig := preload("res://scripts/vale_light.gd")
const BuilderRef := preload("res://scripts/vale_builder.gd")

const SUBJECTS := ["Folk__villager", "Folk__adventurer"]
const BG := Color(0.10, 0.10, 0.12)

var _f := 0
var _shot := 0
var _cam: Camera3D
var _rig: Node3D
var _env_ready := false
var _holder: Node3D


func _initialize() -> void:
	ShotWindowRef.park()
	var root := get_root()

	# ValeLight builds itself in _ready(); there is no setup() to call.
	_rig = LightRig.new()
	root.add_child(_rig)

	_holder = Node3D.new()
	root.add_child(_holder)

	_cam = Camera3D.new()
	_cam.current = true
	root.add_child(_cam)
	# IN THE TREE FIRST. look_at() on a detached node errors and leaves the
	# camera pointing down -Z, which renders empty space and reports it as a
	# clean measurement.
	_cam.look_at_from_position(Vector3(0.0, 0.62, 1.35),
		Vector3(0.0, 0.52, 0.0), Vector3.UP)


## Flat background, no fog, no sky.
##
## Deferred to the first frame rather than done in _initialize(): the rig
## builds its Environment in _ready(), which has not run while the SceneTree
## is still initialising. Reading `rig.env` there returns null, and the first
## version of this tool carried on with the SKY as its background -- so every
## sky pixel counted as subject and both folk measured identically. A backdrop
## that is not the thing you are measuring is the whole trap.
func _prepare_env() -> bool:
	var env: Environment = _rig.env
	if env == null:
		return false
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.fog_enabled = false
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	return true


func _process(_d: float) -> bool:
	_f += 1
	# A hard ceiling. Without it, anything that leaves the state machine stuck
	# -- a null holder, a subject that never loads -- spins forever and the run
	# has to be killed from outside, which is how ten minutes went missing.
	if _f > 400:
		printerr("[FOLK] FAIL: stuck after %d frames on subject %d of %d"
			% [_f, _shot + 1, SUBJECTS.size()])
		quit(1)
		return true
	if _holder == null or _cam == null:
		printerr("[FOLK] FAIL: scene did not build (holder or camera is null)")
		quit(1)
		return true
	if not _env_ready:
		_env_ready = _prepare_env()
		return false
	# Settle before the first capture and between subjects: a swapped mesh is
	# not on screen the frame it is added.
	if _f % 12 != 0:
		return false
	if _shot >= SUBJECTS.size():
		quit(0)
		return true

	var id: String = SUBJECTS[_shot]
	if _holder.get_child_count() == 0:
		var path := "res://assets/library/%s.glb" % id
		if not ResourceLoader.exists(path):
			printerr("[FOLK] missing %s" % path)
			quit(1)
			return true
		# Through the builder's normaliser, not a raw load: this tool must see
		# what the game sees, and the game's COLOR_0 flag is set there.
		var packed: PackedScene = load(path)
		BuilderRef.new()._normalise_vertex_colour(packed)
		var inst := packed.instantiate()
		_holder.add_child(inst)
		return false

	_measure(id)
	for c in _holder.get_children():
		_holder.remove_child(c)
		c.queue_free()
	_shot += 1
	return false


func _measure(id: String) -> void:
	var img := get_root().get_texture().get_image()
	var w := img.get_width()
	var h := img.get_height()
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0
	var surfaces := _count_surfaces()
	# Read the background off a CORNER rather than trusting the colour that was
	# set. Tonemapping and exposure transform it on the way to the framebuffer,
	# so comparing against the authored BG excluded nothing and every sky pixel
	# counted as subject -- which is exactly why both folk first measured the
	# same to three decimals.
	var back := img.get_pixel(2, 2)
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var c := img.get_pixel(x, y)
			# Subject, not background. A distance test rather than a luma
			# threshold, so a dark boot counts and a lit backdrop does not.
			if Vector3(c.r - back.r, c.g - back.g, c.b - back.b).length() < 0.04:
				continue
			r += c.r
			g += c.g
			b += c.b
			n += 1
	if n == 0:
		printerr("[FOLK] %s: no subject pixels -- nothing rendered" % id)
		return
	var frac := 100.0 * float(n) / float((w / 2) * (h / 2))
	print("[FOLK] %-18s surfaces %d  subject %5.1f%% of frame  mean rgb %.4f %.4f %.4f"
		% [id, surfaces, frac, r / n, g / n, b / n])
	if frac > 90.0:
		printerr("[FOLK] %s fills %.1f%% of the frame -- the background test is "
			% [id, frac] + "not separating anything, so this mean is the whole "
			+ "image and means nothing.")
	img.save_png("res://shots/folk_%s.png" % id)


func _count_surfaces() -> int:
	var total := 0
	var stack: Array[Node] = [_holder]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var m := (node as MeshInstance3D).mesh
			if m != null:
				total += m.get_surface_count()
		for c in node.get_children():
			stack.append(c)
	return total
