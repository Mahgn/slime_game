extends SceneTree

const ROUTE = preload("res://scenes/opening/opening_route.tscn")
const OUTPUT := "res://output/opening_rooms_2026_10_06/images/"
var route: SlimeOpeningRoute
var failures := 0
var capture := false
var samples: Array = []


func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	call_deferred("_run")


func _run() -> void:
	var watchdog := Timer.new()
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.wait_time = 160.0
	watchdog.one_shot = true
	root.add_child(watchdog)
	watchdog.timeout.connect(func() -> void: printerr("FAIL opening watchdog"); quit(124))
	watchdog.start()
	if capture and DisplayServer.get_name() == "headless":
		printerr("BLOCKED opening capture needs a native window")
		quit(2)
		return
	SlimeGameSettings.current().load_settings("res://output/opening_rooms_2026_10_06/test_settings.cfg")
	var checkpoint_before := _checkpoint()
	change_scene_to_file("res://scenes/launch.tscn")
	await _frames(8)
	var menu := current_scene as Control
	(menu.find_child("PlayButton",true,false) as Button).pressed.emit()
	await _frames(12)
	route = current_scene as SlimeOpeningRoute
	_check(is_instance_valid(route),"Play opens the new route")
	if not is_instance_valid(route): quit(1); return
	_check(route.player.is_on_floor() and route.room_index == 0,"fresh start at the bottom of the fissure")
	_check(get_nodes_in_group(&"enemies").is_empty(),"opening has no enemies")
	await _shot("01-start")
	# Compare the two existing camera behaviours in the same geometry.
	var center: Vector3 = route.get_meta(&"isometric_camera_center")
	var start_camera := route.player.camera.global_position
	route.remove_meta(&"isometric_camera_center")
	route.player.presentation._update_camera(0.0)
	await _shot("01-follow-comparison")
	_check(route.player.camera.global_position.distance_to(start_camera)>0.5,"room centre and following are actually compared")
	route.set_meta(&"isometric_camera_center",center)
	route.player.presentation._update_camera(0.0)
	await _drive(route.world_point(Vector3(4.5,0,3.8)))
	await _drive(route.world_point(Vector3(5.5,0,3)))
	await _jump_to(route.world_point(Vector3(5.8,0.35,1.9)),"P01 basic jump takes the low shelf")
	await _drive(route.exit_position())
	_check(route._can_exit(),"P01 exit is reachable and grounded")
	await _shot("01-exit")
	await _interact()
	_check(route.room_index==1 and route.player.is_on_floor(),"E enters the crescent room")
	_check(route.player._ground_trail._samples.is_empty(),"room transition clears the previous floor trail")
	await _shot("02-start")
	for raw: Array in route.rooms[1].route:
		await _drive(_v(raw))
	_check(route._can_exit(),"dry crescent reaches the arch without a jump")
	await _shot("02-exit")
	# Walk into the shallow basin and back on the same physical support.
	route.player.global_position=route.world_point(Vector3(6,0.4,3.5))
	route.player.velocity=Vector3.ZERO
	await _frames(8)
	await _drive(route.world_point(Vector3(3.7,0.35,3.5)))
	_check(route.player.is_on_floor(),"basin opening has solid, accessible support")
	await _shot("02-basin")
	await _drive(route.world_point(Vector3(6,0.35,3.5)))
	for raw: Array in route.rooms[1].route.slice(7): await _drive(_v(raw))
	await _interact()
	_check(route.room_index==2 and route.player.is_on_floor(),"E enters the broken gallery")
	await _shot("03-start")
	var steps: Array=route.rooms[2].route
	await _drive(_v(steps[1]))
	await _drive(_v(steps[2]))
	await _jump_to(_v(steps[3]),"first curved gap is reachable with the basic jump")
	await _shot("03-middle")
	await _drive(_v(steps[4]))
	await _drive(_v(steps[5]))
	await _jump_to(_v(steps[6]),"second curved gap is reachable with the basic jump")
	await _drive(route.exit_position())
	_check(route._can_exit(),"upper gallery exit is reachable")
	await _shot("03-upper")
	# Reset only for an independent failure/recovery scenario; walk the gap without jumping.
	route.player.global_position=_v(steps[2])+Vector3.UP*0.04
	route.player.velocity=Vector3.ZERO
	await _frames(10)
	var low: Array=route.rooms[2].recoveryRoute
	await _drive(_v(low[0]),180)
	await _frames(35)
	print("RECOVERY_SAMPLE ",route.player.global_position," expected ",_v(low[0]))
	_check(route.player.is_on_floor() and absf(route.player.global_position.y+0.8)<0.1,"missed jump lands on the visible lower floor without respawn")
	await _shot("03-recovery")
	for raw: Array in low.slice(1): await _drive(_v(raw),180)
	_check(route.player.is_on_floor() and absf(route.player.global_position.y-0.35)<0.1,"lower path and sloped ramp return to A")
	await _shot("03-ramp-return")
	# Visual occlusion never removes a physical wall; restore on exit.
	var collider_count := route.geometry.find_children("*","CollisionShape3D",true,false).size()
	var visibility_checked := false
	for target: Vector3 in [route.world_point(Vector3(6.8,-0.75,6.9)),_v(steps[4]),_v(steps[6])]:
		route.player.global_position=target+Vector3.UP*0.05
		route.player.velocity=Vector3.ZERO
		await _frames(12)
		route.player.presentation._update_occlusion()
		visibility_checked=visibility_checked or not route.player.presentation.hidden.is_empty()
	_check(visibility_checked and route.geometry.find_children("*","CollisionShape3D",true,false).size()==collider_count,"cutaway activates while physical geometry stays intact")
	var previously_hidden: Array=route.player.presentation.hidden.duplicate()
	route.player.global_position=route.spawn_position()+Vector3.UP*0.04
	route.player.velocity=Vector3.ZERO
	await _frames(12)
	route.player.presentation._update_occlusion()
	var restored:=false
	for mesh in previously_hidden:
		restored=restored or mesh.visible
	_check(restored,"cutaway restores geometry when the hero leaves its shadow")
	var paused_position := route.player.global_position
	route._pause_game()
	Input.action_press(&"move_right")
	await _frames(10,false)
	Input.action_release(&"move_right")
	_check(paused and route.player.global_position.is_equal_approx(paused_position),"pause freezes movement in the new route")
	await _shot("03-pause")
	route._resume_game()
	route.player.global_position=route.exit_position()+Vector3.UP*0.04
	route.player.velocity=Vector3.ZERO
	await _frames(10)
	await _interact()
	_check(route.finished and paused and route._ending.visible,"last E shows continuation and stops the scene")
	await _shot("03-end")
	_check(_checkpoint()==checkpoint_before,"new route leaves old save facts untouched")
	# Full restart cleans geometry, transient effects and the hero.
	var node_count:=get_node_count()
	for iteration in 10:
		paused=false
		change_scene_to_file("res://scenes/opening/opening_route.tscn")
		await _frames(10)
		route=current_scene as SlimeOpeningRoute
		_check(route.room_index==0 and route.player.is_on_floor(),"restart %d starts grounded" % iteration)
		if iteration==0: node_count=get_node_count()
		_check(get_node_count()==node_count,"restart %d has no accumulating scene nodes" % iteration)
	_check(_checkpoint()==checkpoint_before,"repeated runs do not write progression")
	route._pause_panel._go_to_menu()
	await _frames(8)
	_check(current_scene is Control and get_nodes_in_group(&"player").is_empty() and not paused,"route returns to menu and frees the hero")
	print("OPENING_RESULT failures=%d" % failures)
	quit(0 if failures==0 else 1)


