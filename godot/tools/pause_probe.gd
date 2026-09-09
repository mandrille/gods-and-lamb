extends SceneTree
## Escape, mute, and the music bed.
##
## Escape used to open the DEBUG PANEL -- a developer console one keypress away
## from the most obvious key on a keyboard, in a build meant for a public
## portal -- and there was no pause, no mute and no way to start over. Portals
## ask for mute outright.
##
## The dangerous half is the same as the night screen's: this menu pauses the
## tree, so every path out of it is asserted. A pause with no exit is a hang.
const ShotWindowRef := preload("res://tools/shot_window.gd")

var _f := 0
var _root: Node = null
var _faults: Array[String] = []
var _stage := 0
var _shot := false
var _skipped_shots := false


func _initialize() -> void:
	ShotWindowRef.park()
	var scene = (load("res://scenes/vale.tscn") as PackedScene).instantiate()
	get_root().add_child(scene)
	_root = scene


func _process(_d: float) -> bool:
	_f += 1
	if _f < 25:
		return false
	if _f == 25:
		if _root == null or _root.get("pause_menu") == null:
			printerr("[PAUSE] FAIL: no pause menu")
			quit(1)
			return true
		return false

	match _stage:
		0:
			_open()
		1:
			_shoot()
		2:
			_mute()
		3:
			_close()
		4:
			_check_music()
			_check_sounds()
			paused = false
			_report()
			quit(0 if _faults.is_empty() else 1)
			return true
	return false


func _open() -> void:
	_root.pause_menu.open()
	if not _root.pause_menu.is_open():
		_faults.append("the pause menu did not open")
	if not paused:
		_faults.append("the pause menu did not pause the village")
	print("[PAUSE] open %s, paused %s"
		% [_root.pause_menu.is_open(), paused])
	_stage += 1


## Mute reaches BOTH audio layers. The API existed on SFX and was called from
## nowhere at all; adding a button that only silences half of it would be
## worse than none.
func _mute() -> void:
	var menu = _root.pause_menu
	menu.muted = true
	menu.muted_changed.emit(true)
	if not _root.sfx.muted:
		_faults.append("mute did not reach the sound effects")
	if _root.music != null and not _root.music.muted:
		_faults.append("mute did not reach the music")
	menu.muted = false
	menu.muted_changed.emit(false)
	if _root.sfx.muted or (_root.music != null and _root.music.muted):
		_faults.append("unmute did not reach both layers")
	print("[PAUSE] mute reaches sfx and music, and lifts")
	_stage += 1


## THE HANG TEST. Everything else here is a convenience; this is the one that
## would strand a player.
func _close() -> void:
	_root.pause_menu.close()
	if _root.pause_menu.is_open():
		_faults.append("the pause menu would not close")
	if paused:
		_faults.append("closing the pause menu left the village paused -- the "
			+ "game is hung with no way out")
	print("[PAUSE] closed, paused %s" % paused)
	_stage += 1


