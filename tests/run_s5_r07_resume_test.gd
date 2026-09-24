extends SceneTree

const STORE_SCRIPT = preload("res://scripts/progression/checkpoint_store.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var store: CheckpointStore = STORE_SCRIPT.new()
	if OS.get_environment("SLIME_R07_TEST_PHASE") == "setup":
		var snapshot := {
			"save_version": 1,
			"checkpoint_room_id": "R07",
			"learned_abilities": ["sticky_spit", "elastic_shell", "slime_spikes"],
			"unlocked_slots": 2,
			"loadout": ["elastic_shell", "slime_spikes"],
			"collected_cores": ["r04_core"],
			"completed_rooms": ["R01", "R02", "R03", "R04", "R05", "R06"],
			"slice_complete": false,
		}
		var result := store.write_checkpoint(snapshot)
		print("R07_SETUP ok=%s" % result["ok"])
		quit(0 if result["ok"] else 1)
		return
	var launch: Control = load("res://scenes/launch.tscn").instantiate()
	root.add_child(launch)
	current_scene = launch
	await _steps(4)
	var available: bool = launch.get("_continue_button").visible
	launch.call("_continue_game")
	await _steps(10)
	var arrived: bool = is_instance_valid(current_scene) and current_scene.scene_file_path == "res://scenes/r07_guardian.tscn"
	var restored := false
	if arrived:
		var player: SlimeController = current_scene.get_node("SlimePlayer")
		restored = player.health == 100 and player.unlocked_slots == 2 and player.get_slot_ability(1) == &"elastic_shell" and player.get_slot_ability(2) == &"slime_spikes"
	var ok := available and arrived and restored
	print("R07_FRESH available=%s arrived=%s restored=%s" % [available, arrived, restored])
	print("PASS R07_FRESH" if ok else "FAIL R07_FRESH")
	paused = false
	quit(0 if ok else 1)

func _steps(count: int) -> void:
	for tick in count:
		await physics_frame
