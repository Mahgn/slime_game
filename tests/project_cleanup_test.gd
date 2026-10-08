extends SceneTree

const MENU = preload("res://scenes/launch.tscn")
const FIXTURE = preload("res://tests/helpers/combat_fixture.tscn")
const MENU_SETTINGS := "res://output/level_cleanup/menu_test_settings.cfg"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var watchdog := Timer.new()
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.wait_time = 40.0
	watchdog.one_shot = true
	root.add_child(watchdog)
	watchdog.timeout.connect(func() -> void: printerr("FAIL cleanup watchdog"); quit(124))
	watchdog.start()
	for directory in ["scenes/levels", "scenes/art_review", "scripts/levels", "scripts/art_review", "slime_lab"]:
		var remaining := _old_runtime_files("res://" + directory)
		if not remaining.is_empty():
			print("CLEANUP_REMAINS ", remaining)
		_check(remaining.is_empty(), "removed runtime content from " + directory)
	var checkpoint_before := _checkpoint_text()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MENU_SETTINGS.get_base_dir()))
	SlimeGameSettings.current().load_settings(MENU_SETTINGS)
	var menu := MENU.instantiate() as Control
	root.add_child(menu)
	current_scene = menu
	await _frames(4)
	var captions: Array[String] = []
	for button in menu.find_children("*", "Button", true, false):
		if button.is_visible_in_tree():
			captions.append(button.text)
	_check(captions == ["Играть", "Путь смотрителя · новый корпус", "Котельная смотрителя", "Настройки", "Выход"], "menu exposes three routes, settings and exit")
	var settings_button := menu.find_child("SettingsButton", true, false) as Button
	settings_button.pressed.emit()
	await _frames(2)
	_check(menu._settings_panel.visible and not menu._main_panel.visible, "settings open")
	menu._settings_panel.close_and_save()
	await _frames(2)
	_check(not menu._settings_panel.visible and menu._main_panel.visible, "settings return to menu")
	_check(_checkpoint_text() == checkpoint_before, "menu leaves old checkpoint untouched")
	await _check_play_entry(menu, checkpoint_before)
	menu = current_scene as Control
	current_scene = null
	menu.queue_free()
	await _frames(4)
	var baseline := get_node_count()
	for iteration in 10:
		var fixture := FIXTURE.instantiate()
		root.add_child(fixture)
		await _frames(5)
		var enemy: Spitter = fixture.spawn_spitter(Vector3(0, 0.05, -3))
		enemy.set_physics_process(false)
		enemy.projectile_requested.emit(enemy, enemy.global_position + Vector3.UP * 0.5, Vector3.FORWARD, 10, 8.0, 12.0, "restart_%d" % iteration)
		enemy.receive_hit(30, "kill_%d" % iteration, &"player")
		await _frames(2)
		_check(fixture.combat.get_child_count() >= 2, "runtime owns attack and source %d" % iteration)
		fixture.queue_free()
		await _frames(4)
		var clean := get_node_count() == baseline
		for group in [&"enemies", &"enemy_projectiles", &"enemy_attacks", &"temporary_effects", &"absorb_sources", &"spitter_remains"]:
			clean = clean and get_nodes_in_group(group).is_empty()
		_check(clean, "restart clears combat nodes and signals %d" % iteration)
	var fixture := FIXTURE.instantiate()
	root.add_child(fixture)
	await _frames(5)
	fixture.player.grant_ability(&"sticky_spit")
	fixture.player.grant_ability(&"elastic_shell")
	await _frames(32)
	_check(fixture.combat.can_change_loadout(), "loadout unlocks after safe interval")
	var guardian := ExitGuardian.new()
	guardian.process_mode = Node.PROCESS_MODE_PAUSABLE
	guardian.position = Vector3(3, 0.05, -3)
	fixture.add_child(guardian)
	fixture.combat.bind_enemy(guardian)
	guardian.set_physics_process(false)
	await _frames(2)
	_check(not fixture.combat.equip_ability(1, &"elastic_shell"), "loadout replacement blocked during combat")
	guardian.line_requested.emit(guardian, guardian.global_position, Vector3.FORWARD, "guardian_line")
	_check(get_nodes_in_group(&"enemy_attacks").size() == 1, "guardian line retained outside old R07")
	guardian.receive_hit(180, "guardian_finish", &"player")
	await _frames(3)
	_check(get_nodes_in_group(&"enemy_attacks").is_empty(), "guardian death clears owned threats")
	await _frames(32)
	_check(fixture.combat.equip_ability(1, &"elastic_shell"), "loadout replacement allowed after combat")
	fixture.queue_free()
	await _frames(4)
	_check(get_node_count() == baseline, "guardian fixture freed")
	print("CLEANUP_RESULT failures=%d" % failures)
	quit(0 if failures == 0 else 1)


