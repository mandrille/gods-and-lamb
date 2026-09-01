extends CanvasLayer
class_name DebugMenu

## The in-game debug panel: look-dev on the running build, plus a stress test.
##
## Code-built, no .tscn and no Theme. Structural changes inside an instantiated
## sub-scene are not serialised, so a panel saved into a scene would come up
## empty; and everything else in this project is assembled in _ready() for the
## same reason.
##
## The panel is REBUILT from scratch every time it opens rather than diffed
## against the live values. It is a debug panel, not a UI framework: a rebuild
## is a few hundred microseconds once per Escape press, and it cannot go stale,
## which is the failure that actually costs time -- a slider showing 1.0 while
## the sun is at 2.3 makes every number you read off the panel a lie.
##
## RANGES COME FROM THE ENGINE. Every slider's min/max/step is parsed out of the
## property's own PROPERTY_HINT_RANGE at build time (see `_hint_range`), so this
## file cannot offer a value the engine will reject and cannot drift when a
## range changes between Godot versions. The two exceptions are the sun's yaw
## and pitch, which are angles with no engine range at all -- their limits are
## the geometric domain and are written out in BINDINGS with a reason.
##
## Nothing here is Forward+. No volumetric fog control exists because
## Compatibility has no volumetric fog; adding one would make the editor
## silently disagree with the web build, which is the one thing this project
## cannot have.
##
## What IS real here was measured rather than recalled -- `tools/menu_probe.gd`
## toggles each property on a lit scene and byte-compares the frames. On
## GL Compatibility, Godot 4.7, NVIDIA/OpenGL 3.3, every control on this panel
## changes the picture, GLOW INCLUDED: glow_enabled at intensity 8 moved mean
## luma by +0.35. The received wisdom that glow is Forward+-only is wrong for
## this version, and a disabled glow slider would have been a lie.
##
## The one property that can be inert is `ambient_light_energy`, and it is not
## the renderer's fault: while `ambient_light_sky_contribution` is 1.0 the
## ambient term comes entirely from the sky and energy is not applied. That is
## exactly how vale_light.gd ships, so the sky-contribution slider sits next to
## it and the row says so while it is inert. See `_note_for`.

## Sizes are DEVICE pixels and go through `_ui()` before they are used. The
## project stretches a 720x1280 portrait canvas onto whatever window it gets
## (`canvas_items` / `expand`), so the logical space the layout runs in is not
## the screen: on a 1280x800 desktop window it is 2048x1280. A literal "480
## wide" panel drew 300 pixels across with 10-pixel text, which is how this
## was found.
const PANEL_W := 480.0
const LABEL_W := 178.0
const VALUE_W := 74.0
const SLIDER_W := 130.0
const SWATCH_W := 80.0
const FONT_PX := 14.0
const HEAD_PX := 12.0
const CANVAS_LAYER := 128

