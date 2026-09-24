extends SceneTree

const STORE_SCRIPT = preload("res://scripts/progression/checkpoint_store.gd")
const PROJECTILE_SCENE = preload("res://scenes/abilities/spit_projectile.tscn")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var store: CheckpointStore = STORE_SCRIPT.new()
	var snapshot := {
		"save_version": 1,
		"checkpoint_room_id": "R05",
		"learned_abilities": ["sticky_spit", "elastic_shell", "slime_spikes"],
		"unlocked_slots": 2,
		"loadout": ["slime_spikes", "sticky_spit"],
		"collected_cores": ["r04_core"],
		"completed_rooms": ["R01", "R02", "R03", "R04"],
		"slice_complete": false,
	}
	var written: bool = store.write_checkpoint(snapshot)["ok"]
	set_meta(&"checkpoint_active", true)
	var room: Node3D = load("res://scenes/r05_mixed.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await _steps(8)
	var player: SlimeController = room.get_node("SlimePlayer")
	var restored: bool = player.get_slot_ability(1) == &"slime_spikes" and player.get_slot_ability(2) == &"sticky_spit"
	for enemy: Node in get_nodes_in_group(&"enemies"):
		enemy.set("player_target", null)
		enemy.call("receive_hit", 100, "r06_route_" + str(enemy.get_instance_id()), &"player")
	await _steps(90)
	var completed: bool = room.get("stage") == &"complete" and room.get("_continue_button").visible
	room.call("_enter_r06")
	await _steps(12)
	var arrived: bool = is_instance_valid(current_scene) and current_scene.scene_file_path == "res://scenes/r06_press.tscn"
	var next_save := store.read_checkpoint()
	var saved: bool = next_save["status"] == "ok" and next_save["snapshot"]["checkpoint_room_id"] == "R06" and next_save["snapshot"]["completed_rooms"].size() == 5
	var transferred := false
	var projectile_hit := false
	var jump := false
	var death_restart := false
	if arrived:
		var press_room: Node3D = current_scene
		player = press_room.get_node("SlimePlayer")
		transferred = player.get_slot_ability(1) == &"slime_spikes" and player.get_slot_ability(2) == &"sticky_spit" and player.health == 100
		var target: PressTarget = press_room.get_node("StickyMechanism")
		var projectile: SpitProjectile = PROJECTILE_SCENE.instantiate()
		projectile.configure(player, &"player", Vector3.FORWARD, 14.0, 12, 18.0, "test:1:sticky_spit", 0.55, 3.0)
		press_room.add_child(projectile)
		projectile.global_position = target.global_position + Vector3(0.0, 0.0, 2.0)
		await _steps(20)
		projectile_hit = press_room.get("sticky_open_left") > 2.5
		player.global_position = Vector3(0.0, 0.05, -2.0)
		player.velocity = Vector3.ZERO
		await _steps(4)
		Input.action_press(&"move_forward")
		Input.action_press(&"jump")
		await _steps(2)
		Input.action_release(&"jump")
		await _steps(40)
		Input.action_release(&"move_forward")
		jump = player.global_position.z < -4.8 and player.global_position.y > -0.5 and player.health == 100
		player.receive_hit(999, "r06_death", &"enemy")
		press_room.call("_restart")
		await _steps(10)
		if is_instance_valid(current_scene) and current_scene.scene_file_path == "res://scenes/r06_press.tscn":
			player = current_scene.get_node("SlimePlayer")
			death_restart = player.health == 100 and player.get_slot_ability(1) == &"slime_spikes" and player.get_slot_ability(2) == &"sticky_spit"
	var ok := written and restored and completed and arrived and saved and transferred and projectile_hit and jump and death_restart
	print("R05_R06_SAVE written=%s restored=%s completed=%s arrived=%s saved=%s transferred=%s projectile=%s jump=%s restart=%s" % [written, restored, completed, arrived, saved, transferred, projectile_hit, jump, death_restart])
	print("PASS S5_R05_R06_SAVE_JUMP" if ok else "FAIL S5_R05_R06_SAVE_JUMP")
	Input.action_release(&"move_forward")
	Input.action_release(&"jump")
	paused = false
	quit(0 if ok else 1)

func _steps(count: int) -> void:
	for tick in count:
		await physics_frame
