extends SceneTree

# S5 T20: repeatedly enter and restart each route room with an active projectile.
# Scene cleanup must dispose the old projectile and every old player/enemy node.

const PROJECTILE_SCENE = preload("res://scenes/abilities/spit_projectile.tscn")
const ROOMS := [
	{"id": "R01", "path": "res://scenes/r01_entrance.tscn", "stage": "", "enemies": 0},
	{"id": "R02", "path": "res://scenes/main.tscn", "stage": "first_fight", "enemies": 1},
	{"id": "R03", "path": "res://scenes/r03_armorer.tscn", "stage": "armorer", "enemies": 1},
	{"id": "R04", "path": "res://scenes/r04_core_trial.tscn", "stage": "core", "enemies": 0},
	{"id": "R05", "path": "res://scenes/r05_mixed.tscn", "stage": "mixed", "enemies": 3},
	{"id": "R06", "path": "res://scenes/r06_press.tscn", "stage": "r06", "enemies": 0},
	{"id": "R07", "path": "res://scenes/r07_guardian.tscn", "stage": "r07_fight", "enemies": 1},
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	set_meta(&"checkpoint_active", false)
	var all_passed := true
	for spec: Dictionary in ROOMS:
		var passed: bool = await _test_room(spec)
		all_passed = all_passed and passed
	print("PASS T20_ROUTE_MATRIX" if all_passed else "FAIL T20_ROUTE_MATRIX")
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _dispose_current_scene()
	quit(0 if all_passed else 1)


func _test_room(spec: Dictionary) -> bool:
	var scene_path: String = spec["path"]
	var room: Node3D = await _open_room(scene_path)
	if not is_instance_valid(room):
		print("FAIL T20_%s load" % spec["id"])
		return false
	var passed := _is_fresh(room, spec)
	for repeat in 10:
		if not passed:
			break
		var old_room: Node3D = room
		var old_player: SlimeController = room.get_node("SlimePlayer")
		var old_enemies: Array[Node] = get_nodes_in_group(&"enemies")
		var projectile := PROJECTILE_SCENE.instantiate() as SpitProjectile
		projectile.configure(old_player, &"enemy", Vector3.UP, 0.1, 5, 100.0, "t20_%s_%d" % [spec["id"], repeat])
		room.add_child(projectile)
		projectile.global_position = Vector3(0.0, 2.0, 0.0)
		await _steps(2)
		var attack_present: bool = get_nodes_in_group(&"enemy_projectiles").size() == 1 and is_instance_valid(projectile)
		if spec["id"] == "R01":
			reload_current_scene()
		else:
			room.call("_restart")
		var replaced := false
		for tick in 30:
			await physics_frame
			if is_instance_valid(current_scene) and current_scene != old_room and current_scene.scene_file_path == scene_path:
				replaced = true
				break
		if not replaced:
			print("FAIL T20_%s repeat=%d no replacement" % [spec["id"], repeat + 1])
			return false
		room = current_scene as Node3D
		await _steps(5)
		var old_disposed := not is_instance_valid(old_room) and not is_instance_valid(old_player) and not is_instance_valid(projectile)
		for enemy: Node in old_enemies:
			old_disposed = old_disposed and not is_instance_valid(enemy)
		var fresh: bool = _is_fresh(room, spec)
		passed = attack_present and old_disposed and fresh
		print("T20_%s repeat=%d attack=%s disposed=%s fresh=%s" % [spec["id"], repeat + 1, attack_present, old_disposed, fresh])
	print("PASS T20_%s" % spec["id"] if passed else "FAIL T20_%s" % spec["id"])
	return passed


func _is_fresh(room: Node3D, spec: Dictionary) -> bool:
	if not is_instance_valid(room) or not room.has_node("SlimePlayer"):
		return false
	var player: SlimeController = room.get_node("SlimePlayer")
	var clean: bool = not paused and player.health == player.MAX_HEALTH
	clean = clean and get_nodes_in_group(&"enemies").size() == int(spec["enemies"])
	clean = clean and get_nodes_in_group(&"enemy_projectiles").is_empty() and get_nodes_in_group(&"enemy_attacks").is_empty()
	clean = clean and get_nodes_in_group(&"projectiles").is_empty()
	var expected_signals := 0 if spec["id"] == "R01" else 1
	clean = clean and player.projectile_requested.get_connections().size() == expected_signals
	clean = clean and player.died.get_connections().size() == expected_signals
	if spec["stage"] != "":
		clean = clean and String(room.get("stage")) == spec["stage"]
	if spec["id"] == "R04":
		clean = clean and is_instance_valid(room.get("_core")) and is_zero_approx(float(room.get("_core_hold")))
	elif spec["id"] == "R06":
		clean = clean and room.has_node("StickyMechanism") and String(room.get("press_phase")) == "warning" and is_zero_approx(float(room.get("sticky_open_left")))
	elif spec["id"] == "R07":
		clean = clean and room.has_node("ExitGuardian") and room.get_node("ExitGate").collision_layer != 0
	return clean


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