## key, label, kind, where it lives, and the property path. `prop` goes through
## get_indexed/set_indexed so a sub-property ("rotation_degrees:y") is just
## another path and needs no special case.
const BINDINGS := [
	# -- Settings ---------------------------------------------------------
	{"key": "render.scale", "label": "Resolution scale", "kind": "float",
	 "tab": "Settings", "obj": "vp", "prop": "scaling_3d_scale"},
	{"key": "render.shadows", "label": "Shadows", "kind": "bool",
	 "tab": "Settings", "obj": "sun", "prop": "shadow_enabled"},

	# -- Post FX ----------------------------------------------------------
	{"key": "fx.fog_enabled", "label": "Fog", "kind": "bool",
	 "tab": "Post FX", "obj": "env", "prop": "fog_enabled", "head": "Fog (depth)"},
	{"key": "fx.fog_density", "label": "Density", "kind": "float",
	 "tab": "Post FX", "obj": "env", "prop": "fog_density"},
	{"key": "fx.fog_light_color", "label": "Colour", "kind": "color",
	 "tab": "Post FX", "obj": "env", "prop": "fog_light_color"},
	{"key": "fx.fog_sun_scatter", "label": "Sun scatter", "kind": "float",
	 "tab": "Post FX", "obj": "env", "prop": "fog_sun_scatter"},
	{"key": "fx.fog_aerial", "label": "Aerial persp.", "kind": "float",
	 "tab": "Post FX", "obj": "env", "prop": "fog_aerial_perspective"},

	{"key": "fx.glow_enabled", "label": "Glow", "kind": "bool",
	 "tab": "Post FX", "obj": "env", "prop": "glow_enabled", "head": "Glow"},
	{"key": "fx.glow_intensity", "label": "Intensity", "kind": "float",
	 "tab": "Post FX", "obj": "env", "prop": "glow_intensity"},
	{"key": "fx.glow_bloom", "label": "Bloom", "kind": "float",
	 "tab": "Post FX", "obj": "env", "prop": "glow_bloom"},

	{"key": "fx.adjust_enabled", "label": "Adjustments", "kind": "bool",
	 "tab": "Post FX", "obj": "env", "prop": "adjustment_enabled",
	 "head": "Colour adjustment"},
	{"key": "fx.adjust_brightness", "label": "Brightness", "kind": "float",
	 "tab": "Post FX", "obj": "env", "prop": "adjustment_brightness"},
	{"key": "fx.adjust_contrast", "label": "Contrast", "kind": "float",
	 "tab": "Post FX", "obj": "env", "prop": "adjustment_contrast"},
	{"key": "fx.adjust_saturation", "label": "Saturation", "kind": "float",
	 "tab": "Post FX", "obj": "env", "prop": "adjustment_saturation"},

	{"key": "fx.exposure", "label": "Exposure", "kind": "float",
	 "tab": "Post FX", "obj": "env", "prop": "tonemap_exposure",
	 "head": "Tonemap"},

	# -- Light ------------------------------------------------------------
	# Yaw and pitch are Node3D rotation, which carries a +-360 wrap hint and no
	# meaningful limit. One full turn of yaw covers every distinct sun compass
	# bearing, and a pitch above 0 puts the sun under the map -- the village
	# goes black and the panel looks broken. Those are the limits, and they are
	# geometry rather than an invented uniform range.
	{"key": "light.yaw", "label": "Sun yaw", "kind": "float",
	 "tab": "Light", "obj": "sun", "prop": "rotation_degrees:y",
	 "min": -180.0, "max": 180.0, "step": 0.5, "head": "Sun direction"},
	{"key": "light.pitch", "label": "Sun pitch", "kind": "float",
	 "tab": "Light", "obj": "sun", "prop": "rotation_degrees:x",
	 "min": -90.0, "max": 0.0, "step": 0.5},
	{"key": "light.energy", "label": "Energy", "kind": "float",
	 "tab": "Light", "obj": "sun", "prop": "light_energy", "head": "Sun"},
	{"key": "light.color", "label": "Colour", "kind": "color",
	 "tab": "Light", "obj": "sun", "prop": "light_color"},
	{"key": "light.shadow", "label": "Shadows", "kind": "bool",
	 "tab": "Light", "obj": "sun", "prop": "shadow_enabled"},
	{"key": "light.ambient", "label": "Ambient energy", "kind": "float",
	 "tab": "Light", "obj": "env", "prop": "ambient_light_energy",
	 "head": "Environment"},
	# Not on the original list, and it is here because without it the slider
	# above is dead. Measured: ambient_light_energy moved nothing at all at
	# sky contribution 1.0, and moved the frame the moment the contribution
	# came down. Shipping the energy slider alone would have shipped a knob
	# that does nothing in the exact configuration the game runs in.
	{"key": "light.ambient_sky", "label": "Ambient from sky", "kind": "float",
	 "tab": "Light", "obj": "env", "prop": "ambient_light_sky_contribution"},
]

const TABS := ["Settings", "Post FX", "Light", "Stress"]

var _env: Environment = null
var _sun: DirectionalLight3D = null
var _host: Node = null
var _settings: Settings = null

