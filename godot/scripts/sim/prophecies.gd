extends RefCounted
class_name Prophecies

## Who speaks them, when, and what happens when they come true.
##
## One at a time and only while there is a prophet, which is the coupling that
## makes this worth having: losing the person who speaks for you also loses the
## thing you were working towards. A village with no prophet has ages and
## prayers and nothing in between, exactly as it did before.

## The gap between one being settled and the next being spoken. A prophecy runs
## for five minutes; this is the breath after it, so the session has a shape
## rather than being an unbroken queue of objectives.
const REST := 70.0

## And it will not foretell something that is nearly true already. Picking is a
## shuffle and then the first kind whose target is a real advance -- without
## this, "%d trees standing" lands on a village that is two trees away and is
## fulfilled before the prophet has finished the sentence.
const MIN_ROOM := 1

signal spoken(prophecy: Prophecy)
signal fulfilled(prophecy: Prophecy)
signal broken(prophecy: Prophecy)

var host = null
var current: Prophecy = null
var _next_at := -1.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 20260913


func tick(now: float) -> void:
	if host == null or host.divinity == null:
		return
	if current != null:
		_settle(now)
		return
	# NO PROPHET, NO PROPHECY. Not a gate bolted on for balance -- there is
	# nobody to say it.
	if not host.divinity.prophet.has():
		_next_at = -1.0
		return
	if _next_at < 0.0:
		_next_at = now + REST
		return
	if now >= _next_at:
		_speak(now)


func _settle(now: float) -> void:
	if current.done(host):
		var p := current
		current = null
		_next_at = now + REST
		_reward(p)
		fulfilled.emit(p)
		return
	if current.expired(now):
		var p := current
		current = null
		_next_at = now + REST
		broken.emit(p)


## What being right is worth. A gift, through the same door a milestone uses,
## because a prophecy is a milestone the player chose to chase.
func _reward(p: Prophecy) -> void:
	var d = host.divinity
	d.add_faith(Prophecy.FAITH)
	d.earned.emit(Prophecy.FAITH, _where(), "prophecy")
	d.grant_draft("prophecy")


func _where() -> Vector3:
	var p = host.divinity.prophet
	if p != null and p.has():
		return p.who.position
	return Vector3.ZERO


## Shuffle the kinds and take the first one that is a genuine advance.
func _speak(now: float) -> void:
	var kinds: Array = Prophecy.KINDS.keys()
	kinds.shuffle()
	for kind in kinds:
		var row: Dictionary = Prophecy.KINDS[kind]
		var here: int = Prophecy.read(String(kind), host)
		var target: int = here + int(row["step"])
		if target - here < MIN_ROOM:
			continue
		var p := Prophecy.new(String(kind), target, now)
		p.spoken = String(row["says"]) % [host.divinity.prophet.name_of(),
										  target]
		current = p
		spoken.emit(p)
		return


## The line the HUD shows, or "" when there is nothing being foretold.
func line(now: float) -> String:
	if current == null:
		return ""
	return current.short(host, now)
