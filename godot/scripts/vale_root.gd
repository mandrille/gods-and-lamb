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
var floaters: Floaters
var draft: BoonDraft
var cursor: MiracleCursor
const CRITTER := preload("res://scripts/critter.gd")
const WOLF := preload("res://scripts/wolf.gd")
## Livestock, kept apart from `folk` so nothing that iterates the village's
## PEOPLE -- blessing, judgement, the social layer, the census -- ever has to
## ask whether this one is a sheep.
var beasts: Array = []
## How many animals a plot supports. Bought land brings a herd with it, which
## is part of what makes a purchase feel like it arrived with something.
const BEASTS_PER_PLOT := 3
## Fired whenever a beast leaves the world -- eaten by a wolf, slain by a
## hunter, struck by wrath. `kind` rather than a node: by the time anything
## can react the node may already be freed.
signal beast_removed(kind: String)
## How often the pack is topped up, and the world-time countdown to the next
## check. See `_maybe_spawn_wolf`.
const WOLF_SPAWN_SECONDS := 90.0
var _wolf_timer := WOLF_SPAWN_SECONDS
## Said once: the wolf GLB does not exist yet in this batch, and standing one
## up on the sheep model every time would spam the log.
var _warned_no_wolf_glb := false
var fxe: FXEvents
var sfx: SFX
var plots: PlotMarkers

## Every follower with a mind, scene residents and stress-spawns alike. The
## social layer needs ONE list to match pairs from; keeping two and iterating
## both would let a resident and a spawn stand nose to nose in silence.
var folk: Array = []

var _spawned: Array = []
var _next_seed := 1
## How often the village is checked for a newcomer, in seconds. Long: an
## arrival should feel like an event, not a spawn timer.
## Seventy-five seconds meant nineteen arrivals took a quarter of an hour, so
## the village was still tiny at the point the player had run out of things to
## watch. Population multiplies every channel in the game -- Faith, work,
## buildings, blessable moments -- so it is the wrong thing to be stingy with.
const NEWCOMER_SECONDS := 22.0
var _newcomer_timer := NEWCOMER_SECONDS
## Settlers owed because ground was opened for them. See _maybe_newcomer.
var _settlers_due := 0
## A grid rebuild that has been asked for but not yet paid for. See
## queue_grid_rebuild.
var _grid_dirty := false
var _grid_wait := 0.0
## Counted so a probe can show the coalescing working rather than assert it.
var n_grid_requests := 0
var n_grid_rebuilds := 0
const GRID_MIN_GAP := 0.35
const SETTLER_DELAY := 6.0
## Population counts that have already paid out a free draft, so a village
## that dips and recovers is not paid twice for the same milestone.
const POP_MILESTONES := [4, 8, 12, 18]
var _milestones_paid := {}

## Diagnostics for the build path, read by tools/build_probe.gd.
var n_build_try := 0
var n_build_ok := 0
var n_build_moved := 0
var n_build_fail := 0
var _rng := RandomNumberGenerator.new()
## The save this launch opened, and how it went. Empty means a new vale.
var _save_doc: Dictionary = {}
var _save_how := ""
## Turned off by probes that must not read the player's village. The default
## is safe on its own -- see Persistence.is_real_game -- and this is the
## override for the one probe that DOES want the disk.
var load_saves := false
var saving: Persistence = null
var _walk_paths: Array = []          ## world-space paths, reused by the stress test


func _ready() -> void:
	# THE SAVE IS READ FIRST, before a single thing is built, because the world
	# seed and the unlocked plots decide what Islands even generates.
	var opened: Dictionary = Persistence.probe_read(get_tree(), load_saves)
	_save_doc = opened.get("doc", {})
	_save_how = String(opened.get("how", SaveGame.FRESH))
	var world: Dictionary = _save_doc.get("world", {})

	# Seeded, where it was never seeded at all. This rng drives spawn cells and
	# every building's yaw, scale and colourway, so an unseeded one meant a
	# saved village came back wearing different roofs.
	_rng.seed = int(world.get("seed", Islands.DEFAULT_SEED))
	if world.has("rng_state"):
		_rng.state = int(world["rng_state"])

	islands = Islands.new(int(world.get("seed", Islands.DEFAULT_SEED)))
	for key in world.get("unlocked", []):
		islands.unlocked[SaveGame.cell_key(String(key))] = true
	builder = BUILDER.new()
	builder.name = "Vale"
	# Handed the generated archipelago BEFORE it enters the tree: the builder
	# reads data/vale.json in _ready() otherwise, and add_child runs _ready
	# immediately.
	builder.source_doc = SaveGame.doc_for(islands, world)
	add_child(builder)

	light = LIGHT.new()
	light.name = "Light"
	add_child(light)

	rig = RIG.new()
	rig.name = "CameraRig"
	add_child(rig)
	# Centred on the home island, which is the middle slot of the grid.
	var home_mid: int = (Islands.MARGIN
						+ (Islands.GRID / 2) * Islands.PITCH
						+ Islands.SPAN / 2)
	rig.focus = builder.world_of(home_mid, home_mid)
	# Framed on ONE plot, not on the whole archipelago. The plot is 10.5 m
	# across and the default 30 m pull-back was set for a 48 m landscape, which
	# left the village a postage stamp in a field of blue.
	rig.dist = 27.0
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
	village.islands = islands
	village.host = self
	var saved_v: Dictionary = _save_doc.get("village", {})
	if not saved_v.is_empty():
		# JSON has one number type, so every store comes back as a float and
		# the ledger would read "16.0 / 24". Cast on the way in.
		for k in (saved_v.get("stores", {}) as Dictionary):
			village.stores[String(k)] = int(saved_v["stores"][k])
		village.now = float(saved_v.get("now", 0.0))
		village.total_gathered = int(saved_v.get("total_gathered", 0))
		village.total_eaten = int(saved_v.get("total_eaten", 0))
		for key in (saved_v.get("richness", {}) as Dictionary):
			village._richness[SaveGame.cell_key(String(key))] = 				float(saved_v["richness"][key])
	# RE-DERIVED, never restored: both are functions of what now stands.
	village.census(builder.placed_props)
	village.pop_cap = islands.pop_cap() + village.passive_add("pop_cap_add")
	social = Social.new(20260901)

	divinity = Divinity.new()
	divinity.name = "Divinity"
	divinity.host = self
	divinity.village = village
	divinity.islands = islands
	divinity.builder = builder
	divinity.grid = grid
	if _save_doc.has("divinity"):
		# Before add_child, so nothing has ticked with the wrong numbers.
		SaveGame.apply_divinity(divinity, _save_doc["divinity"])
	add_child(divinity)

	_add_fx()
	fxe = FXEvents.new()
	fxe.name = "FXEvents"
	add_child(fxe)
	sfx = SFX.new()
	sfx.name = "SFX"
	add_child(sfx)

	if _save_doc.is_empty():
		_add_followers()
	else:
		_restore_followers(_save_doc)
	_add_ui()
	_wire_feedback()
	_add_menu()
	_add_persistence()


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
		# THEY START BY THE WOODS.
		#
		# A random walkable cell put the founding pair anywhere on a 34-metre
		# plot, and most of the opening was then two people walking to the
		# first tree -- the first chop landed at 29.5 s with almost all of it
		# spent on the journey. Opening in a clearing at the edge of the trees
		# is both a better first shot and a faster first axe-swing.
		#
		# The requirement is relaxed if it cannot be met, so a plot generated
		# with no trees near open ground still spawns its villagers.
		if tries < 300 and not _near_trees(cell, 4):
			continue
		var job := _pick_job()
		var at := grid.world_of(cell)
		if _spawn_thinker(job, at, _rng.randf_range(WALK_MIN, WALK_MAX)) != null:
			made += 1
	_stock_animals()
	# THE FOUNDERS START RESTED.
	#
	# Brain gives everyone 0.55-1.0 on each need so a village does not queue at
	# the same stall in the same second -- right for a newcomer, wrong for the
	# two people the game opens on. One of them would start a hair above URGENT
	# (0.45) and be hungry within seconds, so the first thing the player ever
	# saw was somebody looking for lunch. These two have just arrived: they are
	# fed, rested and clean, and the first thing they do is work.
	for f in folk:
		if f.brain == null:
			continue
		for k in Brain.STAT_ORDER:
			f.brain.stats[k] = _rng.randf_range(0.92, 1.0)
	village.population = made
	print("[VALE] followers: %d of %d cap, %s"
		% [made, islands.pop_cap(), village.summary()])


