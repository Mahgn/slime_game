extends SceneTree

const STORE_SCRIPT = preload("res://scripts/progression/checkpoint_store.gd")

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var store: CheckpointStore = STORE_SCRIPT.new()
	var launch: Control = load("res://scenes/launch.tscn").instantiate()
	root.add_child(launch)
	current_scene = launch
	await _steps(3)
	if launch.get("_continue_button").visible:
		await _finish(1, "fresh launcher incorrectly offers Continue")
		return
	launch.call("_start_new_game")
	if not await _wait_scene("res://scenes/r01_entrance.tscn", 25):
		await _finish(1, "new game did not open R01")
		return
	var r01_saved := _saved(store, "R01", [], 1, ["", ""])
	var r01_player: SlimeController = current_scene.get_node("SlimePlayer")
	r01_player.global_position = Vector3(0.0, 1.35, -5.1)
	r01_player.velocity = Vector3.ZERO
	if not await _wait_scene("res://scenes/main.tscn", 100):
		await _finish(1, "R01 did not open R02")
		return
	var r02_saved := _saved(store, "R02", [], 1, ["", ""])
	var r02_room: Node3D = current_scene
	var r02_player: SlimeController = r02_room.get_node("SlimePlayer")
	r02_player.grant_ability(&"sticky_spit")
	r02_room.call("_enter_r03")
	if not await _wait_scene("res://scenes/r03_armorer.tscn", 30):
		await _finish(1, "R02 did not open R03")
		return
	var r03_saved := _saved(store, "R03", ["sticky_spit"], 1, ["sticky_spit", ""])
	var r03_room: Node3D = current_scene
	var r03_player: SlimeController = r03_room.get_node("SlimePlayer")
	await _steps(8)
	var armorer: BorrowableEnemy
	for enemy: Node in get_nodes_in_group(&"enemies"):
		if enemy is BorrowableEnemy:
			armorer = enemy
			break
	if not is_instance_valid(armorer):
		await _finish(1, "R03 Armorer missing")
		return
	armorer.player_target = null
	armorer.receive_hit(100, "save_route_armorer", &"player")
	await _steps(5)
	var shell_source := _find_source(&"elastic_shell")
	if not is_instance_valid(shell_source):
		await _finish(1, "R03 shell source missing")
		return
	await _absorb(r03_player, shell_source)
	r03_player.equip_ability(1, &"elastic_shell")
	r03_room.call("_update_saved_loadout_if_eligible")
	var temporary_not_saved := _saved(store, "R03", ["sticky_spit"], 1, ["sticky_spit", ""])
	r03_player.global_position = Vector3(0.0, 0.05, -3.4)
	r03_player.velocity = Vector3.ZERO
	if not await _wait_scene("res://scenes/r04_core_trial.tscn", 230):
		await _finish(1, "R03 did not open R04")
		return
	var r04_saved := _saved(store, "R04", ["sticky_spit", "elastic_shell"], 1, ["elastic_shell", ""])
	var r04_room: Node3D = current_scene
	var r04_player: SlimeController = r04_room.get_node("SlimePlayer")
	var core_first := await _clear_r04(r04_room, r04_player, "first")
	if not core_first:
		await _finish(1, "R04 first core/Sprout cycle failed")
		return
	r04_player.equip_ability(1, &"slime_spikes")
	r04_room.call("_update_saved_loadout_if_eligible")
	var new_skill_not_saved := _saved(store, "R04", ["sticky_spit", "elastic_shell"], 1, ["elastic_shell", ""])
	r04_player.receive_hit(999, "save_route_die", &"enemy")
	r04_room.call("_restart")
	if not await _wait_scene("res://scenes/r04_core_trial.tscn", 30):
		await _finish(1, "R04 restart failed")
		return
	var restored_room: Node3D = current_scene
	var restored_player: SlimeController = restored_room.get_node("SlimePlayer")
	var restored: bool = restored_room.get("stage") == &"core" and restored_player.unlocked_slots == 1 and restored_player.get_slot_ability(1) == &"elastic_shell" and not restored_player.has_learned(&"slime_spikes") and is_instance_valid(restored_room.get("_core"))
	var core_second := await _clear_r04(restored_room, restored_player, "second")
	if not core_second:
		await _finish(1, "R04 repeat core/Sprout cycle failed")
		return
	restored_player.equip_ability(1, &"")
	restored_player.equip_ability(2, &"")
	restored_player.equip_ability(1, &"slime_spikes")
	restored_player.equip_ability(2, &"sticky_spit")
	restored_player.global_position = Vector3(0.0, 0.05, -8.2)
	restored_player.velocity = Vector3.ZERO
	await _steps(125)
	Input.action_press(&"interact")
	var arrived := await _wait_scene("res://scenes/r05_mixed.tscn", 130)
	Input.action_release(&"interact")
	if not arrived:
		await _finish(1, "R04 did not open R05")
		return
	var r05_saved := _saved(store, "R05", ["sticky_spit", "elastic_shell", "slime_spikes"], 2, ["slime_spikes", "sticky_spit"])
	print("CHECKPOINT_ROUTE r01=%s r02=%s r03=%s temporary=%s r04=%s new_skill_temporary=%s restored=%s r05=%s" % [str(r01_saved), str(r02_saved), str(r03_saved), str(temporary_not_saved), str(r04_saved), str(new_skill_not_saved), str(restored), str(r05_saved)])
	var success: bool = r01_saved and r02_saved and r03_saved and temporary_not_saved and r04_saved and new_skill_not_saved and restored and r05_saved
	print("PASS S5_CHECKPOINT_ROUTE" if success else "FAIL S5_CHECKPOINT_ROUTE")
	await _finish(0 if success else 1, "")