var _open := false
var _panel: Control = null
## key -> Array of {"main": Control, "value": Label, "name": Label}. A key can
## own more than one row: shadows appear on both Settings and Light, and
## toggling either has to move the other or the panel contradicts itself inside
## a single screenshot.
var _rows: Dictionary = {}
## The values the rig itself set, captured before anything saved is applied.
## "Default" means what vale_light.gd shipped, not what Godot's Environment
## constructor happens to hold.
var _defaults: Dictionary = {}
var _lbl_fps: Label = null
var _lbl_count: Label = null
var _lbl_status: Label = null
var _spawned := 0
var _fps_wait := 0.0
var _prev_mouse := Input.MOUSE_MODE_VISIBLE
var _dirty := false


func setup(env: Environment, sun: DirectionalLight3D, host: Node,
		settings: Settings) -> void:
	_env = env
	_sun = sun
	_host = host
	_settings = settings
	layer = CANVAS_LAYER
	# PROCESS_MODE_ALWAYS, before anything pauses. Pausing the tree while a
	# debug panel is open is the obvious thing to want; with an inherited
	# process mode it would stop _unhandled_input, and Escape could no longer
	# close the thing that caused the pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _settings != null and not _settings.changed.is_connected(_on_setting_changed):
		_settings.changed.connect(_on_setting_changed)
	set_process(false)
	set_process_unhandled_input(true)
	# `render.scale` lives on the Viewport, and get_viewport() is null until we
	# are in the tree. setup() may legitimately be called before add_child, so
	# wait rather than silently dropping that one binding.
	if is_inside_tree():
		_init_values()
	else:
		ready.connect(_init_values, CONNECT_ONE_SHOT)


func _init_values() -> void:
	_capture_defaults()
	_apply_saved()


# -- open / close ----------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	if _open:
		return
	_open = true
	# Hand the mouse back exactly as it was found. The game may well capture it
	# later; a debug panel that leaves the cursor mode changed is a bug that
	# shows up three screens away from here.
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	set_process(true)


func close() -> void:
	if not _open:
		return
	_open = false
	Input.mouse_mode = _prev_mouse
	set_process(false)
	_rows.clear()
	_lbl_fps = null
	_lbl_count = null
	_lbl_status = null
	if _panel != null:
		_panel.queue_free()
		_panel = null


func is_open() -> bool:
	return _open


func _process(delta: float) -> void:
	if _lbl_fps == null:
		return
	# Four updates a second. A Label rebuilt every frame allocates a String
	# every frame, and the number is unreadable at 60 Hz anyway.
	_fps_wait -= delta
	if _fps_wait > 0.0:
		return
	_fps_wait = 0.25
	_lbl_fps.text = "%d fps" % Engine.get_frames_per_second()


# -- values ----------------------------------------------------------------

func _obj(which: String) -> Object:
	match which:
		"env":
			return _env
		"sun":
			return _sun
		"vp":
			return get_viewport()
	return null


func _read_prop(e: Dictionary) -> Variant:
	var o := _obj(e["obj"])
	if o == null:
		return null
	return o.get_indexed(NodePath(e["prop"]))


func _write_prop(e: Dictionary, v: Variant) -> void:
	var o := _obj(e["obj"])
	if o == null:
		return
	o.set_indexed(NodePath(e["prop"]), v)


func _capture_defaults() -> void:
	_defaults.clear()
	for e in BINDINGS:
		var v: Variant = _read_prop(e)
		if v != null:
			_defaults[e["key"]] = v


## Push whatever is in the settings file onto the live Environment / light /
## viewport. Anything absent keeps the rig's own value.
func _apply_saved() -> void:
	if _settings == null:
		return
	for e in BINDINGS:
		var key: String = e["key"]
		if not _defaults.has(key):
			continue
		var stored: Variant = _settings.get_value(key, null)
		if stored == null:
			continue
		match String(e["kind"]):
			"bool":
				_write_prop(e, bool(stored))
			"float":
				_write_prop(e, float(stored))
			"color":
				# Stored as "#rrggbbaa": JSON cannot round-trip a Color, so the
				# conversion lives here rather than in Settings.
				var s := String(stored)
				if Color.html_is_valid(s):
					_write_prop(e, Color.html(s))
				else:
					push_warning("DebugMenu: '%s' is not a colour: %s" % [key, s])


