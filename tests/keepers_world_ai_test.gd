extends SceneTree

# Isolated AI movement fixtures in the real connected geometry. Initial actor
# placement is intentional; after each probe starts, only real enemy physics
# moves it. This is separate from the no-fixture combat/pacing autoplay.
const WORLD := "res://scenes/keepers/keepers_world.tscn"
const OUT := "res://output/keepers_seamless_2026_10_08/"
const SPITTER_SCENE = preload("res://scenes/enemies/spitter.tscn")
const SPROUT_SCENE = preload("res://scenes/enemies/stone_sprout.tscn")
const WORLD_SPITTER = preload("res://scripts/keepers/keepers_world_spitter.gd")
const WORLD_ENEMY = preload("res://scripts/keepers/keepers_world_enemy.gd")
const WORLD_GUARDIAN = preload("res://scripts/keepers/keepers_world_guardian.gd")
const PLAYER_SCENE = preload("res://scenes/player/slime_player.tscn")

var level: SlimeKeepersWorld
var records: Array[Dictionary] = []
var probes: Array[Dictionary] = []
var failures := 0
var capture := false
var completed := false
var isolated_probes: Array[Dictionary] = []


func _initialize() -> void:
	capture = OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless"
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "ai_images"))
	SlimeGameSettings.current().load_settings(OUT + "ai_settings.cfg")
	var watchdog := Timer.new()
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.one_shot = true
	watchdog.wait_time = 180.0
	root.add_child(watchdog)
	watchdog.timeout.connect(func() -> void:
		_check(false, "AI fixture watchdog exceeded 180 seconds")
		_finish(124))
	watchdog.start()
	if change_scene_to_file(WORLD) != OK:
		_check(false, "Cannot open connected world")
		_finish(1)
		return
	await _frames(12)
	level = current_scene as SlimeKeepersWorld
	if not is_instance_valid(level):
		_check(false, "Connected runtime missing")
		_finish(1)
		return
	for unused in 120:
		if not level._transitioning:
			break
		await _frames(1)
	_check(not level._transitioning, "World and physical navigation finished building")
	_check(int(level.navigation.build_stats.get("edges", 0)) > 0, "Verified graph contains links")
	_check(level.navigation.build_stats.get("isolated_points", []).is_empty(), "Authored graph has no falsely unsupported isolated points")
	_inspect_isolated()
	# Stop only encounter scheduling, room changes and far-distance sleep. The
	# test enemy, navigation, player, physics and actual attacks keep processing.
	level.set_physics_process(false)
	_release_input()
	await _translated_retreat()
	await _blocked_approach("hub", "spitter", Vector3(-2.8, 0, 0), Vector3(2.8, 0, 0), 6.5)
	await _blocked_approach("gauntlet", "sprout", Vector3(-1.9, 0, 0), Vector3(1.9, 0, 0), 4.0)
	await _cistern_detour()
	await _guardian_ramp()
	_check(level.player.is_alive(), "Stationary target survived without test healing or invulnerability")
	_finish(0 if failures == 0 else 1)


func _translated_retreat() -> void:
	var center: Vector3 = level.rooms.entry.center
	_prepare_target("entry", center + Vector3(0, 0, 2))
	var enemy := _spawn("spitter", "entry", center) as SlimeKeepersWorldSpitter
	await _frames(3)
	_check(absf(enemy.global_position.z) > 8.8, "Retreat fixture lies outside legacy origin bounds")
	_check(enemy._can_retreat(Vector3.FORWARD), "Translated floor allows capsule retreat")
	enemy.global_position = center + Vector3(2.9, 0.04, 0)
	await _frames(2)
	_check(not enemy._can_retreat(Vector3.RIGHT), "Retreat refuses unsupported capsule footprint at outer edge")
	enemy.global_position = center + Vector3.UP * 0.04
	enemy.velocity = Vector3.ZERO
	var start := enemy.global_position
	enemy.set_physics_process(true)
	var row := await _measure(enemy, "translated-retreat", 150, func(actor: CharacterBody3D) -> bool:
		return actor.global_position.distance_to(start) > 0.65 and actor.global_position.distance_to(level.player.global_position) > 2.6)
	_check(bool(row.reached), "Spitter physically retreats in translated room")
	_check(float(row.min_y) > -0.15, "Translated retreat keeps floor support")
	await _shot("translated-retreat")
	await _remove_probe(enemy)


