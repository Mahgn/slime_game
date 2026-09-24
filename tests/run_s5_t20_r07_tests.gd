extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var room: Node3D = load("res://scenes/r07_guardian.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await _steps(8)
	var ok := true
	for run in 10:
		room = current_scene
		var boss: ExitGuardian = room.get_node("ExitGuardian")
		room.call("_add_spikes", boss, &"enemy", boss.global_position, Vector3.BACK, "repeat_%d" % run, 14)
		boss.receive_hit(180, "repeat_kill_%d" % run, &"player")
		await _steps(3)
		var cleaned := get_nodes_in_group(&"enemy_attacks").is_empty()
		room.call("_restart")
		await _steps(10)
		var new_room: Node3D = current_scene
		var player: SlimeController = new_room.get_node("SlimePlayer")
		var fresh: bool = new_room.get("stage") == &"r07_fight" and get_nodes_in_group(&"enemies").size() == 1 and get_nodes_in_group(&"enemy_attacks").is_empty() and get_nodes_in_group(&"enemy_projectiles").is_empty() and player.health == 100
		print("R07_REPEAT %d cleaned=%s fresh=%s" % [run + 1, cleaned, fresh])
		ok = ok and cleaned and fresh
	print("PASS T20_R07" if ok else "FAIL T20_R07")
	paused = false
	quit(0 if ok else 1)

func _steps(count: int) -> void:
	for tick in count:
		await physics_frame