func _save_values() -> void:
	if _settings == null:
		return
	for e in BINDINGS:
		var v: Variant = _read_prop(e)
		if v == null:
			continue
		if String(e["kind"]) == "color":
			_settings.set_value(e["key"], (v as Color).to_html())
		else:
			_settings.set_value(e["key"], v)
	_settings.save_all()
	_dirty = false
	_status("saved %d values to %s" % [BINDINGS.size(), Settings.PATH])
	print("[DEBUG] saved %d values to %s" % [BINDINGS.size(), Settings.PATH])


func _reset_defaults() -> void:
	for e in BINDINGS:
		if _defaults.has(e["key"]):
			_write_prop(e, _defaults[e["key"]])
	_build()
	_status("reset to the rig's own values (press Save to persist)")


func _on_setting_changed(_key: String, _value: Variant) -> void:
	_dirty = true


# -- panel -----------------------------------------------------------------

func _build() -> void:
	if _panel != null:
		_panel.queue_free()
	_rows.clear()

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_right = _ui(PANEL_W)
	# The stock panel style is translucent, and a readout sitting over a bright
	# meadow is a readout nobody can read -- which defeats the point of putting
	# the numbers on the controls. A stylebox override, not a Theme resource.
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.07, 0.08, 0.11, 0.95)
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)
	_panel = panel

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(_ui(8.0)))
	panel.add_child(margin)

	var col := VBoxContainer.new()
	margin.add_child(col)

	col.add_child(_label("DEBUG    esc closes    %s" % _renderer_name()))

	var tabs := TabContainer.new()
	tabs.add_theme_font_size_override("font_size", int(_ui(FONT_PX)))
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(tabs)

	var pages: Dictionary = {}
	for t in TABS:
		# TabContainer takes each tab's title from the child's node name.
		var scroll := ScrollContainer.new()
		scroll.name = t
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tabs.add_child(scroll)
		var page := VBoxContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(page)
		pages[t] = page

	for e in BINDINGS:
		var page: VBoxContainer = pages[e["tab"]]
		if e.has("head"):
			_header(page, String(e["head"]))
		match String(e["kind"]):
			"bool":
				_add_toggle(page, e)
			"float":
				_add_slider(page, e)
			"color":
				_add_color(page, e)

	_build_settings_extras(pages["Settings"])
	_build_stress(pages["Stress"])

	var footer := HBoxContainer.new()
	col.add_child(footer)
	var save := _button("Save")
	save.pressed.connect(_save_values)
	footer.add_child(save)
	_lbl_status = _label("unsaved changes" if _dirty else Settings.PATH)
	_lbl_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_status.clip_text = true
	_lbl_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	footer.add_child(_lbl_status)


## Device pixels -> the logical units the Control layout actually runs in.
## Falls back to 1:1 when there is no window to measure against, which is the
## headless case and does not matter: nothing is being looked at.
func _ui(px: float) -> float:
	if not is_inside_tree():
		return px
	var logical: float = get_viewport().get_visible_rect().size.x
	var device: float = float(DisplayServer.window_get_size().x)
	if device <= 0.0 or logical <= 0.0:
		return px
	return px * (logical / device)


## Every Label goes through here so the font size is converted exactly once.
## Per-control overrides rather than a Theme: the house style is code-built
## controls, and a Theme is a second copy of the look to keep in step.
func _label(text: String, px := FONT_PX) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(_ui(px)))
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", int(_ui(FONT_PX)))
	return b


func _renderer_name() -> String:
	return str(ProjectSettings.get_setting(
		"rendering/renderer/rendering_method", "?"))


func _status(text: String) -> void:
	if _lbl_status != null:
		_lbl_status.text = text


func _header(parent: VBoxContainer, text: String) -> void:
	parent.add_child(HSeparator.new())
	parent.add_child(_label(text.to_upper(), HEAD_PX))


func _name_label(text: String) -> Label:
	var l := _label(text)
	l.custom_minimum_size.x = _ui(LABEL_W)
	# TRIM_ELLIPSIS, not just clip_text: a long label reports a long minimum
	# size, and HBoxContainer honours it by taking the space out of the slider.
	# The first version of the inert note shrank its own slider to ten pixels.
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_FILL
	return l


