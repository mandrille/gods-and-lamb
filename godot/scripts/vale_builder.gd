extends Node3D
class_name ValeBuilder

## Builds the Vale from `data/vale.json` and the GLB library.
##
## The layout arrives as DATA, not as a baked scene, because the village grows
## during play -- and because the same file drives the Blender look-dev render,
## so the two cannot drift into different villages.
##
## Everything is built at RUNTIME in _ready(). Structural changes made inside an
## instantiated sub-scene are not serialised, so a builder that ran at
## scene-build time would produce a .tscn that looks right in the editor and is
## empty when it runs.

const DATA := "res://data/vale.json"
const LIBRARY := "res://assets/library/%s.glb"

## Ground goes through MultiMesh, one per tile type. Hundreds of separate tile
## nodes is the single most likely way to kill a mobile browser, and this map
## has three thousand of them.
var _multi: Dictionary = {}
var _scenes: Dictionary = {}

var doc: Dictionary = {}
var tile := 0.5
var lift := 0.5
var upper_blocks := 2
var water_drop := 0.06
var cols := 0
var rows := 0
var lower: Array = []
var upper: Array = []

## Every prop that was actually placed: {id, node, pos}. Hover picking and the
## FX layer both need this and neither should re-read the JSON to get it --
## a second walk of the layout is a second chance to disagree with the first.
var placed_props: Array = []

## World-space extent of the ground, for clamping the camera.
var extent_min := Vector3.ZERO
var extent_max := Vector3.ZERO


func _ready() -> void:
	_load()
	_build_ground()
	_build_props()


func _load() -> void:
	var f := FileAccess.open(DATA, FileAccess.READ)
	if f == null:
		push_error("ValeBuilder: cannot open %s -- run `build.py -- export`" % DATA)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ValeBuilder: %s is not a JSON object" % DATA)
		return
	doc = parsed
	tile = float(doc.get("tile", 0.5))
	lift = float(doc.get("lift", 0.5))
	upper_blocks = int(doc.get("upper_blocks", 2))
	water_drop = float(doc.get("water_drop", 0.06))
	cols = int(doc.get("cols", 0))
	rows = int(doc.get("rows", 0))
	lower = doc.get("lower", [])
	upper = doc.get("upper", [])


## Tile centre in world space. Row 0 is the FAR edge, so rows run -Z as they go
## down the layout. Blender's +Z is Godot's +Y, and Blender's +Y is Godot's -Z:
## the exporter swizzles the meshes, and this has to swizzle the layout to
## match or the village comes out mirrored with every roof still correct.
func world_of(col: int, row: int) -> Vector3:
	var ox := -float(cols - 1) * tile * 0.5
	var oz := -float(rows - 1) * tile * 0.5
	return Vector3(ox + col * tile, 0.0, oz + (rows - 1 - row) * tile)


func code_at(layer: Array, col: int, row: int) -> String:
	if row < 0 or row >= layer.size():
		return "."
	var line: String = layer[row]
	if col < 0 or col >= line.length():
		return "."
	return line[col]


func _mesh_of(asset_id: String) -> Mesh:
	## The first MeshInstance3D in a library GLB. Keyed on the FILE, never on a
	## node name: Godot's validate_node_name() rewrites . : @ / % to _, so an
	## authored TERRAIN.ground.grass arrives as TERRAIN_ground_grass.
	var packed := _packed_of(asset_id)
	if packed == null:
		return null
	var root := packed.instantiate()
	var found: Mesh = null
	for n in _walk(root):
		if n is MeshInstance3D:
			found = (n as MeshInstance3D).mesh
			break
	root.queue_free()
	return found


func _packed_of(asset_id: String) -> PackedScene:
	if _scenes.has(asset_id):
		return _scenes[asset_id]
	var path := LIBRARY % asset_id.replace("/", "__")
	if not ResourceLoader.exists(path):
		push_error("ValeBuilder: no library asset at %s" % path)
		_scenes[asset_id] = null
		return null
	var packed: PackedScene = load(path)
	_scenes[asset_id] = packed
	return packed


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out


func _multi_for(asset_id: String) -> MultiMeshInstance3D:
	if _multi.has(asset_id):
		return _multi[asset_id]
	var mesh := _mesh_of(asset_id)
	if mesh == null:
		_multi[asset_id] = null
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var inst := MultiMeshInstance3D.new()
	inst.name = "Ground_" + asset_id.replace("/", "_")
	inst.multimesh = mm
	add_child(inst)
	_multi[asset_id] = inst
	return inst


func _build_ground() -> void:
	var code: Dictionary = doc.get("code", {})
	var fill: String = doc.get("fill", "Terrain/dirt")
	var batches: Dictionary = {}     ## asset_id -> Array[Transform3D]

	for row in rows:
		for col in cols:
			var lo := code_at(lower, col, row)
			if lo == ".":
				continue
			var up := code_at(upper, col, row)
			var base := world_of(col, row)
			if up == ".":
				var aid: String = code[lo]
				_stack(batches, aid, base)
				continue
			# The hill: filled blocks under a capped top, so a cliff is solid
			# and only the topmost block wears its grass.
			for b in range(1, upper_blocks):
				_stack(batches, fill, base + Vector3(0, lift * b, 0))
			_stack(batches, code[up], base + Vector3(0, lift * upper_blocks, 0))

	var total := 0
	for aid in batches:
		var inst := _multi_for(aid)
		if inst == null:
			continue
		var xforms: Array = batches[aid]
		inst.multimesh.instance_count = xforms.size()
		for i in xforms.size():
			inst.multimesh.set_instance_transform(i, xforms[i])
		total += xforms.size()
	extent_min = world_of(0, rows - 1)
	extent_max = world_of(cols - 1, 0)
	print("[VALE] ground: %d tiles in %d multimesh batches, %.1f x %.1f m"
		% [total, batches.size(), extent_max.x - extent_min.x,
		   extent_max.z - extent_min.z])


func _stack(batches: Dictionary, aid: String, at: Vector3) -> void:
	if not batches.has(aid):
		batches[aid] = []
	batches[aid].append(Transform3D(Basis(), at))


func _build_props() -> void:
	var props: Array = doc.get("props", [])
	var placed := 0
	for p in props:
		var aid: String = p["id"]
		var packed := _packed_of(aid)
		if packed == null:
			continue
		var col := int(p["col"])
		var row := int(p["row"])
		var on_hill := code_at(upper, col, row) != "."
		var blocks := upper_blocks + 1 if on_hill else 1
		var y := lift * blocks
		if not on_hill and code_at(lower, col, row) == "W":
			y -= water_drop
		var node := packed.instantiate()
		add_child(node)
		node.position = world_of(col, row) + Vector3(0, y, 0)
		# Blender yaw is about +Z and Godot's about +Y, and the sign does NOT
		# flip: the (x, y, z) -> (x, z, -y) swizzle is a -90 degree rotation
		# about X, which preserves handedness, so +90 in Blender is +90 here.
		#
		# This was negated, which mirrored every building's facing. It survived
		# because the props are near-symmetric in plan -- a hut looks like a hut
		# from either side -- and it only became visible once a FOLLOWER, which
		# has a face, was walking around them.
		node.rotation.y = deg_to_rad(float(p["yaw"]))
		var s := float(p.get("scale", 1.0))
		node.scale = Vector3(s, s, s)
		# Recorded for hover picking and the FX layer. Neither should
		# re-read the JSON to find the props: a second walk of the
		# layout is a second chance to disagree with the first.
		placed_props.append({"id": aid, "node": node,
			                     "pos": node.position})
		placed += 1
	print("[VALE] props: %d placed" % placed)
