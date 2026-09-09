extends SceneTree
## One place pays for what the god did.
##
## Faith was credited from five sites, each with its own copy of "scan folk,
## test a distance, pay whoever is near", and each threw the witness list away.
## This probe is about the seam that replaced them, and the things worth
## asserting are the ones a refactor gets wrong quietly:
##
##   - the same people are paid, and the same amount -- a funnel that changes
##     the economy while claiming to be transparent is the worst outcome, since
##     it looks like a tuning decision nobody made
##   - the witness list SURVIVES, because the entire reason for the seam is
##     that something downstream needs to know who saw it
##   - a tier crossing is reported, which no caller in the game had ever
##     captured despite `gain_faith` returning it
##   - relief is paid to EVERYONE, unbanded, however far from the fire
const ShotWindowRef := preload("res://tools/shot_window.gd")
const TestGroundRef := preload("res://tools/test_ground.gd")

var _f := 0
var _root: Node = null
var _faults: Array[String] = []


func _initialize() -> void:
	ShotWindowRef.park()
	get_root().add_child(
		(load("res://scenes/vale.tscn") as PackedScene).instantiate())


func _process(_d: float) -> bool:
	_f += 1
	if _f < 30:
		return false
	for n in get_root().get_children():
		if n.get("divinity") != null:
			_root = n
	if _root == null:
		printerr("[DIVINE] FAIL: no scene root")
		quit(1)
		return true
	TestGroundRef.green(_root)

	# ORDER MATTERS HERE, and the reason is worth stating: `_check_tiers`
	# deliberately saturates a villager to Devoted, and at the cap `gain_faith`
	# zeroes `faith_xp` -- so anything measuring a payout AFTER it silently
	# loses that villager's share and reads as a payout that was thinned.
	# Everything that measures money runs first.
	_check_range()
	_check_matches_the_old_loop()
	_check_relief_reaches_everyone()
	_check_signal()
	_check_bands()
	_check_novelty()
	_check_novelty_spares_people()
	_check_tiers()
	_check_aggregation()
	_check_they_notice()
	_report()
	quit(0 if _faults.is_empty() else 1)
	return true


## EXACTLY the villagers in range, and nobody else.
func _check_range() -> void:
	var who = _anyone()
	if who == null:
		_faults.append("nobody to witness anything")
		return
	var a := DivineAction.make("touch", who.position, 1.0,
							   WorldTouch.WITNESS_RANGE)
	var want := 0
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null \
				and f.position.distance_to(a.at) <= a.radius:
			want += 1
	var r: Dictionary = _root.divinity.perform(a)
	print("[DIVINE] %d villagers within %.1f m; the act reported %d"
		% [want, a.radius, int(r["seen"])])
	if int(r["seen"]) != want:
		_faults.append("counted %d witnesses where %d were in range"
			% [int(r["seen"]), want])
	# The list itself, not just the count -- everything downstream of this seam
	# exists to use it.
	if (r["hits"] as Array).size() != want:
		_faults.append("the witness list has %d entries but the count says %d"
			% [(r["hits"] as Array).size(), want])
	for h in (r["hits"] as Array):
		if (h[0] as Node).position.distance_to(a.at) > a.radius + 0.01:
			_faults.append("a villager outside the radius is in the list")


## NOTHING IS LOST OR PAID TWICE between the act and the villagers.
##
## This began life as a transparency check against the hand-rolled loop the
## funnel replaced, and it stopped meaning that the day bands came on: the
## villager it measures is standing on the spot, so it now asserts the narrower
## thing that a witness at band 1.0 on a fresh act collects the full rate, and
## that the amount the act REPORTS is the amount the village actually gained.
## Both are still worth having -- a funnel that reports one number and pays
## another is the worst kind of wrong -- but the comment should not claim more
## than the assertion does.
func _check_matches_the_old_loop() -> void:
	var at: Vector3 = _somewhere()
	_root.divinity.witness.forget()
	var before := _faith_of_all()
	var want := 0.0
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null \
				and f.position.distance_to(at) <= WorldTouch.WITNESS_RANGE:
			want += WorldTouch.FAITH_PER_TOUCH
	var r: Dictionary = _root.divinity.perform(
		DivineAction.touch({"verb": "Green spreads."}, at))
	var paid := _faith_of_all() - before
	print("[DIVINE] a witness standing in it collects %.2f of a possible %.2f "
		% [paid, want] + "(the act reported %.2f)" % float(r["faith"]))
	if absf(paid - want) > 0.01:
		_faults.append("a witness at full band collected %.2f where the rate "
			% paid + "is %.2f" % want)
	if absf(float(r["faith"]) - paid) > 0.01:
		_faults.append("the act reported %.2f paid but the village gained %.2f"
			% [float(r["faith"]), paid])


