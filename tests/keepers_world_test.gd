extends SceneTree

# Physical integration route. Lethal fixture hits keep traversal independent of
# combat strategy; they are not evidence for fight difficulty or play duration.
const WORLD := "res://scenes/keepers/keepers_world.tscn"
const OUT := "res://output/keepers_seamless_2026_10_08/"
var level
var checks := 0
var failures := 0
var records: Array[Dictionary] = []
var capture := false
var fixture_hits := false
var cast_sequence := 0
var explored: Dictionary = {}
var covered_edges: Dictionary = {}
var root_ids: Dictionary = {}
var room_geometry_ids: Dictionary = {}
var player_id := 0
var geometry_id := 0
var entry_camera_height := 0.0
var max_camera_step := 0.0
var max_player_step := 0.0
var last_camera := Vector3.ZERO
var last_player := Vector3.ZERO
var tracking := false
var completed := false


func _initialize() -> void:
	capture = OS.get_cmdline_user_args().has("--capture")
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "images"))
	SlimeGameSettings.current().load_settings(OUT + "route_test_settings.cfg")
	var watchdog := Timer.new()
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.wait_time = 900.0
	watchdog.one_shot = true
	root.add_child(watchdog)
	watchdog.timeout.connect(func() -> void:
		_check(false, "route watchdog expired")
		_finish(124))
	watchdog.start()
	var saves_before := _saves()
	_check(change_scene_to_file(WORLD) == OK, "seamless scene loads")
	await _frames(30)
	level = current_scene
	if DisplayServer.get_name() != "headless":
		root.grab_focus()
	_check(is_instance_valid(level) and level.has_method("alive_enemies"), "seamless runtime exists")
	if not is_instance_valid(level) or not level.has_method("alive_enemies"):
		_finish(1)
		return
	_check(level.rooms.size() == 15 and level.room_roots.size() == 15, "all thirteen main rooms and two secrets coexist")
	if not is_instance_valid(level.geometry) or level.room_roots.size() != 15:
		_finish(1)
		return
	_check(level.room_id == "entry" and level.player.unlocked_slots == 1, "entry starts with one slot")
	player_id = level.player.get_instance_id()
	geometry_id = level.geometry.get_instance_id()
	for id: String in level.room_roots:
		root_ids[id] = level.room_roots[id].get_instance_id()
		room_geometry_ids[id] = level.geometry.room_nodes[id].get_instance_id()
	await _shot("room-entry")
	entry_camera_height = level.player.presentation.camera.global_position.y
	if capture:
		await _camera_comparison()
	await _jump_camera()
	# Retreat from a live encounter is intentionally legal. The enemy is frozen
	# only in this persistence fixture, so it cannot kill the traversal driver.
	await _travel("entry", "junction", false)
	for i in 150:
		if not level.alive_enemies("junction").is_empty():
			break
		await _frames(1)
	var enemies: Array = level.alive_enemies("junction")
	_check(not enemies.is_empty(), "junction encounter wakes on physical arrival")
	if not enemies.is_empty():
		var enemy = enemies[0]
		enemy.receive_hit(1, "world_persistence", &"player")
		enemy.set_physics_process(false)
		var enemy_id: int = enemy.get_instance_id()
		var enemy_hp: int = enemy.health
		var enemy_phase: int = enemy._phase
		var enemy_phase_left: float = enemy._phase_left
		level.player.apply_environment_damage(23)
		level.player._cooldowns[&"sticky_spit"] = 600.0
		var hp: int = level.player.health
		var elapsed: float = level.elapsed_seconds
		var cooldown: float = level.player.cooldown_remaining(&"sticky_spit")
		level._pause_game()
		await _frames(20)
		_check(paused and is_equal_approx(level.elapsed_seconds, elapsed) and is_equal_approx(level.player.cooldown_remaining(&"sticky_spit"), cooldown), "pause freezes route time and cooldown")
		await _shot("pause")
		level._resume_game()
		await _travel("junction", "entry", false)
		_check(is_instance_valid(enemy) and enemy.get_instance_id() == enemy_id and enemy.health == enemy_hp, "retreat retains living enemy identity and health")
		_check(enemy._phase == enemy_phase and is_equal_approx(enemy._phase_left, enemy_phase_left), "retreat retains frozen fixture enemy phase and countdown")
		_check(level.player.health <= hp and level.player.cooldown_remaining(&"sticky_spit") > 500.0, "ordinary crossing neither heals nor clears cooldown")
		await _travel("entry", "junction", false)
		_check(is_instance_valid(enemy) and enemy.get_instance_id() == enemy_id and enemy.health == enemy_hp, "return resumes the same living enemy")
		enemy.set_physics_process(true)
	fixture_hits = true
	await _fixture_clear("junction")
	await _absorb(&"sticky_spit")
	await _travel("junction", "entry", false)
	await _explore("entry")
	_check(covered_edges.size() == level.connections.size(), "every connection walked in both directions without E")
	_check(level.visited.size() == 15 and level.secrets_found.size() == 2, "all rooms and both secret entrances physically reached")
	_check(level.player.has_learned(&"elastic_shell") and level.player.unlocked_slots == 2, "both secret rewards use existing skill and second slot")
	_check(max_camera_step < 0.8 and max_player_step < 0.7, "walk has no room-change camera snap or player teleport")
	_check(_saves() == saves_before, "existing save files unchanged")
	# Death is the deliberate reset boundary; remote rooms and their sources stay.
	var visited_before: Dictionary = level.visited.duplicate()
	# A roaming enemy can die outside its authored room. Its source must survive
	# rollback of a later absorption, even though another room owns the source.
	var foreign_source := load("res://scenes/interactables/absorb_source.tscn").instantiate() as AbsorbSource
	foreign_source.ability_id = &"slime_spikes"
	foreign_source.set_meta(&"home_room", "junction")
	level.combat.add_child(foreign_source)
	foreign_source.global_position = level.player.global_position + Vector3(0.7, 0, 0)
	var foreign_id := foreign_source.get_instance_id()
	var sources_before := _source_ids("entry")
	await _drive(foreign_source.global_position + Vector3(0, 0, 0.55))
	Input.action_press(&"interact")
	await _frames(45)
	Input.action_release(&"interact")
	await _frames(3)
	_check(foreign_source.is_claimed() and level.player.has_learned(&"slime_spikes"), "held E claims foreign-room source after entry snapshot")
	var previous_player: int = level.player.get_instance_id()
	level.player.apply_environment_damage(100)
	await _frames(3)
	_check(level.finished and paused, "death pauses world")
	await _shot("death")
	level.retry_room()
	# Retry is deferred by one tick and then starts the ordinary 0.5 s safety
	# interval. Wait beyond that interval before testing the loadout UI.
	await _frames(40)
	_check(not level.finished and not paused and level.player.health == 100 and level.player.get_instance_id() != previous_player, "retry creates a living hero in current room")
	_check(level.visited == visited_before and _source_ids("entry") == sources_before, "local retry preserves remote visited rooms and absorption sources")
	_check(is_instance_valid(foreign_source) and foreign_source.get_instance_id() == foreign_id and not foreign_source.is_claimed() and foreign_source.visible and foreign_source.is_processing() and foreign_source.is_in_group(&"absorb_sources") and not level.player.has_learned(&"slime_spikes"), "local retry restores the same foreign source when its absorbed skill rolls back")
	_check(level.geometry.get_instance_id() == geometry_id, "local retry retains world geometry")
	player_id = level.player.get_instance_id()
	level.hud.toggle_loadout()
	await _frames(3)
	_check(level.hud.loadout_open and paused, "safe loadout pauses seamless world")
	await _shot("loadout")
	level.hud.close_loadout()
	await _frames(3)
	await _navigate("summit")
	await _fixture_clear("summit")
	var finish_at: Vector3 = level.rooms.summit.exit_point
	if level.rooms.summit.has("walk_points"):
		for at: Vector3 in level.rooms.summit.walk_points:
			await _drive(at)
	await _drive(finish_at)
	await _press_e()
	_check(level.finished and level.victory and paused, "E at final exit completes cleared world")
	await _shot("ending")
	level.restart_run()
	await _frames(30)
	level = current_scene
	_check(level.room_id == "entry" and level.visited.size() == 1 and level.secrets_found.is_empty() and level.player.learned_abilities.is_empty() and level.player.unlocked_slots == 1, "full restart resets progress and skills")
	fixture_hits = false
	level.return_to_menu()
	await _frames(20)
	_check(current_scene.scene_file_path == "res://scenes/launch.tscn" and not paused, "menu return releases pause")
	for group in [&"enemies", &"enemy_projectiles", &"enemy_attacks", &"absorb_sources", &"spitter_remains"]:
		_check(get_nodes_in_group(group).is_empty(), "menu clears " + String(group))
	await _shot("menu")
	var launch_button := current_scene.find_child("KeepersRunButton", true, false) as Button
	_check(is_instance_valid(launch_button), "menu contains the route launch button")
	if is_instance_valid(launch_button):
		launch_button.pressed.emit()
		await _frames(30)
		level = current_scene
		_check(current_scene.scene_file_path == "res://scenes/keepers/keepers_facility.tscn" and level.room_roots.size() == 10, "menu launch opens the finalized building iteration")
		level.return_to_menu()
		await _frames(15)
	_finish(0 if failures == 0 else 1)


