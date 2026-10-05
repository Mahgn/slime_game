extends SceneTree

const OUTPUT := "res://output/integration_slime_lab/images/"
var _output_dir := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_output_dir = OUTPUT + "%dx%d/" % [root.size.x, root.size.y]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output_dir))
	var launch := (load("res://scenes/launch.tscn") as PackedScene).instantiate()
	root.add_child(launch)
	current_scene = launch
	await _save("01_menu.png")
	launch._open_first_floor()
	await _frames(8)
	var floor := current_scene as FirstFloorGame
	await _save("02_start_game_camera.png")
	# Real viewport captures of the relocated level and current enemy models.
	var survey := Camera3D.new()
	survey.fov = 52
	floor.add_child(survey)
	survey.global_position = Vector3(44, 43, 21)
	survey.look_at(Vector3(13, 2, -21))
	survey.current = true
	await _save("03_route_overview.png")
	floor.player.global_position = Vector3(0, 2.65, -27)
	floor.player.velocity = Vector3.ZERO
	floor.player.camera.current = true
	floor._on_zone_entered(floor.player, "R02")
	await _save("04_spitter_current.png")
	floor._pause_game()
	await _save("05_pause.png")
	floor._overlay_settings.pressed.emit()
	await _save("06_shared_settings.png")
	floor._settings_panel.close_and_save()
	floor._resume_game()
	floor.player.global_position = Vector3(16, 3.25, -36)
	floor._on_zone_entered(floor.player, "R04")
	await _save("07_armorer_current.png")
	floor.player.global_position = Vector3(-3.5, 7.45, -15)
	floor.player.velocity = Vector3.ZERO
	floor._on_zone_entered(floor.player, "R08")
	await _save("08_low_passage.png")
	floor._back_to_menu()
	await _frames(8)
	current_scene.find_child("LabWorkshopButton", true, false).pressed.emit()
	await _save("09_workshop.png")
	SlimeGameSettings.current().request_quit()


func _save(name: String) -> void:
	await _frames(8)
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(_output_dir + name)
	if error != OK:
		printerr("FAIL screenshot ", name, " ", error)
		quit(1)
	print("CAPTURE ", name)


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame
