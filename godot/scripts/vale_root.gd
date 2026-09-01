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

## How many villagers the plot opens with.
##
## Two. The first plot has no buildings, no wood and three days of food, so the
## opening is two people on bare ground deciding what to do about it -- and the
## first hut is something the player watches get earned rather than something
## the world came with.
const START_FOLK := 2

## Walk speed multiplier. The authored stride is 0.46 m per cycle, which at 1.0
## is 0.46 m/s -- and on a 12.5 m island that is 27 seconds to cross, so
## villagers spent nearly all of their lives in transit and completed about
## five errands each in a simulated hour. The slower-draining needs (Faith
## especially) were then almost never the most urgent thing at the moment
## anyone re-planned, so praying essentially never happened and the shrine
## looked broken when the problem was pace.
##
## The animation follows this: `_play` sets the clip's speed_scale to the same
## number, so the feet still match the ground at any value here.
const WALK_MIN := 1.6
const WALK_MAX := 2.1


var builder: ValeBuilder
var light: Node3D
var rig: CameraRig
var pick: HoverPick
var fx: Node3D
var settings: Node
var menu: CanvasLayer

var grid: WalkGrid
var village: Village
var social: Social
var islands: Islands
var divinity: Divinity
var ui: CanvasLayer
var overhead: Overhead
var panel: VillagerPanel
var hud: HUD
var fxe: FXEvents
var sfx: SFX
var plots: PlotMarkers

## Every follower with a mind, scene residents and stress-spawns alike. The
## social layer needs ONE list to match pairs from; keeping two and iterating
## both would let a resident and a spawn stand nose to nose in silence.
var folk: Array = []

var _spawned: Array = []
var _next_seed := 1
var _rng := RandomNumberGenerator.new()
var _walk_paths: Array = []          ## world-space paths, reused by the stress test


func _ready() -> void:
	islands = Islands.new()
	builder = BUILDER.new()
	builder.name = "Vale"
	# Handed the generated archipelago BEFORE it enters the tree: the builder
	# reads data/vale.json in _ready() otherwise, and add_child runs _ready
	# immediately.
	builder.source_doc = islands.build_doc()
	add_child(builder)

	light = LIGHT.new()
	light.name = "Light"
	add_child(light)

	rig = RIG.new()
	rig.name = "CameraRig"
	add_child(rig)
	# Centred on the home island, which is the middle slot of the grid.
	var home_mid: int = Islands.MARGIN + (Islands.GRID / 2) * Islands.PITCH 						+ Islands.SPAN / 2
	rig.focus = builder.world_of(home_mid, home_mid)
	# Framed on ONE plot, not on the whole archipelago. The plot is 10.5 m
	# across and the default 30 m pull-back was set for a 48 m landscape, which
	# left the village a postage stamp in a field of blue.
	rig.dist = 17.0
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

	village = Village.new()
	village.pop_cap = islands.pop_cap()
	village.census(builder.placed_props)
	social = Social.new(20260901)

	divinity = Divinity.new()
	divinity.name = "Divinity"
	divinity.host = self
	divinity.village = village
	divinity.islands = islands
	divinity.builder = builder
	divinity.grid = grid
	add_child(divinity)

	_add_fx()
	fxe = FXEvents.new()
	fxe.name = "FXEvents"
	add_child(fxe)
	sfx = SFX.new()
	sfx.name = "SFX"
	add_child(sfx)

	_add_followers()
	_add_ui()
	_wire_feedback()
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


## The island's residents.
##
## Spawned onto walkable cells of the home island rather than at authored
## coordinates: the world is generated now, so a hard-coded tile is a promise
## about terrain nobody made. Capped by the island, which is the whole point of
## item 6 -- five people on a small island is a village you can watch.
func _add_followers() -> void:
	var made := 0
	var want: int = mini(START_FOLK, islands.pop_cap())
	var home := Vector2i(Islands.GRID / 2, Islands.GRID / 2)
	var tries := 0
	while made < want and tries < 400:
		tries += 1
		var cell := grid.random_cell(_rng)
		# On the STARTING island specifically. random_cell is happy to return a
		# bridge deck or, once more islands are bought, somewhere across the
		# water that nobody has any business being born on.
		if islands.slot_of_cell(cell) != home:
			continue
		var asset := "Folk/adventurer" if made % 3 == 2 else "Folk/villager"
		var at := grid.world_of(cell)
		if _spawn_thinker(asset, at, _rng.randf_range(WALK_MIN, WALK_MAX)) != null:
			made += 1
	village.population = made
	print("[VALE] followers: %d of %d cap, %s"
		% [made, islands.pop_cap(), village.summary()])


