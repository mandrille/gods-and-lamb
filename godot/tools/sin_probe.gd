extends SceneTree
## Is there anything to punish, and does punishing it mean something?
##
## Reported from play: "I haven't seen any evil villager and punishing makes no
## sense atm". Both halves were true and the second followed from the first --
## every action in Brain.ACTIONS carried a morality of zero or better, so no
## follower could become anything but good, and `morality_label` had "Wicked"
## and "Selfish" strings the game could never produce.
const ShotWindowRef := preload("res://tools/shot_window.gd")

const SPEED := 10.0
const RUN := 2600
const WANT_FOLK := 18

var _f := 0
var _root: Node = null
var _sins: Dictionary = {}
var _faults: Array[String] = []


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
			printerr("[SIN] FAIL: no scene root")
			quit(1)
			return true
		_root.village.pop_cap = 200
		while _root.folk.size() < WANT_FOLK:
			if not _root.spawn_villager():
				break
		# Lean times. Sin is the SELFISH SHORTCUT to a need, so a village with
		# a full larder and nothing pressing should mostly behave -- which is
		# itself part of the design and is asserted at the end.
		_root.village.stores["food"] = 2
		for f in _root.folk:
			f.finished.connect(func(act):
				if bool(Brain.ACTIONS[act].get("sin", false)):
					_sins[act] = int(_sins.get(act, 0)) + 1)
		Engine.time_scale = SPEED
		print("[SIN] %d villagers, a thin larder, %.0fx"
			% [_root.folk.size(), SPEED])
		return false
	if _f < 20:
		return false
	# Keep it lean, so hunger keeps biting.
	if _f % 90 == 0:
		_root.village.stores["food"] = mini(int(_root.village.stores["food"]), 3)
	if _f < RUN:
		return false

	Engine.time_scale = 1.0
	_report()
	quit(0 if _faults.is_empty() else 1)
	return true


func _report() -> void:
	var total := 0
	for k in _sins:
		total += int(_sins[k])
	print("[SIN] sins committed: %s (%d total)" % [str(_sins), total])
	if total == 0:
		_faults.append("nobody ever did anything wrong, so there is still "
			+ "nothing to punish")

	# Who they turned into.
	var labels := {}
	var worst = null
	for f in _root.folk:
		var l: String = f.brain.morality_label()
		labels[l] = int(labels.get(l, 0)) + 1
		if worst == null or f.brain.morality < worst.brain.morality:
			worst = f
	print("[SIN] village: %s" % str(labels))
	print("[SIN] worst: %s, %s, morality %.2f, kindness %.2f"
		% [worst.brain.name, worst.brain.morality_label(),
		   worst.brain.morality, worst.brain.personality.kindness])
	# The point is a MIXED village, not a village of thieves.
	if labels.has("Wicked") and int(labels["Wicked"]) > _root.folk.size() / 2:
		_faults.append("most of the village turned wicked; sin should be a "
			+ "few people, not the default")

	# Punishing the guilty pays; punishing the innocent does not.
	var d = _root.divinity
	var guilty = null
	var innocent = null
	for f in _root.folk:
		if d._is_guilty(f):
			guilty = f
		elif innocent == null and f.brain.last_action != "":
			innocent = f
	if guilty == null:
		# Manufacture one, so the payout rule is tested even on a lucky run.
		guilty = _root.folk[0]
		guilty.brain.last_sin = "steal"
		guilty.brain.last_sin_at = float(_root.village.now)
		print("[SIN] (no live wrongdoer at the bell; staged one)")

	d.faith = 500.0
	d.judge_cd = 0.0
	var before: float = d.faith
	d.punish(guilty)
	var for_guilt: float = d.faith - before
	print("[SIN] punishing the guilty paid %.1f Faith" % for_guilt)
	if for_guilt <= 0.0:
		_faults.append("punishing a wrongdoer paid nothing")

	if innocent != null:
		d.judge_cd = 0.0
		before = d.faith
		d.punish(innocent)
		var for_innocent: float = d.faith - before
		print("[SIN] punishing the innocent paid %.1f Faith" % for_innocent)
		if for_innocent > 0.0:
			_faults.append("punishing an innocent paid %.1f -- striking "
				% for_innocent + "anyone would then be free Faith")

	# And being caught has to settle the account, or one theft pays forever.
	if _root.divinity._is_guilty(guilty):
		_faults.append("still guilty after being punished -- the same crime "
			+ "could be farmed over and over")

	if _faults.is_empty():
		print("[SIN] ok")
	else:
		for f in _faults:
			printerr("[SIN]   - " + f)
		printerr("[SIN] %d FAILURE(S)" % _faults.size())