## THE TRACK. It is a sampler now rather than two rendered pads, so what is
## worth asserting changed with it: that the bank is real audio, that the
## arrangement is as long as it claims, that the sequencer actually fires, and
## that night still takes something away.
func _check_music() -> void:
	var m = _root.music
	if m == null:
		_faults.append("there is no music layer at all")
		return

	# EVERY SAMPLE IS REAL AUDIO. A buffer of zeroes loads, plays, and passes
	# any test that only asks whether it exists -- and is silence.
	for name in ["key", "bass", "kick", "snare", "hat", "open", "vinyl"]:
		var w: AudioStreamWAV = m.samples.get(name)
		if w == null or w.data.size() < 200:
			_faults.append("the '%s' sample is missing or empty" % name)
			continue
		# The bed has its own bounds, in both directions. It plays for the whole
		# session with nothing masking it, so it has to be quiet -- but "quiet"
		# and "zeroes" look identical to a floor written for the instruments.
		var lo := 0.008 if name == "vinyl" else 0.05
		var hi := 0.12 if name == "vinyl" else 1.01
		var peak: float = _peak(w)
		if peak < lo:
			_faults.append("the '%s' sample never rises above %.3f -- it is "
				% [name, peak] + "a silent buffer")
		elif peak > hi:
			_faults.append("the vinyl bed peaks at %.3f, which is loud enough "
				% peak + "to be heard over the music instead of under it")

	# THE BED LOOPS, SEAMLESSLY. It is the only thing playing during a
	# breakdown, and a click every four seconds is worse than no music.
	var bed: AudioStreamWAV = m.samples["vinyl"]
	if bed.loop_mode != AudioStreamWAV.LOOP_FORWARD:
		_faults.append("the vinyl bed does not loop, so the record stops "
			+ "four seconds in")
	var seam: float = absf(_sample(bed, 0)
						   - _sample(bed, bed.data.size() / 2 - 1))
	if seam > 0.06:
		_faults.append("the bed's loop seam jumps by %.3f, which is an "
			% seam + "audible click every pass")

	# LONG ENOUGH TO BE A TRACK. Three minutes was the ask; anything under two
	# and the player is hearing the same eight bars for a whole session.
	var secs: float = m.total_seconds()
	if secs < 180.0 or secs > 300.0:
		_faults.append("the arrangement is %.0fs, which is outside the three "
			% secs + "to four minutes it is meant to run")

	# THE SEQUENCER FIRES, and keeps firing all the way through -- including
	# after it wraps, which is where an off-by-one leaves a silent second pass.
	m.running = false
	var before: int = m.fired
	m._clock = 0.0
	m._step = -1
	m.advance()
	var first: int = m.fired - before
	m._clock = secs * 0.5
	m.advance()
	var middle: int = m.fired - before - first
	m._clock = secs * 1.5              # wrapped, second time around
	m.advance()
	var wrapped: int = m.fired - before - first - middle
	print("[PAUSE] music: %.0fs arrangement, %d notes to the middle, "
		% [secs, middle] + "%d after it wraps" % wrapped)
	if middle < 200:
		_faults.append("only %d notes in half an arrangement -- the sequencer "
			% middle + "is barely playing anything")
	if wrapped < 200:
		_faults.append("the second pass fired %d notes against %d in the first "
			% [wrapped, middle] + "-- the track goes quiet after one loop")

	# NIGHT TAKES THE KIT AWAY, and leaves the record spinning.
	m.set_dusk(0.0, 100.0)
	var day_kit: float = m._kit_gain()
	m.set_dusk(1.0, 100.0)
	print("[PAUSE] kit gain: day %.2f, night %.2f; bed %.1f dB at night"
		% [day_kit, m._kit_gain(), m._bed.volume_db])
	if m._kit_gain() >= day_kit:
		_faults.append("the drums are as loud at night as by day")
	if m._bed.volume_db <= -60.0:
		_faults.append("the bed is silent at night, so nightfall sounds like "
			+ "the audio died")
	m.set_dusk(0.0, 100.0)
	m.running = true


## The loudest sample in a buffer, 0..1.
func _peak(w: AudioStreamWAV) -> float:
	var n: int = w.data.size() / 2
	var hi := 0.0
	for i in range(0, n, 7):
		hi = maxf(hi, absf(_sample(w, i)))
	return hi


func _sample(w: AudioStreamWAV, index: int) -> float:
	var lo: int = w.data[index * 2]
	var hi: int = w.data[index * 2 + 1]
	var v: int = lo | (hi << 8)
	if v >= 32768:
		v -= 65536
	return float(v) / 32768.0


func _db_of(p: AudioStreamPlayer) -> float:
	return p.volume_db


## Every action that begins in silence now has something to say.
func _check_sounds() -> void:
	var missing: Array[String] = []
	for act in Brain.ACTIONS:
		var a := String(act)
		if a.begins_with("build_"):
			continue                    # covered by the begins_with fallback
		if not _root.ARRIVAL_SFX.has(a) and not _root.JOB_LOOK.has(a):
			missing.append(a)
	print("[PAUSE] actions with neither an arrival sound nor a payout look: %s"
		% [missing])
	# `flee` is the one that mattered: a villager frightened by a wolf produced
	# nothing at all, which is the single moment the village is in danger.
	if not _root.JOB_LOOK.has("flee"):
		_faults.append("flee still has no feedback")
	if missing.size() > 2:
		_faults.append("%d actions are still entirely silent: %s"
			% [missing.size(), missing])


func _shoot() -> void:
	if _f % 4 != 0:
		return
	if not ShotWindowRef.can_shoot():
		_skipped_shots = true
		_stage += 1
		return
	ShotWindow.shoot("res://shots/pause_menu.png")
	print("[PAUSE] wrote res://shots/pause_menu.png")
	_shot = true
	_stage += 1


func _report() -> void:
	if _skipped_shots:
		print("[PAUSE] no display: the picture was skipped, checks still ran")
	elif not _shot:
		_faults.append("no picture was taken")
	if _faults.is_empty():
		print("[PAUSE] ok")
		return
	print("[PAUSE] %d FAILURE(S)" % _faults.size())
	for f in _faults:
		print("  - %s" % f)
