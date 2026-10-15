extends SceneTree

# Static native diagnostic atlas. Placement is a fixture, not a traversal test.
# Baseline means the rejected reveal implementation before cleanup, still enabled.
const SCENE := "res://scenes/dungeon/dungeon_route.tscn"
const ROOT_OUT := "res://output/room_wall_cleanup_2026_10_14/"
const ROOM_IDS: Array[String] = ["entry", "spring", "barracks", "junction", "furnace", "cistern", "hub", "armory", "garden", "archive", "summit"]
var out := ROOT_OUT + "candidate/"
var baseline := false
var capture := false
var focus := false
var level: SlimeKeepersWorld
var checks: Array[Dictionary] = []
var probes: Array[Dictionary] = []
var inventory: Array[Dictionary] = []
var snapshots: Array[Dictionary] = []
var wall_by_rid: Dictionary = {}
var physics_before: Dictionary = {}
var protected_meshes: Array[MeshInstance3D] = []
var finished := false

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--baseline": baseline = true
		if arg == "--capture": capture = true
		if arg == "--focus": focus = true
		if arg.begins_with("--output=res://output/"): out = arg.trim_prefix("--output=").trim_suffix("/") + "/"
	if baseline and out == ROOT_OUT + "candidate/": out = ROOT_OUT + "baseline/"
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out + "images"))
	SlimeGameSettings.current().load_settings(out + "settings.cfg")
	seed(4873)
	create_timer(180.0, true).timeout.connect(func() -> void: _check(false, "bounded 180 s watchdog"); _finish())
	if DisplayServer.get_name() == "headless": capture = false
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		root.size = Vector2i(1280, 720)
		DisplayServer.window_set_size(root.size)
	change_scene_to_file(SCENE)
	await _ticks(25)
	level = current_scene as SlimeKeepersWorld
	for tick: int in 900:
		if is_instance_valid(level) and not level._transitioning: break
		await _ticks(1)
	_check(is_instance_valid(level) and not level._transitioning and is_instance_valid(level.geometry.cutaway), "actual dungeon and cutaway initialize and finish warmup")
	if not is_instance_valid(level) or not is_instance_valid(level.geometry.cutaway): _finish(); return
	for id: String in level.rooms:
		for actor: Node3D in level.alive_enemies(id):
			actor.set_physics_process(false)
			(actor as CollisionObject3D).collision_layer = 0
	# Every probe keeps its intended position, even where a crate or slope exists.
	# This atlas checks camera/wall coverage, never claims physical reachability.
	level.player.set_physics_process(false)
	for gate: Node3D in level.get("gates"):
		gate.set_physics_process(false)
		for mesh: MeshInstance3D in gate.find_children("*", "MeshInstance3D", true, false): protected_meshes.append(mesh)
	for mesh: MeshInstance3D in level.get("membrane").find_children("*", "MeshInstance3D", true, false): protected_meshes.append(mesh)
	physics_before = _physics_signature()
	for section: Dictionary in level.geometry.cutaway.structural_sections:
		if is_instance_valid(section.get("body")): wall_by_rid[section.body.get_rid()] = section
	_build_probes()
	_inventory_sections()
	_check(level.rooms.size() == 11 and level.connections.size() == 13, "all authored rooms and connections included")
	_check(probes.size() == 181, "88 room edge and corner probes plus 91 passage probes and two reported locations")
	for probe: Dictionary in probes:
		if focus and not String(probe.label) in ["room-entry-se", "room-spring-ne", "room-barracks-sw", "room-junction-se", "room-furnace-se", "room-cistern-sw", "room-hub-se", "room-armory-se", "room-garden-sw", "room-archive-ne", "room-summit-se", "passage-entry-barracks-a-right", "passage-entry-junction-a-left", "passage-junction-furnace-a-left", "passage-furnace-cistern-middle", "service-membrane", "entry-junction-threshold"]: continue
		await _probe(probe)
	await _style_probe()
	level.geometry.cutaway.set_enabled(false)
	_check(_physics_signature() == physics_before, "all geometry collision shapes layers masks and transforms unchanged across probes and F6")
	var gameplay_visible: bool = not protected_meshes.is_empty()
	for mesh: MeshInstance3D in protected_meshes: gameplay_visible = gameplay_visible and mesh.is_visible_in_tree()
	_check(gameplay_visible and bool(level.get("membrane").get("intact")), "gameplay gates and intact acid membrane remain visible")
	if not baseline:
		var restored := true
		var foundations_present := true
		for section: Dictionary in level.geometry.cutaway.structural_sections:
			for mesh: MeshInstance3D in section.get("fade_meshes", []): restored = restored and mesh.visible
			if is_instance_valid(section.get("foundation_mesh")): foundations_present = foundations_present and section.foundation_mesh.visible
		_check(restored, "disabling reveal restores every original wall and mounted mesh")
		_check(foundations_present, "continuous foundation remains grounded when original walls restore")
	_finish()