func _check_play_entry(menu: Control, checkpoint_before: String) -> void:
	var baseline := get_node_count()
	(menu.find_child("PlayButton", true, false) as Button).pressed.emit()
	await _frames(10)
	var workspace := current_scene as SlimeLevelWorkspace
	_check(is_instance_valid(workspace), "Play opens the real starting scene")
	if not is_instance_valid(workspace):
		return
	var hero := workspace.player
	_check(hero.is_on_floor() and hero.health == SlimeController.MAX_HEALTH and hero.learned_abilities.is_empty(), "Play starts a fresh grounded hero without restoring old progression")
	_check(get_nodes_in_group(&"enemies").is_empty(), "starting scene has no old enemies")
	var start := hero.global_position
	Input.action_press(&"move_right")
	await _frames(18)
	Input.action_release(&"move_right")
	await _frames(5)
	_check(hero.global_position.distance_to(start) > 0.5 and hero.is_on_floor(), "WASD input moves the hero on the new surface")
	var floor_y := hero.global_position.y
	Input.action_press(&"jump")
	await _frames(14)
	Input.action_release(&"jump")
	var peak_y := floor_y
	for frame in 50:
		await _frames(1)
		peak_y = maxf(peak_y, hero.global_position.y)
	_check(peak_y > floor_y + 0.4 and hero.is_on_floor(), "starting scene supports the real charged jump and landing")
	var casts := hero._cast_sequence
	Input.action_press(&"attack_primary")
	await _frames(2)
	Input.action_release(&"attack_primary")
	_check(hero._cast_sequence > casts and hero._action == &"slime_whip", "primary input starts the real whip")
	await _frames(30)
	_push_pause()
	await _frames(3)
	_check(paused and workspace._pause_panel.visible, "Escape opens the starting scene pause menu")
	var paused_position := hero.global_position
	Input.action_press(&"move_right")
	await _frames(10)
	Input.action_release(&"move_right")
	_check(hero.global_position.is_equal_approx(paused_position), "pause freezes the hero in the starting scene")
	_push_pause()
	await _frames(3)
	_check(not paused and not workspace._pause_panel.visible, "Escape resumes the starting scene")
	hero.global_position = Vector3(8, -5, 0)
	await _frames(10)
	_check(hero.global_position.distance_to(start) < 0.2 and hero.is_on_floor(), "falling outside the route returns the hero safely")
	workspace._pause_game()
	workspace._pause_panel._request_menu()
	_check(workspace._pause_panel._confirm.visible, "return to menu asks before ending the current session")
	workspace._pause_panel._go_to_menu()
	await _frames(6)
	_check(current_scene is Control and current_scene.scene_file_path == "res://scenes/launch.tscn" and not paused, "starting scene returns to the main menu")
	_check(get_node_count() == baseline and get_nodes_in_group(&"player").is_empty(), "return frees the starting scene and player")
	_check(_checkpoint_text() == checkpoint_before, "playing leaves old checkpoints untouched")
	var returned_menu := current_scene as Control
	(returned_menu.find_child("PlayButton", true, false) as Button).pressed.emit()
	await _frames(8)
	workspace = current_scene as SlimeLevelWorkspace
	_check(is_instance_valid(workspace) and workspace.player.global_position.distance_to(start) < 0.2, "Play works again after returning to the menu")
	if is_instance_valid(workspace):
		workspace._pause_panel._go_to_menu()
		await _frames(6)


func _push_pause() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event)


func _checkpoint_text() -> String:
	return FileAccess.get_file_as_string("user://checkpoint.json") if FileAccess.file_exists("user://checkpoint.json") else "<missing>"


func _old_runtime_files(root_path: String) -> Array[String]:
	var remaining: Array[String] = []
	if not DirAccess.dir_exists_absolute(root_path):
		return remaining
	# Scan only the five retired roots above. User backups and local output may
	# remain there, but an old scene, script or runtime resource must still fail.
	var pending: Array[Dictionary] = [{"path": root_path, "depth": 0}]
	var scanned_entries := 0
	while not pending.is_empty():
		var entry: Dictionary = pending.pop_back()
		var path: String = entry["path"]
		var depth: int = entry["depth"]
		if depth > 32:
			remaining.append("scan depth exceeded: " + path)
			return remaining
		var directory := DirAccess.open(path)
		if directory == null:
			remaining.append("cannot inspect: " + path)
			return remaining
		directory.include_hidden = true
		if directory.list_dir_begin() != OK:
			remaining.append("cannot list: " + path)
			return remaining
		var name := directory.get_next()
		while not name.is_empty():
			scanned_entries += 1
			if scanned_entries > 20000:
				directory.list_dir_end()
				remaining.append("scan entry limit exceeded: " + root_path)
				return remaining
			var child_path := path.path_join(name)
			if name == ".godot" or name == "." or name == "..":
				pass
			elif directory.is_link(name):
				# Never follow a link outside the retired tree or accept an
				# uninspected linked subtree as successfully cleaned.
				remaining.append("uninspected link: " + child_path)
			elif directory.current_is_dir():
				pending.append({"path": child_path, "depth": depth + 1})
			elif name.to_lower() == "project.godot" or name.get_extension().to_lower() in ["gd", "tscn", "scn", "tres", "res", "gdshader"]:
				remaining.append(child_path)
			name = directory.get_next()
		directory.list_dir_end()
	return remaining


func _frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func _check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value:
		failures += 1
