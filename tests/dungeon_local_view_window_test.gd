extends "res://tests/dungeon_camera_rotation_test.gd"

var window: RefCounted
var window_trace: Array[Dictionary] = []
var trace_active := false

func _initialize() -> void:
	out = "res://output/local_view_window_2026_10_15/native/"
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--capture": capture = true
		if arg.begins_with("--output=res://output/"): out = arg.trim_prefix("--output=").trim_suffix("/")+"/"
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out+"images"))
	SlimeGameSettings.current().load_settings(out+"settings.cfg")
	SlimeGameSettings.current().camera_shake = 0.0
	seed(4873)
	create_timer(210.0,true).timeout.connect(func() -> void: _check(false,"bounded watchdog"); _finish())
	if DisplayServer.get_name()=="headless": capture = false
	else:
		root.size = Vector2i(1280,720)
		DisplayServer.window_set_size(root.size)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		RenderingServer.frame_post_draw.connect(_sample_frame)
	change_scene_to_file(SCENE)
	await _ticks(25)
	level = current_scene as SlimeKeepersWorld
	await _wait_ready()
	window = level.geometry.cutaway.local_window
	_check(window != null,"authored local window initialized")
	if window == null: _finish(); return
	_freeze_enemies()
	geometry_before = _geometry_signature()
	_check(window.walls.size()>2 and window.meshes.has(level.geometry.building_crown.mesh_instance),"both passage sides, adjacent jambs and continuous crown are bound")
	_check(window.meshes.all(func(mesh: MeshInstance3D) -> bool: return not String(mesh.get_path()).contains("Floor") and not String(mesh.get_path()).contains("Membrane")),"floors and gameplay barrier excluded from masking")
	_check(not level.geometry.cutaway.enabled and level.geometry.building_crown.visible,"whole-room fading remains disabled")
	await _ticks(40)
	_check(is_zero_approx(window.amount),"start room remains fully closed outside pilot passage")
	var view: SlimeIsometricPresentation = level.player.presentation
	for angle: int in 4:
		_check(absf(wrapf(view.camera_yaw-angle*PI/2.0,-PI,PI))<0.001,"distinct camera angle %d" % angle)
		for spot: Dictionary in [{"id":"west","x":-4.4},{"id":"center","x":-0.6},{"id":"east","x":5.4}]:
			level._reset_position(Vector3(spot.x,0,-18))
			await _ticks(55)
			_check(_uniforms_match(),"all architectural materials share mask at %s/%d" % [spot.id,angle])
			await _shot("intact-%s-%d" % [spot.id,angle])
		_check(level.membrane.intact and level.membrane.collision_layer==1 and level.membrane.visible,"membrane remains a visible physical obstacle %d" % angle)
		_gesture(-70)
		await _ticks(26)
	# A complete walk is possible only after the actual acid interaction opens it.
	level.membrane.receive_dungeon_property(&"acid_spit",1)
	level.membrane.receive_dungeon_property(&"acid_spit",1)
	await _ticks(3)
	_check(not level.membrane.intact and level.membrane.collision_layer==0,"existing acid interaction opens passage for route checks")
	for angle: int in 4:
		level._reset_position(Vector3(-0.6,0,-18))
		await _ticks(50)
		_check(window.amount>0.99,"window fully reveals narrow corridor %d" % angle)
		_check(_protected_points_clear(),"hero and nearby floor rays clear actual architecture %d" % angle)
		await _shot("open-center-%d" % angle)
		await _stationary_edge_check(angle)
		window_trace.clear()
		trace_active = true
		await _cross(Vector3(-7.0,0,-18),Vector3(7.5,0,-18),"window-%d-forward" % angle)
		await _cross(Vector3(7.5,0,-18),Vector3(-7.0,0,-18),"window-%d-return" % angle)
		trace_active = false
		FileAccess.open(out+"angle-%d.trace.json" % angle,FileAccess.WRITE).store_string(JSON.stringify(window_trace,"\t"))
		_check(_trace_continuous(),"rendered mask has bounded frame changes and stays open through room seams %d" % angle)
		level._reset_position(Vector3(-0.6,0,-18))
		await _ticks(50)
		_gesture(-70)
		var retained := true
		for frame: int in 25:
			await _ticks(1)
			retained = retained and window.amount>0.99
			if frame==8: await _shot("turn-%d-middle" % angle)
		_check(retained,"quarter turn never closes/reopens the passage window %d" % angle)
	await _boundary_and_restore()
	await _style_zoom_pause_jump()
	await _wall_and_aim_local()
	_check(_geometry_signature()==geometry_before,"all original geometry colliders unchanged by reveal, rotation and F6")
	var previous := window
	level.restart_run()
	await _ticks(25)
	level = current_scene as SlimeKeepersWorld
	await _wait_ready()
	window = level.geometry.cutaway.local_window
	await _ticks(40)
	_check(window != previous and is_zero_approx(window.amount) and not window.target,"restart discards window state and starts with full walls")
	_check(level.membrane.intact,"restart restores gameplay barrier independently")
	await _shot("restart")
	_finish()

