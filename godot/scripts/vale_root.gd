extends Node3D

## The Vale scene: ground, light, camera rig, hover picking, FX, followers and
## the debug menu.
##
## Everything is assembled here at runtime rather than saved into the .tscn.
## Structural changes made inside an instantiated sub-scene are NOT serialised,
## so a builder that ran at scene-build time would write a scene that looks
## right in the editor and comes up empty when it runs.

const BUILDER := preload("res://scripts/vale_builder.gd")
const LIGHT := preload("res://scripts/vale_light.gd")
const RIG := preload("res://scripts/camera_rig.gd")
const HOVER := preload("res://scripts/hover.gd")
const FOLLOWER := preload("res://scripts/follower.gd")
const WALKGRID := preload("res://scripts/walk_grid.gd")

## Loaded defensively: two of these are authored by other agents in parallel and
## the scene must still come up if one is missing. A hard preload of a file that
## does not exist takes the whole scene down at parse time.
const FX_PATH := "res://scripts/fx.gd"
const SETTINGS_PATH := "res://scripts/settings.gd"
const DEBUG_PATH := "res://scripts/debug_menu.gd"

const CAM_START_COL := 32
const CAM_START_ROW := 50

## Where followers walk. Tile coordinates, so this stays readable against the
## ASCII map in blender/src/vale.py rather than being a list of world floats.
const ROAD_ROW := 49
const WALKERS := [
	{"asset": "Folk/villager", "path": [[5, 49], [30, 49], [52, 49], [76, 49]], "speed": 1.0},
	{"asset": "Folk/villager", "path": [[76, 51], [52, 51], [30, 51], [5, 51]], "speed": 0.9},
	{"asset": "Folk/adventurer", "path": [[21, 30], [21, 47], [40, 49], [60, 49]], "speed": 1.1},
	{"asset": "Folk/villager", "path": [[60, 48], [40, 48], [21, 48], [21, 30]], "speed": 0.95},
	{"asset": "Folk/villager", "path": [[33, 55], [33, 70], [50, 70], [50, 55]], "speed": 0.85},
	{"asset": "Folk/adventurer", "path": [[70, 55], [70, 44], [88, 44], [88, 55]], "speed": 1.0},
]

var builder: ValeBuilder
var light: Node3D
var rig: CameraRig
var pick: HoverPick
var fx: Node3D
var settings: Node
var menu: CanvasLayer

var grid: WalkGrid
var _spawned: Array = []
var _next_seed := 1
var _rng := RandomNumberGenerator.new()
var _walk_paths: Array = []          ## world-space paths, reused by the stress test


func _ready() -> void:
	builder = BUILDER.new()
	builder.name = "Vale"
	add_child(builder)

	light = LIGHT.new()
	light.name = "Light"
	add_child(light)

	rig = RIG.new()
	rig.name = "CameraRig"
	add_child(rig)
	rig.focus = builder.world_of(CAM_START_COL, CAM_START_ROW)
	# Clamp panning to the ground, with a margin so the edge can be inspected
	# but not left behind entirely.
	var pad := 4.0
	rig.set_bounds(builder.extent_min - Vector3(pad, 0, pad),
				   builder.extent_max + Vector3(pad, 0, pad))

	pick = HOVER.new()
	pick.name = "Pick"
	add_child(pick)
	pick.setup(rig, builder, builder.placed_props)
	pick.picked.connect(_on_picked)

	grid = WALKGRID.new()
	grid.build(builder.doc)

	_add_fx()
	_add_followers()
	_add_menu()


## Load an optional script, tolerating one that is missing OR broken.
##
## `ResourceLoader.exists()` only says a FILE is there. A script with a parse
## error still "exists", loads as a GDScript with no class behind it, and then
## `new()` fails with "Nonexistent function 'new'" -- which reads like the
## script is fine and the caller is wrong. can_instantiate() is the honest
## question.
func _optional(path: String, label: String) -> GDScript:
	if not ResourceLoader.exists(path):
		print("[VALE] no %s yet -- skipping" % label)
		return null
	var script: GDScript = load(path)
	if script == null or not script.can_instantiate():
		push_warning("[VALE] %s failed to compile -- skipping" % label)
		return null
	return script


func _add_fx() -> void:
	var script := _optional(FX_PATH, "fx.gd")
	if script == null:
		return
	fx = script.new()
	fx.name = "FX"
	add_child(fx)
	if fx.has_method("setup"):
		fx.setup(builder.placed_props)


func _add_menu() -> void:
	var sset := _optional(SETTINGS_PATH, "settings.gd")
	if sset != null:
		settings = sset.new()
		settings.name = "Settings"
		add_child(settings)
		if settings.has_method("load_all"):
			settings.load_all()
	var dbg := _optional(DEBUG_PATH, "debug_menu.gd")
	if dbg == null:
		return
	menu = dbg.new()
	menu.name = "DebugMenu"
	add_child(menu)
	if menu.has_method("setup"):
		var before := _light_state()
		menu.setup(light.env, light.sun, self, settings)
		_report_overrides(before, _light_state())


