extends SceneTree

## Throwaway harness for scripts/debug_menu.gd and scripts/settings.gd.
##
## The full Vale scene belongs to another agent right now, so this builds the
## smallest thing the menu needs: a Node3D with a WorldEnvironment, a sun, a
## camera, some geometry that fog and shadow can actually land on, and a stub
## host that answers spawn_follower() / clear_spawned().
##
## It does two jobs:
##
##   PHASE 1 -- A/B every Environment property the panel exposes. Toggle it,
##   grab a frame, byte-compare against the baseline. That is the only honest
##   way to say "glow is dead under Compatibility": the docs disagree with
##   themselves across versions and the renderer is the authority. A liveness
##   step at the end moves the camera, which MUST change the image -- otherwise
##   the swapchain never presented and every "NO CHANGE" above it is a lie,
##   which is exactly the failure the shot tool's stale-frame guard exists for.
##
##   PHASE 2 -- press Escape (the real ui_cancel path, not a direct call),
##   screenshot each of the four tabs, press Escape again, and check the panel
##   closed and gave the mouse back.
##
## NOT --headless: get_root().get_texture() needs a real swapchain.

const ShotWindow := preload("res://tools/shot_window.gd")
const DebugMenuScript := preload("res://scripts/debug_menu.gd")
const SettingsScript := preload("res://scripts/settings.gd")

const OUT := "res://shots/"
const WARMUP := 30
const SETTLE := 10          ## frames between a property change and its grab


class StubHost extends Node3D:
	## Stands in for vale_root. The menu only ever asks; it never reaches in.
	var made: Array[Node3D] = []

	func spawn_follower() -> void:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.3, 0.6, 0.3)
		m.mesh = box
		var n := made.size()
		m.position = Vector3(-4.0 + fmod(n, 20) * 0.45, 0.3,
			-2.0 + floor(n / 20.0) * 0.5)
		add_child(m)
		made.append(m)

	func clear_spawned() -> void:
		for m in made:
			m.queue_free()
		made.clear()


var _root: Node3D
var _env: Environment
var _sun: DirectionalLight3D
var _cam: Camera3D
var _host: StubHost
var _menu: DebugMenu
var _settings: Settings

var _frame := 0
var _step := 0
var _next := WARMUP
var _phase := 1
var _shot := 0
var _prev := PackedByteArray()
var _base := PackedByteArray()
var _base_luma := 0.0
var _tests: Array = []
var _faults: Array[String] = []
var _tabs: TabContainer = null


func _initialize() -> void:
	ShotWindow.park()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_build_scene()
	_build_tests()
	# A fresh store every run: a leftover settings.json from a previous run
	# would silently move the values the screenshot is supposed to show.
	var abs := ProjectSettings.globalize_path(SettingsScript.PATH)
	if FileAccess.file_exists(SettingsScript.PATH):
		DirAccess.remove_absolute(abs)
	_settings = SettingsScript.new()
	_settings.load_all()
	_root.add_child(_settings)

	_menu = DebugMenuScript.new()
	_menu.name = "DebugMenu"
	_root.add_child(_menu)
	_menu.setup(_env, _sun, _host, _settings)


