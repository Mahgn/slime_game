extends SceneTree

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var launch: Control = load("res://scenes/launch.tscn").instantiate()
	root.add_child(launch)
	current_scene = launch
	await _steps(3)
	var offered: bool = launch.get("_continue_button").visible
	launch.call("_continue_game")
	var arrived := false
	for tick in 40:
		await physics_frame
		if is_instance_valid(current_scene) and current_scene.scene_file_path == "res://scenes/r03_armorer.tscn":
			arrived = true
			break
	var restored := false
	if arrived:
		var room: Node3D = current_scene
		var player: SlimeController = room.get_node("SlimePlayer")
		restored = player.has_learned(&"sticky_spit") and not player.has_learned(&"elastic_shell") and player.unlocked_slots == 1 and player.get_slot_ability(1) == &"sticky_spit" and get_nodes_in_group(&"enemies").size() == 1 and get_nodes_in_group(&"absorb_sources").is_empty()
	print("CLOSE_RESTORE offered=%s arrived=%s restored=%s" % [str(offered), str(arrived), str(restored)])
	print("PASS S5_CLOSE_RESTORE" if offered and arrived and restored else "FAIL S5_CLOSE_RESTORE")
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(current_scene):
		var room: Node = current_scene
		current_scene = null
		room.queue_free()
	await _steps(8)
	quit(0 if offered and arrived and restored else 1)


func _steps(count: int) -> void:
	for tick in count:
		await physics_frame
