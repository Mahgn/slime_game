extends SceneTree

const RUN := "res://scenes/keepers/keepers_run.tscn"
const OUT := "res://output/keepers_run_2026_10_08/"
var level: SlimeKeepersRun
var failures := 0
var checks := 0
var capture := false
var tick := 0
var records: Array = []


func _initialize() -> void:
	capture = OS.get_cmdline_user_args().has("--capture")
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "images"))
	SlimeGameSettings.current().load_settings(OUT + "test_settings.cfg")
	var watchdog := Timer.new()
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.wait_time = 170
	root.add_child(watchdog)
	watchdog.timeout.connect(func() -> void: printerr("FAIL run watchdog"); quit(124))
	watchdog.start()
	var saves_before := _saves()
	change_scene_to_file("res://scenes/launch.tscn")
	await _frames(8)
	for button: Button in current_scene.find_children("*", "Button", true, false):
		if button.is_visible_in_tree():
			_check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(button.get_global_rect()), "menu button fits: " + button.name)
	await _shot("menu")
	# Isolated arenas remain a regression fixture. The menu now opens the
	# seamless world, whose actual menu connection is tested separately.
	change_scene_to_file(RUN)
	await _frames(12)
	level = current_scene as SlimeKeepersRun
	_check(is_instance_valid(level), "isolated route fixture starts")
	if not is_instance_valid(level):
		quit(1)
		return
	_check(level.rooms.size() == 15 and level.player.unlocked_slots == 1, "thirteen main rooms, two secrets, one starting slot")
	await _shot("entry")
	if capture:
		await _camera_comparison()
	# Initial-room death used to lack a snapshot. The test damages a real actor.
	level.player.apply_environment_damage(100)
	await _frames(3)
	_check(level.finished and paused, "death pauses route and shows retry")
	level.retry_room()
	await _frames(12)
	_check(not level.finished and not paused and level.player.health == 100 and level.room_id == "entry", "initial room retry restores a new living actor")
	await _travel("junction")
	await _drive(Vector3(0, 0, 2))
	await _frames(80)
	_check(level.alive_enemies().size() == 1, "first group spawns when entering arena")
	_check(not level.request_travel("furnace"), "live encounter blocks travel")
	var time_before := level.elapsed_seconds
	var wave_before := level._wave_delay
	var enemy: Node3D = level.alive_enemies()[0]
	var enemy_at := enemy.position
	level._pause_game()
	await _frames(30)
	_check(is_equal_approx(level.elapsed_seconds, time_before) and is_equal_approx(level._wave_delay, wave_before) and enemy.position.is_equal_approx(enemy_at), "pause freezes route clock, wave countdown and enemy movement")
	await _shot("pause")
	level._resume_game()
	await _fixture_clear()
	await _absorb(&"sticky_spit")
	_check(level.player.has_learned(&"sticky_spit") and level.player.get_slot_ability(1) == &"sticky_spit", "hold E absorbs first skill into first slot")
	await _shot("junction-cleared")
	await _secret("spring")
	await _absorb(&"elastic_shell")
	_check(level.secrets_found.has("spring") and level.player.has_learned(&"elastic_shell"), "first secret grants early shell through existing absorption")
	await _shot("secret-spring")
	await _travel("junction", true)
	_check(level.alive_enemies().is_empty() and level.cleared.has("junction"), "return does not repopulate cleared room")
	await _travel("furnace")
	level.player._cooldowns[&"sticky_spit"] = 2.0
	level.player.grant_ability(&"slime_spikes")
	level.player.apply_environment_damage(100)
	await _frames(2)
	await _shot("death")
	level.retry_room()
	await _frames(12)
	_check(not level.player.has_learned(&"slime_spikes") and level.player.has_learned(&"sticky_spit") and level.player.has_learned(&"elastic_shell") and level.player.health == 100 and level.player.cooldown_remaining(&"sticky_spit") == 0.0, "death rolls back only current room to entry skills, health and cooldown")
	_check(level.cleared.has("junction") and level.secrets_found.has("spring"), "retry retains previous rooms and secrets")
	await _fixture_clear()
	await _shot("furnace")
	await _travel("cinder_gallery")
	await _fixture_clear()
	await _shot("cinder_gallery")
	await _travel("hub")
	await _fixture_clear()
	await _absorb(&"slime_spikes")
	await _shot("hub")
	await _secret("archive")
	await _drive(Vector3.ZERO)
	await _press_e()
	_check(level.player.unlocked_slots == 2 and level.rewards_claimed.has("archive"), "secret core opens existing second slot")
	_check(not level.try_interact(), "core cannot be claimed twice")
	await _shot("secret-archive")
	level.hud.toggle_loadout()
	await _frames(3)
	_check(level.hud.loadout_open and paused, "safe loadout opens and pauses")
	_check(level.combat.equip_ability(2, &"slime_spikes"), "second slot can equip learned spikes")
	await _shot("loadout")
	level.hud.close_loadout()
	await _frames(3)
	await _travel("hub", true)
	await _travel("armory")
	await _fixture_clear()
	await _shot("armory")
	await _travel("barracks")
	await _fixture_clear()
	await _shot("barracks")
	await _travel("gauntlet")
	await _fixture_clear()
	await _shot("gauntlet")
	await _travel("summit")
	await _fixture_clear()
	await _shot("summit")
	# Revisit both alternative branches through real doors and walking.
	await _travel("gauntlet", true)
	await _travel("barracks", true)
	await _travel("armory", true)
	await _travel("hub", true)
	await _travel("cinder_gallery", true)
	await _travel("furnace", true)
	await _travel("junction", true)
	await _travel("cistern")
	await _fixture_clear()
	await _shot("cistern")
	await _travel("pump_room")
	await _fixture_clear()
	await _shot("pump_room")
	await _travel("hub")
	await _travel("garden")
	await _fixture_clear()
	await _shot("garden")
	await _travel("root_cellar")
	await _fixture_clear()
	await _shot("root_cellar")
	await _travel("gauntlet")
	await _travel("summit")
	_check(level.visited.size() == 15 and level.secrets_found.size() == 2, "both branches and both secrets reachable")
	await _drive(level.geometry.get_door_position(0, 1))
	await _press_e()
	_check(level.finished and level.victory and paused, "E at cleared summit completes route")
	await _shot("ending")
	_check(_saves() == saves_before, "route does not modify existing save files")
	level.restart_run()
	await _frames(15)
	level = current_scene as SlimeKeepersRun
	_check(level.room_id == "entry" and level.visited.size() == 1 and level.secrets_found.is_empty() and level.player.learned_abilities.is_empty() and level.player.unlocked_slots == 1, "full restart clears route progress, skills, secrets and slots")
	var baseline := get_node_count()
	for i in 3:
		level.player.apply_environment_damage(100)
		await _frames(2)
		level.retry_room()
		await _frames(15)
		_check(get_node_count() == baseline, "retry does not accumulate nodes %d" % i)
	level.return_to_menu()
	await _frames(12)
	_check(current_scene.scene_file_path == "res://scenes/launch.tscn" and not paused, "return to menu unpauses")
	for group in [&"enemies", &"enemy_projectiles", &"enemy_attacks", &"absorb_sources", &"spitter_remains"]:
		_check(get_nodes_in_group(group).is_empty(), "menu clears group " + String(group))
	FileAccess.open(OUT + ("native.json" if capture else "headless.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures, "records": records, "note": "Fixture kills validate flow only, not combat pacing."}, "\t"))
	print("KEEPERS_RUN_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _fixture_clear() -> void:
	await _drive(Vector3(0, 0, 2))
	var room := level.room_id
	for i in 700:
		for enemy in level.alive_enemies():
			enemy.receive_hit(999, "route_fixture_%d" % tick, &"player")
			tick += 1
		if level.cleared.has(room):
			await _frames(40)
			_check(level.room_is_safe(), "fixture completes every wave: " + room)
			return
		await _frames(1)
	_check(false, "encounter did not clear: " + room)


func _absorb(ability: StringName) -> void:
	var source: AbsorbSource
	for candidate in level.combat.get_children():
		if candidate is AbsorbSource and candidate.ability_id == ability and not candidate.is_claimed():
			source = candidate
			break
	_check(is_instance_valid(source), "source exists: " + String(ability))
	if not is_instance_valid(source):
		return
	await _drive(source.position + Vector3(0, 0, 0.65))
	Input.action_release(&"interact")
	await _frames(2)
	Input.action_press(&"interact")
	await _frames(45)
	Input.action_release(&"interact")
	await _frames(2)
	_check(level.player.has_learned(ability), "actual held E claims " + String(ability))


func _travel(destination: String, back: bool = false) -> void:
	var exits: Array = level.current_room().exits
	var at: Vector3 = level.geometry.get_back_position() if back else level.geometry.get_door_position(exits.find(destination), exits.size())
	await _drive(at)
	await _press_e()
	_check(level.room_id == destination, "physical door transition to " + destination)
	_check(level.player.health == 100 and level.player.cooldown_remaining(&"sticky_spit") == 0, "room entry restores health and cooldown: " + destination)


func _secret(destination: String) -> void:
	await _drive(level.geometry.get_secret_position())
	await _press_e()
	_check(level.room_id == destination, "physical secret entrance " + destination)


func _press_e() -> void:
	Input.action_release(&"interact")
	await _frames(3)
	Input.action_press(&"interact")
	await _frames(1)
	Input.action_release(&"interact")
	await _frames(40)


func _drive(at: Vector3) -> void:
	for i in 500:
		var delta := at - level.player.position
		delta.y = 0
		if delta.length() < 0.55:
			_release_motion()
			await _frames(5)
			return
		var axes := level.player.controls.world_direction_to_screen_axes(delta.normalized())
		Input.action_press(&"move_right", maxf(0, axes.x))
		Input.action_press(&"move_left", maxf(0, -axes.x))
		Input.action_press(&"move_back", maxf(0, axes.y))
		Input.action_press(&"move_forward", maxf(0, -axes.y))
		await _frames(1)
	_release_motion()
	_check(false, "walk failed in %s: %s from %s" % [level.room_id, at, level.player.position])


func _release_motion() -> void:
	for action in [&"move_right", &"move_left", &"move_back", &"move_forward"]:
		Input.action_release(action)


func _shot(label: String) -> void:
	if not capture:
		return
	await _frames(3)
	RenderingServer.force_draw()
	var result := root.get_texture().get_image().save_png(OUT + "images/" + label + ".png")
	_check(result == OK, "native capture " + label)


func _camera_comparison() -> void:
	for i in 3:
		var at: Vector3 = [Vector3(0, 0, 4.8), Vector3(4.5, 0, -4.2), Vector3(-4.5, 0, 3.8)][i]
		await _drive(at)
		level.set_physics_process(false)
		level.set_meta(&"isometric_camera_center", Vector3(0, 0.6, 0))
		level.player.presentation._update_camera(0.0)
		await _shot("camera-%d-fixed" % i)
		level._update_camera_center()
		level.player.presentation._update_camera(0.0)
		await _shot("camera-%d-follow" % i)
		var screen := level.player.presentation.camera.unproject_position(level.player.position + Vector3.UP * 0.5)
		_check(screen.y > 125 and screen.y < 560 and screen.x > 24 and screen.x < 1256, "follow keeps hero clear of HUD at sample %d" % i)
		level.set_physics_process(true)
	await _drive(Vector3.ZERO)
	var height: float = level.player.presentation.camera.position.y
	var deviation := 0.0
	Input.action_press(&"jump")
	await _frames(44)
	Input.action_release(&"jump")
	for i in 65:
		await _frames(1)
		deviation = maxf(deviation, absf(height - level.player.presentation.camera.position.y))
	_check(deviation < 0.001 and level.player.is_on_floor(), "charged jump lands without vertical camera movement")
	await _drive(Vector3(0, 0, 4.8))


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label)
	records.append({"pass": ok, "label": label})


func _saves() -> Dictionary:
	var result: Dictionary = {}
	for path in ["user://checkpoint.json", "user://checkpoint.json.bak", "user://savegame.json"]:
		result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "ABSENT"
	return result
