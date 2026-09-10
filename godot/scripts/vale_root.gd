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
var chorus: Chorus = null
var prayers: Prayers = null
var director := Director.new()
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
var _touched_at := -99.0            ## village clock of the last world touch
## Fires, droughts and winds currently eating the world.
var calamities: Array = []
var aftermath = null               ## the disaster resolution card
var prophecies: Prophecies = null  ## what the prophet says is coming
var chronicle: Chronicle = Chronicle.new()   ## what this village remembers
## What a portal would be told. Counted here rather than inside each system for
## the same reason the feedback is: a system that reported its own metrics could
## not be run headless without one.
var stats: Analytics = Analytics.new()
## How much motion and effect the player has asked for. Read wherever it is
## needed rather than pushed anywhere -- see comfort.gd.
var comfort: Comfort = Comfort.new()
var _calamity_timer := 90.0
var _bite_at := 0.0
var _save_doc: Dictionary = {}
var _save_how := ""
## Turned off by probes that must not read the player's village. The default
## is safe on its own -- see Persistence.is_real_game -- and this is the
## override for the one probe that DOES want the disk.
var load_saves := false
var saving: Persistence = null
## The day clock. Public so the HUD can read it and a probe can wind it on.
var daylight: Daylight = null
var day_screen: DayScreen = null
var pause_menu: PauseMenu = null
var music: Music = null
## What this day has amounted to so far, and the one thing worth retelling.
## Snapshotted at dawn and subtracted at dusk, so the summary counts THIS day
## rather than the whole run.
var _day_mark := {}
var _day_drama := ""
## A probe must never be stopped by a modal it did not ask for. The real game
## opens the night screen and pauses; anything else rolls straight on.
var night_screen := true
var _walk_paths: Array = []          ## world-space paths, reused by the stress test


## HOW BIG THE UI IS, IN THE HAND.
##
## The project draws its UI in a 720-unit-wide space, which is right for a
## desktop window and wrong for a phone: a 375 pt handset maps 720 units onto
## 375 points, so every control lands at HALF the size it was drawn. Measured on
## the web build at 375x812: the ledger font came out at 7.8 pt and the two
## standing buttons at 24 pt against a 44 pt minimum. Nothing was clipped and
## nothing overlapped -- it was simply too small to use, which is the failure
## mode a layout test does not catch.
##
## `content_scale_factor` is the fix rather than a smaller `content_scale_size`
## because it scales the 2D layer ONLY: the village keeps rendering at the
## window's full resolution while the UI is dealt out in fewer, larger units.
##
## The target is 400 units across, which is what leaves a 46-unit button at
## about 46 pt on any handset. Capped at 1.0 below, so a desktop window is
## untouched.
const UI_UNITS_WANTED := 400.0


## Put the three switches into effect. Only two things actually need telling --
## the particle pool and the window scale; every pulse in the game reads
## `comfort` at draw time and needs nothing at all.
func _apply_comfort() -> void:
	if fxe != null:
		fxe.set_density(comfort.density())
	_apply_ui_scale()
	if settings != null:
		comfort.store_in(settings)


func _apply_ui_scale() -> void:
	var w: Window = get_window()
	if w == null:
		return
	var across: float = float(w.content_scale_size.x)
	if across <= 0.0:
		across = 720.0
	# PORTRAIT IS THE TEST, not pixel density. Density would be the honest
	# measure and `screen_get_scale()` is the honest way to ask -- but it
	# reports 1.0 headless and on several browsers, which would silently leave
	# every phone at desktop scale, and that is the exact bug this is fixing.
	# A window taller than it is wide is a handset or a tablet held upright;
	# nothing else is shaped like that, and a desktop window narrowed until it
	# is portrait wants the bigger UI too.
	# LARGER TEXT IS ALSO WANTED IN LANDSCAPE, which the portrait test alone
	# cannot deliver -- somebody who needs bigger controls needs them on a
	# desktop monitor too, and returning 1.0 here made the setting silently do
	# nothing on the platform most likely to be reading it.
	var wanted: float = comfort.ui_units(UI_UNITS_WANTED)
	if float(w.size.y) <= float(w.size.x):
		w.content_scale_factor = (clampf(across / (UI_UNITS_WANTED * 2.0),
										 1.0, 1.6) if comfort.big_text else 1.0)
		return
	w.content_scale_factor = clampf(across / wanted, 1.0, 2.4)


func _ready() -> void:
	_apply_ui_scale()
	get_window().size_changed.connect(_apply_ui_scale)
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
	# The surface the player is actually pointing at, not y = 0. See
	# CameraRig.ground_y -- getting this wrong put every click a tile and a half
	# from where it was aimed.
	rig.ground_y = builder.lift
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
	pick.ground_picked.connect(_on_ground)

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
	daylight = Daylight.new()
	daylight.from_doc(_save_doc.get("daylight", {}))
	# Restored HERE rather than in `apply_divinity`, which is handed the god and
	# not the world -- the chronicle belongs to the village.
	chronicle.from_doc(_save_doc.get("chronicle", []))
	daylight.night_fell.connect(_on_night)

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
	# The saved density has to reach the pool at birth, not when somebody first
	# opens the pause menu.
	fxe.set_density(comfort.density())
	add_child(fxe)
	sfx = SFX.new()
	sfx.name = "SFX"
	add_child(sfx)
	music = Music.new()
	music.name = "Music"
	add_child(music)

	if _save_doc.is_empty():
		_add_followers()
	else:
		_restore_followers(_save_doc)
	_add_ui()
	_wire_feedback()
	_add_menu()
	night_screen = Persistence.is_real_game(get_tree())
	_add_persistence()
	_start_day()


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
	# BEFORE ANYTHING IS BUILT WITH IT. A player who turned motion down last
	# session should not get one session of full motion back for their trouble,
	# and the FX pool reads its density when it is created.
	comfort.load_from(settings)
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


## A PROP WAS TOUCHED. This used to print a line and do nothing.
func _on_picked(entry: Dictionary) -> void:
	if entry.size() == 0 or not _touch_ready():
		return
	var id := String(entry.get("id", ""))
	var act := WorldTouch.prop_action(id)
	if act.is_empty():
		return
	# The cooldown is spent only once the touch is going to DO something. A
	# scenery prop with no entry in the table used to eat it silently, and the
	# player's next tap -- on a tree, on purpose -- was the one that failed.
	_touch_take()
	var at: Vector3 = entry.get("pos", Vector3.ZERO)
	if bool(act.get("consumes", false)):
		builder.remove_prop(entry)
		queue_grid_rebuild()
	var spawns := String(act.get("spawns", ""))
	if spawns != "":
		if bool(act.get("fruit", false)):
			_fruit(act, spawns, at)
		else:
			var cell: Vector2i = grid.beside(grid.cell_of(at), _rng)
			if builder.add_prop(spawns, cell.x, cell.y, 0.0):
				queue_grid_rebuild()
	_touch_paid(act, at, "touch:" + id)


