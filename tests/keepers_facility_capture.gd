extends SceneTree

var output_folder := "res://output/keepers_finalization_2026_10_08/"
var level
var stats: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output=res://output/"):
			output_folder = arg.trim_prefix("--output=").trim_suffix("/")+"/"
	root.size = Vector2i(1280,720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_folder+"art"))
	SlimeGameSettings.current().load_settings(output_folder+"art_fixture.cfg")
	change_scene_to_file("res://scenes/keepers/keepers_facility.tscn")
	await _ticks(20)
	level = current_scene
	if not is_instance_valid(level.navigation) or not is_instance_valid(level.geometry.cutaway):
		printerr("FAIL capture: facility did not initialize")
		quit(1)
		return
	for id: String in level.rooms:
		level.cleared[id] = true
	for marker in level._markers.values():
		if is_instance_valid(marker):
			marker.queue_free()
	for id: String in level.rooms:
		level._reset_position(level.rooms[id].spawn)
		await _ticks(24)
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png(output_folder+"art/"+id+".png")
		var viewpoint: Vector3 = {"furnace":Vector3(-10,0,-4),"hub":Vector3(-5,0,-24),"summit":Vector3(-2,1,-64),"pump_room":Vector3(6,0,-20)}.get(id,level.rooms[id].spawn)
		level._reset_position(viewpoint)
		await _ticks(24)
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png(output_folder+"art/"+id+"-detail.png")
		stats.append({"room":id,"images":[id+".png",id+"-detail.png"],"fixture":"relocation and cleared encounters; art only; performance uses separate drawn-frame harness"})
		print("CAPTURE ",id," ",stats[-1])
	# Additional authored-kit views use the unchanged gameplay camera. HUD and
	# dangerous-floor markings remain visible, so these are not asset turntables.
	for pose: Dictionary in [
		{"label":"furnace-workplace","at":Vector3(-14,0,-4)},
		{"label":"furnace-rear-clearance","at":Vector3(-17.4,0,-11.8)},
		{"label":"boiler-service","at":Vector3(-7,0,-21)},
		{"label":"furnace-threshold","at":Vector3(-9,0,-12)},
		{"label":"furnace-threshold-reverse","at":Vector3(-9,0,-15)},
		{"label":"pump-workplace","at":Vector3(11,0,-17)},
		{"label":"workshop-workplace","at":Vector3(-12,0,-43)},
		{"label":"settling-workplace","at":Vector3(11,0,2)},
		{"label":"collector-workplace","at":Vector3(14.6,0,-35)},
		{"label":"receiving-workplace","at":Vector3(-1,0,11)},
		{"label":"archive-workplace","at":Vector3(-27,0,-43)},
		{"label":"gate-workplace","at":Vector3(-2,1,-65)},
		{"label":"settling-instruments","at":Vector3(7,0,-7)},
		{"label":"gate-service-wall","at":Vector3(-11,1,-62.5)}
	]:
		level._reset_position(pose.at)
		level.hud._notice_left = 0.0
		await _ticks(24)
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png(output_folder+"art/"+pose.label+".png")
		stats.append({"view":pose.label,"fixture":"normal gameplay camera; relocated hero; encounters cleared"})
	var report := FileAccess.open(output_folder+"art_capture_inventory.json",FileAccess.WRITE)
	report.store_string(JSON.stringify(stats,"\t"))
	quit()

func _ticks(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame
		paused = false
		if is_instance_valid(current_scene) and current_scene.has_method("_resume_game"):
			current_scene._resume_game()
