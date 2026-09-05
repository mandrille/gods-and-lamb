extends Node
class_name Music

## A chill bed, generated in code. No .ogg, no .wav, no bytes.
##
## The game had NO music and no ambience at all -- nine procedural blips were
## the entire audio layer -- and its pitch word is "chill". Silence is not
## neutral on a portal: it reads as unfinished, and it is the first thing a
## player notices before they have understood a single mechanic.
##
## Same argument sfx.gd makes about download size, only more so: the whole game
## content is 5% of the web build, and a two-minute ambient loop as audio data
## would be larger than every mesh in the village put together. So it is
## arithmetic, built once at startup.
##
## WHAT IT IS: two seamless loops in the same key, cross-faded by time of day.
## A pentatonic pad for the day and a lower, slower one for dusk, both built
## from detuned sines with a slow tremolo -- no percussion, nothing with an
## onset sharp enough to demand attention. The rule is that you should be able
## to forget it is there, and notice when it stops.

const RATE := 22050
## Long enough not to feel like a two-bar loop, short enough to build in a
## frame. Fourteen seconds of 16-bit mono is ~600 KB of RAM and zero download.
const LOOP_SECS := 14.0
const FADE := 2.5                  ## seconds to cross between day and dusk

## A minor pentatonic, which is the least demanding scale there is: no
## semitone clashes, no leading tone pulling anywhere. Root A2.
const DAY_HZ := [220.00, 261.63, 293.66, 329.63, 392.00]
const NIGHT_HZ := [110.00, 130.81, 146.83, 164.81, 196.00]

var volume := 0.34
var muted := false

var _day: AudioStreamPlayer
var _night: AudioStreamPlayer
var _dusk := 0.0                   ## 0 day, 1 night
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 20260901
	_day = _voice(_build(DAY_HZ, 1.0))
	_night = _voice(_build(NIGHT_HZ, 0.72))
	_apply()


func _voice(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Master"
	p.stream = stream
	add_child(p)
	p.play()
	return p


## How far into dusk, 0..1. The crossfade is what makes nightfall felt rather
## than merely displayed.
##
## The delta is passed IN rather than read from get_process_delta_time().
##
## This node is driven by ValeRoot's _process, and the engine's own delta is
## zero while the tree is paused -- so a fade that read it moved nowhere at
## nightfall, when the tree is paused precisely because night has fallen.
## Taking the caller's delta also makes the fade testable in one call instead
## of a hundred and fifty frames.
func set_dusk(amount: float, delta: float) -> void:
	_dusk = move_toward(_dusk, clampf(amount, 0.0, 1.0), delta / FADE)
	_apply()


func set_muted(on: bool) -> void:
	muted = on
	_apply()


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	_apply()


func _apply() -> void:
	if _day == null or _night == null:
		return
	# Equal-power, so the pair does not dip in the middle of the crossfade the
	# way a linear one does.
	var a: float = cos(_dusk * PI * 0.5)
	var b: float = sin(_dusk * PI * 0.5)
	_day.volume_db = _db(a)
	_night.volume_db = _db(b)


func _db(gain: float) -> float:
	if muted or volume <= 0.001 or gain <= 0.001:
		return -80.0
	return linear_to_db(clampf(gain * volume, 0.0, 1.0))


## One seamless loop.
##
## SEAMLESS IS THE WHOLE PROBLEM. A loop whose last sample does not meet its
## first one clicks once every pass, and a click every fourteen seconds is far
## more irritating than no music. So every partial is given a whole number of
## cycles across the loop -- its frequency is rounded to the nearest multiple
## of 1/LOOP_SECS -- and the tremolo is too. Nothing then has a phase to
## discover at the seam.
func _build(scale: Array, warmth: float) -> AudioStreamWAV:
	var n := int(RATE * LOOP_SECS)
	var data := PackedByteArray()
	data.resize(n * 2)

	# Each voice: a scale note, a slight detune, its own slow swell.
	var voices: Array = []
	for i in scale.size():
		var base: float = float(scale[i])
		for d in [0.0, 0.6]:               # a cent or so apart, for movement
			voices.append({
				"hz": _snap(base + d),
				"amp": (0.30 if d == 0.0 else 0.18) * pow(0.82, float(i)),
				# A swell every 3 to 9 loop-lengths, so no two voices breathe
				# together and the pad never repeats audibly.
				"lfo": _snap(1.0 / LOOP_SECS * float(_rng.randi_range(1, 3))),
				"phase": _rng.randf() * TAU,
			})

	for i in n:
		var t := float(i) / float(RATE)
		var v := 0.0
		for w in voices:
			var swell: float = 0.55 + 0.45 * sin(TAU * float(w["lfo"]) * t
												 + float(w["phase"]))
			v += sin(TAU * float(w["hz"]) * t) * float(w["amp"]) * swell
		# A gentle low-pass by way of a softening curve: no harshness, and the
		# night pad sits further back than the day one.
		v = tanh(v * 0.9) * warmth * 0.5
		var s := int(clampf(v, -1.0, 1.0) * 32767.0)
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF

	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	w.data = data
	return w


## Nearest frequency that completes a whole number of cycles in one loop.
func _snap(hz: float) -> float:
	var per := 1.0 / LOOP_SECS
	return maxf(per, round(hz / per) * per)