## A TIER CROSSING IS REPORTED. `gain_faith` has always returned the number of
## tiers crossed and every caller in the game discarded it, so a villager
## reaching Believer -- rare, and the only progress that cannot be lost -- has
## never produced any feedback at all.
func _check_tiers() -> void:
	var who = _anyone()
	if who == null:
		return
	var a := DivineAction.make("touch", who.position, 999.0, 2.0)
	var tier_before: String = who.brain.faith_tier()
	var r: Dictionary = _root.divinity.perform(a)
	print("[DIVINE] a huge act moved %s from %s to %s, reporting %d tier(s)"
		% [who.brain.name, tier_before, who.brain.faith_tier(),
		   int(r["tiers"])])
	if int(r["tiers"]) < 1:
		_faults.append("a villager crossed a tier and the act reported none")


## RELIEF REACHES EVERYONE. Banding it by distance from the fire would pay the
## people furthest from danger the least, which is backwards.
func _check_relief_reaches_everyone() -> void:
	var living := 0
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null:
			living += 1
	var before := _faith_of_all()
	var r: Dictionary = _root.divinity.perform(DivineAction.relief(4.0))
	var paid := _faith_of_all() - before
	print("[DIVINE] relief reached %d of %d villagers, paying %.1f"
		% [int(r["seen"]), living, paid])
	if int(r["seen"]) != living:
		_faults.append("relief reached %d of %d -- somebody was left out of a "
			% [int(r["seen"]), living] + "village-wide thanks")
	if absf(paid - 4.0 * float(living)) > 0.01:
		_faults.append("relief paid %.2f, not %.2f -- it was thinned by "
			% [paid, 4.0 * float(living)] + "distance, which is backwards")


## STANDING IN IT IS WORTH MORE THAN WATCHING FROM THE TREELINE.
func _check_bands() -> void:
	var a := DivineAction.make("touch", Vector3.ZERO, 1.0, 10.0)
	a.bands = true
	var near := Witness._band(0.1)
	var mid := Witness._band(0.4)
	var far := Witness._band(0.9)
	print("[DIVINE] bands: near %.2f, middle %.2f, far %.2f" % [near, mid, far])
	if not (near > mid and mid > far):
		_faults.append("the bands do not fall off with distance: %.2f/%.2f/%.2f"
			% [near, mid, far])
	if far <= 0.0:
		_faults.append("the far band pays nothing, so a witness who saw it "
			+ "from across the meadow is not a witness at all")


## THE TWENTIETH APPLE IS NOT A MIRACLE -- and the fortieth is not worthless.
func _check_novelty() -> void:
	var w: Witness = _root.divinity.witness
	w.forget()
	var now := float(_root.village.now)
	var first := w.novelty("touch:G", now)
	var seq: Array = []
	for i in 12:
		w.spend("touch:G", now)
		seq.append(w.novelty("touch:G", now))
	print("[DIVINE] novelty over twelve touches: %.2f -> %s"
		% [first, ", ".join(seq.slice(0, 6).map(func(x): return "%.2f" % x))])
	if not is_equal_approx(first, 1.0):
		_faults.append("an untouched act did not start fresh: %.2f" % first)
	for i in range(1, seq.size()):
		if float(seq[i]) > float(seq[i - 1]) + 0.0001:
			_faults.append("novelty went UP on use %d" % i)
			break
	var floor_v: float = float(seq[-1])
	if absf(floor_v - Witness.NOVELTY_FLOOR) > 0.01:
		_faults.append("repeated use settled at %.2f, not the %.2f floor -- "
			% [floor_v, Witness.NOVELTY_FLOOR] + "either it decays to nothing "
			+ "or it never stops paying")

	# AND IT COMES BACK. A decay with no recovery is a permanent tax on a verb
	# the player is meant to keep using.
	var later := w.novelty("touch:G", now + Witness.NOVELTY_HALF)
	var much_later := w.novelty("touch:G", now + Witness.NOVELTY_HALF * 4.0)
	print("[DIVINE] recovery: %.2f now, %.2f after %.0fs, %.2f after %.0fs"
		% [floor_v, later, Witness.NOVELTY_HALF, much_later,
		   Witness.NOVELTY_HALF * 4.0])
	if later <= floor_v:
		_faults.append("novelty never recovers, so the ground is spent forever")
	if much_later < 0.85:
		_faults.append("after four half-lives novelty is still %.2f -- it "
			% much_later + "recovers too slowly to feel fresh again")


## IT DOES NOT TOUCH PEOPLE. Blessing and answering a disaster carry no key, so
## they never get stale: `WITNESS_FAITH` was measured down deliberately and a
## player blessing on every cooldown is the INTENDED loop, not spam.
func _check_novelty_spares_people() -> void:
	var w: Witness = _root.divinity.witness
	for i in 20:
		w.spend("touch:G", float(_root.village.now))
	var bless_fresh := w.novelty("", float(_root.village.now))
	print("[DIVINE] after twenty greenings, a keyless act is still %.2f"
		% bless_fresh)
	if not is_equal_approx(bless_fresh, 1.0):
		_faults.append("hammering the ground made blessing less impressive")
	# And one row does not drag another down with it.
	var other := w.novelty("touch:Nature/tree", float(_root.village.now))
	if not is_equal_approx(other, 1.0):
		_faults.append("greening a hillside made fruiting a tree stale -- the "
			+ "novelty key is not specific enough")
	w.forget()


