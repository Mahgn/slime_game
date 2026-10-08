extends SceneTree

const OUTPUT := "res://output/keepers_level_2026_10_08/performance"
var level: SlimeKeepersLevel


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("BLOCKED keepers performance requires native drawn frames")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	SlimeGameSettings.current().load_settings(OUTPUT + "/test_settings.cfg")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	level = preload("res://scenes/keepers/keepers_level.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	process_frame.connect(func() -> void:
		if paused: level._resume_game())
	var results: Array = []
	var locations := [Vector3(6, 0.05, 5.5), Vector3(-5.5, 0.05, -4.5), Vector3(0, -0.60, 0)]
	for size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		DisplayServer.window_set_size(size)
		for index in locations.size():
			level.player.global_position = locations[index]
			level.player.velocity = Vector3.ZERO
			level._update_room_camera()
			level.player.presentation._update_camera(0.0)
			root.grab_focus()
			var start := Time.get_ticks_usec()
			while Time.get_ticks_usec() - start < 1500000:
				await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUTPUT + "/%dx%d-%d.png" % [size.x, size.y, index])
			var times: Array[float] = []
			var frames := Engine.get_frames_drawn()
			var last := Time.get_ticks_usec()
			start = last
			while Time.get_ticks_usec() - start < 4000000:
				await RenderingServer.frame_post_draw
				var now := Time.get_ticks_usec()
				times.append(float(now - last) / 1000.0)
				last = now
			var drawn := Engine.get_frames_drawn() - frames
			times.sort()
			var total := 0.0
			for value in times: total += value
			var result := {"scenario": index, "viewport": [root.size.x, root.size.y],
				"samples": times.size(), "drawnFrames": drawn, "meanMs": total / times.size(),
				"p95Ms": times[int(times.size() * 0.95)], "maxMs": times[-1],
				"drawCalls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				"gpuTimestamps": "NOT_RUN"}
			result.status = "PASS" if result.p95Ms < 16.67 and drawn == times.size() and root.size == size else "FAIL"
			results.append(result)
			print(JSON.stringify(result))
	var file := FileAccess.open(OUTPUT + "/results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	var failed := false
	for result: Dictionary in results: failed = failed or result.status == "FAIL"
	print("KEEPERS_PERFORMANCE_RESULT " + ("FAIL" if failed else "PASS"))
	quit(1 if failed else 0)