## Everything the debug panel can persist, read straight off the live objects.
func _light_state() -> Dictionary:
	var e: Environment = light.env
	var u: DirectionalLight3D = light.sun
	return {
		"fog_enabled": e.fog_enabled, "fog_density": e.fog_density,
		"fog_sun_scatter": e.fog_sun_scatter,
		"fog_aerial_perspective": e.fog_aerial_perspective,
		"glow_enabled": e.glow_enabled, "glow_intensity": e.glow_intensity,
		"tonemap_exposure": e.tonemap_exposure,
		"ambient_light_energy": e.ambient_light_energy,
		"ambient_light_sky_contribution": e.ambient_light_sky_contribution,
		"sun_energy": u.light_energy, "sun_shadow": u.shadow_enabled,
	}


## Say out loud when user://settings.json is overriding the code.
##
## This exists because of a real hour lost: a saved file from a debug session
## held `fog_density 0.01` and `ambient_sky 1.0`, so editing vale_light.gd
## changed NOTHING on screen -- including a fix that made the ambient energy
## live, which the saved contribution of 1.0 quietly re-broke. A settings file
## that silently wins over source is indistinguishable from a broken edit.
func _report_overrides(before: Dictionary, after: Dictionary) -> void:
	var diffs: Array[String] = []
	for k in before:
		var a: Variant = before[k]
		var b: Variant = after[k]
		# Annotated, not inferred: a ternary over two Variants has no static
		# type, and `:=` on it is a parse error rather than a runtime one.
		var same: bool = is_equal_approx(float(a), float(b)) 			if typeof(a) == TYPE_FLOAT else (a == b)
		if not same:
			diffs.append("%s %s -> %s" % [k, str(a), str(b)])
	if diffs.is_empty():
		return
	print("[SETTINGS] user://settings.json OVERRIDES the code in %d place(s):"
		% diffs.size())
	for d in diffs:
		print("    " + d)
	print("    Delete that file, or press Reset in the debug panel, to get the "
		+ "values in vale_light.gd back.")


func _on_picked(entry: Dictionary) -> void:
	if entry.size() == 0:
		return
	print("[PICK] %s at %.1f, %.1f" % [entry["id"], entry["pos"].x, entry["pos"].z])


## Villagers now think for themselves rather than patrolling a fixed loop, so
## WALKERS supplies only a starting place and a speed -- the route is the
## brain's business from the first frame.
func _add_followers() -> void:
	var made := 0
	for w in WALKERS:
		var cell: Array = w["path"][0]
		var at := builder.world_of(int(cell[0]), int(cell[1])) 			+ Vector3(0, builder.lift, 0)
		if _spawn_thinker(String(w["asset"]), at, float(w["speed"])) != null:
			made += 1
	print("[VALE] followers: %d thinking" % made)


func _spawn_thinker(asset_id: String, at: Vector3, speed: float) -> Node:
	var f := _make_follower(asset_id, [], speed)
	if f == null:
		return null
	f.position = at
	f.think(grid, _next_seed, speed)
	_next_seed += 1
	return f


func _make_follower(asset_id: String, pts: Array, speed: float) -> Node:
	var packed: PackedScene = builder._packed_of(asset_id)
	if packed == null:
		return null
	var node := packed.instantiate()
	# The GLB root is a plain Node3D. It is REPARENTED under a Follower rather
	# than having the script attached to it: a script on an imported scene root
	# does not survive a re-import.
	var f: Follower = FOLLOWER.new()
	f.name = "Follower%d" % get_child_count()
	add_child(f)
	f.add_child(node)
	var typed: Array[Vector3] = []
	for p in pts:
		typed.append(p as Vector3)
	f.setup(typed, speed)
	return f


## --- the stress test API the debug menu calls -------------------------------
##
## Spawned followers reuse the authored paths and are tracked separately from
## the scene's own, so `clear_spawned()` cannot delete the village's residents.

func spawn_follower() -> void:
	if grid == null:
		return
	# Dropped on a random WALKABLE cell, which is the only kind there is a
	# route out of. Spawning on the map at large would put half a stress test
	# inside the river.
	var cell := grid.random_cell(_rng)
	var asset := "Folk/villager" if _spawned.size() % 3 else "Folk/adventurer"
	var f := _spawn_thinker(asset, grid.world_of(cell), randf_range(0.8, 1.2))
	if f != null:
		_spawned.append(f)


func clear_spawned() -> void:
	for f in _spawned:
		if is_instance_valid(f):
			f.queue_free()
	_spawned.clear()


## FX density, exposed so the debug menu drives it through the host rather than
## reaching into the tree for a node it did not create.
func set_fx_density(scale: float) -> void:
	if fx != null and fx.has_method("set_density"):
		fx.set_density(scale)


func fx_particles() -> int:
	if fx != null and fx.has_method("active_count"):
		return fx.active_count()
	return 0


func spawned_count() -> int:
	return _spawned.size()


func follower_count() -> int:
	return WALKERS.size() + _spawned.size()