func _build_probes() -> void:
	for id: String in ROOM_IDS:
		var room: Dictionary = level.rooms[id]
		var half: Vector2 = room.half - Vector2.ONE * 1.15
		for edge: Dictionary in [{"tag":"nw","v":Vector2(-1,-1)}, {"tag":"ne","v":Vector2(1,-1)}, {"tag":"se","v":Vector2(1,1)}, {"tag":"sw","v":Vector2(-1,1)}, {"tag":"n","v":Vector2(0,-1)}, {"tag":"e","v":Vector2(1,0)}, {"tag":"s","v":Vector2(0,1)}, {"tag":"w","v":Vector2(-1,0)}]:
			var xz: Vector2 = half * edge.v
			var at: Vector3 = room.center + Vector3(xz.x, 1.0 if id == "summit" and xz.y < -2.49 else 0.0, xz.y)
			probes.append({"label":"room-"+id+"-"+String(edge.tag), "position":at, "rooms":[id], "kind":"room-edge-corner"})
	for link: Dictionary in level.connections:
		var a: Vector3 = link.path[0]
		var b: Vector3 = link.path[-1]
		var along: Vector3 = (b-a).normalized()
		var across := Vector3(-along.z,0,along.x)
		var tag: String = "passage-" + String(link.a) + "-" + String(link.b)
		for side: Dictionary in [{"tag":"a","at":a-along*0.45}, {"tag":"middle","at":(a+b)*0.5}, {"tag":"b","at":b+along*0.45}]:
			probes.append({"label":tag+"-"+String(side.tag), "position":side.at, "rooms":[String(link.a),String(link.b)], "kind":"passage-centerline"})
		# Shoulder positions directly test the two jambs, not only an easy central ray.
		for end: Dictionary in [{"tag":"a","at":a-along*0.45}, {"tag":"b","at":b+along*0.45}]:
			for sign_value: int in [-1,1]:
				probes.append({"label":tag+"-"+String(end.tag)+("-left" if sign_value<0 else "-right"), "position":end.at+across*(float(link.width)*0.5-0.55)*sign_value, "rooms":[String(link.a),String(link.b)], "kind":"passage-jamb"})
	probes.append({"label":"service-membrane","position":Vector3(0.5,0,-18),"rooms":["furnace","cistern"],"kind":"gameplay-membrane-preserved"})
	probes.append({"label":"entry-junction-threshold","position":Vector3(0,0,7.7),"rooms":["entry","junction"],"kind":"reported-defect"})

func _inventory_sections() -> void:
	var mounts: Array[Node] = []
	for child: Node in level.geometry.find_children("*", "Node3D", true, false):
		if child.has_meta("mount_body"): mounts.append(child)
	for section: Dictionary in level.geometry.cutaway.structural_sections:
		var all_meshes: Array[String] = []
		var declared: Array[String] = []
		var owned_mounts: Array[String] = []
		var missing: Array[String] = []
		for mesh: MeshInstance3D in section.node.find_children("*", "MeshInstance3D", true, false):
			all_meshes.append(String(mesh.get_path()))
			if mesh != section.get("foundation_mesh") and not section.get("fade_meshes", []).has(mesh): missing.append(String(mesh.get_path()))
		for mesh: MeshInstance3D in section.get("fade_meshes", []): declared.append(String(mesh.get_path()))
		for mount: Node in mounts:
			if mount.get_meta("mount_body") == section.get("body"):
				owned_mounts.append(String(mount.get_path()))
				if not section.node.is_ancestor_of(mount): missing.append("mount outside assembly: "+String(mount.get_path()))
		inventory.append({"node":String(section.node.get_path()),"body":String(section.body.get_path()),"rooms":section.get("room_ids",[]),"reveal_rooms":section.get("reveal_room_ids",[]),"reasons":section.get("reveal_reasons",[]),"meshes":all_meshes,"fade_meshes":declared,"mounts":owned_mounts,"missing":missing})
		if baseline: continue
		_check(missing.is_empty(), "all wall and mounted meshes registered: "+String(section.node.get_path()))
		var foundation: MeshInstance3D = section.get("foundation_mesh") as MeshInstance3D
		var valid: bool = is_instance_valid(foundation) and not section.get("fade_meshes", []).has(foundation)
		if valid and bool(section.get("shared_foundation", false)):
			valid = foundation.mesh is ArrayMesh and foundation.name == &"ContinuousCutawayFoundation"
		elif valid and foundation.mesh is BoxMesh:
			var box := foundation.mesh as BoxMesh
			valid = is_equal_approx(box.size.y, float(section.get("base_height", 0.0))) and box.size.x > 0.0 and box.size.z > 0.0
			var bottom: float = foundation.global_position.y - box.size.y * absf(foundation.global_basis.y.y) * 0.5
			valid = valid and absf(bottom-0.18) < 0.015
		else: valid = false
		_check(valid, "grounded continuous or raised solid foundation: "+String(section.node.get_path()))
	_check(not mounts.is_empty(), "mounted decor inventory is nonempty")

