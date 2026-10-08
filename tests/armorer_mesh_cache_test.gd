extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(10,true).timeout.connect(func(): printerr("FAIL cache test timeout"); quit(2))
	var first := ArmorerVisual.new()
	var second := ArmorerVisual.new()
	var start := Time.get_ticks_usec()
	root.add_child(first)
	var first_us := Time.get_ticks_usec()-start
	start=Time.get_ticks_usec()
	root.add_child(second)
	print("ARMORER_BUILD_US first=",first_us," reused=",Time.get_ticks_usec()-start)
	var failed := false
	var meshes := first.find_children("*","MeshInstance3D",true,false)
	var peers := second.find_children("*","MeshInstance3D",true,false)
	if meshes.size()!=peers.size():
		printerr("FAIL model part count changed")
		quit(1)
		return
	for index in meshes.size():
		var mesh: MeshInstance3D = meshes[index]
		var peer: MeshInstance3D = peers[index]
		if mesh.mesh != peer.mesh:
			printerr("FAIL geometry was rebuilt: ",mesh.name)
			failed=true
	var color := second._shell_material.albedo_color
	first.animate(0.1,Vector3.FORWARD,true)
	if first._shell_material == second._shell_material or second._shell_material.albedo_color != color:
		printerr("FAIL hit flash leaks between enemies")
		failed=true
	first.set_phase(&"shell")
	first.animate(0.1,Vector3.ZERO,false)
	if first._plates[0].transform == second._plates[0].transform:
		printerr("FAIL animation state not independent")
		failed=true
	print("ARMORER_MESH_CACHE ","FAIL" if failed else "PASS"," shared_meshes=",meshes.size()," independent_materials_and_pose=true")
	first.free()
	second.free()
	quit(1 if failed else 0)