## Bring the herd up to what the owned land supports.
##
## Called at the start and again whenever a plot is bought, so buying ground
## visibly arrives with livestock on it rather than being an empty field and a
## raised number.
func _stock_animals() -> void:
	if grid == null:
		return
	var want: int = islands.count() * BEASTS_PER_PLOT
	var made := 0
	var tries := 0
	while beasts.size() < want and tries < 300:
		tries += 1
		var cell := grid.random_cell(_rng)
		if islands.slot_of_cell(cell).x < 0:
			continue
		# Two sheep to a cow: a flock with the odd cow in it reads as a
		# village's animals, an even split reads as a menu of options.
		var aid := "Animals/cow" if beasts.size() % 3 == 2 else "Animals/sheep"
		if _spawn_beast(aid, grid.world_of(cell)):
			made += 1
	if made > 0:
		print("[VALE] livestock: %d (%d plots)" % [beasts.size(), islands.count()])


func _spawn_beast(asset_id: String, at: Vector3) -> bool:
	# THE WOLF GLB DOES NOT EXIST YET. Standing a Wolf up on the sheep mesh
	# keeps the id, the behaviour and the class all real -- `kind` still reads
	# "Animals/wolf" for every system that asks -- while only the LOOK is a
	# stand-in, and the batch's own rule is that a missing asset must fail
	# soft rather than take a spawn down.
	var load_id := asset_id
	if asset_id == "Animals/wolf" and builder._packed_of("Animals/wolf") == null:
		if not _warned_no_wolf_glb:
			_warned_no_wolf_glb = true
			push_warning("ValeRoot: no Animals/wolf GLB yet -- standing a "
				+ "wolf up on the sheep model so it can still hunt")
		load_id = "Animals/sheep"
	var packed: PackedScene = builder._packed_of(load_id)
	if packed == null:
		return false
	# Same reparenting rule as a follower: a script on an imported scene root
	# does not survive a re-import, so the GLB goes UNDER the script node.
	var c: Critter = WOLF.new() if asset_id == "Animals/wolf" else CRITTER.new()
	c.name = "Beast%d" % beasts.size()
	add_child(c)
	c.add_child(packed.instantiate())
	c.setup(asset_id, at, grid, village, self)
	beasts.append(c)
	return true


## Take a beast out of the world -- eaten, slain, or struck by wrath. The
## entry leaves `beasts` and the signal fires BEFORE queue_free actually runs
## (it is deferred), so anything listening still sees a consistent world this
## frame.
func remove_beast(c) -> void:
	var kind := String(c.kind) if is_instance_valid(c) else ""
	beasts.erase(c)
	if is_instance_valid(c):
		c.queue_free()
	beast_removed.emit(kind)


## Keep the pack topped up once the village is old enough to have one, and
## only while there is something in the field for it to hunt -- a wolf spawned
## into an empty plot has nothing to do but stand at the edge scaring nobody.
func _maybe_spawn_wolf(delta: float) -> void:
	if divinity == null or grid == null or divinity.age < 2:
		return
	var have_prey := false
	var have_wolves := 0
	for b in beasts:
		if not is_instance_valid(b):
			continue
		if b.kind == "Animals/wolf":
			have_wolves += 1
		else:
			have_prey = true
	if not have_prey:
		return
	_wolf_timer -= delta
	if _wolf_timer > 0.0:
		return
	_wolf_timer = WOLF_SPAWN_SECONDS
	var cap: int = 1 + divinity.age + village.passive_add("wolf_cap_add")
	if have_wolves >= cap:
		return
	var spot := _wolf_rim_cell()
	if spot.x < 0:
		return
	if _spawn_beast("Animals/wolf", grid.world_of(spot)):
		divinity.notice.emit("Wolves at the edge of the village.")


