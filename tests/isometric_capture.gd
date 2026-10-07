extends SceneTree

const OUTPUT := "res://output/play_entry/images/"
var capture_phase := "startup"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("BLOCKED MENU_CAPTURE: native window required")
		quit(2)
		return
	var watchdog := Timer.new()
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.wait_time = 20.0
	watchdog.one_shot = true
	root.add_child(watchdog)
	watchdog.timeout.connect(func() -> void: printerr("FAIL native capture watchdog at " + capture_phase); quit(124))
	watchdog.start()
	root.grab_focus()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	SlimeGameSettings.current().load_settings("res://output/play_entry/menu_test_settings.cfg")
	var menu := preload("res://scenes/launch.tscn").instantiate() as Control
	root.add_child(menu)
	current_scene = menu
	await _frames(12)
	await _capture("menu")
	(menu.find_child("SettingsButton", true, false) as Button).pressed.emit()
	await _frames(8)
	await _capture("settings")
	_press_escape()
	await _frames(8)
	if menu._settings_panel.visible or not menu._main_panel.visible:
		printerr("FAIL native Escape did not close settings")
		quit(1)
		return
	await _capture("menu-return")
	capture_phase = "Play click"
	await _click(menu.find_child("PlayButton", true, false) as Button)
	await _physics_frames(15)
	var workspace := current_scene as SlimeLevelWorkspace
	if not is_instance_valid(workspace):
		printerr("FAIL native Play button did not open the starting scene")
		quit(1)
		return
	await _capture("play")
	var start := workspace.player.global_position
	Input.action_press(&"move_right")
	await _physics_frames(16, &"move_right")
	Input.action_release(&"move_right")
	if workspace.player.global_position.distance_to(start) < 0.5:
		printerr("FAIL native movement after Play: paused=%s input=%s position=%s start=%s" % [paused, Input.is_action_pressed(&"move_right"), workspace.player.global_position, start])
		quit(1)
		return
	await _capture("movement")
	Input.action_press(&"jump")
	await _physics_frames(16, &"jump")
	Input.action_release(&"jump")
	await _physics_frames(12)
	await _capture("jump")
	await _physics_frames(36)
	workspace.player.pointer = workspace.player.camera.unproject_position(workspace.player.global_position + Vector3.FORWARD * 2.0)
	Input.action_press(&"attack_primary")
	await _physics_frames(6, &"attack_primary")
	Input.action_release(&"attack_primary")
	await _capture("whip")
	await _physics_frames(30)
	_press_escape()
	await _frames(5)
	if not paused or not workspace._pause_panel.visible:
		printerr("FAIL native pause after Play")
		quit(1)
		return
	await _capture("pause")
	for button in workspace._pause_panel._main_box.get_children():
		if button is Button and button.text == "В меню":
			button.pressed.emit()
			break
	for button in workspace._pause_panel._confirm.find_children("*", "Button", true, false):
		if button.text == "Выйти в меню":
			button.pressed.emit()
			break
	await _frames(8)
	menu = current_scene as Control
	if not is_instance_valid(menu) or paused:
		printerr("FAIL native return to main menu")
		quit(1)
		return
	await _capture("play-return")
	print("PASS native Play click, movement, jump, whip, pause, menu return and viewport captures")
	await _click(menu.find_child("ExitButton", true, false) as Button)


func _frames(count: int) -> void:
	for frame in count:
		await process_frame


func _physics_frames(count: int, held_action: StringName = &"") -> void:
	for frame in count:
		# The desktop may focus Codex when a tool yields. Resume through the
		# normal pause-menu signal; production focus-loss pausing stays enabled.
		if current_scene is SlimeLevelWorkspace and paused:
			print("INFO capture resumes after desktop focus loss")
			root.grab_focus()
			(current_scene as SlimeLevelWorkspace)._pause_panel.resume_requested.emit()
		if held_action != &"" and not Input.is_action_pressed(held_action):
			Input.action_press(held_action)
		await physics_frame
		await process_frame


func _click(button: Button) -> void:
	print("CLICK ", button.text)
	var point := button.get_global_transform_with_canvas() * (button.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = motion.position
	root.push_input(motion, true)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.button_mask = MOUSE_BUTTON_MASK_LEFT
	click.position = point
	click.global_position = click.position
	click.pressed = true
	root.push_input(click, true)
	await process_frame
	click = click.duplicate() as InputEventMouseButton
	click.pressed = false
	click.button_mask = 0
	root.push_input(click, true)


func _press_escape() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event)
	event = event.duplicate() as InputEventKey
	event.pressed = false
	root.push_input(event)


func _capture(label: String) -> void:
	capture_phase = label
	print("CAPTURE ", label)
	# Capture after the normal camera process, including the spring-arm update.
	call_deferred("_draw_capture_frame")
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	var result := screenshot.save_png(OUTPUT + label + ".png")
	if result != OK:
		printerr("FAIL screenshot %s: %d" % [label, result])
		quit(1)


func _draw_capture_frame() -> void:
	RenderingServer.force_draw(true, 0.0)