## A TREE FRUITS. Several heaps under the canopy, not one item beside the trunk.
##
## The heaps are the mechanic and they exist the instant this returns: `forage`
## already lists `Nature/apples` as a source and already consumes it, so a
## hungry villager is walking toward one before the player has let go of the
## mouse. FruitFall is the picture of it -- apples in the leaves that hang and
## then drop onto exactly the squares the heaps went to.
func _fruit(act: Dictionary, aid: String, at: Vector3) -> void:
	var home: Vector2i = grid.cell_of(at)
	var reach: int = int(act.get("reach", WorldTouch.FRUIT_REACH))
	var want: int = int(act.get("count", WorldTouch.FRUIT)) 		+ divinity.boons.extra_fruit()
	# Every square under the canopy, nearest first, so a tree in a corner still
	# drops what it can rather than failing on twenty random misses.
	var near: Array[Vector2i] = []
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var c := home + Vector2i(dx, dy)
			if grid.is_walkable(c) and not _prop_on(c) 					and not builder.would_overlap(aid, c.x, c.y):
				near.append(c)
	near.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (absi(a.x - home.x) + absi(a.y - home.y)) 			< (absi(b.x - home.x) + absi(b.y - home.y)))

	var landed: Array = []
	for c in near:
		if landed.size() >= want:
			break
		if builder.add_prop(aid, c.x, c.y, _rng.randf_range(0.0, 360.0)):
			landed.append(grid.world_of(c))
	if landed.is_empty():
		return
	queue_grid_rebuild()
	FruitFall.drop(builder, at, landed, _rng)


## THE GROUND WAS TOUCHED, which is the verb the whole desert opening is made
## of: dirt becomes grass, and grass grows something if there is room for it.
func _on_ground(at: Vector3) -> void:
	if not _touch_ready():
		return
	var cell: Vector2i = grid.cell_of(at)
	var ch := builder.code_at(builder.lower, cell.x, cell.y)
	var act := WorldTouch.tile_action(ch)
	if act.is_empty():
		return
	var becomes := String(act.get("becomes", ""))
	if becomes != "":
		# A TIDE, not a tile: 4x4 now and it keeps spreading on its own out to
		# 16x16. See WorldTouch for the shape and why the raggedness is a hash
		# rather than a die roll.
		if _green(WorldTouch.block(cell, WorldTouch.SEED_SIZE), becomes) == 0:
			return
		_start_tide(cell, becomes)
	elif bool(act.get("grows", false)):
		# Only where there is ROOM. A meadow you can fill by holding the mouse
		# down is not a decision, and a tree on top of a hut is a bug.
		if not grid.is_plain(cell) or _prop_on(cell):
			return
		# AND THE ROOM IS BIGGER THAN THE TILE. A tree's footprint covers its
		# neighbours, so a square that is empty by cell can still be full by
		# geometry -- measured, about half of all grass was, and every one of
		# those taps did nothing, said nothing, and spent the cooldown anyway.
		# It reads as the game ignoring you.
		var seed_id := WorldTouch.seed_for(cell)
		if builder.would_overlap(seed_id, cell.x, cell.y):
			_touch_take()
			if divinity != null:
				divinity.notice.emit("No room to grow there.")
			if sfx != null:
				sfx.play("deny")
			return
		if not builder.add_prop(seed_id, cell.x, cell.y,
								_rng.randf_range(0.0, 360.0)):
			return
		queue_grid_rebuild()
	_touch_take()
	_touch_paid(act, grid.world_of(cell), "touch:" + ch)


## GREEN A SET OF SQUARES, and only the ones that are actually ground the
## player could green.
##
## The filter matters: `set_tiles` will happily convert whatever tile it is
## handed, and a spread that reached the shore would turn the pond into a lawn.
## What may become grass is exactly what the touch table says becomes grass.
func _green(cells: Array, becomes: String) -> int:
	var want: Array[Vector2i] = []
	for c in cells:
		var cell: Vector2i = c
		var here := builder.code_at(builder.lower, cell.x, cell.y)
		if here == becomes:
			continue
		if String(WorldTouch.tile_action(here).get("becomes", "")) != becomes:
			continue
		want.append(cell)
	if want.is_empty():
		return 0
	var made: Array[Vector2i] = builder.set_tiles(want, becomes)
	for c in made:
		grid.set_code(c, becomes)
	if not made.is_empty():
		queue_grid_rebuild()
	return made.size()


## --- the spreading green ----------------------------------------------------
##
## Each entry is one touch still running: {at, becomes, size, step, left, next}.
##
## NOT SAVED, deliberately. A tide is a few seconds of spectacle and the GROUND
## it has already made is what persists -- reloading into a half-finished lawn
## that then kept growing would be a village changing shape while the player
## reads their away log.
var _tides: Array = []


func _start_tide(cell: Vector2i, becomes: String) -> void:
	# At the cap the OLDEST is finished in one go rather than dropped. A click
	# that quietly did nothing is worse than one that resolves early.
	while _tides.size() >= WorldTouch.TIDE_MAX_LIVE:
		var old: Dictionary = _tides.pop_front()
		_green(WorldTouch.block(old["at"], WorldTouch.TIDE_MAX),
			   String(old["becomes"]))
	_tides.append({"at": cell, "becomes": becomes,
				   "size": WorldTouch.SEED_SIZE, "step": 0, "fills": 0,
				   "next": float(village.now) + WorldTouch.TIDE_STEP})


func _tick_tides() -> void:
	if _tides.is_empty():
		return
	var now := float(village.now)
	for t in _tides.duplicate():
		if now < float(t["next"]):
			continue
		t["next"] = now + WorldTouch.TIDE_STEP
		t["step"] = int(t["step"]) + 1
		t["size"] = mini(int(t["size"]) + 2, WorldTouch.TIDE_MAX)
		# Once the square has stopped growing, the last two passes take
		# everything -- otherwise a spread stops at whatever the dice left and
		# the player is handed a lawn with holes in it to tidy by hand.
		var full: bool = int(t["size"]) >= WorldTouch.TIDE_MAX
		if full:
			t["fills"] = int(t["fills"]) + 1
		var chance: float = 1.0 if int(t["fills"]) >= 2 else WorldTouch.TIDE_TAKE
		var want: Array[Vector2i] = []
		for c in WorldTouch.block(t["at"], int(t["size"])):
			if WorldTouch.takes(c, int(t["step"]), chance):
				want.append(c)
		_green(want, String(t["becomes"]))
		if int(t["fills"]) >= 2:
			_tides.erase(t)


