extends SceneTree

## Headless check: the renderer is the one the platform requires, the library
## is complete, the layout parses, and the folk carry a skin and a clip.
##
## Prints `[TAG] label ... ok/FAIL` and quits 1 on any failure, so CI and a
## human get the same answer.

func _initialize() -> void:
	var faults: Array[String] = []

	var method := str(ProjectSettings.get_setting(
		"rendering/renderer/rendering_method"))
	_check(faults, "renderer is gl_compatibility (web has no other)",
		method == "gl_compatibility", method)

	var f := FileAccess.open("res://data/vale.json", FileAccess.READ)
	if f == null:
		faults.append("no res://data/vale.json -- run `build.py -- export`")
	else:
		var doc: Variant = JSON.parse_string(f.get_as_text())
		_check(faults, "vale.json parses", typeof(doc) == TYPE_DICTIONARY, "")
		if typeof(doc) == TYPE_DICTIONARY:
			var d: Dictionary = doc
			_check(faults, "layout has rows", int(d.get("rows", 0)) > 0, "")
			var ids := {}
			for p in d.get("props", []):
				ids[p["id"]] = true
			for code_id in d.get("code", {}).values():
				ids[code_id] = true
			var missing: Array[String] = []
			for aid in ids.keys():
				var path := "res://assets/library/%s.glb" \
					% String(aid).replace("/", "__")
				if not ResourceLoader.exists(path):
					missing.append(String(aid))
			_check(faults, "every asset the layout names is in the library",
				missing.is_empty(), ", ".join(missing))

	# The folk are the only assets that must carry more than geometry.
	for folk in ["Folk__villager", "Folk__adventurer"]:
		var path := "res://assets/library/%s.glb" % folk
		if not ResourceLoader.exists(path):
			faults.append("%s missing from the library" % folk)
			continue
		var packed: PackedScene = load(path)
		var root := packed.instantiate()
		var has_skin := false
		var has_clip := false
		for n in _walk(root):
			if n is MeshInstance3D and (n as MeshInstance3D).skin != null:
				has_skin = true
			if n is AnimationPlayer:
				for a in (n as AnimationPlayer).get_animation_list():
					if "walk" in String(a).to_lower():
						has_clip = true
		root.queue_free()
		_check(faults, "%s has a skin" % folk, has_skin, "")
		_check(faults, "%s has a walk clip" % folk, has_clip, "")

	if faults.is_empty():
		print("[VALE-TEST] all checks ok")
		quit(0)
	else:
		for fault in faults:
			printerr("  - " + fault)
		printerr("[VALE-TEST] %d FAILED" % faults.size())
		quit(1)


func _check(faults: Array[String], label: String, ok: bool, detail: String) -> void:
	print("[VALE-TEST] %-52s %s" % [label, "ok" if ok else "FAIL"])
	if not ok:
		faults.append(label + (" (%s)" % detail if detail != "" else ""))


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out
