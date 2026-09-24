extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok := true
	var room: Node3D = load("res://scenes/r04_core_trial.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await _steps(8)
	room.call("_spawn_training_target")
	await _steps(2)
	var target: TrainingTarget = room.get_node("TrainingTarget")
	var excluded := get_nodes_in_group(&"enemies").is_empty() and get_nodes_in_group(&"training_targets").has(target)
	var first := target.receive_hit(12, "dummy_spit", &"player")
	target.apply_sticky(0.55, 3.0)
	var sticky := target.get_sticky_time_left() > 2.9
	var player: SlimeController = room.get_node("SlimePlayer")
	room.call("_add_spikes", player, &"player", target.global_position + Vector3(0.0, 0.0, 2.0), Vector3.FORWARD, "dummy_spikes", 22)
	await _steps(2)
	var combo := target.health == 10 and target.get_sticky_time_left() == 0.0
	target.receive_hit(10, "dummy_whip", &"player")
	var hidden := target.health == 0 and target.collision_layer == 0
	await _steps(125)
	var respawn := target.health == target.MAX_HEALTH and target.collision_layer == 4
	print("R04_DUMMY excluded=%s spit=%s sticky=%s combo=%s hidden=%s respawn=%s" % [excluded, first, sticky, combo, hidden, respawn])
	ok = ok and excluded and first and sticky and combo and hidden and respawn
	room.queue_free()
	current_scene = null
	await _steps(6)

	room = load("res://scenes/r06_press.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await _steps(8)
	player = room.get_node("SlimePlayer")
	var entry: bool = room.get("stage") == &"r06" and player.unlocked_slots == 2 and player.has_learned(&"slime_spikes")
	var mechanism: PressTarget = room.get_node("StickyMechanism")
	var activated := mechanism.receive_hit(12, "1:1:sticky_spit", &"player")
	mechanism.apply_sticky(0.55, 3.0)
	var held: bool = room.get("sticky_open_left") > 2.9 and room.get("press_phase") == &"open"
	await _steps(90)
	mechanism.apply_sticky(0.55, 3.0)
	var refreshed: bool = room.get("sticky_open_left") > 2.9
	await _steps(185)
	var reset: bool = room.get("sticky_open_left") == 0.0 and room.get("press_phase") == &"warning"
	var before_pause: float = room.get("phase_left")
	paused = true
	await _steps(30)
	var paused_cycle := absf(float(room.get("phase_left")) - before_pause) < 0.001
	paused = false
	room.set("press_phase", &"open")
	room.set("phase_left", 2.4)
	player.global_position = Vector3(0.0, 0.05, 2.6)
	player.velocity = Vector3.ZERO
	Input.action_press(&"move_forward")
	await _steps(42)
	Input.action_release(&"move_forward")
	var ordinary_pass := player.global_position.z < -0.15 and player.health == 100
	room.set("press_phase", &"warning")
	room.set("phase_left", 1.0)
	var target_position := Vector3(0.0, 0.05, 0.5)
	player.global_position = target_position
	player.velocity = Vector3.ZERO
	await _steps(85)
	var hit: bool = player.health == 85 and player.global_position.distance_to(Vector3(0.0, 0.05, 2.6)) < 1.2 and room.get("trap_protection_left") >= 0.0
	player.global_position = Vector3(0.0, -3.0, -3.9)
	player.velocity = Vector3.ZERO
	await _steps(2)
	var fall := player.health == 75 and player.global_position.y > -0.5
	print("R06_PRESS entry=%s activated=%s held=%s refreshed=%s reset=%s pause=%s ordinary=%s hit=%s fall=%s" % [entry, activated, held, refreshed, reset, paused_cycle, ordinary_pass, hit, fall])
	ok = ok and entry and activated and held and refreshed and reset and paused_cycle and ordinary_pass and hit and fall
	room.queue_free()
	current_scene = null
	await _steps(6)
	print("PASS S5_R04_DUMMY_R06_PRESS" if ok else "FAIL S5_R04_DUMMY_R06_PRESS")
	quit(0 if ok else 1)

func _steps(count: int) -> void:
	for tick in count:
		await physics_frame
