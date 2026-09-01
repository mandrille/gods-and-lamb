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


## Set BEFORE the node enters the tree to build a generated world instead of
## reading data/vale.json. The archipelago uses this; the Blender-authored Vale
## still comes off disk, and both go through exactly one builder.
var source_doc: Dictionary = {}


func _ready() -> void:
	if source_doc.is_empty():
		_load()
	else:
		_adopt(source_doc)
	_build_ground()
	_build_props()


## Throw the world away and build a different one.
##
## Everything derived from the layout goes with it -- the ground batches, the
## prop nodes, and `placed_props`, which hover picking and FX both hold. Leaving
## any of those behind is how a bought island arrives with the previous world
## still standing inside it, and the stale AABBs in `placed_props` would make
## the picker report hits on props that are no longer there.
func rebuild(new_doc: Dictionary) -> void:
	for inst in _multi.values():
		if is_instance_valid(inst):
			inst.queue_free()
	_multi.clear()
	for entry in placed_props:
		var n = entry.get("node")
		if is_instance_valid(n):
			n.queue_free()
	placed_props.clear()
	var skirt := get_node_or_null("Skirt")
	if skirt != null:
		skirt.queue_free()
	_adopt(new_doc)
	_build_ground()
	_build_props()


func _adopt(d: Dictionary) -> void:
	doc = d
	tile = float(doc.get("tile", 0.5))
	lift = float(doc.get("lift", 0.5))
	upper_blocks = int(doc.get("upper_blocks", 2))
	water_drop = float(doc.get("water_drop", 0.06))
	cols = int(doc.get("cols", 0))
	rows = int(doc.get("rows", 0))
	lower = doc.get("lower", [])
	upper = doc.get("upper", [])


func _load() -> void:
	var f := FileAccess.open(DATA, FileAccess.READ)
	if f == null:
		push_error("ValeBuilder: cannot open %s -- run `build.py -- export`" % DATA)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ValeBuilder: %s is not a JSON object" % DATA)
		return
	# One place that reads a document into fields, so the file path and the
	# generated path cannot drift apart.
	_adopt(parsed)


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
	_normalise_vertex_colour(packed)
	_scenes[asset_id] = packed
	return packed


## Make every material in a library asset multiply COLOR_0 into its albedo.
##
## That is the pipeline's invariant -- the Blender side bakes AO into COLOR_0
## and wires every material to read it, and glTF defines COLOR_0 as multiplying
## into base colour. Godot's glTF importer does not carry it across reliably:
## measured across four assets, the material on SURFACE 0 comes in with the
## flag clear and every later surface comes in with it set.
##
##     Buildings/hut   Plaster false, Hollow/Wood/Thatch/WoodDark true
##     Terrain/grass   Dirt    false, Grass true
##     Nature/tree     Trunk   false, LeafDark/LeafLight/Leaf true
##     Folk/villager   the single folded material, false
##
## So every tree trunk, every dirt tile and every hut wall in this village has
## been rendering without its baked AO, and nobody could see it because the
## other surfaces of the same asset looked right. It only became obvious when
## the folk were folded to ONE surface and a villager came back as a flat blue
## silhouette with no colour at all.
##
## Setting the flag here rather than in an import script keeps it in one place
## that headless tools, the editor and the exported build all go through --
## an .import sidecar has to be written twice for a new GLB before Godot will
## even attach a post-import script to it.
func _normalise_vertex_colour(packed: PackedScene) -> void:
	var state := packed.get_state()
	var seen := {}
	for i in state.get_node_count():
		for j in state.get_node_property_count(i):
			if String(state.get_node_property_name(i, j)) != "mesh":
				continue
			var mesh: Mesh = state.get_node_property_value(i, j) as Mesh
			if mesh == null:
				continue
			for k in mesh.get_surface_count():
				var mat := mesh.surface_get_material(k) as BaseMaterial3D
				if mat == null or seen.has(mat.get_instance_id()):
					continue
				seen[mat.get_instance_id()] = true
				mat.vertex_color_use_as_albedo = true


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
	_add_skirt()
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
		placed_props.append({"id": aid, "node": node, "pos": node.position,
							 "col": col, "row": row,
							 "fp": p.get("fp", [0.5, 0.5])})
		placed += 1
	print("[VALE] props: %d placed" % placed)


## Put one more thing into the world after the build, and record it exactly the
## way the initial pass does.
##
## Same record shape, appended to the same list, because hover picking, FX and
## the walk grid all read `placed_props` -- a miracle-grown tree that is not in
## that list is a tree nobody can click, nothing walks around, and no smoke ever
## rises from. Returns false rather than placing something in the sea.
func add_prop(aid: String, col: int, row: int, yaw := 0.0,
			  scale_v := 1.0) -> bool:
	if col < 0 or row < 0 or col >= cols or row >= rows:
		return false
	if code_at(lower, col, row) in [".", "W"]:
		return false
	var packed := _packed_of(aid)
	if packed == null:
		return false
	var node := packed.instantiate()
	add_child(node)
	node.position = world_of(col, row) + Vector3(0, lift, 0)
	node.rotation.y = deg_to_rad(yaw)
	node.scale = Vector3(scale_v, scale_v, scale_v)
	placed_props.append({"id": aid, "node": node, "pos": node.position,
						 "col": col, "row": row,
						 "fp": Islands.FOOTPRINTS.get(aid, [0.5, 0.5])})
	return true


