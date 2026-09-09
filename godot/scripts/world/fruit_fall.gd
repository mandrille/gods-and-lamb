extends RefCounted
class_name FruitFall

## Apples hanging in a tree, and then not.
##
## Touching a tree drops food on the ground, and the ground is where the
## mechanic lives -- a villager walks over a heap and eats it. But food that
## simply appears in the grass is a spawn, not a harvest: nothing connects the
## tree you touched to the apples you got, and the one thing the player did is
## the one thing they cannot see.
##
## So the apples appear IN THE CANOPY first, hang there for a moment, and fall.
## They are pure decoration -- the real `Nature/apples` heaps go down at the
## same instant, so a villager who happens to be walking past is already
## heading for one before the visual has landed. If this helper failed to run
## at all, the game would play identically and only look worse.
##
## Runtime primitives rather than an asset, which is the same call
## miracle_cursor.gd makes: a sphere the size of a thumbnail seen for one and a
## half seconds does not justify a GLB in the library, an entry in the vocab and
## a row in the build gate.

const R := 0.075                   ## apple radius, in metres
const HANG_MIN := 0.35             ## how long one waits in the tree
const HANG_MAX := 1.30
const DROP := 0.42                 ## seconds from canopy to grass
## Where the fruit sits on the tree. `Nature/tree` has an 0.86 m trunk with the
## canopy core at +0.32 above it, so this is the lower half of the leaves --
## fruit at the very top of a blob reads as a decoration balanced on it.
const CANOPY_Y := 1.05
const CANOPY_R := 0.42


## Hang `count` apples in the tree at `trunk`, then drop them on the given
## world positions. `host` only needs to be somewhere in the tree that can hold
## children and make timers.
static func drop(host: Node3D, trunk: Vector3, landings: Array,
				 rng: RandomNumberGenerator) -> void:
	if host == null or not host.is_inside_tree():
		return
	var mesh := SphereMesh.new()
	mesh.radius = R
	mesh.height = R * 2.0
	# Four rings and six segments: this is a red dot at play distance, and the
	# default 64x32 sphere is 4,000 triangles for something the size of a pixel.
	mesh.radial_segments = 6
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.79, 0.16, 0.15)
	mat.roughness = 0.65

	for i in landings.size():
		var to: Vector3 = landings[i]
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.material_override = mat
		# Somewhere in the leaves, not on the trunk axis.
		var a: float = rng.randf() * TAU
		var r: float = CANOPY_R * sqrt(rng.randf())
		var from := trunk + Vector3(cos(a) * r, CANOPY_Y
									+ rng.randf_range(-0.16, 0.20),
									sin(a) * r)
		node.position = from
		host.add_child(node)

		var hang: float = rng.randf_range(HANG_MIN, HANG_MAX)
		var tween := host.create_tween()
		# ALWAYS: the tree pauses at nightfall and half-fallen fruit frozen in
		# mid-air is the kind of thing a player screenshots.
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_interval(hang)
		# EASE_IN on the way down, because that is what falling looks like; a
		# linear drop reads as an object being carried.
		tween.tween_property(node, "position", to + Vector3(0, R, 0), DROP) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(node, "scale", Vector3.ZERO, 0.18) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_callback(node.queue_free)
