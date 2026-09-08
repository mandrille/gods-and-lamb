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


## The bed exists, loops seamlessly, and follows the day.
func _check_music() -> void:
	var m = _root.music
	if m == null:
		_faults.append("there is no music layer at all")
		return
	var players: Array = []
	for c in m.get_children():
		if c is AudioStreamPlayer:
			players.append(c)
	if players.size() < 2:
		_faults.append("expected a day pad and a night pad, found %d"
			% players.size())
		return
	for p in players:
		var w := p.stream as AudioStreamWAV
		if w == null or w.data.size() < 1000:
			_faults.append("a music stream is empty -- a silent buffer passes "
				+ "every test that only asks whether it loaded")
			continue
		if w.loop_mode != AudioStreamWAV.LOOP_FORWARD:
			_faults.append("a music stream does not loop, so the bed stops "
				+ "fourteen seconds in")
		# SEAMLESS: the last sample must meet the first, or it clicks once a
		# pass, and a click every fourteen seconds is worse than silence.
		var first := _sample(w, 0)
		var last := _sample(w, w.data.size() / 2 - 1)
		if absf(first - last) > 0.06:
			_faults.append("the loop seam jumps by %.3f, which is an audible "
				% absf(first - last) + "click every pass")
	# Day and night cross-fade rather than switching.
	m.set_dusk(0.0, 100.0)
	m.set_dusk(1.0, 100.0)
	if _db_of(players[1]) <= _db_of(players[0]):
		_faults.append("at full dusk the night pad is not the louder one")
	print("[PAUSE] music: %d pads, seamless, dusk moves the mix" % players.size())


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
