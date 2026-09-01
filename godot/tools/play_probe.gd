extends SceneTree
## Drive the gameplay slice the way a player would, and check what happened.
##
## Not "does the code run" -- does CLICKING do the thing. Every step below is a
## synthetic input or a call the UI itself makes, followed by an assertion
## about the world that the click was supposed to change. A probe that only
## called Divinity directly would pass with the entire HUD disconnected.
##
## Screenshots are captured along the way so the panel and the icons can be
## looked at, because "the bar is 62%" is checkable and "the panel is legible"
## is not.
const ShotWindowRef := preload("res://tools/shot_window.gd")

var _f := 0
var _root: Node = null
var _step := 0
var _faults: Array[String] = []
var _shots := 0
var _prev := PackedByteArray()


func _initialize() -> void:
	ShotWindowRef.park()
	get_root().add_child(
		(load("res://scenes/vale.tscn") as PackedScene).instantiate())


func _process(_d: float) -> bool:
	_f += 1
	if _f == 20:
		for n in get_root().get_children():
			if n.get("divinity") != null:
				_root = n
		if _root == null:
			printerr("[PLAY] FAIL: no scene root")
			quit(1)
			return true
		print("[PLAY] village up: %d folk, %.0f faith"
			% [_root.folk.size(), _root.divinity.faith])
	if _f < 20:
		return false
	# One step every 30 frames, so each change has time to reach the screen
	# before the next one is asked for.
	if _f % 30 != 0:
		return false
	_step += 1
	match _step:
		1: _hover_and_click()
		2: _shoot("play_1_panel")
		3: _check_panel()
		4: _bless()
		5: _cards()
		6: _cast_ground_card()
		7: _shoot("play_2_after_miracle")
		8: _smite()
		9: _shoot("play_3_after_wrath")
		10: _check_feedback()
		11: _buy_island()
		12: _shoot("play_4_island")
		13: _check_island()
		14: _check_clips()
		_:
			_report()
			return true
	return false


## --- steps ------------------------------------------------------------------

func _hover_and_click() -> void:
	var who = _root.folk[0]
	# Put the mouse exactly where that villager's head projects, then let the
	# overhead layer resolve it -- the same path a real hover takes.
	var head: Vector3 = who.position + Vector3(0, Overhead.HEAD_HEIGHT, 0)
	var at: Vector2 = _root.rig.cam.unproject_position(head)
	var hit = _root.overhead._under(at)
	print("[PLAY] hover at %s -> %s" % [str(at.round()),
		"nothing" if hit == null else String(hit.brain.name)])
	if hit != who:
		_faults.append("hovering a villager's own head did not pick them")
	_root.overhead.selected = who
	_root.panel.show_for(who)
	# A mood face must be one of the three the design names.
	var face: String = who.brain.mood_face()
	if not face in ["happy", "flat", "sad"]:
		_faults.append("mood_face returned '%s'" % face)
	print("[PLAY] %s mood '%s' (%.2f)" % [who.brain.name, face, who.brain.mood()])


func _check_panel() -> void:
	var p = _root.panel
	if not p.visible:
		_faults.append("panel did not become visible on click")
		return
	var b = p.who.brain
	print("[PLAY] panel shows %s | %s | %s"
		% [b.name, b.personality.describe(), b.morality_label()])
	for k in Brain.STAT_ORDER:
		var v := float(b.stats[k])
		if v < 0.0 or v > 1.0:
			_faults.append("stat %s out of range: %f" % [k, v])
	# The panel must be tall enough to have laid out its buttons, and they must
	# be inside it -- a Bless button drawn off the bottom is not clickable.
	if p._bless.position.y + p._bless.size.y > p.size.y + 1.0:
		_faults.append("Bless button (%s) falls outside the panel (h %.0f)"
			% [str(p._bless.position.round()), p.size.y])
	print("[PLAY] panel %.0f x %.0f, bless at %s"
		% [p.size.x, p.size.y, str(p._bless.position.round())])


func _bless() -> void:
	var who = _root.panel.who
	who.brain.last_action = "chop"
	var before := float(who.brain.favour["chop"])
	var faith_before: float = _root.divinity.faith
	# Through the BUTTON's signal, not by calling Divinity -- the wiring is the
	# thing under test.
	_root.panel.bless_pressed.emit(who)
	var after := float(who.brain.favour["chop"])
	print("[PLAY] bless: faith %.1f -> %.1f, favour[chop] %.2f -> %.2f"
		% [faith_before, _root.divinity.faith, before, after])
	if after <= before:
		_faults.append("the panel's Bless button did not change favour")
	if _root.divinity.faith >= faith_before:
		_faults.append("blessing was free")


