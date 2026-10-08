extends SceneTree

const OUTPUT := "res://output/authored_occlusion_2026_10_07/images/"
const POSITIONS := [Vector3(4.3, 0.0, 5.45), Vector3(6.55, 0.35, 3.5), Vector3(3.9, -0.8, 1.1)]
var route: SlimeOpeningRoute
var failures := 0
var assertions := 0
var capture := false


func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var watchdog := Timer.new()
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.one_shot = true
	watchdog.wait_time = 100.0
	root.add_child(watchdog)
	watchdog.timeout.connect(func() -> void: printerr("FAIL cutaway watchdog"); quit(124))
	watchdog.start()
	if capture and DisplayServer.get_name() == "headless":
		printerr("BLOCKED cutaway capture requires a native window")
		quit(2)
		return
	SlimeGameSettings.current().load_settings("res://output/authored_occlusion_2026_10_07/test_settings.cfg")
	change_scene_to_file("res://scenes/opening/opening_route.tscn")
	await _frames(15)
	route = current_scene as SlimeOpeningRoute
	for index in 3:
		var previous_geometry := route.geometry
		var previous_cutaway: SlimeRoomCutaway = route.geometry.cutaway
		route._enter_room(index)
		await _frames(12)
		_check(not is_instance_valid(previous_geometry) and not is_instance_valid(previous_cutaway),
			"P%d transition frees the previous room and its section owner" % (index + 1))
		var cutaway: SlimeRoomCutaway = route.geometry.cutaway
		_check(route.player.presentation.room_cutaway == cutaway,
			"P%d binds the current room section owner" % (index + 1))
		var original_shapes := _collision_state()
		route.player.global_position = route.world_point(POSITIONS[index]) + Vector3.UP * 0.04
		route.player.velocity = Vector3.ZERO
		await _frames(28)
		_check(route.player.is_on_floor() and _has_support(), "P%d hero remains on a physical support" % (index + 1))
		_check(route.player.presentation.hidden.is_empty(), "P%d does not use independent legacy mesh hiding" % (index + 1))
		if index < 2:
			_check(cutaway.sections.is_empty(), "P%d walls and small props remain solid architecture" % (index + 1))
			if capture:
				await _capture_image("p%d-front-wall" % (index + 1))
		else:
			_check(cutaway.sections.size() == 3 and _sections_at(1.0), "gallery lower route reveals all three complete upper sections")
			_check(cutaway.lower_route, "lower route owns the gallery visibility state")
			for name in ["recoveryVisual", "ReturnRampVisual", "RampLandingVisual"]:
				var mesh := route.geometry.find_child(name, true, false) as MeshInstance3D
				_check(mesh != null and mesh.is_visible_in_tree(), "gallery retains lower support " + name)
			if capture:
				cutaway.set_enabled(false)
				await _frames(20)
				await _capture_image("p3-upper-solid")
				cutaway.set_enabled(true)
				await _frames(20)
				await _capture_image("p3-lower-revealed")
			await _lower_jump_trial()
			await _restore_upper_trial()
		cutaway.set_enabled(false)
		await _frames(20)
		_check(_collision_state() == original_shapes and _sections_at(0.0), "P%d disabled reveal restores sections and preserves physics" % (index + 1))
		cutaway.set_enabled(true)
		await _frames(20)
		_check(_collision_state() == original_shapes, "P%d enabled reveal preserves all physical shapes" % (index + 1))
		if index == 1:
			await _physical_wall_trial()
			await _low_wall_jump_trial()
			if capture:
				await _silhouette_pixels()
	var final_cutaway: SlimeRoomCutaway = route.geometry.cutaway
	route._enter_room(0)
	await _frames(12)
	_check(not is_instance_valid(final_cutaway) and route.player.presentation.room_cutaway == route.geometry.cutaway
		and not route.geometry.cutaway.lower_route, "return to P01 clears the lower gallery state")
	print("WALL_CUTAWAY_RESULT assertions=%d failures=%d capture=%s" % [assertions, failures, str(capture)])
	quit(0 if failures == 0 else 1)


