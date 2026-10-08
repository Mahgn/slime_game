extends SceneTree

const OUTPUT := "res://output/authored_occlusion_2026_10_07/trail_images/"
var route: SlimeOpeningRoute
var failures := 0
var assertions := 0
var preserve_pause := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("BLOCKED trail raster check requires native rendering")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.grab_focus()
	var watchdog := Timer.new()
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.one_shot = true
	watchdog.wait_time = 60.0
	root.add_child(watchdog)
	watchdog.timeout.connect(func() -> void: printerr("FAIL trail capture watchdog"); quit(124))
	watchdog.start()
	SlimeGameSettings.current().load_settings("res://output/authored_occlusion_2026_10_07/test_settings.cfg")
	change_scene_to_file("res://scenes/opening/opening_route.tscn")
	await _frames(10)
	route = current_scene as SlimeOpeningRoute
	route._enter_room(2)
	await _frames(20)
	var material := route.player._ground_trail.material_override as ShaderMaterial
	# Two controlled patches share the real runtime trail material. Empty
	# architecture prevents a deck from masking a shader failure in this test.
	route.geometry.hide()
	var upper := _patch(route.world_point(Vector3(3.0, 0.85, 3.8)), Color(1, 0, 1, 1), material)
	var lower := _patch(route.world_point(Vector3(5.5, -0.75, 3.8)), Color(0, 1, 0, 1), material)
	var solid := await _capture("01-upper-floor")
	var initial := _counts(solid)
	_check(initial.x > 100 and initial.y > 100, "native trail shader draws both upper and lower diagnostic patches")
	route.player.global_position = route.world_point(Vector3(3.9, -0.76, 1.1))
	route.player.velocity = Vector3.ZERO
	await _frames(4)
	var middle := float(material.get_shader_parameter("upper_floor_fade"))
	preserve_pause = true
	paused = true
	await _frames(15)
	_check(middle > 0.0 and middle < 1.0 and is_equal_approx(middle, float(material.get_shader_parameter("upper_floor_fade"))),
		"pause freezes an actual in-progress gallery and trail fade")
	preserve_pause = false
	route._resume_game()
	await _frames(25)
	var revealed := await _capture("02-lower-floor")
	var hidden := _counts(revealed)
	_check(hidden.x == 0, "native reveal removes upper-floor trail pixels")
	_check(hidden.y >= int(initial.y * 0.98), "native reveal retains lower-floor trail pixels")
	route.player.global_position = route.spawn_position()
	route.player.velocity = Vector3.ZERO
	await _frames(25)
	var restored := _counts(await _capture("03-upper-restored"))
	_check(restored.x >= int(initial.x * 0.98) and is_zero_approx(float(material.get_shader_parameter("upper_floor_fade"))),
		"upper landing restores the upper trail material")
	route._enter_room(0)
	await _frames(15)
	_check(is_zero_approx(float(material.get_shader_parameter("upper_floor_fade"))) and route.player._ground_trail._samples.is_empty(),
		"room transition clears the old trail and resets its floor fade")
	print("TRAIL_PIXELS initial=%s lower=%s restored=%s" % [initial, hidden, restored])
	upper.queue_free()
	lower.queue_free()
	await _frames(3)
	print("OCCLUSION_TRAIL_RESULT assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _patch(at: Vector3, color: Color, material: Material) -> MeshInstance3D:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in [Vector3(-0.45,0,-0.45), Vector3(0.45,0,-0.45), Vector3(0.45,0,0.45),
		Vector3(-0.45,0,-0.45), Vector3(0.45,0,0.45), Vector3(-0.45,0,0.45)]:
		tool.set_color(color)
		tool.add_vertex(vertex)
	var result := MeshInstance3D.new()
	result.mesh = tool.commit()
	result.material_override = material
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	route.add_child(result)
	result.global_position = at
	return result


func _counts(image: Image) -> Vector2i:
	var count := Vector2i.ZERO
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.r > 0.7 and color.b > 0.7 and color.g < 0.15:
				count.x += 1
			if color.g > 0.7 and color.r < 0.15 and color.b < 0.15:
				count.y += 1
	return count


func _capture(label: String) -> Image:
	await _frames(4)
	RenderingServer.force_draw()
	var image := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	if image.save_png(OUTPUT + label + ".png") != OK:
		_check(false, "failed saving trail raster capture " + label)
	return image


func _frames(count: int) -> void:
	for frame in count:
		if paused and not preserve_pause and is_instance_valid(route):
			route._resume_game()
		await physics_frame
		await process_frame


func _check(value: bool, label: String) -> void:
	assertions += 1
	print(("PASS " if value else "FAIL ") + label)
	if not value:
		failures += 1