func _cards() -> void:
	# Cards arrive on a 10 s timer; the probe does not have 10 s to spare per
	# card, so it asks for them directly and then checks the HUD noticed.
	for i in 3:
		_root.divinity.draw_card()
	var hand: int = _root.divinity.hand.size()
	var buttons: int = _root.hud._cards.size()
	print("[PLAY] hand %d cards, HUD shows %d buttons" % [hand, buttons])
	if hand == 0:
		_faults.append("no cards were drawn")
	if buttons != hand:
		_faults.append("HUD shows %d card buttons for a hand of %d"
			% [buttons, hand])


func _cast_ground_card() -> void:
	# Find a "none" card and play it, so the assertion does not depend on
	# aiming; grove and folk cards are covered by the aiming path in the HUD.
	var idx := -1
	for i in _root.divinity.hand.size():
		if String(_root.divinity.hand[i]["target"]) == "none":
			idx = i
			break
	if idx < 0:
		print("[PLAY] no untargeted card in hand this run -- skipping cast")
		return
	var name := String(_root.divinity.hand[idx]["name"])
	var before: int = _root.village.amount("food")
	var pop_before: int = _root.folk.size()
	var ok: bool = _root.divinity.play(idx)
	print("[PLAY] cast %s -> %s | food %d -> %d | folk %d -> %d"
		% [name, str(ok), before, _root.village.amount("food"),
		   pop_before, _root.folk.size()])
	if not ok:
		_faults.append("casting '%s' failed" % name)
	if _root.hud._cards.size() != _root.divinity.hand.size():
		_faults.append("the HUD did not rebuild the hand after a cast")


func _smite() -> void:
	# Aim at a tree, so there is definitely something to destroy.
	var target = null
	for e in _root.builder.placed_props:
		if String(e["id"]).begins_with("Nature/tree"):
			target = e
			break
	if target == null:
		print("[PLAY] no tree to smite")
		return
	var at: Vector3 = target["node"].position
	var props_before: int = _root.builder.placed_props.size()
	var walk_before: int = _walkable()
	_root.divinity.faith = 200.0
	var ok: bool = _root.divinity.smite(at, 2.5)
	var walk_after := _walkable()
	print("[PLAY] smite: props %d -> %d, walkable %d -> %d"
		% [props_before, _root.builder.placed_props.size(),
		   walk_before, walk_after])
	if not ok:
		_faults.append("smite refused")
	if _root.builder.placed_props.size() >= props_before:
		_faults.append("smite destroyed nothing")
	# Felling a tree must OPEN the tile it stood on. If it does not, the walk
	# grid was not rebuilt and followers will keep pathing around a ghost.
	if walk_after <= walk_before:
		_faults.append("the walk grid did not reopen after destruction "
			+ "(%d -> %d)" % [walk_before, walk_after])
	var remembered := 0
	for f in _root.folk:
		for e in f.brain.memories.entries:
			if String(e["kind"]) == Memories.KIND_LOSS:
				remembered += 1
	print("[PLAY] loss memories held: %d" % remembered)
	if remembered == 0:
		_faults.append("nobody remembered the destruction")


func _buy_island() -> void:
	var before: int = _root.islands.count()
	var cap_before: int = _root.village.pop_cap
	var tiles_before: int = _walkable()
	_root.divinity.faith = 500.0
	var slots: Array = _root.islands.buyable()
	if slots.is_empty():
		_faults.append("nothing was buyable")
		return
	var ok: bool = _root.divinity.buy_island(slots[0])
	print("[PLAY] buy %s -> %s | islands %d -> %d | cap %d -> %d | walkable %d -> %d"
		% [str(slots[0]), str(ok), before, _root.islands.count(),
		   cap_before, _root.village.pop_cap, tiles_before, _walkable()])
	if not ok:
		_faults.append("buying an island failed")


func _check_island() -> void:
	# The new island has to be REACHABLE, or it is scenery with a price tag.
	# One connected walkable region is the whole claim.
	var regions := _regions()
	print("[PLAY] walkable regions after purchase: %s" % str(regions.slice(0, 4)))
	if regions.size() > 1 and regions[1] > 12:
		_faults.append("the archipelago is in %d pieces (%s) -- the bridge "
			% [regions.size(), str(regions.slice(0, 3))]
			+ "did not connect the new island")