func _explore(id: String) -> void:
	explored[id] = true
	await _fixture_clear(id)
	var room: Dictionary = level.rooms[id]
	for point: Vector3 in room.get("walk_points", []):
		await _drive(point)
		_check(absf(level.player.global_position.y - point.y) < 0.32 and level.player.is_on_floor(), "authored floor/alternate walk point " + id + " " + str(point))
		if point.y > 0.7:
			await _frames(35)
			_check(level.player.presentation.camera.global_position.y > entry_camera_height + 0.5, "camera follows actual upper floor height on ramp: " + id)
			await _shot("upper-floor-%s-%s-%s" % [id, point.x, point.z])
			await _jump_camera()
	await _shot("room-" + id)
	if id == "spring":
		await _absorb(&"elastic_shell")
	if id == "archive":
		await _drive(room.get("reward_position", room.spawn))
		await _press_e()
		_check(level.rewards_claimed.has("archive") and level.player.unlocked_slots == 2, "E claims archive core once")
		_check(not level.try_interact(), "archive reward cannot be repeated")
	await _drive(room.spawn)
	for link: Dictionary in level.connections:
		if id != link.a and id != link.b:
			continue
		var edge := String(link.a) + "--" + String(link.b)
		if covered_edges.has(edge):
			continue
		covered_edges[edge] = true
		var destination: String = link.b if id == link.a else link.a
		await _travel(id, destination)
		if not explored.has(destination):
			await _explore(destination)
		await _travel(destination, id)