func _uniforms_match() -> bool:
	for material: ShaderMaterial in window.materials:
		if not is_equal_approx(float(material.get_shader_parameter("view_window_amount")),window.amount): return false
		if not (material.get_shader_parameter("view_window_center") as Vector3).is_equal_approx(window.center): return false
		if not (material.get_shader_parameter("view_window_back") as Vector3).is_equal_approx(window.camera.global_basis.z): return false
	return true

func _stationary_edge_check(angle: int) -> void:
	if not capture: return
	await RenderingServer.frame_post_draw
	var before := root.get_texture().get_image()
	var pixel_center: Vector2 = window.camera.unproject_position(window.center)
	var radius: Vector2 = Vector2(2.7,2.15)*float(root.size.y)/window.camera.size
	await _ticks(30)
	await RenderingServer.frame_post_draw
	var after := root.get_texture().get_image()
	var sampled := 0
	var changed := 0
	# The settled fade edge, outside the animated body, is compared in real
	# GPU images. Animated water/enemies elsewhere do not define wall flicker.
	for y: int in range(int(pixel_center.y-radius.y*1.08),int(pixel_center.y+radius.y*1.08)):
		for x: int in range(int(pixel_center.x-radius.x*1.08),int(pixel_center.x+radius.x*1.08)):
			var distance: float = ((Vector2(x,y)-pixel_center)/radius).length()
			if distance<0.88 or distance>1.07: continue
			var a := before.get_pixel(x,y)
			var b := after.get_pixel(x,y)
			sampled += 1
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>0.035: changed += 1
	print("WINDOW_EDGE_PIXELS angle=",angle," changed=",changed," sampled=",sampled)
	_check(sampled>500 and float(changed)/sampled<0.005,"stationary rendered window edge remains stable %d" % angle)

func _sample_frame() -> void:
	super._sample_frame()
	if trace_active and window != null:
		window_trace.append({"usec":Time.get_ticks_usec(),"amount":window.amount,"target":window.target,"x":level.player.global_position.x,"z":level.player.global_position.z,"room":level.room_id})

func _trace_continuous() -> bool:
	if not capture: return true
	var good := window_trace.size()>60
	for i: int in range(1,window_trace.size()):
		var before := window_trace[i-1]
		var after := window_trace[i]
		var dt := float(after.usec-before.usec)/1000000.0
		good = good and absf(after.amount-before.amount)<=dt/window.OPEN_SECONDS+0.04
		if after.x> -3.6 and after.x<4.6: good = good and after.amount>0.99
	return good

func _protected_points_clear() -> bool:
	var hero := level.player.global_position
	for p: Vector3 in [hero+Vector3.UP*0.45,hero+Vector3.UP*0.8,Vector3(hero.x-0.8,0.1,hero.z),Vector3(hero.x+0.8,0.1,hero.z)]:
		var back: Vector3 = window.camera.global_basis.z
		for section: Dictionary in window.walls:
			var body: StaticBody3D = section.body
			var shape: BoxShape3D = body.get_child(0).shape
			var hit: Variant = AABB(-shape.size*0.5,shape.size).intersects_segment(body.to_local(p+back*12),body.to_local(p))
			if hit != null and window.coverage_at(body.to_global(hit))<0.98: return false
		var top: Vector3 = p+back*((level.geometry.building_crown.top_height-p.y)/back.y)
		if not level.geometry.building_crown._is_open(Vector2(top.x,top.z)) and window.coverage_at(top)<0.98: return false
	return true

