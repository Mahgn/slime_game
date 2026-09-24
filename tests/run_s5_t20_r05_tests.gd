extends SceneTree

const STORE_SCRIPT = preload("res://scripts/progression/checkpoint_store.gd")

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var store: CheckpointStore = STORE_SCRIPT.new()
	var snapshot := store.initial_snapshot()
	snapshot["checkpoint_room_id"] = "R05"
	snapshot["learned_abilities"] = ["sticky_spit", "elastic_shell", "slime_spikes"]
	snapshot["unlocked_slots"] = 2
	snapshot["loadout"] = ["slime_spikes", "sticky_spit"]
	snapshot["collected_cores"] = ["r04_core"]
	snapshot["completed_rooms"] = ["R01", "R02", "R03", "R04"]
	if not store.write_checkpoint(snapshot)["ok"]:
		quit(1)
		return
	set_meta(&"checkpoint_active", true)
	var room: Node3D = load("res://scenes/r05_mixed.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await _steps(8)
	var passed := true
	for repeat in 10:
		var spitter: Spitter
		for enemy: Node in get_nodes_in_group(&"enemies"):
			if enemy is Spitter:
				spitter = enemy
				break
		if not is_instance_valid(spitter):
			passed = false
			break
		room.call("_on_enemy_projectile", spitter, spitter.global_position + Vector3.UP * 0.7, Vector3.UP, 5, 0.1, 20.0, "restart_%d" % repeat)
		await _steps(1)
		var had_projectile := not get_nodes_in_group(&"enemy_projectiles").is_empty()
		room.call("_restart")
		var entered := false
		for tick in 25:
			await physics_frame
			if is_instance_valid(current_scene) and current_scene != room and current_scene.scene_file_path == "res://scenes/r05_mixed.tscn":
				entered = true
				break
		if not entered:
			passed = false
			break
		room = current_scene
		await _steps(5)
		var player: SlimeController = room.get_node("SlimePlayer")
		var clean: bool = get_nodes_in_group(&"enemies").size() == 3 and get_nodes_in_group(&"enemy_projectiles").is_empty() and get_nodes_in_group(&"enemy_attacks").is_empty() and get_nodes_in_group(&"absorb_sources").is_empty()
		clean = clean and player.health == player.MAX_HEALTH and player.unlocked_slots == 2 and player.get_slot_ability(1) == &"slime_spikes" and player.get_slot_ability(2) == &"sticky_spit"
		passed = passed and had_projectile and clean
		print("R05_REPEAT %d projectile=%s clean=%s" % [repeat + 1, str(had_projectile), str(clean)])
		if not passed:
			break
	print("PASS T20_R05" if passed else "FAIL T20_R05")
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(current_scene):
		var final_room: Node3D = current_scene
		current_scene = null
		final_room.queue_free()
	await _steps(12)
	quit(0 if passed else 1)


func _steps(count: int) -> void:
	for tick in count:
		await physics_frame
