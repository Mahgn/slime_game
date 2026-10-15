extends SceneTree

# Geometry-first audit of the roof itself. Camera-to-player rays cannot detect
# unsupported roof sheets; inspect closed volumes, visible support and joints.
const SCENE := "res://scenes/dungeon/dungeon_route.tscn"
const ROOT_OUT := "res://output/room_wall_caps_2026_10_14/"
const CAMERA_OFFSET := Vector3(12.0, 13.9, 12.0)
const TOP_Y := 3.4
var out := ROOT_OUT + "candidate/"
var capture := false
var focus := false
var level: SlimeKeepersWorld
var checks: Array[Dictionary] = []
var joints: Array[Dictionary] = []
var snapshots: Array[Dictionary] = []
var sections: Array[Dictionary] = []
var supports: Array[Dictionary] = []
var openings: Array[Rect2] = []
var finished := false

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--capture": capture = true
		if arg == "--focus": focus = true
		if arg.begins_with("--output=res://output/"): out = arg.trim_prefix("--output=").trim_suffix("/") + "/"
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out + "images"))
	SlimeGameSettings.current().load_settings(out + "settings.cfg")
	seed(4873)
	create_timer(240.0, true).timeout.connect(func() -> void: _check(false, "bounded 240 s watchdog"); _finish())
	if DisplayServer.get_name() == "headless": capture = false
	else:
		root.size = Vector2i(1600, 900)
		DisplayServer.window_set_size(root.size)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	change_scene_to_file(SCENE)
	await _ticks(25)
	level = current_scene as SlimeKeepersWorld
	for tick: int in 900:
		if is_instance_valid(level) and not level._transitioning: break
		await _ticks(1)
	_check(is_instance_valid(level) and not level._transitioning, "real dungeon initializes before roof audit")
	if not is_instance_valid(level): _finish(); return
	level.set_physics_process(false)
	level.player.set_physics_process(false)
	level.player.presentation.set_process(false)
	level.hud.hide()
	for id: String in level.rooms:
		for actor: Node3D in level.alive_enemies(id): actor.set_physics_process(false)
	for gate: Node in level.get("gates"): gate.set_physics_process(false)
	sections.assign(level.geometry.cutaway.structural_sections)
	level.geometry.cutaway.set_enabled(false)
	_build_openings()
	_inventory()
	_build_joints()
	_check(not joints.is_empty(), "physical wall endpoints supply the joint capture list")
	var baseline_signature := _physics_signature()
	# Audit every actual visibility region separately, including narrow passages.
	_audit_state("all-restored")
	for id: String in level.rooms:
		_set_reveal(level.rooms[id].center)
		_audit_state("room-" + id)
	for link: Dictionary in level.connections:
		_set_reveal((link.path[0] + link.path[-1]) * 0.5)
		_audit_state("passage-" + String(link.a) + "-" + String(link.b))
	# Close views are aimed at the architecture, with the same fixed camera basis.
	for index: int in joints.size():
		if focus and index % maxi(1, joints.size() / 12) != 0: continue
		var joint: Dictionary = joints[index]
		level.geometry.cutaway.set_enabled(false)
		_frame_joint(joint.position)
		await _shot("joint-%03d-restored" % index)
		for owner: String in joint.rooms:
			_set_reveal(level.rooms[owner].center)
			_frame_joint(joint.position)
			await _shot("joint-%03d-" % index + owner)
	await _style_and_partial()
	level.geometry.cutaway.set_enabled(false)
	_audit_state("final-restored")
	_check(_physics_signature() == baseline_signature, "roof reveal F6 and restore leave all structural collision unchanged")
	_finish()

func _build_openings() -> void:
	for room: Dictionary in level.rooms.values():
		var half: Vector2 = room.half - Vector2.ONE * 0.45
		openings.append(Rect2(Vector2(room.center.x, room.center.z) - half, half * 2.0))
	for link: Dictionary in level.connections:
		var a := Vector2(link.path[0].x, link.path[0].z)
		var b := Vector2(link.path[-1].x, link.path[-1].z)
		var direction := (b-a).normalized()
		a -= direction * 0.45
		b += direction * 0.45
		var across := Vector2(absf(direction.y), absf(direction.x)) * (float(link.width)-0.9) * 0.5
		openings.append(Rect2(a.min(b)-across, a.max(b)-a.min(b)+across*2.0))