## A walkable cell on the RIM of an unlocked plot, farthest from where the
## village actually lives -- a wolf that spawns in the middle of the square
## has already walked through everyone's back garden before anyone sees it
## arrive.
func _wolf_rim_cell() -> Vector2i:
	var centre := _village_centre()
	var best := Vector2i(-1, -1)
	var best_d := -1.0
	for slot in islands.unlocked:
		var o: Vector2i = islands.origin(slot)
		for i in Islands.SPAN:
			for j in Islands.SPAN:
				if i != 0 and i != Islands.SPAN - 1 \
						and j != 0 and j != Islands.SPAN - 1:
					continue                 # interior; only the rim counts
				var c := o + Vector2i(i, j)
				if not grid.is_walkable(c):
					continue
				var d: float = grid.world_of(c).distance_to(centre)
				if d > best_d:
					best_d = d
					best = c
	return best


## Is there something to chop within `span` cells of here?
func _near_trees(cell: Vector2i, span: int) -> bool:
	for aid in ["Nature/tree", "Nature/pine"]:
		for c in grid.cells_of(aid):
			var t: Vector2i = c
			if absi(t.x - cell.x) <= span and absi(t.y - cell.y) <= span:
				return true
	return false


## The job with the largest deficit (Village.job_for_newcomer), falling back
## to the old villager/adventurer split when nothing is standing to employ
## anyone -- nobody is born a lumberjack in a village with no lumber camp.
func _pick_job() -> String:
	var counts := village.job_counts(folk)
	var job := village.job_for_newcomer(counts)
	if job != "":
		return job
	return "adventurer" if folk.size() % 3 == 0 else "villager"


## `job`, not an asset id -- the LOOK follows from what they ARE (Jobs.asset_of),
## and falls back to the plain villager body when the job's GLB has not landed
## yet, per the batch's rule that a missing asset must fail SOFTLY rather than
## take the spawn down.
## `seed_value` < 0 takes the next one in sequence. A RESTORED follower passes
## the seed it was born with, which is what brings back their name and their
## whole personality without either being stored.
##
## Restoring goes through THIS function rather than a second spawn path on
## purpose: a parallel path is how _wire_follower gets forgotten on one side
## and every loaded villager's chop goes silent.
func _spawn_thinker(job: String, at: Vector3, speed: float,
					seed_value := -1) -> Node:
	var asset_id := Jobs.asset_of(job)
	if builder._packed_of(asset_id) == null:
		asset_id = "Folk/villager"
	var f := _make_follower(asset_id, [], speed)
	if f == null:
		return null
	f.position = at
	var use: int = _next_seed if seed_value < 0 else seed_value
	f.think(grid, use, speed, village, divinity.boons)
	f.set_walk_boost(divinity.boons.walk())
	if seed_value < 0:
		_next_seed += 1
	folk.append(f)
	if f.brain != null:
		f.brain.job = job
	if fxe != null and sfx != null:
		_wire_follower(f)
	return f


## Put the village back: the people, their state, and the animals.
##
## Names and personalities are NOT restored -- they are re-derived from the one
## seed each brain was rolled from, so they cannot drift out of step with the
## code that generates them. Mid-errand state (the current action, the path,
## the cooldowns) is deliberately dropped: _replan() re-decides on the next
## frame anyway, and an interrupted chop is not worth a field or a bug.
func _restore_followers(doc: Dictionary) -> void:
	for row in (doc.get("folk", []) as Array):
		var cell := Vector2i(int(row.get("c", 0)), int(row.get("r", 0)))
		var at: Vector3 = grid.world_of(cell)
		var f := _spawn_thinker(String(row.get("job", "villager")), at,
								float(row.get("walk", 1.0)),
								int(row.get("seed", 0)))
		if f == null:
			continue
		var b = f.brain
		b.age = float(row.get("age", 0.0))
		b.adult = bool(row.get("adult", true))
		b.morality = float(row.get("morality", 0.0))
		for k in (row.get("stats", {}) as Dictionary):
			b.stats[String(k)] = float(row["stats"][k])
		for k in (row.get("favour", {}) as Dictionary):
			b.favour[String(k)] = float(row["favour"][k])
		for e in (row.get("mem", []) as Array):
			b.memories.entries.append({
				"kind": String(e.get("k", "")), "text": String(e.get("t", "")),
				"other": String(e.get("o", "")),
				"valence": float(e.get("v", 0.0)),
				"heat": float(e.get("h", 0.0)),
				"age": float(e.get("a", 0.0))})
		for line in (row.get("log", []) as Array):
			b.thought_log.append(String(line))
		if not b.adult:
			f.become_child()
	_next_seed = maxi(_next_seed, int((doc.get("root", {}) as Dictionary)
									  .get("next_seed", 1)))
	for n in (doc.get("root", {}) as Dictionary).get("milestones_paid", []):
		_milestones_paid[int(n)] = true
	for row in (doc.get("beasts", []) as Array):
		var cell := Vector2i(int(row.get("c", 0)), int(row.get("r", 0)))
		_spawn_beast(String(row.get("kind", "Animals/sheep")),
					 grid.world_of(cell))
	# Boons are state ON THE BODY for walk speed, so they are pushed once here
	# rather than left to whatever set them last.
	apply_boons()


## The disk layer, and the away log if this launch opened a save.
func _add_persistence() -> void:
	saving = Persistence.new()
	saving.name = "Persistence"
	saving.host = self
	saving.armed = load_saves or Persistence.is_real_game(get_tree())
	add_child(saving)
	if _save_doc.is_empty():
		return
	var log := saving.open_log(_save_doc,
							   int(Time.get_unix_time_from_system()))
	if log.is_empty() or float(log.get("faith", 0.0)) <= 0.0:
		return
	divinity.add_faith(float(log["faith"]))
	# v1 shows the log through the notice stack, which now holds three. The
	# Day Summary screen is where it gets a room of its own.
	for line in (log.get("lines", []) as Array):
		divinity.notice.emit(String(line))
	divinity.notice.emit("While you were away: %d Faith."
		% int(log["faith"]))


