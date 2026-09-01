extends Node
class_name SFX

## Basic sounds, generated in code.
##
## No .wav files anywhere. Every sound here is a few hundred samples of
## arithmetic built once at startup, which means the whole audio layer costs
## ZERO bytes of download -- and on a project whose entire game content is 5% of
## its web build, shipping a megabyte of audio to make a village go "clonk"
## would be the single most expensive thing in it.
##
## They are meant to read as toy-like and soft, matching the art. Nothing here
## is a realistic axe.
##
## Players are POOLED. AudioStreamPlayer allocation on a frame that already has
## a particle burst on it is the wrong moment to ask the engine for a node.

const RATE := 22050
const VOICES := 8

## name -> {freq, secs, kind, gain, sweep}
##   kind "tone"  a soft sine with a little second harmonic
##   kind "noise" filtered noise, for wood and impacts
const BANK := {
	"bless":   {"freq": 660.0, "secs": 0.42, "kind": "tone", "gain": 0.30,
				"sweep": 1.6},
	"punish":  {"freq": 190.0, "secs": 0.40, "kind": "tone", "gain": 0.34,
				"sweep": 0.45},
	"wrath":   {"freq": 90.0, "secs": 0.55, "kind": "noise", "gain": 0.40,
				"sweep": 0.3},
	"miracle": {"freq": 520.0, "secs": 0.55, "kind": "tone", "gain": 0.26,
				"sweep": 2.2},
	"chop":    {"freq": 240.0, "secs": 0.16, "kind": "noise", "gain": 0.30,
				"sweep": 0.5},
	"pick":    {"freq": 880.0, "secs": 0.09, "kind": "tone", "gain": 0.16,
				"sweep": 1.2},
	"chat":    {"freq": 430.0, "secs": 0.11, "kind": "tone", "gain": 0.13,
				"sweep": 1.35},
	"coin":    {"freq": 990.0, "secs": 0.20, "kind": "tone", "gain": 0.20,
				"sweep": 1.5},
	"deny":    {"freq": 160.0, "secs": 0.18, "kind": "tone", "gain": 0.22,
				"sweep": 0.7},
}

var muted := false
var volume := 0.7

var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _next := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 20260901
	for name in BANK:
		_streams[name] = _build(String(name), BANK[name])
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_voices.append(p)


## One sound, as 16-bit mono PCM.
##
## The envelope matters more than the waveform. A raw sine that starts and
## stops at full amplitude clicks at both ends -- that click is louder than the
## note and it is the first thing anyone notices -- so every sound gets a short
## attack and a long decay, and the decay does the character work.
func _build(name: String, spec: Dictionary) -> AudioStreamWAV:
	var secs := float(spec["secs"])
	var n := int(RATE * secs)
	var data := PackedByteArray()
	data.resize(n * 2)
	var freq := float(spec["freq"])
	var sweep := float(spec["sweep"])
	var gain := float(spec["gain"])
	var noisy := String(spec["kind"]) == "noise"
	var phase := 0.0
	var last := 0.0

	for i in n:
		var t := float(i) / float(n)
		# Attack over the first 4%, then an exponential decay. Fast for the
		# percussive ones, slow for the chimes.
		var env: float = minf(1.0, t / 0.04) * pow(1.0 - t, 2.2 if noisy else 1.4)
		var v := 0.0
		if noisy:
			# One-pole low pass on white noise: cheap, and it turns a hiss into
			# something with a body to it.
			var white := _rng.randf_range(-1.0, 1.0)
			last = last * 0.72 + white * 0.28
			v = last
		else:
			# Pitch glides by `sweep` across the sound. Rising reads as good
			# news, falling as bad, and that is most of the semantics here.
			var f: float = freq * lerpf(1.0, sweep, t)
			phase += TAU * f / float(RATE)
			v = sin(phase) * 0.8 + sin(phase * 2.0) * 0.2
		var s := int(clampf(v * env * gain, -1.0, 1.0) * 32767.0)
		# Little-endian 16-bit, which is what FORMAT_16_BITS expects.
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF

	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


## Play one. `pitch` varies per call so a repeated sound does not machine-gun:
## four villagers chopping in earshot with the identical sample is the most
## obvious tell that a game's audio is a lookup table.
func play(name: String, pitch := 1.0) -> void:
	if muted or not _streams.has(name) or _voices.is_empty():
		return
	var p := _voices[_next % _voices.size()]
	_next += 1
	p.stream = _streams[name]
	p.pitch_scale = clampf(pitch * _rng.randf_range(0.94, 1.07), 0.4, 2.4)
	p.volume_db = linear_to_db(clampf(volume, 0.0, 1.0))
	p.play()


func set_muted(on: bool) -> void:
	muted = on
	if on:
		for p in _voices:
			p.stop()