func _inventory() -> void:
	_check(_whole_roof_hidden(), "no visible UnifiedBuildingMass or ContinuousBuildingCrown whole plane")
	var legacy: Node3D = level.geometry.get("building_crown") as Node3D
	if is_instance_valid(legacy):
		var previous: bool = legacy.visible
		legacy.show()
		_check(not _whole_roof_hidden(), "negative control detects the former unsupported whole roof when made visible")
		legacy.visible = previous
	var caps: Array[MeshInstance3D] = []
	for index: int in sections.size():
		var section: Dictionary = sections[index]
		var cap: MeshInstance3D = section.get("cap_mesh") as MeshInstance3D
		var valid: bool = is_instance_valid(cap) and cap.mesh is BoxMesh
		if valid:
			caps.append(cap)
			var bounds := _world_bounds(cap)
			valid = cap.name == &"OwnedWallCap" and section.node.is_ancestor_of(cap) and _closed_mesh(cap.mesh)
			valid = valid and absf(bounds.position.y - 3.22) < 0.002 and absf(bounds.end.y - TOP_Y) < 0.002
			valid = valid and absf((cap.mesh as BoxMesh).size.z - 0.9) < 0.002
		_check(valid, "closed 18 cm cap attached to actual wall section %d" % index)
		for mesh: MeshInstance3D in section.node.find_children("*", "MeshInstance3D", true, false):
			if mesh == cap or mesh.get_parent() != section.node or mesh.mesh == null: continue
			var bounds := _world_bounds(mesh)
			# Real bulk masonry reaches almost from the floor to the cap underside.
			# Mounted props and the cap itself cannot count as their own support.
			if bounds.position.y <= float(section.get("base_height",0.0))+0.1 and bounds.end.y >= 3.16:
				supports.append({"mesh":mesh,"bounds":bounds,"body":section.body})
	_check(caps.size() == sections.size() and not supports.is_empty(), "every section has a cap and bulk masonry support is discoverable")
	var unexpected: Array[String] = []
	for mesh: MeshInstance3D in level.geometry.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree() or mesh.mesh == null or caps.has(mesh): continue
		var bounds := _world_bounds(mesh)
		if bounds.end.y < 3.38 or bounds.position.y > 3.42: continue
		for triangle: PackedVector3Array in _triangles(mesh):
			var center: Vector3 = (triangle[0]+triangle[1]+triangle[2])/3.0
			var cross: Vector3 = (triangle[1]-triangle[0]).cross(triangle[2]-triangle[0])
			if absf(center.y-TOP_Y)<0.002 and absf(cross.normalized().y)>0.99 and cross.length()>0.02 and not _inside_opening(Vector2(center.x,center.z)):
				unexpected.append(String(mesh.get_path()))
				break
	_check(unexpected.is_empty(), "no unregistered roof-height sheets outside playable interiors: "+str(unexpected))
	var foundation := level.geometry.get_node_or_null("ContinuousCutawayFoundation") as MeshInstance3D
	var ground_valid := is_instance_valid(foundation) and foundation.mesh is ArrayMesh
	if ground_valid:
		var bounds := _world_bounds(foundation)
		ground_valid = _closed_mesh(foundation.mesh) and absf(bounds.position.y+0.75)<0.002 and absf(bounds.end.y-0.18)<0.002
		var intrusions := 0
		for triangle: PackedVector3Array in _triangles(foundation):
			if absf(triangle[0].y-0.18)>0.002 or absf(triangle[1].y-0.18)>0.002 or absf(triangle[2].y-0.18)>0.002: continue
			var polygon := PackedVector2Array([Vector2(triangle[0].x,triangle[0].z),Vector2(triangle[1].x,triangle[1].z),Vector2(triangle[2].x,triangle[2].z)])
			for opening: Rect2 in openings:
				var inner := opening.grow(-0.004)
				var rectangle := PackedVector2Array([inner.position,Vector2(inner.end.x,inner.position.y),inner.end,Vector2(inner.position.x,inner.end.y)])
				for overlap: PackedVector2Array in Geometry2D.intersect_polygons(polygon,rectangle):
					if _area(overlap)>0.0001: intrusions += 1
		_check(intrusions == 0, "continuous low infill has no triangle area inside any room or passage opening")
	_check(ground_valid, "continuous low infill is a closed grounded volume from -0.75 to +0.18 m")