func _build_scene() -> void:
	_root = Node3D.new()
	_root.name = "Probe"
	get_root().add_child(_root)

	# The same rig vale_light.gd builds, close enough that a fog or ambient
	# reading here transfers: sky background, sky ambient, Linear tonemap.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.286, 0.565, 0.85)
	sky_mat.sky_horizon_color = Color(0.66, 0.80, 0.93)
	sky_mat.ground_horizon_color = Color(0.52, 0.62, 0.45)
	sky_mat.ground_bottom_color = Color(0.44, 0.54, 0.40)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_sky_contribution = 1.0
	_env.ambient_light_energy = 0.36
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_env.tonemap_exposure = 1.0
	var we := WorldEnvironment.new()
	we.environment = _env
	_root.add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.light_color = Color(1.0, 0.945, 0.87)
	_sun.light_energy = 1.0
	_sun.light_angular_distance = 3.6
	_sun.shadow_enabled = true
	_sun.shadow_bias = 0.03
	_sun.rotation_degrees = Vector3(-48.0, -128.0, 0.0)
	_root.add_child(_sun)

	# Ground, plus a row of blocks running away from the camera. Fog and aerial
	# perspective are distance effects: on a single close-up object they change
	# almost nothing and the A/B would report a false "dead".
	var ground := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(80, 0.2, 80)
	ground.mesh = plane
	ground.position = Vector3(0, -0.1, 0)
	ground.set_surface_override_material(0, _mat(Color(0.42, 0.60, 0.30)))
	_root.add_child(ground)

	for i in 14:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.2, 1.6 + fmod(i, 3) * 0.8, 1.2)
		m.mesh = box
		m.position = Vector3(-3.0 + fmod(i, 2) * 6.0, box.size.y * 0.5,
			2.0 - i * 2.6)
		m.set_surface_override_material(0,
			_mat(Color.from_hsv(fmod(i * 0.13, 1.0), 0.55, 0.85)))
		_root.add_child(m)

	# One deliberately blown-out emitter, so glow has the brightest thing it is
	# ever going to get to work with.
	var lamp := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.6
	sph.height = 1.2
	lamp.mesh = sph
	lamp.position = Vector3(1.6, 1.4, -1.0)
	var em := StandardMaterial3D.new()
	em.albedo_color = Color(1, 0.95, 0.7)
	em.emission_enabled = true
	em.emission = Color(1, 0.9, 0.6)
	em.emission_energy_multiplier = 6.0
	lamp.set_surface_override_material(0, em)
	_root.add_child(lamp)

	_host = StubHost.new()
	_host.name = "Host"
	_root.add_child(_host)

	_cam = Camera3D.new()
	_cam.current = true
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_cam.fov = 2.0 * rad_to_deg(atan(18.0 / 35.0))
	_cam.position = Vector3(3.4, 4.2, 8.0)
	_root.add_child(_cam)
	_cam.look_at(Vector3(0, 1.0, -6.0), Vector3.UP)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


