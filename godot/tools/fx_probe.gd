extends SceneTree

## Throwaway harness for scripts/fx.gd: a scrap of village for the pictures, the
## whole village's worth of emitters for the frame cost, and the API exercised
## on the way past.
##
## NOT --headless -- get_root().get_texture() needs a real swapchain.
##
##   godot --path . --resolution 1280x800 --audio-driver Dummy \
##         --script res://tools/fx_probe.gd
##
## The stale-frame guard does double duty here. Two of the grabs are taken from
## the SAME camera 22 frames apart, and nothing in this scene moves except the
## particles -- so if that pair comes back bit-identical, either the swapchain
## never presented or GPUParticles3D is not simulating under GL Compatibility.
## Either way the run is worthless and it says so.
##
## The frame cost is measured A/B/A/B/A/B rather than once each way. The first
## attempt did one window per state and reported the FX as NEGATIVE cost: at
## 3000 fps the whole scene is a third of a millisecond, and the run drifts by
## more than the thing being measured over its own lifetime. Alternating and
## averaging is what makes the difference bigger than the drift.

const ShotWindow := preload("res://tools/shot_window.gd")
const FX := preload("res://scripts/fx.gd")
const LIGHT := preload("res://scripts/vale_light.gd")
const OUT := "res://shots/"
const LIB := "res://assets/library/%s.glb"

## Roughly the game camera: 35 mm on a 36 mm frame, KEEP_WIDTH, the hero angle
## out of vale_root.gd. Three of them, because an effect that reads at 5 m and
## is gone at 17 m has failed the only camera the player has.
const CAM_DIR := Vector3(-0.72, 0.88, 1.00)
const CAM_LENS := 35.0

## The picture set: close enough to judge the plume, sparse enough to see it.
const HERO := [
	["Buildings/cottage", Vector3(0.0, 0.0, 0.0), 18.0],
	["Buildings/hut", Vector3(2.7, 0.0, 0.5), -35.0],
	["Nature/tree", Vector3(-2.5, 0.0, 0.7), 0.0],
	["Nature/tree", Vector3(3.9, 0.0, -1.4), 40.0],
	["Nature/pine", Vector3(-3.6, 0.0, -1.8), 0.0],
]

## The census out of data/vale.json, which is what the pools actually get sized
## against. Measuring the FX on five props would understate it four-fold.
const CENSUS := {
	"Buildings/cottage": 3,
	"Buildings/hut": 3,
	"Nature/tree": 20,
	"Nature/pine": 10,
}
## The Vale is 64 x 48 tiles at 0.5 m.
const MAP := Vector2(32.0, 24.0)

const WINDOW := 1.1        ## seconds of timing per window
const SETTLE := 0.5        ## seconds discarded after a state change

## Node3D, not ValeFX: a class_name from a sibling script is not in the global
## cache on a --script run, so the type annotation would not resolve even
## though the preload above works.
var _fx: Node3D
var _root: Node3D
var _cams: Array[Camera3D] = []
var _frame := 0
var _prev := PackedByteArray()

## Alternating states for the timing phase.
## -1.0 means "take the FX node out of the tree entirely", which is the only
## way to get a draw-call baseline: an emitter with emitting=false still
## submits its pass.
var _plan: Array[float] = [1.0, 0.0, 1.0, 0.0, 1.0, 0.0, -1.0]
var _step := -1
var _settle := 0.0
var _sample := 0.0
var _ticks := 0
var _ms: Array[float] = []
var _calls: Array[int] = []


func _initialize() -> void:
	ShotWindow.park()
	# Uncapped, or every number below is 60 and the comparison is meaningless.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	_root = Node3D.new()
	_root.name = "Probe"
	get_root().add_child(_root)

	var light: Node3D = LIGHT.new()
	light.name = "Light"
	_root.add_child(light)
	_root.add_child(_ground())

	var props: Array = []
	for spec in HERO:
		var made := _spawn(String(spec[0]), spec[1], float(spec[2]))
		if made.is_empty():
			quit(1)
			return
		props.append(made)

	_fx = FX.new()
	_fx.name = "FX"
	_root.add_child(_fx)
	_fx.setup(props)

	# The API, exercised. `amount` must be identical either side of every
	# set_density() call -- that is the whole pooling claim, and it is
	# checkable rather than assertable.
	var pool := _pool_of()
	print("[FXP] emitters %d  pool %s" % [_fx.emitter_count(), str(pool)])
	for d in [1.0, 2.0, 0.5, 0.0, 1.0]:
		_fx.set_density(d)
		var ok := _pool_of() == pool
		print("[FXP] density %.2f -> active_count %d  amount unchanged: %s"
			% [d, _fx.active_count(), "ok" if ok else "FAIL"])
		if not ok:
			printerr("[FXP] FAIL: set_density() reallocated the GPU pool")
			quit(1)
			return

	_cams.append(_camera(7.2, Vector3(0.35, 1.15, 0.0)))
	_cams.append(_camera(4.6, Vector3(-2.5, 1.15, 0.7)))
	_cams.append(_camera(17.4, Vector3(0.0, 0.9, 0.0)))
	for c in _cams:
		_root.add_child(c)
	_cams[0].current = true


func _pool_of() -> Array:
	var out: Array[int] = []
	for e in _fx.get_children():
		out.append((e as GPUParticles3D).amount)
	return out


