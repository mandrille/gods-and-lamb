extends SceneTree
## Which of the four things that look like fog is actually doing it?
##
## "Fog is too aggressive" can be at least four separate causes and they are
## visually identical: the depth fog itself, the fog's AERIAL PERSPECTIVE which
## blends toward the sky, `fog_sky_affect` which fogs the SKY as well, and the
## sky's own GROUND hemisphere, which is what fills the frame past the edge of
## the map because the camera never reaches the horizon. Turning each off in
## isolation is the only way to attribute it.
const ShotWindowRef := preload("res://tools/shot_window.gd")
var _f := 0
var _step := 0
var _env: Environment
var _sky: ProceduralSkyMaterial
var _base := 0.0

func _initialize() -> void:
	ShotWindowRef.park()
	var packed: PackedScene = load("res://scenes/vale.tscn")
	get_root().add_child(packed.instantiate())

func _find() -> void:
	for n in _walk(get_root()):
		if n is WorldEnvironment:
			_env = (n as WorldEnvironment).environment
			if _env.sky != null:
				_sky = _env.sky.sky_material as ProceduralSkyMaterial

func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _luma() -> float:
	# -1 means "nobody looked", which the caller reports rather than asserts on.
	# Reading the backbuffer headless returns null and the throw would abort
	# _process before the quit() that ends this probe -- it hangs instead of
	# failing, which is the worst of the three outcomes.
	if not ShotWindow.can_shoot():
		return -1.0
	var img := get_root().get_texture().get_image()
	var s := 0.0
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			s += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return s / float(max(n, 1))

func _process(_d: float) -> bool:
	_f += 1
	if _f < 40:
		return false
	if _env == null:
		_find()
		if _env == null:
			printerr("[FOG] no WorldEnvironment found")
			quit(1)
			return true
		_base = _luma()
		print("[FOG] baseline luma %.4f" % _base)
		print("[FOG]   fog_enabled=%s density=%.4f aerial=%.2f sky_affect=%.2f mode=%d"
			% [_env.fog_enabled, _env.fog_density, _env.fog_aerial_perspective,
			   _env.fog_sky_affect, _env.fog_mode])
		return false
	if _f % 12 != 0:
		return false

	var label := ""
	match _step:
		0:
			_env.fog_aerial_perspective = 0.0
			label = "aerial_perspective 0.35 -> 0"
		1:
			_env.fog_aerial_perspective = 0.35
			_env.fog_sky_affect = 0.0
			label = "fog_sky_affect 1 -> 0 (aerial restored)"
		2:
			_env.fog_sky_affect = 1.0
			_env.fog_enabled = false
			label = "fog OFF entirely"
		3:
			_env.fog_enabled = true
			if _sky != null:
				_sky.ground_horizon_color = Color(0.30, 0.62, 0.28)
				_sky.ground_bottom_color = Color(0.26, 0.55, 0.24)
			label = "sky GROUND hemisphere pushed green"
		_:
			print("[FOG] done")
			quit(0)
			return true
	var now := _luma()
	print("[FOG] %-46s luma %.4f  delta %+.4f" % [label, now, now - _base])
	_step += 1
	return false
