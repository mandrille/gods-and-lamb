extends Node3D
class_name PlotMarkers

## The land you can buy, shown as land rather than as a button.
##
## Item 5: "clicking on the side expands it". So every buyable plot gets a
## translucent plate lying on the water exactly where the ground will appear,
## with its price floating over it, and clicking the plate buys it. The player
## never has to work out which compass button corresponds to which patch of
## sea -- the thing they click IS the thing they get, at the size they get it.
##
## Plates are rebuilt whenever the archipelago changes. There are at most a
## handful, so rebuilding is simpler than diffing and cannot drift.

signal plot_clicked(slot: Vector2i)

## Just above the WATER SURFACE, which is not y=0.
##
## A ground tile is `lift` tall standing on y=0, so its top is at 0.5, and
## water is sunk by `water_drop` to 0.44. The first version put the plates at
## 0.06 -- comfortably inside the seabed -- so nothing rendered at all and only
## the floating price labels gave any sign the plots were there.
const PLATE_Y := 0.47
const READY := Color(0.55, 0.92, 0.62, 0.30)
const HOVER := Color(0.75, 1.00, 0.80, 0.46)
const POOR := Color(0.85, 0.72, 0.45, 0.20)

var islands = null
var divinity = null
var rig = null

var _plates: Dictionary = {}       ## slot -> {mesh, label, rect}
var _hover := Vector2i(-99, -99)


func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_plates.clear()
	if islands == null:
		return
	var price: int = islands.price_next()
	var span := float(Islands.SPAN) * Islands.TILE

	for slot in islands.buyable():
		var centre := _world_of(islands.centre_cell(slot))

		var plane := PlaneMesh.new()
		# A tile short on each side, so neighbouring plates never touch and the
		# gap between plots stays readable as water.
		plane.size = Vector2(span - Islands.TILE * 2.0,
							 span - Islands.TILE * 2.0)
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = READY
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		plane.material = mat

		var mi := MeshInstance3D.new()
		mi.mesh = plane
		mi.position = centre + Vector3(0, PLATE_Y, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

		# Label3D rather than a projected 2D label: it sits in the world, so it
		# pans and zooms with the plate it belongs to and cannot drift off it.
		var tag := Label3D.new()
		tag.text = "%d Faith" % price
		tag.font_size = 96
		tag.pixel_size = 0.0032
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.modulate = Color(1, 1, 1, 0.95)
		tag.outline_size = 28
		tag.outline_modulate = Color(0, 0, 0, 0.75)
		tag.position = centre + Vector3(0, 1.2, 0)
		add_child(tag)

		_plates[slot] = {"mesh": mi, "mat": mat, "label": tag,
						 "centre": centre, "half": span * 0.5 - Islands.TILE}
	_repaint()


func _world_of(cell: Vector2i) -> Vector3:
	var n := float(islands.cols())
	var ox := -(n - 1.0) * Islands.TILE * 0.5
	var oz := -(n - 1.0) * Islands.TILE * 0.5
	return Vector3(ox + cell.x * Islands.TILE, 0.0,
				   oz + (n - 1.0 - cell.y) * Islands.TILE)


func _process(_d: float) -> void:
	if rig == null or rig.cam == null or _plates.is_empty():
		return
	var was := _hover
	_hover = _slot_under(get_viewport().get_mouse_position())
	if _hover != was:
		_repaint()


## Which plate is under a screen point, by intersecting the ground plane and
## testing the square. No physics and no picking layer -- the plates are flat,
## axis-aligned and few, so this is two compares each.
func _slot_under(screen: Vector2) -> Vector2i:
	var hit: Variant = rig.ground_at(screen)
	if hit == null:
		return Vector2i(-99, -99)
	var at: Vector3 = hit
	for slot in _plates:
		var e: Dictionary = _plates[slot]
		var c: Vector3 = e["centre"]
		var half: float = e["half"]
		if absf(at.x - c.x) <= half and absf(at.z - c.z) <= half:
			return slot
	return Vector2i(-99, -99)


func _repaint() -> void:
	var afford: bool = divinity == null \
		or divinity.can_afford(float(islands.price_next()))
	for slot in _plates:
		var e: Dictionary = _plates[slot]
		var mat: StandardMaterial3D = e["mat"]
		if not afford:
			mat.albedo_color = POOR
		else:
			mat.albedo_color = HOVER if slot == _hover else READY
		(e["label"] as Label3D).modulate = Color(1, 1, 1,
			0.95 if afford else 0.55)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	var slot := _slot_under(mb.position)
	if slot.x < -1:
		return
	plot_clicked.emit(slot)
	get_viewport().set_input_as_handled()
