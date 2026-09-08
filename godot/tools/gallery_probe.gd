extends SceneTree
## A picture of everything the content batch added, in the game's own renderer.
##
## Two shots. `gallery_folk.png` lines up the nine humans and three animals in a
## row at play scale, walking; `gallery_buildings.png` stages every building
## in a grid on the home plot. Not a correctness check -- the probes do that --
## this is what the batch LOOKS like, which is what it was for.
const ShotWindowRef := preload("res://tools/shot_window.gd")

const FOLK := ["Folk/villager", "Folk/adventurer", "Folk/priest", "Folk/nurse",
			   "Folk/bard", "Folk/builder", "Folk/lumberjack", "Folk/miner",
			   "Folk/hunter"]
const SPACING := 1.05   ## metres between two subjects in the row
const BEASTS := ["Animals/sheep", "Animals/lamb", "Animals/cow", "Animals/wolf"]
const BUILDINGS := ["Buildings/hut", "Buildings/hut_b", "Buildings/cottage",
					"Buildings/cottage_b", "Buildings/shrine", "Buildings/mansion",
					"Buildings/tavern", "Buildings/hotel", "Buildings/lumber_camp",
					"Buildings/mine", "Buildings/smithy", "Buildings/barracks",
					"Buildings/farm", "Buildings/farm_b", "Buildings/windmill",
					"Buildings/well", "Buildings/market_stall"]

var _f := 0
var _root: Node = null
var _stage := 0
var _row: Array = []
var _seats: Array[Vector3] = []


func _initialize() -> void:
	ShotWindowRef.park()
	get_root().add_child(
		(load("res://scenes/vale.tscn") as PackedScene).instantiate())


func _process(_d: float) -> bool:
	_f += 1
	if _f < 30:
		return false
	if _f == 30:
		for n in get_root().get_children():
			if n.get("divinity") != null:
				_root = n
		if _root == null:
			printerr("[GALLERY] FAIL: no scene root")
			quit(1)
			return true
		# Grass, because this probe is not about the desert.
		TestGround.green(_root)
		_root.draft.close()
		_root.divinity.pending_draft = []
		for n in _root.POP_MILESTONES:
			_root._milestones_paid[n] = true
		_line_up_folk()
		return false
	# Folk: they keep their walk cycle (a static row of statues says nothing
	# about the rig), but they are re-seated on the line every frame -- left to
	# themselves they scattered across a river inside half a second.
	if _f > 30 and _f < 60:
		_hold_row()
	if _f == 60:
		get_root().get_texture().get_image().save_png("res://shots/gallery_folk.png")
		print("[GALLERY] wrote res://shots/gallery_folk.png")
		# The same row with the job badges lit, which is how a player tells a
		# miner from a bard without clicking on one.
		# The HUD reassigns `highlight_all` from the aimed miracle every frame,
		# so setting it once is stomped before the next draw. Freezing the
		# HUD's process is enough for one shutter and touches no game code.
		if _root.hud != null:
			_root.hud.set_process(false)
		if _root.overhead != null:
			_root.overhead.highlight_all = true
		return false
	if _f > 60 and _f < 68:
		_hold_row()
		if _root.overhead != null:
			_root.overhead.highlight_all = true
		return false
	if _f == 68:
		get_root().get_texture().get_image().save_png("res://shots/gallery_jobs.png")
		print("[GALLERY] wrote res://shots/gallery_jobs.png")
		if _root.overhead != null:
			_root.overhead.highlight_all = false
		if _root.hud != null:
			_root.hud.set_process(true)
		_stage_buildings()
		return false
	if _f == 78:
		get_root().get_texture().get_image().save_png(
			"res://shots/gallery_buildings.png")
		print("[GALLERY] wrote res://shots/gallery_buildings.png")
		quit(0)
		return true
	return false


## Every human and animal in one row across open ground, camera pulled in so
## a villager is ~90 px -- twice play scale, close enough to tell a nurse from
## a priest but far enough that only the silhouette and one accent count.
func _line_up_folk() -> void:
	var jobs := ["villager", "adventurer", "priest", "nurse", "bard", "builder",
				 "lumberjack", "miner", "hunter"]
	var n := jobs.size() + BEASTS.size()
	# Frame first, THEN lay the line: the row runs along the camera's own right
	# vector, so all thirteen face the lens broadside. Laid along +X it ran
	# diagonally into the distance and the far end was three pixels wide.
	_root.rig.focus = _root._village_centre()
	_root.rig.dist = 16.5
	_root.rig.call("_place")
	var cam: Camera3D = _root.rig.cam
	var right := cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	# The village centre drifts with whoever is wandering, and twice it put the
	# row in the river. Score the ground along the line instead and stand them
	# where the most of it is plain grass.
	var centre := _best_line_centre(right, n)
	# Aim past the line rather than at it: the rig pins focus to the ground
	# plane, so a row of standing figures sits in the top third of the frame
	# unless the camera looks a little beyond them.
	var fwd := (centre - cam.global_position)
	fwd.y = 0.0
	_root.rig.focus = centre + fwd.normalized() * 2.0
	_root.rig.call("_place")
	_clear_line(centre, right, float(n - 1) * 0.5 * SPACING)
	_root.village.pop_cap = 200
	var i := 0
	for job in jobs:
		var at: Vector3 = centre + right * (float(i) - float(n - 1) * 0.5) * SPACING
		var f = _root._spawn_thinker(job, at, 1.0)
		if f != null:
			f.brain.job = job
			_row.append(f)
			_seats.append(at)
		i += 1
	for aid in BEASTS:
		var at: Vector3 = centre + right * (float(i) - float(n - 1) * 0.5) * SPACING
		var b = _root._spawn_beast(aid, at)
		if b != null:
			_row.append(b)
			_seats.append(at)
		i += 1


