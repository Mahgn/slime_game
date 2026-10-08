extends SceneTree

# Native drawn-frame sampling. Teleports only choose benchmark viewpoints;
# physical traversal belongs to keepers_world_test.gd. No GPU timing claim.
const WORLD := "res://scenes/keepers/keepers_facility.tscn"
var output_folder := "res://output/keepers_finalization_2026_10_08/performance/"
var level


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output=res://output/"):
			output_folder = arg.trim_prefix("--output=").trim_suffix("/")+"/"
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("BLOCKED seamless performance needs a native renderer")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_folder))
	SlimeGameSettings.current().load_settings(output_folder + "settings.cfg")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if change_scene_to_file(WORLD) != OK:
		printerr("FAIL seamless performance scene unavailable")
		quit(1)
		return
	for i in 120:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.scene_file_path == WORLD and is_instance_valid(current_scene.get("geometry")):
			break
	level = current_scene
	if not is_instance_valid(level) or not is_instance_valid(level.get("geometry")):
		printerr("FAIL seamless performance world did not initialize")
		quit(1)
		return
	process_frame.connect(func() -> void:
		if is_instance_valid(level) and level == current_scene:
			if paused:
				level._resume_game()
			level.player._hurt_protection_left = 60.0)
	var results: Array[Dictionary] = []
	for size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		DisplayServer.window_set_size(size)
		root.size = size
		for room: String in ["entry", "furnace", "cistern", "pump_room", "hub", "armory", "garden", "summit"]:
			level.player.global_position = {"furnace":Vector3(-9,0,-8),"hub":Vector3(-5,0,-27),"cistern":Vector3(11,0,3),"pump_room":Vector3(11,0,-16),"armory":Vector3(-12,0,-40),"garden":Vector3(14.6,0,-34)}.get(room,level.rooms[room].spawn)
			level.player.velocity = Vector3.ZERO
			root.grab_focus()
			var warm_start := Time.get_ticks_usec()
			while Time.get_ticks_usec() - warm_start < 2000000:
				await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			var image_size := image.get_size()
			image.save_png(output_folder + "%dx%d-%s.png" % [size.x, size.y, room])
			var times: Array[float] = []
			var drawn_start := Engine.get_frames_drawn()
			var start := Time.get_ticks_usec()
			var last := start
			var saw_active_hazard := false
			var maximum_local_enemies := 0
			while Time.get_ticks_usec() - start < 3000000:
				await RenderingServer.frame_post_draw
				for hazard in level.hazards:
					if hazard.phase=="active" and hazard.global_position.distance_to(level.player.global_position)<16:
						saw_active_hazard = true
				maximum_local_enemies = maxi(maximum_local_enemies,level.alive_enemies().size())
				var now := Time.get_ticks_usec()
				times.append(float(now - last) / 1000.0)
				last = now
			var drawn := Engine.get_frames_drawn() - drawn_start
			times.sort()
			var sum := 0.0
			for value: float in times:
				sum += value
			var sample: Dictionary = {
				"room": room, "viewport": [root.size.x, root.size.y], "image_size": [image_size.x, image_size.y],
				"samples": times.size(), "drawn_frames": drawn,
				"mean_ms": sum / times.size(), "p95_ms": times[int(times.size() * 0.95)], "max_ms": times[-1],
				"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				"nodes": get_node_count(), "resident_rooms": level.room_roots.size(),
				"alive_enemies": get_nodes_in_group(&"enemies").size(),
				"maximum_local_enemies":maximum_local_enemies,"saw_active_hazard":saw_active_hazard,
				"gpu_timestamps": "NOT_RUN",
				"note": "Uncapped native drawn frames, static camera, invulnerable fixture hero. Not a device-wide FPS guarantee."
			}
			sample["status"] = "PASS" if sample.p95_ms < 16.67 and drawn == times.size() and root.size == size and image_size == size else "FAIL"
			results.append(sample)
			print(JSON.stringify(sample))
	FileAccess.open(output_folder + "results.json", FileAccess.WRITE).store_string(JSON.stringify(results, "\t"))
	var failed := false
	for sample: Dictionary in results:
		failed = failed or sample.status == "FAIL"
	print("KEEPERS_WORLD_PERFORMANCE_RESULT " + ("FAIL" if failed else "PASS"))
	quit(1 if failed else 0)