func _travel(origin: String, destination: String, take_shot: bool = true) -> void:
	var link := _connection(origin, destination)
	_check(not link.is_empty(), "authored link " + origin + " -> " + destination)
	if link.is_empty():
		return
	var hp: int = level.player.health
	var sources := _source_ids()
	var origin_path: Array = level.rooms[origin].port_paths[destination].duplicate()
	var corridor: Array = link.path.duplicate()
	if origin != link.a:
		corridor.reverse()
	var destination_path: Array = level.rooms[destination].port_paths[origin].duplicate()
	destination_path.reverse()
	await _drive(level.rooms[origin].spawn)
	tracking = true
	last_player = level.player.global_position
	last_camera = level.player.presentation.camera.global_position
	for at: Vector3 in origin_path:
		await _drive(at)
	for i in corridor.size():
		await _drive(corridor[i])
		if take_shot and i == floori(corridor.size() * 0.5):
			await _shot("link-" + origin + "-" + destination)
	for at: Vector3 in destination_path:
		await _drive(at)
	tracking = false
	await _frames(4)
	_check(level.room_id == destination, "walk reaches " + destination + " without interaction")
	_check(level.player.get_instance_id() == player_id and level.geometry.get_instance_id() == geometry_id, "crossing keeps hero and world identities: " + destination)
	var stable := true
	for id: String in root_ids:
		stable = stable and is_instance_valid(level.room_roots[id]) and level.room_roots[id].get_instance_id() == root_ids[id]
		stable = stable and is_instance_valid(level.geometry.room_nodes[id]) and level.geometry.room_nodes[id].get_instance_id() == room_geometry_ids[id]
	_check(stable, "crossing does not rebuild any room: " + destination)
	_check(level.player.health <= hp, "crossing does not heal: " + destination)
	var sources_after := _source_ids()
	var sources_stable := true
	for source: int in sources:
		sources_stable = sources_stable and sources_after.has(source)
	_check(sources_stable, "crossing preserves unclaimed source identities: " + destination)


