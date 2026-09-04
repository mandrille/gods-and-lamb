extends SceneTree
## Can time away ever beat time played?
##
## Pure and headless: Away.roll takes the clock as an argument, so a year of
## absence sweeps in milliseconds with no window, no swapchain and no GLB
## library. That was the whole reason for injecting the clock.
##
## The assertion this file exists for is the inequality at the bottom of it:
## faith(t) < income_per_s * t at EVERY horizon. An idle game whose offline
## rate beats its online rate has taught the player to close the tab.

const HOURS := 3600.0

var _faults: Array[String] = []


func _initialize() -> void:
	var save := _save()
	var rate: float = float(save["divinity"]["income_per_s"])

	print("%10s %10s %10s %8s  %s"
		% ["away", "faith", "if played", "ratio", "lines"])
	var last := -1.0
	for t in [0.0, 60.0, 119.0, 121.0, 600.0, HOURS, 4.0 * HOURS,
			  8.0 * HOURS, 24.0 * HOURS, 7.0 * 24.0 * HOURS,
			  365.0 * 24.0 * HOURS]:
		var r := Away.roll(save, int(save["meta"]["saved_at"] + t))
		var faith: float = float(r["faith"])
		var played: float = rate * t
		print("%10s %10.1f %10.1f %8s  %d"
			% [_span(t), faith, played,
			   "-" if played <= 0.0 else "%.3f" % (faith / played),
			   (r["lines"] as Array).size()])
		# MONOTONE: more time away is never worth less.
		if faith < last - 0.001:
			_faults.append("payout fell as absence grew: %.2f then %.2f"
				% [last, faith])
		last = faith
		# THE INEQUALITY. Being away must never pay better than being here.
		if t > 0.0 and faith >= played:
			_faults.append("%s away paid %.1f against %.1f for playing -- "
				% [_span(t), faith, played] + "leaving is now a strategy")
		if t >= Away.AWAY_MIN and (r["lines"] as Array).size() < 3:
			_faults.append("%s away produced %d lines, wanted 3-6"
				% [_span(t), (r["lines"] as Array).size()])
		if t < Away.AWAY_MIN and faith > 0.0:
			_faults.append("%s is under the minimum and still paid %.2f"
				% [_span(t), faith])

	_check_ceiling(save, rate)
	_check_determinism(save)
	_check_no_reroll(save)
	_check_gates(save)
	_check_clock(save)
	_report()
	quit(0 if _faults.is_empty() else 1)


## The ceiling is COMPUTED from the constants, never typed in -- retuning
## AWAY_TAU must not be able to silently invalidate this test.
func _check_ceiling(save: Dictionary, rate: float) -> void:
	var bound: float = rate * Away.AWAY_RATE * Away.AWAY_TAU
	var far := Away.roll(save, int(save["meta"]["saved_at"] + 365.0 * 24.0 * HOURS))
	if float(far["faith"]) > bound + 0.001:
		_faults.append("a year away paid %.1f, above the computed ceiling %.1f"
			% [far["faith"], bound])
	# Saturating: the last six days of a week are worth almost nothing.
	var day := Away.roll(save, int(save["meta"]["saved_at"] + 24.0 * HOURS))
	var week := Away.roll(save, int(save["meta"]["saved_at"] + 7.0 * 24.0 * HOURS))
	var growth: float = float(week["faith"]) - float(day["faith"])
	if growth > 0.01 * float(day["faith"]):
		_faults.append("a week away paid %.1f more than a day (%.1f) -- the "
			% [growth, day["faith"]] + "payout is not saturating, so checking "
			+ "in rarely beats checking in often")
	print("[AWAY] ceiling %.1f Faith = %.1f minutes of watched play"
		% [bound, bound / maxf(rate, 0.0001) / 60.0])


func _check_determinism(save: Dictionary) -> void:
	var t := int(save["meta"]["saved_at"] + 4.0 * HOURS)
	var a := Away.roll(save, t)
	var b := Away.roll(save, t)
	if str(a) != str(b):
		_faults.append("two identical rolls differed")
	# A different seed must give a different story, or the seed is doing nothing.
	var other := save.duplicate(true)
	other["meta"]["away_seed"] = int(save["meta"]["away_seed"]) + 977
	if str(Away.roll(other, t)["lines"]) == str(a["lines"]):
		_faults.append("changing away_seed changed nothing")
	print("[AWAY] deterministic, and the seed matters")


