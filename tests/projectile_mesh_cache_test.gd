extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var failures := 0
	for team: StringName in [&"player",&"enemy"]:
		var a := SpitProjectile.new()
		var b := SpitProjectile.new()
		a.team=team
		b.team=team
		root.add_child(a)
		root.add_child(b)
		var parts := a.find_children("*","MeshInstance3D",true,false)
		for part: MeshInstance3D in parts:
			var peer: MeshInstance3D = b.get_node(a.get_path_to(part))
			if part.mesh!=peer.mesh:
				printerr("FAIL repeated projectile geometry: ",team," ",part.name)
				failures+=1
			if team==&"player" and part.material_override==peer.material_override:
				printerr("FAIL player shots share animated material")
				failures+=1
			if team==&"enemy" and part.material_override!=peer.material_override:
				printerr("FAIL immutable enemy material was rebuilt")
				failures+=1
		a._process(0.1)
		if b._visual_age != 0.0:
			printerr("FAIL projectile animation state leaked")
			failures+=1
		a.free()
		b.free()
	print("PROJECTILE_CACHE ","PASS" if failures==0 else "FAIL")
	quit(0 if failures==0 else 1)
