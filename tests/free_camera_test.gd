extends "res://tests/visibility_combat_test.gd"

var anchor := Vector2(610, 350)
var replay_filter: Node

class ReplayMouseFilter extends Node:
	func _input(event: InputEvent) -> void:
		# Windows emits its own zero-button motion when capture warps a pointer.
		# Isolate the replayed mouse stream from the physical desktop mouse.
		if (event is InputEventMouseMotion or event is InputEventMouseButton) and event.device != 63027:
			get_viewport().set_input_as_handled()

func _fresh_scene(mode: int) -> bool:
	var ready: bool = await super._fresh_scene(mode)
	if not is_instance_valid(replay_filter):
		replay_filter = ReplayMouseFilter.new()
		replay_filter.process_mode = Node.PROCESS_MODE_ALWAYS
		root.add_child(replay_filter)
	root.move_child(replay_filter,root.get_child_count()-1)
	return ready

func _initialize() -> void:
	out = "res://output/free_camera_2026_10_15/native/"
	part = "free-camera"
	super._initialize()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out + "images"))
	SlimeGameSettings.current().load_settings(out + "settings.cfg")
	SlimeGameSettings.current().camera_shake = 0.0
	create_timer(235.0, true).timeout.connect(func() -> void: _check(false, "bounded free camera watchdog"); _finish())
	node_added.connect(_watch_projectile)
	if DisplayServer.get_name() == "headless": capture = false
	else:
		root.size = Vector2i(1280,720)
		DisplayServer.window_set_size(root.size)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		RenderingServer.frame_post_draw.connect(_sample_frame)
	if not await _fresh_scene(0): _finish(); return
	level.set_camera_mode(1)
	var signature: Dictionary = _geometry_signature()
	var actors: Array = _actor_state()
	await _gesture_checks()
	for degrees: float in [13.0, 37.0, 112.0, 203.0]:
		await _drag_to(degrees)
		await _movement_check(degrees)
		await _aim_check(degrees)
	await _moving_jump()
	await _interruption_checks()
	_check(_geometry_signature() == signature and _actor_state() == actors, "camera input preserves all physical walls and frozen actor state")
	await _open_membrane(0)
	for spot: Dictionary in [{"id":"west", "at":Vector3(-5.5,0,-18)}, {"id":"threshold", "at":Vector3(-0.6,0,-18)}, {"id":"east", "at":Vector3(5.5,0,-18)}]:
		level._reset_position(spot.at)
		await _ticks(25)
		for index: int in 16:
			await _drag_to(float(index)*22.5)
			var record: Dictionary = _visibility_record(0,index,spot.id)
			record["yaw_degrees"] = rad_to_deg(_view().camera_yaw)
			visibility.append(record)
			if index in [0,2,4,6,8,10,12,14]:
				await _shot("%s-yaw-%03d" % [spot.id, int(index*22.5)],0,index)
		_check(_ghost_contract(0), "free orbit keeps complete architecture at " + spot.id)
	await _drag_to(45)
	await _cross(Vector3(-5.5,0,-18),Vector3(5.5,0,-18),"free-45-forward")
	await _drag_to(137)
	await _cross(Vector3(5.5,0,-18),Vector3(-5.5,0,-18),"free-137-return")
	await _wall_motion(0)
	await _mode_checks()
	# The same real fight runs while the new camera is actively turning.
	if not await _fresh_scene(0): _finish(); return
	level.set_camera_mode(1)
	await _open_membrane(0)
	level._reset_position(Vector3(-5.5,0,-18))
	await _drag_to(45)
	level.set_test_ai_paused(false)
	await _begin_sample()
	_button(true)
	var warning_frames := 0
	var rotating_frames := 0
	for tick: int in 600:
		var previous_yaw: float = _view().camera_yaw
		_motion(Vector2(-0.45,0),MOUSE_BUTTON_MASK_MIDDLE)
		var destination := Vector3(-5.2 if tick < 160 or tick > 440 else 5.8,0,-18)
		if level.player.global_position.distance_to(destination)>0.35: _walk_towards(destination)
		else: _release()
		await _ticks(1)
		if absf(wrapf(_view().camera_yaw-previous_yaw,-PI,PI))>0.001: rotating_frames += 1
		for enemy: Spitter in level.comparison_enemies():
			if enemy.ground_warning.visible: warning_frames += 1
		if not level.player.is_alive(): break
	_button(false)
	_release()
	_end_sample("free-rotation-live-combat")
	_check(level.enemy_shots.values().all(func(count: int) -> bool: return count >= 1) and warning_frames>10, "all four original enemies attack with warnings during continuous free rotation")
	_check(rotating_frames>=580, "camera continues responding through the real battle without losing the held gesture")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "live combat releases the camera cursor")
	records.append({"case":"free-live-combat", "enemy_shots":level.enemy_shots.duplicate(), "warning_frames":warning_frames, "rotating_frames":rotating_frames, "hp":level.player.health, "yaw":rad_to_deg(_view().camera_yaw)})
	await _shot("free-live-end",0,0)
	await _restart_and_death()
	_finish()

