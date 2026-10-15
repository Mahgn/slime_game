extends SceneTree

# Native comparison of exactly the same physical doorway paths. Relocation only
# selects each start; every measured crossing uses the normal movement actions.
const SCENE := "res://scenes/dungeon/dungeon_route.tscn"
const ROOT_OUT := "res://output/room_wall_fade_2026_10_14/"
const MOVES: Array[StringName] = [&"move_right", &"move_left", &"move_back", &"move_forward"]
const ROUTES: Array[String] = ["entry-spring", "entry-barracks", "entry-junction", "junction-furnace", "furnace-hub", "hub-armory"]
var out := ROOT_OUT + "candidate/"
var baseline := false
var capture := false
var aim_only := false
var level: SlimeKeepersWorld
var checks: Array[Dictionary] = []
var records: Array[Dictionary] = []
var raw_frames: Array[float] = []
var samples_active := false
var last_draw := 0
var finished := false
var geometry_before: Dictionary = {}
var fade_trace: Array[Dictionary] = []
var tracing_fade := false

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--baseline": baseline = true
		if arg == "--capture": capture = true
		if arg == "--aim-only": aim_only = true
		if arg.begins_with("--output=res://output/"): out = arg.trim_prefix("--output=").trim_suffix("/") + "/"
	if baseline and out == ROOT_OUT + "candidate/": out = ROOT_OUT + "baseline/"
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out + "images"))
	SlimeGameSettings.current().load_settings(out + "settings.cfg")
	seed(4873)
	create_timer(180.0, true).timeout.connect(func() -> void: _check(false, "bounded 180 s watchdog"); _finish())
	if DisplayServer.get_name() == "headless":
		capture = false
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		root.size = Vector2i(1920, 1080)
		DisplayServer.window_set_size(root.size)
		RenderingServer.frame_post_draw.connect(_sample_frame)
	change_scene_to_file(SCENE)
	await _ticks(25)
	level = current_scene as SlimeKeepersWorld
	await _wait_ready()
	_check(is_instance_valid(level) and level.player is SlimeDungeonPlayer, "real dungeon route initializes")
	if not is_instance_valid(level): _finish(); return
	_check(is_instance_valid(level.geometry.cutaway), "cutaway compiled and initialized")
	if not is_instance_valid(level.geometry.cutaway): _finish(); return
	if baseline:
		level.geometry.cutaway.set_enabled(false)
	_freeze_enemies()
	geometry_before = _geometry_signature()
	if aim_only:
		level._reset_position(level.rooms.entry.spawn)
		await _ticks(50)
		await _wall_and_aim(level.geometry.cutaway)
		_finish()
		return
	_check(level.rooms.size() == 11, "all eleven authored rooms remain resident")
	for id: String in ["entry", "spring", "barracks", "junction", "furnace", "cistern", "hub", "armory", "garden", "archive", "summit"]:
		level._reset_position(level.rooms[id].spawn)
		await _ticks(40)
		await _shot("room-" + id)
	level._reset_position(level.rooms.entry.spawn)
	await _ticks(40)
	for link: Dictionary in level.connections:
		var route_name: String = String(link.a) + "-" + String(link.b)
		if not ROUTES.has(route_name): continue
		var direction: Vector3 = (link.path[1] - link.path[0]).normalized()
		var a: Vector3 = link.path[0] - direction * 1.8
		var b: Vector3 = link.path[1] + direction * 1.8
		await _cross(a, b, route_name + "-forward")
		await _cross(b, a, route_name + "-return")
	_check(_geometry_signature() == geometry_before, "render changes preserve every geometry collider layer, mask, shape, transform and enabled state")
	if not baseline:
		await _candidate_checks()
	_finish()

func _wait_ready() -> void:
	for tick: int in 900:
		if is_instance_valid(level) and not level._transitioning:
			level._pause_panel.hide()
			paused = false
			return
		await _ticks(1)
	_check(false, "navigation and render warmup complete")