## Sound and one-shot FX for everything the player does or watches happen.## Sound and one-shot FX for everything the player does or watches happen.
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

	# A judgement asked for too early. The `deny` sound already existed and was
	# used in exactly one place; a dead click is precisely what it is for.
	divinity.judge_refused.connect(func(_who): sfx.play("deny"))

	divinity.smote.connect(func(at, radius, destroyed):
		fxe.ring("wrath", at, radius)
		sfx.play("wrath")
		# A strike that hit nothing gets the refusal sound instead, so the
		# player hears the difference between "missed" and "nothing there".
		if destroyed == 0:
			sfx.play("deny"))

	# Just the chime. Every card in the deck is CHANNELLED now (see
	# MiracleCursor), which owns its own particle trail and its own landing
	# burst at wherever it actually was released -- this used to also fire a
	# burst here, at pickup, at the village centre, using whatever
	# `FXEvents.miracle` mapped the id to. That was a second, disconnected
	# effect competing with the real one, left over from when a card resolved
	# in a single instant at a chosen point rather than being carried.
	divinity.miracle_cast.connect(func(_id, _at): sfx.play("miracle"))

	divinity.island_bought.connect(func(_slot):
		sfx.play("coin")
		# LAND MUST BRING PEOPLE.
		#
		# A purchase used to raise the population CAP and nothing else, and a
		# cap nobody fills is worth nothing: arrivals are gated on a 58-75 s
		# timer AND on mood AND on food, so a two-person village that bought
		# ground got a map three times the size and no one to work it.
		#
		# Measured: a scripted player who bought land but never blessed ended
		# ten minutes at population 2 and earned 220 Faith, against 697 for one
		# who touched nothing at all. Land was the standing decision of the run
		# and it was strictly worse than doing nothing.
		#
		# So the purchase owes a settler, and that settler ignores the mood and
		# food gates -- which is also what the notice has always promised the
		# player: "The land extends. Room for N."
		_settlers_due += 1
		_newcomer_timer = minf(_newcomer_timer, SETTLER_DELAY)
		# And the field comes with animals on it.
		_stock_animals())
	# Every Faith gain leaves the thing that earned it and flies to the
	# counter it changed. That connection is the whole reason the economy is
	# legible -- a number moving in a corner is not feedback.
	divinity.earned.connect(func(amount, at, why):
		if amount < 0.5:
			return
		floaters.spawn("faith", "faith", int(round(amount)), at)
		if why == "bless":
			sfx.play("bless", 1.0 + 0.04 * float(divinity.combo_chain)))
	divinity.combo_changed.connect(func(chain, mult):
		if chain >= 2:
			var who = overhead.selected
			var at: Vector3 = (who.position + Vector3(0, 1.3, 0)
							   if who != null and is_instance_valid(who)
							   else _village_centre())
			floaters.puff("bless", "x%.2f" % mult, at))
	social.chat_started.connect(func(a, _b): sfx.play("chat",
		1.0 + a.brain.rng.randf_range(-0.1, 0.1)))
	social.child_wanted.connect(_on_child_wanted)
	# A silent economy failure is the worst kind. `depleted` and `land_full`
	# were both declared and connected to nothing.
	village.depleted.connect(func(res):
		divinity.notice.emit("The %s is gone." % res))
	village.land_full.connect(func():
		divinity.notice.emit("There is no room left to build. Buy land."))


## Per-follower feedback, connected as each one is made.
func _wire_follower(f: Node) -> void:
	f.arrived_at.connect(func(act):
		if act == "chop":
			sfx.play("chop")
		elif act in ["harvest", "forage", "eat", "wash"]:
			sfx.play("pick")
		_first_light(f, act))
	f.finished.connect(func(act):
		var at: Vector3 = f.position + Vector3(0, 0.6, 0)
		var spec: Dictionary = Brain.ACTIONS.get(act, {})
		# THE LIVE BUG: Divinity.on_work_done and on_prayer_done were declared
		# and never called from anywhere. Called BEFORE the build early-return,
		# not after -- a raised building is itself a WORK action and earns the
		# BUILD_BONUS on top of the ordinary payout, which on_work_done already
		# knows how to compute.
		if act in Brain.WORK:
			divinity.on_work_done(f, act, spec)
			_first_light_finished(f)
		elif act == "pray":
			divinity.on_prayer_done(f)
		var raises := String(spec.get("builds", ""))
		if raises != "":
			_raise_structure(f, act, raises, spec)
			return
		_consume_target(f, spec, at)
		_report_job(f, act, spec, at)
		_job_effect(f, act))


## THE FIRST THIRTY SECONDS, said out loud.
##
## The opening is deliberately quiet -- no cards until an age, Commune refuses,
## land is unaffordable, and a blessing pays nothing until somebody has
## actually done something (divinity.gd:161-167 argues for the gate and the
## argument is sound). But quiet is not the same as unexplained. A player who
## does not know what they are waiting for concludes there is nothing to wait
## for, and on a portal they are gone in twenty seconds.
##
## So: name the villager, name the moment, and get out of the way. Three lines,
## once each, driven by what the villagers were going to do anyway.
var _lit := {}


func _first_light(f: Node, act: String) -> void:
	if divinity == null or divinity.age > 0 or f.brain == null:
		return
	if _lit.has("aim") or act != "chop":
		return
	_lit["aim"] = true
	divinity.notice.emit("%s is working. Bless them the moment they finish."
		% f.brain.name)


func _first_light_finished(f: Node) -> void:
	if divinity == null or divinity.age > 0 or f.brain == null:
		return
	if _lit.has("now"):
		return
	_lit["now"] = true
	divinity.notice.emit("Now. The ring above %s is your window."
		% f.brain.name)


