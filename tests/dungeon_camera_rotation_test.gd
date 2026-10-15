extends "res://tests/dungeon_wall_fade_test.gd"

var capture_pointer := Vector2(640,360)

func _initialize() -> void:
	out = "res://output/camera_rotation_2026_10_15/native/"
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--capture": capture = true
		if arg.begins_with("--output=res://output/"): out = arg.trim_prefix("--output=").trim_suffix("/") + "/"
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out + "images"))
	SlimeGameSettings.current().load_settings(out + "settings.cfg")
	SlimeGameSettings.current().camera_shake = 0.0
	seed(4873)
	create_timer(180.0, true).timeout.connect(func() -> void: _check(false,"bounded watchdog"); _finish())
	if DisplayServer.get_name() == "headless": capture = false
	else:
		root.size = Vector2i(1280,720)
		DisplayServer.window_set_size(root.size)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		RenderingServer.frame_post_draw.connect(_sample_frame)
	change_scene_to_file(SCENE)
	await _ticks(25)
	level = current_scene as SlimeKeepersWorld
	await _wait_ready()
	_check(is_instance_valid(level) and not level._transitioning,"real dungeon ready")
	if not is_instance_valid(level): _finish(); return
	_freeze_enemies()
	geometry_before = _geometry_signature()
	var view: SlimeIsometricPresentation = level.player.presentation
	_check(view.quarter_turns_enabled,"rotation is enabled explicitly for this dungeon")
	if not view.quarter_turns_enabled: _finish(); return
	_check(not level.geometry.cutaway.enabled and level.geometry.building_crown.visible and not level.geometry.has_node("HybridRoomArchitecture"),"original full shell is active without hybrid or fade")
	var original_basis := view.camera.global_basis
	await _gesture_contract()
	for angle: int in 4:
		_check(absf(wrapf(view.camera_yaw-angle*PI/2.0,-PI,PI))<0.001,"camera has reached distinct quarter angle %d" % angle)
		for spot: Dictionary in [{"id":"entry","at":Vector3(-3.4,0,14)}, {"id":"threshold","at":Vector3(-8.5,0,14)}, {"id":"spring","at":Vector3(-13.6,0,14)}]:
			level._reset_position(spot.at)
			await _ticks(30)
			await _shot("%s-angle-%d" % [spot.id,angle])
		await _movement_checks(angle)
		await _aim_check(angle)
		await _cross(Vector3(-6.2,0,14),Vector3(-10.8,0,14),"angle-%d-forward" % angle)
		await _cross(Vector3(-10.8,0,14),Vector3(-6.2,0,14),"angle-%d-return" % angle)
		_check(_full_walls(),"all structural walls remain fully visible at angle %d" % angle)
		await _turn_while_moving(angle)
	_check(view.camera.global_basis.is_equal_approx(original_basis),"four gestures return exactly to the original camera basis")
	_check(_geometry_signature() == geometry_before,"rotation and all physical crossings preserve the same colliders")
	var zoom := view.zoom_target
	_button(MOUSE_BUTTON_WHEEL_UP,true)
	_check(is_equal_approx(view.zoom_target,zoom-1.0),"wheel still controls zoom")
	view.zoom_target = zoom
	level.ink_style.cycle_style(1)
	await _ticks(3)
	_check(_full_walls(),"F6 keeps the complete shell visible")
	level.ink_style.cycle_style(-1)
	await _jump_during_turn()
	level._reset_position(Vector3(0,0,14))
	_gesture(-70)
	await _ticks(5)
	var paused_yaw := view.camera_yaw
	level.hud.toggle_map()
	await _ticks(5,false)
	_check(paused and is_equal_approx(view.camera_yaw,paused_yaw),"map pause freezes an in-progress camera turn")
	level.hud.close_map()
	await _ticks(30)
	_check(not view.is_camera_turning(),"closing map finishes the same turn")
	var old_player: SlimeController = level.player
	level.restart_run()
	await _ticks(25)
	level = current_scene as SlimeKeepersWorld
	await _wait_ready()
	_freeze_enemies()
	_check(level.player != old_player and is_zero_approx(level.player.presentation.camera_yaw),"restart restores the initial angle with a fresh input owner")
	_check(_full_walls(),"restart keeps full walls without retained fade")
	await _shot("restart")
	_finish()

