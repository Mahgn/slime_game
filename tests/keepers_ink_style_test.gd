extends SceneTree

# Native preset capture and interleaved movement measurements. Rendering and
# gameplay invariants are separate from the user's artistic acceptance.
var out := "res://output/keepers_comic_variants_2026_10_08/final/"
var level
var checks: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var frozen: Array[Dictionary] = []
var times: Array[float] = []
var sampling := false
var last_draw := 0
var quick := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output=res://output/"): out = arg.trim_prefix("--output=").trim_suffix("/") + "/"
		if arg == "--quick": quick = true
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("BLOCKED: this test requires a native renderer")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	SlimeGameSettings.current().load_settings(out + "settings.cfg")
	root.size = Vector2i(1280, 720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.frame_post_draw.connect(_drawn)
	create_timer(600, true).timeout.connect(func(): printerr("FAIL ink test timeout"); quit(2))
	change_scene_to_file("res://scenes/keepers/keepers_facility.tscn")
	await _ticks(35)
	level = current_scene
	if not is_instance_valid(level.ink_style):
		printerr("FAIL: style controller did not initialize")
		quit(1)
		return
	var style: SlimeKeepersInkStyle = level.ink_style
	_check(style.mode == 4, "User-selected Ink is the initial style")
	var hero: SlimeController = level.player
	var camera: Camera3D = hero.presentation.camera
	var source: ShaderMaterial = hero.get_node("VisualRoot/SlimeHeroModelV5").get_surface_override_material(0)
	var state := [hero.get_instance_id(), hero.health, hero.collision_layer, hero.collision_mask, hero.global_transform, camera.global_transform, camera.projection, camera.size, level.geometry.get_instance_id(), level.encounters.duplicate(true)]
	var shader_count := style._shaders.size()
	var material_count := style._materials.size()
	var actor_shader: Shader = source.shader
	var hazard_material: Material = level.hazards[0].warning_material
	for mode in [0, 1, 2, 3, 4, 5, 6, 0, 3, 2]:
		style.set_mode(mode)
		_check(state == [hero.get_instance_id(), hero.health, hero.collision_layer, hero.collision_mask, hero.global_transform, camera.global_transform, camera.projection, camera.size, level.geometry.get_instance_id(), level.encounters], "Mode %d preserves world, camera, collision and combat state" % mode)
		_check(hero.get_node("VisualRoot/SlimeHeroModelV5").get_surface_override_material(0) == source and source.shader == actor_shader, "Mode %d retains the animated hero material" % mode)
	_check(style._shaders.size() == shader_count and style._materials.size() == material_count, "Repeated switches reuse the shader/material variants")
	_check(level.hazards[0].warning_material == hazard_material, "Hazard animation keeps its live material reference")
	style.set_mode(0)
	var restored := true
	for binding in style._bindings:
		var material: Material = binding.mesh.material_override if binding.surface < 0 else binding.mesh.get_surface_override_material(binding.surface)
		restored = restored and material == binding.original
	_check(restored, "Original restores all original overrides including mesh-owned surfaces")
	_check(style._environment.ambient_light_color == style._ambient_color and is_equal_approx(style._environment.ambient_light_energy, style._ambient_energy), "Original restores the original environment")
	for expected in [1, 2, 3, 4, 5, 6, 0]:
		_key()
		await process_frame
		_check(style.mode == expected, "Real F6 input selects mode %d" % expected)
	var echo := InputEventKey.new()
	echo.physical_keycode = KEY_F6
	echo.pressed = true
	echo.echo = true
	root.push_input(echo)
	_check(style.mode == 0, "Held-key repeat does not cycle repeatedly")
	for expected in [6,5,4,3,2,1,0]:
		_key(true)
		await process_frame
		_check(style.mode == expected, "Real Shift+F6 selects previous mode %d" % expected)
	paused = true
	_key()
	await process_frame
	_check(paused and style.mode == 1, "F6 works while paused without resuming gameplay")
	paused = false
	level._resume_game()
	style.set_mode(2)
	var before_time: float = source.get_shader_parameter("gel_time")
	await _ticks(12)
	_check(float(source.get_shader_parameter("gel_time")) > before_time, "Hero gel animation continues in comic mode")
	_check(hero._action == &"", "Style switching does not trigger an attack")
	for id in level.rooms: level.cleared[id] = true
	level._spawn_wave("furnace")
	for pose: Dictionary in [
		{"name":"furnace", "at":Vector3(-10,0,-4)},
		{"name":"pump", "at":Vector3(10,0,-20)},
		{"name":"archive", "at":Vector3(-27,0,-43)},
		{"name":"collector", "at":Vector3(14.6,0,-35)}
	]:
		level._reset_position(pose.at)
		await _ticks(25)
		_freeze()
		var hud_pixel := Color()
		var comic_frame: Image
		for mode in 7:
			style.set_mode(mode)
			var frame := await _shot(pose.name + "_%d" % mode)
			if mode == 0: hud_pixel = frame.get_pixel(70, 620)
			else: _check(frame.get_pixel(70, 620).is_equal_approx(hud_pixel), "%s mode %d leaves the opaque HUD health bar unchanged" % [pose.name,mode])
			if mode == 2: comic_frame = frame
		if pose.name == "furnace":
			style.set_mode(2)
			var returned := await _shot("comic_restored")
			var region := Rect2i(200,130,620,400)
			_check(returned.get_region(region).get_data() == comic_frame.get_region(region).get_data(), "Returning from all variants restores the comic image pixel-for-pixel in the frozen room")
		_unfreeze()
	# Same active steam plume and warning material in every mode.
	level._reset_position(Vector3(-8,0,-3))
	await _ticks(15)
	_freeze()
	var hazard = level.hazards[0]
	hazard.phase = "active"
	hazard.clock = hazard.SAFE + hazard.WARNING + 0.2
	hazard._refresh_visual()
	for mode in 7:
		style.set_mode(mode)
		await _shot("steam_%d" % mode)
	_unfreeze()
	for enemy in level.alive_enemies(): enemy.queue_free()
	for hazard_node in level.hazards: hazard_node.disable()
	await _ticks(5)
	if not quick:
		# Forward and reverse mode order reduces warmup/order bias. No readbacks
		# occur while measuring. Every route uses ordinary movement actions.
		for resolution in [Vector2i(1280,720), Vector2i(1920,1080)]:
			root.size = resolution
			for mode in [2,4,5,6,6,5,4,2]:
				await _measure(mode)
	# Record the actual final movement separately from measurements.
	root.size = Vector2i(1280,720)
	for mode in [2,4,5,6]:
		style.set_mode(mode)
		level._reset_position(Vector3(-6.3,0,13))
		await _ticks(20)
		for tick in 72:
			_walk_towards(Vector3(-10.6,0,13) if tick<36 else Vector3(-6.3,0,13))
			await _ticks(1)
			if tick % 4 == 0: await _shot("motion_%d_%03d" % [mode,tick/4])
		_release()
	style.set_mode(3)
	await _shot("dark_final")
	var old_outline = weakref(style.outline)
	level.restart_run()
	await _ticks(40)
	level = current_scene
	_check(old_outline.get_ref() == null, "Restart releases the old camera outline")
	_check(level.player.presentation.camera.find_children("GeometryInk","MeshInstance3D",false,false).size() == 1, "Restart creates exactly one camera outline")
	var failed := checks.any(func(c: Dictionary) -> bool: return not c.pass)
	var budget_failed := samples.any(func(s: Dictionary) -> bool: return s.p95_ms > 16.67)
	FileAccess.open(out + "results.json", FileAccess.WRITE).store_string(JSON.stringify({"status":"FAIL" if failed else "PASS", "checks":checks, "performance":samples, "frame_budget":"NOT_RUN" if quick else ("FAIL" if budget_failed else "PASS"), "renderer":RenderingServer.get_current_rendering_method(), "device":RenderingServer.get_video_adapter_name(), "shader_variants":shader_count, "material_variants":material_count, "art_acceptance":"PENDING"}, "\t"))
	print("INK_STYLE_RESULT checks=",checks.size()," failures=",checks.filter(func(c:Dictionary)->bool:return not c.pass).size()," samples=",samples.size())
	quit(1 if failed else 0)

func _key(backwards: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F6
	event.shift_pressed = backwards
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)

func _freeze() -> void:
	for node in [level] + level.find_children("*", "Node", true, false):
		frozen.append({"node":node,"process":node.is_processing(),"physics":node.is_physics_processing()})
		node.set_process(false)
		node.set_physics_process(false)

func _unfreeze() -> void:
	for entry in frozen:
		if is_instance_valid(entry.node):
			entry.node.set_process(entry.process)
			entry.node.set_physics_process(entry.physics)
	frozen.clear()

func _measure(mode: int) -> void:
	level.ink_style.set_mode(mode)
	level._reset_position(Vector3(-6.3,0,13))
	await _ticks(35)
	times.clear()
	sampling = true
	var crossings := 0
	var target := Vector3(-10.6,0,13)
	for tick in 150:
		if level.player.global_position.distance_to(target)<0.24:
			crossings += 1
			target = Vector3(-6.3,0,13) if target.x < -8.0 else Vector3(-10.6,0,13)
		_walk_towards(target)
		await _ticks(1)
	sampling = false
	_release()
	times.sort()
	_check(crossings >= 2, "Mode %d at %dp crosses the doorway with normal movement" % [mode,root.size.y])
	samples.append({"mode":mode,"resolution":[root.size.x,root.size.y],"frames":times.size(),"median_ms":times[times.size()/2],"p95_ms":times[int(times.size()*0.95)],"max_ms":times[-1],"crossings":crossings,"fixture":"cleared encounters; moving hero and camera; active game; screenshot readback excluded; inter-draw wall time, not GPU timestamps"})
	print("INK_PERF ",JSON.stringify(samples[-1]))

func _walk_towards(target: Vector3) -> void:
	var direction: Vector3 = target - level.player.global_position
	direction.y = 0
	var axes: Vector2 = level.player.controls.world_direction_to_screen_axes(direction.normalized())
	Input.action_press(&"move_right",maxf(axes.x,0))
	Input.action_press(&"move_left",maxf(-axes.x,0))
	Input.action_press(&"move_back",maxf(axes.y,0))
	Input.action_press(&"move_forward",maxf(-axes.y,0))

func _release() -> void:
	for action in [&"move_right",&"move_left",&"move_back",&"move_forward"]: Input.action_release(action)

func _drawn() -> void:
	var now := Time.get_ticks_usec()
	if sampling: times.append(float(now-last_draw)/1000.0)
	last_draw = now

func _shot(name: String) -> Image:
	await _ticks(3)
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	frame.save_png(out + name + ".png")
	return frame

func _ticks(count: int) -> void:
	for i in count:
		if is_instance_valid(current_scene) and current_scene.has_method("_resume_game"): current_scene._resume_game()
		await physics_frame
		await process_frame

func _check(ok: bool, label: String) -> void:
	checks.append({"pass":ok,"label":label})
	print("PASS " if ok else "FAIL ", label)
