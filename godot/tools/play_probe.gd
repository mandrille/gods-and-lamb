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
		15: _check_targeting()
		16: _check_children()
		17: _check_draft_rules()
		18: _check_boon_effects()
		19: _open_draft()
		20: _shoot("play_5_draft")
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
	var hit = _root.overhead.under(at)
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
	# A timestamp, or this is an UNWITNESSED bless and pays nothing.
	who.brain.last_action_at = float(_root.village.now)
	_root.divinity.judge_cd = 0.0
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
	# Blessing is FREE now and PAYS -- the opposite of what this asserted.
	if _root.divinity.faith <= faith_before:
		_faults.append("a witnessed blessing paid nothing")

	# And an unwitnessed one must pay nothing and break the chain.
	var idle = _root.folk[1]
	idle.brain.last_action = ""
	_root.divinity.judge_cd = 0.0
	var faith_mid: float = _root.divinity.faith
	_root.divinity.bless(idle)
	print("[PLAY] unwitnessed bless: faith %.1f -> %.1f, chain %d"
		% [faith_mid, _root.divinity.faith, _root.divinity.combo_chain])
	if _root.divinity.faith > faith_mid:
		_faults.append("blessing someone idle paid Faith")
	if _root.divinity.combo_chain != 0:
		_faults.append("blessing someone idle did not break the chain")

	# The cooldown must actually bite.
	_root.divinity.judge_cd = 0.0
	_root.divinity.bless(who)
	var blocked: bool = not _root.divinity.bless(who)
	if not blocked:
		_faults.append("judgement has no cooldown -- it can be spammed")


func _cards() -> void:
	# Cards arrive on a 10 s timer; the probe does not have 10 s to spare per
	# card, so it asks for them directly and then checks the HUD noticed.
	for i in 3:
		_root.divinity.draw_card()
	var hand: int = _root.divinity.hand.size()
	# The hand is DRAWN now, so what has to line up is the geometry the HUD
	# hit-tests against -- one rect per card, on screen. A card the player can
	# see but not click, or a rect over a card that is no longer there, is the
	# whole failure mode of hand-rolled hit testing.
	# ONE RECT PER STACK, not per card: identical cards collapse into one card
	# on screen and are played together. The invariant this protects is
	# unchanged -- what the player sees and what they can click must be the
	# same list -- only the list is stacks now.
	var rects: Array = _root.hud._hand_rects()
	var stacks: int = _root.divinity.stacks().size()
	print("[PLAY] hand %d cards in %d stacks, HUD lays out %d rects"
		% [hand, stacks, rects.size()])
	if hand == 0:
		_faults.append("no cards were drawn")
	if rects.size() != stacks:
		_faults.append("HUD laid out %d card rects for %d stacks"
			% [rects.size(), stacks])
	var vp: Vector2 = Vector2(_root.get_viewport().get_visible_rect().size)
	for i in rects.size():
		var r: Rect2 = rects[i]
		if r.position.x < 0.0 or r.end.x > vp.x or r.end.y > vp.y:
			_faults.append("card %d is off screen at %s" % [i, str(r)])


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
	if _root.hud._hand_rects().size() != _root.divinity.stacks().size():
		_faults.append("the HUD did not relayout the hand after a cast")


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


## Can you actually hit a villager?
##
## The complaint was that clicking them is "super hard", so this samples the
## whole FIGURE, not just the head: a point-to-head test leaves a hole over the
## body, which is exactly where people aim. It also checks that the target does
## not swallow the entire screen, because a fix that makes everything hit the
## nearest villager is not a fix.
func _check_targeting() -> void:
	var who = _root.folk[0]
	var cam = _root.rig.cam
	var feet: Vector2 = cam.unproject_position(who.position)
	var head: Vector2 = cam.unproject_position(
		who.position + Vector3(0, Overhead.HEAD_HEIGHT, 0))
	var tall: float = feet.distance_to(head)
	var hits := 0
	var tried := 0
	for i in 5:
		# Along the body from feet to head, and a little to each side.
		var along: Vector2 = feet.lerp(head, float(i) / 4.0)
		for dx in [-10.0, 0.0, 10.0]:
			tried += 1
			if _root.overhead.under(along + Vector2(dx, 0)) == who:
				hits += 1
	print("[PLAY] villager is %.0f px tall; %d of %d body points hit"
		% [tall, hits, tried])
	# A CLAIM ABOUT PIXELS, so it needs a real viewport to project into. With
	# no display the window is a nominal size the camera never framed for, the
	# fifteen sample points land off the body, and the probe would report a
	# picking bug that only exists on a machine with the screen locked.
	if not ShotWindowRef.can_shoot():
		print("[PLAY] no display: the picking check was skipped")
	elif hits < tried:
		_faults.append("only %d of %d points ON the villager selected them"
			% [hits, tried])
	# And a point clear of EVERYONE must select nobody. "420 px right of this
	# villager" stopped meaning that when the plot shrank: the camera sits
	# closer and the founders stand together, so the point landed on the other
	# one. Find a point clear of every villager by the picker's own geometry.
	var far: Vector2 = _clear_point(feet)
	if far.x > -99999.0 and _root.overhead.under(far) != null:
		_faults.append("a point clear of every villager still selected a villager -- the "
			+ "target is too big to be a target")