func _button(down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.device = 63027
	event.button_index = MOUSE_BUTTON_MIDDLE
	event.pressed = down
	event.position = anchor
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _motion(delta: Vector2, mask: int) -> void:
	var event := InputEventMouseMotion.new()
	event.device = 63027
	event.relative = delta
	event.position = anchor + delta
	event.button_mask = mask
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _drag_to(degrees: float) -> void:
	var delta := wrapf(deg_to_rad(degrees) - _view().camera_yaw,-PI,PI)
	if absf(delta) < 0.0001: return
	var pixels := -delta / SlimeIsometricPresentation.FREE_ROTATION_RADIANS_PER_PIXEL
	pixels += signf(pixels)*SlimeIsometricInput.FREE_DRAG_THRESHOLD
	_button(true)
	for step: int in 12:
		_motion(Vector2(pixels/12.0,0),MOUSE_BUTTON_MASK_MIDDLE)
		await _ticks(1)
	_button(false)
	await _ticks(4)
	records.append({"case":"drag", "target":degrees, "yaw":rad_to_deg(_view().camera_yaw), "paused":paused, "capture":Input.mouse_mode})
	_check(absf(wrapf(_view().camera_yaw-deg_to_rad(degrees),-PI,PI)) < 0.001, "actual drag reaches free angle %.1f without snapping" % degrees)

func _gesture_checks() -> void:
	_button(true)
	_motion(Vector2(2,80),MOUSE_BUTTON_MASK_MIDDLE)
	await _ticks(2)
	_check(is_zero_approx(_view().camera_yaw), "vertical drag and initial hand jitter do not rotate")
	_motion(Vector2(1400,0),MOUSE_BUTTON_MASK_MIDDLE)
	await _ticks(2)
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and level.player.controls.pointer.is_equal_approx(anchor), "held camera captures relative motion and preserves the screen aim anchor")
	print("FREE_GESTURE_STATE yaw=", _view().camera_yaw, " paused=", paused, " mouse=", Input.mouse_mode, " anchor=",level.player.controls.pointer)
	var expected := wrapf(-(1402.0-3.0)*0.006,-PI,PI)
	_check(absf(wrapf(_view().camera_yaw-expected,-PI,PI))<0.001, "long drag continues beyond quarter and full revolutions")
	_button(false)
	var released: float = _view().camera_yaw
	await _ticks(35)
	_check(is_equal_approx(_view().camera_yaw,released) and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "release stops exactly at the selected angle without inertia and restores cursor")
	_motion(Vector2(100,0),0)
	await _ticks(2)
	_check(is_equal_approx(_view().camera_yaw,released), "ordinary pointer movement does not rotate camera")
	_check(level.player._action == &"", "camera gesture does not trigger an ability")

func _movement_check(degrees: float) -> void:
	var directions_ok := true
	var speeds_ok := true
	for axis: Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(1,1),Vector2(-1,1),Vector2(1,-1),Vector2(-1,-1)]:
		level._reset_position(Vector3(0,0,14))
		await _ticks(3)
		var before: Vector3 = level.player.global_position
		_set_axes(axis.normalized())
		await _ticks(15)
		var pixels: Vector2 = _view().camera.unproject_position(level.player.global_position)-_view().camera.unproject_position(before)
		for component: int in 2:
			directions_ok = directions_ok and (absf(pixels[component])<0.1 if axis[component]==0 else pixels[component]*axis[component]>1.0)
		var speed := Vector2(level.player.velocity.x,level.player.velocity.z).length()
		speeds_ok = speeds_ok and speed>5.1 and speed<5.3
		_release()
	_check(directions_ok and speeds_ok, "eight physical directions and unchanged speed at %.1f degrees" % degrees)

func _set_axes(axis: Vector2) -> void:
	_release()
	Input.action_press(&"move_right",maxf(axis.x,0))
	Input.action_press(&"move_left",maxf(-axis.x,0))
	Input.action_press(&"move_back",maxf(axis.y,0))
	Input.action_press(&"move_forward",maxf(-axis.y,0))

