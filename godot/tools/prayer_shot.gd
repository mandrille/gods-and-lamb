extends SceneTree
## What a standing prayer looks like AT THE ZOOM THE PLAYER ACTUALLY PLAYS AT.
const ShotWindowRef := preload("res://tools/shot_window.gd")
const OUT := "user://shots"
var _f := 0
var _root: Node = null
var _shot := false


func _initialize() -> void:
	ShotWindowRef.park()
	DisplayServer.window_set_size(Vector2i(1280, 720))
	get_root().add_child(
		(load("res://scenes/vale.tscn") as PackedScene).instantiate())


func _process(_d: float) -> bool:
	_f += 1
	if _f == 20:
		for n in get_root().get_children():
			if n.get("divinity") != null:
				_root = n
		if _root == null:
			printerr("no root"); quit(1); return true
		DirAccess.make_dir_recursive_absolute(OUT)
		Engine.time_scale = 8.0
		return false
	if _root == null or _shot:
		return false
	# Wait for the village to be genuinely asking for something.
	if (_root.prayers.active as Array).size() < 2:
		if float(_root.village.now) > 600.0:
			print("[SHOT] gave up: never two at once")
			quit(0)
			return true
		return false
	_shot = true
	Engine.time_scale = 0.0
	# The boon draft is a full-screen modal and it lands early on; it is not
	# what this photograph is of.
	_root.divinity.pending_draft = []
	if _root.draft != null:
		_root.draft.close()
	print("[SHOT] %d praying at %.0fs, camera at default %.0f"
		% [(_root.prayers.active as Array).size(), _root.village.now,
		   _root.rig.dist])
	for p in _root.prayers.active:
		print("[SHOT]   %s" % p.says())
	return false


func _physics_process(_d: float) -> bool:
	if _shot and _f > 0:
		_f = -1
		return false
	if _f == -1:
		print("[SHOT] %s" % ShotWindowRef.shoot(OUT.path_join("praying.png")))
		quit(0)
	return false
