extends SceneTree
## Photograph the disaster feedback, because that is the whole of stage 10.
##
## The probe next door proves the numbers are right. Numbers being right is not
## the deliverable here -- the deliverable is that a player who was looking
## somewhere else can find the fire, and that when it is over they are told what
## it cost and what it made them. Neither of those can be asserted; they have to
## be looked at.
##
## Two frames: one with a fire off camera and the arrow pointing at it, one with
## the resolution card up.
const ShotWindowRef := preload("res://tools/shot_window.gd")
const TestGroundRef := preload("res://tools/test_ground.gd")

const OUT := "user://shots"

var _f := 0
var _root: Node = null
var _shot := 0
var _fire = null


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
		DirAccess.make_dir_recursive_absolute(OUT)
		if not ShotWindowRef.can_shoot():
			print("[SHOT] no display on this machine -- took no pictures")
			quit(0)
			return true
		# ZOOMED IN AND LOOKING ELSEWHERE, because that is the only state in
		# which the arrow means anything. At the default distance the whole
		# island is on screen and nothing is ever off it -- which is exactly
		# how a marker like this ends up shipping untested and wrong.
		_root.rig.dist = 14.0
		# ON A VILLAGER, because a cell index is not a promise that there is
		# any island there -- the first attempt aimed at open sea and produced
		# a photograph of the sky.
		for f in _root.folk:
			if is_instance_valid(f):
				_root.rig.focus = f.position
				break
		_root.rig._place()
		# A FIRE IN THE FAR CORNER, which is the case the arrow exists for.
		_fire = Calamity.new("fire", Vector2i(1, 1))
		_root.calamities.append(_fire)
		_root.divinity.notice.emit("Fire in the trees.")
		return false

	# Give the arrow a few frames to be drawn, then photograph it.
	if _shot == 0 and _f >= 55:
		_shot = 1
		print("[SHOT] arrow: %s"
			% ShotWindowRef.shoot(OUT.path_join("aftermath_arrow.png")))
		_fire.eaten = 3
		_fire.watch(_root.folk, _root.grid.world_of)
		_root._end_calamity(_fire, true)
		return false

	if _shot == 1 and _f >= 62:
		print("[SHOT] card: %s"
			% ShotWindowRef.shoot(OUT.path_join("aftermath_card.png")))
		print("[SHOT] written to %s" % ProjectSettings.globalize_path(OUT))
		quit(0)
		return true
	return false