func _checkpoint() -> String:
	return FileAccess.get_file_as_string("user://checkpoint.json") if FileAccess.file_exists("user://checkpoint.json") else "<missing>"


func _v(raw: Array) -> Vector3:
	return route.world_point(Vector3(float(raw[0]),float(raw[1]),float(raw[2])))


func _frames(count: int, resume: bool = true) -> void:
	for i in count:
		if resume and is_instance_valid(route) and paused and not route.finished:
			route._resume_game()
		await physics_frame
		await process_frame


func _release() -> void:
	for action in [&"move_forward",&"move_back",&"move_left",&"move_right"]: Input.action_release(action)


func _steer(target: Vector3) -> void:
	_release()
	var dir: Vector3=target-route.player.global_position
	dir.y=0
	dir=dir.normalized()
	var x:=dir.dot(route.player.camera_yaw.global_basis.x)
	var z:=dir.dot(route.player.camera_yaw.global_basis.z)
	Input.action_press(&"move_right" if x>=0 else &"move_left",absf(x))
	Input.action_press(&"move_back" if z>=0 else &"move_forward",absf(z))


func _drive(target: Vector3, limit: int = 160) -> void:
	for i in limit:
		var offset:=target-route.player.global_position
		if Vector2(offset.x,offset.z).length()<0.12:
			_release()
			await _frames(6)
			return
		_steer(target)
		await _frames(1)
	_release()
	_check(false,"walk timed out to %s from %s" % [target,route.player.global_position])


func _jump_to(target: Vector3, message: String) -> void:
	var initial_y:=route.player.global_position.y
	var initial_position:=route.player.global_position
	Input.action_press(&"jump")
	_steer(target)
	await _frames(2)
	Input.action_release(&"jump")
	await _drive(target)
	await _frames(25)
	print("JUMP_SAMPLE ",initial_position," -> ",target," ended ",route.player.global_position)
	_check(route.player.is_on_floor() and absf(route.player.global_position.y-target.y)<0.10 and route.player.global_position.y>initial_y+0.25,message)


func _interact() -> void:
	Input.action_press(&"interact")
	await _frames(2)
	Input.action_release(&"interact")
	await _frames(12)


func _shot(label: String) -> void:
	if not capture:return
	root.grab_focus()
	if paused and not route.finished and not label.ends_with("pause"):
		route._resume_game()
	await _frames(8,false)
	RenderingServer.force_draw()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var image:=root.get_texture().get_image()
	var result:=image.save_png(OUTPUT+label+".png")
	_check(result==OK,"native capture "+label)


func _check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ")+message)
	if not value: failures+=1
