extends SceneTree
## Does the simulation actually simulate?
##
## Every claim the gameplay slice makes, checked against a running village
## rather than against the code that is supposed to implement it. The order
## matters: each check is worthless if the one above it failed, so a failure
## reports and keeps going rather than aborting, and the summary counts.
##
## Runs the real scene, not a mock. A mock village would let every one of these
## pass while the actual game did nothing -- the interesting failures here are
## wiring failures (a brain nobody ticks, a store nobody spends), and a mock is
## precisely the thing that cannot catch those.
const ShotWindowRef := preload("res://tools/shot_window.gd")

const RUN_FRAMES := 2400          ## ~40 s of village life at 60 fps
const SPEED := 8.0                ## simulation multiplier, so 40 s buys hours

var _f := 0
var _root: Node = null
var _faults: Array[String] = []
var _notes: Array[String] = []

## Observations accumulated across the run.
var _actions_started := {}
var _actions_done := {}
var _chats := 0
var _thoughts := {}
var _stat_lo := {}
var _stat_hi := {}
var _store_seen := {}


func _initialize() -> void:
	ShotWindowRef.park()
	get_root().add_child(
		(load("res://scenes/vale.tscn") as PackedScene).instantiate())


func _process(delta: float) -> bool:
	_f += 1
	if _f == 15:
		for n in get_root().get_children():
			if n.get("village") != null:
				_root = n
		if _root == null:
			printerr("[SIM] FAIL: no scene root with a village")
			quit(1)
			return true
		# Time compression. The needs are tuned for an idle game -- minutes per
		# bar -- so a real-time probe would watch nothing happen and pass.
		Engine.time_scale = SPEED
		for f in _root.folk:
			f.arrived_at.connect(_on_started.bind(f))
			f.finished.connect(_on_done.bind(f))
		print("[SIM] watching %d followers at %.0fx for %d frames"
			% [_root.folk.size(), SPEED, RUN_FRAMES])
		_snapshot_names()
	if _f < 15:
		return false

	_observe()
	if _f < RUN_FRAMES:
		return false

	Engine.time_scale = 1.0
	_report()
	quit(0 if _faults.is_empty() else 1)
	return true


func _snapshot_names() -> void:
	var names := {}
	for f in _root.folk:
		names[f.brain.name] = true
		print("[SIM]   %s" % f.brain.describe())
	# Distinct names, because the panel and every memory refer to people BY
	# name -- two Brams means one of them inherits the other's grudges.
	if names.size() != _root.folk.size():
		_faults.append("only %d distinct names for %d followers"
			% [names.size(), _root.folk.size()])


func _on_started(act: String, _f2) -> void:
	_actions_started[act] = int(_actions_started.get(act, 0)) + 1


func _on_done(act: String, _f2) -> void:
	_actions_done[act] = int(_actions_done.get(act, 0)) + 1


func _observe() -> void:
	for f in _root.folk:
		if not is_instance_valid(f) or f.brain == null:
			continue
		for k in Brain.STAT_ORDER:
			var v := float(f.brain.stats[k])
			_stat_lo[k] = minf(float(_stat_lo.get(k, 1.0)), v)
			_stat_hi[k] = maxf(float(_stat_hi.get(k, 0.0)), v)
		if f.brain.thought != "":
			_thoughts[f.brain.thought] = true
	_chats = maxi(_chats, _root.social.active_count())
	for res in ["food", "wood"]:
		var lo: float = float(_store_seen.get(res + "_lo", 9999))
		var hi: float = float(_store_seen.get(res + "_hi", -1))
		_store_seen[res + "_lo"] = minf(lo, _root.village.amount(res))
		_store_seen[res + "_hi"] = maxf(hi, _root.village.amount(res))