func _gesture_contract() -> void:
	var view: SlimeIsometricPresentation = level.player.presentation
	level._reset_position(Vector3(0,0,14))
	await _ticks(3)
	_motion(Vector2(200,0),0)
	_button(MOUSE_BUTTON_MIDDLE,true)
	_motion(Vector2(15,100),MOUSE_BUTTON_MASK_MIDDLE)
	_button(MOUSE_BUTTON_MIDDLE,false)
	await _ticks(24)
	_check(is_zero_approx(view.camera_yaw),"pointer motion, small jitter and vertical drag do not rotate")
	_button(MOUSE_BUTTON_MIDDLE,true)
	_motion(Vector2(70,0),MOUSE_BUTTON_MASK_MIDDLE)
	await _ticks(25)
	_motion(Vector2(350,0),MOUSE_BUTTON_MASK_MIDDLE)
	await _ticks(25)
	_button(MOUSE_BUTTON_MIDDLE,false)
	_check(is_equal_approx(view.camera_yaw,-PI/2.0),"one long held drag makes only one quarter turn")
	_gesture(-70)
	await _ticks(25)
	_check(is_zero_approx(view.camera_yaw),"opposite gesture returns the camera")
	_check(level.player._action == &"","middle-button gesture does not activate combat actions")
	_button(MOUSE_BUTTON_MIDDLE,true)
	_motion(Vector2(20,0),MOUSE_BUTTON_MASK_MIDDLE)
	level.player.controls.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_motion(Vector2(70,0),MOUSE_BUTTON_MASK_MIDDLE)
	_button(MOUSE_BUTTON_MIDDLE,false)
	await _ticks(25)
	_check(is_zero_approx(view.camera_yaw),"focus-loss notification cancels a pending drag")
	_button(MOUSE_BUTTON_MIDDLE,true)
	_motion(Vector2(20,0),MOUSE_BUTTON_MASK_MIDDLE)
	paused = true
	await _ticks(2,false)
	paused = false
	_motion(Vector2(70,0),MOUSE_BUTTON_MASK_MIDDLE)
	_button(MOUSE_BUTTON_MIDDLE,false)
	await _ticks(25)
	_check(is_zero_approx(view.camera_yaw),"pause cancels an unfinished gesture without a deferred turn")

func _movement_checks(angle: int) -> void:
	var directions_ok := true
	var speeds_ok := true
	for axis: Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(1,1),Vector2(-1,1),Vector2(1,-1),Vector2(-1,-1)]:
		level._reset_position(Vector3(0,0,14))
		await _ticks(3)
		var before := level.player.global_position
		_set_axes(axis.normalized())
		await _ticks(15)
		var after := level.player.global_position
		var camera: Camera3D = level.player.presentation.camera
		var pixels := camera.unproject_position(after)-camera.unproject_position(before)
		for component: int in 2:
			directions_ok = directions_ok and (absf(pixels[component]) < 0.1 if axis[component] == 0.0 else pixels[component]*axis[component] > 1.0)
		var speed := Vector2(level.player.velocity.x,level.player.velocity.z).length()
		speeds_ok = speeds_ok and speed > 5.1 and speed < 5.3
		_release()
	_check(directions_ok,"eight physical movement directions match the screen at angle %d" % angle)
	_check(speeds_ok,"cardinal and diagonal physical speeds remain 5.2 at angle %d" % angle)

func _aim_check(angle: int) -> void:
	level._reset_position(Vector3(0,0,14))
	var target := CharacterBody3D.new()
	target.name = "OrbitAimProbe"
	target.collision_layer = 4
	target.collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.0
	capsule.radius = 0.3
	shape.shape = capsule
	shape.position.y = 0.5
	target.add_child(shape)
	level.add_child(target)
	target.global_position = Vector3(1.4,0,13)
	await _ticks(3)
	var view: SlimeIsometricPresentation = level.player.presentation
	view.set_process(false)
	var expected := target.global_position + Vector3.UP * 0.45
	level.player.controls.pointer = view.camera.unproject_position(expected)
	_check(level.player.controls.get_aim_point().distance_to(expected)<0.001,"current camera ray selects a real actor at angle %d" % angle)
	SlimeGameSettings.current().camera_shake = 1.0
	view.play_combat_impact(Vector3.RIGHT,1.0)
	view._update_camera(0.01)
	_check(level.player.controls.get_aim_point().distance_to(expected)<0.001 and absf(view.get_combat_camera_offset().dot(view.camera.global_basis.z))<0.0001,"combat camera kick preserves aim and image plane at angle %d" % angle)
	SlimeGameSettings.current().camera_shake = 0.0
	view._update_camera(0.0)
	view.set_process(true)
	target.queue_free()
	await _ticks(2)