func _freeze_enemies() -> void:
	for id: String in level.rooms:
		for actor: Node3D in level.alive_enemies(id):
			actor.set_physics_process(false)
			# Preserve visible actors as readability references, remove dynamic path blocks.
			(actor as CollisionObject3D).collision_layer = 0

func _geometry_signature() -> Dictionary:
	var result: Dictionary = {}
	for body: StaticBody3D in level.geometry.find_children("*", "StaticBody3D", true, false):
		var shapes: Array = []
		for child: Node in body.get_children():
			if child is CollisionShape3D:
				shapes.append([child.disabled, child.shape.get_rid(), child.transform])
		result[String(body.get_path())] = [body.collision_layer, body.collision_mask, body.global_transform, shapes]
	return result

func _cross(a: Vector3, b: Vector3, label: String) -> void:
	level._reset_position(a)
	await _ticks(36)
	var geometry_id: int = level.geometry.get_instance_id()
	var take_shots: bool = label.begins_with("entry-spring") or label.begins_with("entry-junction") or label.begins_with("furnace-hub") or label.begins_with("fade-")
	if take_shots: await _shot(label + "-before")
	await _begin_sample()
	var arrived := false
	var middle := false
	for tick: int in 300:
		var offset: Vector3 = b - level.player.global_position
		offset.y = 0.0
		if offset.length() < 0.22: arrived = true; break
		_walk_towards(b)
		await _ticks(1)
		if take_shots and not middle and offset.length() < a.distance_to(b) * 0.5:
			middle = true
			await _shot(label + "-middle")
	_release()
	await _ticks(30)
	_end_sample(label, arrived)
	if take_shots: await _shot(label + "-after")
	_check(arrived and geometry_id == level.geometry.get_instance_id(), label + " crosses physically without replacing geometry")
	if not arrived:
		print("WALL_PATH_BLOCKED ", level.player.global_position, " expected ", b)

func _walk_towards(target: Vector3) -> void:
	var offset: Vector3 = target - level.player.global_position
	offset.y = 0.0
	var axes: Vector2 = level.player.controls.world_direction_to_screen_axes(offset.normalized())
	Input.action_press(&"move_right", maxf(axes.x, 0.0))
	Input.action_press(&"move_left", maxf(-axes.x, 0.0))
	Input.action_press(&"move_back", maxf(axes.y, 0.0))
	Input.action_press(&"move_forward", maxf(-axes.y, 0.0))

func _release() -> void:
	for action: StringName in MOVES: Input.action_release(action)

func _begin_sample() -> void:
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	raw_frames.clear()
	last_draw = Time.get_ticks_usec()
	samples_active = true

func _sample_frame() -> void:
	var now: int = Time.get_ticks_usec()
	if tracing_fade and is_instance_valid(level):
		fade_trace.append({"usec": now, "position": level.player.global_position, "entry": float(level.geometry.cutaway.room_amounts.entry), "spring": float(level.geometry.cutaway.room_amounts.spring), "entry_target": float(level.geometry.cutaway.room_targets.entry), "spring_target": float(level.geometry.cutaway.room_targets.spring)})
	if samples_active: raw_frames.append(float(now - last_draw) / 1000.0)
	last_draw = now

func _end_sample(label: String, arrived: bool) -> void:
	samples_active = false
	var sorted: Array[float] = raw_frames.duplicate()
	sorted.sort()
	var record: Dictionary = {"label": label, "arrived": arrived, "frames": sorted.size(), "viewport": [root.size.x, root.size.y]}
	if not sorted.is_empty():
		record.merge({"median_ms": _percentile(sorted, 0.5), "p95_ms": _percentile(sorted, 0.95), "p99_ms": _percentile(sorted, 0.99), "max_ms": sorted[-1], "over_16_67_ms": sorted.filter(func(v: float) -> bool: return v > 16.67).size(), "over_33_33_ms": sorted.filter(func(v: float) -> bool: return v > 33.33).size()})
	records.append(record)
	FileAccess.open(out + label + ".frames.json", FileAccess.WRITE).store_string(JSON.stringify(raw_frames))
	print("WALL_FRAME_METRIC ", JSON.stringify(record))