## The cell whose `n`-subject line lies on the most plain grass.
func _best_line_centre(right: Vector3, n: int) -> Vector3:
	var g = _root.grid
	var near: Vector3 = _root._village_centre()
	var best: Vector3 = near
	var best_score := -1.0
	for c in g.walkable_cells():
		var base: Vector3 = g.world_of(c)
		var plain := 0
		for i in n:
			var at: Vector3 = base + right * (float(i) - float(n - 1) * 0.5) * SPACING
			if g.is_plain(g.cell_of(at)):
				plain += 1
		var score := float(plain) * 1000.0 - base.distance_squared_to(near)
		if score > best_score:
			best_score = score
			best = base
	return best


## Clear the trees and bushes off the strip the row stands on, so the gallery
## is of the characters and not of the shrubbery in front of them.
func _clear_line(centre: Vector3, right: Vector3, half_len: float) -> void:
	var doomed: Array = []
	for e in _root.builder.placed_props:
		var node = e.get("node")
		if not is_instance_valid(node):
			continue
		var d: Vector3 = node.global_position - centre
		d.y = 0.0
		var along: float = d.dot(right)
		var across: float = d.dot(right.cross(Vector3.UP))
		if absf(along) < half_len + 1.5 and absf(across) < 4.5:
			doomed.append(e)
	for e in doomed:
		_root.builder.remove_prop(e)
	_root.queue_grid_rebuild()


## Put every subject back on its seat, facing the camera.
func _hold_row() -> void:
	var cam: Camera3D = _root.rig.cam
	for k in _row.size():
		var n = _row[k]
		if is_instance_valid(n):
			n.position = _seats[k]
			var to := cam.global_position
			to.y = n.global_position.y
			if n.global_position.distance_to(to) > 0.01:
				# look_at aims -Z at the target and these models face +Z, so
				# without the half turn the gallery is thirteen backs.
				n.look_at(to, Vector3.UP)
				n.rotate_y(PI)


## Every building staged on open ground, stamped straight into the builder
## (no villager has to afford them), camera framed on the block.
##
## A fixed lattice of cells does not work: the home plot is an irregular island
## with water, trees and the founders' own huts on it, so ten of seventeen
## sites on an 8-cell pitch fell on something. This walks the buildable cells
## outward from the centre instead and takes the first one that is far enough
## from everything already staged -- placement follows the ground.
func _stage_buildings() -> void:
	var centre: Vector3 = _root._village_centre()
	var cells: Array[Vector2i] = _root.grid.walkable_cells()
	# Nearest-first, so the gallery packs around the middle of the island
	# rather than trailing off to whichever corner the array happened to list.
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _root.grid.world_of(a).distance_squared_to(centre) 			< _root.grid.world_of(b).distance_squared_to(centre))
	const PITCH := 6            # cells between two staged buildings
	var taken: Array[Vector2i] = []
	var placed := 0
	var lo := Vector3(1e9, 0, 1e9)
	var hi := Vector3(-1e9, 0, -1e9)
	for aid in BUILDINGS:
		var got := false
		for c in cells:
			var clear := true
			for t in taken:
				if absi(t.x - c.x) < PITCH and absi(t.y - c.y) < PITCH:
					clear = false
					break
			if not clear or not _root.grid.is_buildable(c):
				continue
			if not _root.builder.add_prop(aid, c.x, c.y, 0.0):
				continue
			taken.append(c)
			var w: Vector3 = _root.grid.world_of(c)
			lo = Vector3(minf(lo.x, w.x), 0, minf(lo.z, w.z))
			hi = Vector3(maxf(hi.x, w.x), 0, maxf(hi.z, w.z))
			placed += 1
			got = true
			break
		if not got:
			print("[GALLERY] could not stage %s" % aid)
	_root.queue_grid_rebuild()
	print("[GALLERY] staged %d of %d buildings" % [placed, BUILDINGS.size()])
	if placed > 0:
		_root.rig.focus = (lo + hi) * 0.5
		_root.rig.dist = maxf(26.0, lo.distance_to(hi) * 1.15)
		_root.rig.call("_place")


## A run of `n` cells of plain grass in a straight line, for the folk row.
##
## `is_buildable` was too strict -- it also refuses any cell a prop already
## stands on, and there is no 14-cell run of virgin ground on the home island.
## `is_plain` asks the question that actually matters here: grass, not a road,
## a field, a bank, a bridge deck or water. The subjects are re-seated every
## frame, so a bush in the way costs nothing; a river costs the shot.
func _open_row_start(n: int) -> Vector2i:
	var g = _root.grid
	var centre: Vector3 = _root._village_centre()
	var best := Vector2i(-1, -1)
	var best_score := -1.0
	for start in g.walkable_cells():
		var plain := 0
		for step in n:
			if g.is_plain(start + Vector2i(step * 2, 0)):
				plain += 1
		if plain == 0:
			continue
		# All-or-nothing found nothing: the island's grass is cut up by roads,
		# fields and banks, and no 14-stride line of it exists. Score instead --
		# the most grass, ties broken by nearness to the village centre.
		var d: float = g.world_of(start).distance_squared_to(centre)
		var score := float(plain) * 1000.0 - d
		if score > best_score:
			best_score = score
			best = start
	return best