func _blocked_approach(room: String, kind: String, local_start: Vector3, local_target: Vector3, stop_range: float) -> void:
	var center: Vector3 = level.rooms[room].center
	_prepare_target(room, center + local_target)
	var enemy := _spawn(kind, room, center + local_start)
	await _frames(3)
	var start := enemy.global_position
	var initial_distance := _flat_distance(start, level.player.global_position)
	_check(initial_distance < stop_range, "%s fixture is inside inherited stop range" % kind)
	_check(not bool(enemy.call("_has_line_of_sight")), "%s starts behind a real collider" % kind)
	var planned: PackedVector3Array = level.navigation.path_between(start, level.player.global_position, 0.56)
	_check(not planned.is_empty(), "%s has a verified route around the obstacle" % kind)
	enemy.set_physics_process(true)
	var label := room + "-" + kind + "-blocked-approach"
	var row := await _measure(enemy, label, 1200, func(actor: CharacterBody3D) -> bool:
		return actor.global_position.distance_to(start) > 1.0 and bool(actor.call("_has_line_of_sight")))
	_check(bool(row.reached), "%s physically rounds obstacle and reacquires sight" % kind)
	_check(float(row.distance_m) > 1.0 and float(row.max_z_deviation) > 0.7, "%s used a lateral physical detour" % kind)
	_check(float(row.min_y) > center.y - 0.15, "%s kept floor support during detour" % kind)
	await _shot(label)
	await _remove_probe(enemy)


func _cistern_detour() -> void:
	var center: Vector3 = level.rooms.cistern.center
	_prepare_target("cistern", center + Vector3(4.5, 0, 0))
	var enemy := _spawn("spitter", "cistern", center + Vector3(-4.5, 0, 0))
	await _frames(3)
	_check(not level.navigation.can_travel(enemy.global_position, level.player.global_position, 0.52), "Direct cistern crossing has no continuous walking support")
	enemy.set_physics_process(true)
	var row := await _measure(enemy, "cistern-detour", 1500, func(actor: CharacterBody3D) -> bool:
		return actor.global_position.x > center.x - 2.0 and absf(actor.global_position.z - center.z) > 2.9 and _flat_distance(actor.global_position, level.player.global_position) <= 6.6)
	# A ranged enemy correctly stops at its unchanged engagement distance;
	# crossing all the way to the player's bank is not required by its AI.
	_check(bool(row.reached), "Spitter reaches normal attack range via the basin detour")
	_check(float(row.min_y) > -0.15 and float(row.max_z_deviation) > 2.9, "Basin detour stays on upper floor and goes around the rim")
	await _shot("cistern-detour")
	await _remove_probe(enemy)


func _guardian_ramp() -> void:
	var center: Vector3 = level.rooms.summit.center
	_prepare_target("summit", center + Vector3(0, 1, -6.4))
	var enemy := _spawn("guardian", "summit", center + Vector3(0, 0, 4))
	await _frames(3)
	var route: PackedVector3Array = level.navigation.path_between(enemy.global_position, level.player.global_position, 0.86)
	_check(not route.is_empty(), "Guardian-width route reaches the upper terrace")
	enemy.set_physics_process(true)
	var row := await _measure(enemy, "guardian-ramp", 1500, func(actor: CharacterBody3D) -> bool:
		return actor.global_position.y > 0.93 and actor.global_position.z < center.z - 2.8 and actor.is_on_floor())
	_check(bool(row.reached), "Guardian physically climbs the authored ramp onto terrace")
	_check(float(row.max_y) > 0.93 and float(row.min_y) > -0.15, "Guardian ascent has continuous vertical support")
	await _shot("guardian-ramp")
	await _remove_probe(enemy)


func _prepare_target(room: String, at: Vector3) -> void:
	_release_input()
	# Independent fixture actor, like starting a fresh isolated scenario.
	# Never heal or modify health while an AI probe is running.
	level.player.free()
	level.player = PLAYER_SCENE.instantiate() as SlimeController
	level.player.name = "SlimePlayer"
	level.add_child(level.player)
	level.combat.player = null
	level.combat.bind_player(level.player)
	level._bind_player()
	level.hud.rebind_runtime()
	level.player.presentation.room_cutaway = level.geometry.cutaway
	level.room_id = room
	level.player.global_position = at + Vector3.UP * 0.04
	level.player.velocity = Vector3.ZERO
	level._ground_y = at.y
	level._update_camera_center()
	level._update_visibility()
	level.player.presentation._update_camera(0.0)


func _spawn(kind: String, room: String, at: Vector3) -> CharacterBody3D:
	var actor: CharacterBody3D
	if kind == "guardian":
		actor = WORLD_GUARDIAN.new()
	elif kind == "spitter":
		actor = SPITTER_SCENE.instantiate()
		actor.set_script(WORLD_SPITTER)
	else:
		actor = SPROUT_SCENE.instantiate()
		actor.set_script(WORLD_ENEMY)
		actor.set("kind", kind)
	actor.set("movement_guide", level.navigation.steer)
	actor.set_meta(&"home_room", room)
	actor.set_physics_process(false)
	level.room_roots[room].add_child(actor)
	actor.global_position = at + Vector3.UP * 0.04
	level.combat.bind_enemy(actor)
	return actor


