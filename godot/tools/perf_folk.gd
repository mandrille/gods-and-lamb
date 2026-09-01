extends SceneTree

## What every library asset is made of. Numbers only, so this may run
## --headless.
##
## perf_followers.gd measures what N followers COST; this says what the unit
## IS, which is the difference between "400 followers cost 53 ms" and "400
## followers cost 53 ms BECAUSE each one is nine surfaces on a skinned mesh".
##
## Surfaces, not nodes, are the unit: a MeshInstance3D with nine surfaces is
## nine submissions -- and on a SKINNED mesh, nine skinning updates every
## frame. The props carry the same high surface counts and it costs them
## almost nothing, because they are static. Same number, two prices.


func _initialize() -> void:
	var ids: Array[String] = []
	for f in DirAccess.get_files_at("res://assets/library"):
		if String(f).ends_with(".glb"):
			ids.append(String(f).get_basename())
	ids.sort()
	for id in ids:
		var path := "res://assets/library/%s.glb" % id
		var packed: PackedScene = load(path)
		var root := packed.instantiate()
		var meshes := 0
		var surfaces := 0
		var tris := 0
		var skinned := 0
		var bones := -1
		var nodes := 0
		var clips: Array[String] = []
		var mats := {}
		for n in _walk(root):
			nodes += 1
			if n is Skeleton3D:
				bones = (n as Skeleton3D).get_bone_count()
			if n is AnimationPlayer:
				for a in (n as AnimationPlayer).get_animation_list():
					var clip := (n as AnimationPlayer).get_animation(a)
					clips.append("%s (%.2fs, %d tracks, step %.4f)"
						% [a, clip.length, clip.get_track_count(), clip.step])
			if n is MeshInstance3D:
				var mi := n as MeshInstance3D
				if mi.mesh == null:
					continue
				meshes += 1
				if mi.skin != null:
					skinned += 1
				var sc := mi.mesh.get_surface_count()
				surfaces += sc
				for s in sc:
					var arr := mi.mesh.surface_get_arrays(s)
					var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
					var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
					tris += (idx.size() / 3) if idx.size() > 0 else (verts.size() / 3)
					var m := mi.mesh.surface_get_material(s)
					if m != null:
						mats[m.resource_name if m.resource_name != "" else str(m)] = true
					mi.cast_shadow = mi.cast_shadow
		print("%s: nodes=%d meshes=%d (skinned %d) surfaces=%d tris=%d materials=%d bones=%d"
			% [id, nodes, meshes, skinned, surfaces, tris, mats.size(), bones])
		for c in clips:
			print("    clip %s" % c)
		root.queue_free()
	quit(0)


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out
