extends SceneTree
## Fire every effect at once, spread out and labelled, and photograph them.
##
## The complaint this answers is "there's just like 1 fx reused for everything",
## and no assertion can settle that -- two effects can differ in every number
## and still look identical. So this puts them side by side on a plain ground
## with their names over them and takes a picture, which is the only way to
## check the thing that was actually wrong.
const ShotWindowRef := preload("res://tools/shot_window.gd")
const FX := preload("res://scripts/fx_events.gd")
const LightRig := preload("res://scripts/vale_light.gd")

const COLS := 4
const PITCH := 3.2

var _f := 0
var _fx: Node3D
var _rig: Node3D
var _cam: Camera3D
var _kinds: Array = []
var _shot := 0


func _initialize() -> void:
	ShotWindowRef.park()
	var root := get_root()
	_rig = LightRig.new()
	root.add_child(_rig)

	_fx = FX.new()
	root.add_child(_fx)
	_kinds = FX.KINDS.keys()
	_kinds.sort()

	# A plain dark floor: these are additive and mixed effects and half of them
	# vanish against a bright sky.
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(60, 60)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.16, 0.19, 0.22)
	fm.roughness = 1.0
	floor_mesh.material = fm
	var mi := MeshInstance3D.new()
	mi.mesh = floor_mesh
	root.add_child(mi)

	for i in _kinds.size():
		var tag := Label3D.new()
		tag.text = String(_kinds[i])
		tag.font_size = 64
		tag.pixel_size = 0.006
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.outline_size = 20
		tag.position = _spot(i) + Vector3(0, 2.6, 0)
		root.add_child(tag)

	_cam = Camera3D.new()
	_cam.current = true
	_cam.fov = 46.0
	root.add_child(_cam)
	var rows := int(ceil(float(_kinds.size()) / float(COLS)))
	var mid := Vector3(float(COLS - 1) * PITCH * 0.5, 0.0,
					   float(rows - 1) * PITCH * 0.5)
	_cam.look_at_from_position(mid + Vector3(0, 9.5, 13.0), mid + Vector3(0, 1.0, 0),
							   Vector3.UP)


func _spot(i: int) -> Vector3:
	return Vector3(float(i % COLS) * PITCH, 0.0, float(i / COLS) * PITCH)


func _process(_d: float) -> bool:
	_f += 1
	if _f > 900:
		printerr("[FXS] stuck")
		quit(1)
		return true
	# Fire them all, then photograph a few frames into their lives -- most of
	# these read by their MOTION, so a capture on the emission frame shows
	# nothing but a cluster of dots for every one of them.
	if _f == 20 or _f == 120 or _f == 220:
		for i in _kinds.size():
			_fx.burst(String(_kinds[i]), _spot(i))
	if _f in [34, 134, 234]:
		var env: Environment = _rig.env
		if env != null:
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.09, 0.10, 0.13)
		var img := get_root().get_texture().get_image()
		var path := "res://shots/fx_%d.png" % _shot
		img.save_png(path)
		print("[FXS] %s  (%d emitters live)" % [path, _fx.active_count()])
		_shot += 1
	if _shot >= 3:
		print("[FXS] %d effects: %s" % [_kinds.size(), str(_kinds)])
		quit(0)
		return true
	return false
