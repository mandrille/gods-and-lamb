extends SceneTree

## What a follower actually costs, measured rather than reported.
##
## Run WINDOWED (not --headless): --headless swaps in the dummy rendering
## driver, so every draw call, primitive and GPU millisecond reads zero and the
## only honest number left is script time.
##
##     Godot_v4.7-stable_win64_console.exe --path godot --script tools/perf_followers.gd
##
## THE SCHEDULE IS THE POINT. A single "measure at 0, then measure at 400" run
## is worthless here: with nothing on screen this project runs at four figures
## of fps and the machine's own clock drift over a few seconds is larger than
## the effect being measured. That is how an earlier pass on this project
## measured a NEGATIVE cost for adding particles.
##
## So every treatment is sandwiched: A T A T A T A, baseline before AND after,
## three times, spread across the whole run. Each treatment window is scored
## against the mean of the baseline window immediately before it and the one
## immediately after it, which cancels drift that is linear in time. The three
## repeats are reported individually so a reader can see whether the number is
## stable or noise.
##
## Followers are POOLED, not spawned and freed per cell. Reparenting a node to
## a holder outside the tree removes it from _process, from animation and from
## the render server as thoroughly as freeing it, and costs microseconds
## instead of a GLB instantiation. Static memory is therefore measured
## separately, during pool construction, where it is meaningful.
##
## TRAPS PAID FOR IN RUN 1 OF THIS FILE, both of which made the first numbers
## worthless:
##
## 1. `spawn_follower()` adds to the tree, so after building the pool the
##    followers were ALL active while `_active` still said 0. `_set_active(0)`
##    was a no-op and the first repeat measured a village of 800 no matter what
##    the cell said. `_active` is now seeded from the pool size.
## 2. `Performance.TIME_PROCESS` / `TIME_PHYSICS_PROCESS` are updated ONCE PER
##    SECOND and hold the MAX over that second, not a mean. Averaging them over
##    a half-second window reads back the previous cell's value. They are now
##    sampled only in a dedicated pass with holds longer than a second.

const FOLLOWER := preload("res://scripts/follower.gd")
const SCENE_PATH := "res://scenes/vale.tscn"

const POOL_MAX := 800
const POOL_CHUNK := 25
const MEM_MARKS := [0, 25, 50, 100, 200, 400, 800]

const REPS := 3
const WINDOW_SEC := 0.50
const MIN_FRAMES := 24          ## a 0.5 s window at 113 ms/frame is 5 samples
const SETTLE_SEC := 0.30
const SETTLE_FRAMES := 12

## Camera framings. "near" is the shipped dist (camera_rig.dist default 30),
## focused on the map centre so the run is deterministic; "wide" is dist_max,
## which puts the whole village inside the frustum but pushes most of it out of
## the directional shadow's range. The pair is what culling and shadow range
## are actually buying.
const CAM_NEAR := 30.0
const CAM_WIDE := 70.0

## Attribution modes, applied to the ACTIVE followers only.
##   full        everything on
##   no_anim     AnimationMixer.active = false. The skeleton keeps its last
##               pose, so the mesh is still bound to a skin and still drawn --
##               this isolates the moving skeleton, not the skin binding.
##   anim_half   the mixer is driven MANUALLY, advanced on every other frame.
##               What a halved AnimationMixer update rate would cost.
##   no_proc     Follower._process off: no lerp, no atan2, no transform write.
##   hidden      visible = false: no draw, no cull test, no skinned submission.
##               Script and animation still run, so this is the ceiling on
##               "don't draw followers that are off screen".
##   no_shadow   cast_shadow = OFF on the mesh. Everything else unchanged.
##   merged      the 8/11 material surfaces collapsed to ONE vertex-coloured
##               surface, built at runtime from the same arrays. Measurement
##               only -- nothing is written back to the asset.
##   merged_ns   merged AND no_shadow.
##   inert       anim, process and visibility all off: what a follower costs
##               purely by existing as a node in the tree.