## THEY LOOK UP.
##
## The spec's acceptance test is that a first-time player can SEE that the
## village noticed, without a tutorial and without reading a number. This is
## that: whoever was nearest turns toward the act, an exclamation appears over
## their head, and a tier crossing gets its name said out loud.
##
## CAPPED AT FOUR, nearest first. Twenty people snapping round in unison does
## not read as twenty people noticing, it reads as a bug -- and the turn costs a
## replan when they resume, which is the budget Follower guards at six a frame.
const REACT_MAX := 4


## WHERE THE REACTION DETAIL STEPS DOWN, as MULTIPLES OF THE CAMERA'S OWN
## DISTANCE rather than in metres.
##
## Written in metres first, at 18 and 34, and that was simply wrong: the camera
## sits 30 m back by default, so everything on screen is 25 to 55 m away and an
## 18 m band culled the overhead mark from the entire visible island. divine_
## probe caught it -- "no marker went up over the villager who noticed" -- and
## it would have shipped as marks that never appeared at default zoom.
##
## A multiple is also the RIGHT shape rather than merely a working one. What
## decides whether a clip is worth playing is how big the villager looks, and
## that is apparent size, which is distance divided by how far back the camera
## is. Written this way the bands behave identically at every zoom level, which
## a pair of constants in metres could never do.
const REACT_NEAR := 1.35
const REACT_FAR := 2.20


## How far away this is, in camera-distances. 1.0 is the point the camera is
## looking at; the far edge of the view is somewhere near 1.8.
func _camera_distance(at: Vector3) -> float:
	if rig == null or rig.cam == null:
		return 0.0
	return rig.cam.global_position.distance_to(at) / maxf(1.0, float(rig.dist))


func _villagers_react(r: Dictionary) -> void:
	var hits: Array = r.get("hits", [])
	if hits.is_empty():
		return
	var at: Vector3 = r.get("at", Vector3.ZERO)
	var sorted := hits.duplicate()
	sorted.sort_custom(func(a, b):
		return (a[0] as Node3D).position.distance_squared_to(at) 			< (b[0] as Node3D).position.distance_squared_to(at))
	var turned := 0
	for h in sorted:
		if turned >= REACT_MAX:
			break
		var f = h[0]
		if not is_instance_valid(f) or f.brain == null:
			continue
		# LEVEL OF DETAIL, and it is a correctness question before it is a
		# performance one. A reaction is an animation clip plus an overhead
		# mark, and both are wasted on somebody the camera cannot resolve --
		# but the SIMULATION result is not: they were still paid, they still
		# remember it, they simply do not perform it for nobody.
		var d: float = _camera_distance(f.position)
		if d > REACT_FAR:
			continue
		# THE DEVOUT LOOK UP FIRST. Free characterisation from a roll that
		# already exists, and it keeps a crowd from moving as one body.
		var chance: float = 0.35 + 0.55 * float(f.brain.personality.devotion)
		if _rng.randf() > chance:
			continue
		f.notice_at(at)
		# The mark above the head is the cheapest part and the least readable
		# at range; near camera only.
		if overhead != null and d <= REACT_NEAR:
			overhead.mark(f)
		turned += 1

	# A TIER CROSSING SAYS ITS OWN NAME. `gain_faith` has always returned the
	# number of tiers crossed and nothing ever used it, so a villager reaching
	# Believer -- the one piece of progress in this game that cannot be lost --
	# happened in total silence.
	if int(r.get("tiers", 0)) <= 0 or floaters == null:
		return
	for h in hits:
		var f = h[0]
		if is_instance_valid(f) and f.brain != null:
			floaters.puff("bless", f.brain.faith_tier(),
						  f.position + Vector3(0, 1.35, 0))
			break


## THE HEARTBEAT.
##
## Every source of drama in this village runs on its own timer, which averages
## out fine and clumps badly: four things in ten seconds and then three quiet
## minutes, and the three minutes are what a player quits during. This does not
## take any decision away from those systems -- it only refuses to let the quiet
## run past about a minute, by leaning on whichever of them is currently able to
## fire. See director.gd for why the pressure behind it is never shown.
## WHOEVER BELIEVES HARDEST, reconsidered slowly and said out loud.
##
## Two announcements and they are deliberately different things. The title
## changing hands is news about a PERSON -- somebody the player has been paying
## into for twenty minutes -- so it is said whether or not anything else is
## happening. The proclamation is news about the GOD, and it only lands once per
## axis, because a prophet who tells you what you are every thirty seconds is a
## caption rather than a character.
func _tick_prophet() -> void:
	if divinity == null or village == null:
		return
	var was: String = divinity.prophet.name_of()
	if divinity.prophet.tick(folk, float(village.now)):
		var now_name: String = divinity.prophet.name_of()
		if now_name != "":
			divinity.notice.emit("%s speaks for you now." % now_name)
			chronicle.add("prophet", daylight.day,
						  "%s began to speak for you." % now_name)
			stats.reach("first_prophet")
			if fxe != null and divinity.prophet.has():
				fxe.burst("bless", divinity.prophet.who.position
									+ Vector3(0, 1.2, 0))
		elif was != "":
			# LOSING one is the half that makes having one mean anything.
			divinity.notice.emit("%s no longer speaks for you." % was)
			chronicle.add("prophet", daylight.day,
						  "%s stopped speaking for you." % was)
	var said: String = divinity.prophet.proclaim(divinity.reputation.title(),
												divinity.reputation.dominant())
	if said != "":
		divinity.notice.emit(said)


func _tick_director() -> void:
	if divinity == null or village == null or folk.size() < Director.MIN_FOLK:
		return
	var now := float(village.now)
	director.tick(now)
	var want := director.wants(now, {
		"newcomer": village.population < village.pop_cap,
		"wolf": divinity.age >= 2 and _has_prey(),
		# See Director.CALAMITY_FOLK: the director may not pull a disaster
		# forward into a village too young to survive one.
		"calamity": divinity.age >= 2 and calamities.is_empty() 			and folk.size() >= Director.CALAMITY_FOLK,
	})
	if want == "":
		return
	director.mark(want, now)
	match want:
		"newcomer":
			# Reach for the village's own timer rather than its guts: it
			# already knows where a newcomer may stand and what to say.
			_newcomer_timer = 0.01
		"wolf":
			_wolf_timer = 0.01
		"calamity":
			_calamity_timer = 0.01