func _aim_check(degrees: float) -> void:
	level._reset_position(Vector3(0,0,14))
	await _ticks(5)
	var wanted: Vector3 = level.player.global_position + Vector3(-1.6,level.player._combat_origin_height(),-1.2)
	var screen: Vector2 = _view().camera.unproject_position(wanted)
	var event := InputEventMouseMotion.new()
	event.device = 63027
	event.position = screen
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	_check(level.player.controls.get_aim_point().distance_to(wanted)<0.01, "screen pointer ray reaches its real world aiming plane at %.1f degrees" % degrees)

func _moving_jump() -> void:
	level._reset_position(Vector3(0,0,14))
	await _ticks(8)
	Input.action_press(&"jump")
	await _ticks(48)
	var charged: float = level.player.get_jump_charge_ratio()
	Input.action_release(&"jump")
	_button(true)
	var peak := 0.0
	var correct_direction := true
	var correct_aim := true
	for tick: int in 65:
		_motion(Vector2(1.5,0),MOUSE_BUTTON_MASK_MIDDLE)
		Input.action_press(&"move_forward")
		var before: Vector3 = level.player.global_position
		await _ticks(1)
		peak = maxf(peak,level.player.global_position.y)
		var horizontal: Vector3 = level.player.global_position
		horizontal.y = before.y
		correct_direction = correct_direction and (_view().camera.unproject_position(horizontal)-_view().camera.unproject_position(before)).y < -0.001
		var aim: Vector3 = level.player.controls.get_aim_point()
		correct_aim = correct_aim and _view().camera.unproject_position(aim).distance_to(anchor)<1.0
	_button(false)
	_release()
	await _ticks(15)
	records.append({"case":"rotating-jump", "charge":charged, "peak":peak, "landed":level.player.is_on_floor(), "screen_direction":correct_direction})
	_check(charged>0.99 and peak>1.7 and level.player.is_on_floor(), "full charged jump rises and lands during free rotation")
	_check(correct_direction, "held W stays screen-oriented throughout a rotating jump")
	_check(correct_aim, "aim remains at its screen anchor throughout moving and jumping free rotation")

func _interruption_checks() -> void:
	for reason: String in ["pause","map","focus","lost-button"]:
		_button(true)
		_motion(Vector2(20,0),MOUSE_BUTTON_MASK_MIDDLE)
		await _ticks(2)
		var yaw: float = _view().camera_yaw
		if reason == "pause": paused = true
		elif reason == "map": level.hud.toggle_map()
		elif reason == "focus": level.player.controls.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
		else: _motion(Vector2(20,0),0)
		await _ticks(3)
		_motion(Vector2(60,0),MOUSE_BUTTON_MASK_MIDDLE)
		if reason == "map": level.hud.close_map()
		else: paused = false
		_motion(Vector2(60,0),MOUSE_BUTTON_MASK_MIDDLE)
		await _ticks(3)
		_check(is_equal_approx(_view().camera_yaw,yaw) and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, reason + " cancels capture without delayed rotation on return")
		_button(false)

func _mode_checks() -> void:
	await _drag_to(37)
	var state: Array = _actor_state()
	level.set_camera_mode(0)
	_check(absf(rad_to_deg(_view().camera_yaw)-37)<0.01, "switch to quarter mode preserves current angle")
	_button(true)
	_motion(Vector2(-70,0),MOUSE_BUTTON_MASK_MIDDLE)
	_button(false)
	await _ticks(25)
	_check(absf(rad_to_deg(_view().camera_yaw)-127)<0.01, "quarter gesture advances exactly 90 degrees from an arbitrary starting angle")
	level.set_camera_mode(1)
	_check(absf(rad_to_deg(_view().camera_yaw)-127)<0.01 and _actor_state()==state, "return to free mode preserves view and fight")
	level.set_compare_mode(1)
	await _drag_to(61)
	await _ticks(60)
	_check(_ghost_contract(1), "optional reveal also works at arbitrary camera angle")
	level.set_compare_mode(0)
	await _ticks(60)
	_check(_ghost_contract(0), "returning to full walls restores all structure")

func _restart_and_death() -> void:
	_button(true)
	level.reset_comparison(0)
	await _ticks(3)
	level = current_scene
	for tick: int in 900:
		if is_instance_valid(level) and level.ready_for_comparison: break
		await _ticks(1)
	_check(level.ready_for_comparison and paused and level.camera_mode==1 and level.compare_mode==0 and is_zero_approx(_view().camera_yaw), "restart retains chosen modes but starts from a fresh initial angle")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "restart during drag restores cursor for the start panel")
	level.set_test_ai_paused(true)
	level.start_comparison()
	await _ticks(3)
	_button(true)
	level.player.health = 0
	await _ticks(3)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not level.player.controls._camera_dragging, "death releases held camera capture")
