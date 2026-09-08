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

## Scatter that nothing has to build around. Flowers, grass, reeds and lily
## pads are dressing: a villager walks through them and a hut is raised over
## them. Treating them as obstacles made a 7x7 building site need 49 cells
## clear of every tuft of grass on the map, and forty villagers with unlimited
## materials managed to raise ONE building in a whole run.
const SOFT := ["Nature/flowers", "Nature/tall_grass", "Nature/reeds",
			   "Nature/lily_pad", "Nature/crop_row", "Nature/apples"]

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
## The ground, in a form that can be edited one tile at a time. See set_tile.
var _ground_xforms: Dictionary = {}      ## asset_id -> Array[Transform3D]
var _tile_aid: Dictionary = {}           ## Vector2i -> asset_id (flat tiles)
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

## Props mid-topple: {node, axis, spin, t}. A tree that vanishes the instant
## the axe lands reads as a bug -- the player sees the swing and then a hole.
## It falls instead, and the RECORD is removed immediately so the walk grid and
## the picker are correct from the first frame while the body is still moving.
var _falling: Array[Dictionary] = []
const FALL_SECONDS := 0.85


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


## Change one tile, in the ground and in the document.
##
## THE WHOLE POINT OF THE DESERT. The world starts as dirt and the player turns
## it green a click at a time, so this runs constantly and cannot afford to
## rebuild anything: the tile's transform moves from one multimesh batch to
## another and only those two are re-uploaded. A thousand transforms is well
## under a millisecond, against ~30 ms to rebuild the ground.
##
## Only flat tiles -- a cliff top is two stacked blocks and is not something
## the player is turning into a meadow.
func set_tile(col: int, row: int, ch: String) -> bool:
	var cell := Vector2i(col, row)
	if not _tile_aid.has(cell):
		return false
	var code: Dictionary = doc.get("code", {})
	if not code.has(ch):
		return false
	var want := String(code[ch])
	var had := String(_tile_aid[cell])
	if want == had:
		return false

	var base := world_of(col, row)
	var moved := false
	var from: Array = _ground_xforms.get(had, [])
	for i in from.size():
		if (from[i] as Transform3D).origin.distance_squared_to(base) < 0.001:
			from.remove_at(i)
			moved = true
			break
	if not moved:
		return false
	if not _ground_xforms.has(want):
		_ground_xforms[want] = []
	(_ground_xforms[want] as Array).append(Transform3D(Basis(), base))
	_tile_aid[cell] = want
	_upload(had)
	_upload(want)

	# The DOCUMENT too, or the change is a lick of paint: the walk grid, the
	# save and every buildability test read this, not the multimesh.
	if row >= 0 and row < lower.size():
		var line: String = lower[row]
		if col >= 0 and col < line.length():
			lower[row] = line.substr(0, col) + ch + line.substr(col + 1)
	return true


func _upload(aid: String) -> void:
	var inst := _multi_for(aid)
	if inst == null:
		return
	var xforms: Array = _ground_xforms.get(aid, [])
	inst.multimesh.instance_count = xforms.size()
	for i in xforms.size():
		inst.multimesh.set_instance_transform(i, xforms[i])


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

	# KEPT, so one tile can change later without rebuilding the world.
	# `_ground_xforms` is the same data the multimeshes hold, in a form that
	# can be edited; `_tile_aid` says which batch a cell currently lives in.
	_ground_xforms = batches
	_tile_aid.clear()
	for row in rows:
		for col in cols:
			var lo := code_at(lower, col, row)
			if lo != "." and code_at(upper, col, row) == "." and code.has(lo):
				_tile_aid[Vector2i(col, row)] = String(code[lo])

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
							 "yaw": float(p["yaw"]), "scale": s,
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
	# NOTHING MAY STAND ON SOMETHING ELSE.
	#
	# This checked only the tile CODE, never whether a prop was already there,
	# which is why buildings were seen stacked on each other in play. The tile
	# test answers "is this ground" and was being asked "is this free" -- two
	# different questions, and the second one was never asked at all.
	if would_overlap(aid, col, row):
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
						 "yaw": yaw, "scale": scale_v,
						 "fp": Islands.FOOTPRINTS.get(aid, [0.5, 0.5])})
	if aid.begins_with("Buildings/"):
		_clear_site(aid, col, row)
	return true