## Tell the player what a finished job DID.## Tell the player what a finished job DID.
##
## Every action gets an effect, a sound and -- when it produced something -- a
## token that flies from the villager to the counter it changed. The report was
## that the village felt inert, and the cause was that work was invisible: an
## animation played, a number in the corner moved, and nothing connected the
## two. A token leaving the person who earned it is that connection.
const JOB_LOOK := {
	"chop":    {"fx": "chips", "sfx": "chop", "icon": "wood"},
	"quarry":  {"fx": "chips", "sfx": "chop", "icon": "stone"},
	"forage":  {"fx": "grove", "sfx": "pick", "icon": "food"},
	"harvest": {"fx": "bounty", "sfx": "pick", "icon": "food"},
	"pick":    {"fx": "revel", "sfx": "pick", "icon": "fun"},
	"eat":     {"fx": "feast", "sfx": "pick", "icon": "hunger"},
	"rest":    {"fx": "mend", "sfx": "chat", "icon": "energy"},
	"wash":    {"fx": "splash", "sfx": "pick", "icon": "hygiene"},
	"pray":    {"fx": "bless", "sfx": "miracle", "icon": "faith"},
	"play":    {"fx": "revel", "sfx": "chat", "icon": "fun"},
	"sow":     {"fx": "grove", "sfx": "pick", "icon": "wheat"},
	"bless_flock": {"fx": "bless", "sfx": "miracle", "icon": "faith"},
	"tend":        {"fx": "mend", "sfx": "chat", "icon": "health"},
	"sing":        {"fx": "revel", "sfx": "chat", "icon": "fun"},
	"hunt":        {"fx": "chips", "sfx": "chop", "icon": "bolt"},
}

const RESOURCE_ROW := {"wood": "wood", "stone": "stone", "food": "food"}


func _report_job(f: Node, act: String, spec: Dictionary, at: Vector3) -> void:
	# A SIN HAS TO BE SEEN, or it may as well not have happened.
	#
	# The whole point of adding wrongdoing was to give punishment something to
	# be for, and a crime nobody notices leaves the player exactly where they
	# were -- with a button that hurts a villager for no reason. So it is
	# announced, it is marked over their head (see Overhead), and there is a
	# few-second window in which striking them is justice rather than cruelty.
	if bool(spec.get("sin", false)):
		divinity.notice.emit("%s: %s." % [f.brain.name,
			String(spec.get("verb", act)).capitalize()])
		fxe.burst("wrath", at + Vector3(0, 0.8, 0), 0.5)
		sfx.play("wrath", 1.35)
		floaters.puff("bolt", String(spec.get("verb", act)).capitalize(), at)
		return

	var look: Dictionary = JOB_LOOK.get(act, {})
	if not look.is_empty():
		fxe.burst(String(look["fx"]), at, 0.7)
		sfx.play(String(look["sfx"]), 1.0)

	# What it produced, flying to the counter it changed.
	var gave := false
	for res in spec.get("gives", {}):
		var key := String(res)
		floaters.spawn(String(RESOURCE_ROW.get(key, "food")), key,
					   int(spec["gives"][res]), at)
		gave = true
	if gave:
		return
	# Nothing for the ledger, but the villager still did something -- a need
	# filled, a field sown. Say so where it happened and let it fade.
	if not look.is_empty():
		floaters.puff(String(look["icon"]),
					  String(spec.get("verb", act)).capitalize(), at)


## Take away what was just worked on, and leave behind whatever replaces it.
##
## The prop is found by SEARCHING near the villager for one of the right kind,
## not by holding a reference from when the errand was planned. Between
## choosing a tree and reaching it, a miracle may have grown a grove over it,
## wrath may have levelled it, or another villager may have felled it first --
## a stored reference would be to a freed node, and a stored index would be to
## whatever slid into that slot.
func _consume_target(f: Node, spec: Dictionary, at: Vector3) -> void:
	if not bool(spec.get("consumes", false)) 			and spec.get("consumes_only", []).is_empty():
		return
	var only: Array = spec.get("consumes_only", [])
	var want := String(f.brain.target_id)
	if want == "" or (not only.is_empty() and not only.has(want)):
		return

	var best: Dictionary = {}
	var best_d := 2.2                       ## metres; arm's reach plus a tile
	for e in builder.placed_props:
		if String(e["id"]) != want:
			continue
		var node = e.get("node")
		if not is_instance_valid(node):
			continue
		var d: float = node.position.distance_to(f.position)
		if d < best_d:
			best_d = d
			best = e
	if best.is_empty():
		return

	var col := int(best.get("col", -1))
	var row := int(best.get("row", -1))
	# Trees and rocks TOPPLE away from whoever worked them; small scatter just
	# goes, because a flower falling over is not a moment.
	if want in ["Nature/tree", "Nature/pine"]:
		builder.fell_prop(best, f.position)
	else:
		builder.remove_prop(best)
	var leaves := String(spec.get("leaves", ""))
	if leaves != "" and col >= 0:
		builder.add_prop(leaves, col, row, _rng.randf_range(0.0, 360.0))
	queue_grid_rebuild()


## What a JOB does when its work completes -- the four job actions each ask
## something of the world beyond the ordinary gives/takes ACTIONS already
## handles: the priest reaches everyone near them, the nurse and the hunter
## each reach whoever they walked over to specifically.
func _job_effect(f: Node, act: String) -> void:
	var at: Vector3 = f.position + Vector3(0, 0.6, 0)
	match act:
		"bless_flock":
			# `brain.bless`, NOT `divinity.bless` -- the god's own bless() is
			# the player's judgement, on the player's cooldown, paid in Faith
			# from being WITNESSED. A priest's blessing is a job perk, free and
			# constant, and routing it through Divinity would silently spend
			# the player's cooldown and steal the witnessed-blessing chain out
			# from under them every time a priest finishes a shift.
			for o in folk:
				if is_instance_valid(o) and o != f and o.brain != null \
						and o.brain.adult \
						and o.position.distance_to(f.position) <= 3.0:
					o.brain.bless(0.4)
			fxe.burst("bless", at)
		"tend":
			var target := _nearest_other_folk(f, 1.6)
			if target != null:
				target.brain.stats["health"] = minf(1.0,
					float(target.brain.stats["health"]) + 0.3)
				floaters.puff("heart", "Tended",
							  target.position + Vector3(0, 0.9, 0))
		"sing":
			for o in folk:
				if is_instance_valid(o) and o.brain != null \
						and o.position.distance_to(f.position) <= 3.0:
					o.brain.stats["fun"] = minf(1.0,
						float(o.brain.stats["fun"]) + 0.25)
					o.brain.stats["social"] = minf(1.0,
						float(o.brain.stats["social"]) + 0.15)
			fxe.burst("revel", at)
		"hunt":
			_hunt_effect(f, at)


