extends SceneTree
func _initialize() -> void:
	for id in ["Folk__villager", "Folk__adventurer"]:
		var inst := (load("res://assets/library/%s.glb" % id) as PackedScene).instantiate()
		var ap := _find(inst)
		print("%s: %s" % [id, "NO AnimationPlayer" if ap == null
			else str(ap.get_animation_list())])
	quit(0)
func _find(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer: return n
	for c in n.get_children():
		var f := _find(c)
		if f != null: return f
	return null