func _measure(actor: CharacterBody3D, label: String, limit: int, reached: Callable) -> Dictionary:
	var initial := actor.global_position
	var previous := initial
	var row := {"probe": label, "start": _v3(initial), "reached": false, "frames": 0, "distance_m": 0.0, "max_step": 0.0, "min_y": initial.y, "max_y": initial.y, "max_z_deviation": 0.0, "samples": []}
	for index in limit:
		await _frames(1)
		if completed or not is_instance_valid(actor) or not level.player.is_alive():
			break
		var at := actor.global_position
		var step := at.distance_to(previous)
		row.distance_m = float(row.distance_m) + step
		row.max_step = maxf(float(row.max_step), step)
		row.min_y = minf(float(row.min_y), at.y)
		row.max_y = maxf(float(row.max_y), at.y)
		row.max_z_deviation = maxf(float(row.max_z_deviation), absf(at.z - initial.z))
		row.frames = index + 1
		if index % 15 == 0:
			row.samples.append({"frame": index, "at": _v3(at), "grounded": actor.is_on_floor(), "phase": String(actor.call("get_attack_phase"))})
		previous = at
		if index > 5 and bool(reached.call(actor)):
			row.reached = true
			break
	row.end = _v3(actor.global_position) if is_instance_valid(actor) else []
	row.elapsed_physics_seconds = float(row.frames) / float(Engine.physics_ticks_per_second)
	row.player_health = level.player.health
	probes.append(row)
	_check(float(row.max_step) < 0.22, label + " advances continuously without actor teleport")
	print("AI_PROBE %s reached=%s frames=%d distance=%.2f" % [label, row.reached, row.frames, row.distance_m])
	return row


func _remove_probe(actor: CharacterBody3D) -> void:
	for child: Node in level.combat.get_children():
		if (child is SpitProjectile or child is SpikeLine) and child.get("owner_body") == actor:
			child.queue_free()
	actor.queue_free()
	await _frames(3)


func _frames(count: int) -> void:
	for unused in count:
		await physics_frame
		await process_frame
		if is_instance_valid(level) and paused and not level.finished:
			level._resume_game()


func _release_input() -> void:
	for action in [&"move_right", &"move_left", &"move_back", &"move_forward", &"jump", &"interact", &"attack_primary", &"ability_slot_1", &"ability_slot_2"]:
		Input.action_release(action)


func _inspect_isolated() -> void:
	for at: Vector3 in level.navigation.build_stats.get("isolated_points", []):
		var row := {"point": _v3(at), "ground_probes": []}
		for offset: Vector3 in [Vector3.ZERO, Vector3(0.003,0,0), Vector3(-0.003,0,0), Vector3(0,0,0.003), Vector3(0,0,-0.003)]:
			var query := PhysicsRayQueryParameters3D.create(at + offset + Vector3.UP * 0.8, at + offset + Vector3.DOWN * 3.5, 1)
			var hit := level.get_world_3d().direct_space_state.intersect_ray(query)
			row.ground_probes.append({"offset": _v3(offset), "hit": not hit.is_empty(), "position": _v3(hit.position) if not hit.is_empty() else [], "normal": _v3(hit.normal) if not hit.is_empty() else [], "collider": String(hit.collider.name) if not hit.is_empty() else ""})
		isolated_probes.append(row)


func _shot(label: String) -> void:
	if not capture:
		return
	RenderingServer.force_draw()
	_check(root.get_texture().get_image().save_png(OUT + "ai_images/" + label + ".png") == OK, "Native AI capture " + label)


func _check(passed: bool, label: String) -> void:
	records.append({"pass": passed, "label": label})
	if not passed:
		failures += 1
	print(("PASS " if passed else "FAIL ") + label)


func _finish(code: int) -> void:
	if completed:
		return
	completed = true
	_release_input()
	var report := {"status": "PASS" if code == 0 else ("TIMEOUT" if code == 124 else "FAIL"), "checks": records, "failures": failures, "probes": probes, "capture": capture, "scope": "Physical AI navigation fixtures; independent default player per probe; initial positions assigned, then actual AI physics; not combat difficulty or human pacing", "player_health_modified_by_test": false, "enemy_health_modified_by_test": false, "graph": level.navigation.build_stats if is_instance_valid(level) else {}, "isolated_point_diagnostics": isolated_probes}
	var file := FileAccess.open(OUT + "ai.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	else:
		printerr("FAIL cannot write AI report")
		code = 2
	print("KEEPERS_WORLD_AI_%s checks=%d failures=%d" % [report.status, records.size(), failures])
	quit(code)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _v3(at: Vector3) -> Array:
	return [at.x, at.y, at.z]