func _build_tests() -> void:
	# Each test turns one thing on hard enough that a real effect cannot be
	# mistaken for noise, then puts it back.
	_tests = [
		{"name": "fog_enabled", "on": func() -> void:
			_env.fog_enabled = true
			_env.fog_density = 0.08,
		 "off": func() -> void:
			_env.fog_enabled = false
			_env.fog_density = 0.01},
		{"name": "fog_density", "on": func() -> void:
			_env.fog_enabled = true
			_env.fog_density = 0.6,
		 "off": func() -> void:
			_env.fog_enabled = false
			_env.fog_density = 0.01},
		{"name": "fog_light_color", "on": func() -> void:
			_env.fog_enabled = true
			_env.fog_density = 0.2
			_env.fog_light_color = Color(1.0, 0.1, 0.1),
		 "off": func() -> void:
			_env.fog_enabled = false
			_env.fog_density = 0.01
			_env.fog_light_color = Color(0.518, 0.553, 0.608)},
		{"name": "fog_sun_scatter", "on": func() -> void:
			_env.fog_enabled = true
			_env.fog_density = 0.2
			_env.fog_sun_scatter = 1.0,
		 "off": func() -> void:
			_env.fog_enabled = false
			_env.fog_density = 0.01
			_env.fog_sun_scatter = 0.0},
		{"name": "fog_aerial_perspective", "on": func() -> void:
			_env.fog_enabled = true
			_env.fog_density = 0.2
			_env.fog_aerial_perspective = 1.0,
		 "off": func() -> void:
			_env.fog_enabled = false
			_env.fog_density = 0.01
			_env.fog_aerial_perspective = 0.0},
		# Glow gets every advantage: enabled, maximum intensity, and an HDR
		# threshold of 0 so it does not need a float buffer to find something
		# bright. If it is still identical, it is not there.
		{"name": "glow_enabled", "on": func() -> void:
			_env.glow_enabled = true
			_env.glow_intensity = 8.0
			_env.glow_bloom = 1.0
			_env.glow_hdr_threshold = 0.0,
		 "off": func() -> void:
			_env.glow_enabled = false
			_env.glow_intensity = 0.8
			_env.glow_bloom = 0.0
			_env.glow_hdr_threshold = 1.0},
		{"name": "adjustment_enabled", "on": func() -> void:
			_env.adjustment_enabled = true
			_env.adjustment_saturation = 0.0,
		 "off": func() -> void:
			_env.adjustment_enabled = false
			_env.adjustment_saturation = 1.0},
		{"name": "adjustment_brightness", "on": func() -> void:
			_env.adjustment_enabled = true
			_env.adjustment_brightness = 2.0,
		 "off": func() -> void:
			_env.adjustment_enabled = false
			_env.adjustment_brightness = 1.0},
		{"name": "adjustment_contrast", "on": func() -> void:
			_env.adjustment_enabled = true
			_env.adjustment_contrast = 1.25,
		 "off": func() -> void:
			_env.adjustment_enabled = false
			_env.adjustment_contrast = 1.0},
		{"name": "tonemap_exposure", "on": func() -> void:
			_env.tonemap_exposure = 2.0,
		 "off": func() -> void:
			_env.tonemap_exposure = 1.0},
		{"name": "ambient_light_energy", "on": func() -> void:
			_env.ambient_light_energy = 4.0,
		 "off": func() -> void:
			_env.ambient_light_energy = 0.36},
		{"name": "sun light_energy", "on": func() -> void:
			_sun.light_energy = 3.0,
		 "off": func() -> void:
			_sun.light_energy = 1.0},
		{"name": "sun light_color", "on": func() -> void:
			_sun.light_color = Color(1.0, 0.2, 0.1),
		 "off": func() -> void:
			_sun.light_color = Color(1.0, 0.945, 0.87)},
		{"name": "sun yaw/pitch", "on": func() -> void:
			_sun.rotation_degrees = Vector3(-20.0, 40.0, 0.0),
		 "off": func() -> void:
			_sun.rotation_degrees = Vector3(-48.0, -128.0, 0.0)},
		{"name": "shadow_enabled", "on": func() -> void:
			_sun.shadow_enabled = false,
		 "off": func() -> void:
			_sun.shadow_enabled = true},
		{"name": "scaling_3d_scale", "on": func() -> void:
			get_root().scaling_3d_scale = 0.25,
		 "off": func() -> void:
			get_root().scaling_3d_scale = 1.0},
		# LIVENESS. This one cannot fail to change the picture. If it reports NO
		# CHANGE the swapchain is stale and nothing above it means anything.
		{"name": "LIVENESS camera move", "on": func() -> void:
			_cam.position += Vector3(0, 3.0, 4.0),
		 "off": func() -> void:
			_cam.position -= Vector3(0, 3.0, 4.0)},
	]


func _process(_d: float) -> bool:
	_frame += 1
	if _frame < _next:
		return false
	if _phase == 1:
		return _phase_effects()
	return _phase_menu()


# -- phase 1 ---------------------------------------------------------------

func _phase_effects() -> bool:
	if _step == 0:
		_base = _grab()
		_base_luma = _luma(_base)
		print("[PROBE] baseline captured, mean luma %.4f" % _base_luma)
		_step = 1
		_next = _frame + SETTLE
		_tests[0]["on"].call()
		return false

	var t: Dictionary = _tests[_step - 1]
	var data := _grab()
	var same := data == _base
	var dl: float = _luma(data) - _base_luma
	print("[PROBE] %-26s %s (d-luma %+.4f)"
		% [t["name"], "NO CHANGE" if same else "changed", dl])
	if same:
		_faults.append(String(t["name"]) + " did nothing")
	t["off"].call()

	_step += 1
	if _step - 1 < _tests.size():
		_tests[_step - 1]["on"].call()
		_next = _frame + SETTLE
		return false

	_phase = 2
	_step = 0
	_next = _frame + SETTLE
	return false


func _grab() -> PackedByteArray:
	return get_root().get_texture().get_image().get_data()


