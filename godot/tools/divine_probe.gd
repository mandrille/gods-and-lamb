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
	_check_tiers()
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


## THE FUNNEL IS TRANSPARENT. A touch pays what the hand-rolled loop paid.
func _check_matches_the_old_loop() -> void:
	var at: Vector3 = _somewhere()
	var before := _faith_of_all()
	# What the old code did, verbatim: flat FAITH_PER_TOUCH to everyone inside
	# WITNESS_RANGE, no bands, no falloff.
	var want := 0.0
	for f in _root.folk:
		if is_instance_valid(f) and f.brain != null \
				and f.position.distance_to(at) <= WorldTouch.WITNESS_RANGE:
			want += WorldTouch.FAITH_PER_TOUCH
	var r: Dictionary = _root.divinity.perform(
		DivineAction.touch({"verb": "Green spreads."}, at))
	var paid := _faith_of_all() - before
	print("[DIVINE] the old loop would pay %.2f; the funnel paid %.2f "
		% [want, paid] + "(reported %.2f)" % float(r["faith"]))
	if absf(paid - want) > 0.01:
		_faults.append("the funnel paid %.2f where the loop it replaced paid "
			% paid + "%.2f -- it is not transparent" % want)
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
