extends SceneTree

var route: SlimeOpeningRoute
var output_dir := "res://output/opening_rooms_2026_10_06"


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			output_dir = argument.trim_prefix("--output-dir=").trim_suffix("/")
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name()=="headless":
		printerr("BLOCKED performance requires drawn native frames")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	SlimeGameSettings.current().load_settings(output_dir + "/perf_settings.cfg")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	route=preload("res://scenes/opening/opening_route.tscn").instantiate()
	root.add_child(route)
	current_scene=route
	process_frame.connect(func() -> void:
		if paused: route._resume_game())
	var results: Array=[]
	for size in [Vector2i(1280,720),Vector2i(1920,1080)]:
		DisplayServer.window_set_size(size)
		for scenario in 4:
			var index:=mini(scenario,2)
			route._enter_room(index)
			if scenario==3:
				route.player.global_position=route.world_point(Vector3(6.8,-0.75,4.9))
				route.player.velocity=Vector3.ZERO
			root.grab_focus()
			var start:=Time.get_ticks_usec()
			while Time.get_ticks_usec()-start<1500000:
				if paused:route._resume_game()
				await RenderingServer.frame_post_draw
			var raster:=root.get_texture().get_image()
			raster.save_png(output_dir + "/perf-%dx%d-%d.png" % [size.x,size.y,scenario])
			var times: Array[float]=[]
			var frame_start:=Engine.get_frames_drawn()
			var process_start:=Engine.get_process_frames()
			var last:=Time.get_ticks_usec()
			start=last
			while Time.get_ticks_usec()-start<5000000:
				if paused:route._resume_game()
				if scenario==3:
					var target:=route.world_point(Vector3(6.8,-0.8,5.9 if (Time.get_ticks_usec()/800000)%2==0 else 4.9))
					var dir:=(target-route.player.global_position).normalized()
					var axes := route.player.controls.world_direction_to_screen_axes(dir)
					for action in [&"move_right",&"move_left",&"move_back",&"move_forward"]:Input.action_release(action)
					Input.action_press(&"move_right" if axes.x>=0 else &"move_left",absf(axes.x))
					Input.action_press(&"move_back" if axes.y>=0 else &"move_forward",absf(axes.y))
				await RenderingServer.frame_post_draw
				var now:=Time.get_ticks_usec()
				times.append(float(now-last)/1000.0)
				last=now
			var drawn:=Engine.get_frames_drawn()-frame_start
			var process:=Engine.get_process_frames()-process_start
			times.sort()
			var total:=0.0
			for value in times:total+=value
			for action in [&"move_right",&"move_left",&"move_back",&"move_forward"]:Input.action_release(action)
			var result: Dictionary={"room":index+1,"scenario":"lower-path-motion" if scenario==3 else "room-start","requestedSize":[size.x,size.y],"viewportSize":[root.size.x,root.size.y],
				"samples":times.size(),"drawnFrames":drawn,"processFrames":process,"meanMs":total/times.size(),
				"p95Ms":times[int(times.size()*0.95)],"maximumMs":times[-1],
				"drawCalls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				"rasterSize":[raster.get_width(),raster.get_height()],"gpuTimestamps":"NOT_RUN","fpsMonitor":Performance.get_monitor(Performance.TIME_FPS)}
			result["status"]="PASS" if result.p95Ms<16.67 and drawn==times.size() and root.size==size else "FAIL"
			results.append(result)
			print(JSON.stringify(result))
	var file:=FileAccess.open(output_dir + "/performance.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t"))
	var failed:=false
	for result: Dictionary in results:failed=failed or result.status=="FAIL"
	print("PERFORMANCE_RESULT "+("FAIL" if failed else "PASS"))
	quit(1 if failed else 0)