func _luma(data: PackedByteArray) -> float:
	# The image is RGBA8 off the backbuffer; sample every 64th pixel.
	var sum := 0.0
	var n := 0
	var i := 0
	while i + 2 < data.size():
		sum += (0.2126 * data[i] + 0.7152 * data[i + 1]
			+ 0.0722 * data[i + 2]) / 255.0
		n += 1
		i += 256
	return sum / float(max(n, 1))


# -- phase 2 ---------------------------------------------------------------

func _phase_menu() -> bool:
	match _step:
		0:
			_press_escape()
			_step = 1
			_next = _frame + SETTLE
			return false
		1:
			if not _menu.is_open():
				_faults.append("Escape did not open the menu")
				print("[PROBE] menu did not open on ui_cancel")
				_finish()
				return true
			print("[PROBE] menu open after Escape; mouse_mode %d"
				% Input.mouse_mode)
			_tabs = _find_tabs(_menu)
			if _tabs == null:
				_faults.append("no TabContainer in the panel")
				_finish()
				return true
			print("[PROBE] tabs: %d" % _tabs.get_tab_count())
			_step = 2
			return false
		2:
			if _shot >= _tabs.get_tab_count():
				_step = 4
				_next = _frame + SETTLE
				return false
			_tabs.current_tab = _shot
			# Press the stress buttons on their own tab, so the live count and
			# the spawned bodies are both in the picture that gets reviewed.
			if _tabs.get_tab_title(_shot) == "Stress":
				_menu._spawn(10)
			_step = 3
			_next = _frame + 4        ## let the tab switch actually draw
			return false
		3:
			_capture_tab()
			_step = 2
			_next = _frame + 2
			return false
		4:
			_press_escape()
			_step = 5
			_next = _frame + SETTLE
			return false
		5:
			if _menu.is_open():
				_faults.append("Escape did not close the menu")
			else:
				print("[PROBE] menu closed on second Escape; mouse_mode %d"
					% Input.mouse_mode)
			_finish()
			return true
	return false


func _capture_tab() -> void:
	var img := get_root().get_texture().get_image()
	var data := img.get_data()
	# The stale-frame guard, same reason as tools/shots.gd: four screenshots of
	# four different tabs cannot be bit-identical, and a failed run that writes
	# four copies of one frame looks exactly like a good one in the log.
	if data == _prev:
		printerr("[PROBE] FAIL: tab %d is bit-identical to the last grab -- "
			% _shot + "the swapchain never presented; refusing to write.")
		_faults.append("stale frame on tab %d" % _shot)
		_shot = _tabs.get_tab_count()
		return
	_prev = data
	var path := OUT + "menu_%d_%s.png" % [_shot,
		_tabs.get_tab_title(_shot).to_lower().replace(" ", "_")]
	img.save_png(ProjectSettings.globalize_path(path))
	print("[PROBE] %s  luma %.4f" % [path, _luma(data)])
	_shot += 1


func _press_escape() -> void:
	# The real path: a key event through the input map, not a call to open().
	# "ui_cancel opens it" is the requirement, and calling the method would
	# verify something else entirely.
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)


func _find_tabs(n: Node) -> TabContainer:
	if n is TabContainer:
		return n
	for c in n.get_children():
		var found := _find_tabs(c)
		if found != null:
			return found
	return null


func _finish() -> void:
	# Round trip the store, so "the next load restores them" is measured.
	_menu._save_values()
	var check: Settings = SettingsScript.new()
	check.load_all()
	var got: Variant = check.get_value("light.energy", null)
	print("[PROBE] settings round-trip: light.energy = %s (live %.3f)"
		% [str(got), _sun.light_energy])
	if got == null:
		_faults.append("settings did not round-trip")

	if _faults.is_empty():
		print("[PROBE] all checks ok")
		quit(0)
	else:
		for f in _faults:
			printerr("  - " + f)
		printerr("[PROBE] %d note(s)" % _faults.size())
		quit(0)   ## a dead uniform is a finding, not a build failure