## The other follower this one just walked next to -- how `tend` finds WHO it
## just tended, rather than re-asking `seek` and possibly getting a different
## answer than the one the nurse actually walked to.
func _nearest_other_folk(f: Node, radius: float) -> Node:
	var best = null
	var best_d := radius
	for o in folk:
		if not is_instance_valid(o) or o == f or o.brain == null:
			continue
		var d: float = o.position.distance_to(f.position)
		if d <= best_d:
			best_d = d
			best = o
	return best


func _nearest_wolf(pos: Vector3, radius: float) -> Node:
	var best = null
	var best_d := radius
	for b in beasts:
		if not is_instance_valid(b) or b.kind != "Animals/wolf":
			continue
		var d: float = b.position.distance_to(pos)
		if d <= best_d:
			best_d = d
			best = b
	return best


## A completed hunt: the wolf takes a wound, and the killing blow is reported
## the same way wrath is -- this is the village striking back, not a silent
## number changing.
func _hunt_effect(f: Node, at: Vector3) -> void:
	var target := _nearest_wolf(f.position, 1.0)
	if target == null:
		return
	target.hp -= 1
	if target.hp <= 0:
		remove_beast(target)
		divinity.notice.emit("%s slew a wolf." % f.brain.name)
		divinity.add_faith(3.0)
		fxe.burst("wrath", at)
	else:
		fxe.burst("chips", at)


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
	# RE-VALIDATE ON ARRIVAL. The site was chosen at decision time and the
	# villager then WALKED to it -- twenty seconds during which a miracle may
	# have grown a grove on it, wrath may have levelled something into it, or
	# another builder may have got there first. Nothing re-checked, which is
	# the third reason buildings ended up stacked.
	n_build_try += 1
	var cell: Vector2i = f.brain.target_cell
	var ok := false
	# A `_b` colourway, half the time, when one exists and its GLB has
	# actually landed -- a village of forty identical huts is a grid, not a
	# settlement. Chosen once per building raised, never per attempt, so a
	# retry after a blocked site does not silently swap colourways mid-build.
	var place_id := aid
	var sibling := aid + "_b"
	if Islands.FOOTPRINTS.has(sibling) and builder._packed_of(sibling) != null \
			and _rng.randf() < 0.5:
		place_id = sibling
	# A LITTLE off 1.0, per building, so a row of huts is not a row of clones
	# stamped from one mould.
	var scale_v := _rng.randf_range(0.94, 1.06)
	# SQUARE TO THE GRID. Buildings are rectangular, the ground is a grid, and
	# a cottage at 37 degrees reads as something that fell out of the sky.
	var yaw := 90.0 * float(_rng.randi_range(0, 3))
	if cell.x >= 0:
		ok = builder.add_prop(place_id, cell.x, cell.y, yaw, scale_v)
		if not ok:
			# Taken while they walked. Look nearby before giving up -- the
			# villager is standing right here with the materials in hand.
			for i in 24:
				var near := cell + Vector2i(_rng.randi_range(-4, 4),
											_rng.randi_range(-4, 4))
				if not grid.is_plain(near):
					continue
				if builder.add_prop(place_id, near.x, near.y, yaw, scale_v):
					cell = near
					ok = true
					n_build_moved += 1
					break
	if not ok:
		# The cost was taken when the job completed, so a placement that fails
		# must REFUND. Otherwise a villager spends six wood on a hut that never
		# appears and the village quietly starves of materials for no reason
		# anything reports.
		n_build_fail += 1
		village.give(spec.get("takes", {}))
		divinity.notice.emit("%s found nowhere to build." % f.brain.name)
		return
	n_build_ok += 1
	var at := builder.world_of(cell.x, cell.y) + Vector3(0, builder.lift, 0)
	queue_grid_rebuild()
	village.census(builder.placed_props)
	# "grow" was never a real FXEvents kind, so this has been a silent no-op --
	# "build" is the one already meant for exactly this (a structure just
	# went up).
	fxe.burst("build", at + Vector3(0, 0.6, 0))
	sfx.play("coin", 0.8)
	f.brain.memories.add(Memories.KIND_WORK,
		"I built that with my own hands.", 0.6)
	f.brain.think_aloud()


