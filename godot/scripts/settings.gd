extends Node
class_name Settings

## Player/debug settings, persisted as a flat JSON object in `user://`.
##
## Deliberately dumb: a Dictionary in, `JSON.stringify` out, `JSON.parse_string`
## back with a type guard. No Resource, no custom binary, no version field.
## A Resource carries a class path into the save file and turns a rename into a
## broken save; a version field is a thing to forget to bump. A dictionary that
## is missing a key just falls back, which is the behaviour a settings file
## wants on every upgrade anyway.
##
## `user://` maps to IndexedDB in a web export, so this works unchanged there.
##
## WRITES ARE EXPLICIT. `set_value` only updates memory, emits `changed` and
## marks dirty; nothing touches the disk until `save_all()`. A slider dragged
## across its range fires a hundred `set_value` calls and must not fire a
## hundred file writes -- on web each one is an IndexedDB transaction.
##
## Values must be JSON-native (bool / number / String / Array / Dictionary).
## A Color is NOT: `JSON.stringify` would fall back to `str()` and hand back
## "(1, 1, 1, 1)" on load, a String that no longer converts. Convert at the call
## site with `Color.to_html()` / `Color.html()`.

const PATH := "user://settings.json"

signal changed(key: String, value: Variant)

var _values: Dictionary = {}
var _dirty := false


## Replace the in-memory store with what is on disk. A missing or corrupt file
## is not an error -- it is a first run, and the caller's fallbacks apply.
func load_all() -> void:
	_values = {}
	_dirty = false
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_warning("Settings: cannot read %s (%d)"
			% [PATH, FileAccess.get_open_error()])
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Settings: %s is not a JSON object -- ignoring it" % PATH)
		return
	_values = parsed


func save_all() -> void:
	# Nothing changed and the file already says so. On web every write is an
	# IndexedDB transaction, and a Save button people press twice should not
	# cost two of them.
	if not _dirty and FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("Settings: cannot write %s (%d)"
			% [PATH, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(_values, "\t"))
	f.close()
	_dirty = false


func get_value(key: String, fallback: Variant) -> Variant:
	return _values[key] if _values.has(key) else fallback


func set_value(key: String, v: Variant) -> void:
	if not _is_json_native(v):
		push_warning("Settings: '%s' is a %s, which JSON cannot round-trip; "
			% [key, type_string(typeof(v))]
			+ "convert it at the call site (a Color wants to_html()).")
	_values[key] = v
	_dirty = true
	changed.emit(key, v)


func _is_json_native(v: Variant) -> bool:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, \
		TYPE_STRING_NAME, TYPE_ARRAY, TYPE_DICTIONARY:
			return true
	return false
