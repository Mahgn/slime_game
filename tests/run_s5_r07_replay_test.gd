extends SceneTree

const STORE_SCRIPT = preload("res://scripts/progression/checkpoint_store.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var store: CheckpointStore = STORE_SCRIPT.new()
	var entry := {
		"save_version": 1,
		"checkpoint_room_id": "R07",
		"learned_abilities": ["sticky_spit", "elastic_shell", "slime_spikes"],
		"unlocked_slots": 2,
		"loadout": ["sticky_spit", "elastic_shell"],
		"collected_cores": ["r04_core"],
		"completed_rooms": ["R01", "R02", "R03", "R04", "R05", "R06"],
		"slice_complete": false,
	}
	var written: bool = store.write_checkpoint(entry)["ok"]
	set_meta(&"checkpoint_active", true)
	var room: Node3D = load("res://scenes/r07_guardian.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await _steps(8)
	var boss: ExitGuardian = room.get_node("ExitGuardian")
	boss.receive_hit(180, "replay_boss", &"player")
	await _steps(3)
	room.call("_complete_run")
	var finished: bool = room.get("stage") == &"complete" and room.get("_replay_button").visible
	var button: Button = room.get("_replay_button")
	button.pressed.emit()
	await _steps(12)
	var save := store.read_checkpoint()
	var restarted: bool = is_instance_valid(current_scene) and current_scene.scene_file_path == "res://scenes/r01_entrance.tscn" and save["status"] == "ok" and save["snapshot"]["checkpoint_room_id"] == "R01" and not save["snapshot"]["slice_complete"]
	var ok := written and finished and restarted
	print("R07_REPLAY written=%s finished=%s restarted=%s" % [written, finished, restarted])
	print("PASS R07_REPLAY" if ok else "FAIL R07_REPLAY")
	paused = false
	quit(0 if ok else 1)

func _steps(count: int) -> void:
	for tick in count:
		await physics_frame