## Reloading cannot reroll the log, and waiting cannot rewrite it.
func _check_no_reroll(save: Dictionary) -> void:
	var base := Away.roll(save, int(save["meta"]["saved_at"] + 3.0 * HOURS))
	var later := Away.roll(save, int(save["meta"]["saved_at"] + 5.0 * HOURS))
	var a: Array = base["lines"]
	var b: Array = later["lines"]
	for i in mini(3, mini(a.size(), b.size())):
		if String(a[i]) != String(b[i]):
			_faults.append("waiting rewrote line %d of the log, so waiting is "
				% i + "a strategy")
			break
	print("[AWAY] first lines stable as the absence grows")


## Every gated event is unreachable when its gate fails. Driven off the table
## itself, so adding an event without a gate test fails here rather than being
## remembered.
func _check_gates(save: Dictionary) -> void:
	var bare := save.duplicate(true)
	bare["folk"] = []
	bare["beasts"] = []
	bare["world"]["props"] = []
	bare["village"]["stores"] = {"food": 0, "wood": 0, "stone": 0}
	bare["divinity"]["age"] = 0
	var seen := {}
	for k in 400:
		var r := Away.roll(bare, int(bare["meta"]["saved_at"] + 6.0 * HOURS))
		bare["meta"]["away_seed"] = k * 7919 + 13
		for line in (r["lines"] as Array):
			seen[String(line)] = true
	for e in Away.EVENTS:
		if String(e["needs"]) == "":
			continue
		if Away._allows(bare, String(e["needs"])):
			continue
		var line := String(e["line"])
		for text in seen:
			# Compare on the fixed head of the line, since names are filled in.
			var head := line.split("%s")[0]
			if head.length() > 8 and String(text).begins_with(head):
				_faults.append("%s appeared for a village that cannot do it"
					% e["id"])
				break
	print("[AWAY] %d distinct lines over 400 rolls of an empty village"
		% seen.size())


func _check_clock(save: Dictionary) -> void:
	var back := Away.roll(save, int(save["meta"]["saved_at"] - 3600))
	if float(back["faith"]) > 0.0:
		_faults.append("a clock that moved backwards still paid out")
	# Forward, collect, back: the high-water mark makes the return trip free.
	var ratchet := save.duplicate(true)
	ratchet["meta"]["max_seen_unix"] = int(save["meta"]["saved_at"] + 48.0 * HOURS)
	var cheat := Away.roll(ratchet, int(save["meta"]["saved_at"] + 4.0 * HOURS))
	if float(cheat["faith"]) > 0.0:
		_faults.append("setting the clock forward, collecting, and setting it "
			+ "back paid a second time")
	print("[AWAY] backwards clock and the forward-then-back trick both pay 0")


## A village worth writing a log about, built by hand so this probe needs no
## scene at all.
func _save() -> Dictionary:
	return {
		"v": 1,
		"meta": {"saved_at": 1788561234, "max_seen_unix": 1788561234,
				 "away_seed": 918273645, "aura": ""},
		"world": {"props": [{"id": "Nature/crop_row", "col": 4, "row": 4},
							{"id": "Buildings/shrine", "col": 6, "row": 6},
							{"id": "Buildings/mine", "col": 8, "row": 8}]},
		"village": {"stores": {"food": 18, "wood": 12, "stone": 6}},
		"divinity": {"income_per_s": 0.9, "total_earned": 900.0, "age": 2},
		"folk": [{"seed": 1}, {"seed": 2}, {"seed": 3}, {"seed": 4}],
		"beasts": [{"kind": "Animals/sheep"}, {"kind": "Animals/cow"}],
	}


func _span(t: float) -> String:
	if t < 120.0:
		return "%ds" % int(t)
	if t < HOURS:
		return "%dm" % int(t / 60.0)
	if t < 48.0 * HOURS:
		return "%dh" % int(t / HOURS)
	return "%dd" % int(t / (24.0 * HOURS))


func _report() -> void:
	if _faults.is_empty():
		print("[AWAY] ok")
		return
	print("[AWAY] %d FAILURE(S)" % _faults.size())
	for f in _faults:
		print("  - %s" % f)
