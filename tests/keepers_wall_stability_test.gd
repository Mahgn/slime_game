extends SceneTree

var out := "res://output/keepers_wall_stability_2026_10_08/baseline/"
var level
var baseline := false
var changes := 0
var previous: Array[bool] = []
var bounds: Array[AABB] = []
var checks: Array[Dictionary] = []

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output=res://output/"): out=arg.trim_prefix("--output=").trim_suffix("/")+"/"
		if arg=="--baseline": baseline=true
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out+"motion"))
	SlimeGameSettings.current().load_settings(out+"settings.cfg")
	root.size=Vector2i(1280,720)
	change_scene_to_file("res://scenes/keepers/keepers_facility.tscn")
	await _ticks(20)
	level=current_scene
	if not is_instance_valid(level) or not is_instance_valid(level.geometry.cutaway):
		push_error("FAIL wall stability: facility did not initialize")
		quit(1)
		return
	for id: String in level.rooms: level.cleared[id]=true
	for enemy in level.alive_enemies(): enemy.queue_free()
	for hazard in level.hazards: hazard.disable()
	await _building_checks()
	for shell in [level.geometry]+level.geometry.room_nodes.values():
		for span: Dictionary in shell.masonry_spans:
			var box := AABB()
			var first := true
			for mesh: MeshInstance3D in span.lower.find_children("*","MeshInstance3D",false,false):
				var transformed: AABB=mesh.global_transform*mesh.get_aabb()
				box=transformed if first else box.merge(transformed)
				first=false
			bounds.append(box)
	var overlaps: Array=[]
	for i in bounds.size():
		for j in range(i+1,bounds.size()):
			var overlap := bounds[i].intersection(bounds[j])
			if overlap.size.x>0.002 and overlap.size.y>0.05 and overlap.size.z>0.002:
				overlaps.append({"a":i,"b":j,"position":overlap.position,"size":overlap.size})
	_check(overlaps.is_empty(),"Masonry skins have no intersecting volumes across rooms, corners or passage cheeks")
	level._reset_position(Vector3(-6.3,0,13))
	await _ticks(20)
	previous=_visibility()
	var frame := 0
	# Repeat the doorway movement from the user's example through ordinary
	# movement actions; no teleport across the sampled threshold.
	for target: Vector3 in [Vector3(-10.6,0,13),Vector3(-6.3,0,13),Vector3(-10.6,0,13),Vector3(-6.3,0,13)]:
		var arrived := false
		for tick in 130:
			var delta: Vector3=target-level.player.global_position
			delta.y=0
			if delta.length()<0.18:
				arrived=true
				break
			var axes: Vector2=level.player.controls.world_direction_to_screen_axes(delta.normalized())
			Input.action_press(&"move_right",maxf(axes.x,0))
			Input.action_press(&"move_left",maxf(-axes.x,0))
			Input.action_press(&"move_back",maxf(axes.y,0))
			Input.action_press(&"move_forward",maxf(-axes.y,0))
			await _ticks(1)
			var state := _visibility()
			for i in state.size():
				if state[i]!=previous[i]: changes+=1
			previous=state
			if frame%4==0 and DisplayServer.get_name()!="headless":
				RenderingServer.force_draw()
				root.get_texture().get_image().save_png(out+"motion/%04d.png"%(frame/4))
			frame+=1
		_check(arrived,"Physical doorway crossing "+str(target))
	for action in [&"move_right",&"move_left",&"move_back",&"move_forward"]: Input.action_release(action)
	_check(changes==0,"No wall visibility changes during repeated threshold crossings")
	# Check all rooms and a jump-height pose without depending on local timing.
	var stable := _visibility()
	for room: Dictionary in level.rooms.values():
		for height in [0.0,1.4]:
			level.player.global_position=room.spawn+Vector3.UP*height
			level.geometry.cutaway.update_view(level.player,level.player.presentation.camera)
			_check(_visibility()==stable,"Building silhouette independent of room/jump "+room.title+" "+str(height))
	var failed: bool=checks.any(func(c: Dictionary)->bool:return not c.pass)
	FileAccess.open(out+"results.json",FileAccess.WRITE).store_string(JSON.stringify({"status":"BASELINE" if baseline else ("FAIL" if failed else "PASS"),"checks":checks,"overlaps":overlaps,"wall_visibility_changes":changes,"sampled_physics_frames":frame,"wall_spans":bounds.size()},"\t"))
	print("WALL_STABILITY overlaps=",overlaps.size()," visibility_changes=",changes," frames=",frame)
	quit(0 if baseline else (1 if failed else 0))