func _connection(a: String, b: String) -> Dictionary:
	for link: Dictionary in level.connections:
		if (link.a == a and link.b == b) or (link.a == b and link.b == a):
			return link
	return {}


func _navigate(destination: String) -> void:
	var start: String = level.room_id
	var queue: Array[String] = [start]
	var previous: Dictionary = {start: ""}
	while not queue.is_empty() and not previous.has(destination):
		var id := queue.pop_front() as String
		for link: Dictionary in level.connections:
			if id != link.a and id != link.b:
				continue
			var next: String = link.b if link.a == id else link.a
			if not previous.has(next):
				previous[next] = id
				queue.append(next)
	_check(previous.has(destination), "connected graph reaches final room")
	if not previous.has(destination):
		return
	var path: Array[String] = [destination]
	while path[-1] != start:
		path.append(previous[path[-1]])
	path.reverse()
	for i in range(1, path.size()):
		await _travel(path[i - 1], path[i], false)


func _fixture_clear(id: String) -> void:
	await _drive(level.rooms[id].spawn)
	for i in 650:
		if level.cleared.has(id):
			await _frames(35)
			_check(level.alive_enemies(id).is_empty(), "fixture clears all waves: " + id)
			return
		await _frames(1)
	_check(false, "fixture encounter failed to clear: " + id)


func _absorb(ability: StringName) -> void:
	var source: AbsorbSource
	for candidate in get_nodes_in_group(&"absorb_sources"):
		if candidate is AbsorbSource and candidate.ability_id == ability and not candidate.is_claimed():
			source = candidate
			break
	_check(is_instance_valid(source), "existing absorption source " + String(ability))
	if not is_instance_valid(source):
		return
	await _drive(source.global_position + Vector3(0, 0, 0.65))
	Input.action_press(&"interact")
	await _frames(45)
	Input.action_release(&"interact")
	await _frames(3)
	_check(level.player.has_learned(ability), "held E absorbs " + String(ability))


func _jump_camera() -> void:
	await _frames(25)
	var height: float = level.player.presentation.camera.global_position.y
	var deviation := 0.0
	Input.action_press(&"jump")
	await _frames(44)
	Input.action_release(&"jump")
	for i in 90:
		await _frames(1)
		deviation = maxf(deviation, absf(height - level.player.presentation.camera.global_position.y))
	_check(deviation < 0.02 and level.player.is_on_floor(), "charged jump lands without lifting camera")


func _camera_comparison() -> void:
	var positions: Array = level.rooms.entry.get("walk_points", [level.rooms.entry.spawn]).duplicate()
	for i in mini(3, positions.size()):
		await _drive(positions[i])
		await _frames(25)
		var following: Vector3 = level.get_meta(&"isometric_camera_center")
		level.set_physics_process(false)
		level.set_meta(&"isometric_camera_center", level.rooms.entry.center + Vector3.UP * 0.6)
		level.player.presentation._update_camera(0.0)
		await _shot("camera-%d-fixed" % i)
		level.set_meta(&"isometric_camera_center", following)
		level.player.presentation._update_camera(0.0)
		await _shot("camera-%d-follow" % i)
		var screen: Vector2 = level.player.presentation.camera.unproject_position(level.player.global_position + Vector3.UP * 0.5)
		_check(screen.y > 125 and screen.y < 560 and screen.x > 24 and screen.x < 1256, "world follow keeps hero clear of HUD at sample %d" % i)
		level.set_physics_process(true)
	await _drive(level.rooms.entry.spawn)


