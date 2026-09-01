extends Node3D

## The Vale scene: ground, light, camera, and followers walking the road.
##
## Everything is assembled here at runtime rather than saved into the .tscn.
## Structural changes made inside an instantiated sub-scene are NOT serialised,
## so a builder that ran at scene-build time would write a scene that looks
## right in the editor and comes up empty when it runs.

const FOLLOWER := preload("res://scripts/follower.gd")
const BUILDER := preload("res://scripts/vale_builder.gd")
const LIGHT := preload("res://scripts/vale_light.gd")

## Where the camera looks and from how far. Matches the Blender `hero` angle so
## the two pictures are comparable: dirv (-0.72, -1.00, 0.88) in Blender axes.
const CAM_TARGET_COL := 21
const CAM_TARGET_ROW := 34
const CAM_DIR := Vector3(-0.72, 0.88, 1.00)   ## Blender -Y is Godot +Z
const CAM_DIST := 17.4
const CAM_LENS := 35.0

## The followers walk the main road, which runs the full width of the map at
## rows 31-33, and cross the bridge over the river. Tile coordinates; the
## builder turns them into world space so this stays readable against the map.
const ROAD_ROW := 32
const WALKERS := [
	{"asset": "Folk/villager", "path": [[3, 32], [20, 32], [34, 32], [50, 32]],
	 "speed": 1.0, "offset": 0.0},
	{"asset": "Folk/villager", "path": [[50, 33], [34, 33], [20, 33], [3, 33]],
	 "speed": 0.9, "offset": 0.35},
	{"asset": "Folk/adventurer", "path": [[14, 20], [14, 31], [26, 32], [40, 32]],
	 "speed": 1.1, "offset": 0.6},
	{"asset": "Folk/villager", "path": [[40, 31], [26, 31], [14, 31], [14, 20]],
	 "speed": 0.95, "offset": 0.15},
]

var builder: ValeBuilder


func _ready() -> void:
	builder = BUILDER.new()
	builder.name = "Vale"
	add_child(builder)

	var light: Node3D = LIGHT.new()
	light.name = "Light"
	add_child(light)

	_add_camera()
	_add_followers()


func _add_camera() -> void:
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.current = true
	# Godot's `fov` is VERTICAL by default and Blender's lens is horizontal, so
	# setting one from the other made the Godot shot far wider than the
	# look-dev render it is supposed to match -- wide enough to see past the
	# edge of the map. KEEP_WIDTH makes `fov` horizontal, and then 35 mm on a
	# 36 mm frame is the same number in both.
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = 2.0 * rad_to_deg(atan(18.0 / CAM_LENS))
	var target := builder.world_of(CAM_TARGET_COL, CAM_TARGET_ROW) \
		+ Vector3(0, builder.lift * 1.6, 0)
	cam.position = target + CAM_DIR.normalized() * CAM_DIST
	add_child(cam)
	cam.look_at(target, Vector3.UP)


func _add_followers() -> void:
	var made := 0
	for w in WALKERS:
		var packed: PackedScene = builder._packed_of(w["asset"])
		if packed == null:
			continue
		var node := packed.instantiate()
		# The GLB root is a plain Node3D. Reparent its children under a
		# Follower so the script owns the transform, rather than trying to
		# attach a script to an imported scene root -- which does not survive
		# a re-import.
		var f: Follower = FOLLOWER.new()
		f.name = "Follower%d" % made
		add_child(f)
		f.add_child(node)

		var pts: Array[Vector3] = []
		for cell in w["path"]:
			var here := builder.world_of(int(cell[0]), int(cell[1]))
			pts.append(here + Vector3(0, builder.lift, 0))
		f.setup(pts, float(w["speed"]))
		# Spread them along the road so they do not start in a heap.
		f._t = float(w["offset"])
		made += 1
	print("[VALE] followers: %d walking" % made)