func _lower_jump_trial() -> void:
	# Jump in the open lower approach, where the body crosses the restore
	# height. The occupied floor must control visibility, not airborne feet.
	route.player.global_position = route.world_point(Vector3(6.8, -0.8, 5.7)) + Vector3.UP * 0.04
	route.player.velocity = Vector3.ZERO
	await _frames(25)
	Input.action_press(&"jump")
	await _frames(45)
	Input.action_release(&"jump")
	var peak := route.player.global_position.y
	var remained_lower := true
	var airborne := false
	for sample in 95:
		await _frames(1)
		peak = maxf(peak, route.player.global_position.y)
		airborne = airborne or not route.player.is_on_floor()
		remained_lower = remained_lower and route.geometry.cutaway.lower_route and _sections_at(1.0)
	_check(airborne and peak > 0.18, "charged jump from lower approach actually crosses the upper restore height")
	_check(remained_lower and route.player.is_on_floor(), "airborne lower-route jump never flashes the upper sections")
	if capture:
		await _capture_image("p3-lower-after-jump")


func _restore_upper_trial() -> void:
	route.player.global_position = route.spawn_position()
	route.player.velocity = Vector3.ZERO
	await _frames(28)
	_check(route.player.is_on_floor() and not route.geometry.cutaway.lower_route and _sections_at(0.0),
		"standing on upper A restores every gallery section")
	if capture:
		await _capture_image("p3-upper-restored")


func _physical_wall_trial() -> void:
	var start := route.player.global_position
	var ray_origin := start + Vector3.UP * 0.12
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + Vector3.RIGHT * 2.0, 1)
	var before := route.player.get_world_3d().direct_space_state.intersect_ray(query)
	_check(not before.is_empty(), "P02 ray hits the retained low front wall")
	var axes := route.player.controls.world_direction_to_screen_axes(Vector3.RIGHT)
	Input.action_press(&"move_right" if axes.x >= 0 else &"move_left", absf(axes.x))
	Input.action_press(&"move_back" if axes.y >= 0 else &"move_forward", absf(axes.y))
	await _frames(36)
	for action in [&"move_left", &"move_right", &"move_forward", &"move_back"]:
		Input.action_release(action)
	await _frames(8)
	var displacement := route.player.global_position - start
	_check(route.player.is_on_floor() and displacement.x < 0.8 and absf(displacement.z) < 0.15,
		"P02 real input cannot walk through the low front boundary")
	var after := route.player.get_world_3d().direct_space_state.intersect_ray(query)
	_check(not before.is_empty() and not after.is_empty() and before["collider"] == after["collider"],
		"P02 movement still meets the same physical front boundary")


func _low_wall_jump_trial() -> void:
	# The central front rib is intentionally still tall. Use the neighbouring
	# low parapet span, where the rendered crossing is actually unobstructed.
	route.player.global_position = route.world_point(Vector3(6.35, 0.35, 4.8)) + Vector3.UP * 0.04
	route.player.velocity = Vector3.ZERO
	await _frames(15)
	var start := route.player.global_position
	var spawn := route.spawn_position()
	var axes := route.player.controls.world_direction_to_screen_axes(Vector3.RIGHT)
	Input.action_press(&"jump")
	await _frames(45)
	Input.action_release(&"jump")
	Input.action_press(&"move_right" if axes.x >= 0 else &"move_left", absf(axes.x))
	Input.action_press(&"move_back" if axes.y >= 0 else &"move_forward", absf(axes.y))
	var farthest_x := start.x
	var peak := start.y
	var reset := false
	for frame in 160:
		await _frames(1)
		farthest_x = maxf(farthest_x, route.player.global_position.x)
		peak = maxf(peak, route.player.global_position.y)
		if farthest_x > start.x + 1.0 and route.player.global_position.distance_to(spawn) < 0.3:
			reset = true
			break
	for action in [&"move_left", &"move_right", &"move_forward", &"move_back", &"jump"]:
		Input.action_release(action)
	await _frames(12)
	_check(farthest_x > 11.0 and peak > 1.0, "charged jump crosses the low front wall without an invisible upper collision")
	_check(reset and route.player.is_on_floor() and route.player.global_position.distance_to(spawn) < 0.35,
		"falling beyond the low wall returns the hero safely to the room start")
	print("LOW_WALL_JUMP max_x=%.3f peak=%.3f reset=%s" % [farthest_x, peak, str(reset)])