## Resolve a `seeks` action (Brain._somewhere_to_do, Brain.destination_for) to
## an actual target. The brain knows it wants "the sickest villager" or "a
## wolf"; only the scene root can say which node that currently is, because
## `folk` and `beasts` live here, not on the Village ledger.
func seek(kind: String, from: Vector3):
	match kind:
		"lowest_health":
			var best = null
			var worst := 2.0
			for f in folk:
				if not is_instance_valid(f) or f.brain == null or not f.brain.adult:
					continue
				var h: float = float(f.brain.stats["health"])
				if h < worst:
					worst = h
					best = f
			return best
		"wolf":
			var best = null
			var best_d := 1.0e30
			for b in beasts:
				if not is_instance_valid(b) or b.kind != "Animals/wolf":
					continue
				var d: float = b.position.distance_to(from)
				if d < best_d:
					best_d = d
					best = b
			return best
	return null


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
	panel.divinity = divinity
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

	floaters = Floaters.new()
	floaters.name = "Floaters"
	floaters.host = self
	floaters.hud = hud
	ui.add_child(floaters)

	# The held miracle lives in the WORLD, not the UI: it is a cloud with a
	# position, and it has to be occluded by the terrain like anything else.
	cursor = MiracleCursor.new()
	cursor.name = "MiracleCursor"
	cursor.host = self
	cursor.divinity = divinity
	add_child(cursor)
	divinity.cursor = cursor
	# The bar and the ground ring live in a separate Control so MiracleCursor
	# stays a pure Node3D with no UI concerns -- it only has to draw nothing
	# when idle, which `is_active()` guards on its own.
	var gauge := MiracleGauge.new()
	gauge.name = "MiracleGauge"
	gauge.cursor = cursor
	gauge.rig = rig
	ui.add_child(gauge)
	cursor.finished.connect(func(id, touched, gain):
		if touched == 0:
			divinity.notice.emit(
				"The %s passed over nothing at all." % id)
		else:
			divinity.notice.emit("The %s touched %d, and you gained %d Faith."
				% [id, touched, int(gain)]))

	# The draft sits ABOVE everything and takes every click while it is open.
	draft = BoonDraft.new()
	draft.name = "BoonDraft"
	draft.divinity = divinity
	ui.add_child(draft)
	divinity.draft_offered.connect(draft.open)
	draft.chosen.connect(func(id):
		divinity.take_boon(id)
		draft.close()
		fxe.burst("bless", _village_centre())
		sfx.play("coin", 0.85))
	draft.rerolled.connect(func():
		divinity.add_faith(-float(draft.reroll_cost()))
		draft.open(divinity.boons.offer(), draft._source)
		sfx.play("chat", 1.2))

	overhead.follower_clicked.connect(panel.show_for)
	panel.bless_pressed.connect(func(who): divinity.bless(who))
	panel.punish_pressed.connect(func(who): divinity.punish(who))
	panel.closed.connect(func(): overhead.selected = null)


## A child is born to two villagers.
##
## The social layer decided they WANT one; whether there is room and where the
## child stands are questions about the map, and belong here.
func _on_child_wanted(a: Node, b: Node) -> void:
	if not village.has_room():
		return
	var at: Vector3 = (a.position + b.position) * 0.5
	var cell := grid.cell_of(at)
	if not grid.is_walkable(cell):
		cell = grid.beside(cell, _rng)
		if cell.x < 0:
			return
	var job := _pick_job()
	var f := _spawn_thinker(job, grid.world_of(cell),
							_rng.randf_range(WALK_MIN, WALK_MAX))
	if f == null:
		return
	f.become_child()
	village.population = folk.size()
	fxe.burst("birth", grid.world_of(cell) + Vector3(0, 0.7, 0))
	sfx.play("coin", 1.25)
	divinity.notice.emit("%s and %s have a child: %s."
		% [a.brain.name, b.brain.name, f.brain.name])
	for p in [a, b]:
		p.brain.memories.add(Memories.KIND_SOCIAL,
			"We have a child, %s." % f.brain.name, 0.9, f.brain.name, 1.5)
		p.brain.think_aloud()


## Somebody heard the village was worth joining and walked in.
##
## The other half of item 5, and the one that keeps a village from stalling: a
## settlement of two who never get on would otherwise never grow at all. It is
## earned, not free -- a village nobody is happy in attracts nobody.
func _maybe_newcomer(delta: float) -> void:
	if not village.has_room() or folk.is_empty():
		return
	# WELCOMING, not happy.
	#
	# This used `mood()`, which weights the WORST stat at 0.45 -- and in a
	# two-person village Social is pinned near zero, because a chat needs two
	# people who both want one, within two metres, off a 26-second cooldown.
	# So the gate read "miserable" forever and the village could never grow:
	# you needed people to be sociable and sociability to get people.
	#
	# Loneliness should ATTRACT newcomers, not repel them. So the gate asks
	# whether this is a place worth arriving at -- fed, rested, well, clean --
	# and says nothing about whether they have company.
	var mood := 0.0
	for f in folk:
		var b = f.brain
		mood += (float(b.stats["hunger"]) + float(b.stats["energy"])
				 + float(b.stats["health"]) + float(b.stats["hygiene"])) * 0.25
	mood = mood / float(folk.size()) * 2.0 - 1.0
	# DECAY, do not reset.
	#
	# This reset the full 75 s the instant mean mood dipped under the gate --
	# and mood() weights the WORST stat at 0.45, so one villager going
	# desperate on any of seven stats tripped it. A run where the village never
	# grew past its two starting people was entirely possible, and population
	# multiplies every income channel there is. A dip now costs twice the time
	# it lasted, which is pressure without a cliff.
	# A settler who was PROMISED ground comes whatever the mood is. Everyone
	# else still has to be attracted.
	if _settlers_due <= 0:
		if mood < divinity.boons.mood_gate() or village.amount("food") < 2:
			_newcomer_timer = minf(NEWCOMER_SECONDS, _newcomer_timer + delta * 2.0)
			return
	_newcomer_timer -= delta
	if _newcomer_timer > 0.0:
		return
	# A hotel's `newcomer_mult` (1.5) is an ATTRACTIVENESS multiplier, not a
	# delay -- more visitors passing through means a shorter wait, so it
	# divides the timer rather than stretching it. Every other passive that
	# reads through `passive_mult` is a genuine multiplier on its own quantity
	# (build seconds, a resource cap); this is the one where "bigger number"
	# means "sooner", so the arithmetic has to bend to match the word.
	_newcomer_timer = (divinity.boons.newcomer_seconds()
		/ maxf(0.1, village.passive_mult("newcomer_mult")))
	if not spawn_villager():
		return
	if _settlers_due > 0:
		_settlers_due -= 1
	var who = folk[folk.size() - 1]
	fxe.burst("bless", who.position + Vector3(0, 0.8, 0))
	sfx.play("coin")
	divinity.notice.emit("You have a new follower: %s." % who.brain.name)


