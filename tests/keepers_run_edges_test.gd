extends SceneTree

# Integration fixtures place actors and apply lethal hits to reach boundaries.
# Keyboard/mouse cases go through InputEvent dispatch, never route._input().
# These checks do not measure combat pacing or visual quality.
const RUN := "res://scenes/keepers/keepers_run.tscn"
const OUT := "res://output/keepers_run_2026_10_08/"
var level: SlimeKeepersRun
var checks := 0
var failures := 0
var records: Array[Dictionary] = []
var rates: Array[int] = [60]
var ticks := 60
var cast_sequence := 0
var completed := false
var original_ticks := 60


func _initialize() -> void:
	original_ticks = Engine.physics_ticks_per_second
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("ticks="):
			var requested := int(argument.trim_prefix("ticks="))
			if requested in [30, 60, 120]:
				rates.assign([requested])
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	SlimeGameSettings.current().load_settings(OUT + "edges_test_settings.cfg")
	var watchdog := Timer.new()
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.one_shot = true
	watchdog.wait_time = 150.0
	root.add_child(watchdog)
	watchdog.timeout.connect(func() -> void:
		_check(false, "watchdog expired")
		_finish(124)
	)
	watchdog.start()
	var saves_before := _saves()
	for rate in rates:
		ticks = rate
		Engine.physics_ticks_per_second = ticks
		if not await _fresh_run():
			break
		await _tab_events()
		await _simultaneous_travel_actions()
		if not await _fresh_run():
			break
		await _encounter_and_snapshot_edges()
	_check(_saves() == saves_before, "existing save files unchanged")
	_release_input()
	paused = false
	if is_instance_valid(current_scene):
		current_scene.queue_free()
	await _frames(3)
	_finish(0 if failures == 0 else 1)


func _fresh_run() -> bool:
	_release_input()
	paused = false
	var result := change_scene_to_file(RUN)
	_check(result == OK, "new fixture scene can be loaded")
	if result != OK:
		return false
	await _seconds(0.70)
	level = current_scene as SlimeKeepersRun
	_check(is_instance_valid(level), "new fixture is a KeepersRun")
	if not is_instance_valid(level):
		return false
	_check(level.room_id == "entry" and level.room_is_safe(), "entry fixture is safe and settled")
	return true


func _tab_events() -> void:
	_key(KEY_TAB, true)
	await _frames(3)
	_check(level.hud.loadout_open and paused, "real Tab press opens and pauses loadout")
	_key(KEY_TAB, false)
	await _frames(3)
	_check(level.hud.loadout_open and paused, "Tab release does not close loadout")
	_key(KEY_TAB, true)
	await _frames(4)
	_check(not level.hud.loadout_open and not paused, "second Tab press closes without reopening on physics ticks")
	_key(KEY_TAB, false)
	await _frames(3)
	_check(not level.hud.loadout_open and not paused, "closed loadout remains closed after release")
	_key(KEY_TAB, true)
	await _frames(2)
	_key(KEY_TAB, false)
	_key(KEY_ESCAPE, true)
	await _frames(3)
	_check(not level.hud.loadout_open and not paused and not level._pause_panel.visible, "Esc closes only loadout without opening the pause panel")
	_key(KEY_ESCAPE, false)
	await _frames(2)


func _simultaneous_travel_actions() -> void:
	# First prove the injected mouse events actually reach the controller.
	_mouse(MOUSE_BUTTON_LEFT, true)
	await _frames(1)
	_check(level.player._action == &"slime_whip", "real left mouse press starts whip outside travel")
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _seconds(0.75)
	level.player.grant_ability(&"sticky_spit")
	_mouse(MOUSE_BUTTON_RIGHT, true)
	await _frames(1)
	_check(level.player._action == &"sticky_spit", "real right mouse press starts equipped skill outside travel")
	_mouse(MOUSE_BUTTON_RIGHT, false)
	await _seconds(0.75)
	await _place_player(level.geometry.get_door_position(0, 1))
	await _travel_with_mouse("junction", MOUSE_BUTTON_LEFT, "E + left mouse")
	# This fixture has no active enemy/wave: isolate the second mouse binding.
	level.cleared["junction"] = true
	await _seconds(0.65)
	await _place_player(level.geometry.get_back_position())
	await _travel_with_mouse("entry", MOUSE_BUTTON_RIGHT, "E + right mouse")


