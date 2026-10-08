extends SceneTree

var out := "res://output/keepers_asset_craft_2026_10_08/baseline/"

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output=res://output/"):
			out=arg.trim_prefix("--output=").trim_suffix("/")+"/"
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	root.size=Vector2i(1280,900)
	SlimeGameSettings.current().load_settings(out+"settings.cfg")
	change_scene_to_file("res://scenes/keepers/keepers_facility.tscn")
	await _ticks(25)
	var level=current_scene
	for id: String in level.rooms: level.cleared[id]=true
	for actor in level.alive_enemies(): actor.queue_free()
	for hazard in level.hazards: hazard.disable()
	for marker in level._markers.values():
		if is_instance_valid(marker): marker.queue_free()
	level.hud.hide()
	level.get_node("HUD").hide()
	var inventory: Array=[]
	for spec: Dictionary in [
		{"id":"supplies","room":"armory","at":Vector3(-4.1,2.0,-48.40),"size":2.4},
		{"id":"valve","room":"cistern","at":Vector3(7.5,1.05,-9.8),"size":2.3},
		{"id":"sacks-cart","room":"entry","at":Vector3(-5,0.9,15.5),"size":3.5},
		{"id":"records","room":"archive","at":Vector3(-30.5,1.2,-43),"size":6.7},
		{"id":"barrel","room":"furnace","at":Vector3(-3.8,0.7,1.8),"size":2.7},
		{"id":"crates","room":"entry","at":Vector3(6.3,0.75,13.7),"size":4.9},
		{"id":"masonry","room":"armory","at":Vector3(-14.5,1.5,-48.7),"size":4.0},
		{"id":"floor-dry","room":"furnace","at":Vector3(-12,0,-3.0),"size":5.2},
		{"id":"floor-wet","room":"cistern","at":Vector3(15,0,-4),"size":5.2}
	]:
		level.player.show()
		level._reset_position(level.rooms[spec.room].spawn)
		await _ticks(12)
		level.player.hide()
		level.player.set_physics_process(false)
		level.player.presentation.set_process(false)
		level.player.presentation.set_physics_process(false)
		var camera: Camera3D=level.player.presentation.camera
		camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
		camera.size=float(spec.size)
		camera.global_position=spec.at+camera.global_basis.z*30.0
		camera.reset_physics_interpolation()
		await process_frame
		# Inspection runs may lose OS focus while shaders compile. Keep this
		# fixture unpaused; production focus-loss behavior stays unchanged.
		level._resume_game()
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png(out+spec.id+".png")
		inventory.append(spec)
		print("CAPTURE ",spec.id)
	FileAccess.open(out+"inventory.json",FileAccess.WRITE).store_string(JSON.stringify({"views":inventory,"fixture":"close inspection; real scene and lighting; orthographic camera recentered and zoomed; hero and HUD hidden; not ordinary gameplay"},"\t"))
	quit(0)

func _ticks(count: int) -> void:
	for i in count:
		if is_instance_valid(current_scene) and current_scene.has_method("_resume_game"):
			current_scene._resume_game()
		await physics_frame
		await process_frame