## min / max / step straight off the property's own range hint. Extra hint bits
## ("or_greater", "suffix:m") are ignored on purpose: the slider stops where the
## engine's own inspector stops, and a property that accepts more than that can
## still be driven past it in code.
func _hint_range(obj: Object, prop: String) -> Vector3:
	var base: String = prop.split(":")[0]
	if obj != null:
		for p in obj.get_property_list():
			if String(p["name"]) != base:
				continue
			if int(p["hint"]) != PROPERTY_HINT_RANGE:
				break
			var bits := String(p["hint_string"]).split(",")
			if bits.size() < 3:
				break
			return Vector3(float(bits[0]), float(bits[1]), float(bits[2]))
	push_warning("DebugMenu: no range hint for %s -- falling back to 0..1"
		% prop)
	return Vector3(0.0, 1.0, 0.01)


func _range_of(e: Dictionary) -> Vector3:
	if e.has("min"):
		return Vector3(float(e["min"]), float(e["max"]), float(e["step"]))
	return _hint_range(_obj(e["obj"]), String(e["prop"]))


## Decimals that actually show the step. A 0.0001-step slider printed to two
## places sits still while the value moves, which is worse than no readout.
func _fmt(v: float, step: float) -> String:
	var dp := 0
	if step < 1.0:
		dp = 1
	if step < 0.1:
		dp = 2
	if step < 0.01:
		dp = 3
	if step < 0.001:
		dp = 4
	return String.num(v, dp)


func _register(key: String, main: Control, value: Label, name: Label) -> void:
	if not _rows.has(key):
		_rows[key] = []
	_rows[key].append({"main": main, "value": value, "name": name})


## Repaint every control bound to `key` from the live value. Cheap, and it is
## what keeps the two Shadows rows from disagreeing.
func _refresh(key: String) -> void:
	if not _rows.has(key):
		return
	var e := _binding(key)
	if e.is_empty():
		return
	var v: Variant = _read_prop(e)
	for row in _rows[key]:
		var main: Control = row["main"]
		var value: Label = row["value"]
		match String(e["kind"]):
			"bool":
				var cb := main as CheckButton
				cb.set_pressed_no_signal(bool(v))
				cb.text = "on" if bool(v) else "off"
			"float":
				var sl := main as HSlider
				sl.set_value_no_signal(float(v))
				if value != null:
					value.text = _fmt(float(v), sl.step)
			"color":
				var cp := main as ColorPickerButton
				cp.color = v
				if value != null:
					value.text = "#" + (v as Color).to_html(false)


func _binding(key: String) -> Dictionary:
	for e in BINDINGS:
		if String(e["key"]) == key:
			return e
	return {}


func _add_slider(parent: VBoxContainer, e: Dictionary) -> void:
	var r := _range_of(e)
	var hb := HBoxContainer.new()
	parent.add_child(hb)
	var name := _name_label(String(e["label"]) + _note_for(e))
	hb.add_child(name)

	var sl := HSlider.new()
	sl.min_value = r.x
	sl.max_value = r.y
	sl.step = r.z
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.custom_minimum_size.x = _ui(SLIDER_W)
	var now: Variant = _read_prop(e)
	sl.set_value_no_signal(float(now) if now != null else r.x)
	hb.add_child(sl)

	var val := _label(_fmt(sl.value, sl.step))
	val.custom_minimum_size.x = _ui(VALUE_W)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(val)

	sl.value_changed.connect(func(v: float) -> void:
		_write_prop(e, v)
		val.text = _fmt(v, sl.step)
		_dirty = true
		_update_notes())
	_register(String(e["key"]), sl, val, name)


func _add_toggle(parent: VBoxContainer, e: Dictionary) -> void:
	var hb := HBoxContainer.new()
	parent.add_child(hb)
	var name := _name_label(String(e["label"]) + _note_for(e))
	hb.add_child(name)

	var cb := CheckButton.new()
	cb.add_theme_font_size_override("font_size", int(_ui(FONT_PX)))
	var now := bool(_read_prop(e))
	cb.set_pressed_no_signal(now)
	cb.text = "on" if now else "off"
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(cb)

	var key: String = e["key"]
	cb.toggled.connect(func(pressed: bool) -> void:
		_write_prop(e, pressed)
		_dirty = true
		_refresh(key)
		_update_notes())
	_register(key, cb, null, name)


