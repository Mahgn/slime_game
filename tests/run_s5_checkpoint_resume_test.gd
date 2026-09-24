extends SceneTree

const STORE_SCRIPT = preload("res://scripts/progression/checkpoint_store.gd")

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var store: CheckpointStore = STORE_SCRIPT.new()
	var before := store.read_checkpoint()
	if before["status"] != "ok" or before["snapshot"]["checkpoint_room_id"] != "R05":
		await _finish(1, "R05 disk snapshot missing in fresh process")
		return
	var launch: Control = load("res://scenes/launch.tscn").instantiate()
	root.add_child(launch)
	current_scene = launch
	await _steps(3)
	var offered: bool = launch.get("_continue_button").visible
	launch.call("_continue_game")
	var arrived := false
	for tick in 45:
		await physics_frame
		if is_instance_valid(current_scene) and current_scene.scene_file_path == "res://scenes/r05_mixed.tscn":
			arrived = true
			break
	var restored := false
	if arrived:
		var room: Node3D = current_scene
		var player: SlimeController = room.get_node("SlimePlayer")
		restored = player.health == player.MAX_HEALTH and player.unlocked_slots == 2 and player.has_learned(&"sticky_spit") and player.has_learned(&"elastic_shell") and player.has_learned(&"slime_spikes")
		restored = restored and player.get_slot_ability(1) == &"slime_spikes" and player.get_slot_ability(2) == &"sticky_spit" and get_nodes_in_group(&"enemies").size() == 3
	print("CHECKPOINT_RESUME offered=%s arrived=%s restored=%s" % [str(offered), str(arrived), str(restored)])
	print("PASS S5_CHECKPOINT_FRESH_PROCESS" if offered and arrived and restored else "FAIL S5_CHECKPOINT_FRESH_PROCESS")
	await _finish(0 if offered and arrived and restored else 1, "")


func _steps(count: int) -> void:
	for tick in count:
		await physics_frame


func _finish(code: int, reason: String) -> void:
	if not reason.is_empty():
		print("FAIL " + reason)
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(current_scene):
		var old_room := current_scene
		current_scene = null
		old_room.queue_free()
	await _steps(12)
	quit(code)
