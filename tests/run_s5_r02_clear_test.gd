extends SceneTree

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await _steps(5)
	var first: Spitter = main.get("first_enemy")
	first.queue_free()
	await _steps(3)
	main.set("stage", &"second_fight")
	var second: Spitter = main.call("_add_enemy", Vector3(0, 0.05, -3.0))
	main.set("second_enemy", second)
	second.player_target = null
	var lingering: SpitProjectile = main.call("_add_projectile", second, &"enemy", Vector3(5.0, 1.0, 5.0), Vector3.FORWARD, 1, 0.1, 18.0, "r02_t19", 1.0, 0.0)
	await _steps(2)
	var actual_projectile := is_instance_valid(lingering) and not get_nodes_in_group(&"enemy_projectiles").is_empty()
	second.receive_hit(30, "r02_t19_kill", &"player")
	await _steps(8)
	var pending: bool = main.get("stage") == &"clear_pending" and not paused and not (main.get("_next_button") as Button).visible and is_instance_valid(lingering)
	lingering.queue_free()
	await _steps(5)
	var completed: bool = main.get("stage") == &"complete" and paused and (main.get("_next_button") as Button).visible
	print("T19_R02 projectile=%s pending=%s completed=%s" % [str(actual_projectile), str(pending), str(completed)])
	print("PASS T19_R02" if actual_projectile and pending and completed else "FAIL T19_R02")
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	current_scene = null
	main.queue_free()
	await _steps(12)
	quit(0 if actual_projectile and pending and completed else 1)


func _steps(count: int) -> void:
	for tick in count:
		await physics_frame
