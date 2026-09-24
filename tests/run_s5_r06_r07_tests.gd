extends SceneTree

const STORE_SCRIPT = preload("res://scripts/progression/checkpoint_store.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var store: CheckpointStore = STORE_SCRIPT.new()
	var entry := {
		"save_version": 1,
		"checkpoint_room_id": "R06",
		"learned_abilities": ["sticky_spit", "elastic_shell", "slime_spikes"],
		"unlocked_slots": 2,
		"loadout": ["slime_spikes", "sticky_spit"],
		"collected_cores": ["r04_core"],
		"completed_rooms": ["R01", "R02", "R03", "R04", "R05"],
		"slice_complete": false,
	}
	var written: bool = store.write_checkpoint(entry)["ok"]
	set_meta(&"checkpoint_active", true)
	var room: Node3D = load("res://scenes/r06_press.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await _steps(9)
	var player: SlimeController = room.get_node("SlimePlayer")
	player.global_position = Vector3(0.0, 0.05, -7.55)
	player.velocity = Vector3.ZERO
	await _steps(8)
	Input.action_press(&"interact")
	await _steps(2)
	Input.action_release(&"interact")
	var exit_ready: bool = room.get("stage") == &"complete" and room.get("_continue_button").visible
	room.call("_enter_r07")
	await _steps(12)
	var arrived: bool = is_instance_valid(current_scene) and current_scene.scene_file_path == "res://scenes/r07_guardian.tscn"
	var saved_entry := store.read_checkpoint()
	var saved: bool = saved_entry["status"] == "ok" and saved_entry["snapshot"]["checkpoint_room_id"] == "R07" and saved_entry["snapshot"]["completed_rooms"].size() == 6 and not saved_entry["snapshot"]["slice_complete"]
	var restored := false
	var opened := false
	var completed := false
	var menu_done := false
	var replay := false
	if arrived:
		var final_room: Node3D = current_scene
		player = final_room.get_node("SlimePlayer")
		restored = player.health == 100 and player.unlocked_slots == 2 and player.get_slot_ability(1) == &"slime_spikes" and player.get_slot_ability(2) == &"sticky_spit"
		var boss: ExitGuardian = final_room.get_node("ExitGuardian")
		boss.receive_hit(180, "route_final_boss", &"player")
		await _steps(3)
		opened = final_room.get("stage") == &"r07_exit" and final_room.get_node("ExitGate").collision_layer == 0
		player.global_position = Vector3(0.0, 0.05, -10.4)
		player.velocity = Vector3.ZERO
		await _steps(8)
		Input.action_press(&"interact")
		await _steps(2)
		Input.action_release(&"interact")
		var completed_save := store.read_checkpoint()
		completed = final_room.get("stage") == &"complete" and completed_save["status"] == "ok" and completed_save["snapshot"]["slice_complete"] and completed_save["snapshot"]["completed_rooms"].size() == 7
		completed = completed and final_room.get("_replay_button").visible and final_room.get("_menu_button").visible
		final_room.call("_go_to_menu")
		await _steps(10)
		if is_instance_valid(current_scene) and current_scene.scene_file_path == "res://scenes/launch.tscn":
			var launch: Control = current_scene
			menu_done = not launch.get("_continue_button").visible and launch.get("_message").text.contains("Демо пройдено")
			launch.call("_start_new_game")
			await _steps(10)
			var new_save := store.read_checkpoint()
			replay = is_instance_valid(current_scene) and current_scene.scene_file_path == "res://scenes/r01_entrance.tscn" and new_save["status"] == "ok" and new_save["snapshot"]["checkpoint_room_id"] == "R01" and not new_save["snapshot"]["slice_complete"]
	var ok := written and exit_ready and arrived and saved and restored and opened and completed and menu_done and replay
	print("R07_ROUTE written=%s exit=%s arrived=%s saved=%s restored=%s gate=%s completed=%s menu=%s replay=%s" % [written, exit_ready, arrived, saved, restored, opened, completed, menu_done, replay])
	print("PASS S5_R06_R07_COMPLETE" if ok else "FAIL S5_R06_R07_COMPLETE")
	Input.action_release(&"interact")
	paused = false
	quit(0 if ok else 1)

func _steps(count: int) -> void:
	for tick in count:
		await physics_frame