## Children are born small and grow up.
func _check_children() -> void:
	var before: int = _root.folk.size()
	var a = _root.folk[0]
	var b = _root.folk[1]
	# Put both in a state to parent, then ask the host directly -- the social
	# layer's dice are not what is under test here.
	for who in [a, b]:
		for k in Brain.STAT_ORDER:
			who.brain.stats[k] = 1.0
		who.brain.adult = true
		who.brain.age = Brain.ADULT_AT
		if not who.brain.can_parent():
			_faults.append("%s is fed, well and content but cannot parent"
				% who.brain.name)
	_root.village.pop_cap = 99
	_root._on_child_wanted(a, b)
	if _root.folk.size() != before + 1:
		_faults.append("no child was born (%d -> %d)"
			% [before, _root.folk.size()])
		return
	var kid = _root.folk[_root.folk.size() - 1]
	kid._apply_growth()
	var small: float = kid._shown_scale
	print("[PLAY] child %s born at scale %.2f, adult=%s"
		% [kid.brain.name, small, str(kid.brain.adult)])
	if not kid.is_child():
		_faults.append("the newborn is not a child")
	if small > 0.8:
		_faults.append("the newborn is %.2f scale -- not visibly a child" % small)
	# Grow them up and check the body follows.
	kid.brain.age = Brain.ADULT_AT
	kid.brain.adult = true
	kid._apply_growth()
	print("[PLAY] grown to scale %.2f" % kid._shown_scale)
	if kid._shown_scale < 0.98:
		_faults.append("a grown child stayed at %.2f scale" % kid._shown_scale)
	# And a child must not be sent to chop trees.
	kid.brain.adult = false
	var picks := {}
	for i in 60:
		picks[kid.brain.choose_action()] = true
	for banned in ["chop", "quarry", "build_hut", "build_shrine"]:
		if picks.has(banned):
			_faults.append("a child chose '%s'" % banned)
	print("[PLAY] child chooses among: %s" % str(picks.keys()))


## The draft must always be a real CHOICE.
##
## Three cards where two are the same thing, or where everything on offer is
## already maxed, is a moment that looks like a decision and is not. Two
## hundred offers, because these are rules about a random process and one
## sample proves nothing.
func _check_draft_rules() -> void:
	var b = _root.divinity.boons
	var bad_size := 0
	var dupes := 0
	var maxed := 0
	var no_new := 0
	var early_r3 := 0
	for i in 200:
		# Random state each time, so the rules are tested against a village
		# part-way through rather than only a fresh one.
		b.held.clear()
		for id in Boons.CATALOGUE:
			if _root.divinity.rng.randf() < 0.45:
				b.held[id] = _root.divinity.rng.randi_range(1, 3)
		b.rank3_open = i % 2 == 0
		var offer: Array = b.offer()
		if offer.is_empty():
			continue
		if offer.size() != 3 and offer.size() < 3:
			# Fewer than three is only allowed when the pool is genuinely
			# smaller than three.
			# Count the pool the way offer() does -- rank-3 options are
			# withheld until the third Age, so "not maxed" overcounts it and
			# this flagged a correct two-card offer as a fault.
			var pool := 0
			for id in Boons.CATALOGUE:
				var idn := String(id)
				if b.maxed(idn):
					continue
				if b.rank(idn) >= 2 and not b.rank3_open:
					continue
				pool += 1
			if pool >= 3:
				bad_size += 1
		var seen := {}
		var any_new := false
		var pool_has_new := false
		for id in Boons.CATALOGUE:
			if b.rank(String(id)) == 0 and not b.maxed(String(id)):
				pool_has_new = true
		for o in offer:
			var id := String(o["id"])
			if seen.has(id):
				dupes += 1
			seen[id] = true
			if b.maxed(id):
				maxed += 1
			if b.rank(id) == 0:
				any_new = true
			if int(o["rank"]) >= 3 and not b.rank3_open:
				early_r3 += 1
		if pool_has_new and not any_new:
			no_new += 1
	b.held.clear()
	b.rank3_open = false
	print("[PLAY] 200 offers: %d wrong size, %d duplicated, %d already maxed, "
		% [bad_size, dupes, maxed]
		+ "%d without anything new, %d rank-3 too early"
		% [no_new, early_r3])
	if bad_size > 0:
		_faults.append("%d offers had the wrong number of cards" % bad_size)
	if dupes > 0:
		_faults.append("%d offers repeated a boon" % dupes)
	if maxed > 0:
		_faults.append("%d offers included a maxed boon" % maxed)
	if no_new > 0:
		_faults.append("%d offers were all upgrades while new boons existed"
			% no_new)
	if early_r3 > 0:
		_faults.append("%d offers showed rank 3 before it was unlocked"
			% early_r3)