func _building_checks() -> void:
	var crown: Node3D=level.geometry.building_crown
	var mesh: ArrayMesh=crown.mesh_instance.mesh
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var uniform := true
	for i in vertices.size():
		if normals[i].y>0.9:
			uniform=uniform and is_equal_approx(vertices[i].y,3.4)
	_check(uniform,"Every horizontal crown triangle shares the same 3.4 m plane")
	var wall_heights := true
	for wall: StaticBody3D in level.geometry.find_children("FullStructuralWall*","StaticBody3D",true,false):
		var shape: BoxShape3D=wall.get_child(0).shape
		wall_heights=wall_heights and is_equal_approx(wall.global_position.y+shape.size.y*0.5,3.4) and not wall.has_meta(&"architectural_cut_height")
	_check(wall_heights,"Front, rear and raised-floor walls all meet the common crown")
	var services_clear := true
	for slot: Rect2 in crown.service_slots:
		for playable: Rect2 in crown.playable_openings:
			services_clear=services_clear and not slot.grow(0.25).intersects(playable)
	_check(services_clear,"All recessed service wells stay inside nonplayable masonry")
	var service_bounds := true
	for instance: MeshInstance3D in crown.get_node("RecessedServiceWells").find_children("*","MeshInstance3D",true,false):
		var aabb: AABB=instance.global_transform*instance.get_aabb()
		service_bounds=service_bounds and aabb.end.y<3.401 and aabb.position.y>2.7
	_check(service_bounds,"Grating and supported pipes stay below the common top plane")
	var probe := StaticBody3D.new()
	probe.collision_layer=512; probe.collision_mask=0
	var collision := CollisionShape3D.new()
	collision.shape=mesh.create_trimesh_shape()
	probe.add_child(collision); level.add_child(probe)
	await _ticks(2)
	var missing := 0
	for cell: Rect2 in crown.solid_cells:
		for uv: Vector2 in [Vector2(0.5,0.5),Vector2(0.05,0.05),Vector2(0.95,0.95)]:
			var point := cell.position+cell.size*uv
			if not _crown_hit(point):
				missing+=1
				if missing<10: print("CROWN_MISSING ",point," cell=",cell)
	print("CROWN_COVERAGE cells=",crown.solid_cells.size()," missing=",missing)
	_check(missing==0,"Actual crown mesh has no holes between room shells or at cell seams")
	for link: Dictionary in level.connections:
		var a: Vector3=link.path[0]; var b: Vector3=link.path[-1]
		var side := Vector3(-(b-a).normalized().z,0,(b-a).normalized().x)
		var clear := true
		for along in [0.0,0.5,1.0]:
			for across in [-1.2,0.0,1.2]:
				var p: Vector3=a.lerp(b,along)+side*across
				clear=clear and not _crown_hit(Vector2(p.x,p.z))
		_check(clear,"Crown leaves the entire doorway open: "+link.a+" / "+link.b)
	probe.queue_free()
	await _ticks(2)

func _crown_hit(point: Vector2) -> bool:
	var from := Vector3(point.x,4.0,point.y)
	var to := Vector3(point.x,3.0,point.y)
	var query := PhysicsRayQueryParameters3D.create(from,to,512)
	return not level.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _visibility() -> Array[bool]:
	var states: Array[bool]=[]
	for section: Dictionary in level.geometry.cutaway.structural_sections: states.append(section.node.visible)
	return states

func _check(ok: bool,label: String) -> void:
	checks.append({"pass":ok,"label":label})
	print(("BASELINE " if baseline else ("PASS " if ok else "FAIL "))+label+" "+str(ok))

func _ticks(count: int) -> void:
	for i in count:
		if is_instance_valid(current_scene) and current_scene.has_method("_resume_game"): current_scene._resume_game()
		await physics_frame
		await process_frame