func _boundary_and_restore() -> void:
	level._reset_position(Vector3(-4,0,-18))
	await _ticks(55)
	var stable := true
	for frame: int in 90:
		# Oscillate across the ENTER boundary while staying within EXIT margin.
		level._reset_position(Vector3(-5.8+sin(frame*0.4)*0.18,0,-18))
		await _ticks(1)
		stable = stable and window.target and window.amount>0.99
	_check(stable,"repeated approach boundary reversals do not blink")
	level._reset_position(Vector3(-10,0,-18))
	await _ticks(8)
	_check(window.amount>0.99,"release hold prevents immediate closure")
	await _ticks(65)
	_check(is_zero_approx(window.amount),"leaving pilot restores entire shell")
	await _shot("restored")
	for room: String in ["entry","spring","hub"]:
		level._reset_position(level.rooms[room].spawn)
		await _ticks(50)
		_check(is_zero_approx(window.amount),"no local window in unrelated room "+room)

func _style_zoom_pause_jump() -> void:
	level._reset_position(Vector3(-0.6,0,-18))
	await _ticks(5)
	var partial: float = window.amount
	_check(partial>0.0 and partial<1.0,"opening spans multiple frames")
	await _shot("opening-partial")
	level.hud.toggle_map()
	partial = window.amount # PNG readback advanced a frame before the pause.
	await _ticks(12,false)
	_check(is_equal_approx(window.amount,partial),"map pause freezes local transition")
	level.hud.close_map()
	await _ticks(55)
	for style: int in 7:
		level.ink_style.set_mode(style)
		_check(_uniforms_match() and window.amount>0.99,"F6 preserves current mask immediately in style %d" % style)
	level.ink_style.set_mode(4)
	for zoom: float in [9.0,18.0]:
		level.player.presentation.zoom_target = zoom
		await _ticks(45)
		_check(_protected_points_clear(),"protected area retained at zoom %.1f" % zoom)
		await _shot("zoom-%d" % int(zoom))
	level.player.presentation.zoom_target = 13.0
	Input.action_press(&"jump")
	await _ticks(24)
	Input.action_release(&"jump")
	var peak := 0.0
	var clear := true
	for frame: int in 75:
		await _ticks(1)
		peak = maxf(peak,level.player.global_position.y)
		clear = clear and _protected_points_clear() and window.amount>0.99
		if frame==15: await _shot("jump")
	_check(peak>0.6 and level.player.is_on_floor(),"charged jump still takes off and lands")
	_check(clear,"jump never closes window or hides protected hero points")

func _wall_and_aim_local() -> void:
	level._reset_position(Vector3(-0.6,0,-18))
	await _ticks(40)
	var target := CharacterBody3D.new()
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
	target.global_position = Vector3(-1.6,0,-18)
	await _ticks(3)
	var expected := target.global_position+Vector3.UP*0.45
	level.player.controls.pointer = window.camera.unproject_position(expected)
	_check(level.player.controls.get_aim_point().distance_to(expected)<0.01,"camera aim reaches target through locally revealed architecture")
	window.enabled = false
	await _ticks(60)
	_check(level.player.controls.get_aim_point().distance_to(expected)>0.05,"restored wall blocks actor selection again")
	window.enabled = true
	await _ticks(40)
	target.queue_free()
	var blocked := false
	for frame: int in 55:
		_walk_towards(Vector3(-0.6,0,-21))
		await _ticks(1)
		blocked = blocked or level.player.get_slide_collision_count()>0
	_release()
	_check(blocked and level.player.global_position.z> -19.1,"walking into revealed side wall remains physically blocked")
	var hit := level.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-0.6,0.8,-18),Vector3(-0.6,0.8,-21),1))
	_check(not hit.is_empty(),"ordinary combat/world ray still collides with revealed wall")

func _finish() -> void:
	if finished: return
	finished = true
	_release()
	var failed := checks.any(func(item: Dictionary) -> bool: return not item.pass)
	var report := {"status":"FAIL" if failed else "PASS","checks":checks,"records":records,"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name(),"scope":"Native four-angle membrane passage pilot. Frozen nonblocking enemies. Eight physical crossings after real membrane property interaction; window state traces, screenshots, pause, F6, zoom, jump, aim, wall collision and restart. Frame intervals exclude screenshot readback. No full-combat or human input acceptance claim."}
	FileAccess.open(out+"results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("LOCAL_VIEW_WINDOW_RESULT checks=",checks.size()," failures=",checks.filter(func(item: Dictionary) -> bool: return not item.pass).size())
	quit(1 if failed else 0)
