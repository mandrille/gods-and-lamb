extends SceneTree
## Nothing worth watching for three minutes is what a player quits during.
##
## The director's whole job is a FLOOR under the pacing, so the things worth
## asserting are that it insists when the village goes quiet, that it says
## nothing while the village is already busy, that it does not fire twice in a
## row, and that it never reaches for the same thing repeatedly when it has a
## choice -- wolves, then wolves, then wolves is weather rather than events.
var _faults: Array[String] = []

func _initialize() -> void:
	var d := Director.new()
	var all := {"newcomer": true, "wolf": true, "calamity": true}

	# QUIET INSISTS.
	d.mark("start", 0.0)
	d.tick(10.0)
	var early: String = d.wants(10.0, all)
	d.tick(Director.QUIET + 5.0)
	var late: String = d.wants(Director.QUIET + 5.0, all)
	print("[DIR] after 10s the director wants '%s'; after %.0fs it wants '%s'"
		% [early, Director.QUIET + 5.0, late])
	if early != "":
		_faults.append("the director interrupted a village that was ten "
			+ "seconds into its own business")
	if late == "":
		_faults.append("the village went quiet for %.0fs and the director "
			% (Director.QUIET + 5.0) + "never insisted on anything")

	# THE GENTLE RUNG FIRST. It would rather add somebody than set fire to them.
	if late != "newcomer":
		_faults.append("with every option open the director reached for '%s' "
			% late + "rather than the gentlest one")

	# NOT TWICE IN A ROW.
	d.mark(late, Director.QUIET + 5.0)
	d.tick(Director.QUIET + 5.0 + Director.AFTER * 0.5)
	var soon: String = d.wants(Director.QUIET + 5.0 + Director.AFTER * 0.5, all)
	print("[DIR] %.0fs after an event it wants '%s'" % [Director.AFTER * 0.5, soon])
	if soon != "":
		_faults.append("two events inside the breathing room -- that is noise, "
			+ "not twice the drama")

	# AND NOT THE SAME THING REPEATEDLY when there is a choice.
	var t := 1000.0
	var picks: Array = []
	for i in 4:
		d.mark(picks[-1] if not picks.is_empty() else "wolf", t)
		t += Director.QUIET + Director.AFTER + 5.0
		d.tick(t)
		picks.append(d.wants(t, all))
	print("[DIR] four in a row: %s" % [picks])
	var same := true
	for p in picks:
		if p != picks[0]:
			same = false
	if same:
		_faults.append("the director reached for '%s' every time -- that is "
			% picks[0] + "weather, not events")

	# IT SAYS NOTHING WHEN NOTHING IS POSSIBLE, rather than forcing one.
	d.mark("x", 0.0)
	d.tick(9999.0)
	var stuck: String = d.wants(9999.0, {})
	if stuck != "":
		_faults.append("with nothing eligible the director still demanded '%s'"
			% stuck)

	# AND PRESSURE IS BOUNDED, so a long quiet cannot make it insist twice.
	print("[DIR] pressure after a very long quiet: %.2f" % d.pressure)
	if d.pressure > 1.0:
		_faults.append("pressure ran past 1.0 (%.2f) -- it will spend the "
			% d.pressure + "backlog all at once when something becomes possible")

	if _faults.is_empty():
		print("[DIR] ok")
	else:
		print("[DIR] %d FAILURE(S)" % _faults.size())
		for f in _faults:
			print("  - %s" % f)
	quit(0 if _faults.is_empty() else 1)