## Clear the ground a new building now stands on.
##
## Everything inside the footprint goes -- dressing AND trees. Flowers growing
## up through a cottage floor is the tell that two systems never spoke, and
## refusing to build because a sapling is in the way is why a hut had zero
## valid sites on the whole map.
func _clear_site(aid: String, col: int, row: int) -> void:
	var fp: Array = Islands.FOOTPRINTS.get(aid, [0.5, 0.5])
	var hc := int(ceil(float(fp[0]) / tile / 2.0))
	var hr := int(ceil(float(fp[1]) / tile / 2.0))
	for e in placed_props.duplicate():
		if String(e["id"]).begins_with("Buildings/"):
			continue                     # would_overlap already refused these
		var near_col := absi(int(e.get("col", -999)) - col) <= hc
		var near_row := absi(int(e.get("row", -999)) - row) <= hr
		if near_col and near_row:
			remove_prop(e)


## Would a prop of this kind at this cell collide with something standing?
##
## Rectangle overlap between declared footprints, in CELLS. Buildings are the
## ones that matter -- a hut is 5x5 cells and two of them 3 cells apart look
## like one broken building -- but scatter is tested too, so trees do not grow
## inside each other.
##
## `ceil` on the half-extent for the same reason the walk grid uses it: a
## 2.15 m building spans more than four 0.5 m tiles, and rounding down leaves
## an overlap the test says is fine.
func would_overlap(aid: String, col: int, row: int) -> bool:
	var mine: Array = Islands.FOOTPRINTS.get(aid, [0.5, 0.5])
	var hc := int(ceil(float(mine[0]) / tile / 2.0))
	var hr := int(ceil(float(mine[1]) / tile / 2.0))
	# A BUILDING only collides with other BUILDINGS.
	#
	# It clears its own site of trees, stumps and dressing when it goes up
	# (`_clear_site`), so those must not veto it here -- and `is_buildable`,
	# which chose the site, already ignores them. The two disagreed: the site
	# test said yes and this said no, and 113 of 197 placements were refused
	# after a villager had walked there with the materials.
	#
	# Anything else -- a miracle-grown tree, a scattered rock -- avoids
	# everything solid, because nothing clears the ground for it.
	var mine_is_building := aid.begins_with("Buildings/")
	for e in placed_props:
		if not is_instance_valid(e.get("node")):
			continue
		var theirs_is_building := String(e["id"]).begins_with("Buildings/")
		if mine_is_building and not theirs_is_building:
			continue
		if String(e["id"]) in SOFT:
			continue                     # dressing; built over, not around
		var oc := int(e.get("col", -999))
		var orow := int(e.get("row", -999))
		if oc < -900:
			continue
		var theirs: Array = e.get("fp", [0.5, 0.5])
		var ohc := int(ceil(float(theirs[0]) / tile / 2.0))
		var ohr := int(ceil(float(theirs[1]) / tile / 2.0))
		if absi(col - oc) <= hc + ohc and absi(row - orow) <= hr + ohr:
			return true
	return false


## Take one out. The entry is removed from `placed_props` FIRST, so nothing can
## observe the list holding a freed node -- queue_free is deferred, and a picker
## running this frame would happily test its AABB.
## Take a prop out of the world by TIPPING IT OVER, away from `from`.
##
## The entry leaves `placed_props` at once -- pathing and picking must agree
## with the rules immediately -- and only the visual body lingers. Doing it the
## other way round would leave a felled tree still blocking the tile it fell
## off.
func fell_prop(entry: Dictionary, from: Vector3) -> void:
	placed_props.erase(entry)
	var node = entry.get("node")
	if not is_instance_valid(node):
		return
	var away: Vector3 = node.position - from
	away.y = 0.0
	if away.length_squared() < 0.001:
		away = Vector3(1, 0, 0)
	away = away.normalized()
	# Rotate about the horizontal axis PERPENDICULAR to the fall direction, so
	# the trunk lies down away from whoever was chopping it.
	_falling.append({"node": node, "axis": Vector3(-away.z, 0.0, away.x),
					 "t": 0.0, "base": node.position.y})