## A village that reaches a size has EARNED something. Same draft as Commune,
## free, because a moment the player is taught once should not have two shapes.
## The one thing the player should be aiming at, in five words.
##
## The age notices are RETROSPECTIVE -- "The First Roof" announces a thing that
## already happened. Nothing on screen has ever said what to do next, and a
## portal player who does not know what to aim at leaves before they find out.
## The gates are read from the same places that enforce them, so this line
## cannot drift away from the game.
func next_goal() -> String:
	if divinity == null or village == null:
		return ""
	# A full village with nowhere to grow is the wall the whole opening runs
	# into, so it outranks whatever age is pending.
	if folk.size() >= village.pop_cap and islands != null:
		var slots: Array = islands.buyable()
		if not slots.is_empty():
			return "Buy land  %d Faith" % islands.price_next()
	match divinity.age:
		0:
			return "Raise a roof"
		1:
			if folk.size() < 4:
				return "Gather 4 followers  (%d)" % folk.size()
			return "Bless them as they work  (%d/20)" % divinity.witnessed_total
		2:
			if village.count_of("Buildings/shrine") <= 0:
				return "Raise a shrine"
			return "Earn 500 Faith in all  (%d)" % int(divinity.total_earned)
	for n in POP_MILESTONES:
		if not _milestones_paid.has(n) and folk.size() < n:
			return "Grow to %d followers  (%d)" % [n, folk.size()]
	if islands != null and not islands.buyable().is_empty():
		return "Buy land  %d Faith" % islands.price_next()
	return "Tend them"


func _check_milestones() -> void:
	for n in POP_MILESTONES:
		if folk.size() >= n and not _milestones_paid.has(n):
			_milestones_paid[n] = true
			if divinity.grant_draft("milestone"):
				divinity.notice.emit("%d followers. Choose a gift." % n)
			return


## Ask for a grid rebuild soon, rather than paying for one right now.
##
## rebuild_grid() allocates a fresh WalkGrid, re-walks every prop, rebuilds a
## ~100x100 AStarGrid2D and floods it for connected regions. Measured at
## 29.75 ms -- a two-frame stall -- and it was being called on EVERY chop and
## EVERY building raised. Two dozen villagers fell a tree every few seconds
## each, so the game spent a large fraction of its time rebuilding a map that
## had changed by one cell, which is what "the game just runs slow" was.
##
## Nothing needs the grid to be correct in the same frame the tree falls: the
## villager who felled it is standing still playing an animation, and every
## target is re-validated on arrival anyway. So changes are coalesced -- ten
## trees felled across a third of a second cost one rebuild instead of ten.
func queue_grid_rebuild() -> void:
	n_grid_requests += 1
	_grid_dirty = true


func _service_grid(delta: float) -> void:
	_grid_wait = maxf(0.0, _grid_wait - delta)
	if not _grid_dirty or _grid_wait > 0.0:
		return
	_grid_dirty = false
	_grid_wait = GRID_MIN_GAP
	n_grid_rebuilds += 1
	rebuild_grid()


## Push every boon that lives on a follower back out to all of them.
##
## Called when a boon is taken. Boons are READ wherever possible -- drains and
## yields are asked for at the moment they are used -- but walk speed is state
## on the body, so it has to be written, and written to everyone rather than
## only to whoever is spawned next.
func apply_boons() -> void:
	var boost: float = divinity.boons.walk()
	for f in folk:
		if is_instance_valid(f):
			f.set_walk_boost(boost)
			if f.brain != null:
				f.brain.boons = divinity.boons


## Rebuild the walk grid from what is STANDING, not from the document.
##
## Called whenever the world changes under the villagers -- a miracle grows a
## grove, wrath flattens a cottage. Skipping it leaves followers routing around
## trees that no longer exist and walking through the space a felled one left.
## Terrain is unchanged here -- only props moved -- so the existing grid is
## updated in place rather than a new one built and handed to everybody. See
## WalkGrid.rebuild_props for why that matters.
func rebuild_grid() -> void:
	if grid != null:
		grid.rebuild_props(builder.live_doc())
		return
	grid = WALKGRID.new()
	grid.build(builder.live_doc())
	divinity.grid = grid
	for f in folk:
		if is_instance_valid(f):
			f.grid = grid
			# The BRAIN holds one too, for deciding whether a job has anywhere
			# to be done. Updating only the body leaves every villager
			# reasoning about the world as it was before the last miracle.
			if f.brain != null:
				f.brain.grid = grid
	for b in beasts:
		if is_instance_valid(b):
			b.grid = grid
	# The prop set changed too -- that is WHY the grid is being rebuilt -- so
	# the picker's cached AABBs are stale in exactly the same way, and the
	# structure census is what tells villagers whether to build another.
	village.census(builder.placed_props)
	if pick != null:
		pick.setup(rig, builder, builder.placed_props)


## A bought island: regenerate the terrain, then everything derived from it.
func rebuild_world() -> void:
	# carry_doc, NOT the raw generated document. See ValeBuilder.carry_doc:
	# rebuilding from the generator alone demolished every hut the followers
	# had built and regrew every tree they had felled.
	builder.rebuild(builder.carry_doc(islands.build_doc()))
	if plots != null:
		plots.rebuild()
	grid = WALKGRID.new()
	grid.build(builder.doc)
	divinity.grid = grid
	for f in folk:
		if is_instance_valid(f):
			f.grid = grid
			# The BRAIN holds one too, for deciding whether a job has anywhere
			# to be done. Updating only the body leaves every villager
			# reasoning about the world as it was before the last miracle.
			if f.brain != null:
				f.brain.grid = grid
	for b in beasts:
		if is_instance_valid(b):
			b.grid = grid
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
		var job := _pick_job()
		var f := _spawn_thinker(job, grid.world_of(cell),
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
	village.tick(delta)
	_service_grid(delta)
	social.tick(delta, folk)
	_maybe_newcomer(delta)
	_check_milestones()
	_maybe_spawn_wolf(delta)


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
	var job := _pick_job()
	var f := _spawn_thinker(job, grid.world_of(cell), randf_range(0.8, 1.2))
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