func _spawn_thinker(asset_id: String, at: Vector3, speed: float) -> Node:
	var f := _make_follower(asset_id, [], speed)
	if f == null:
		return null
	f.position = at
	f.think(grid, _next_seed, speed, village)
	_next_seed += 1
	folk.append(f)
	if fxe != null and sfx != null:
		_wire_follower(f)
	return f


## Sound and one-shot FX for everything the player does or watches happen.
##
## Wired HERE rather than inside each system, so Divinity and Social stay
## testable without an audio bus or a particle pool -- both of the headless
## probes run them with neither, and a system that emitted its own effects
## could not be run that way.
func _wire_feedback() -> void:
	divinity.judged.connect(func(who, good):
		if not is_instance_valid(who):
			return
		var at: Vector3 = who.position + Vector3(0, 0.5, 0)
		fxe.burst("bless" if good else "punish", at)
		sfx.play("bless" if good else "punish"))

	divinity.smote.connect(func(at, radius, destroyed):
		fxe.ring("wrath", at, radius)
		sfx.play("wrath")
		# A strike that hit nothing gets the refusal sound instead, so the
		# player hears the difference between "missed" and "nothing there".
		if destroyed == 0:
			sfx.play("deny"))

	# Each miracle plays its OWN effect; the mapping lives in FXEvents so the
	# rules layer never names a particle system.
	divinity.miracle_cast.connect(func(id, at):
		fxe.miracle(id, at if at != Vector3.ZERO else _village_centre())
		sfx.play("miracle"))

	divinity.island_bought.connect(func(_slot): sfx.play("coin"))
	social.chat_started.connect(func(a, _b): sfx.play("chat",
		1.0 + a.brain.rng.randf_range(-0.1, 0.1)))


## Per-follower feedback, connected as each one is made.
func _wire_follower(f: Node) -> void:
	f.arrived_at.connect(func(act):
		if act == "chop":
			sfx.play("chop")
		elif act in ["harvest", "forage", "eat", "wash"]:
			sfx.play("pick"))
	f.finished.connect(func(act):
		var at: Vector3 = f.position + Vector3(0, 0.6, 0)
		var spec: Dictionary = Brain.ACTIONS.get(act, {})
		var raises := String(spec.get("builds", ""))
		if raises != "":
			_raise_structure(f, act, raises, spec)
			return
		if act == "chop" or act == "quarry":
			fxe.burst("chips", at)
			sfx.play("chop", 0.85)
		elif act in ["harvest", "forage"]:
			fxe.burst("chips", at, 0.5)
			sfx.play("pick", 1.1))


## A villager finished building something. THE BUILDER places it, not the
## brain: the brain chose the spot and paid for it, and holding a reference to
## the scene from inside the simulation is how a headless probe stops working.
##
## The cost was already taken when the action completed, so a placement that
## fails has to REFUND -- otherwise a villager can spend eight wood on a hut
## that never appears, and the village slowly starves of materials for reasons
## nothing reports.
func _raise_structure(f: Node, act: String, aid: String,
					  spec: Dictionary) -> void:
	var cell: Vector2i = f.brain.target_cell
	var ok := false
	if cell.x >= 0:
		ok = builder.add_prop(aid, cell.x, cell.y, _rng.randf_range(0.0, 360.0))
	if not ok:
		village.give(spec.get("takes", {}))
		return
	var at := builder.world_of(cell.x, cell.y) + Vector3(0, builder.lift, 0)
	rebuild_grid()
	village.census(builder.placed_props)
	fxe.burst("grow", at + Vector3(0, 0.6, 0))
	sfx.play("coin", 0.8)
	f.brain.memories.add(Memories.KIND_WORK,
		"I built that with my own hands.", 0.6)
	f.brain.think_aloud()


## Somewhere sensible to put an effect that has no place of its own -- a
## village-wide miracle. The mean of where everyone is standing, which is a
## better answer than the world origin now that the world is an archipelago.
func _village_centre() -> Vector3:
	if folk.is_empty():
		return Vector3.ZERO
	var total := Vector3.ZERO
	for f in folk:
		total += f.position
	return total / float(folk.size()) + Vector3(0, 0.8, 0)


