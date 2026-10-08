extends SceneTree

const LEVEL_SCENE := "res://scenes/keepers/keepers_level.tscn"
const MAIN_PATH := [
	Vector3(-5.5, 0, 5.5), Vector3(-5.5, 0, -4.5),
	Vector3(1.5, 0, -5.4), Vector3(3, 0, -5.4), Vector3(6, 0.65, -5.4),
]
var level: SlimeKeepersLevel
var failures := 0
var assertions := 0
var capture := false
var output_dir := "res://output/keepers_level_2026_10_08/images/"
var checks: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var captures: Array[String] = []
var checkpoint_before: Dictionary
var restart_baseline := 0
var _finishing := false


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--capture":
			capture = true
		elif argument.begins_with("--capture-dir="):
			output_dir = argument.trim_prefix("--capture-dir=").replace("\\", "/").trim_suffix("/") + "/"
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var watchdog := Timer.new()
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.one_shot = true
	watchdog.wait_time = 240.0
	root.add_child(watchdog)
	watchdog.timeout.connect(func() -> void:
		_check(false, "keepers watchdog exceeded 240 seconds")
		_finish(124))
	watchdog.start()
	if capture and DisplayServer.get_name() == "headless":
		printerr("BLOCKED keepers capture requires a native window")
		_finish(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	SlimeGameSettings.current().load_settings(output_dir + "test_settings.cfg")
	checkpoint_before = _checkpoint_files()
	change_scene_to_file("res://scenes/launch.tscn")
	await _frames(10)
	var menu_bounds := Rect2(Vector2.ZERO, Vector2(root.size))
	for button: Button in current_scene.find_children("*", "Button", true, false):
		if button.is_visible_in_tree():
			_check(menu_bounds.encloses(button.get_global_rect()), "visible menu button fits viewport: " + button.name)
	await _shot("menu")
	if not _press_named(current_scene, "PlayButton"):
		_finish(1)
		return
	await _frames(14)
	var original_route := current_scene as SlimeOpeningRoute
	_check(is_instance_valid(original_route), "main Play still opens the original three-room route")
	if not is_instance_valid(original_route):
		_finish(1)
		return
	original_route._pause_panel._go_to_menu()
	await _frames(10)
	if not _press_named(current_scene, "KeepersButton"):
		_finish(1)
		return
	await _frames(20)
	level = current_scene as SlimeKeepersLevel
	_check(is_instance_valid(level) and current_scene.scene_file_path == LEVEL_SCENE, "KeepersButton opens the separate level")
	if not is_instance_valid(level):
		_finish(1)
		return
	_check(level.player.is_on_floor() and level.player.global_position.distance_to(SlimeKeepersLevel.ENTRY) < 0.1,
		"keepers entry starts on its physical floor")
	_check(get_nodes_in_group(&"enemies").is_empty(), "keepers route contains no enemies")
	restart_baseline = get_node_count()
	await _compare_camera("entry")
	if not await _walk_main_route(true):
		_finish(1)
		return
	await _test_pause()
	if not await _finish_and_replay(1):
		_finish(1)
		return

	# Reach both bridge ends by actual movement. Only the later isolated
	# out-of-bounds test injects a position; no traversal uses a teleport.
	if not await _drive(Vector3(6, 0, 1.4)) or not await _drive(Vector3(3, 0, 1.4)) or not await _drive(Vector3(1.25, 0.04, 1.4)):
		_finish(1)
		return
	await _shot("bridge-right")
	var quick := await _jump_to(Vector3(-1.35, 0.04, 1.4), 2, "bridge-basic")
	_check(bool(quick["landed"]), "ordinary release jump crosses the broken bridge and lands")
	_check(float(quick["camera_y_range"]) < 0.001, "ordinary bridge jump keeps camera Y fixed")
	if not bool(quick["landed"]):
		_finish(1)
		return
	var charged := await _jump_to(Vector3(1.35, 0.04, 1.4), 46, "bridge-charged")
	_check(bool(charged["landed"]) and float(charged["peak"]) > float(quick["peak"]) + 0.35,
		"charged release jump returns over the bridge with a higher physical apex")
	_check(float(charged["camera_y_range"]) < 0.001, "charged bridge jump keeps camera Y fixed")
	if not bool(charged["landed"]):
		_finish(1)
		return
	if not await _drive(Vector3(0, -0.65, 1.4)):
		_finish(1)
		return
	await _frames(25)
	_check(level.player.is_on_floor() and absf(level.player.global_position.y + 0.65) < 0.08,
		"walking off the bridge gap lands in the basin without a respawn")
	await _shot("basin-after-fall")
	if not await _drive(Vector3(0, -0.65, 2.15)) or not await _drive(Vector3(0, 0, 4.35)):
		_finish(1)
		return
	_check(level.player.is_on_floor() and absf(level.player.global_position.y) < 0.08,
		"basin ramp returns to the main floor through physical movement")
	await _shot("basin-ramp-return")

	# Deliberate fault injection, independent of the physical routes above.
	level.player.global_position = Vector3(0, -5, 5)
	level.player.velocity = Vector3.ZERO
	await _frames(20)
	_check(level.player.is_on_floor() and level.player.global_position.distance_to(SlimeKeepersLevel.ENTRY) < 0.1,
		"out-of-bounds fault injection respawns the hero safely at entry")
	for iteration in [2, 3]:
		if not await _walk_main_route(false) or not await _finish_and_replay(iteration):
			_finish(1)
			return
	level._pause_game()
	level._pause_panel._request_menu()
	_check(level._pause_panel._confirm.visible, "pause menu requests confirmation before leaving keepers")
	level._pause_panel._go_to_menu()
	await _frames(10)
	_check(current_scene is Control and current_scene.scene_file_path == "res://scenes/launch.tscn"
		and get_nodes_in_group(&"player").is_empty() and not paused,
		"keepers returns to the real menu and frees the hero")
	_check(_checkpoint_files() == checkpoint_before, "route, bridge trials and three replays leave saved progression unchanged")
	_finish(0 if failures == 0 else 1)


func _walk_main_route(compare_camera: bool) -> bool:
	for index in MAIN_PATH.size():
		if not await _drive(MAIN_PATH[index]):
			return false
		if compare_camera and index in [0, 1, 4]:
			await _compare_camera("main-%d" % index)
	_check(level.can_exit() and level.player.is_on_floor(), "walking route reaches the raised exit without jumping")
	return level.can_exit()


func _finish_and_replay(iteration: int) -> bool:
	Input.action_press(&"interact")
	await _frames(2, false)
	Input.action_release(&"interact")
	await _frames(5, false)
	var finished := level.finished and paused and level._ending.visible
	_check(finished, "exit E completes keepers and pauses the scene before replay %d" % iteration)
	if not finished:
		return false
	if iteration == 1:
		await _shot("exit-ending", false)
	var old_level := level
	if not _press_named(level, "KeepersReplayButton"):
		return false
	await _frames(20)
	level = current_scene as SlimeKeepersLevel
	var restarted := is_instance_valid(level) and not is_instance_valid(old_level)
	_check(restarted, "replay button replaces the old keepers scene %d" % iteration)
	if not restarted:
		return false
	_check(not level.finished and not paused and level.player.is_on_floor()
		and level.player.global_position.distance_to(SlimeKeepersLevel.ENTRY) < 0.1,
		"replay %d starts a fresh grounded hero at entry" % iteration)
	_check(get_node_count() == restart_baseline, "replay %d does not accumulate scene nodes" % iteration)
	_check(_checkpoint_files() == checkpoint_before, "replay %d does not write progression" % iteration)
	return true


func _test_pause() -> void:
	_push_escape()
	await _frames(3, false)
	_check(paused and level._pause_panel.visible, "Escape opens keepers pause")
	var before := level.player.global_position
	Input.action_press(&"move_right")
	await _frames(10, false)
	Input.action_release(&"move_right")
	_check(level.player.global_position.is_equal_approx(before), "keepers pause freezes real movement input")
	await _shot("pause", false)
	_push_escape()
	await _frames(4, false)
	_check(not paused and not level._pause_panel.visible, "Escape resumes keepers")


func _compare_camera(label: String) -> void:
	level.camera_follow = false
	level._update_room_camera()
	level.player.presentation._update_camera(0.0)
	await _frames(4)
	var fixed := level.player.presentation.camera.global_transform
	await _shot(label + "-fixed-center")
	level.camera_follow = true
	level._update_room_camera()
	level.player.presentation._update_camera(0.0)
	await _frames(4)
	var follow := level.player.presentation.camera.global_transform
	var center: Vector3 = level.get_meta(&"isometric_camera_center")
	_check(follow.origin.distance_to(fixed.origin) > 0.5 and absf(follow.origin.y - fixed.origin.y) < 0.001
		and follow.basis.is_equal_approx(fixed.basis), "camera comparison changes horizontal framing only at " + label)
	_check(absf(center.x) <= 3.501 and absf(center.z) <= 2.801, "camera follow remains within room bounds at " + label)
	samples.append({"kind": "camera", "label": label, "hero": _xyz(level.player.global_position),
		"fixed": _xyz(fixed.origin), "follow": _xyz(follow.origin), "center": _xyz(center)})
	await _shot(label + "-clamped-follow")


func _drive(target: Vector3, limit: int = 240) -> bool:
	var start := level.player.global_position
	for frame in limit:
		var offset := target - level.player.global_position
		if Vector2(offset.x, offset.z).length() < 0.10:
			_release_movement()
			await _frames(8)
			samples.append({"kind": "walk", "from": _xyz(start), "target": _xyz(target), "end": _xyz(level.player.global_position), "frames": frame})
			return true
		_steer(target)
		await _frames(1)
	_release_movement()
	_check(false, "physical walk timed out: %s -> %s, ended %s" % [start, target, level.player.global_position])
	return false


func _jump_to(target: Vector3, hold_frames: int, label: String) -> Dictionary:
	_release_movement()
	await _frames(8)
	var start := level.player.global_position
	var peak := start.y
	var minimum_camera_y := level.player.presentation.camera.global_position.y
	var maximum_camera_y := minimum_camera_y
	Input.action_press(&"jump")
	await _frames(hold_frames)
	Input.action_release(&"jump")
	var airborne := false
	var reached := false
	var landed := false
	var landing_support: Dictionary = {}
	for frame in 125:
		var offset := target - level.player.global_position
		reached = Vector2(offset.x, offset.z).length() < 0.12
		if reached:
			_release_movement()
		else:
			_steer(target)
		await _frames(1)
		peak = maxf(peak, level.player.global_position.y)
		minimum_camera_y = minf(minimum_camera_y, level.player.presentation.camera.global_position.y)
		maximum_camera_y = maxf(maximum_camera_y, level.player.presentation.camera.global_position.y)
		airborne = airborne or not level.player.is_on_floor()
		if airborne and level.player.is_on_floor():
			landing_support = _bridge_support(target)
			landed = bool(landing_support["supported"])
			break
		if frame == 14:
			await _shot(label + "-airborne", true, 0)
	_release_movement()
	await _frames(10)
	var settled_support := _bridge_support(target)
	landed = landed and bool(settled_support["supported"])
	var result := {"kind": "jump", "label": label, "from": _xyz(start), "target": _xyz(target),
		"end": _xyz(level.player.global_position), "peak": peak, "landed": landed,
		"camera_y_range": maximum_camera_y - minimum_camera_y, "hold_frames": hold_frames,
		"landing_support": landing_support, "settled_support": settled_support}
	samples.append(result)
	print("KEEPERS_JUMP ", JSON.stringify(result))
	await _shot(label + "-landing")
	return result


func _bridge_support(target: Vector3) -> Dictionary:
	var at := level.player.global_position
	var capsule := level.player.collision_shape.shape as CapsuleShape3D
	var radius := capsule.radius
	var expected_name := "BridgeWest" if target.x < 0.0 else "BridgeEast"
	var expected_body := level.geometry.get_node_or_null(expected_name)
	var x_min := -2.7 + radius if target.x < 0.0 else 0.7 + radius
	var x_max := -0.7 - radius if target.x < 0.0 else 2.7 - radius
	var inside := at.x >= x_min and at.x <= x_max and at.z >= 0.6 + radius and at.z <= 2.2 - radius
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.08, at + Vector3.DOWN * 0.25, 1)
	var hit := level.player.get_world_3d().direct_space_state.intersect_ray(query)
	var support_matches: bool = expected_body != null and not hit.is_empty() and hit["collider"] == expected_body
	return {"supported": level.player.is_on_floor() and absf(at.y - 0.04) < 0.10 and inside and support_matches,
		"position": _xyz(at), "expected_body": expected_name, "support_matches": support_matches,
		"fully_inside": inside, "capsule_radius": radius, "x_bounds": [x_min, x_max], "z_bounds": [0.6 + radius, 2.2 - radius]}