func _travel_with_mouse(destination: String, button: MouseButton, label: String) -> void:
	_check(level.room_is_safe(), label + " begins at a valid safe door")
	var started: Array[StringName] = []
	var observer := func(ability: StringName) -> void: started.append(ability)
	level.player.action_started.connect(observer)
	_key(KEY_E, true)
	_mouse(button, true)
	_check(Input.is_action_pressed(&"interact") and Input.is_action_pressed(&"attack_primary" if button == MOUSE_BUTTON_LEFT else &"ability_slot_1"), label + " injects both actions before the same physics tick")
	await _frames(1)
	_key(KEY_E, false)
	_mouse(button, false)
	_check(level.room_id == destination, label + " completes the requested transition")
	_check(started.is_empty() and level.player._action == &"" and level.player._phase == &"", label + " does not start or carry a combat action")
	_check(level.player.is_physics_processing(), label + " restores controller physics after travel")
	await _frames(4)
	_check(started.is_empty() and level.player._action == &"", label + " does not release a delayed action in the new room")
	_check(get_nodes_in_group(&"temporary_effects").is_empty(), label + " clears previous room combat effects")
	level.player.action_started.disconnect(observer)


func _encounter_and_snapshot_edges() -> void:
	if not await _travel_e("junction", level.geometry.get_door_position(0, 1)):
		return
	await _place_player(Vector3(0, 0, 2.8))
	if not await _wait_for_enemies(1, 3.0):
		return
	var enemy: CharacterBody3D = level.alive_enemies()[0]
	var enemy_id := enemy.get_instance_id()
	enemy.set("attack_permission", func(_actor: Node3D) -> bool: return false)
	_hit(enemy, 10)
	var health_before := int(enemy.get("health"))
	var kills_before := level.kills
	var sources_before := get_nodes_in_group(&"absorb_sources").size()
	enemy.position = Vector3(0, -5.0, 8.0)
	enemy.velocity = Vector3(0, -20, 2)
	await _seconds(0.20)
	_check(is_instance_valid(enemy) and enemy.get_instance_id() == enemy_id and enemy.call("is_alive"), "fallen enemy returns as the same living actor")
	if not is_instance_valid(enemy):
		return
	_check(enemy.position.y > -0.2 and enemy.position.y < 0.3 and enemy.is_on_floor(), "fallen enemy regains physical floor support")
	_check(int(enemy.get("health")) == health_before and level.kills == kills_before and get_nodes_in_group(&"absorb_sources").size() == sources_before, "enemy return preserves damage and grants no kill or ability source")
	_check(level.alive_enemies().size() == 1 and not level.cleared.has("junction"), "returned enemy still belongs to the current encounter")
	_hit(enemy, 999)
	await _frames(1)
	await _seconds(0.65)
	_check(level.alive_enemies().is_empty() and level._wave_delay > 0.0 and not level.cleared.has("junction"), "fixture reaches the gap before the next wave")
	_check(level.combat.can_change_loadout(), "low-level threat timer has elapsed during the wave gap")
	_key(KEY_TAB, true)
	await _frames(2)
	_check(not level.hud.loadout_open and not paused, "real Tab cannot change loadout between unfinished waves")
	_key(KEY_TAB, false)
	if not await _clear_encounter():
		return
	var sources := _sources(&"sticky_spit")
	_check(not sources.is_empty() and not level.player.has_learned(&"sticky_spit"), "cleared room contains an unlearned absorption source")
	if sources.is_empty():
		return
	var source_at: Vector3 = sources[0].position
	if not await _travel_e("spring", level.geometry.get_secret_position()):
		return
	_check(_sources(&"sticky_spit").is_empty(), "previous room source does not leak into the secret room")
	if not await _travel_e("junction", level.geometry.get_back_position()):
		return
	sources = _sources(&"sticky_spit")
	_check(sources.size() == 1 and sources[0].position.is_equal_approx(source_at) and not sources[0].is_claimed(), "return restores an unclaimed source at its original position without duplicates")
	_check(not level.player.has_learned(&"sticky_spit"), "return does not grant an unabsorbed ability")
	var old_player_id := level.player.get_instance_id()
	var cleared_kills := level.kills
	# Acquiring a different ability after this entry must roll back on death.
	level.player.grant_ability(&"elastic_shell")
	level.player.apply_environment_damage(100)
	await _frames(2)
	_check(level.finished and paused, "death in a revisited cleared room opens the paused result")
	(level.hud.find_child("RetryRoomButton", true, false) as Button).pressed.emit()
	await _seconds(0.70)
	_check(level.player.get_instance_id() != old_player_id and level.player.health == 100 and not level.finished and not paused, "retry button recreates a living player from the room snapshot")
	_check(not level.player.has_learned(&"elastic_shell") and not level.player.has_learned(&"sticky_spit"), "retry restores the entry collection without keeping later grants")
	_check(level.cleared.has("junction") and level.cleared.has("spring") and level.secrets_found.has("spring") and level.kills == cleared_kills, "cleared-room retry preserves prior clears, secret discovery and kill total")
	await _place_player(Vector3(0, 0, 2.8))
	await _seconds(1.50)
	_check(level.alive_enemies().is_empty() and level.room_is_safe(), "crossing the encounter trigger after cleared-room retry does not respawn waves")
	sources = _sources(&"sticky_spit")
	_check(sources.size() == 1 and sources[0].position.is_equal_approx(source_at) and not sources[0].is_claimed(), "cleared-room retry restores its unlearned entry source")
	_check(level.hud._player == level.player and level.hud._combat == level.combat and level.hud._health.text.contains("100"), "HUD binds the replacement player and combat after retry")
	_key(KEY_TAB, true)
	await _frames(2)
	_check(level.hud.loadout_open and paused, "real Tab works with the replacement runtime after retry")
	_key(KEY_TAB, false)
	_key(KEY_TAB, true)
	await _frames(3)
	_key(KEY_TAB, false)
	_check(not level.hud.loadout_open and not paused, "replacement runtime closes loadout without a stale-reference pause")


