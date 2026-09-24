extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var launch: Control = load("res://scenes/launch.tscn").instantiate()
	root.add_child(launch)
	current_scene = launch
	await _steps(5)
	var available: bool = launch.get("_continue_button").visible
	launch.call("_continue_game")
	await _steps(12)
	var arrived: bool = is_instance_valid(current_scene) and current_scene.scene_file_path == "res://scenes/r06_press.tscn"
	var restored := false
	if arrived:
		var player: SlimeController = current_scene.get_node("SlimePlayer")
		restored = player.health == 100 and player.unlocked_slots == 2 and player.get_slot_ability(1) == &"slime_spikes" and player.get_slot_ability(2) == &"sticky_spit"
	var ok := available and arrived and restored
	print("R06_FRESH_PROCESS available=%s arrived=%s restored=%s" % [available, arrived, restored])
	print("PASS R06_FRESH_PROCESS" if ok else "FAIL R06_FRESH_PROCESS")
	paused = false
	quit(0 if ok else 1)

func _steps(count: int) -> void:
	for tick in count:
		await physics_frame