func _percentile(values: Array[float], percentile: float) -> float:
	return values[clampi(int(ceil(values.size() * percentile)) - 1, 0, values.size() - 1)]

func _shot(label: String) -> void:
	if not capture: return
	var sampling: bool = samples_active
	samples_active = false
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png(out + "images/" + label + ".png")
	_check(error == OK, "native image " + label)
	last_draw = Time.get_ticks_usec()
	samples_active = sampling

func _ticks(count: int, resume: bool = true) -> void:
	for tick: int in count:
		if resume and is_instance_valid(level) and is_instance_valid(level._pause_panel) and level._pause_panel.visible:
			level._resume_game()
		await physics_frame
		await process_frame
		if resume: paused = false

func _candidate_checks() -> void:
	var cutaway: Node = level.geometry.cutaway
	_check(cutaway.has_method("advance"), "room-owned fade controller exposes its bounded update")
	if not cutaway.has_method("advance"): return
	_controller_contract(cutaway)
	await _fade_approach()
	level._reset_position(level.rooms.entry.spawn)
	await _ticks(50)
	_check(float(cutaway.room_amounts.entry) > 0.99, "active room fully reveals its foreground")
	var old_amounts: Dictionary = cutaway.room_amounts.duplicate()
	var camera_basis: Basis = level.player.presentation.camera.global_basis
	var start_y: float = level.player.global_position.y
	Input.action_press(&"jump")
	await _ticks(30)
	Input.action_release(&"jump")
	var peak := 0.0
	var jump_stable := true
	for tick: int in 110:
		await _ticks(1)
		peak = maxf(peak, level.player.global_position.y - start_y)
		jump_stable = jump_stable and cutaway.room_amounts == old_amounts
	_check(peak > 0.5 and level.player.is_on_floor(), "charged jump uses real physics and lands on retained floor")
	_check(jump_stable and level.player.presentation.camera.global_basis.is_equal_approx(camera_basis), "jump does not close room walls or rotate camera")
	level.player.presentation.set_process(false)
	for ratio: float in [0.2, 0.5, 0.8]:
		cutaway.set_enabled(false)
		cutaway.set_enabled(true)
		cutaway.advance(level.player.global_position, 0.30 * ratio)
		await _shot("fade-%02d" % int(ratio * 100))
	level.player.presentation.set_process(true)
	cutaway.set_enabled(false)
	cutaway.set_enabled(true)
	cutaway.advance(level.player.global_position, 0.10)
	var paused_amounts: Dictionary = cutaway.room_amounts.duplicate()
	paused = true
	await create_timer(0.20, true).timeout
	_check(cutaway.room_amounts == paused_amounts, "pause freezes a partially completed room reveal")
	paused = false
	await _ticks(40)
	_check(float(cutaway.room_amounts.entry) > 0.99, "resume finishes the same room reveal")
	var style: Node = level.get("ink_style")
	var previous_style: int = style.mode
	var style_amounts: Dictionary = cutaway.room_amounts.duplicate()
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F6
	event.pressed = true
	Input.parse_input_event(event)
	await _ticks(3)
	event.pressed = false
	Input.parse_input_event(event)
	_check(style.mode != previous_style and cutaway.room_amounts == style_amounts, "F6 changes style without resetting room reveal")
	var correct_materials := true
	for section: Dictionary in cutaway.structural_sections:
		for mesh: MeshInstance3D in section.get("fade_meshes", []):
			var materials: Array = [mesh.material_override] if mesh.material_override != null else []
			if mesh.material_override == null:
				for surface: int in mesh.mesh.get_surface_count(): materials.append(mesh.get_active_material(surface))
			for material: Material in materials:
				if material is ShaderMaterial:
					var actual: Variant = material.get_shader_parameter("wall_reveal")
					correct_materials = correct_materials and actual != null and is_equal_approx(float(actual), float(section.reveal_amount))
	_check(correct_materials, "F6 material copies preserve each structural section's actual fade uniform")
	style.set_mode(previous_style)
	await _ticks(3)
	await _wall_and_aim(cutaway)
	_check(_geometry_signature() == geometry_before, "jump, pause, aim and reveal toggles preserve structural physics")
	var old_controller: int = cutaway.get_instance_id()
	level.restart_run()
	await _ticks(25)
	level = current_scene as SlimeKeepersWorld
	await _wait_ready()
	_freeze_enemies()
	await _ticks(40)
	_check(level.geometry.cutaway.get_instance_id() != old_controller and level.room_id == "entry", "restart replaces the old room controller and restores entry")
	_check(float(level.geometry.cutaway.room_amounts.entry) > 0.99 and float(level.geometry.cutaway.room_amounts.summit) < 0.01, "restart has no retained distant room fade")
	await _shot("restart-entry")