func _wait_for_enemies(expected: int, seconds: float) -> bool:
	for index in ceili(seconds * ticks):
		if level.alive_enemies().size() == expected:
			_check(true, "encounter spawns expected group of %d" % expected)
			return true
		await _frames(1)
	_check(false, "encounter did not spawn expected group of %d" % expected)
	return false


func _clear_encounter() -> bool:
	for index in ceili(8.0 * ticks):
		for enemy in level.alive_enemies():
			_hit(enemy, 999)
		if level.cleared.has(level.room_id):
			await _seconds(0.70)
			_check(level.room_is_safe(), "fixture finishes all waves and the threat cooldown")
			return level.room_is_safe()
		await _frames(1)
	_check(false, "fixture could not finish the encounter")
	return false


func _hit(enemy: Node, damage: int) -> void:
	cast_sequence += 1
	enemy.call("receive_hit", damage, "edge_fixture_%d" % cast_sequence, &"player")


func _sources(ability: StringName) -> Array[AbsorbSource]:
	var result: Array[AbsorbSource] = []
	for child in level.combat.get_children():
		if child is AbsorbSource and child.ability_id == ability and not child.is_claimed():
			result.append(child)
	return result


func _travel_e(destination: String, at: Vector3) -> bool:
	await _place_player(at)
	_key(KEY_E, true)
	await _frames(1)
	_key(KEY_E, false)
	await _seconds(0.65)
	var arrived := level.room_id == destination
	_check(arrived, "real E travels to " + destination)
	return arrived


func _place_player(at: Vector3) -> void:
	level.player.position = at + Vector3.UP * 0.05
	level.player.velocity = Vector3.ZERO
	level.player.cancel_absorb_for_pause()
	level.player.clear_action_buffer()
	_key(KEY_E, false)
	await _frames(6)
	_check(level.player.is_on_floor(), "interaction fixture has physical floor support")


func _key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _mouse(button: MouseButton, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = down
	event.position = Vector2(800, 360)
	event.global_position = event.position
	event.button_mask = (MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if down else 0
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _release_input() -> void:
	for code in [KEY_E, KEY_TAB, KEY_ESCAPE]:
		_key(code, false)
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		_mouse(button, false)
	for action in [&"move_left", &"move_right", &"move_forward", &"move_back", &"jump", &"interact", &"attack_primary", &"ability_slot_1", &"ability_slot_2"]:
		if InputMap.has_action(action):
			Input.action_release(action)


func _frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame


func _seconds(value: float) -> void:
	await _frames(ceili(value * ticks))


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	var tagged := "%d Hz: %s" % [ticks, label]
	print(("PASS " if ok else "FAIL ") + tagged)
	records.append({"pass": ok, "physics_hz": ticks, "label": label})


func _saves() -> Dictionary:
	var result: Dictionary = {}
	for path in ["user://checkpoint.json", "user://checkpoint.json.bak", "user://savegame.json"]:
		result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "ABSENT"
	return result


func _finish(exit_code: int) -> void:
	if completed:
		return
	completed = true
	Engine.physics_ticks_per_second = original_ticks
	var suffix := "_%d" % rates[0] if rates.size() == 1 else ""
	var file := FileAccess.open(OUT + "edges" + suffix + ".json", FileAccess.WRITE)
	if file == null:
		printerr("FAIL cannot write edges JSON: ", FileAccess.get_open_error())
		exit_code = 1
	else:
		file.store_string(JSON.stringify({"checks": checks, "failures": failures, "physics_rates": rates, "records": records, "note": "Integration fixtures, real dispatched keyboard/mouse input. Does not validate combat pacing, native frame rate or visual quality."}, "\t"))
		file.close()
	print("KEEPERS_RUN_EDGES_RESULT checks=%d failures=%d" % [checks, failures])
	quit(exit_code)