func _report() -> void:
	print("")
	print("[SIM] === after %d frames at %.0fx ===" % [RUN_FRAMES, SPEED])

	# 1. Needs actually move, in BOTH directions. A stat that only ever falls
	#    means nothing refills it; one that never falls means the drain is not
	#    wired. Either way the bar is decoration.
	for k in Brain.STAT_ORDER:
		var lo := float(_stat_lo.get(k, 1.0))
		var hi := float(_stat_hi.get(k, 0.0))
		print("[SIM] stat %-8s ranged %.2f .. %.2f" % [k, lo, hi])
		if hi - lo < 0.02:
			_faults.append("stat '%s' never moved (%.3f..%.3f)" % [k, lo, hi])

	# 2. Work happens and COMPLETES. Started-but-never-finished is the classic
	#    state-machine hang, and it looks identical to a busy village.
	print("[SIM] actions started: %s" % str(_actions_started))
	print("[SIM] actions finished: %s" % str(_actions_done))
	if _actions_started.is_empty():
		_faults.append("no follower ever began an action")
	for a in _actions_started:
		if int(_actions_done.get(a, 0)) == 0:
			_faults.append("'%s' started %d times and finished none"
				% [a, int(_actions_started[a])])
	var kinds: int = _actions_done.size()
	if kinds < 2:
		_notes.append("only %d kind(s) of action completed; the village may be "
			% kinds + "too comfortable to work, or sources are missing")

	# EVERY need with an action attached must eventually be answered. This is
	# the check that catches a need which is unreachable for a reason nothing
	# reports: a source building missing from the island, a `beside()` that
	# cannot see past a footprint, or -- the one that actually happened -- a
	# branch above it in choose_action() that pre-empts it forever. All three
	# look identical from outside: a bar that sits at zero while the villager
	# cheerfully does something else.
	var never: Array[String] = []
	for a in Brain.ACTIONS:
		if String(Brain.ACTIONS[a].get("need", "")) == "":
			continue
		if int(_actions_done.get(a, 0)) == 0:
			never.append(String(a))
	if not never.is_empty():
		_notes.append("need-actions never performed: %s -- check the island "
			% ", ".join(never) + "has a source, and that nothing outranks them "
			+ "in choose_action()")

	# 3. The economy moves. Stores that never change mean gives/takes are not
	#    reaching the ledger.
	for res in ["food", "wood"]:
		print("[SIM] store %-5s ranged %d .. %d" % [res,
			int(_store_seen.get(res + "_lo", 0)),
			int(_store_seen.get(res + "_hi", 0))])
		if int(_store_seen.get(res + "_hi", 0)) \
				== int(_store_seen.get(res + "_lo", 0)):
			_notes.append("store '%s' never changed" % res)

	# 4. Thoughts are generated and VARIED. One thought repeated is a generator
	#    that is really a constant.
	print("[SIM] distinct thoughts: %d" % _thoughts.size())
	if _thoughts.size() == 0:
		_faults.append("no follower ever had a thought")
	elif _thoughts.size() < 4:
		_faults.append("only %d distinct thought(s) -- the generator is stuck"
			% _thoughts.size())

	# 5. Conversations happen and leave a trace in memory.
	var with_bonds := 0
	var social_mem := 0
	for f in _root.folk:
		if f.brain.memories.bonds().size() > 0:
			with_bonds += 1
		for e in f.brain.memories.entries:
			if String(e["kind"]) == Memories.KIND_SOCIAL:
				social_mem += 1
	print("[SIM] peak simultaneous chats: %d" % _chats)
	print("[SIM] followers holding an opinion of someone: %d of %d"
		% [with_bonds, _root.folk.size()])
	print("[SIM] social memories held: %d" % social_mem)
	if social_mem == 0:
		_faults.append("nobody remembers talking to anybody -- the social "
			+ "layer is not reaching memory")

	# 6. Blessing REWEIGHTS, and punishment reweights the other way. This is
	#    the god's entire influence on the village, so it is checked directly
	#    rather than inferred from behaviour drifting.
	_check_favour()

	print("")
	for n in _notes:
		print("[SIM] note: " + n)
	if _faults.is_empty():
		print("[SIM] all checks ok")
	else:
		for f in _faults:
			printerr("[SIM]   - " + f)
		printerr("[SIM] %d FAILURE(S)" % _faults.size())


func _check_favour() -> void:
	var f = _root.folk[0]
	var b = f.brain
	b.last_action = "chop"
	var before := float(b.favour["chop"])
	var faith_before := float(b.stats["faith"])
	var mem_before: int = b.memories.entries.size()
	b.bless(1.0)
	var after := float(b.favour["chop"])
	print("[SIM] bless: favour[chop] %.3f -> %.3f, faith %.2f -> %.2f, "
		% [before, after, faith_before, float(b.stats["faith"])]
		+ "memories %d -> %d" % [mem_before, b.memories.entries.size()])
	if after <= before:
		_faults.append("blessing did not raise favour for the blessed action")
	if b.memories.entries.size() <= mem_before:
		_faults.append("blessing left no memory")
	if b.memories.divine_standing() <= 0.0:
		_faults.append("blessing did not improve divine standing")

	var mid := float(b.favour["chop"])
	b.punish(1.0)
	var punished := float(b.favour["chop"])
	print("[SIM] punish: favour[chop] %.3f -> %.3f, standing now %.2f"
		% [mid, punished, b.memories.divine_standing()])
	if punished >= mid:
		_faults.append("punishment did not lower favour")

	# And the reweighting must actually change what gets chosen. A favour
	# dictionary nothing reads is the same as no favour system at all.
	var g = _root.folk[1].brain
	for a in g.favour:
		g.favour[a] = 0.01
	g.favour["chop"] = 6.0
	for k in Brain.STAT_ORDER:
		g.stats[k] = 1.0            # nothing urgent, so work is the only driver
	var chops := 0
	for i in 200:
		if g.choose_action() == "chop":
			chops += 1
	print("[SIM] with favour[chop]=6 and all else 0.01: chose chop %d/200" % chops)
	if chops < 150:
		_faults.append("favour barely steers choice (%d/200 with a 600x edge)"
			% chops)
