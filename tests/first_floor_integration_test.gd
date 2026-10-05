extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var watchdog := Timer.new()
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.wait_time = 90.0
	watchdog.one_shot = true
	root.add_child(watchdog)
	watchdog.timeout.connect(func() -> void: printerr("FAIL watchdog"); quit(1))
	watchdog.start()
	var store := CheckpointStore.new()
	_check(store.write_checkpoint(store.initial_snapshot(), true)["ok"], "create isolated demo save")
	var saved := FileAccess.get_file_as_string("user://checkpoint.json")
	var launch := (load("res://scenes/launch.tscn") as PackedScene).instantiate()
	root.add_child(launch)
	current_scene = launch
	await _frames(3)
	var button := launch.find_child("FirstFloorButton", true, false) as Button
	_check(button != null, "main menu exposes first floor")
	button.pressed.emit()
	await _frames(8)
	var floor := current_scene as FirstFloorGame
	_check(floor != null, "menu enters integrated floor")
	if floor == null:
		quit(1)
		return
	_check(floor.player.get_script().resource_path == "res://scripts/player/slime_controller.gd", "shared current controller")
	_check(floor.get_node("R02First/VisualRoot/Model") is SpitterVisual, "current Spitter v4")
	_check(floor.get_node("R04Armorer/ArmorerVisual") is ArmorerVisual, "current Armorer visual")
	_check(not ResourceLoader.exists("res://assets/first_floor/sample_crate.gltf"), "unreviewed imported samples excluded")
	var stable_count := 0
	floor.player.global_position = Vector3(0, 7.45, -24)
	floor.player.velocity = Vector3.ZERO
	for code in ["R02", "R04", "R05", "R06", "R08", "R09"]:
		floor._on_zone_entered(floor.player, code)
		var active := 0
		for enemy in get_nodes_in_group(&"enemies"):
			if enemy.is_physics_processing():
				active += 1
		_check(active > 0 and active <= 3, "bounded active encounter " + code)
		floor._open_loadout()
		_check(not floor._loadout.visible, "loadout blocked during " + code)
	floor._on_zone_entered(floor.player, "R07")
	var owner := floor.get_node("R02First") as Spitter
	floor._add_projectile(owner, &"enemy", Vector3(0, 15, -20), Vector3.RIGHT, 8, 1.0, 18, "safety", 1.0, 0.0)
	await _frames(2)
	_check(floor._has_threat(), "orphan enemy projectile remains threat")
	floor._open_loadout()
	_check(not floor._loadout.visible, "loadout blocked by projectile")
	var projectile := get_nodes_in_group(&"enemy_projectiles")[0] as Node3D
	var before := projectile.global_position
	floor._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(paused and floor._overlay.visible, "focus-loss handler pauses floor")
	await _frames(20)
	_check(before.is_equal_approx(projectile.global_position), "projectile frozen on pause")
	floor._resume_game()
	for node in get_nodes_in_group(&"projectiles"):
		node.queue_free()
	await _frames(3)
	floor._open_loadout()
	_check(not floor._loadout.visible, "quiet interval enforced")
	await _frames(36)
	floor._open_loadout()
	_check(floor._loadout.visible and paused, "safe loadout pauses world")
	floor._close_loadout()
	floor.player.grant_ability(&"sticky_spit")
	floor.player.global_position = Vector3(0, 7.45, -24)
	floor._on_zone_entered(floor.player, "K4")
	var snapshot := floor._checkpoint_state.duplicate(true)
	for iteration in range(10):
		floor.player.grant_ability(&"slime_spikes")
		floor._add_projectile(floor.player, &"player", Vector3(0, 15, -20), Vector3.RIGHT, 12, 1.0, 18, "restart_%d" % iteration, 0.55, 3.0)
		floor.player.apply_environment_damage(500)
		_check(paused and not floor.player.is_alive(), "death pauses before restart %d" % iteration)
		floor._restart_at_checkpoint()
		await _frames(8)
		floor = current_scene as FirstFloorGame
		_check(floor != null and not paused, "scene restart %d" % iteration)
		if floor == null:
			quit(1)
			return
		_check(floor.player.health == SlimeController.MAX_HEALTH and floor.player.has_learned(&"sticky_spit") and not floor.player.has_learned(&"slime_spikes"), "atomic ability rollback %d" % iteration)
		_check(floor.player.get_slot_ability(1) == &"sticky_spit" and floor.player.unlocked_slots == 1, "atomic slots %d" % iteration)
		_check(get_nodes_in_group(&"projectiles").is_empty() and get_nodes_in_group(&"enemy_attacks").is_empty(), "no old attacks %d" % iteration)
		_check(floor._checkpoint_state["defeated"] == snapshot["defeated"], "consistent enemies %d" % iteration)
		var count := root.get_child_count()
		if iteration == 0:
			stable_count = count
		_check(count == stable_count, "stable root count %d" % iteration)
	_check(FileAccess.get_file_as_string("user://checkpoint.json") == saved, "floor leaves demo save intact")
	floor._back_to_menu()
	await _frames(8)
	launch = current_scene
	_check(launch.scene_file_path == "res://scenes/launch.tscn", "return to shared menu")
	var workshop_button := launch.find_child("LabWorkshopButton", true, false) as Button
	workshop_button.pressed.emit()
	await _frames(8)
	_check(current_scene.scene_file_path == "res://scenes/art_review/lab_workshop.tscn", "workshop inside same project")
	_check(FileAccess.get_file_as_string("user://checkpoint.json") == saved, "workshop leaves demo save intact")
	print("SUMMARY: %d failed" % failures)
	await _frames(3)
	if failures > 0:
		quit(1)
		return
	SlimeGameSettings.current().request_quit()


func _check(ok: bool, label: String) -> void:
	if ok:
		print("PASS " + label)
	else:
		failures += 1
		printerr("FAIL " + label)


func _frames(count: int) -> void:
	for index in range(count):
		await physics_frame