func _has_prey() -> bool:
	for b in beasts:
		if is_instance_valid(b) and b.kind != "Animals/wolf":
			return true
	return false


## Is a BUILDING standing here? Dressing and trees do not count -- they are
## things the ground carries, not things that depend on it.
func _building_on(cell: Vector2i) -> bool:
	for e in builder.placed_props:
		if not is_instance_valid(e.get("node")):
			continue
		if not String(e.get("id", "")).begins_with("Buildings/"):
			continue
		var fp: Array = e.get("fp", [0.5, 0.5])
		var hc := int(ceil(float(fp[0]) / builder.tile / 2.0))
		var hr := int(ceil(float(fp[1]) / builder.tile / 2.0))
		if absi(cell.x - int(e.get("col", -999))) <= hc 				and absi(cell.y - int(e.get("row", -999))) <= hr:
			return true
	return false


## Is anything already standing here?
##
## Asked of the BUILDER rather than the walk grid, because the grid is rebuilt
## on a coalesced timer -- a tree planted half a second ago is not in it yet,
## and the second click on the same square would stack a bush inside the tree.
## The builder knows immediately.
func _prop_on(cell: Vector2i) -> bool:
	for e in builder.placed_props:
		if not is_instance_valid(e.get("node")):
			continue
		if int(e.get("col", -1)) == cell.x and int(e.get("row", -1)) == cell.y:
			return true
	return false


## One shared cooldown for every kind of touch.
## ASKING is not TAKING. These were one function, and it stamped the cooldown
## as a side effect of being asked -- so any caller that checked before acting
## consumed the touch it was checking for, and the action that followed was
## silently refused. Measured: economy_probe pre-checked, every one of its
## twelve thousand touches was swallowed, wood stayed at 3 for a full ten
## minutes, and the probe reported it as an economy failure.
func _touch_ready() -> bool:
	if village == null:
		return false
	return float(village.now) - _touched_at >= WorldTouch.COOLDOWN


func _touch_take() -> bool:
	if not _touch_ready():
		return false
	_touched_at = float(village.now)
	return true


## What a touch is worth: the goods, the sight of it, and the faith of whoever
## was near enough to see a god do something.
## `novelty_key` names the SPECIFIC table row, not the kind of act: greening is
## "touch:G", breaking a rock is "touch:Nature/rock". Sharing a key across rows
## would mean greening a hillside made fruiting a tree less impressive, and
## those are different verbs. Per-row keying is also self-limiting -- greening
## is spammable and fruiting is capped by how many trees exist.
func _touch_paid(act: Dictionary, at: Vector3, novelty_key := "") -> void:
	stats.note("touches")
	stats.reach("first_touch")
	var gives: Dictionary = act.get("gives", {})
	if not gives.is_empty():
		village.give(gives)
		for res in gives:
			var key := String(res)
			if floaters != null:
				floaters.spawn(String(RESOURCE_ROW.get(key, "food")), key,
							   int(gives[key]), at)
	# WHO SAW IT is the processor's business now. This function used to do its
	# own scan and throw the answer away; it keeps only what is genuinely local
	# to a touch -- the goods, the tokens, the little bump of fun, its own
	# click sound.
	var fun := float(act.get("fun", 0.0))
	var r: Dictionary = divinity.perform(
		DivineAction.touch(act, at, novelty_key))
	var seen: int = int(r["seen"])
	if fun > 0.0:
		for h in (r["hits"] as Array):
			var f = h[0]
			f.brain.stats["fun"] = minf(1.0, float(f.brain.stats["fun"]) + fun)
	if fxe != null:
		fxe.burst(String(act.get("fx", "grove")), at + Vector3(0, 0.4, 0))
	if sfx != null:
		sfx.play(String(act.get("sfx", "pick")))
	# THE MESSAGE IS CHORUS'S JOB NOW. This counted its own witnesses and wrote
	# its own line, and a second line saying the same thing is exactly what the
	# aggregation layer exists to stop. What stays here is the click's own
	# feedback -- the burst and the sound above -- which belongs to the touch
	# rather than to what anyone thought of it.
	if seen <= 0 and divinity != null:
		# Nobody saw it, so Chorus stays quiet: say what happened, at least.
		divinity.notice.emit(String(act.get("verb", "")))


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
		# The faith ladder. Absent on a pre-fix save, which restores an Atheist
		# -- exactly what every load did before these two keys existed.
		b.faith_xp = float(row.get("fxp", 0.0))
		b.faith_level = int(row.get("ftr", 0))
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
				"keep": float(e.get("kp", 0.0)),
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


## --- calamities -------------------------------------------------------------

## HOW OFTEN THE WORLD TAKES SOMETHING BACK.
##
## Gated on the second age for the same reason wolves are: a village that is
## still three people and a woodpile has nothing to lose and no card to answer
## with. After that it is one crisis every couple of minutes, never two at
## once -- two simultaneous disasters is not twice the drama, it is a mess with
## no right answer.
const CALAMITY_EVERY := 130.0


func _tick_calamities(delta: float) -> void:
	if divinity == null or grid == null:
		return
	for c in calamities:
		c.age += delta
		# Counted while it burns, because at the moment it ends nobody is in
		# danger any more and there would be nothing left to count.
		c.watch(folk, grid.world_of)
	_answer_calamities()
	for c in calamities.duplicate():
		if c.expired():
			_end_calamity(c, false)
	if not calamities.is_empty():
		if float(village.now) - _bite_at >= Calamity.BITE:
			_bite_at = float(village.now)
			for c in calamities:
				_bite(c)
		return
	if divinity.age < 2:
		return
	_calamity_timer -= delta
	if _calamity_timer <= 0.0:
		_calamity_timer = CALAMITY_EVERY
		_start_calamity()