func _turn_while_moving(angle: int) -> void:
	level._reset_position(Vector3(0,0,14))
	await _ticks(3)
	var view: SlimeIsometricPresentation = level.player.presentation
	var start := view.camera_yaw
	var previous := 0.0
	var monotonic := true
	var moving_up := true
	var intermediate := 0
	_gesture(-70)
	for frame: int in 28:
		var before := level.player.global_position
		if frame == 4: _gesture(-70) # A second gesture must not queue another spin.
		_set_axes(Vector2.UP)
		await _ticks(1)
		var amount := wrapf(view.camera_yaw-start,0.0,TAU)
		if amount > 0.001 and amount < PI/2.0-0.001: intermediate += 1
		monotonic = monotonic and amount >= previous-0.0001 and amount <= PI/2.0+0.0001
		previous = amount
		var delta_pixels := view.camera.unproject_position(level.player.global_position)-view.camera.unproject_position(before)
		moving_up = moving_up and delta_pixels.y < -0.01
		if frame == 8: await _shot("turn-%d-middle" % angle)
	_release()
	_check(monotonic and intermediate>=5 and not view.is_camera_turning(),"quarter turn interpolates smoothly without overshoot %d" % angle)
	_check(moving_up,"holding W keeps moving up-screen during turn %d" % angle)

func _jump_during_turn() -> void:
	level._reset_position(Vector3(0,0,14))
	await _ticks(8)
	var view: SlimeIsometricPresentation = level.player.presentation
	var camera_y := view.center.y
	var start_y := level.player.global_position.y
	Input.action_press(&"jump")
	await _ticks(24)
	_gesture(-70)
	await _ticks(3)
	Input.action_release(&"jump")
	var peak := 0.0
	var camera_lift := 0.0
	for frame: int in 70:
		await _ticks(1)
		peak = maxf(peak,level.player.global_position.y-start_y)
		camera_lift = maxf(camera_lift,absf(view.center.y-camera_y))
	_check(peak>0.6 and level.player.is_on_floor(),"charged jump still takes off and lands during a camera turn")
	_check(camera_lift<0.05 and not view.is_camera_turning(),"camera turn preserves the established ground-height follow during jump")
	_check(_full_walls() and _geometry_signature()==geometry_before,"jump and rotation preserve full walls and physical structure")
	_gesture(70)
	await _ticks(25)

func _full_walls() -> bool:
	return not level.geometry.cutaway.enabled and level.geometry.building_crown.visible and level.geometry.cutaway.structural_sections.all(func(section: Dictionary) -> bool: return section.node.is_visible_in_tree() and is_zero_approx(section.reveal_amount))

func _set_axes(axes: Vector2) -> void:
	_release()
	if axes.x>0: Input.action_press(&"move_right",axes.x)
	if axes.x<0: Input.action_press(&"move_left",-axes.x)
	if axes.y>0: Input.action_press(&"move_back",axes.y)
	if axes.y<0: Input.action_press(&"move_forward",-axes.y)

func _gesture(distance: float) -> void:
	_button(MOUSE_BUTTON_MIDDLE,true)
	_motion(Vector2(distance,0),MOUSE_BUTTON_MASK_MIDDLE)
	_button(MOUSE_BUTTON_MIDDLE,false)

func _button(index: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.position = capture_pointer
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _motion(relative: Vector2, mask: int) -> void:
	var event := InputEventMouseMotion.new()
	event.position = capture_pointer+relative
	event.relative = relative
	event.button_mask = mask
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _finish() -> void:
	if finished: return
	finished = true
	_release()
	var failed: bool = checks.any(func(item: Dictionary) -> bool: return not item.pass)
	FileAccess.open(out+"results.json",FileAccess.WRITE).store_string(JSON.stringify({"status":"FAIL" if failed else "PASS","checks":checks,"records":records,"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name(),"scope":"Four camera directions, injected mouse gestures, physical movement and crossings. Enemies frozen. Inter-draw timing, not GPU or user/device acceptance."},"\t"))
	print("CAMERA_ROTATION_RESULT checks=",checks.size()," failures=",checks.filter(func(item: Dictionary) -> bool: return not item.pass).size())
	quit(1 if failed else 0)
