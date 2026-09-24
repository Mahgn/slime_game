extends SceneTree

const STORE_SCRIPT = preload("res://scripts/progression/checkpoint_store.gd")

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var store: CheckpointStore = STORE_SCRIPT.new()
	var snapshot := store.initial_snapshot()
	snapshot["checkpoint_room_id"] = "R03"
	snapshot["learned_abilities"] = ["sticky_spit"]
	snapshot["loadout"] = ["sticky_spit", ""]
	snapshot["completed_rooms"] = ["R01", "R02"]
	if not store.write_checkpoint(snapshot)["ok"]:
		quit(1)
		return
	set_meta(&"checkpoint_active", true)
	var room: Node3D = load("res://scenes/r03_armorer.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await _steps(10)
	var player: SlimeController = room.get_node("SlimePlayer")
	var armorer: BorrowableEnemy
	for enemy: Node in get_nodes_in_group(&"enemies"):
		if enemy is BorrowableEnemy:
			armorer = enemy
			break
	if not is_instance_valid(armorer):
		quit(1)
		return
	armorer.player_target = null
	armorer.receive_hit(100, "close_test", &"player")
	await _steps(5)
	var source: AbsorbSource
	for node: Node in get_nodes_in_group(&"absorb_sources"):
		if node is AbsorbSource and node.ability_id == &"elastic_shell":
			source = node
			break
	if not is_instance_valid(source):
		quit(1)
		return
	player.global_position = source.global_position + Vector3(0.0, 0.05, 1.0)
	player.velocity = Vector3.ZERO
	await _steps(7)
	Input.action_press(&"interact")
	await _steps(39)
	Input.action_release(&"interact")
	await _steps(6)
	var saved := store.read_checkpoint()
	var pass_result: bool = player.has_learned(&"elastic_shell") and saved["status"] == "ok" and saved["snapshot"]["checkpoint_room_id"] == "R03" and saved["snapshot"]["learned_abilities"] == ["sticky_spit"]
	print("PASS S5_CLOSE_STAGE" if pass_result else "FAIL S5_CLOSE_STAGE")
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	current_scene = null
	room.queue_free()
	await _steps(8)
	quit(0 if pass_result else 1)


func _steps(count: int) -> void:
	for tick in count:
		await physics_frame
