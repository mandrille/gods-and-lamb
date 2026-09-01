extends SceneTree

## Screenshot the running Vale. NOT --headless: get_texture() needs a real
## swapchain.
##
## Two guards, both because a failed shot run and a good one look identical:
##   * a STALE-FRAME check. Two captures taken frames apart cannot be
##     bit-identical once anything is moving; a repeat means the swapchain
##     never presented and the picture is a lie.
##   * photometrics on every frame. A render that succeeds and is empty reads
##     exactly like one that worked, in a log.

const ShotWindow := preload("res://tools/shot_window.gd")
const OUT := "res://shots/"
const WARMUP := 45          ## frames before the first grab: the GLB library,
                            ## the multimesh fill and the first shadow pass all
                            ## land after _ready() returns.
const GAP := 60             ## frames between grabs. Long enough that a
                            ## follower moves a visible distance: at
                            ## 0.46 m/s that is ~0.46 m, one tile.

var _frame := 0
var _taken := 0
var _prev := PackedByteArray()


func _initialize() -> void:
	ShotWindow.park()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var packed: PackedScene = load("res://scenes/vale.tscn")
	get_root().add_child(packed.instantiate())


func _process(_d: float) -> bool:
	_frame += 1
	if _frame < WARMUP or (_frame - WARMUP) % GAP != 0:
		return false
	var img := get_root().get_texture().get_image()
	var data := img.get_data()
	if data == _prev:
		printerr("[SHOT] FAIL: frame %d is bit-identical to the last grab. "
			% _frame + "The swapchain never presented; refusing to write.")
		quit(1)
		return true
	_prev = data

	var lo := 1.0
	var hi := 0.0
	var sum := 0.0
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			lo = min(lo, l)
			hi = max(hi, l)
			sum += l
			n += 1
	var mean: float = sum / float(max(n, 1))
	var path := OUT + "vale_%02d.png" % _taken
	img.save_png(ProjectSettings.globalize_path(path))
	print("[SHOT] %s  frame %d  luma %.3f (%.3f..%.3f)%s"
		% [path, _frame, mean, lo, hi,
		   "   ** BLANK **" if hi - lo < 0.05 else ""])
	# Positions, so "the followers walk" is a measurement and not a claim. A
	# still image cannot tell you whether they moved.
	for top in get_root().get_children():
		for c in top.get_children():
			if c.get_script() != null and c.name.begins_with("Follower"):
				# Position proves TRANSLATION. A frozen mesh sliding along a
				# path produces the same numbers, so the leg bone is sampled
				# too -- that is the only thing that proves the clip is
				# actually deforming the skin.
				var leg := _leg_pitch(c)
				print("        %s at (%.2f, %.2f) yaw %.0f  LegL pitch %s"
					% [c.name, c.position.x, c.position.z,
					   rad_to_deg(c.rotation.y),
					   ("%.1f deg" % leg) if not is_nan(leg) else "NO SKELETON"])
	# Hover picking, proven rather than assumed. Aiming at the middle of the
	# frame proves nothing -- the centre is usually bare ground, and "nothing"
	# is then a correct answer that looks like a broken one. So take a prop
	# that is actually ON SCREEN, project it to its own pixel, and fire the
	# ray the mouse would fire there. The right answer is that prop.
	for top in get_root().get_children():
		if top.has_method("_on_picked") and top.get("pick") != null:
			var pk = top.get("pick")
			var cam: Camera3D = top.get("rig").cam
			var tested := 0
			var ok := 0
			for entry in pk.props:
				var world: Vector3 = (entry["aabb"] as AABB).get_center()
				if cam.is_position_behind(world):
					continue
				var screen := cam.unproject_position(world)
				if screen.x < 0 or screen.y < 0 or screen.x > img.get_width() 						or screen.y > img.get_height():
					continue
				tested += 1
				var hit: Dictionary = pk._pick_at(screen)
				if not hit.is_empty():
					ok += 1
				if tested >= 40:
					break
			print("        pick: %d/%d on-screen props hit by their own ray"
				% [ok, tested])
	_taken += 1
	if _taken >= 3:
		quit(0)
		return true
	return false


func _leg_pitch(n: Node) -> float:
	for d in _walk_nodes(n):
		if d is Skeleton3D:
			var sk := d as Skeleton3D
			var idx := sk.find_bone("LegL")
			if idx >= 0:
				return rad_to_deg(sk.get_bone_pose_rotation(idx).get_euler().x)
	return NAN


func _walk_nodes(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk_nodes(c))
	return out