func _start_calamity() -> void:
	# ONLY A KIND THE WORLD CAN ACTUALLY HOST. A fire needs a tree and a drought
	# needs grass, and picking blind meant a village with no trees rolled fire,
	# found nothing to burn, and spent the whole two-minute cycle on nothing --
	# so early on, when the plot is mostly desert, the world would go silent
	# exactly where it was supposed to start pushing back.
	var kinds: Array = Calamity.KINDS.duplicate()
	kinds.shuffle()
	var kind := ""
	var where := Vector2i(-1, -1)
	for k in kinds:
		var at := _somewhere_alive(String(k))
		if at.x >= 0:
			kind = String(k)
			where = at
			break
	if kind == "":
		return
	var winds: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0),
								  Vector2i(0, 1), Vector2i(0, -1)]
	var heading: Vector2i = winds[_rng.randi() % winds.size()]
	var c := Calamity.new(kind, where, heading)
	calamities.append(c)
	stats.note("disasters_started")
	# Tell the director, whether it asked for this or the village's own timer
	# did -- pressure is time since ANYTHING happened, not since the director
	# last spoke, or it would fire on top of the village's own drama.
	director.mark("calamity", float(village.now))
	var look: Dictionary = c.look()
	divinity.notice.emit(String(look["notice"]))
	if sfx != null:
		sfx.play(String(look["sfx"]))
	if fxe != null:
		fxe.burst(String(look["fx"]), grid.world_of(where) + Vector3(0, 0.6, 0))


## A cell worth losing: trees for a fire, grass for a drought, anything the
## player has touched for a wind.
func _somewhere_alive(kind: String) -> Vector2i:
	var pool: Array[Vector2i] = []
	if kind == "fire":
		for e in builder.placed_props:
			if String(e.get("id", "")).begins_with("Nature/tree"):
				pool.append(Vector2i(int(e.get("col", 0)), int(e.get("row", 0))))
	else:
		for row in builder.lower.size():
			var line: String = builder.lower[row]
			for col in line.length():
				if line[col] == "G":
					pool.append(Vector2i(col, row))
	if pool.is_empty():
		return Vector2i(-1, -1)
	return pool[_rng.randi() % pool.size()]


## One bite. Small, and on a slow clock, so there is time to answer.
func _bite(c) -> void:
	c.bites += 1
	var look: Dictionary = c.look()
	match c.kind:
		"fire":
			# Spreads to a neighbouring tree and scorches what it leaves.
			var burnt := _burn_at(c.cell)
			var next := _nearest_tree(c.cell, 6)
			if next.x >= 0:
				c.cell = next
			if burnt:
				c.eaten += 1
		"drought":
			# Grass back to dirt, outward from where it started.
			var dried := 0
			for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0),
					  Vector2i(0, 1), Vector2i(0, -1)]:
				var at: Vector2i = c.cell + d * c.bites
				if builder.code_at(builder.lower, at.x, at.y) != "G":
					continue
				# NOT UNDER A BUILDING. A drought reverting the tile a well
				# stands on leaves a well in the middle of a desert patch --
				# and, worse, leaves the world saying a building stands on
				# ground nothing may be built on, which every buildability test
				# then disagrees with. Grass under a tree is fair game; grass
				# under a roof is not.
				if _building_on(at):
					continue
				if builder.set_tile(at.x, at.y, "D"):
					grid.set_code(at, "D")
					dried += 1
			c.eaten += dried
		"tornado":
			# Walks, and flattens whatever it crosses.
			c.cell += c.dir
			for e in builder.placed_props.duplicate():
				if not is_instance_valid(e.get("node")):
					continue
				if Vector2i(int(e.get("col", -1)), int(e.get("row", -1))) != c.cell:
					continue
				if String(e.get("id", "")).begins_with("Buildings/bridge"):
					continue
				builder.remove_prop(e)
				c.eaten += 1
			queue_grid_rebuild()
	if fxe != null:
		fxe.burst(String(look["fx"]),
				  grid.world_of(c.cell) + Vector3(0, 0.5, 0))


func _burn_at(cell: Vector2i) -> bool:
	for e in builder.placed_props.duplicate():
		if not is_instance_valid(e.get("node")):
			continue
		if Vector2i(int(e.get("col", -1)), int(e.get("row", -1))) != cell:
			continue
		if not String(e.get("id", "")).begins_with("Nature/"):
			continue
		builder.remove_prop(e)
		queue_grid_rebuild()
		if builder.code_at(builder.lower, cell.x, cell.y) == "G":
			if builder.set_tile(cell.x, cell.y, "D"):
				grid.set_code(cell, "D")
		return true
	return false