func _silhouette_pixels() -> void:
	# Controlled opaque column is test-only. Compare rendered pixels rather
	# than duplicating the shader's depth formula in a CPU assertion.
	route.player.global_position = route.world_point(Vector3(6.0, 0.35, 3.5)) + Vector3.UP * 0.04
	route.player.velocity = Vector3.ZERO
	await _frames(150)
	var presentation := route.player.presentation
	var hero := route.player.hero_visual
	var silhouette: MeshInstance3D = presentation.silhouette
	var pillar := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.25, 1.8, 1.25)
	pillar.mesh = box
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("514b43")
	pillar.material_override = material
	route.add_child(pillar)
	pillar.global_position = route.player.global_position + Vector3(0.9, 0.8, 0.9)
	await _frames(8)
	presentation.set_process(false)
	hero.set_process(false)
	route.player.set_physics_process(false)
	route.player.set_process(false)
	var center := presentation.camera.unproject_position(route.player.global_position + Vector3.UP * 0.38)
	silhouette.visible = false
	var solid: Image = await _capture_image("silhouette-column-off")
	silhouette.visible = true
	var outlined: Image = await _capture_image("silhouette-column-on")
	var changed := _pixel_changes(solid, outlined, center)
	_check(changed.x > 20, "native silhouette reveals the hero behind an opaque column")
	_check(changed.y == 0, "native silhouette preserves architecture outside the hero footprint")
	pillar.hide()
	# The room's natural ribs may still overlap this point. Remove all room
	# visuals for the clear-body control; their physics keeps the hero still.
	route.geometry.hide()
	silhouette.visible = false
	var clear: Image = await _capture_image("silhouette-open-off")
	var clear_repeat: Image = await _capture_image("silhouette-open-off-repeat")
	_check(_pixel_changes(clear, clear_repeat, center) == Vector2i.ZERO, "native clear-body comparison has no animation drift")
	silhouette.visible = true
	var clear_on: Image = await _capture_image("silhouette-open-on")
	var clear_changes := _pixel_changes(clear, clear_on, center)
	_check(clear_changes.x <= 8 and clear_changes.y == 0, "native silhouette does not paint the unobstructed hero")
	print("SILHOUETTE_PIXELS column=%s open=%s" % [changed, clear_changes])
	route.geometry.show()
	pillar.queue_free()
	hero.set_process(true)
	presentation.set_process(true)
	route.player.set_physics_process(true)
	route.player.set_process(true)
	await _frames(3)


func _pixel_changes(before: Image, after: Image, center: Vector2) -> Vector2i:
	var changes := Vector2i.ZERO
	for y in before.get_height():
		for x in before.get_width():
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) <= 0.04:
				continue
			if absf(float(x) - center.x) < 58.0 and absf(float(y) - center.y) < 58.0:
				changes.x += 1
			else:
				changes.y += 1
	return changes


func _sections_at(amount: float) -> bool:
	for section: Dictionary in route.geometry.cutaway.sections.values():
		if not is_equal_approx(float(section.amount), amount):
			return false
		for material: ShaderMaterial in section.materials:
			if not is_equal_approx(float(material.get_shader_parameter("cutaway_amount")), amount):
				return false
	return true


func _capture_image(label: String) -> Image:
	root.grab_focus()
	await _frames(5)
	RenderingServer.force_draw()
	var image := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	_check(image.save_png(OUTPUT + label + ".png") == OK, "native image " + label)
	return image


func _has_support() -> bool:
	var from := route.player.global_position + Vector3.UP * 0.08
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 0.3, 1)
	return not route.player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _collision_state() -> Dictionary:
	var state := {}
	for node in route.geometry.find_children("*", "CollisionShape3D", true, false):
		var shape := node as CollisionShape3D
		var body := shape.get_parent() as CollisionObject3D
		state[shape.get_instance_id()] = [shape.shape, shape.disabled, body.collision_layer, body.collision_mask, shape.global_transform]
	return state


func _frames(count: int) -> void:
	for frame in count:
		if paused and is_instance_valid(route) and not route.finished:
			route._resume_game()
		await physics_frame
		await process_frame


func _check(value: bool, label: String) -> void:
	assertions += 1
	print(("PASS " if value else "FAIL ") + label)
	if not value:
		failures += 1