func _add_color(parent: VBoxContainer, e: Dictionary) -> void:
	var hb := HBoxContainer.new()
	parent.add_child(hb)
	var name := _name_label(String(e["label"]) + _note_for(e))
	hb.add_child(name)

	var cp := ColorPickerButton.new()
	cp.edit_alpha = false
	cp.custom_minimum_size = Vector2(_ui(SWATCH_W), _ui(22.0))
	cp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var now: Variant = _read_prop(e)
	cp.color = now if now != null else Color.WHITE
	hb.add_child(cp)

	var val := _label("#" + cp.color.to_html(false))
	val.custom_minimum_size.x = _ui(VALUE_W)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(val)

	cp.color_changed.connect(func(c: Color) -> void:
		_write_prop(e, c)
		val.text = "#" + c.to_html(false)
		_dirty = true)
	_register(String(e["key"]), cp, val, name)


## A control that is live but currently inert, and why. A slider that moves and
## changes nothing is worse than a missing one: it invites an afternoon of
## tuning, and the panel is the only place that fact will ever be read.
##
## Exactly one property earns a note, and it was measured rather than assumed:
## ambient_light_energy does nothing at all while the ambient term comes
## entirely from the sky. `tools/menu_probe.gd` reports it NO CHANGE at sky
## contribution 1.0 and changed at 0.0.
func _note_for(e: Dictionary) -> String:
	if String(e["key"]) == "light.ambient" and _env != null \
			and _env.ambient_light_sky_contribution >= 1.0:
		return "  (inert)"
	return ""


## Re-apply every row's note. Called after any change, because the thing that
## makes a note stale is the slider two rows below it.
func _update_notes() -> void:
	for key in _rows:
		var e := _binding(key)
		if e.is_empty():
			continue
		for row in _rows[key]:
			var lbl: Label = row["name"]
			if lbl != null:
				lbl.text = String(e["label"]) + _note_for(e)


func _build_settings_extras(page: VBoxContainer) -> void:
	_header(page, "Defaults")
	var btn := _button("Reset to defaults")
	btn.pressed.connect(_reset_defaults)
	page.add_child(btn)
	var note := _label("Restores the values the light rig set at startup. "
		+ "The saved file only changes when you press Save.", HEAD_PX)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(note)


func _build_stress(page: VBoxContainer) -> void:
	_header(page, "Followers")
	var hb := HBoxContainer.new()
	page.add_child(hb)
	for n in [1, 10, 50]:
		var b := _button("+%d" % n)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_spawn.bind(n))
		hb.add_child(b)
	var clear := _button("Clear")
	clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear.pressed.connect(_clear)
	hb.add_child(clear)

	var count_row := HBoxContainer.new()
	page.add_child(count_row)
	count_row.add_child(_name_label("Spawned"))
	_lbl_count = _label(str(_spawned))
	count_row.add_child(_lbl_count)

	var fps_row := HBoxContainer.new()
	page.add_child(fps_row)
	fps_row.add_child(_name_label("Frame rate"))
	_lbl_fps = _label("%d fps" % Engine.get_frames_per_second())
	fps_row.add_child(_lbl_fps)


## The host owns the followers; this only asks. `spawn_follower` and
## `clear_spawned` are checked rather than assumed so a host that has not wired
## them up says so in the panel instead of taking the scene down.
func _spawn(n: int) -> void:
	if _host == null or not _host.has_method("spawn_follower"):
		_status("host has no spawn_follower()")
		return
	for i in n:
		_host.call("spawn_follower")
		_spawned += 1
	if _lbl_count != null:
		_lbl_count.text = str(_spawned)
	_status("spawned %d (%d total)" % [n, _spawned])


func _clear() -> void:
	if _host == null or not _host.has_method("clear_spawned"):
		_status("host has no clear_spawned()")
		return
	_host.call("clear_spawned")
	_spawned = 0
	if _lbl_count != null:
		_lbl_count.text = "0"
	_status("cleared")
