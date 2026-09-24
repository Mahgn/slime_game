extends SceneTree

const STORE_SCRIPT = preload("res://scripts/progression/checkpoint_store.gd")

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var store: CheckpointStore = STORE_SCRIPT.new()
	var prior := store.read_checkpoint()
	if prior["status"] != "ok" or prior["snapshot"]["checkpoint_room_id"] != "R05":
		await _finish(1, "expected R05 save before menu test")
		return
	var launch: Control = load("res://scenes/launch.tscn").instantiate()
	root.add_child(launch)
	current_scene = launch
	await _steps(3)
	launch.call("_request_new_game")
	var confirmation: bool = launch.get("_confirm_panel").visible and store.read_checkpoint()["snapshot"]["checkpoint_room_id"] == "R05"
	launch.call("_start_new_game")
	if not await _wait_scene("res://scenes/r01_entrance.tscn"):
		await _finish(1, "confirmed new game did not open R01")
		return
	var replaced: bool = store.read_checkpoint()["snapshot"]["checkpoint_room_id"] == "R01"
	var backup: CheckpointStore = STORE_SCRIPT.new("user://checkpoint.json.bak")
	var previous_preserved: bool = backup.read_checkpoint()["status"] == "ok" and backup.read_checkpoint()["snapshot"]["checkpoint_room_id"] == "R05"
	var bad := FileAccess.open("user://checkpoint.json", FileAccess.WRITE)
	bad.store_string("{broken")
	bad.close()
	var result := change_scene_to_file("res://scenes/launch.tscn")
	if result != OK or not await _wait_scene("res://scenes/launch.tscn"):
		await _finish(1, "launcher did not reopen")
		return
	var recovery_launch: Control = current_scene
	await _steps(3)
	var backup_offered: bool = recovery_launch.get("_continue_button").visible and store.read_checkpoint()["status"] == "backup"
	recovery_launch.call("_continue_game")
	if not await _wait_scene("res://scenes/r05_mixed.tscn"):
		await _finish(1, "backup Continue did not open R05")
		return
	var repaired: bool = store.read_checkpoint()["status"] == "ok" and store.read_checkpoint()["snapshot"]["checkpoint_room_id"] == "R05" and FileAccess.get_file_as_string("user://checkpoint.json.rejected") == "{broken"
	print("CHECKPOINT_MENU confirm=%s replaced=%s previous=%s backup_offered=%s repaired=%s" % [str(confirmation), str(replaced), str(previous_preserved), str(backup_offered), str(repaired)])
	var success: bool = confirmation and replaced and previous_preserved and backup_offered and repaired
	print("PASS S5_CHECKPOINT_MENU_RECOVERY" if success else "FAIL S5_CHECKPOINT_MENU_RECOVERY")
	await _finish(0 if success else 1, "")


func _wait_scene(path: String) -> bool:
	for tick in 45:
		await physics_frame
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path:
			return true
	return false


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