func _drive(at: Vector3) -> void:
	for i in 650:
		var offset: Vector3 = at - level.player.global_position
		offset.y = 0
		if offset.length() < 0.28:
			_release_motion()
			await _frames(8)
			return
		var axes: Vector2 = level.player.controls.world_direction_to_screen_axes(offset.normalized())
		Input.action_press(&"move_right", maxf(0, axes.x))
		Input.action_press(&"move_left", maxf(0, -axes.x))
		Input.action_press(&"move_back", maxf(0, axes.y))
		Input.action_press(&"move_forward", maxf(0, -axes.y))
		await _frames(1)
	_release_motion()
	_check(false, "walk blocked: target %s from %s in %s" % [at, level.player.global_position, level.room_id])
	if capture:
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png(OUT + "images/blocked-walk.png")
	_finish(1)


func _release_motion() -> void:
	for action in [&"move_right", &"move_left", &"move_back", &"move_forward"]:
		Input.action_release(action)


func _press_e() -> void:
	Input.action_release(&"interact")
	await _frames(3)
	Input.action_press(&"interact")
	await _frames(1)
	Input.action_release(&"interact")
	await _frames(8)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame
		if not is_instance_valid(level) or level != current_scene or paused:
			continue
		if fixture_hits:
			for enemy in level.alive_enemies():
				if enemy.is_alive():
					enemy.receive_hit(999, "seamless_fixture_%d" % cast_sequence, &"player")
					cast_sequence += 1
		if tracking:
			var camera_at: Vector3 = level.player.presentation.camera.global_position
			var player_at: Vector3 = level.player.global_position
			max_camera_step = maxf(max_camera_step, camera_at.distance_to(last_camera))
			max_player_step = maxf(max_player_step, player_at.distance_to(last_player))
			last_camera = camera_at
			last_player = player_at


func _source_ids(exclude_room: String = "") -> Dictionary:
	var result: Dictionary = {}
	for source in get_nodes_in_group(&"absorb_sources"):
		if source is AbsorbSource and not source.is_claimed():
			if exclude_room != "" and String(source.get_meta(&"home_room", "")) == exclude_room:
				continue
			result[source.get_instance_id()] = String(source.ability_id)
	return result


func _shot(label: String) -> void:
	if not capture:
		return
	await _frames(3)
	RenderingServer.force_draw()
	_check(root.get_texture().get_image().save_png(OUT + "images/" + label + ".png") == OK, "native capture " + label)


func _saves() -> Dictionary:
	var result: Dictionary = {}
	for path in ["user://checkpoint.json", "user://checkpoint.json.bak", "user://savegame.json"]:
		result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "ABSENT"
	return result


func _check(ok: bool, label: String) -> void:
	checks += 1
	failures += 0 if ok else 1
	print(("PASS " if ok else "FAIL ") + label)
	records.append({"pass": ok, "label": label})


func _finish(code: int) -> void:
	if completed:
		return
	completed = true
	_release_motion()
	Input.action_release(&"interact")
	Input.action_release(&"jump")
	FileAccess.open(OUT + ("native.json" if capture else "headless.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures, "records": records, "max_camera_step": max_camera_step, "max_player_step": max_player_step, "edges": covered_edges.keys(), "note": "Fixture hits validate traversal and persistence; no human duration or combat difficulty claim."}, "\t"))
	print("KEEPERS_WORLD_RESULT checks=%d failures=%d" % [checks, failures])
	quit(code)
