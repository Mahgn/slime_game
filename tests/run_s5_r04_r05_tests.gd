extends SceneTree

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	set_meta(&"r03_slot_one", &"elastic_shell")
	var room: Node3D = load("res://scenes/r04_core_trial.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	var player: SlimeController = room.get_node("SlimePlayer")
	await _steps(8)
	var r04_entry: bool = room.get("stage") == &"core" and player.get_slot_ability(1) == &"elastic_shell" and player.unlocked_slots == 1
	var core: Node3D = room.get("_core")
	if not is_instance_valid(core):
		await _finish(1, "R04 core missing")
		return
	player.global_position = core.global_position + Vector3(0.0, 0.05, 1.0)
	player.velocity = Vector3.ZERO
	await _steps(7)
	Input.action_press(&"interact")
	await _steps(39)
	Input.action_release(&"interact")
	await _steps(143)
	var core_opened: bool = player.unlocked_slots == 2
	var sprout: BorrowableEnemy
	for candidate: Node in get_nodes_in_group(&"enemies"):
		if candidate is BorrowableEnemy and candidate.kind == "sprout":
			sprout = candidate
			break
	if not is_instance_valid(sprout):
		await _finish(1, "R04 Sprout missing")
		return
	sprout.player_target = null
	sprout.receive_hit(100, "r05_route_sprout", &"player")
	await _steps(5)
	var source: AbsorbSource
	for candidate: Node in get_nodes_in_group(&"absorb_sources"):
		if candidate is AbsorbSource and candidate.ability_id == &"slime_spikes":
			source = candidate
			break
	if not is_instance_valid(source):
		await _finish(1, "R04 spike source missing")
		return
	player.global_position = source.global_position + Vector3(0.0, 0.05, 1.0)
	player.velocity = Vector3.ZERO
	await _steps(7)
	Input.action_press(&"interact")
	await _steps(39)
	Input.action_release(&"interact")
	await _steps(5)
	var r04_clear: bool = room.get("stage") == &"r04_exit" and player.has_learned(&"slime_spikes") and room.get_node("R05Exit").visible and get_nodes_in_group(&"enemies").is_empty()
	player.equip_ability(1, &"")
	player.equip_ability(2, &"")
	var selected: bool = player.equip_ability(1, &"slime_spikes") and player.equip_ability(2, &"sticky_spit")
	player.global_position = Vector3(0.0, 0.05, -8.2)
	player.velocity = Vector3.ZERO
	await _steps(7)
	Input.action_press(&"interact")
	await _steps(2)
	var gated: bool = current_scene == room
	Input.action_release(&"interact")
	await _steps(125)
	Input.action_press(&"interact")
	for tick in 120:
		await physics_frame
		if is_instance_valid(current_scene) and current_scene != room:
			break
	Input.action_release(&"interact")
	var arrived: bool = is_instance_valid(current_scene) and current_scene.scene_file_path == "res://scenes/r05_mixed.tscn"
	var transferred := false
	var restarted := false
	var completed := false
	if arrived:
		var next_room: Node3D = current_scene
		var next_player: SlimeController = next_room.get_node("SlimePlayer")
		transferred = next_room.get("stage") == &"mixed" and next_player.unlocked_slots == 2 and next_player.has_learned(&"sticky_spit") and next_player.has_learned(&"elastic_shell") and next_player.has_learned(&"slime_spikes")
		transferred = transferred and next_player.get_slot_ability(1) == &"slime_spikes" and next_player.get_slot_ability(2) == &"sticky_spit"
		transferred = transferred and next_room.has_node("MixedHall/WestSupport") and next_room.has_node("MixedHall/EastSupport") and get_nodes_in_group(&"enemies").size() == 3
		next_player.equip_ability(1, &"elastic_shell")
		next_player.receive_hit(999, "r05_restart_check", &"enemy")
		var died: bool = next_room.get("stage") == &"dead" and paused
		next_room.call("_restart")
		await _steps(10)
		restarted = died and is_instance_valid(current_scene) and current_scene.scene_file_path == "res://scenes/r05_mixed.tscn"
		if restarted:
			var restored_room: Node3D = current_scene
			var restored_player: SlimeController = restored_room.get_node("SlimePlayer")
			restarted = restored_player.get_slot_ability(1) == &"slime_spikes" and restored_player.get_slot_ability(2) == &"sticky_spit" and restored_player.health == restored_player.MAX_HEALTH and get_nodes_in_group(&"enemies").size() == 3
			for enemy: Node in get_nodes_in_group(&"enemies"):
				if enemy is Spitter:
					(enemy as Spitter).player_target = null
					(enemy as Spitter).receive_hit(100, "r05_final_%d" % enemy.get_instance_id(), &"player")
				elif enemy is BorrowableEnemy:
					(enemy as BorrowableEnemy).player_target = null
					(enemy as BorrowableEnemy).receive_hit(100, "r05_final_%d" % enemy.get_instance_id(), &"player")
			await _steps(90)
			completed = restored_room.get("stage") == &"complete" and paused and restored_room.get("_end_title").text == "R05 пройден"
	var empty_slot_restored := false
	if completed:
		set_meta(&"r05_entry", {"slot_one": &"", "slot_two": &"elastic_shell"})
		paused = false
		reload_current_scene()
		await _steps(10)
		if is_instance_valid(current_scene) and current_scene.scene_file_path == "res://scenes/r05_mixed.tscn":
			var empty_player: SlimeController = current_scene.get_node("SlimePlayer")
			empty_slot_restored = empty_player.get_slot_ability(1) == &"" and empty_player.get_slot_ability(2) == &"elastic_shell" and empty_player.unlocked_slots == 2
	print("R05_ROUTE r04_entry=%s core=%s clear=%s selected=%s gated=%s arrived=%s transferred=%s restarted=%s completed=%s empty_slot=%s" % [str(r04_entry), str(core_opened), str(r04_clear), str(selected), str(gated), str(arrived), str(transferred), str(restarted), str(completed), str(empty_slot_restored)])
	var pass_result := r04_entry and core_opened and r04_clear and selected and gated and arrived and transferred and restarted and completed and empty_slot_restored
	print("PASS S5_R04_R05_LOADOUT_RESTART" if pass_result else "FAIL S5_R04_R05_LOADOUT_RESTART")
	await _finish(0 if pass_result else 1, "")


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
		var old_room := current_scene
		current_scene = null
		old_room.queue_free()
	await _steps(12)
	quit(code)
