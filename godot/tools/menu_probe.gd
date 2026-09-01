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
	# look_at() refuses to run on a node that is not in the tree yet, and
	# during _initialize() it is not. Aim it before parenting instead.
	_cam.look_at_from_position(_cam.position, Vector3(0, 1.0, -6.0), Vector3.UP)
	_root.add_child(_cam)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


func _build_tests() -> void:
	# Declarative on purpose. The first version wrote an `off` lambda per test
	# that put each property back to a value typed in by hand, and one of those
	# was wrong: glow_intensity was "restored" to 0.8 when Godot 4.7's default
	# is 0.3, so every screenshot after the glow test showed a value the engine
	# had never chosen. The harness now snapshots whatever is there and puts
	# exactly that back, and no default is written down anywhere.
	#
	# Each test names an object and the properties to push, hard enough that a
	# real effect cannot be mistaken for noise.
	_tests = [
		{"name": "fog_enabled", "who": "env",
		 "set": {"fog_enabled": true, "fog_density": 0.08}},
		{"name": "fog_density", "who": "env",
		 "set": {"fog_enabled": true, "fog_density": 0.6}},
		{"name": "fog_light_color", "who": "env",
		 "set": {"fog_enabled": true, "fog_density": 0.2,
			"fog_light_color": Color(1.0, 0.1, 0.1)}},
		{"name": "fog_sun_scatter", "who": "env",
		 "set": {"fog_enabled": true, "fog_density": 0.2,
			"fog_sun_scatter": 1.0}},
		{"name": "fog_aerial_perspective", "who": "env",
		 "set": {"fog_enabled": true, "fog_density": 0.2,
			"fog_aerial_perspective": 1.0}},
		# Glow gets every advantage: enabled, maximum intensity, and an HDR
		# threshold of 0 so it does not need a float buffer to find something
		# bright. If it were still identical, it would not be there.
		{"name": "glow_enabled", "who": "env",
		 "set": {"glow_enabled": true, "glow_intensity": 8.0,
			"glow_bloom": 1.0, "glow_hdr_threshold": 0.0}},
		{"name": "adjustment_enabled", "who": "env",
		 "set": {"adjustment_enabled": true, "adjustment_saturation": 0.0}},
		{"name": "adjustment_brightness", "who": "env",
		 "set": {"adjustment_enabled": true, "adjustment_brightness": 2.0}},
		{"name": "adjustment_contrast", "who": "env",
		 "set": {"adjustment_enabled": true, "adjustment_contrast": 1.25}},
		{"name": "tonemap_exposure", "who": "env",
		 "set": {"tonemap_exposure": 2.0}},
		# Ambient, four ways. The Light tab exposes ambient_light_energy and
		# vale_light.gd calls it "the shadow-depth knob", so whether it is
		# actually wired under this renderer AND this sky configuration is
		# worth four A/Bs rather than one.
		{"name": "ambient_energy @sky=1", "who": "env",
		 "set": {"ambient_light_energy": 4.0}},
		{"name": "ambient sky_contrib 1->0", "who": "env",
		 "set": {"ambient_light_sky_contribution": 0.0,
			"ambient_light_color": Color(1, 0, 0)}},
		{"name": "ambient_energy @sky=0", "who": "env",
		 "set": {"ambient_light_sky_contribution": 0.0,
			"ambient_light_color": Color(1, 0, 0),
			"ambient_light_energy": 4.0}},
		{"name": "ambient_energy @src=COLOR", "who": "env",
		 "set": {"ambient_light_source": Environment.AMBIENT_SOURCE_COLOR,
			"ambient_light_color": Color(0.4, 0.5, 0.6),
			"ambient_light_energy": 4.0}},
		{"name": "sun light_energy", "who": "sun",
		 "set": {"light_energy": 3.0}},
		{"name": "sun light_color", "who": "sun",
		 "set": {"light_color": Color(1.0, 0.2, 0.1)}},
		{"name": "sun yaw/pitch", "who": "sun",
		 "set": {"rotation_degrees": Vector3(-20.0, 40.0, 0.0)}},
		{"name": "shadow_enabled", "who": "sun",
		 "set": {"shadow_enabled": false}},
		{"name": "scaling_3d_scale", "who": "vp",
		 "set": {"scaling_3d_scale": 0.25}},
		# LIVENESS. This one cannot fail to change the picture. If it reports NO
		# CHANGE the swapchain is stale and nothing above it means anything.
		{"name": "LIVENESS camera move", "who": "cam",
		 "set": {"position": Vector3(3.4, 7.2, 12.0)}},
	]


func _who(which: String) -> Object:
	match which:
		"env":
			return _env
		"sun":
			return _sun
		"cam":
			return _cam
		"vp":
			return get_root()
	return null


## Apply a test's properties, remembering what was there. Nothing is restored
## from a written-down default; the snapshot is the only source.
func _apply_test(t: Dictionary) -> void:
	var o := _who(String(t["who"]))
	var was: Dictionary = {}
	for k in t["set"]:
		was[k] = o.get(k)
		o.set(k, t["set"][k])
	t["was"] = was


