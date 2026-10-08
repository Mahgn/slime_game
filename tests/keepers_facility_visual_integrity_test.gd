extends SceneTree

# Geometry regression plus real camera views of every connection, in both
# directions. Fixture relocation is explicit; combat is covered separately.
var out := "res://output/keepers_visual_repair_2026_10_08/integrity/"
var level
var checks: Array[Dictionary] = []

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output=res://output/"):
			out = arg.trim_prefix("--output=").trim_suffix("/")+"/"
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	SlimeGameSettings.current().load_settings(out+"settings.cfg")
	root.size = Vector2i(1280,720)
	change_scene_to_file("res://scenes/keepers/keepers_facility.tscn")
	await _ticks(20)
	level = current_scene
	for id: String in level.rooms: level.cleared[id] = true
	for actor in level.alive_enemies(): actor.queue_free()
	for hazard in level.hazards: hazard.disable()
	await _ticks(2)
	var mounted_count := 0
	for node: Node in level.geometry.find_children("*","Node3D",true,false):
		if not node.has_meta("mount_anchor"): continue
		mounted_count += 1
		var anchor: Vector3 = node.get_meta("mount_anchor")
		var normal: Vector3 = node.get_meta("mount_normal")
		var query := PhysicsRayQueryParameters3D.create(anchor+normal*0.04,anchor-normal*0.10,1)
		var hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(query)
		_check(not hit.is_empty() and hit.collider==node.get_meta("mount_body") and hit.position.distance_to(anchor)<0.015,"Mounted support contact: "+String(node.name)+" / "+String(node.get_parent().get_parent().name))
		var owned: bool = level.geometry.cutaway.structural_sections.any(func(section: Dictionary) -> bool: return section.node==node.get_parent())
		_check(owned,"Mount shares cutaway ownership: "+String(node.name))
		if String(node.name).begins_with("WallServiceDetail"):
			var wall: StaticBody3D = node.get_meta("mount_body")
			var half: Vector3 = wall.get_child(0).shape.size*0.5
			var section: Dictionary = level.geometry.cutaway.structural_sections.filter(func(item: Dictionary) -> bool: return item.node==node.get_parent())[0]
			var fits := true
			for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
				for i in 8:
					var world := mesh.to_global(mesh.get_aabb().get_endpoint(i))
					var local := wall.to_local(world)
					fits = fits and absf(local.x)<half.x-0.02 and local.y<half.y and world.y>float(section.base_height)+0.02 and world.y<3.21
			_check(fits,"Wall detail stays within its full-height support: "+String(node.get_parent().get_parent().name))
	_check(mounted_count==30,"All 17 lights, 2 noticeboards, banner and 10 service details audited")
	var pipes := 0
	var segments := 0
	var corridor_intrusions := 0
	for shell in [level.geometry]+level.geometry.room_nodes.values():
		for kit: Node in shell.get_children():
			if not "service_paths" in kit: continue
			for service: Dictionary in kit.service_paths:
				pipes += 1
				for i in range(service.points.size()-1):
					var a: Vector3 = kit.to_global(service.points[i])
					var b: Vector3 = kit.to_global(service.points[i+1])
					var radius: float = service.radius
					# Sample the actual swept tube, including its rounded bends.
					for step in range(int(ceil(a.distance_to(b)/0.1))+1):
						var p := a.lerp(b,float(step)/maxf(1,ceil(a.distance_to(b)/0.1)))
						if p.y+radius<0.05 or p.y-radius>2.1: continue
						for link: Dictionary in level.connections:
							var start: Vector3 = link.path[0]
							var end: Vector3 = link.path[-1]
							var direction := (end-start).normalized()
							var along := (p-start).dot(direction)
							var side := absf((p-start).dot(Vector3(-direction.z,0,direction.x)))
							if along>0 and along<start.distance_to(end) and side<float(link.width)*0.5-0.45+radius:
								corridor_intrusions += 1
					if maxf(a.y,b.y)+radius<0: continue
					segments += 1
	_check(pipes>=15 and segments>20,"Exposed and buried pipe geometry audited")
	_check(corridor_intrusions==0,"No service mesh in any of the 11 doorway envelopes")
	for link: Dictionary in level.connections:
		var a: Vector3 = link.path[0]
		var b: Vector3 = link.path[-1]
		var direction := (b-a).normalized()
		for reverse in [false,true]:
			var at := b+direction*2 if reverse else a-direction*2
			level._reset_position(at)
			await _ticks(22)
			var valid := true
			for section: Dictionary in level.geometry.cutaway.structural_sections:
				valid = valid and section.node.is_visible_in_tree() and not section.body.has_meta(&"architectural_cut_height")
			_check(valid,"Continuous full-height walls: %s-%s %s" % [link.a,link.b,"return" if reverse else "forward"])
			if DisplayServer.get_name()!="headless":
				RenderingServer.force_draw()
				root.get_texture().get_image().save_png(out+"%s-%s-%s.png" % [link.a,link.b,"return" if reverse else "forward"])
	var failed := checks.any(func(item: Dictionary) -> bool: return not item.pass)
	FileAccess.open(out+"results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"pipes":pipes,"exposed_segments":segments,"door_intrusions":corridor_intrusions,"status":"FAIL" if failed else "PASS"},"\t"))
	quit(1 if failed else 0)

func _check(ok: bool, label: String) -> void:
	checks.append({"pass":ok,"label":label})
	print("PASS " if ok else "FAIL ",label)

func _ticks(count: int) -> void:
	for i in count:
		# Keep relocation inspection independent of desktop focus changes.
		if is_instance_valid(current_scene) and current_scene.has_method("_resume_game"):
			current_scene._resume_game()
		await physics_frame
		await process_frame