## Take one out. The entry is removed from `placed_props` FIRST, so nothing can
## observe the list holding a freed node -- queue_free is deferred, and a picker
## running this frame would happily test its AABB.
func remove_prop(entry: Dictionary) -> void:
	placed_props.erase(entry)
	var node = entry.get("node")
	if is_instance_valid(node):
		node.queue_free()


## The layout as the walk grid wants it: the current document, but with `props`
## replaced by what is ACTUALLY standing right now. Rebuilding the grid from
## `doc` alone would resurrect every tree a miracle burned down.
func live_doc() -> Dictionary:
	var out := doc.duplicate()
	var props: Array = []
	for e in placed_props:
		if not is_instance_valid(e.get("node")):
			continue
		var col: int = int(e.get("col", -1))
		var row: int = int(e.get("row", -1))
		if col < 0:
			var c := cell_of(e["pos"])
			col = c.x
			row = c.y
		props.append({"id": e["id"], "col": col, "row": row, "yaw": 0.0,
					  "scale": 1.0, "fp": e.get("fp", [0.5, 0.5])})
	out["props"] = props
	return out


## Inverse of world_of. Kept here rather than duplicated in the grid, so the
## two cannot disagree about where a tile is.
func cell_of(world: Vector3) -> Vector2i:
	var ox := -float(cols - 1) * tile * 0.5
	var oz := -float(rows - 1) * tile * 0.5
	return Vector2i(int(round((world.x - ox) / tile)),
					(rows - 1) - int(round((world.z - oz) / tile)))

## A flat plane of distant grass, far beyond the map, one draw call.
##
## The play camera is pitched down about 35 degrees with a half-FOV under 20,
## so the frame NEVER reaches the horizon: everything past the last tile is the
## sky's ground hemisphere, which is a flat slab of colour. It reads as heavy
## haze, and it was reported as "the fog is too aggressive" when measurement
## showed the fog contributes 0.008 of mean luma and that slab contributes
## 0.041 -- five times more.
##
## Fog cannot fix that, because there is nothing out there for fog to sit on.
## Ground can. The skirt sits a hair below the tile tops so it cannot z-fight
## with them, and it is a desaturated grass so the tiles read as the near
## detail of a landscape that keeps going.
## The colour the world fades into: the most common ground tile along the map
## border, pushed toward the sky.
func _horizon_colour() -> Color:
	var tally := {}
	for col in cols:
		for row in [0, rows - 1]:
			var c := code_at(lower, col, row)
			tally[c] = int(tally.get(c, 0)) + 1
	for row in rows:
		for col in [0, cols - 1]:
			var c := code_at(lower, col, row)
			tally[c] = int(tally.get(c, 0)) + 1
	var best := "G"
	var top := -1
	for c in tally:
		if String(c) != "." and int(tally[c]) > top:
			top = int(tally[c])
			best = String(c)
	var by_code := {"W": Color(0.24, 0.52, 0.72), "G": Color(0.34, 0.50, 0.31),
					"A": Color(0.72, 0.66, 0.46), "S": Color(0.46, 0.47, 0.49),
					"D": Color(0.42, 0.33, 0.24), "P": Color(0.52, 0.51, 0.48),
					"C": Color(0.38, 0.29, 0.21)}
	return by_code.get(best, Color(0.34, 0.50, 0.31))


func _add_skirt() -> void:
	var span := maxf(extent_max.x - extent_min.x, extent_max.z - extent_min.z)
	var plane := PlaneMesh.new()
	plane.size = Vector2(span * 12.0, span * 12.0)
	var mat := StandardMaterial3D.new()
	# Coloured after whatever the map actually ENDS in, desaturated and lifted
	# in value: this is DISTANCE, and matching the near tiles exactly makes the
	# map edge vanish into a flat field with no depth to it.
	#
	# It was a fixed meadow green, which was right for a continuous landscape
	# and became a green horizon around an archipelago the moment the world
	# turned to ocean. Reading the dominant edge tile means it cannot be wrong
	# again for the next kind of world either.
	mat.albedo_color = _horizon_colour()
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Skirt"
	mi.mesh = plane
	# At the BASE of the tiles, not near their tops.
	#
	# The first version sat 1.5 cm under the tile top and hid the river: water
	# tiles are sunk 6 cm, so a skirt above them covers them. Anything that
	# passes UNDER the terrain has to clear the lowest surface in it, not the
	# highest -- and at y=0 it is below every tile, so it is only ever visible
	# out past the last one, which is the whole job.
	mi.position = Vector3((extent_min.x + extent_max.x) * 0.5, 0.0,
						  (extent_min.z + extent_max.z) * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