func _steer(target: Vector3) -> void:
	_release_movement()
	var direction := target - level.player.global_position
	direction.y = 0
	var axes := level.player.controls.world_direction_to_screen_axes(direction.normalized())
	Input.action_press(&"move_right" if axes.x >= 0 else &"move_left", absf(axes.x))
	Input.action_press(&"move_back" if axes.y >= 0 else &"move_forward", absf(axes.y))


func _release_movement() -> void:
	for action in [&"move_left", &"move_right", &"move_forward", &"move_back"]:
		Input.action_release(action)


func _press_named(owner: Node, button_name: String) -> bool:
	var button := owner.find_child(button_name, true, false) as Button
	_check(button != null and button.is_visible_in_tree(), "available UI button " + button_name)
	if button == null or not button.is_visible_in_tree():
		return false
	button.pressed.emit()
	return true


func _push_escape() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event)


func _frames(count: int, resume: bool = true) -> void:
	for frame in count:
		if resume and is_instance_valid(level) and paused and not level.finished:
			level._resume_game()
		await physics_frame
		await process_frame


func _shot(label: String, resume: bool = true, settle_frames: int = 5) -> void:
	if not capture:
		return
	root.grab_focus()
	await _frames(settle_frames, resume)
	RenderingServer.force_draw()
	var image := root.get_texture().get_image()
	var path := output_dir + label + ".png"
	var result := image.save_png(path)
	_check(result == OK, "native image " + label)
	if result == OK:
		captures.append(path)