func _build_joints() -> void:
	var by_position: Dictionary = {}
	for index: int in sections.size():
		var section: Dictionary = sections[index]
		var shape_node := section.body.get_child(0) as CollisionShape3D
		if shape_node == null or not shape_node.shape is BoxShape3D: continue
		var box := shape_node.shape as BoxShape3D
		for sign_value: float in [-1.0,1.0]:
			var position := shape_node.to_global(Vector3(sign_value*box.size.x*0.5,0,0))
			position.y = 1.7
			var key := "%0.2f,%0.2f" % [position.x,position.z]
			if not by_position.has(key): by_position[key] = {"position":position,"sections":[],"rooms":[]}
			var joint: Dictionary = by_position[key]
			joint.sections.append(index)
			for id: String in section.get("room_ids",[]):
				if level.rooms.has(id) and not joint.rooms.has(id): joint.rooms.append(id)
	for key: String in by_position: joints.append(by_position[key])

func _audit_state(label: String) -> void:
	var unsupported: Array[Dictionary] = []
	var disagreement: Array[String] = []
	var visible_caps := 0
	for section: Dictionary in sections:
		var cap: MeshInstance3D = section.get("cap_mesh") as MeshInstance3D
		if not is_instance_valid(cap): continue
		if cap.is_visible_in_tree() != section.node.is_visible_in_tree(): disagreement.append(String(cap.get_path()))
		if not cap.is_visible_in_tree(): continue
		visible_caps += 1
		var box := cap.mesh as BoxMesh
		if box == null: continue
		var count := maxi(2,int(ceil(box.size.x/0.4)))
		for along: int in count+1:
			for across: float in [-0.98,0.0,0.98]:
				var point := cap.to_global(Vector3(lerpf(-box.size.x*0.5+0.003,box.size.x*0.5-0.003,float(along)/count),-box.size.y*0.5-0.035,across*box.size.z*0.5))
				var supported := false
				for support: Dictionary in supports:
					if support.mesh.is_visible_in_tree() and (support.bounds as AABB).grow(0.018).has_point(point): supported = true; break
				if not supported: unsupported.append({"cap":String(cap.get_path()),"point":point})
	_check(_whole_roof_hidden(), "whole roof stays absent: "+label)
	_check(disagreement.is_empty(), "cap and parent masonry visibility agree: "+label)
	_check(unsupported.is_empty(), "every visible cap underside has visible bulk-wall support: "+label)
	snapshots.append({"label":label,"visible_caps":visible_caps,"unsupported":unsupported,"visibility_disagreement":disagreement})

func _set_reveal(position: Vector3, delta: float = 1.0) -> void:
	level.geometry.cutaway.set_enabled(false)
	level._reset_position(position)
	level.geometry.cutaway.set_enabled(true)
	level.geometry.cutaway.advance(position,delta)

func _frame_joint(position: Vector3) -> void:
	var camera: Camera3D = level.player.presentation.camera
	camera.size = 6.0
	camera.global_position = position + CAMERA_OFFSET
	camera.look_at(position)

func _style_and_partial() -> void:
	var style: Node = level.get("ink_style")
	var original: int = style.mode
	for id: String in ["entry","junction","cistern","armory","summit"]:
		_set_reveal(level.rooms[id].center,0.15)
		_audit_state("partial-"+id)
		_frame_joint(level.rooms[id].center + Vector3(0,1.7,0))
		await _shot("partial-"+id)
		_set_reveal(level.rooms[id].center)
		var event := InputEventKey.new()
		event.physical_keycode = KEY_F6
		event.pressed = true
		Input.parse_input_event(event)
		await _ticks(2)
		event.pressed = false
		Input.parse_input_event(event)
		_check(style.mode != original, "actual F6 changes style: "+id)
		_audit_state("f6-"+id)
		await _shot("f6-"+id)
		style.set_mode(original)

