extends SceneTree

# S5 T19: the R05 clear must remain unsafe while a real enemy projectile exists.
# R07 deliberately clears the boss's active attack before opening its exit.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	set_meta(&"checkpoint_active", false)
	var r05_ok := await _test_r05_pending_projectile()
	var r07_ok := await _test_r07_boss_cleanup()
	var passed: bool = r05_ok and r07_ok
	print("PASS T19_ROOMS" if passed else "FAIL T19_ROOMS")
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _dispose_current_scene()
	quit(0 if passed else 1)


func _test_r05_pending_projectile() -> bool:
	var room: Node3D = await _open_room("res://scenes/r05_mixed.tscn")
	if not is_instance_valid(room):
		print("FAIL T19_R05 missing room")
		return false
	var spitter: Spitter
	for enemy: Node in get_nodes_in_group(&"enemies"):
		enemy.set("player_target", null)
		if enemy is Spitter:
			spitter = enemy as Spitter
	if not is_instance_valid(spitter):
		print("FAIL T19_R05 missing Spitter")
		return false
	room.call("_on_enemy_projectile", spitter, Vector3(0.0, 2.0, 0.0), Vector3.UP, 5, 0.1, 100.0, "t19_r05_pending")
	await _steps(2)
	var created: bool = not get_nodes_in_group(&"enemy_projectiles").is_empty()
	for enemy: Node in get_nodes_in_group(&"enemies"):
		enemy.call("receive_hit", 999, "t19_r05_kill_%d" % enemy.get_instance_id(), &"player")
	await _steps(48)
	room.call("_try_open_collection")
	var blocked: bool = room.get("stage") == &"mixed" and not room.get("_collection_open") and not paused and not (room.get("_end_panel") as ColorRect).visible
	blocked = blocked and not get_nodes_in_group(&"enemy_projectiles").is_empty()
	for projectile: Node in get_nodes_in_group(&"enemy_projectiles"):
		projectile.queue_free()
	await _steps(48)
	var completed: bool = room.get("stage") == &"complete" and paused and (room.get("_end_panel") as ColorRect).visible
	print("T19_R05 created=%s blocked=%s completed=%s" % [created, blocked, completed])
	return created and blocked and completed


func _test_r07_boss_cleanup() -> bool:
	var room: Node3D = await _open_room("res://scenes/r07_guardian.tscn")
	if not is_instance_valid(room):
		print("FAIL T19_R07 missing room")
		return false
	var boss: ExitGuardian = room.get_node("ExitGuardian")
	var player: SlimeController = room.get_node("SlimePlayer")
	boss.player_target = null
	room.call("_add_spikes", boss, &"enemy", boss.global_position, Vector3.FORWARD, "t19_r07_pending", 14)
	var attack_created: bool = not get_nodes_in_group(&"enemy_attacks").is_empty()
	var health_before: int = player.health
	boss.receive_hit(999, "t19_r07_kill", &"player")
	await _steps(4)
	var safe_exit: bool = room.get("stage") == &"r07_exit" and get_nodes_in_group(&"enemy_attacks").is_empty() and get_nodes_in_group(&"enemy_projectiles").is_empty()
	safe_exit = safe_exit and room.get_node("ExitGate").collision_layer == 0 and player.health == health_before
	print("T19_R07 attack=%s safe_exit=%s" % [attack_created, safe_exit])
	return attack_created and safe_exit


func _open_room(scene_path: String) -> Node3D:
	await _dispose_current_scene()
	paused = false
	var scene: PackedScene = load(scene_path)
	if scene == null:
		return null
	var room := scene.instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await _steps(8)
	return room


func _dispose_current_scene() -> void:
	paused = false
	if is_instance_valid(current_scene):
		var old_scene: Node = current_scene
		current_scene = null
		old_scene.queue_free()
	await _steps(6)


func _steps(count: int) -> void:
	for step in count:
		await physics_frame