## THE RESULT GOES OUT. Everything the feedback layer will do hangs off this
## one signal, so an act that credits correctly and announces nothing is a
## silent game.
func _check_signal() -> void:
	var seen: Array = []
	_root.divinity.witnessed.connect(func(res): seen.append(res))
	_root.divinity.perform(DivineAction.make("touch", _somewhere(), 1.0, 5.0))
	print("[DIVINE] one act emitted %d result(s)" % seen.size())
	if seen.size() != 1:
		_faults.append("one act emitted %d results" % seen.size())
	elif not (seen[0] as Dictionary).has("hits"):
		_faults.append("the result carries no witness list, so nothing "
			+ "downstream can know who saw it")


## FIVE WITNESSES ARE ONE MESSAGE.
##
## The naive use of a witness list is a floating number over each head, and that
## tells the player less than one line while covering the village up. This is
## the assertion that the aggregation layer is actually doing its job -- and it
## has to count LINES, because a version that batches the faith and still pushes
## five notices has fixed nothing.
func _check_aggregation() -> void:
	var c = _root.chorus
	if c == null:
		_faults.append("there is no aggregation layer at all")
		return
	var lines := 0
	_root.divinity.notice.connect(func(_t): lines += 1)
	var said: Array = []
	# Count what reaches the notice stack rather than the signal, because that
	# is what the player actually sees.
	var before: int = _root.hud._notices.size()
	var at: Vector3 = _somewhere()
	for i in 5:
		var a := DivineAction.make("touch", at, 0.4, 8.0)
		a.verb = "Green spreads."
		_root.divinity.perform(a)
	# Nothing has flushed yet: the window is still open.
	var mid: int = _root.hud._notices.size() - before
	_root.village.now = float(_root.village.now) + WorldTouch.COOLDOWN * 2.0
	c._flush()
	var after: int = _root.hud._notices.size() - before
	print("[DIVINE] five acts in one window: %d notice line(s) mid-window, "
		% mid + "%d after the flush" % after)
	if after > 1:
		_faults.append("five acts in one window produced %d notice lines -- "
			% after + "the batch is not batching")
	if mid > 1:
		_faults.append("the batch emitted %d lines before its window closed"
			% mid)


## THEY VISIBLY NOTICE. The spec's acceptance test is that a first-time player
## can SEE the village react without reading a number, and a turn is the only
## thing that reads at the size a villager occupies on screen.
func _check_they_notice() -> void:
	var who = _anyone()
	if who == null:
		return
	# Somewhere they are not standing, or "turned to face it" is meaningless.
	var at: Vector3 = who.position + Vector3(3.0, 0.0, 0.0)
	who.state = who.State.IDLE
	who._notice_left = 0.0
	var facing_before: float = who.rotation.y
	var a := DivineAction.make("touch", at, 0.4, 8.0)
	# Certain, so the devotion roll cannot make this flaky.
	who.brain.personality.devotion = 1.0
	_root._villagers_react(_root.divinity.perform(a))
	var turned: bool = not is_equal_approx(who.rotation.y, facing_before)
	var marked: bool = _root.overhead._looking.has(who.get_instance_id())
	print("[DIVINE] after an act 3 m away: turned %s, marked %s, state %d"
		% [turned, marked, who.state])
	if not turned:
		_faults.append("nobody turned toward the act -- the village noticing "
			+ "is the whole acceptance test and it is invisible")
	if not marked:
		_faults.append("no marker went up over the villager who noticed")
	# AND THEY GESTURE. The clip is a cycle back to rest so it can go through
	# the normal player, but it still has to be the clip that is actually
	# playing -- `_play` falls back to idle for a name it does not have, so a
	# GLB exported before the clip existed would silently look like nothing.
	var clip: String = who._anim.current_animation
	print("[DIVINE] the villager who noticed is playing '%s'" % clip)
	if not who._clips.has("awe"):
		_faults.append("the folk GLB has no 'awe' clip -- the library was not "
			+ "rebuilt after the rig gained one")
	elif clip != String(who._clips["awe"]):
		_faults.append("expected the awe clip and got '%s'" % clip)
	# AND THEY GO BACK TO WORK. A reaction that never ends is a statue.
	who._notice_left = 0.01
	who._process(0.05)
	if who.state == who.State.TALK:
		_faults.append("the villager never resumed -- a reaction that does not "
			+ "end leaves them standing there forever")


func _anyone():
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null:
			return f
	return null


func _somewhere() -> Vector3:
	var who = _anyone()
	return who.position if who != null else Vector3.ZERO


func _faith_of_all() -> float:
	var total := 0.0
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null:
			total += float(f.brain.faith_xp) \
				+ float(f.brain.faith_level) * 10000.0
	return total


func _report() -> void:
	if _faults.is_empty():
		print("[DIVINE] ok")
		return
	print("[DIVINE] %d FAILURE(S)" % _faults.size())
	for f in _faults:
		print("  - %s" % f)
