extends SceneTree

## Throwaway harness for scripts/fx.gd: a scrap of village, the real light rig,
## the real FX, two screenshots and a measured frame cost.
##
## NOT --headless -- get_root().get_texture() needs a real swapchain.
##
##   godot --path . --resolution 1280x800 --audio-driver Dummy \
##         --script res://tools/fx_probe.gd
##
## The stale-frame guard does double duty here. In this scene NOTHING moves
## except the particles, so two captures that come back bit-identical mean
## either the swapchain never presented or GPUParticles3D is not simulating
## under GL Compatibility. Either way the run is worthless and it fails loudly,
## which is the whole reason the guard exists.

const ShotWindow := preload("res://tools/shot_window.gd")
const FX := preload("res://scripts/fx.gd")
const LIGHT := preload("res://scripts/vale_light.gd")
const OUT := "res://shots/"
const LIB := "res://assets/library/%s.glb"

## Roughly the game camera: 35 mm on a 36 mm frame, KEEP_WIDTH, the hero angle
## out of vale_root.gd. Two distances, because an effect that reads at 7 m and
## vanishes at 17 m has failed the only camera the player has.
const CAM_DIR := Vector3(-0.72, 0.88, 1.00)
const CAM_LENS := 35.0

const PROPS := [
	["Buildings/cottage", Vector3(0.0, 0.0, 0.0), 18.0],
	["Buildings/hut", Vector3(2.7, 0.0, 0.5), -35.0],
	["Nature/tree", Vector3(-2.5, 0.0, 0.7), 0.0],
	["Nature/tree", Vector3(3.9, 0.0, -1.4), 40.0],
	["Nature/pine", Vector3(-3.6, 0.0, -1.8), 0.0],
]

## Node3D, not ValeFX: a class_name from a sibling script is not in the global
## cache on a --script run, so the type annotation would not resolve even
## though the preload above works.
var _fx: Node3D
var _cams: Array[Camera3D] = []
var _frame := 0
var _prev := PackedByteArray()
var _shots := 0
var _win_frames := 0
var _win_time := 0.0
var _phase := 0
var _on_fps := 0.0
var _off_fps := 0.0
var _on_calls := 0
var _off_calls := 0


func _initialize() -> void:
	ShotWindow.park()
	# Uncapped, or every number below is 60 and the comparison is meaningless.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	var root := Node3D.new()
	root.name = "Probe"
	get_root().add_child(root)

	var light: Node3D = LIGHT.new()
	light.name = "Light"
	root.add_child(light)
	root.add_child(_ground())

	var props: Array = []
	for spec in PROPS:
		var aid: String = spec[0]
		var path := LIB % aid.replace("/", "__")
		if not ResourceLoader.exists(path):
			printerr("[FXP] FAIL: missing %s" % path)
			quit(1)
			return
		var packed: PackedScene = load(path)
		var node: Node3D = packed.instantiate()
		root.add_child(node)
		node.position = spec[1]
		node.rotation.y = deg_to_rad(float(spec[2]))
		props.append({"id": aid, "node": node, "pos": node.position})

	_fx = FX.new()
	_fx.name = "FX"
	root.add_child(_fx)
	_fx.setup(props)

	# The API, exercised. `amount` must be identical either side of every
	# set_density() call -- that is the pooling claim, and it is checkable.
	var pool: Array[int] = []
	for e in _fx.get_children():
		pool.append((e as GPUParticles3D).amount)
	print("[FXP] emitters %d  pool %s" % [_fx.emitter_count(), str(pool)])
	for d in [1.0, 2.0, 0.5, 0.0, 1.0]:
		_fx.set_density(d)
		var now: Array[int] = []
		for e in _fx.get_children():
			now.append((e as GPUParticles3D).amount)
		var ok := now == pool
		print("[FXP] density %.2f -> active_count %d  amount unchanged: %s"
			% [d, _fx.active_count(), "ok" if ok else "FAIL"])
		if not ok:
			printerr("[FXP] FAIL: set_density() reallocated the pool")
			quit(1)
			return

	_cams.append(_camera(7.2, Vector3(0.35, 1.15, 0.0)))
	_cams.append(_camera(17.4, Vector3(0.0, 0.9, 0.0)))
	for c in _cams:
		root.add_child(c)
	_cams[0].current = true


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
	match _phase:
		0:
			if _frame == 90:
				_grab("fx_hero")
			elif _frame == 112:
				# Same camera, 22 frames later. This is the pair that proves
				# the particles are SIMULATING: nothing else in the scene
				# moves, so a bit-identical result is a dead particle system.
				_grab("fx_hero_b")
				_cams[0].current = false
				_cams[1].current = true
			elif _frame == 150:
				_grab("fx_play")
				_phase = 1
				_win_frames = 0
				_win_time = 0.0
		1:
			# FX on, authored density.
			_win_frames += 1
			_win_time += delta
			if _win_frames >= 180:
				_on_fps = float(_win_frames) / maxf(_win_time, 0.0001)
				_on_calls = int(RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
				print("[FXP] FX ON   %.1f fps (Engine %d)  draw calls %d"
					% [_on_fps, Engine.get_frames_per_second(), _on_calls])
				_fx.set_density(0.0)
				_phase = 2
				_win_frames = 0
				_win_time = 0.0
		2:
			_win_frames += 1
			_win_time += delta
			if _win_frames >= 180:
				_off_fps = float(_win_frames) / maxf(_win_time, 0.0001)
				_off_calls = int(RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
				print("[FXP] FX OFF  %.1f fps (Engine %d)  draw calls %d"
					% [_off_fps, Engine.get_frames_per_second(), _off_calls])
				print("[FXP] cost: %.2f ms/frame, %d draw calls, %d particles"
					% [(1000.0 / _on_fps) - (1000.0 / _off_fps),
					   _on_calls - _off_calls, _fx.emitter_count()])
				quit(0)
				return true
	return false


func _grab(label: String) -> void:
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
	_shots += 1
