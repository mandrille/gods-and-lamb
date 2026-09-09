extends Node
class_name Music

## Lo-fi hip hop, generated in code. No .ogg, no .wav, no bytes.
##
## Same argument sfx.gd makes about download size, only more so: the whole game
## content is 5% of the web build, and three and a half minutes of audio data
## would be larger than every mesh in the village put together. So it is
## arithmetic, built once at startup.
##
## WHAT IT IS: a dusty four-chord loop at 76 BPM with a swung boom-bap kit over
## it, arranged into sections so it runs three and a half minutes before it
## comes back around. I-vi-ii-V in C with sevenths on everything, an upright-ish
## bass on the roots, and a bed of vinyl crackle underneath that never stops.
## The rule is still that you should be able to forget it is there -- nothing
## has an onset sharp enough to demand attention, the snare is a soft brushed
## thing rather than a crack, and the whole kit ducks away at nightfall.
##
## HOW IT IS BUILT, and this is the part that matters:
##
## It is a SAMPLER, not a rendered track. Four minutes of PCM is 5 MB of RAM
## and, far worse, millions of sine calls in GDScript at startup -- an earlier
## version of this file rendered fourteen seconds across ten voices and cost
## 6.2 million of them, which added tens of seconds to every scene load, killed
## the probe suite outright, and would have been a black screen on a phone
## before the game had started. So seven short one-shots are built (about 15,000
## samples of audio all told, a fifth of a second) and a sequencer triggers them
## on a musical grid. Every pitch comes from `pitch_scale` on one key sample and
## one bass sample, which is what a sampler has always done and what makes a
## whole arrangement affordable.

const RATE := 22050                ## for the keys, which have real partials
const LOW_RATE := 11025            ## drums and bass: nothing above 3 kHz

const BPM := 76.0                  ## the tempo the whole genre lives at
const BEATS_PER_BAR := 4
const STEPS_PER_BAR := 16          ## sixteenths
const BARS_PER_SECTION := 4
## How far the off-eighths lean late, as a fraction of a sixteenth. Straight
## sixteenths are a drum machine; this is most of the difference between "lo-fi
## hip hop" and "a metronome with chords on it".
const SWING := 0.22

## The reference pitch each sampled note was rendered at. Everything else is
## this one buffer played faster or slower.
const KEY_REF := 261.63            ## C4
const BASS_REF := 65.41            ## C2

## I - vi - ii - V in C, one bar each, with sevenths. Voiced close, and rootless
## so the chords stay out of the bass's way -- four notes including the root is
## what makes a keyboard sound like a church organ.
const CHORDS := [
	[329.63, 392.00, 493.88, 587.33],   # Cmaj7  -- E4 G4 B4 D5
	[261.63, 329.63, 392.00, 440.00],   # Am7    -- C4 E4 G4 A4
	[293.66, 349.23, 440.00, 523.25],   # Dm7    -- D4 F4 A4 C5
	[293.66, 349.23, 392.00, 493.88],   # G7     -- D4 F4 G4 B4
]
const ROOTS := [65.41, 55.00, 73.42, 49.00]   ## C2 A1 D2 G1

## THE ARRANGEMENT, four bars per entry, which is what makes this a track rather
## than a loop. Sixteen sections is 3:22 before anything repeats.
##
## A loop the player hears twenty times in a session has to earn each pass, and
## the cheapest way to earn it is to leave things out: the breakdowns are what
## make the full sections land.
const SECTIONS := [
	{"keys": true, "bass": false, "kit": false, "open": false},   # intro
	{"keys": true, "bass": true, "kit": false, "open": false},
	{"keys": true, "bass": true, "kit": true, "open": false},     # in
	{"keys": true, "bass": true, "kit": true, "open": true},
	{"keys": true, "bass": true, "kit": true, "open": true},
	{"keys": true, "bass": true, "kit": true, "open": false},
	{"keys": true, "bass": true, "kit": false, "open": false},    # breathe
	{"keys": true, "bass": false, "kit": false, "open": false},
	{"keys": true, "bass": true, "kit": true, "open": false},     # back in
	{"keys": true, "bass": true, "kit": true, "open": true},
	{"keys": false, "bass": true, "kit": true, "open": true},     # kit alone
	{"keys": true, "bass": true, "kit": true, "open": true},
	{"keys": true, "bass": true, "kit": true, "open": false},
	{"keys": true, "bass": true, "kit": false, "open": false},    # breathe
	{"keys": true, "bass": true, "kit": true, "open": true},
	{"keys": true, "bass": true, "kit": true, "open": true},
]

