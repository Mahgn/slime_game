extends SceneTree

const PLAYER := preload("res://scenes/player/slime_player.tscn")
const CONTROLLER := preload("res://scripts/player/slime_controller.gd")
var failures := 0
var assertions := 0
var player: SlimeController


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# SceneTree scripts start with a 64x64 headless window. Match the configured
	# viewport so screen events are not stretched a second time by input routing.
	root.size = Vector2i(1280, 720)
	var watchdog := Timer.new()
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.one_shot = true
	watchdog.wait_time = 35.0
	root.add_child(watchdog)
	watchdog.timeout.connect(func() -> void: printerr("FAIL foundation watchdog"); quit(124))
	watchdog.start()
	preload("res://scripts/input_setup.gd").install()
	var fixture := Node3D.new()
	fixture.set_meta(&"isometric_camera_center", Vector3(0, 0.45, 0))
	fixture.set_meta(&"isometric_dressing_owned", true)
	var floor_body := StaticBody3D.new()
	floor_body.position.y = -0.2
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(30, 0.4, 30)
	collision.shape = shape
	floor_body.add_child(collision)
	fixture.add_child(floor_body)
	root.add_child(fixture)
	var startup_motion := InputEventMouseMotion.new()
	startup_motion.position = Vector2(140, 180)
	startup_motion.global_position = startup_motion.position
	Input.parse_input_event(startup_motion)
	Input.flush_buffered_events()
	await _frames(1)
	# Native DisplayServer reads the OS cursor; synthetic motion does not move it.
	# Use that actual position for synchronization, while headless verifies the
	# deliberately injected coordinates exactly.
	var startup_pointer := startup_motion.position if DisplayServer.get_name() == "headless" else root.get_mouse_position()
	player = PLAYER.instantiate() as SlimeController
	player.position.y = 0.05
	fixture.add_child(player)
	await _frames(20)
	print("FOUNDATION_POINTER startup=", player.controls.pointer, " viewport=", root.get_mouse_position(), " expected=", startup_pointer, " viewport_size=", root.size)
	_check(player.controls.pointer.distance_to(startup_pointer) < 0.01,
		"spawn initializes aim from the existing viewport pointer position")
	var controller_script: Script = player.get_script()
	_check(controller_script == CONTROLLER and controller_script.get_base_script() == null,
		"player runs the shared CharacterBody3D controller without a third-person subclass")
	_check(player.find_children("*", "SpringArm3D", true, false).is_empty()
		and player.find_child("CameraYaw", true, false) == null
		and player.find_child("CameraPitch", true, false) == null,
		"player scene has no legacy camera rig")
	_check(player.controls is SlimeIsometricInput and player.presentation is SlimeIsometricPresentation,
		"player scene owns separate input and presentation components")
	var camera := player.presentation.camera
	var camera_before := camera.global_transform
	var right_before := player.screen_movement_direction(Vector2.RIGHT)
	player.rotation.y = 1.37
	await _frames(8)
	_check(camera.global_transform.is_equal_approx(camera_before), "physical root rotation leaves the room camera unchanged")
	_check(player.screen_movement_direction(Vector2.RIGHT).is_equal_approx(right_before),
		"physical root rotation leaves screen movement directions unchanged")
	var start := player.global_position
	Input.action_press(&"move_right")
	await _frames(18)
	Input.action_release(&"move_right")
	await _frames(8)
	var screen_displacement := camera.unproject_position(player.global_position) - camera.unproject_position(start)
	_check(player.global_position.distance_to(start) > 1.0 and screen_displacement.normalized().dot(Vector2.RIGHT) > 0.99,
		"D still physically moves right on screen after rotating the root")
	var passage := Node.new()
	fixture.add_child(passage)
	player.set_low_passage_active(passage, true)
	await _frames(10)
	_check(player.is_compressed() and camera.global_transform.is_equal_approx(camera_before),
		"actual compressed stance leaves the room camera unchanged")
	player.set_low_passage_active(passage, false)
	await _frames(10)
	_check(not player.is_compressed() and camera.global_transform.is_equal_approx(camera_before),
		"standing up leaves the room camera unchanged")
	var settings := SlimeGameSettings.current()
	var previous_shake := settings.camera_shake
	settings.camera_shake = 1.0
	player._hit_pulse = 0.3
	player._landing_pulse = 0.12
	await _frames(4)
	_check(camera.global_transform.is_equal_approx(camera_before),
		"legacy shake setting cannot alter the fixed isometric camera")
	settings.camera_shake = previous_shake
	player._hit_pulse = 0.0
	player._landing_pulse = 0.0

	# No mouse-motion event precedes this click: its own coordinates must aim
	# the real input-triggered attack instead of the previous pointer position.
	var click_target := player.global_position + Vector3(3.0, player._combat_origin_height(), 0.0)
	var click_position := camera.unproject_position(click_target)
	player.controls.pointer = camera.unproject_position(player.global_position + Vector3.FORWARD * 3.0)
	var casts_before := player._cast_sequence
	_mouse_button(click_position, true)
	await _frames(2)
	print("FOUNDATION_POINTER click=", player.controls.pointer, " expected=", click_position, " aim=", player.controls.get_aim_point(), " target=", click_target, " casts=", player._cast_sequence-casts_before, " direction=", player._action_direction)
	_check(player.controls.pointer.distance_to(click_position) < 0.01
		and player.controls.get_aim_point().distance_to(click_target) < 0.05,
		"mouse click updates the world aim without an earlier motion event")
	_check(player._cast_sequence == casts_before + 1 and player._action_direction.dot(Vector3.RIGHT) > 0.99,
		"the same click starts exactly one whip toward its own position")
	_mouse_button(click_position, false)
	await _frames(50)
	_check(camera.global_transform.is_equal_approx(camera_before), "aiming and attacking do not rotate or move the camera")

	# The pointer moves while gameplay input is paused. Resuming without a
	# further motion or click must refresh aim before the next action.
	player.clear_action_buffer()
	var resume_target := player.global_position + Vector3(0.0, player._combat_origin_height(), -3.0)
	var resume_position := camera.unproject_position(resume_target)
	var paused_position := player.global_position
	paused = true
	var motion := InputEventMouseMotion.new()
	motion.position = resume_position
	motion.global_position = resume_position
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await _frames(4)
	_check(player.global_position.is_equal_approx(paused_position), "pointer movement during pause does not move the hero")
	if DisplayServer.get_name() != "headless":
		resume_position = root.get_mouse_position()
		var aim_plane := Plane(Vector3.UP, player.global_position.y + player._combat_origin_height())
		resume_target = aim_plane.intersects_ray(camera.project_ray_origin(resume_position), camera.project_ray_normal(resume_position))
	# Make stale aim explicit in either display mode; unpause must replace it.
	player.controls.pointer = resume_position + Vector2(170, 90)
	paused = false
	await _frames(2)
	print("FOUNDATION_POINTER resume=",player.controls.pointer," viewport=",root.get_mouse_position()," expected=",resume_position)
	_check(player.controls.pointer.distance_to(resume_position) < 0.01
		and player.controls.get_aim_point().distance_to(resume_target) < 0.05,
		"resume refreshes the pointer moved during pause without another mouse event")
	casts_before = player._cast_sequence
	Input.action_press(&"attack_primary")
	await _frames(2)
	Input.action_release(&"attack_primary")
	var resume_direction := resume_target - player.global_position
	resume_direction.y = 0.0
	_check(player._cast_sequence == casts_before + 1 and player._action_direction.dot(resume_direction.normalized()) > 0.99,
		"first action after resume uses the fresh pointer direction")
	_check(camera.global_transform.is_equal_approx(camera_before), "pause and fresh aiming preserve the camera transform")
	fixture.queue_free()
	await _frames(3)
	print("ISOMETRIC_FOUNDATION_RESULT assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _mouse_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.position = position
	event.global_position = position
	event.pressed = pressed
	Input.parse_input_event(event)


func _frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func _check(value: bool, label: String) -> void:
	assertions += 1
	print(("PASS " if value else "FAIL ") + label)
	if not value:
		failures += 1