## A boon must change the thing its own sentence names.
func _check_boon_effects() -> void:
	var d = _root.divinity
	var b = d.boons
	b.held.clear()
	var f = _root.folk[0]

	var speed_before: float = f.speed
	var scale_before: float = f._walk_scale
	b.take("swift_feet")
	_root.apply_boons()
	print("[PLAY] Swift Feet: speed %.3f -> %.3f, clip scale %.3f -> %.3f"
		% [speed_before, f.speed, scale_before, f._walk_scale])
	if f.speed <= speed_before:
		_faults.append("Swift Feet did not change walk speed")
	# BOTH, always: `_play` feeds `_walk_scale` to the clip's speed_scale, so a
	# boon that writes only `speed` makes the whole village skate.
	if f._walk_scale <= scale_before:
		_faults.append("Swift Feet moved speed but not the animation scale -- "
			+ "they will skate")

	# Full Hands must raise a yield AND leave the shared const table alone.
	var before_table: int = int(Brain.ACTIONS["chop"]["gives"]["wood"])
	b.take("full_hands")
	var bonus: int = b.yield_bonus()
	var after_table: int = int(Brain.ACTIONS["chop"]["gives"]["wood"])
	print("[PLAY] Full Hands: bonus +%d, ACTIONS table still %d (was %d)"
		% [bonus, after_table, before_table])
	if bonus <= 0:
		_faults.append("Full Hands granted no yield bonus")
	if after_table != before_table:
		_faults.append("Full Hands MUTATED Brain.ACTIONS -- that const is "
			+ "shared by every mind in the game")

	var zeal_before: float = b.zeal()
	b.take("zeal")
	if b.zeal() <= zeal_before:
		_faults.append("Zeal did not raise the passive multiplier")
	b.held.clear()
	_root.apply_boons()


func _open_draft() -> void:
	var d = _root.divinity
	# Commune has two preconditions besides the price, and the probe met
	# neither: the altar opens at Age I, and a draft already on the table
	# blocks a second one. Both are deliberate, so the probe establishes them
	# rather than the game relaxing them.
	if d.age < 1:
		d.age = 1
	d.pending_draft = []
	d.faith = 500.0
	if not d.commune():
		_faults.append("Commune refused at Age %d with 500 Faith and no "
			% d.age + "draft pending")
		return
	if not _root.draft.is_open():
		_faults.append("the draft did not open")
		return
	print("[PLAY] draft open with %d options: %s"
		% [_root.draft._options.size(),
		   str(_root.draft._options.map(func(o): return String(o["name"])))])


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
	# The byte-comparison below asserts the frame was actually PRESENTED, which
	# is a question about a swapchain. Without a display there is nothing to
	# present and nothing to compare, so the picture is skipped rather than
	# reported as a game that failed to draw.
	if not ShotWindowRef.can_shoot():
		print("[PLAY] no display: %s not photographed" % label)
		_shots += 1
		return
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


## A screen point outside every villager's pick capsule with room to spare, or
## (-1e5, -1e5) when the view is too crowded to have one.
func _clear_point(near: Vector2) -> Vector2:
	var cam: Camera3D = _root.rig.cam
	for off in [Vector2(420, 0), Vector2(-420, 0), Vector2(0, 420),
				Vector2(0, -420), Vector2(620, 300), Vector2(-620, -300)]:
		var p: Vector2 = near + off
		var clear := true
		for f in _root.folk:
			if not is_instance_valid(f):
				continue
			var pf: Vector2 = cam.unproject_position(f.position)
			var ph: Vector2 = cam.unproject_position(
				f.position + Vector3(0, Overhead.HEAD_HEIGHT, 0))
			var radius: float = maxf(Overhead.PICK_RADIUS,
									 maxf(ph.distance_to(pf), 8.0) * 0.62)
			if _root.overhead._to_segment(p, pf, ph) < radius * 1.5:
				clear = false
				break
		if clear:
			return p
	print("[PLAY] no point on screen is clear of every villager; skipped")
	return Vector2(-100000.0, -100000.0)