func _nearest_tree(from: Vector2i, within: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := within + 1
	for e in builder.placed_props:
		if not String(e.get("id", "")).begins_with("Nature/tree"):
			continue
		var c := Vector2i(int(e.get("col", 0)), int(e.get("row", 0)))
		var d: int = absi(c.x - from.x) + absi(c.y - from.y)
		if d < best_d and d > 0:
			best_d = d
			best = c
	return best


## A HELD MIRACLE PUTS IT OUT, if it is the right one and it is close enough.
##
## Checked against where the effigy actually IS rather than where the card was
## played: the whole shape of a miracle in this game is that you sweep it over
## something, so answering a fire has to mean holding the rain over the fire.
func _answer_calamities() -> void:
	if cursor == null or not cursor.is_active() or calamities.is_empty():
		return
	var at: Vector3 = cursor.global_position
	for c in calamities.duplicate():
		if not c.answered_by(String(cursor.id)):
			continue
		if grid.world_of(c.cell).distance_to(at) > cursor.radius + 1.5:
			continue
		_end_calamity(c, true)


## The end of one, either answered or burnt out. Answering pays FAITH FROM
## EVERY VILLAGER -- the village thanks you, and a crisis leaves the place more
## devout than it found it.
## What a disaster is called when it is over, either way.
const CALAMITY_HEAD := {
	"fire": ["FIRE CONTAINED", "THE FIRE BURNED OUT"],
	"drought": ["THE DROUGHT BREAKS", "THE DROUGHT RAN ITS COURSE"],
	"tornado": ["THE WIND IS STILLED", "THE WIND BLEW ITSELF OUT"],
}

## How an axis is named when the player is told it moved.
const AXIS_TITLE := {
	"provider": "Provider", "protector": "Protector", "nature": "Nature",
	"life": "Life", "wrath": "Wrath", "fortune": "Fortune",
}


func _end_calamity(c, solved: bool) -> void:
	calamities.erase(c)
	var heads: Array = CALAMITY_HEAD.get(c.kind, CALAMITY_HEAD["fire"])
	if not solved:
		divinity.notice.emit("It burns itself out. %d lost." % c.eaten)
		chronicle.add("loss", daylight.day,
			"The %s ran its course. %d lost." % [c.kind, c.eaten])
		stats.note("disasters_lost")
		_aftermath(String(heads[1]), false, [
			["punish", "%d lost to it" % c.eaten, Aftermath.BAD],
			["pop", "%d stood in its way" % c.saved(folk), Aftermath.DIM],
		])
		return
	# EVERY VILLAGER, UNBANDED, and that is a decision rather than an oversight.
	# Thinning relief by distance from the fire would pay the people who were
	# furthest from danger the least, which is backwards -- and calamity.gd's
	# own header says a crisis should leave the place more devout. Note that
	# calamity_probe cannot catch a regression here: it checks one villager and
	# never looks at where they were standing.
	var a := DivineAction.relief(c.thanks())
	a.verb = "You answered it."
	var r: Dictionary = divinity.perform(a)
	var n: int = int(r["seen"])
	if fxe != null:
		fxe.burst("bless", grid.world_of(c.cell) + Vector3(0, 0.6, 0))
	if sfx != null:
		sfx.play("bless")
	divinity.notice.emit("You answered it. %d gave thanks." % n)
	chronicle.add("disaster", daylight.day,
		"You answered the %s. %d were saved." % [c.kind, c.saved(folk)])
	stats.note("disasters_answered")
	stats.reach("first_disaster_answered")

	# THE REPORT. Three lines, and the order is the order the player cares
	# about: who got out, what it paid, and what it made you.
	var rows: Array = []
	var rescued: int = c.saved(folk)
	if rescued > 0:
		rows.append(["cross", "%d saved" % rescued, Aftermath.GOOD])
	if c.eaten > 0:
		rows.append(["punish", "%d lost" % c.eaten, Aftermath.DIM])
	rows.append(["faith", "+%d Faith" % int(round(float(r["faith"]))),
				 Aftermath.GOLD])
	var axis: String = Reputation.leading_from(a.tags)
	if axis != "" and n > 0:
		rows.append(["saint", "%s rising" % String(AXIS_TITLE.get(axis, axis)),
					 Aftermath.GOOD])
	_aftermath(String(heads[0]), true, rows)


func _aftermath(head: String, good: bool, rows: Array) -> void:
	if aftermath != null:
		aftermath.show_report(head, good, rows)


## Losing focus pauses the village.
##
## Portals expect it, and it closes a real hole besides: without it, a tab left
## open in the background keeps burning game time it will never be watched for,
## and the away roll then measures an absence the village did not actually
## have. Guarded on the same real-game check the disk layer uses, because every
## probe parks its window unfocused and a probe that paused itself at startup
## would hang forever.
## WIPE THE SAVE AND START CLEAN. F8.
##
## "Start over" in the pause menu does the same thing and is the one a player
## uses; this is the one you want while testing, because it skips the
## are-you-sure and it can be hit without taking a hand off the mouse.
##
## Note it is NOT gated behind the debug panel. A reset you can only reach by
## opening a panel is a reset you cannot use to test what happens on a fresh
## boot, which is the thing it exists for.
const WIPE_KEY := KEY_F8


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or k.keycode != WIPE_KEY:
		return
	get_viewport().set_input_as_handled()
	wipe_save()


## Erase the save and rebuild the world from nothing.
##
## `armed = false` FIRST, and it is the load-bearing line: reloading the scene
## frees this node, the save layer writes on the way out, and without it the
## village you just deleted is written straight back over the hole.
func wipe_save() -> void:
	SaveGame.erase()
	if saving != null:
		saving.armed = false
	if divinity != null:
		divinity.notice.emit("Save wiped. Starting over.")
	get_tree().paused = false
	get_tree().reload_current_scene()


func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_OUT:
		return
	if not Persistence.is_real_game(get_tree()):
		return
	if pause_menu != null and not pause_menu.is_open() 			and (day_screen == null or not day_screen.is_open()):
		pause_menu.open()


## Night. For now this marks the day and saves; the Day Summary and the
## overnight aura are the next piece, and this is the seam they attach to.
func _on_night(which: int) -> void:
	if sfx != null:
		sfx.play("coin", 0.8)
	# A day boundary is exactly the moment a player might close the tab, so it
	# is worth a write of its own rather than waiting for the autosave.
	if saving != null:
		saving.save_now("night")
	if not night_screen or day_screen == null:
		_start_day()
		return
	# The HUD does not process while paused, so it would keep whatever frame it
	# last drew -- yesterday's day number, under a screen announcing tonight.
	# Drawing is not pause-gated, only processing, so one request is enough.
	if hud != null:
		hud.queue_redraw()
	day_screen.open_night(_day_summary(which))
	# STOP the village. The point of nightfall is that the day is over, and a
	# summary you have to read while the simulation runs on underneath it is a
	# summary nobody reads.
	get_tree().paused = true


## The numbers this day earned, as deltas against the mark taken at dawn.
func _day_summary(which: int) -> Dictionary:
	var built := 0
	for aid in village.structures:
		if String(aid).begins_with("Buildings/"):
			built += int(village.structures[aid])
	return {
		"day": which,
		"built": maxi(0, built - int(_day_mark.get("built", 0))),
		"newcomers": maxi(0, folk.size() - int(_day_mark.get("folk", 0))),
		"faith": maxf(0.0, divinity.total_earned
					  - float(_day_mark.get("earned", 0.0))),
		"gathered": maxi(0, village.total_gathered
						 - int(_day_mark.get("gathered", 0))),
		"drama": _day_drama,
		"aura": saving.aura if saving != null else "",
	}


## Dawn: unpause, take the mark the next summary will be measured against.
func _start_day() -> void:
	get_tree().paused = false
	var built := 0
	for aid in village.structures:
		if String(aid).begins_with("Buildings/"):
			built += int(village.structures[aid])
	_day_mark = {"built": built, "folk": folk.size(),
				 "earned": divinity.total_earned,
				 "gathered": village.total_gathered}
	_day_drama = ""


## Warm the light as the day runs out.
##
## The sun's own colour and angle, interpolated away from the measured daytime
## values and back -- those stay the noon anchor and are never retuned here.
## Without this the countdown is a number on a panel; with it the world itself
## is the clock, which is what a player actually notices.
func _sky_for(dusk: float) -> void:
	if light == null or light.sun == null:
		return
	var warm := Color(0.99, 0.72, 0.42)
	light.sun.light_color = ValeLight.SUN_COLOR.lerp(warm, dusk * 0.85)
	light.sun.light_energy = ValeLight.SUN_ENERGY * (1.0 - 0.35 * dusk)
	var e := ValeLight.SUN_EULER
	# Down toward the horizon, never past it: the shadows lengthen, the plot
	# stays readable, and nobody has to play in the dark.
	light.sun.rotation_degrees = Vector3(e.x + 22.0 * dusk, e.y, e.z)


## The disk layer, and the away log if this launch opened a save.## The disk layer, and the away log if this launch opened a save.
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
	var streak: int = int(log.get("streak", 1))
	var gift := _streak_gift(streak)
	var faith: float = float(log.get("faith", 0.0))
	if faith <= 0.0 and gift == "" and (log.get("lines", []) as Array).is_empty():
		return
	divinity.add_faith(faith)
	if not night_screen or day_screen == null:
		return
	log["day"] = daylight.day
	log["gift"] = gift
	log["span"] = _span(float(log.get("seconds", 0.0)))
	# WHAT THIS VILLAGE REMEMBERS, and WHAT HAS NOT FINISHED HAPPENING. The
	# away log has only ever been able to talk about a stretch of time nobody
	# watched; these two put it in a village with a past and a present.
	log["history"] = chronicle.recent(3)
	log["pending"] = Chronicle.pending(self)
	day_screen.open_morning(log)
	get_tree().paused = true


## What showing up again is worth. Small, escalating, and never a substitute
## for playing -- the streak is a reason to open the tab, not a way to win.
## TWO FULL-SCREEN MODALS AT ONCE, which is what this used to do.
##
## The streak gift called `grant_draft` here, which opens the boon draft, and
## then the caller opened the morning screen straight on top of it. The player
## came back to a stack: an away log they could read, over three boon cards they
## could not reach, and no way to tell that the second thing was even there.
##
## The draft is now REMEMBERED and dealt when the morning screen is dismissed,
## which is also the right order to read them in -- what happened while you were
## gone, and then what you get for it.
var _draft_owed := ""


func _streak_gift(streak: int) -> String:
	if streak < 2:
		return ""
	if streak >= 5:
		divinity.add_faith(80.0)
		_draft_owed = "streak"
		return "A gift, and 80 Faith."
	if streak >= 3:
		_draft_owed = "streak"
		return "A gift waits for you."
	divinity.add_faith(40.0)
	return "40 Faith for your return."


## Hand over anything the return owes, once the player has finished reading.
func pay_owed_draft() -> void:
	if _draft_owed == "":
		return
	var source := _draft_owed
	_draft_owed = ""
	divinity.grant_draft(source)


func _span(seconds: float) -> String:
	if seconds < 3600.0:
		return "You were gone %d minutes." % maxi(1, int(seconds / 60.0))
	if seconds < 48.0 * 3600.0:
		return "You were gone %d hours." % int(seconds / 3600.0)
	return "You were gone %d days." % int(seconds / 86400.0)


## Sound and one-shot FX for everything the player does or watches happen.## Sound and one-shot FX for everything the player does or watches happen.
##
## Wired HERE rather than inside each system, so Divinity and Social stay
## testable without an audio bus or a particle pool -- both of the headless
## probes run them with neither, and a system that emitted its own effects
## could not be run that way.
func _wire_feedback() -> void:
	divinity.judged.connect(func(who, good):
		if good:
			stats.note("blessings")
			stats.reach("first_bless")
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
		# Every job STARTS with something. Only chopping and the four gathering
		# actions made a sound, so quarrying, praying, singing, tending,
		# hunting and all fourteen build actions began in total silence -- a
		# villager walked somewhere and then nothing happened for eight
		# seconds.
		sfx.play(String(ARRIVAL_SFX.get(act, "pick" if act.begins_with("build_")
										else "")), 1.0)
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
			stats.reach("first_building")
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
## What a job sounds like when it BEGINS, as opposed to when it pays out.
const ARRIVAL_SFX := {
	"chop": "chop", "quarry": "chop", "hunt": "chop",
	"harvest": "pick", "forage": "pick", "eat": "pick", "wash": "pick",
	"sow": "pick", "tend": "pick",
	"pray": "chat", "sing": "chat", "play": "chat", "rest": "chat",
	"bless_flock": "miracle",
	"steal": "deny", "shirk": "deny", "brawl": "deny",
}

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
	# Being frightened by a wolf produced NOTHING -- not in this table, not a
	# build, not a sin, so _report_job found nothing to show and the one moment
	# the village is in danger passed in silence.
	"flee":        {"fx": "punish", "sfx": "deny", "icon": "bolt"},
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
		_day_drama = "%s took the easy way." % f.brain.name
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

	aftermath = Aftermath.new()
	aftermath.name = "Aftermath"
	aftermath.comfort = comfort
	ui.add_child(aftermath)

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

	# THE ONLY THING ALLOWED TO TURN A DIVINE ACT INTO A MESSAGE. Every witness
	# result goes through here and comes out as one line rather than one per
	# villager -- see chorus.gd for why that is the whole point of it.
	chorus = Chorus.new()
	chorus.name = "Chorus"
	chorus.floaters = floaters
	chorus.fxe = fxe
	chorus.sfx = sfx
	chorus.hud = hud
	chorus.village = village
	ui.add_child(chorus)
	chorus.listen(divinity)
	divinity.witnessed.connect(_villagers_react)

	# THE VILLAGE ASKS. Built after Chorus so the answer's feedback has
	# somewhere to go, and after divinity so it can listen for witnesses.
	prayers = Prayers.new()
	prayers.name = "Prayers"
	prayers.host = self
	prayers.village = village
	prayers.divinity = divinity
	add_child(prayers)
	# THE AGES, which are the most memorable thing the game has and were the one
	# event that scrolled past in four seconds with nowhere to go and see it
	# again.
	divinity.age_reached.connect(func(i: int, what: String):
		chronicle.add("age", daylight.day, "%s." % what)
		if i >= 1:
			stats.reach("age_1"))

	prophecies = Prophecies.new()
	prophecies.host = self
	prophecies.spoken.connect(func(p: Prophecy):
		stats.note("prophecies_spoken")
		divinity.notice.emit(p.spoken)
		if sfx != null:
			sfx.play("bless"))
	prophecies.fulfilled.connect(func(p: Prophecy):
		divinity.notice.emit("It came to pass.")
		chronicle.add("prophecy", daylight.day, p.spoken + " It came to pass.")
		stats.note("prophecies_kept")
		stats.reach("first_prophecy_kept")
		if aftermath != null:
			aftermath.show_report("IT CAME TO PASS", true, [
				[p.icon(), String(p.spec().get("short", "%d/%d"))
					% [p.need, p.need], Aftermath.GOOD],
				["faith", "+%d Faith" % int(Prophecy.FAITH), Aftermath.GOLD],
			]))
	prophecies.broken.connect(func(p: Prophecy):
		# NO PENALTY, and the line says so. The prophet was wrong; that is a
		# thing that happens to prophets.
		divinity.notice.emit("The hour passed, and it did not come.")
		chronicle.add("prophecy", daylight.day,
					  p.spoken + " The hour passed, and it did not.")
		stats.note("prophecies_broken")
		if aftermath != null:
			aftermath.show_report("IT DID NOT COME", false, [
				[p.icon(), String(p.spec().get("short", "%d/%d"))
					% [mini(p.at(self), p.need), p.need], Aftermath.DIM],
			]))

	# THE SESSION STARTS NOW, not at the dawn of the village. `Village.now` is
	# restored from the save and keeps counting, so without this every funnel
	# step on a loaded game would be stamped with the total age of the village
	# -- "they reached the first prophet after four hours" for something that
	# happened forty seconds after they opened the tab.
	stats.begin(float(village.now))

	prayers.opened.connect(func(p: Prayer):
		stats.note("prayers_opened")
		stats.reach("first_prayer_seen"))
	prayers.closed.connect(func(_p: Prayer, answered: bool):
		stats.note("prayers_answered" if answered else "prayers_lapsed")
		if answered:
			stats.reach("first_prayer_answered"))
	prayers.listen()
	# TAKING A SIDE IS SAID OUT LOUD, and it names the person who lost. A choice
	# nobody is told about is not a choice, it is a coin the game flipped.
	prayers.took_sides.connect(func(won: Prayer, lost: Prayer):
		if not is_instance_valid(won.who) or not is_instance_valid(lost.who):
			return
		divinity.notice.emit("You sided with %s. %s will remember."
			% [String(won.who.brain.name), String(lost.who.brain.name)])
		stats.note("feuds_settled")
		chronicle.add("feud", daylight.day,
			"You took %s's side against %s."
			% [String(won.who.brain.name), String(lost.who.brain.name)]))
	prayers.opened.connect(func(pr):
		# Somebody asking for something IS the interesting thing happening.
		director.mark("prayer", float(village.now))
		# The bubble is the real announcement; the line is for anyone whose eye
		# was somewhere else, and only for the ones that are actually urgent.
		if pr.urgent and divinity != null:
			divinity.notice.emit(pr.says()))
	prayers.closed.connect(func(pr, answered):
		if answered and divinity != null:
			divinity.notice.emit("%s got what they asked for."
				% pr.who.brain.name if is_instance_valid(pr.who) else "Answered."))

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
			return
		divinity.notice.emit("The %s touched %d, and you gained %d Faith."
			% [id, touched, int(gain)])
		# ONE token for the whole sweep. The cursor used to emit `earned` per
		# villager, so eight people meant eight tokens racing the counter; the
		# credit was always right and the picture of it was a pile-up.
		if floaters != null and gain >= 1.0:
			floaters.spawn("faith", "faith", int(round(gain)),
						   cursor.global_position - Vector3(0, 1.6, 0)))

	# The draft sits ABOVE everything and takes every click while it is open.
	draft = BoonDraft.new()
	draft.name = "BoonDraft"
	draft.divinity = divinity
	ui.add_child(draft)
	# Escape's home. Above everything, because a paused game that cannot be
	# unpaused is the worst bug a portal build can have.
	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	pause_menu.comfort = comfort
	pause_menu.comfort_changed.connect(_apply_comfort)
	ui.add_child(pause_menu)
	pause_menu.muted_changed.connect(func(on: bool):
		if sfx != null:
			sfx.set_muted(on)
		if music != null:
			music.set_muted(on))
	# ONE DOOR. "Start over" and the F8 debug key are the same operation, and
	# a second copy of it is how one of them quietly stops erasing the save.
	pause_menu.restarted.connect(wipe_save)

	# ABOVE the draft: a day that ends while a gift is pending must still end,
	# and the gift is waiting on the other side of the morning.
	day_screen = DayScreen.new()
	day_screen.name = "DayScreen"
	ui.add_child(day_screen)
	day_screen.aura_chosen.connect(func(id):
		if saving != null:
			saving.aura = id
		divinity.notice.emit("The village sleeps under %s." % id))
	day_screen.rested.connect(func():
		day_screen.close()
		_start_day()
		pay_owed_draft()
		if saving != null:
			saving.save_now("rest"))
	day_screen.resumed.connect(func():
		day_screen.close()
		_start_day()
		pay_owed_draft())

	divinity.draft_offered.connect(draft.open)
	draft.chosen.connect(func(id):
		stats.note("boons_taken")
		stats.reach("first_boon")
		divinity.take_boon(id)
		draft.close()
		fxe.burst("bless", _village_centre())
		sfx.play("coin", 0.85))
	draft.rerolled.connect(func():
		divinity.add_faith(-float(draft.reroll_cost()))
		draft.open(divinity.boons.offer(), draft._source)
		sfx.play("chat", 1.2))

	# A CLICK IS A BLESSING, and it opens the panel in the same motion.
	#
	# Blessing used to cost two clicks and a hunt for a small button: select,
	# find Bless, press it -- inside a four-second window, on a villager who is
	# walking. The verb is now the click itself, and the panel comes with it so
	# the player still learns who they just blessed. One tap, which is also the
	# only shape that will work on a phone.
	overhead.follower_clicked.connect(func(who):
		panel.show_for(who)
		divinity.bless(who))
	panel.bless_pressed.connect(func(who): divinity.bless(who))
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
	director.mark("newcomer", float(village.now))
	# BORN ALREADY KNOWING YOUR NAME. Asked at the moment of birth, so a boon
	# taken later never retroactively converts anybody -- which is the whole
	# reason boons are questions rather than things that get applied.
	var inherited: float = divinity.boons.birth_faith()
	if inherited > 0.0:
		f.brain.gain_faith(inherited)
	village.population = folk.size()
	stats.note("births")
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
	if _day_drama == "":
		_day_drama = "%s came up the road and stayed." % who.brain.name
	stats.note("newcomers")
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
		3:
			if folk.size() < 20:
				return "Grow to 20 souls  (%d)" % folk.size()
			return "Bring them through a night"
		4:
			return "Hold four plots  (%d)" % islands.count()
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
	if daylight != null:
		daylight.tick(delta)
		_sky_for(daylight.dusk_amount())
		if music != null:
			music.set_dusk(daylight.dusk_amount(), delta)
	_tick_calamities(delta)
	_tick_director()
	_tick_prophet()
	stats.now = float(village.now)
	if prophecies != null and village != null:
		prophecies.tick(float(village.now))
	_tick_tides()
	if prayers != null:
		prayers.tick(delta)
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
