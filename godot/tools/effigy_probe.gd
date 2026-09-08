extends SceneTree
## A gallery shot of every miracle's bespoke effigy.
##
## Not a correctness check -- there is nothing to assert about what a tree
## looks like -- this exists so a redesign of the shapes can be reviewed as
## pictures rather than as GDScript. One screenshot per card in the deck,
## framed the same way, at the same scale, so they can be compared side by
## side.
const ShotWindowRef := preload("res://tools/shot_window.gd")

const IDS := ["rain", "grove", "bounty", "feast", "revel", "mend", "calm",
			  "upheaval"]

var _f := 0
var _root: Node = null
var _i := 0
var _settle := 0


func _initialize() -> void:
	ShotWindowRef.park()
	get_root().add_child(
		(load("res://scenes/vale.tscn") as PackedScene).instantiate())


func _process(_d: float) -> bool:
	_f += 1
	if _f == 30:
		for n in get_root().get_children():
			if n.get("divinity") != null:
				_root = n
		if _root == null:
			printerr("[EFFIGY] FAIL: no scene root")
			quit(1)
			return true
		# The camera is placed ONCE, here, not per shot -- see the note in
		# the per-shot block below for why that matters.
		_root.rig.focus = Vector3.ZERO
		_root.rig.dist = 30.0
		_root.rig.call("_place")
		return false
	if _f < 30:
		return false

	if _i >= IDS.size():
		print("[EFFIGY] %d shots written to res://shots/effigy_*.png"
			% IDS.size())
		quit(0)
		return true

	var c = _root.cursor
	if _settle == 0:
		# Aimed at screen CENTRE directly, and the camera is placed ONCE at
		# frame 30 (not here) -- recomputing a ground point via ground_at()
		# before the new dist/focus had actually been applied read the ray
		# against the PREVIOUS shot's camera transform, and the error
		# compounded shot over shot until effigies were drifting metres apart.
		#
		# Screen centre, not world origin: the camera's DIR is a genuinely
		# oblique angle (see camera_rig.gd), so a point floating straight up
		# in world Y does not stay centred in screen space on its own -- it
		# drifts diagonally, enough at a tight dist to push a magnificent
		# tree entirely off-frame while a shorter cloud still read fine.
		# Following the pointer at screen centre keeps the FLOATED anchor
		# close to centre by construction, for every shape.
		#
		# The RAW viewport, not get_visible_rect(): the latter is canvas
		# (stretched, 2D-UI) space, and camera-ray math wants the same space
		# Camera3D itself projects in -- mixing the two is the same class of
		# bug this project already hit once for HUD hit-testing.
		c._pointer_override = Vector2(_root.rig.get_viewport().size) * 0.5
		c.begin(IDS[_i], 4.5)
		_settle = 1
		return false
	_settle += 1
	# A handful of frames so the idle sway/spin/orbit/pulse motion has visibly
	# started, and the first _apply has run, before the picture is taken.
	if _settle < 10:
		return false

	var path := "res://shots/effigy_%s.png" % IDS[_i]
	if not ShotWindowRef.can_shoot():
		print("[EFFIGY] no display: %s not photographed" % IDS[_i])
	else:
		ShotWindow.shoot(path)
		print("[EFFIGY] %s -> %s" % [IDS[_i], path])
	c.release()
	_i += 1
	_settle = 0
	return false