func _spawn(aid: String, at: Vector3, yaw: float) -> Dictionary:
	var path := LIB % aid.replace("/", "__")
	if not ResourceLoader.exists(path):
		printerr("[FXP] FAIL: missing %s" % path)
		return {}
	var packed: PackedScene = load(path)
	var node: Node3D = packed.instantiate()
	_root.add_child(node)
	node.position = at
	node.rotation.y = deg_to_rad(yaw)
	return {"id": aid, "node": node, "pos": node.position}


## Every smoke and canopy source data/vale.json actually contains, scattered
## over the real map footprint. Placement does not matter -- the pool sizes and
## the on-screen particle count do.
func _village() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	var props: Array = []
	for aid in CENSUS:
		for i in int(CENSUS[aid]):
			var at := Vector3(rng.randf_range(-MAP.x, MAP.x) * 0.5, 0.0,
				rng.randf_range(-MAP.y, MAP.y) * 0.5)
			var made := _spawn(String(aid), at, rng.randf_range(0.0, 360.0))
			if not made.is_empty():
				props.append(made)
	return props


func _ground() -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = Vector2(44, 44)
	var m := StandardMaterial3D.new()
	# The grass value out of kit.py init_materials(), so the smoke is judged
	# against the key the real shot has.
	m.albedo_color = Color(0.380, 0.740, 0.220)
	m.roughness = 0.58
	pm.material = m
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = pm
	return mi


func _camera(dist: float, target: Vector3) -> Camera3D:
	var cam := Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = 2.0 * rad_to_deg(atan(18.0 / CAM_LENS))
	cam.position = target + CAM_DIR.normalized() * dist
	cam.look_at_from_position(cam.position, target, Vector3.UP)
	return cam


func _process(delta: float) -> bool:
	_frame += 1
	if _step < 0:
		if _frame == 90:
			_grab("fx_hero")
		elif _frame == 112:
			# Same camera, 22 frames later: the pair that proves the particles
			# are simulating and not a still picture of a particle system.
			_grab("fx_hero_b")
			_cams[0].current = false
			_cams[1].current = true
		elif _frame == 140:
			_grab("fx_tree")
			_cams[1].current = false
			_cams[2].current = true
		elif _frame == 180:
			_grab("fx_play")
			# Now up to the whole village's worth of sources, and rebuilt
			# through the public API rather than by reaching inside.
			_fx.setup(_village())
			print("[FXP] village pool %s  active_count %d"
				% [str(_pool_of()), _fx.active_count()])
			_step = 0
			_fx.set_density(_plan[0])
		return false

	if _settle < SETTLE:
		_settle += delta
		return false
	_sample += delta
	_ticks += 1
	if _sample < WINDOW:
		return false

	var ms := 1000.0 * _sample / float(_ticks)
	var calls := int(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	print("[FXP] %-16s %8.1f fps  %6.3f ms  draw calls %d"
		% ["FX node removed" if _plan[_step] < 0.0
		   else "density %.1f" % _plan[_step], 1000.0 / ms, ms, calls])
	_ms.append(ms)
	_calls.append(calls)
	_settle = 0.0
	_sample = 0.0
	_ticks = 0
	_step += 1
	if _step < _plan.size():
		if _plan[_step] < 0.0:
			_root.remove_child(_fx)
			_fx.queue_free()
		else:
			_fx.set_density(_plan[_step])
		return false

	var on := 0.0
	var off := 0.0
	var n := 0
	for i in _ms.size():
		if _plan[i] > 0.0:
			on += _ms[i]
		elif _plan[i] == 0.0:
			off += _ms[i]
			n += 1
	on /= float(n)
	off /= float(n)
	print("[FXP] mean ON %.3f ms (%.0f fps), mean OFF %.3f ms (%.0f fps)"
		% [on, 1000.0 / on, off, 1000.0 / off])
	print("[FXP] FX at authored density, village scale: %+.3f ms/frame" % (on - off))
	print("[FXP] draw calls: %d with FX, %d with the FX node removed -> %d for %d emitters"
		% [_calls[0], _calls[_calls.size() - 1],
		   _calls[0] - _calls[_calls.size() - 1], 3])
	quit(0)
	return true


func _grab(label: String) -> void:
	# No screen, no picture -- and saying so rather than throwing, because a
	# throw in here aborts _process before the quit() that ends the probe.
	if not ShotWindow.can_shoot():
		print("[FXP] no display: %s not photographed" % label)
		return
	var img := get_root().get_texture().get_image()
	var data := img.get_data()
	if data == _prev:
		printerr("[FXP] FAIL: %s is bit-identical to the last grab. " % label
			+ "Nothing in this scene moves but the particles, so either the "
			+ "swapchain never presented or GPUParticles3D is not simulating "
			+ "under GL Compatibility. Refusing to write.")
		quit(1)
		return
	_prev = data
	var lo := 1.0
	var hi := 0.0
	var sum := 0.0
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			lo = minf(lo, l)
			hi = maxf(hi, l)
			sum += l
			n += 1
	var mean: float = sum / float(maxi(n, 1))
	var path := OUT + label + ".png"
	img.save_png(ProjectSettings.globalize_path(path))
	print("[FXP] %s  frame %d  luma %.3f (%.3f..%.3f)%s"
		% [path, _frame, mean, lo, hi,
		   "   ** BLANK **" if hi - lo < 0.05 else ""])
