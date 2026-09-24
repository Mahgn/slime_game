extends SceneTree

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var room: Node3D = load("res://scenes/r03_armorer.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	var player: SlimeController = room.get_node("SlimePlayer")
	await _steps(12)
	var armorer: BorrowableEnemy
	for candidate: Node in get_nodes_in_group(&"enemies"):
		if candidate is BorrowableEnemy:
			armorer = candidate
			break
	if not is_instance_valid(armorer):
		await _finish(1, "R03 enemy missing")
		return
	armorer.player_target = null
	armorer.receive_hit(40, "r03_capture", &"player")
	await _steps(5)
	var source: AbsorbSource
	for candidate: Node in get_nodes_in_group(&"absorb_sources"):
		if candidate is AbsorbSource and candidate.ability_id == &"elastic_shell":
			source = candidate
			break
	if not is_instance_valid(source):
		await _finish(1, "R03 shell source missing")
		return
	player.global_position = source.global_position + Vector3(0, 0.05, 1.0)
	player.velocity = Vector3.ZERO
	await _steps(6)
	Input.action_press(&"interact")
	await _steps(39)
	Input.action_release(&"interact")
	await _steps(5)
	var absorbed := player.has_learned(&"elastic_shell") and source.is_claimed()
	var waiting_at_exit: bool = room.get("stage") == &"r03_exit" and room.get("_core") == null
	if not absorbed or not waiting_at_exit:
		await _finish(1, "R03 did not finish shell absorption")
		return
	var chose_shell := player.equip_ability(1, &"elastic_shell")
	player.global_position = Vector3(0, 0.05, -3.4)
	player.velocity = Vector3.ZERO
	for tick in 220:
		await physics_frame
		if current_scene != room:
			break
	var arrived := is_instance_valid(current_scene) and current_scene.scene_file_path == "res://scenes/r04_core_trial.tscn"
	var transferred := false
	if arrived:
		var next_player: SlimeController = current_scene.get_node("SlimePlayer")
		transferred = next_player.has_learned(&"sticky_spit") and next_player.has_learned(&"elastic_shell") and next_player.get_slot_ability(1) == &"elastic_shell" and next_player.unlocked_slots == 1
		transferred = transferred and current_scene.get("stage") == &"core" and is_instance_valid(current_scene.get("_core")) and get_nodes_in_group(&"enemies").is_empty()
		await _steps(5)
		var entered_room := current_scene
		next_player.receive_hit(999, "r04_restart_check", &"enemy")
		var died: bool = paused and entered_room.get("stage") == &"dead"
		entered_room.call("_restart")
		await _steps(6)
		var restored := is_instance_valid(current_scene) and current_scene.scene_file_path == "res://scenes/r04_core_trial.tscn"
		if restored:
			var restored_player: SlimeController = current_scene.get_node("SlimePlayer")
			restored = restored_player.get_slot_ability(1) == &"elastic_shell" and restored_player.unlocked_slots == 1 and current_scene.get("stage") == &"core" and is_instance_valid(current_scene.get("_core"))
		transferred = transferred and died and restored
		print("R04_RESTART died=%s restored=%s" % [str(died), str(restored)])
	print("R03_R04 absorbed=%s exit=%s chose_shell=%s arrived=%s transferred=%s" % [str(absorbed), str(waiting_at_exit), str(chose_shell), str(arrived), str(transferred)])
	print("PASS S5_R03_R04_RESTART" if absorbed and waiting_at_exit and chose_shell and arrived and transferred else "FAIL S5_R03_R04_RESTART")
	await _finish(0 if absorbed and waiting_at_exit and chose_shell and arrived and transferred else 1, "")


func _steps(count: int) -> void:
	for tick in count:
		await physics_frame


func _finish(code: int, reason: String) -> void:
	if not reason.is_empty():
		print("FAIL %s" % reason)
	Input.action_release(&"interact")
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(current_scene):
		var room := current_scene
		current_scene = null
		room.queue_free()
	await _steps(12)
	quit(code)