func _probe(probe: Dictionary) -> void:
	level.geometry.cutaway.set_enabled(false)
	level._reset_position(probe.position)
	level.geometry.cutaway.set_enabled(true)
	level.geometry.cutaway.advance(probe.position, 1.0)
	await _ticks(2)
	var missing_hidden: Array[String] = []
	var foundations: Array[String] = []
	var active := 0
	for section: Dictionary in level.geometry.cutaway.structural_sections:
		if float(section.get("reveal_amount",0.0)) < 0.999: continue
		active += 1
		for mesh: MeshInstance3D in section.get("fade_meshes", []):
			if mesh.is_visible_in_tree(): missing_hidden.append(String(mesh.get_path()))
		var foundation: MeshInstance3D = section.get("foundation_mesh") as MeshInstance3D
		if is_instance_valid(foundation) and foundation.is_visible_in_tree(): foundations.append(String(foundation.get_path()))
	var blockers := _wall_ray_blockers(probe.position)
	var state: Dictionary = {"label":probe.label,"position":probe.position,"kind":probe.kind,"active_rooms":level.geometry.cutaway.active_rooms.duplicate(),"active_sections":active,"visible_old_meshes":missing_hidden,"foundations":foundations,"wall_ray_blockers":blockers}
	snapshots.append(state)
	if not baseline:
		_check(active > 0 and missing_hidden.is_empty(), "no original wall or hanging mesh remains: "+String(probe.label))
		_check(foundations.size() == active, "each revealed wall retains its separate clean foundation: "+String(probe.label))
		_check(blockers.is_empty(), "three camera rays to hero clear structural walls: "+String(probe.label))
	await _shot(String(probe.label))

func _wall_ray_blockers(position: Vector3) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var camera: Camera3D = level.player.presentation.camera
	for offset: Vector3 in [Vector3(0,0.45,0), Vector3(-0.23,0.45,0.23), Vector3(0.23,0.45,-0.23)]:
		var target := position + offset
		var pointer := camera.unproject_position(target)
		var origin := camera.project_ray_origin(pointer)
		var query := PhysicsRayQueryParameters3D.create(origin, target, 1, [level.player.get_rid()])
		for step: int in 24:
			var hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty(): break
			if wall_by_rid.has(hit.rid) and not level.geometry.cutaway.is_point_cut(hit.collider,hit.position):
				var section: Dictionary = wall_by_rid[hit.rid]
				result.append({"body":String(hit.collider.get_path()),"hit":hit.position,"amount":section.get("reveal_amount",0.0),"owners":section.get("reveal_room_ids",[]),"target":target})
			var exclusions: Array[RID] = query.exclude
			exclusions.append(hit.rid)
			query.exclude = exclusions
	return result

func _style_probe() -> void:
	var style: Node = level.get_node_or_null("InkStyle")
	_check(style != null, "live style controller exists")
	if style == null: return
	var original: int = style.mode
	for label: String in ["room-entry-se", "passage-entry-barracks-a-right", "passage-junction-furnace-a-left", "service-membrane"]:
		for probe: Dictionary in probes:
			if probe.label != label: continue
			await _probe(probe)
			var key := InputEventKey.new()
			key.physical_keycode = KEY_F6
			key.pressed = true
			Input.parse_input_event(key)
			await _ticks(2)
			key.pressed = false
			Input.parse_input_event(key)
			_check(style.mode != original, "actual F6 changes style at "+label)
			var resurrected: Array[String] = []
			for section: Dictionary in level.geometry.cutaway.structural_sections:
				if float(section.get("reveal_amount",0.0)) < 0.999: continue
				for mesh: MeshInstance3D in section.get("fade_meshes",[]):
					if mesh.is_visible_in_tree(): resurrected.append(String(mesh.get_path()))
			if not baseline: _check(resurrected.is_empty(), "F6 preserves fully hidden structural meshes at "+label)
			await _shot(label+"-f6")
			style.set_mode(original)
			await _ticks(1)

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
	_check(error == OK, "native image "+label)

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
	var report: Dictionary = {"status":"PASS" if failures == 0 else "FAIL","baseline":baseline,"focus_subset":focus,"planned_probe_count":probes.size(),"checks":checks,"probes":snapshots,"inventory":inventory,"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"scope":"Static diagnostic placement at every room edge/corner and passage mouth/jamb/middle, or the explicitly flagged focus subset. Frozen actors, player and gate animation; no traversal or combat/performance claim. Structural rays ignore unrelated props and cannot prove crown shader pixels; inspect native images separately. Baseline is the rejected enabled reveal before cleanup."}
	FileAccess.open(out+"results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ROOM_WALL_CLEANUP_RESULT checks=",checks.size()," failures=",failures," probes=",snapshots.size())
	quit(1 if failures else 0)