## The kit, as sixteenth-note steps within a bar. Boom-bap: the kick lands on
## one and then late, the snare only ever on two and four.
const KICK_STEPS := [0, 6, 10]
const KICK_GHOST := [3, 11]        ## quieter, and only in the busier bars
const SNARE_STEPS := [4, 12]
const OPEN_HAT_STEPS := [14]

const FADE := 2.5                  ## seconds to cross between day and dusk

var volume := 0.34
var muted := false
## Whether the sequencer is allowed to run. Off in probes that only want to
## look at the sample bank.
var running := true

var samples: Dictionary = {}       ## name -> AudioStreamWAV
var fired := 0                     ## notes triggered, for the probe

## OFFLINE RENDERING. With `recording` on, every note is written to `record`
## as {at, stream, pitch, gain} instead of being played.
##
## The point is that tools/music_render.gd bounces the arrangement to a .wav
## you can listen to WITHOUT a second copy of the sequencer in it. A preview
## built from its own idea of the pattern is a preview of nothing: it would
## still sound fine after this file had been broken.
var recording := false
var record: Array = []
var _fire_at := 0.0                ## absolute time of the step being fired

var _dusk := 0.0                   ## 0 day, 1 night
var _rng := RandomNumberGenerator.new()

var _bed: AudioStreamPlayer        ## vinyl, the one thing that never stops
var _keys: Array[AudioStreamPlayer] = []
var _bass: Array[AudioStreamPlayer] = []
var _drums: Array[AudioStreamPlayer] = []
var _key_i := 0
var _bass_i := 0
var _drum_i := 0

var _clock := 0.0                  ## seconds since the track started
var _step := -1                    ## last sixteenth already fired


func _ready() -> void:
	# ALWAYS. The tree is paused at nightfall and while the pause menu is open,
	# and music that stops dead the moment a modal opens is worse than no music:
	# it makes the game feel like it crashed.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 20260901

	samples["key"] = _key_sample()
	samples["bass"] = _bass_sample()
	samples["kick"] = _kick()
	samples["snare"] = _snare()
	samples["hat"] = _hat(0.055, 0.020)
	samples["open"] = _hat(0.190, 0.075)
	samples["vinyl"] = _vinyl()

	_bed = _player(samples["vinyl"])
	_bed.play()
	for i in 8:
		_keys.append(_player(samples["key"]))
	for i in 3:
		_bass.append(_player(samples["bass"]))
	for i in 6:
		_drums.append(_player(samples["kick"]))
	_apply()


