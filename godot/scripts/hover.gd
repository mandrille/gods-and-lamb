extends Node
class_name HoverPick

## Hover and click highlighting for props and ground tiles.
##
## NO PHYSICS. There is no StaticBody, no collision shape and no raycast query
## anywhere in this game -- that is a standing design decision, not an
## oversight, and adding a collider per prop to get a hover would quietly undo
## it. Instead the ray is intersected against each prop's AABB directly. There
## are a few hundred props; a ray-box test is a handful of compares, and the
## whole pass is cheaper than the physics server would be to merely exist.
##
## The highlight itself is `material_overlay`, which is a PER-INSTANCE property.
## That matters: every cottage in the village shares ONE mesh resource, so
## touching a material would light up all of them at once.

signal hovered(entry: Dictionary)      ## {} when nothing is under the cursor
signal picked(entry: Dictionary)

const HOVER_TINT := Color(1.0, 1.0, 1.0, 0.20)
const PICK_TINT := Color(1.0, 0.86, 0.42, 0.42)

var rig: CameraRig
var builder: Node
var props: Array = []                   ## [{id, node, aabb (world), pos}]

var _hover: Dictionary = {}
var _picked: Dictionary = {}
var _hover_mat: StandardMaterial3D
var _pick_mat: StandardMaterial3D
var _last_screen := Vector2(-1, -1)


func _ready() -> void:
	_hover_mat = _overlay(HOVER_TINT)
	_pick_mat = _overlay(PICK_TINT)


func _overlay(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	# No depth write, and no cull change: the overlay is a wash over whatever
	# the mesh already drew, so it must not fight the mesh for the depth buffer.
	m.no_depth_test = false
	m.disable_receive_shadows = true
	return m


func setup(camera_rig: CameraRig, vale_builder: Node, prop_nodes: Array) -> void:
	rig = camera_rig
	builder = vale_builder
	props.clear()
	for p in prop_nodes:
		var node: Node3D = p["node"]
		var aabb := _world_aabb(node)
		if aabb.size == Vector3.ZERO:
			continue
		props.append({"id": p["id"], "node": node, "aabb": aabb,
					  "pos": node.global_position})


## The union of every MeshInstance3D AABB under a node, in world space.
func _world_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for d in _walk(n):
		if d is MeshInstance3D:
			var mi := d as MeshInstance3D
			if mi.mesh == null:
				continue
			var box := mi.global_transform * mi.mesh.get_aabb()
			if first:
				out = box
				first = false
			else:
				out = out.merge(box)
	return out


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out


func _process(_d: float) -> void:
	if rig == null or rig.cam == null:
		return
	var vp := get_viewport()
	var m := vp.get_mouse_position()
	if m == _last_screen:
		return
	_last_screen = m
	_set_hover(_pick_at(m))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			# On RELEASE, and only if the cursor barely moved. Otherwise every
			# pan ends by selecting whatever the drag happened to finish over.
			if _hover.size() > 0:
				_set_picked(_hover)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			# Touch has no hover, so a tap has to do both jobs at once.
			var hit := _pick_at(st.position)
			_set_hover(hit)
			_set_picked(hit)


func _pick_at(screen: Vector2) -> Dictionary:
	var from := rig.cam.project_ray_origin(screen)
	var dir := rig.cam.project_ray_normal(screen)
	var best: Dictionary = {}
	var best_t := INF
	for p in props:
		var box: AABB = p["aabb"]
		var hit: Variant = box.intersects_ray(from, dir)
		if hit == null:
			continue
		var t := from.distance_to(hit as Vector3)
		if t < best_t:
			best_t = t
			best = p
	return best


func _set_hover(entry: Dictionary) -> void:
	if entry.get("node") == _hover.get("node"):
		return
	_apply(_hover, null)
	_hover = entry
	if _hover.size() > 0 and _hover.get("node") != _picked.get("node"):
		_apply(_hover, _hover_mat)
	hovered.emit(_hover)


func _set_picked(entry: Dictionary) -> void:
	_apply(_picked, null)
	_picked = entry
	_apply(_picked, _pick_mat)
	picked.emit(_picked)


func _apply(entry: Dictionary, mat: Material) -> void:
	if entry.size() == 0:
		return
	var node: Node3D = entry.get("node")
	if node == null or not is_instance_valid(node):
		return
	for d in _walk(node):
		if d is MeshInstance3D:
			(d as MeshInstance3D).material_overlay = mat


func clear() -> void:
	_apply(_hover, null)
	_apply(_picked, null)
	_hover = {}
	_picked = {}