func _process(delta: float) -> void:
	if _falling.is_empty():
		return
	var kept: Array[Dictionary] = []
	for e in _falling:
		var node = e["node"]
		if not is_instance_valid(node):
			continue
		var t: float = float(e["t"]) + delta / FALL_SECONDS
		e["t"] = t
		if t >= 1.0:
			node.queue_free()
			continue
		# Accelerating fall, then a short sink so it leaves rather than lying
		# there forever accumulating.
		var ang: float = deg_to_rad(84.0) * minf(1.0, t * t * 1.6)
		node.basis = Basis(e["axis"], ang)
		node.position.y = float(e["base"]) - maxf(0.0, (t - 0.75) * 1.6)
		kept.append(e)
	_falling = kept


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
		props.append({"id": e["id"], "col": col, "row": row,
					  "yaw": float(e.get("yaw", 0.0)),
					  "scale": float(e.get("scale", 1.0)),
					  "fp": e.get("fp", [0.5, 0.5])})
	out["props"] = props
	return out


## The regenerated layout, with everything that has HAPPENED folded back in.
##
## Buying land regenerates the world document, and rebuild() frees every prop
## and builds the new one. Handed the raw generated document that DEMOLISHED
## THE VILLAGE: every hut the followers had raised vanished, and every tree
## they had felled grew back. It was invisible because both halves undo each
## other in a screenshot -- the village looks like a village either way, just
## an earlier one.
##
## The cost was not cosmetic. A probe of a player who buys land but never
## blesses earned LESS Faith over ten minutes than one who touched nothing at
## all (339 against 443), because they paid three times to reset their own
## village. Land was the standing decision of the run and it was a trap.
##
## `live_doc` already had the principle for the walk grid -- "rebuilding from
## doc alone would resurrect every tree a miracle burned down" -- and was never
## applied to the world itself.
##
## The merge holds because the grid is a FIXED size (Islands.GRID * PITCH +
## MARGIN * 2, independent of how much is owned), so a cell index means the
## same place before and after. Anything in the new document that the old one
## did not list is genuinely new ground; everything else comes from what is
## actually standing.
func carry_doc(base: Dictionary) -> Dictionary:
	# THE GROUND THE PLAYER MADE COMES WITH THEM.
	#
	# Buying land regenerates the world from the generator, and the generator
	# now emits bare dirt -- so without this every tile the player had greened
	# turned back to desert the moment they bought a plot. The whole opening,
	# undone by the reward for finishing it.
	#
	# The rule is simple and covers more than grass: wherever the OLD document
	# had a tile, that tile wins. New land arrives as whatever the generator
	# says, which is dirt, and that is exactly right -- a plot you have just
	# bought should be bare.
	var carried: Array = []
	var base_lower: Array = base.get("lower", [])
	for row in base_lower.size():
		var line: String = base_lower[row]
		if row < lower.size():
			var old_line: String = lower[row]
			var out := ""
			for col in line.length():
				var had := "." if col >= old_line.length() else old_line[col]
				out += line[col] if had == "." else had
			line = out
		carried.append(line)
	base["lower"] = carried

	var was := {}
	for p in (doc.get("props", []) as Array):
		was["%d,%d" % [int(p["col"]), int(p["row"])]] = true

	var out := base.duplicate()
	var props: Array = []
	# What stands now, whatever put it there.
	for e in placed_props:
		if not is_instance_valid(e.get("node")):
			continue
		var col: int = int(e.get("col", -1))
		var row: int = int(e.get("row", -1))
		if col < 0:
			var c := cell_of(e["pos"])
			col = c.x
			row = c.y
		props.append({"id": e["id"], "col": col, "row": row,
					  "yaw": float(e.get("yaw", 0.0)),
					  "scale": float(e.get("scale", 1.0)),
					  "fp": e.get("fp", [0.5, 0.5])})
	# Plus the dressing on ground that was not ours until now.
	for p in (base.get("props", []) as Array):
		if was.has("%d,%d" % [int(p["col"]), int(p["row"])]):
			continue
		props.append(p)
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