func _fade_approach() -> void:
	# Begin outside the 3.45 m approach capsule, unlike the short threshold
	# crossings used for the matched baseline/candidate timing comparison.
	for route: Dictionary in [{"a": Vector3(-3.4, 0, 14), "b": Vector3(-13.6, 0, 14), "label": "fade-entry-spring", "opens": "spring", "closes": "entry"}, {"a": Vector3(-13.6, 0, 14), "b": Vector3(-3.4, 0, 14), "label": "fade-spring-entry", "opens": "entry", "closes": "spring"}]:
		level._reset_position(route.a)
		await _ticks(90)
		fade_trace.clear()
		tracing_fade = true
		await _cross(route.a, route.b, route.label)
		await _ticks(60)
		tracing_fade = false
		FileAccess.open(out + route.label + ".fade.json", FileAccess.WRITE).store_string(JSON.stringify(fade_trace, "\t"))
		if DisplayServer.get_name() == "headless": continue
		var opening: String = route.opens
		var closing: String = route.closes
		var previous_open := 0.0
		var previous_close := 1.0
		var monotonic := true
		var fractions := 0
		var switches := {"entry": 0, "spring": 0}
		for index: int in fade_trace.size():
			var item: Dictionary = fade_trace[index]
			var amount_open: float = item[opening]
			var amount_close: float = item[closing]
			monotonic = monotonic and amount_open + 0.0001 >= previous_open and amount_close <= previous_close + 0.0001
			if (amount_open > 0.01 and amount_open < 0.99) or (amount_close > 0.01 and amount_close < 0.99): fractions += 1
			if index > 0:
				for id: String in ["entry", "spring"]:
					if item[id + "_target"] != fade_trace[index - 1][id + "_target"]: switches[id] += 1
			previous_open = amount_open
			previous_close = amount_close
		_check(monotonic and fractions >= 4, route.label + " native rendered fade changes continuously in one direction")
		_check(switches.entry <= 1 and switches.spring <= 1, route.label + " has no repeated target reversal at doorway")
		_check(previous_open > 0.99 and previous_close < 0.01, route.label + " fully restores the room left behind")