func _player(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Master"
	p.stream = stream
	add_child(p)
	return p


## --- the sequencer ----------------------------------------------------------

func step_seconds() -> float:
	return (60.0 / BPM) * float(BEATS_PER_BAR) / float(STEPS_PER_BAR)


func total_steps() -> int:
	return SECTIONS.size() * BARS_PER_SECTION * STEPS_PER_BAR


## How long the whole arrangement runs before it comes back around.
func total_seconds() -> float:
	return float(total_steps()) * step_seconds()


func _process(delta: float) -> void:
	if not running or muted or volume <= 0.001:
		return
	_clock += delta
	advance()


## Fire every sixteenth that has come due. Split out from `_process` so a probe
## can run a whole three-minute arrangement in one call instead of waiting
## twelve thousand frames for it.
func advance() -> void:
	var want := int(fmod(_clock, total_seconds()) / step_seconds())
	# Wrapped: the track came round again, so start the count over rather than
	# firing four thousand steps to catch up.
	if want < _step:
		_step = -1
	while _step < want:
		_step += 1
		_fire(_step)


## One sixteenth.
func _fire(step: int) -> void:
	_fire_at = float(step) * step_seconds()
	var bar: int = step / STEPS_PER_BAR
	var s: int = step % STEPS_PER_BAR
	var section: Dictionary = SECTIONS[(bar / BARS_PER_SECTION) % SECTIONS.size()]
	var chord: int = bar % CHORDS.size()

	# CHORDS ON THE DOWNBEAT AND A PUSH BEFORE IT. The push -- the last
	# sixteenth of the bar, quiet, already on the next chord -- is most of what
	# keeps the loop from sitting square, and it costs one extra note.
	if bool(section["keys"]):
		if s == 0:
			_chord(chord, 1.0)
		elif s == 15:
			_chord((chord + 1) % CHORDS.size(), 0.34)
		elif s == 8 and bar % 2 == 1:
			_chord(chord, 0.42)

	if bool(section["bass"]):
		if s == 0:
			_note(_bass, _bass_i, samples["bass"],
				  float(ROOTS[chord]) / BASS_REF, 0.9, 0.0)
			_bass_i += 1
		elif s == 10:
			# The late root: the one thing that makes a bass line walk.
			_note(_bass, _bass_i, samples["bass"],
				  float(ROOTS[chord]) / BASS_REF, 0.55, _swing(s))
			_bass_i += 1

	if not bool(section["kit"]):
		return
	if s in KICK_STEPS:
		_drum("kick", 1.0, _swing(s))
	elif s in KICK_GHOST and bar % 2 == 1:
		_drum("kick", 0.35, _swing(s))
	if s in SNARE_STEPS:
		_drum("snare", 0.8, _swing(s))
	if s % 2 == 0:
		# Hats breathe: loud on the beat, softer between, and one nearly gone.
		# An even hat is the sound of a machine.
		var v := 0.42 if s % 4 == 0 else 0.24
		if s == 6:
			v = 0.14
		_drum("hat", v, _swing(s))
	if bool(section["open"]) and s in OPEN_HAT_STEPS:
		_drum("open", 0.30, _swing(s))


## How late this step sits. Only the off-eighths lean; anything on a beat stays
## exactly where it is, which is what swing means.
func _swing(step: int) -> float:
	if step % 4 == 2:
		return step_seconds() * SWING
	return 0.0


func _chord(index: int, gain: float) -> void:
	var notes: Array = CHORDS[index]
	for i in notes.size():
		# Rolled, barely: about six milliseconds between notes, which is under
		# the threshold for hearing them as separate and over the threshold for
		# hearing a struck chord rather than a stab.
		_note(_keys, _key_i, samples["key"], float(notes[i]) / KEY_REF,
			  gain * _key_gain() * 0.6 * (1.0 - 0.12 * float(i)),
			  float(i) * 0.006)
		_key_i += 1


func _drum(name: String, gain: float, delay: float) -> void:
	_note(_drums, _drum_i, samples[name], 1.0, gain * _kit_gain(), delay)
	_drum_i += 1


## Round-robin across the pool. Hunting for a silent player sounds better in
## theory and cuts the oldest note in practice, because at four notes a chord
## and a 1.8-second tail there is never a silent one.
func _note(pool: Array, index: int, stream: AudioStreamWAV, pitch: float,
		   gain: float, delay: float) -> void:
	if pool.is_empty() or gain <= 0.002:
		return
	fired += 1
	if recording:
		record.append({"at": _fire_at + delay, "stream": stream,
					   "pitch": pitch, "gain": gain})
		return
	var p: AudioStreamPlayer = pool[index % pool.size()]
	p.stream = stream
	p.pitch_scale = clampf(pitch, 0.1, 4.0)
	p.volume_db = _db(gain)
	if delay <= 0.0 or get_tree() == null:
		p.play()
		return
	# A timer rather than a tween: this has to fire while the tree is paused,
	# and it is one shot with nothing to interpolate.
	get_tree().create_timer(delay, true, false, true).timeout.connect(
		func():
			if is_instance_valid(p):
				p.play())


## --- day and night ----------------------------------------------------------

## How far into dusk, 0..1. The crossfade is what makes nightfall felt rather
## than merely displayed.
##
## The delta is passed IN rather than read from get_process_delta_time(). This
## node is driven by ValeRoot's _process, and the engine's own delta is zero
## while the tree is paused -- so a fade that read it moved nowhere at
## nightfall, when the tree is paused precisely because night has fallen.
## Taking the caller's delta also makes the fade testable in one call instead of
## a hundred and fifty frames.
func set_dusk(amount: float, delta: float) -> void:
	_dusk = move_toward(_dusk, clampf(amount, 0.0, 1.0), delta / FADE)
	_apply()


func dusk() -> float:
	return _dusk


## NIGHT TAKES THE DRUMS AWAY. Not the whole track -- silence at nightfall would
## read as a bug -- but a beat is the wrong thing to hear over a sleeping
## village. The keys and the vinyl stay, quieter, and the kit comes back with
## the sun.
func _kit_gain() -> float:
	return 1.0 - _dusk


func _key_gain() -> float:
	return 1.0 - 0.45 * _dusk


func set_muted(on: bool) -> void:
	muted = on
	_apply()


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	_apply()


## Only the things that are sustaining. Everything else takes its level at the
## moment it is struck, which is how an instrument works -- a note already
## ringing does not get quieter because the sun went down.
func _apply() -> void:
	if _bed != null:
		# The crackle comes UP a little at night, because it is the only thing
		# left holding the floor once the kit has gone.
		_bed.volume_db = _db(0.5 + 0.25 * _dusk)
	if muted or volume <= 0.001:
		for p in _keys + _bass + _drums:
			p.volume_db = -80.0


func _db(gain: float) -> float:
	if muted or volume <= 0.001 or gain <= 0.001:
		return -80.0
	return linear_to_db(clampf(gain * volume, 0.0, 1.0))


## --- the sample bank --------------------------------------------------------
##
## Everything below builds one short buffer, once. None of it is called again.

## A soft electric-piano-ish note: a fundamental with two quiet partials and a
## long exponential tail. Every pitch in the track is this buffer resampled.
func _key_sample() -> AudioStreamWAV:
	var n := int(RATE * 1.8)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / float(RATE)
		# 6 ms attack. An instant onset on a sine is a click, and a click is the
		# one thing a bed must never make.
		var env: float = minf(t / 0.006, 1.0) * exp(-t * 1.9)
		var v := sin(TAU * KEY_REF * t)
		v += 0.30 * sin(TAU * KEY_REF * 2.0 * t) * exp(-t * 3.4)
		v += 0.10 * sin(TAU * KEY_REF * 3.0 * t) * exp(-t * 6.0)
		buf[i] = v * env * 0.42
	return _wav(buf, RATE, false)


func _bass_sample() -> AudioStreamWAV:
	var n := int(LOW_RATE * 1.1)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / float(LOW_RATE)
		var env: float = minf(t / 0.010, 1.0) * exp(-t * 2.2)
		var v := sin(TAU * BASS_REF * t)
		# One quiet octave up, which is what lets a 55 Hz note be audible at all
		# on a phone speaker that cannot reproduce 55 Hz.
		v += 0.22 * sin(TAU * BASS_REF * 2.0 * t) * exp(-t * 3.0)
		buf[i] = tanh(v * 1.1) * env * 0.5
	return _wav(buf, LOW_RATE, false)


func _kick() -> AudioStreamWAV:
	var n := int(LOW_RATE * 0.34)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / float(LOW_RATE)
		# The pitch drop IS the kick. A fixed low sine is a hum.
		var hz: float = 48.0 + 78.0 * exp(-t * 26.0)
		var env: float = minf(t / 0.003, 1.0) * exp(-t * 9.0)
		buf[i] = sin(TAU * hz * t) * env * 0.75
	return _wav(buf, LOW_RATE, false)


## Brushed rather than cracked: a short noise burst with a soft body under it
## and the top rolled off. A snare with a real transient would be the one thing
## on this screen demanding attention every two seconds.
func _snare() -> AudioStreamWAV:
	var n := int(LOW_RATE * 0.26)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / float(LOW_RATE)
		var env: float = minf(t / 0.004, 1.0) * exp(-t * 15.0)
		var noise: float = _rng.randf_range(-1.0, 1.0) * 0.5
		var body: float = sin(TAU * 186.0 * t) * 0.35 * exp(-t * 22.0)
		# One-pole low-pass on the way past, which is the only kind of filter
		# this file can afford and all this needs.
		prev = prev * 0.45 + (noise + body) * 0.55
		buf[i] = prev * env * 0.42
	return _wav(buf, LOW_RATE, false)


## Noise, made bright by taking the DIFFERENCE between neighbouring samples --
## a one-line high-pass.
func _hat(secs: float, decay: float) -> AudioStreamWAV:
	var n := int(LOW_RATE * secs)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / float(LOW_RATE)
		var x: float = _rng.randf_range(-1.0, 1.0)
		buf[i] = (x - prev) * 0.5 * exp(-t / maxf(decay, 0.001)) * 0.30
		prev = x
	return _wav(buf, LOW_RATE, false)


## THE BED. Vinyl surface noise with the odd pop in it, looping forever under
## everything else -- it is what makes four bars of silence during a breakdown
## sound like a record still spinning rather than the audio having died.
##
## Seamless by crossfading the tail back over the head, because random noise has
## no phase to line up and a click every four seconds is exactly what a quiet
## bed must not have.
func _vinyl() -> AudioStreamWAV:
	var n := int(LOW_RATE * 4.0)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var prev := 0.0
	for i in n:
		# Low-passed noise: hiss that sits under the music rather than over it.
		prev = prev * 0.86 + _rng.randf_range(-1.0, 1.0) * 0.14
		buf[i] = prev * 0.5
	# The pops. Sparse, short, and never inside the crossfade region where they
	# would be heard twice.
	var fade := int(LOW_RATE * 0.12)
	for p in 22:
		var at: int = _rng.randi_range(fade, n - fade * 2)
		var loud: float = _rng.randf_range(0.25, 0.85)
		for k in 40:
			if at + k >= n:
				break
			buf[at + k] += sin(TAU * 1400.0 * float(k) / float(LOW_RATE)) \
				* loud * exp(-float(k) * 0.16)
	for i in fade:
		var a: float = float(i) / float(fade)
		buf[i] = buf[i] * a + buf[n - fade + i] * (1.0 - a)
	buf.resize(n - fade)
	# Quiet, and that is a requirement rather than taste: this plays for the
	# whole session with nothing masking it.
	for i in buf.size():
		buf[i] *= 0.055
	return _wav(buf, LOW_RATE, true)


func _wav(buf: PackedFloat32Array, rate: int, looping: bool) -> AudioStreamWAV:
	var n := buf.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var s := int(clampf(buf[i], -1.0, 1.0) * 32767.0)
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.loop_mode = (AudioStreamWAV.LOOP_FORWARD if looping
				   else AudioStreamWAV.LOOP_DISABLED)
	w.loop_begin = 0
	w.loop_end = n
	w.data = data
	return w
