extends SceneTree
## Bounce the music to a .wav you can actually listen to.
##
## Nobody can judge "lo-fi hip hop, chill" from a source file, and the game's
## own audio only exists at runtime -- there is no asset to open. So this drives
## the REAL sequencer in recording mode, mixes what it asks for, and writes a
## file.
##
## It has no idea what the pattern is. `Music` hands it a list of
## {at, stream, pitch, gain} and this only sums them; a preview with its own
## copy of the arrangement would keep sounding fine after the arrangement broke,
## which makes it a preview of nothing.
##
##   godot --headless --audio-driver Dummy --script tools/music_render.gd
##
## Renders SECONDS from the top by default; pass a number of seconds and an
## output path after `--` to change either.
const OUT := "user://music_preview.wav"
const RATE := 22050
const SECONDS := 75.0

var _m: Music = null
var _f := 0


func _initialize() -> void:
	_m = Music.new()
	get_root().add_child(_m)


func _process(_d: float) -> bool:
	_f += 1
	if _f < 2:
		return false                  # _ready has to have built the bank
	var secs := SECONDS
	var out := OUT
	for a in OS.get_cmdline_user_args():
		if a.is_valid_float():
			secs = a.to_float()
		elif a.ends_with(".wav"):
			out = a

	_m.recording = true
	_m.running = false
	_m._clock = minf(secs, _m.total_seconds())
	_m.advance()
	print("[MIX] %d notes over %.0fs of a %.0fs arrangement"
		% [_m.record.size(), secs, _m.total_seconds()])

	var n := int(RATE * secs)
	var buf := PackedFloat32Array()
	buf.resize(n)

	# The bed first, looped underneath everything, because that is how it plays.
	_lay(buf, _m.samples["vinyl"], 0, 1.0, 1.0, true)
	for e in _m.record:
		var at: int = int(float(e["at"]) * RATE)
		if at >= n:
			continue
		_lay(buf, e["stream"], at, float(e["pitch"]), float(e["gain"]), false)

	# Peak-normalise to -1 dB rather than clipping. This is a preview of the
	# arrangement, and a limiter smashing the transients would be a preview of
	# the limiter.
	var peak := 0.0
	for i in n:
		peak = maxf(peak, absf(buf[i]))
	var g: float = (0.89 / peak) if peak > 0.001 else 1.0
	print("[MIX] peak %.2f before normalising, gain x%.2f" % [peak, g])
	if peak < 0.02:
		printerr("[MIX] FAIL: the mix is silent")
		quit(1)
		return true

	var path := ProjectSettings.globalize_path(out)
	_write_wav(path, buf, g)
	print("[MIX] wrote %s (%.1f s, %.1f MB)"
		% [path, secs, float(n * 2) / 1048576.0])
	quit(0)
	return true


## Sum one sample into the mix at `at`, resampled by `pitch`.
##
## Linear interpolation, which is the same thing an AudioStreamPlayer's
## pitch_scale does and is what makes the preview match what the game plays.
func _lay(buf: PackedFloat32Array, w: AudioStreamWAV, at: int, pitch: float,
		  gain: float, loop: bool) -> void:
	var src := _floats(w)
	if src.is_empty():
		return
	# Two rates in play: the sample's own and the mix's. Ignoring that is how a
	# drum kit rendered at 11 kHz ends up an octave high in a 22 kHz file.
	var step: float = pitch * float(w.mix_rate) / float(RATE)
	var n := buf.size()
	var pos := 0.0
	var i := at
	while i < n:
		var k := int(pos)
		if k + 1 >= src.size():
			if not loop:
				return
			pos -= float(src.size())
			k = int(pos)
			if k + 1 >= src.size() or k < 0:
				return
		var frac: float = pos - float(k)
		buf[i] += (src[k] * (1.0 - frac) + src[k + 1] * frac) * gain
		pos += step
		i += 1


func _floats(w: AudioStreamWAV) -> PackedFloat32Array:
	var n: int = w.data.size() / 2
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var v: int = w.data[i * 2] | (w.data[i * 2 + 1] << 8)
		if v >= 32768:
			v -= 65536
		out[i] = float(v) / 32767.0
	return out


func _write_wav(path: String, buf: PackedFloat32Array, gain: float) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("[MIX] FAIL: cannot write %s" % path)
		quit(1)
		return
	var n := buf.size()
	var bytes := n * 2
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + bytes)
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)                    # PCM header size
	f.store_16(1)                     # PCM
	f.store_16(1)                     # mono
	f.store_32(RATE)
	f.store_32(RATE * 2)              # byte rate
	f.store_16(2)                     # block align
	f.store_16(16)                    # bits
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(bytes)
	for i in n:
		f.store_16(_pcm(buf[i] * gain))
	f.close()


func _pcm(v: float) -> int:
	var s := int(clampf(v, -1.0, 1.0) * 32767.0)
	return s if s >= 0 else s + 65536