func _controller_contract(current: Node) -> void:
	# Use the real controller with the actual authored layout, but no materials.
	# Fixed deltas make hysteresis and fade boundaries independent of GPU speed.
	var test: Node = current.get_script().new()
	var high: Node = current.get_script().new()
	test.configure_building(level.rooms, level.connections)
	high.configure_building(level.rooms, level.connections)
	test.set_enabled(true)
	high.set_enabled(true)
	var previous := 0.0
	var smooth := true
	for frame: int in 30:
		test.advance(level.rooms.entry.spawn, 1.0 / 60.0)
		var amount: float = test.room_amounts.entry
		smooth = smooth and amount >= previous and amount - previous <= 0.056
		previous = amount
	_check(smooth and previous > 0.99, "reveal progresses monotonically over multiple frames")
	var frozen: Dictionary = test.room_amounts.duplicate()
	for frame: int in 30: test.advance(level.rooms.summit.spawn, 0.0)
	_check(test.room_amounts == frozen, "zero delta cannot advance fade or consume release time")
	test.set_enabled(false)
	test.set_enabled(true)
	var same_y := true
	for frame: int in 160:
		var point := Vector3(-8.5 + sin(frame * 0.8) * 0.65, 0, 14)
		test.advance(point, 1.0 / 60.0)
		high.advance(point + Vector3.UP * (2.0 + sin(frame * 0.2)), 1.0 / 60.0)
		same_y = same_y and test.room_amounts == high.room_amounts and test.room_targets == high.room_targets
	_check(same_y, "ownership and fade are independent of airborne height")
	_check(float(test.room_amounts.entry) > 0.99 and float(test.room_amounts.spring) > 0.99, "doorway jitter keeps both neighbouring rooms open")
	var retained := true
	for frame: int in 8:
		test.advance(level.rooms.summit.center, 1.0 / 60.0)
		retained = retained and float(test.room_amounts.entry) > 0.99
	_check(retained, "leaving a room has a release hold instead of immediate closure")
	for frame: int in 90: test.advance(level.rooms.summit.center, 1.0 / 60.0)
	_check(float(test.room_amounts.entry) < 0.01 and float(test.room_amounts.spring) < 0.01, "distant room walls restore after release hold and fade")
	test.set_enabled(false)
	_check(test.active_rooms.is_empty() and test.room_amounts.values().all(func(v: float) -> bool: return is_zero_approx(v)), "disabling reveal restores every room and clears ownership")
	_check(is_zero_approx(test.get_reveal_amount()), "wall reveal never fades the floor or slime trail")
	test.free()
	high.free()