func _revert_test(t: Dictionary) -> void:
	var o := _who(String(t["who"]))
	for k in t["was"]:
		o.set(k, t["was"][k])


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
		_apply_test(_tests[0])
		return false

	var t: Dictionary = _tests[_step - 1]
	var data := _grab()
	var same := data == _base
	var dl: float = _luma(data) - _base_luma
	print("[PROBE] %-25s %s (d-luma %+.4f)"
		% [t["name"], "NO CHANGE" if same else "changed", dl])
	if same:
		_faults.append(String(t["name"]) + " did nothing")
	_revert_test(t)

	_step += 1
	if _step - 1 < _tests.size():
		_apply_test(_tests[_step - 1])
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
			# The panel came out narrower than PANEL_W on the first run. Print
			# the numbers rather than guessing at a stretch factor.
			var panel: Control = _menu._panel
			print("[PROBE] window %s  root vp %s  scale %.4f  stretch '%s'/'%s'"
				% [str(DisplayServer.window_get_size()), str(get_root().size),
				   get_root().content_scale_factor,
				   str(ProjectSettings.get_setting("display/window/stretch/mode")),
				   str(ProjectSettings.get_setting("display/window/stretch/aspect"))])
			print("[PROBE] panel rect %s (asked for %.0f wide)"
				% [str(panel.size), DebugMenuScript.PANEL_W])
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


## Drive every control the way a finger does -- set the Control, not the
## property -- and read the target back. A slider whose signal is not connected
## looks identical in a screenshot to one that is, so this is the only thing
## that proves the panel is wired rather than drawn.
func _check_wiring() -> void:
	_menu.open()                       ## rows only exist while it is built
	var ok := 0
	for e in DebugMenuScript.BINDINGS:
		var key: String = e["key"]
		if not _menu._rows.has(key):
			_faults.append("%s built no control" % key)
			continue
		var main: Control = _menu._rows[key][0]["main"]
		var kind := String(e["kind"])
		var want: Variant = null
		match kind:
			"float":
				var sl := main as HSlider
				# 70% along the range, so it differs from any sane default.
				sl.value = sl.min_value + (sl.max_value - sl.min_value) * 0.7
				want = sl.value
			"bool":
				var cb := main as CheckButton
				cb.button_pressed = not cb.button_pressed
				want = cb.button_pressed
			"color":
				# ColorPickerButton.color does not emit on assignment -- only a
				# human picking does. Emit it, which tests the handler but NOT
				# the widget; the colour rows are only half proven here.
				var cp := main as ColorPickerButton
				cp.color = Color(0.25, 0.5, 0.75)
				cp.color_changed.emit(cp.color)
				want = cp.color
		var got: Variant = _menu._read_prop(e)
		var match_ok := false
		if kind == "color":
			match_ok = (got as Color).is_equal_approx(want)
		elif kind == "bool":
			match_ok = bool(got) == bool(want)
		else:
			match_ok = is_equal_approx(float(got), float(want))
		if match_ok:
			ok += 1
		else:
			_faults.append("%s: control says %s, %s.%s says %s"
				% [key, str(want), e["obj"], e["prop"], str(got)])
	print("[PROBE] wiring: %d/%d controls moved their target"
		% [ok, DebugMenuScript.BINDINGS.size()])


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
	_check_wiring()

	# Reset to defaults, measured rather than eyeballed: move the sun off its
	# rig value, press reset, and check it came back. This is also the only
	# proof that setup() captured the defaults before applying anything saved.
	_sun.light_energy = 3.0
	_menu._reset_defaults()
	print("[PROBE] reset: light_energy back to %.3f (rig value 1.000), "
		% _sun.light_energy + "%d defaults captured" % _menu._defaults.size())
	if not is_equal_approx(_sun.light_energy, 1.0):
		_faults.append("reset did not restore light_energy")
	if _menu._defaults.size() != DebugMenuScript.BINDINGS.size():
		_faults.append("captured %d defaults for %d bindings"
			% [_menu._defaults.size(), DebugMenuScript.BINDINGS.size()])

	# Round trip the store, so "the next load restores them" is measured.
	# Move two values off their defaults FIRST -- saving the defaults back and
	# reading the defaults out again would pass with a store that does nothing.
	_sun.light_energy = 2.5
	_env.fog_enabled = true
	_menu._save_values()
	var check: Settings = SettingsScript.new()
	check.load_all()
	var got: Variant = check.get_value("light.energy", null)
	var fog: Variant = check.get_value("fx.fog_enabled", null)
	var col: Variant = check.get_value("light.color", null)
	print("[PROBE] round-trip from disk: light.energy=%s fx.fog_enabled=%s "
		% [str(got), str(fog)] + "light.color=%s" % str(col))
	if typeof(got) != TYPE_FLOAT or not is_equal_approx(float(got), 2.5):
		_faults.append("light.energy did not round-trip as 2.5 (got %s)"
			% str(got))
	if fog != true:
		_faults.append("fx.fog_enabled did not round-trip as true")
	if typeof(col) != TYPE_STRING or not Color.html_is_valid(String(col)):
		_faults.append("light.color did not round-trip as a colour string")

	if _faults.is_empty():
		print("[PROBE] all checks ok")
		quit(0)
	else:
		for f in _faults:
			printerr("  - " + f)
		printerr("[PROBE] %d note(s)" % _faults.size())
		quit(0)   ## a dead uniform is a finding, not a build failure