## Sound and one-shot FX have to actually FIRE, not merely exist.
##
## The audio driver is Dummy here, so `playing` proves nothing -- what is
## checkable is that every sound was BUILT with real samples and that a burst
## puts particles in flight. A bank of nine silent buffers passes every test
## that only asks whether the file loaded.
func _check_feedback() -> void:
	var sfx = _root.sfx
	if sfx._streams.size() != SFX.BANK.size():
		_faults.append("%d sounds built for a bank of %d"
			% [sfx._streams.size(), SFX.BANK.size()])
	var silent: Array[String] = []
	for name in sfx._streams:
		var w: AudioStreamWAV = sfx._streams[name]
		var peak := 0
		# Every other byte is the high half of a little-endian 16-bit sample;
		# a buffer of zeroes is a sound that plays and cannot be heard.
		for i in range(1, w.data.size(), 2):
			peak = maxi(peak, absi(w.data[i] - (256 if w.data[i] > 127 else 0)))
		if w.data.size() < 512 or peak < 4:
			silent.append("%s(%db peak %d)" % [name, w.data.size(), peak])
	print("[PLAY] sounds: %d built, %d silent" % [sfx._streams.size(),
		silent.size()])
	if not silent.is_empty():
		_faults.append("silent or empty sounds: " + ", ".join(silent))

	# A burst must put particles in flight. amount_ratio, not amount -- the
	# pool sets amount once at build time and never touches it again.
	var fxe = _root.fxe
	var before: int = fxe.active_count()
	fxe.burst("bless", _root.folk[0].position + Vector3(0, 0.6, 0))
	fxe.ring("wrath", _root.folk[0].position, 2.0)
	var after: int = fxe.active_count()
	print("[PLAY] fx emitters active %d -> %d" % [before, after])
	if after <= before:
		_faults.append("firing FX left nothing emitting")
	for kind in FXEvents.KINDS:
		var bucket: Array = fxe._pool[kind]
		if bucket.size() != FXEvents.POOL_PER_KIND:
			_faults.append("pool '%s' has %d emitters" % [kind, bucket.size()])
		if int(bucket[0].amount) != int(FXEvents.KINDS[kind]["count"]):
			_faults.append("pool '%s' amount was changed at play time" % kind)


## The three new clips (item 14) plus walk have to reach the mesh AND be
## selectable by the follower. Checking the GLB alone would miss the substring
## matcher, which is what actually decides which one plays.
func _check_clips() -> void:
	var f = _root.folk[0]
	var want := ["walk", "idle", "pickup", "chop"]
	var missing: Array[String] = []
	for w in want:
		if not f._clips.has(w):
			missing.append(w)
	print("[PLAY] clips resolved: %s" % str(f._clips))
	if not missing.is_empty():
		_faults.append("follower could not resolve clips: " + ", ".join(missing))
	# And the action catalogue must only ever ask for clips that exist.
	for a in Brain.ACTIONS:
		var anim := String(Brain.ACTIONS[a].get("anim", ""))
		if anim != "" and not f._clips.has(anim):
			_faults.append("action '%s' wants clip '%s', which no folk mesh has"
				% [a, anim])


## --- helpers ----------------------------------------------------------------

func _walkable() -> int:
	var n := 0
	for row in _root.grid.rows:
		for col in _root.grid.cols:
			if _root.grid.is_walkable(Vector2i(col, row)):
				n += 1
	return n


func _regions() -> Array:
	var seen := {}
	var sizes: Array = []
	for row in _root.grid.rows:
		for col in _root.grid.cols:
			var start := Vector2i(col, row)
			if not _root.grid.is_walkable(start) or seen.has(start):
				continue
			var n := 0
			var stack: Array[Vector2i] = [start]
			seen[start] = true
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				n += 1
				for d in WalkGrid.NEIGHBOURS:
					var nb: Vector2i = c + d
					if _root.grid.is_walkable(nb) and not seen.has(nb):
						seen[nb] = true
						stack.append(nb)
			sizes.append(n)
	sizes.sort()
	sizes.reverse()
	return sizes


## Stale-frame guard, same rule as the shot tool: two captures from different
## moments cannot be byte-identical, so a repeat means nothing was presented.
func _shoot(label: String) -> void:
	var img := get_root().get_texture().get_image()
	var data := img.get_data()
	if data == _prev:
		_faults.append("capture '%s' is byte-identical to the previous one "
			% label + "-- the frame was never presented")
	_prev = data
	var path := "res://shots/%s.png" % label
	img.save_png(path)
	_shots += 1
	print("[PLAY] %s" % path)


func _report() -> void:
	print("")
	if _faults.is_empty():
		print("[PLAY] all checks ok (%d shots)" % _shots)
		quit(0)
	else:
		for f in _faults:
			printerr("[PLAY]   - " + f)
		printerr("[PLAY] %d FAILURE(S)" % _faults.size())
		quit(1)