func _whole_roof_hidden() -> bool:
	var legacy: Node3D = level.geometry.get("building_crown") as Node3D
	if is_instance_valid(legacy) and legacy.is_visible_in_tree(): return false
	for mesh: MeshInstance3D in level.geometry.find_children("*ContinuousBuildingCrown*", "MeshInstance3D", true, false):
		if mesh.is_visible_in_tree(): return false
	return true

func _inside_opening(point: Vector2) -> bool:
	for opening: Rect2 in openings:
		if opening.has_point(point): return true
	return false

func _world_bounds(mesh: MeshInstance3D) -> AABB:
	var local := mesh.mesh.get_aabb()
	var result := AABB(mesh.to_global(local.position),Vector3.ZERO)
	for vertex: int in 8: result = result.expand(mesh.to_global(local.get_endpoint(vertex)))
	return result

func _triangles(mesh: MeshInstance3D) -> Array[PackedVector3Array]:
	var result: Array[PackedVector3Array] = []
	for surface: int in mesh.mesh.get_surface_count():
		var arrays: Array = mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var count: int = indices.size() if not indices.is_empty() else vertices.size()
		for cursor: int in range(0,count,3):
			var triangle := PackedVector3Array()
			for corner: int in 3: triangle.append(mesh.to_global(vertices[indices[cursor+corner] if not indices.is_empty() else cursor+corner]))
			result.append(triangle)
	return result

func _closed_mesh(mesh: Mesh) -> bool:
	var edges: Dictionary = {}
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var count: int = indices.size() if not indices.is_empty() else vertices.size()
		for cursor: int in range(0,count,3):
			var keys: Array[String] = []
			for corner: int in 3:
				var point := vertices[indices[cursor+corner] if not indices.is_empty() else cursor+corner]
				keys.append("%d,%d,%d" % [roundi(point.x*10000),roundi(point.y*10000),roundi(point.z*10000)])
			for edge: int in 3:
				var pair: Array[String] = [keys[edge],keys[(edge+1)%3]]
				pair.sort()
				var key := pair[0]+"/"+pair[1]
				edges[key] = int(edges.get(key,0))+1
	return not edges.is_empty() and edges.values().all(func(value: int) -> bool: return value == 2)

func _area(polygon: PackedVector2Array) -> float:
	var sum := 0.0
	for index: int in polygon.size(): sum += polygon[index].cross(polygon[(index+1)%polygon.size()])
	return absf(sum)*0.5

func _physics_signature() -> Dictionary:
	var result: Dictionary = {}
	for body: StaticBody3D in level.geometry.find_children("*", "StaticBody3D", true, false):
		var shapes: Array = []
		for child: Node in body.get_children():
			if child is CollisionShape3D: shapes.append([child.disabled,child.shape.get_rid(),child.transform])
		result[String(body.get_path())] = [body.collision_layer,body.collision_mask,body.global_transform,shapes]
	return result

func _shot(label: String) -> void:
	if not capture: return
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(out+"images/"+label+".png")
	_check(error == OK, "native closeup "+label)

func _ticks(count: int) -> void:
	for tick: int in count:
		if is_instance_valid(level) and is_instance_valid(level._pause_panel) and level._pause_panel.visible: level._resume_game()
		paused = false
		await physics_frame
		await process_frame

func _check(ok: bool, label: String) -> void:
	checks.append({"pass":ok,"check":label})
	print("PASS " if ok else "FAIL ",label)

func _finish() -> void:
	if finished: return
	finished = true
	var failures: int = checks.filter(func(item: Dictionary) -> bool: return not item.pass).size()
	var report: Dictionary = {"status":"PASS" if failures == 0 else "FAIL","focus_subset":focus,"checks":checks,"joints":joints,"states":snapshots,"renderer":RenderingServer.get_current_rendering_method(),"scope":"Closed-volume and visible-support audit of actual cap/foundation geometry. Native closeups use fixed isometric basis, camera size 6 m and no HUD. Static fixtures, no traversal/FPS/visual acceptance claim. No reliance on camera-to-hero rays to certify roof pixels."}
	FileAccess.open(out+"results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ROOM_WALL_CAPS_RESULT checks=",checks.size()," failures=",failures," joints=",joints.size())
	quit(1 if failures else 0)