func _wall_and_aim(cutaway: Node) -> void:
	var target := CharacterBody3D.new()
	target.name = "WallAimPhysicsProbe"
	target.collision_layer = 4
	target.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.0
	shape_node.shape = capsule
	shape_node.position.y = 0.5
	target.add_child(shape_node)
	level.add_child(target)
	var chosen: Dictionary = {}
	for section: Dictionary in cutaway.structural_sections:
		if not bool(section.get("is_foreground", false)) or not section.get("room_ids", []).has("entry"): continue
		var point: Vector3 = section.point
		var normal: Vector3 = section.normal
		target.global_position = point - normal * 1.4
		await _ticks(2)
		var camera: Camera3D = level.player.presentation.camera
		var pointer: Vector2 = camera.unproject_position(target.global_position + Vector3.UP * 0.45)
		var ray_from: Vector3 = camera.project_ray_origin(pointer)
		var query := PhysicsRayQueryParameters3D.create(ray_from, ray_from + camera.project_ray_normal(pointer) * 180.0, 5, [level.player.get_rid()])
		var hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider == section.body and hit.position.y > float(section.cut_height):
			# Reject a fixture obscured by a real prop behind the wall. Such a prop
			# must continue blocking aim, so it cannot stand for a clear shot.
			var reached_target := false
			for step: int in 24:
				if hit.is_empty(): break
				if hit.collider == target: reached_target = true; break
				if not cutaway.is_point_cut(hit.collider, hit.position): break
				query.from = hit.position + camera.project_ray_normal(pointer) * 0.01
				hit = level.get_world_3d().direct_space_state.intersect_ray(query)
			if not reached_target: continue
			chosen = section
			level.player.controls.pointer = pointer
			break
	_check(not chosen.is_empty(), "native camera ray first meets a real foreground wall before target")
	if chosen.is_empty(): target.queue_free(); return
	var aim_visible: Vector3 = level.player.controls.get_aim_point()
	var trace_camera: Camera3D = level.player.presentation.camera
	var trace_from: Vector3 = trace_camera.project_ray_origin(level.player.controls.pointer)
	var trace_direction: Vector3 = trace_camera.project_ray_normal(level.player.controls.pointer)
	var trace_query := PhysicsRayQueryParameters3D.create(trace_from, trace_from + trace_direction * 180.0, 5, [level.player.get_rid()])
	var trace_hits: Array = []
	for step: int in 12:
		var trace_hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(trace_query)
		if trace_hit.is_empty(): break
		var cut: bool = cutaway.is_point_cut(trace_hit.collider, trace_hit.position)
		trace_hits.append({"collider": String(trace_hit.collider.get_path()), "position": trace_hit.position, "cut": cut})
		if not cut: break
		trace_query.from = trace_hit.position + trace_direction * 0.01
	print("AIM_DIAGNOSTIC ", JSON.stringify({"body": String(chosen.body.get_path()), "reveal": chosen.reveal_amount, "owners": chosen.get("reveal_room_ids", []), "target": target.global_position + Vector3.UP * 0.45, "actual": aim_visible, "hits": trace_hits}))
	_check(aim_visible.distance_to(target.global_position + Vector3.UP * 0.45) < 0.01, "revealed foreground lets camera aim select the real target collider")
	_check(not cutaway.is_point_cut(chosen.body, chosen.point + Vector3.UP * 0.05), "wall foundation still blocks camera aim")
	cutaway.set_enabled(false)
	var aim_closed: Vector3 = level.player.controls.get_aim_point()
	_check(aim_closed.distance_to(target.global_position + Vector3.UP * 0.45) > 0.03, "restored wall prevents target selection through its full height")
	cutaway.set_enabled(true)
	await _ticks(40)
	var normal: Vector3 = chosen.normal
	var point: Vector3 = chosen.point
	var query := PhysicsRayQueryParameters3D.create(point - normal * 1.5 + Vector3.UP * 0.8, point + normal * 1.5 + Vector3.UP * 0.8, 1)
	var solid_hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(query)
	_check(not solid_hit.is_empty() and solid_hit.collider == chosen.body, "revealed wall remains in the ordinary world collision ray used by combat")
	target.queue_free()
	await _ticks(2)
	level._reset_position(point - normal * 1.4)
	await _ticks(6)
	var wall_contact := false
	for frame: int in 45:
		_walk_towards(point + normal * 1.4)
		await _ticks(1)
		for slide: int in level.player.get_slide_collision_count():
			wall_contact = wall_contact or level.player.get_slide_collision(slide).get_collider() == chosen.body
	_release()
	_check(wall_contact and (level.player.global_position - point).dot(normal) < -0.5, "normal movement cannot cross the visually removed wall")
	await _ticks(2)

func _check(ok: bool, label: String) -> void:
	checks.append({"pass": ok, "check": label})
	print("PASS " if ok else "FAIL ", label)

func _finish() -> void:
	if finished: return
	finished = true
	_release()
	var failed: bool = checks.any(func(item: Dictionary) -> bool: return not item.pass)
	var report: Dictionary = {"status": "FAIL" if failed else "PASS", "baseline": baseline, "checks": checks, "records": records, "engine": Engine.get_version_info(), "renderer": RenderingServer.get_current_rendering_method(), "device": RenderingServer.get_video_adapter_name(), "scope": "Six authored doorways crossed in both directions through normal input. Visible enemies frozen and nonblocking. PNG readback, relocation and warmup excluded. Uncapped inter-draw wall times, not GPU timestamps. No combat-load or user acceptance claim."}
	FileAccess.open(out + "results.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ROOM_WALL_FADE_RESULT checks=", checks.size(), " failures=", checks.filter(func(item: Dictionary) -> bool: return not item.pass).size())
	quit(1 if failed else 0)