func _checkpoint_files() -> Dictionary:
	var state := {}
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp", ".rejected"]:
		var path: String = "user://checkpoint.json" + suffix
		state[path] = FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "<missing>"
	return state


func _xyz(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _check(value: bool, label: String) -> void:
	assertions += 1
	if not value:
		failures += 1
	checks.append({"status": "PASS" if value else "FAIL", "label": label})
	print(("PASS " if value else "FAIL ") + label)


func _finish(code: int) -> void:
	if _finishing:
		return
	_finishing = true
	_release_movement()
	Input.action_release(&"jump")
	Input.action_release(&"interact")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	var file := FileAccess.open(output_dir + "result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"status": "BLOCKED" if code == 2 else ("PASS" if code == 0 else "FAIL"),
			"exit_code": code, "assertions": assertions, "failures": failures, "capture": capture,
			"display": DisplayServer.get_name(), "checks": checks, "samples": samples, "images": captures,
			"manual_playthrough": "NOT_RUN", "audio_listening": "NOT_RUN",
			"traversal": "Input actions and physical movement; only out-of-bounds test injects a position; UI buttons emit their real signals"}, "\t") + "\n")
	else:
		printerr("FAIL could not write keepers result.json")
		code = 1
	print("KEEPERS_RESULT assertions=%d failures=%d exit_code=%d" % [assertions, failures, code])
	quit(code)
