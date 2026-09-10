extends SceneTree
## Photograph the argument.
##
## Two prayer bubbles a few metres apart are two prayers. The thing that makes a
## feud a feud is the line between them, and a line is exactly the sort of thing
## that ships pointing at the wrong heads.
const ShotWindowRef := preload("res://tools/shot_window.gd")
const TestGroundRef := preload("res://tools/test_ground.gd")

const OUT := "user://shots"

var _f := 0
var _root: Node = null


func _initialize() -> void:
	ShotWindowRef.park()
	DisplayServer.window_set_size(Vector2i(1280, 720))
	get_root().add_child(
		(load("res://scenes/vale.tscn") as PackedScene).instantiate())


func _process(_d: float) -> bool:
	_f += 1
	if _f < 40:
		return false
	if _root == null:
		for n in get_root().get_children():
			if n.get("divinity") != null:
				_root = n
		if _root == null:
			printerr("[SHOT] FAIL: no scene root")
			quit(1)
			return true
		TestGroundRef.green(_root)
		if not ShotWindowRef.can_shoot():
			print("[SHOT] no display on this machine -- took no picture")
			quit(0)
			return true
		DirAccess.make_dir_recursive_absolute(OUT)
		_stage()
		return false

	# EVERY FRAME, not once. Raising the village past a milestone deals a boon
	# draft, the draft is a full-screen modal, and it gets re-dealt on whatever
	# frame the milestone is noticed -- so closing it once at staging left three
	# boon cards and no villagers in the photograph. And `get_image` returns the
	# frame ALREADY rendered, so the shutter has to be well behind the closing.
	_root.divinity.pending_draft = []
	if _root.draft != null and _root.draft.visible:
		_root.draft.close()

	if _f == 64:
		# FROZEN, because they walk. The pair were placed 2.6 m apart at staging
		# and by the time the shutter opened they had strolled to opposite
		# corners of the frame, joined by a very long orange line.
		Engine.time_scale = 0.0
		var pair: Array = []
		for p in _root.prayers.active:
			if p.feud() and is_instance_valid(p.who):
				pair.append(p.who)
		if pair.size() >= 2:
			pair[1].position = pair[0].position + Vector3(2.6, 0, 0.4)
			_root.rig.focus = (pair[0].position + pair[1].position) * 0.5
			_root.rig._place()
			for w in pair:
				print("[SHOT] %s at %s -> screen %s, bubble %s"
					% [w.brain.name, w.position,
					   _root.rig.cam.unproject_position(
						   w.position + Vector3(0, 1.05, 0)),
					   _root.prayers.of(w) != null])
		return false

	if _f >= 74:
		print("[SHOT] draft open: %s"
			% (_root.draft != null and _root.draft.is_open()))
		print("[SHOT] feud: %s"
			% ShotWindowRef.shoot(OUT.path_join("feud.png")))
		quit(0)
		return true
	return false


func _stage() -> void:
	_root.village.pop_cap = maxi(int(_root.village.pop_cap), 8)
	var guard := 0
	while _adults().size() < Prayers.FEUD_MIN_FOLK and guard < 40:
		guard += 1
		if not _root.spawn_villager():
			break
	# THE DRAFT GETS IN THE WAY. Raising the village past a milestone deals a
	# boon draft, which is a full-screen modal -- the first attempt photographed
	# three boon cards and no villagers at all.
	_root.divinity.pending_draft = []
	if _root.draft != null:
		_root.draft.close()
	var folk := _adults()
	if folk.size() < 2:
		return
	# Stand them face to face, close in, so the line between them is the thing
	# the picture is of.
	folk[1].position = folk[0].position + Vector3(2.6, 0, 0.4)
	folk[0].brain.job = Prayers.CLEARERS[0]
	folk[1].brain.job = Prayers.GROWERS[0]
	_root.prayers._feud_at = -1.0
	_root.prayers._cooldown.clear()
	_root.prayers._open_feud(float(_root.village.now))
	# WHOEVER ACTUALLY GOT PICKED, not whoever I dressed for the part. Other
	# villagers already hold these jobs, so `_open_feud` chose two of its own
	# and the first photograph framed a bystander while the argument ran off
	# the bottom-left corner.
	var pair: Array = []
	for p in _root.prayers.active:
		if p.feud() and is_instance_valid(p.who):
			pair.append(p.who)
	if pair.size() < 2:
		return
	pair[1].position = pair[0].position + Vector3(2.6, 0, 0.4)
	_root.rig.dist = 17.0
	_root.rig.focus = (pair[0].position + pair[1].position) * 0.5
	_root.rig._place()
	for p in _root.prayers.active:
		print("[SHOT] %s: %s at %s" % [p.kind, p.says(), p.who.position])
	print("[SHOT] camera on %s at %.1f" % [_root.rig.focus, _root.rig.dist])


func _adults() -> Array:
	var out: Array = []
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null and f.brain.adult:
			out.append(f)
	return out