var _host: Node = null
var _park: Node3D = null
var _pool: Array = []
var _anims: Dictionary = {}
var _meshes: Dictionary = {}      ## follower -> MeshInstance3D
var _orig_skin: Dictionary = {}   ## follower -> its authored Skin
var _orig_mesh: Dictionary = {}   ## follower -> its authored Mesh
var _merged: Dictionary = {}      ## source Mesh -> merged ArrayMesh
var _rebuilt: Dictionary = {}     ## source Mesh -> same surfaces, rebuilt
var _one_mat: Material = null     ## an AUTHORED material, for the controls
var _active := 0
var _mode := "full"
var _cam := "near"
var _half_tick := false

var _phase := "boot"
var _boot_frames := 0
var _mem: Dictionary = {}
var _pool_us := 0

var _cells: Array = []
var _cell := 0
var _cell_phase := "settle"
var _clock := 0.0
var _settled := 0
var _last_us := 0
var _acc: Dictionary = {}
var _rid: RID
var _run_us := 0

## The slow second pass: long holds so the 1 Hz engine monitors are readable.
var _mon: Array = []
var _mon_i := 0
const MON_HOLD := 2.6


func _initialize() -> void:
	# Deterministic: spawn_follower() calls randf() for the phase offset and
	# the speed jitter, so an unseeded run puts a different crowd on the paths
	# every time and the draw counts move with it.
	seed(20260901)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		printerr("[PERF] cannot load %s" % SCENE_PATH)
		quit(1)
		return
	_host = packed.instantiate()
	root.add_child(_host)
	_rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_rid, true)
	_park = Node3D.new()
	_park.name = "Parked"
	print("[PERF] renderer=%s vsync=disabled max_fps=0 window=%s msaa=%s shadow_filter=%s scaling_3d=%s"
		% [ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		   str(DisplayServer.window_get_size()),
		   str(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d")),
		   str(ProjectSettings.get_setting(
			   "rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality")),
		   str(ProjectSettings.get_setting("rendering/scaling_3d/scale"))])
	print("[PERF] gpu=%s / %s" % [RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_vendor()])


func _process(delta: float) -> bool:
	match _phase:
		"boot":
			_boot_frames += 1
			if _boot_frames >= 10:
				_start_pool()
			return false
		"pool":
			_step_pool()
			return false
		"run":
			return _step_run(delta)
		"monitors":
			return _step_monitors(delta)
	return true


# -- pool ------------------------------------------------------------------

func _start_pool() -> void:
	_mem[0] = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	# The scene's own six authored walkers join the pool, so that "0 followers"
	# in this harness really is zero and not six.
	for c in _host.get_children():
		if c.get_script() == FOLLOWER:
			_pool.append(c)
	_pool_us = Time.get_ticks_usec()
	print("[PERF] scene built; %d authored followers adopted into the pool"
		% _pool.size())
	_phase = "pool"


func _step_pool() -> void:
	var n := 0
	while n < POOL_CHUNK and _pool.size() < POOL_MAX:
		_host.spawn_follower()
		var made: Array = _host._spawned
		if made.size() == 0:
			break
		var f: Node = made[made.size() - 1]
		if not _pool.has(f):
			_pool.append(f)
		n += 1
	for mark in MEM_MARKS:
		if int(mark) > 0 and _pool.size() >= int(mark) and not _mem.has(mark):
			_mem[mark] = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	if _pool.size() < POOL_MAX and n > 0:
		return

	var spent := Time.get_ticks_usec() - _pool_us
	print("[PERF] pool: %d followers instantiated in %.0f ms (%.3f ms each)"
		% [_pool.size(), spent / 1000.0,
		   (spent / 1000.0) / float(max(_pool.size() - 6, 1))])
	for f in _pool:
		_anims[f] = _find_anim(f)
		var mi := _find_mesh(f)
		_meshes[f] = mi
		if mi != null:
			_orig_mesh[f] = mi.mesh
			_orig_skin[f] = mi.skin
			if not _merged.has(mi.mesh):
				_merged[mi.mesh] = _merge_mesh(mi.mesh)
				_rebuilt[mi.mesh] = _rebuild_mesh(mi.mesh)
			if _one_mat == null:
				_one_mat = mi.mesh.surface_get_material(0)
	_describe_unit()
	# THE BUG FROM RUN 1: spawn_follower() already put every one of these in
	# the tree, so _active is 800, not 0. Seed it before parking.
	_active = _pool.size()
	_set_active(0)
	_apply_cam("near")
	_build_schedule()
	_phase = "run"
	_run_us = Time.get_ticks_usec()
	_begin_cell()


func _describe_unit() -> void:
	var seen := {}
	for f in _pool:
		var mi: MeshInstance3D = _meshes.get(f, null)
		if mi == null or mi.mesh == null:
			continue
		var key := str(mi.mesh.get_rid())
		if seen.has(key):
			seen[key]["n"] = int(seen[key]["n"]) + 1
			continue
		var tris := 0
		for s in mi.mesh.get_surface_count():
			var a := mi.mesh.surface_get_arrays(s)
			var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			tris += ix.size() / 3
		var merged: ArrayMesh = _merged.get(mi.mesh, null)
		seen[key] = {"n": 1, "surf": mi.mesh.get_surface_count(), "tris": tris,
			"merged_surf": merged.get_surface_count() if merged != null else -1}
	for k in seen:
		var e: Dictionary = seen[k]
		print("[PERF] follower mesh: %d instances, %d surfaces, %d tris, merged -> %d surface(s)"
			% [int(e["n"]), int(e["surf"]), int(e["tris"]), int(e["merged_surf"])])


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var found := _find_anim(c)
		if found != null:
			return found
	return null


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return n
	for c in n.get_children():
		var found := _find_mesh(c)
		if found != null:
			return found
	return null


## Collapse every material surface into one vertex-coloured surface.
##
## This is a MEASUREMENT, not a proposed patch: it answers "what would the
## folk cost if they were one surface instead of eight" without touching the
## asset. The skin is untouched -- ARRAY_BONES indexes the same skeleton -- so
## the merged mesh animates identically.
func _merge_mesh(src: Mesh) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var idx := PackedInt32Array()
	var per := 0
	for s in src.get_surface_count():
		var a: Array = src.surface_get_arrays(s)
		var sv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		if sv.size() == 0:
			continue
		var base := verts.size()
		var tint := Color(1, 1, 1, 1)
		var use_vc := false
		var m: Material = src.surface_get_material(s)
		if m is StandardMaterial3D:
			var sm := m as StandardMaterial3D
			tint = sm.albedo_color
			use_vc = sm.vertex_color_use_as_albedo
		verts.append_array(sv)
		if a[Mesh.ARRAY_NORMAL] != null:
			norms.append_array(a[Mesh.ARRAY_NORMAL] as PackedVector3Array)
		var src_col: PackedColorArray = PackedColorArray()
		if a[Mesh.ARRAY_COLOR] != null:
			src_col = a[Mesh.ARRAY_COLOR]
		for i in sv.size():
			var c := tint
			if use_vc and i < src_col.size():
				c = Color(tint.r * src_col[i].r, tint.g * src_col[i].g,
					tint.b * src_col[i].b, tint.a * src_col[i].a)
			cols.append(c)
		if a[Mesh.ARRAY_BONES] != null:
			var sb: PackedInt32Array = a[Mesh.ARRAY_BONES]
			per = sb.size() / sv.size()
			bones.append_array(sb)
			weights.append_array(a[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array)
		var si: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		for i in si.size():
			idx.append(si[i] + base)
	if verts.size() == 0 or idx.size() == 0:
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	if norms.size() == verts.size():
		arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	if bones.size() == verts.size() * per and per > 0:
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = idx
	var flags := 0
	if per == 8:
		flags = Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	var first := src.surface_get_material(0)
	if first is StandardMaterial3D:
		mat.roughness = (first as StandardMaterial3D).roughness
		mat.metallic = (first as StandardMaterial3D).metallic
	out.surface_set_material(0, mat)
	return out


## THE CONTROL for `merged`. Same rebuild path, same vertex format, same
## runtime-built ArrayMesh -- but the surfaces are NOT collapsed. If this costs
## what `full` costs, the win in `merged` is the surface count and the fix is
## the material split. If it costs what `merged` costs, the win was never about
## surfaces at all and the fix is an import setting, which is a very different
## conversation.
func _rebuild_mesh(src: Mesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var a: Array = src.surface_get_arrays(s)
		var flags := 0
		var sv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		if a[Mesh.ARRAY_BONES] != null:
			var sb: PackedInt32Array = a[Mesh.ARRAY_BONES]
			if sv.size() > 0 and sb.size() / sv.size() == 8:
				flags = Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, flags)
		out.surface_set_material(s, src.surface_get_material(s))
	return out


# -- activation and modes --------------------------------------------------

func _set_active(n: int) -> void:
	var want: int = clampi(n, 0, _pool.size())
	while _active < want:
		var f: Node = _pool[_active]
		if f.get_parent() == _park:
			_park.remove_child(f)
		if f.get_parent() == null:
			_host.add_child(f)
		_active += 1
	while _active > want:
		_active -= 1
		var f: Node = _pool[_active]
		if f.get_parent() != null:
			f.get_parent().remove_child(f)
		_park.add_child(f)


func _apply_mode(mode: String) -> void:
	var anim := mode != "no_anim" and mode != "inert"
	var manual := mode == "anim_half"
	var proc := mode != "no_proc" and mode != "inert"
	var vis := mode != "hidden" and mode != "inert"
	var shadow := mode != "no_shadow" and mode != "merged_ns"
	var merged := mode == "merged" or mode == "merged_ns"
	var rebuilt := mode == "rebuilt"
	# one_mat: the AUTHORED mesh, 9 surfaces, forced through a SINGLE material.
	# merged_authored: the MERGED mesh, 1 surface, forced through one of the
	# authored materials. Between them they prove the axis is the surface count
	# and not the replacement material this harness builds.
	var over: Material = null
	if mode == "one_mat" or mode == "merged_authored":
		over = _one_mat
	var skin := mode != "no_skin"
	for i in _active:
		var f: Node = _pool[i]
		f.set_process(proc)
		(f as Node3D).visible = vis
		var mi: MeshInstance3D = _meshes.get(f, null)
		if mi != null:
			var want_mesh: Mesh = _orig_mesh[f]
			if merged and _merged.get(want_mesh, null) != null:
				want_mesh = _merged[want_mesh]
			elif rebuilt and _rebuilt.get(want_mesh, null) != null:
				want_mesh = _rebuilt[want_mesh]
			elif mode == "merged_authored" and _merged.get(want_mesh, null) != null:
				want_mesh = _merged[want_mesh]
			if mi.material_override != over:
				mi.material_override = over
			if mi.mesh != want_mesh:
				mi.mesh = want_mesh
			mi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			var want_skin: Skin = _orig_skin[f] if skin else null
			if mi.skin != want_skin:
				mi.skin = want_skin
		var ap: AnimationPlayer = _anims.get(f, null)
		if ap == null:
			continue
		ap.callback_mode_process = (AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			if manual else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE)
		ap.active = anim
		if anim and not ap.is_playing():
			ap.play()
	_mode = mode


func _tick_manual(delta: float) -> void:
	# Half rate: advance by two frames' worth on every other frame. The clip
	# then plays at the right ground speed with half the pose updates, which is
	# exactly what a lowered AnimationMixer update rate would do.
	_half_tick = not _half_tick
	if not _half_tick:
		return
	for i in _active:
		var ap: AnimationPlayer = _anims.get(_pool[i], null)
		if ap != null:
			ap.advance(delta * 2.0)


func _apply_cam(which: String) -> void:
	var rig: Node = _host.rig
	if rig == null:
		return
	rig.focus = Vector3.ZERO
	rig.dist = CAM_NEAR if which == "near" else CAM_WIDE
	rig._place()
	_cam = which


# -- schedule --------------------------------------------------------------

func _cell_of(n: int, mode: String, cam: String) -> Dictionary:
	return {"n": n, "mode": mode, "cam": cam}


func _build_schedule() -> void:
	if "--quick" in OS.get_cmdline_args():
		_build_quick()
		return
	var t1: Array = []
	for n in [25, 50, 100, 200, 400, 800]:
		t1.append(_cell_of(int(n), "full", "near"))
	for n in [25, 50, 100, 200, 400, 800]:
		t1.append(_cell_of(int(n), "merged", "near"))
	for m in ["rebuilt", "no_anim", "anim_half", "no_proc", "hidden",
			"no_shadow", "merged_ns", "inert"]:
		t1.append(_cell_of(400, String(m), "near"))
	t1.append(_cell_of(100, "no_shadow", "near"))
	var t2: Array = []
	for n in [100, 400]:
		t2.append(_cell_of(int(n), "full", "wide"))
		t2.append(_cell_of(int(n), "merged", "wide"))

	for pass_t in [t1, t2]:
		var cam: String = String((pass_t[0] as Dictionary)["cam"])
		for _r in REPS:
			for t in pass_t:
				_cells.append(_cell_of(0, "full", cam))
				_cells.append(t)
			_cells.append(_cell_of(0, "full", cam))
	# The engine's own monitors, held long enough to be readable.
	for n in [0, 100, 400]:
		_mon.append(_cell_of(int(n), "full", "near"))
	for n in [100, 400, 800]:
		_mon.append(_cell_of(int(n), "merged", "near"))
	print("[PERF] schedule: %d windows, >= %.2f s and >= %d frames each (settle %.2f s / %d frames), then %d monitor holds of %.1f s"
		% [_cells.size(), WINDOW_SEC, MIN_FRAMES, SETTLE_SEC, SETTLE_FRAMES,
		   _mon.size(), MON_HOLD])


## The material controls only. Short enough to re-run while arguing.
func _build_quick() -> void:
	var t: Array = []
	for m in ["full", "rebuilt", "one_mat", "merged", "merged_authored"]:
		t.append(_cell_of(400, String(m), "near"))
	for _r in REPS:
		for c in t:
			_cells.append(_cell_of(0, "full", "near"))
			_cells.append(c)
		_cells.append(_cell_of(0, "full", "near"))
	_mon.append(_cell_of(400, "full", "near"))
	_mon.append(_cell_of(400, "merged", "near"))
	print("[PERF] QUICK schedule: %d windows" % _cells.size())


func _begin_cell() -> void:
	var c: Dictionary = _cells[_cell]
	if String(c["cam"]) != _cam:
		_apply_cam(String(c["cam"]))
	_set_active(int(c["n"]))
	_apply_mode(String(c["mode"]))
	_cell_phase = "settle"
	_clock = 0.0
	_settled = 0
	_acc = {"frames": 0, "us": 0, "ms2": 0.0, "draw": 0.0, "obj": 0.0,
		"prim": 0.0, "rcpu": 0.0, "rgpu": 0.0}


func _step_run(delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if _mode == "anim_half":
		_tick_manual(delta)
	if _cell_phase == "settle":
		_clock += delta
		_settled += 1
		if _clock >= SETTLE_SEC and _settled >= SETTLE_FRAMES:
			_cell_phase = "measure"
			_clock = 0.0
			_last_us = now
		return false

	var dt := now - _last_us
	_last_us = now
	_clock += delta
	var a: Dictionary = _acc
	a["frames"] = int(a["frames"]) + 1
	a["us"] = int(a["us"]) + dt
	var ms := dt / 1000.0
	a["ms2"] = float(a["ms2"]) + ms * ms
	a["draw"] = float(a["draw"]) + Performance.get_monitor(
		Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	a["obj"] = float(a["obj"]) + Performance.get_monitor(
		Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	a["prim"] = float(a["prim"]) + Performance.get_monitor(
		Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	a["rcpu"] = float(a["rcpu"]) + RenderingServer.viewport_get_measured_render_time_cpu(_rid)
	a["rgpu"] = float(a["rgpu"]) + RenderingServer.viewport_get_measured_render_time_gpu(_rid)

	if _clock < WINDOW_SEC or int(a["frames"]) < MIN_FRAMES:
		return false

	_finish_cell()
	_cell += 1
	if _cell >= _cells.size():
		_report()
		_phase = "monitors"
		_mon_i = 0
		_begin_monitor()
		return false
	_begin_cell()
	return false


func _finish_cell() -> void:
	var a: Dictionary = _acc
	var frames: int = int(a["frames"])
	var fdiv := float(max(frames, 1))
	var mean_ms := (float(a["us"]) / fdiv) / 1000.0
	var var_ms := float(a["ms2"]) / fdiv - mean_ms * mean_ms
	var c: Dictionary = _cells[_cell]
	c["frames"] = frames
	c["ms"] = mean_ms
	c["sd"] = sqrt(max(var_ms, 0.0))
	c["draw"] = float(a["draw"]) / fdiv
	c["obj"] = float(a["obj"]) / fdiv
	c["prim"] = float(a["prim"]) / fdiv
	c["rcpu"] = float(a["rcpu"]) / fdiv
	c["rgpu"] = float(a["rgpu"]) / fdiv
	print("[CELL] %3d/%d %-5s n=%-4d %-9s frames=%-5d ms=%8.4f sd=%6.4f draw=%6.0f obj=%6.0f prim=%9.0f rcpu=%7.3f rgpu=%7.3f"
		% [_cell + 1, _cells.size(), c["cam"], int(c["n"]), c["mode"], frames,
		   c["ms"], c["sd"], c["draw"], c["obj"], c["prim"], c["rcpu"], c["rgpu"]])


# -- the 1 Hz engine monitors ----------------------------------------------

func _begin_monitor() -> void:
	var c: Dictionary = _mon[_mon_i]
	_set_active(int(c["n"]))
	_apply_mode(String(c["mode"]))
	_clock = 0.0


func _step_monitors(delta: float) -> bool:
	_clock += delta
	if _clock < MON_HOLD:
		return false
	var c: Dictionary = _mon[_mon_i]
	print("[MON ] n=%-4d %-9s fps=%-6d TIME_PROCESS=%7.3f ms  TIME_PHYSICS_PROCESS=%7.3f ms  MEMORY_STATIC=%d"
		% [int(c["n"]), c["mode"], Engine.get_frames_per_second(),
		   Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		   Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		   int(Performance.get_monitor(Performance.MEMORY_STATIC))])
	_mon_i += 1
	if _mon_i >= _mon.size():
		print("[MON ] note: TIME_PROCESS/TIME_PHYSICS_PROCESS update once per")
		print("[MON ] second and hold the MAX over that second, not a mean.")
		# The parked pool is outside the tree, so nothing else frees it and the
		# exit is otherwise buried under 800 leaked skeletons of GL error spam.
		_park.free()
		return true
	_begin_monitor()
	return false


# -- report ----------------------------------------------------------------

func _key(c: Dictionary) -> String:
	return "%s|%s|%d" % [c["cam"], c["mode"], int(c["n"])]


## Baseline immediately before and after a treatment cell, same camera. The
## sandwich is what makes the number a difference and not a drift.
func _sandwich(i: int) -> float:
	var cam: String = String((_cells[i] as Dictionary)["cam"])
	var before := -1
	var after := -1
	var j := i - 1
	while j >= 0:
		var c: Dictionary = _cells[j]
		if int(c["n"]) == 0 and String(c["cam"]) == cam:
			before = j
			break
		j -= 1
	j = i + 1
	while j < _cells.size():
		var c2: Dictionary = _cells[j]
		if int(c2["n"]) == 0 and String(c2["cam"]) == cam:
			after = j
			break
		j += 1
	if before < 0 and after < 0:
		return NAN
	if before < 0:
		return float((_cells[after] as Dictionary)["ms"])
	if after < 0:
		return float((_cells[before] as Dictionary)["ms"])
	return 0.5 * (float((_cells[before] as Dictionary)["ms"])
		+ float((_cells[after] as Dictionary)["ms"]))


func _report() -> void:
	var order: Array = []
	var by: Dictionary = {}
	for i in _cells.size():
		var c: Dictionary = _cells[i]
		var k := _key(c)
		if not by.has(k):
			by[k] = {"cells": [], "delta": []}
			order.append(k)
		(by[k]["cells"] as Array).append(c)
		if int(c["n"]) > 0:
			(by[k]["delta"] as Array).append(float(c["ms"]) - _sandwich(i))

	print("")
	print("=== PERF FOLLOWERS =========================================================")
	print("measure phase %.1f s" % ((Time.get_ticks_usec() - _run_us) / 1000000.0))
	print("")
	print("MEMORY_STATIC during pool construction:")
	for mark in MEM_MARKS:
		if not _mem.has(mark):
			continue
		var v: int = int(_mem[mark])
		var per := 0.0
		if int(mark) > 0:
			per = float(v - int(_mem[0])) / float(mark)
		print("  n=%-4d  %12d B   +%9d from n=0   %8.0f B/follower"
			% [int(mark), v, v - int(_mem[0]), per])
	print("")
	print("%-5s %-9s %5s | %9s %8s | %9s %9s | %7s %7s %11s %8s | %7s %7s"
		% ["cam", "mode", "n", "ms", "sd", "d_ms", "per_flr", "draw", "obj",
		   "prim", "dr/flr", "rcpu_ms", "rgpu_ms"])
	for k in order:
		var g: Dictionary = by[k]
		var cells: Array = g["cells"]
		var ms := 0.0
		var sd := 0.0
		var draw := 0.0
		var obj := 0.0
		var prim := 0.0
		var rcpu := 0.0
		var rgpu := 0.0
		for c in cells:
			ms += float(c["ms"])
			sd += float(c["sd"])
			draw += float(c["draw"])
			obj += float(c["obj"])
			prim += float(c["prim"])
			rcpu += float(c["rcpu"])
			rgpu += float(c["rgpu"])
		var cn := float(cells.size())
		var first: Dictionary = cells[0]
		var n := int(first["n"])
		var deltas: Array = g["delta"]
		var dm := 0.0
		for d in deltas:
			dm += float(d)
		if deltas.size() > 0:
			dm /= float(deltas.size())
		var per := 0.0
		var dpf := 0.0
		if n > 0:
			per = dm / float(n)
			var base_draw := _base_draw(String(first["cam"]))
			dpf = (draw / cn - base_draw) / float(n)
		print("%-5s %-9s %5d | %9.4f %8.4f | %9.4f %9.5f | %7.0f %7.0f %11.0f %8.2f | %7.3f %7.3f"
			% [first["cam"], first["mode"], n, ms / cn, sd / cn, dm, per,
			   draw / cn, obj / cn, prim / cn, dpf, rcpu / cn, rgpu / cn])
	print("")
	print("per-window deltas (ms above the sandwiching baseline), one per rep:")
	for k in order:
		var deltas: Array = by[k]["delta"]
		if deltas.size() == 0:
			continue
		var parts: Array = []
		for d in deltas:
			parts.append("%+.4f" % float(d))
		print("  %-24s %s" % [k, ", ".join(parts)])
	print("=== END ====================================================================")


func _base_draw(cam: String) -> float:
	var sum := 0.0
	var n := 0
	for c in _cells:
		var d: Dictionary = c
		if int(d["n"]) == 0 and String(d["cam"]) == cam and d.has("draw"):
			sum += float(d["draw"])
			n += 1
	return sum / float(max(n, 1))