## The god's screen.
##
## Built AFTER the followers, because the overhead icons and the HUD both read
## `folk` on their first frame. Layer 10 puts it under the debug menu, which
## lives higher up: an Escape menu that opens behind the card hand is a menu
## the player has to click through to use.
func _add_ui() -> void:
	ui = CanvasLayer.new()
	ui.name = "UI"
	ui.layer = 10
	add_child(ui)

	overhead = Overhead.new()
	overhead.name = "Overhead"
	overhead.host = self
	overhead.rig = rig
	ui.add_child(overhead)

	panel = VillagerPanel.new()
	panel.name = "VillagerPanel"
	panel.position = Vector2(16, 96)
	ui.add_child(panel)

	plots = PlotMarkers.new()
	plots.name = "Plots"
	plots.islands = islands
	plots.divinity = divinity
	plots.rig = rig
	add_child(plots)
	plots.plot_clicked.connect(func(slot): divinity.buy_island(slot))
	divinity.island_bought.connect(func(_s): plots.rebuild())
	divinity.faith_changed.connect(func(_a): plots._repaint())
	plots.rebuild()

	hud = HUD.new()
	hud.name = "HUD"
	hud.host = self
	hud.divinity = divinity
	hud.rig = rig
	ui.add_child(hud)

	overhead.follower_clicked.connect(panel.show_for)
	panel.bless_pressed.connect(func(who): divinity.bless(who))
	panel.punish_pressed.connect(func(who): divinity.punish(who))
	panel.closed.connect(func(): overhead.selected = null)


## Rebuild the walk grid from what is STANDING, not from the document.
##
## Called whenever the world changes under the villagers -- a miracle grows a
## grove, wrath flattens a cottage. Skipping it leaves followers routing around
## trees that no longer exist and walking through the space a felled one left.
func rebuild_grid() -> void:
	grid = WALKGRID.new()
	grid.build(builder.live_doc())
	divinity.grid = grid
	for f in folk:
		if is_instance_valid(f):
			f.grid = grid
	# The prop set changed too -- that is WHY the grid is being rebuilt -- so
	# the picker's cached AABBs are stale in exactly the same way, and the
	# structure census is what tells villagers whether to build another.
	village.census(builder.placed_props)
	if pick != null:
		pick.setup(rig, builder, builder.placed_props)


## A bought island: regenerate the terrain, then everything derived from it.
func rebuild_world() -> void:
	builder.rebuild(islands.build_doc())
	if plots != null:
		plots.rebuild()
	grid = WALKGRID.new()
	grid.build(builder.doc)
	divinity.grid = grid
	for f in folk:
		if is_instance_valid(f):
			f.grid = grid
	village.census(builder.placed_props)
	if pick != null:
		# setup(), not a direct assignment. The picker builds a WORLD AABB per
		# prop and stores it beside the node; handing it the builder's raw
		# records skips that and every ray test then reads a missing 'aabb'
		# key -- once per prop per frame, which is loud but only at runtime.
		pick.setup(rig, builder, builder.placed_props)
	if fx != null and fx.has_method("setup"):
		fx.setup(builder.placed_props)
	var pad := 4.0
	rig.set_bounds(builder.extent_min - Vector3(pad, 0, pad),
				   builder.extent_max + Vector3(pad, 0, pad))


## One more villager, anywhere they can stand. Returns false when there is
## genuinely nowhere, which the Fertility miracle reports rather than silently
## doing nothing.
func spawn_villager() -> bool:
	if grid == null or not village.has_room():
		return false
	for attempt in 200:
		var cell := grid.random_cell(_rng)
		if islands.slot_of_cell(cell).x < 0:
			continue
		var asset := "Folk/villager" if folk.size() % 3 else "Folk/adventurer"
		var f := _spawn_thinker(asset, grid.world_of(cell),
								_rng.randf_range(WALK_MIN, WALK_MAX))
		if f != null:
			village.population = folk.size()
			return true
	return false


func _process(delta: float) -> void:
	if social == null:
		return
	# Prune here rather than in every consumer. A freed follower left in the
	# list is a dangling reference the matchmaker would dereference next frame.
	var live: Array = []
	for f in folk:
		if is_instance_valid(f):
			live.append(f)
	folk = live
	social.tick(delta, folk)


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
		village.population = folk.size()


func clear_spawned() -> void:
	for f in _spawned:
		if is_instance_valid(f):
			folk.erase(f)
			f.queue_free()
	_spawned.clear()
	if village != null:
		village.population = folk.size()


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
	return folk.size()