func _clear_r04(room: Node3D, player: SlimeController, key: String) -> bool:
	var core: Node3D = room.get("_core")
	if not is_instance_valid(core):
		return false
	player.global_position = core.global_position + Vector3(0.0, 0.05, 1.0)
	player.velocity = Vector3.ZERO
	await _steps(7)
	Input.action_press(&"interact")
	await _steps(39)
	Input.action_release(&"interact")
	await _steps(143)
	if player.unlocked_slots != 2:
		return false
	var sprout: BorrowableEnemy
	for enemy: Node in get_nodes_in_group(&"enemies"):
		if enemy is BorrowableEnemy and enemy.kind == "sprout":
			sprout = enemy
			break
	if not is_instance_valid(sprout):
		return false
	sprout.player_target = null
	sprout.receive_hit(100, "save_route_sprout_" + key, &"player")
	await _steps(5)
	var source := _find_source(&"slime_spikes")
	if not is_instance_valid(source):
		return false
	await _absorb(player, source)
	return player.has_learned(&"slime_spikes") and room.get("stage") == &"r04_exit"


func _find_source(ability_id: StringName) -> AbsorbSource:
	for candidate: Node in get_nodes_in_group(&"absorb_sources"):
		if candidate is AbsorbSource and candidate.ability_id == ability_id:
			return candidate
	return null


func _absorb(player: SlimeController, source: AbsorbSource) -> void:
	player.global_position = source.global_position + Vector3(0.0, 0.05, 1.0)
	player.velocity = Vector3.ZERO
	await _steps(7)
	Input.action_press(&"interact")
	await _steps(39)
	Input.action_release(&"interact")
	await _steps(6)


func _saved(store: CheckpointStore, room_id: String, learned: Array, slots: int, loadout: Array) -> bool:
	var result := store.read_checkpoint()
	if result["status"] != "ok":
		return false
	var snapshot: Dictionary = result["snapshot"]
	return snapshot["checkpoint_room_id"] == room_id and snapshot["learned_abilities"] == learned and snapshot["unlocked_slots"] == slots and snapshot["loadout"] == loadout


func _wait_scene(path: String, ticks: int) -> bool:
	for tick in ticks:
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
	Input.action_release(&"interact")
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(current_scene):
		var old_room := current_scene
		current_scene = null
		old_room.queue_free()
	await _steps(12)
	quit(code)
