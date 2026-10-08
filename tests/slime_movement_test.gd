extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player/slime_player.tscn")
const INPUT_SETUP := preload("res://scripts/input_setup.gd")

var _failed := 0
var _watchdog: Timer


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	INPUT_SETUP.install()
	_watchdog = Timer.new()
	_watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	_watchdog.one_shot = true
	_watchdog.wait_time = 90.0
	root.add_child(_watchdog)
	_watchdog.timeout.connect(_on_timeout)
	_watchdog.start()
	_report("M01_LOW_PASSAGE", await _test_low_passage())
	_report("M02_CHARGED_JUMP", await _test_jump_heights())
	_report("M03_AIR_REPRESS", await _test_no_air_charge())
	_report("M04_PAUSE_RESET", await _test_pause_charge_reset())
	_release_actions()
	_watchdog.stop()
	_watchdog.free()
	print("SUMMARY: %d failed" % _failed)
	quit(1 if _failed > 0 else 0)


func _on_timeout() -> void:
	print("FAIL TIMEOUT: movement test exceeded 90 seconds")
	_release_actions()
	quit(124)


func _report(test_id: String, problem: String) -> void:
	if problem.is_empty():
		print("PASS %s" % test_id)
	else:
		_failed += 1
		print("FAIL %s: %s" % [test_id, problem])


func _test_low_passage() -> String:
	_release_actions()
	var fixture := _make_floor_fixture(Vector3(0.0, 0.05, 1.0), true)
	var player := fixture.get_node("SlimePlayer") as SlimeController
	_add_static_box(fixture, "LowCeiling", Vector3(0.0, 0.66, -4.0), Vector3(1.6, 0.20, 3.5))
	var area := Area3D.new()
	area.name = "LowPassageArea"
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitoring = true
	area.position = Vector3(0.0, 0.55, -4.0)
	var trigger_shape := CollisionShape3D.new()
	var trigger_box := BoxShape3D.new()
	trigger_box.size = Vector3(2.4, 1.1, 5.5)
	trigger_shape.shape = trigger_box
	area.add_child(trigger_shape)
	fixture.add_child(area)
	area.body_entered.connect(_on_passage_enter.bind(player, area))
	area.body_exited.connect(_on_passage_exit.bind(player, area))
	await _physics_steps(5)
	var initially_normal := player.is_on_floor() and not player.is_compressed()
	var body_collision := player.get_node("CollisionShape3D") as CollisionShape3D
	var standing_top := body_collision.position.y + (body_collision.shape as CapsuleShape3D).height * 0.5
	var rest_camera := player.presentation.camera.global_transform
	Input.action_press(&"move_forward")
	Input.action_press(&"move_right")
	var entry_ticks := 0
	while player.global_position.z > -4.5 and entry_ticks < 140:
		await _physics_steps(1)
		entry_ticks += 1
	Input.action_release(&"move_forward")
	Input.action_release(&"move_right")
	await _physics_steps(8)
	var inside_z := player.global_position.z
	var through_roof := inside_z < -4.5 and player.is_on_floor()
	var compressed_inside := player.is_compressed()
	var compressed_top := body_collision.position.y + (body_collision.shape as CapsuleShape3D).height * 0.5
	var compressed_camera := player.presentation.camera.global_transform
	# Simulate a zone leaving early while the body is still below the solid roof:
	# the standing collider must stay compressed until it has physical clearance.
	player.set_low_passage_active(area, false)
	await _physics_steps(6)
	var blocked_standup := player.is_compressed()
	var blocked_top := body_collision.position.y + (body_collision.shape as CapsuleShape3D).height * 0.5
	Input.action_press(&"jump")
	await _physics_steps(48)
	var blocked_charge := player.get_jump_charge_ratio()
	Input.action_release(&"jump")
	await _physics_steps(1)
	var blocked_jump := player.is_compressed() and player.is_on_floor() and player.velocity.y < 0.5
	Input.action_press(&"move_forward")
	Input.action_press(&"move_right")
	var exit_ticks := 0
	while player.global_position.z > -7.5 and exit_ticks < 90:
		await _physics_steps(1)
		exit_ticks += 1
	Input.action_release(&"move_forward")
	Input.action_release(&"move_right")
	await _physics_steps(20)
	var beyond_roof := player.global_position.z < -7.5 and player.is_on_floor()
	var restored := not player.is_compressed()
	var restored_top := body_collision.position.y + (body_collision.shape as CapsuleShape3D).height * 0.5
	var restored_camera := player.presentation.camera.global_transform
	Input.action_press(&"jump")
	await _physics_steps(1)
	Input.action_release(&"jump")
	await _physics_steps(1)
	var jump_after_exit := player.velocity.y
	print("M01 tunnel: height %.3f -> %.3f -> %.3f, z %.3f -> %.3f; camera stable inside=%s after=%s; under roof charge=%.2f jump=%s, exit vy=%.3f" % [standing_top, compressed_top, restored_top, inside_z, player.global_position.z, str(compressed_camera.is_equal_approx(rest_camera)), str(restored_camera.is_equal_approx(rest_camera)), blocked_charge, str(blocked_jump), jump_after_exit])
	await _discard_fixture(fixture)
	if not initially_normal or standing_top < 0.76:
		return "player did not start standing on physical floor"
	if not through_roof or not compressed_inside or compressed_top >= 0.56:
		return "automatic compression did not let physical body traverse the 0.56 m tunnel"
	if not blocked_standup or blocked_top >= 0.56:
		return "player expanded into the solid ceiling after zone exit"
	if blocked_charge > 0.05 or not blocked_jump:
		return "jump charged or launched while compressed below the roof"
	if not beyond_roof or not restored or restored_top < 0.76:
		return "normal collision height did not return after clearing the roof"
	if not compressed_camera.is_equal_approx(rest_camera):
		return "compression moved or rotated the independent room camera"
	if not restored_camera.is_equal_approx(rest_camera):
		return "standing up changed the independent room camera"
	if jump_after_exit < 5.0:
		return "ordinary jump did not return after leaving the passage"
	return ""

func _test_jump_heights() -> String:
	var quick: Dictionary = await _jump_trial(1)
	var charged: Dictionary = await _jump_trial(48)
	var capped: Dictionary = await _jump_trial(90)
	print("M02 jumps: quick apex=%.3f vy=%.3f, charged apex=%.3f vy=%.3f ratio=%.2f, capped apex=%.3f ratio=%.2f" % [quick["apex"], quick["first_vy"], charged["apex"], charged["first_vy"], charged["ratio"], capped["apex"], capped["ratio"]])
	if not quick["grounded"] or not quick["landed"] or quick["first_vy"] < 5.0:
		return "quick tap did not perform the ordinary physical jump and land"
	if not charged["grounded"] or not charged["landed"] or charged["ratio"] < 0.90:
		return "held jump did not charge on the ground or return to floor"
	if charged["apex"] < quick["apex"] + 0.35 or charged["first_vy"] < quick["first_vy"] + 1.2:
		return "held jump did not rise substantially higher than a quick tap"
	if capped["ratio"] < 0.99 or capped["apex"] > charged["apex"] + 0.12:
		return "charge did not cap after the full hold"
	return ""


func _jump_trial(hold_ticks: int) -> Dictionary:
	_release_actions()
	var fixture := _make_floor_fixture(Vector3(0.0, 0.05, 0.0))
	var player := fixture.get_node("SlimePlayer") as SlimeController
	await _physics_steps(5)
	var grounded := player.is_on_floor()
	var start_y := player.global_position.y
	Input.action_press(&"jump")
	await _physics_steps(hold_ticks)
	var ratio := player.get_jump_charge_ratio()
	Input.action_release(&"jump")
	await _physics_steps(1)
	var first_vy := player.velocity.y
	var apex := player.global_position.y - start_y
	for tick in range(90):
		await _physics_steps(1)
		apex = maxf(apex, player.global_position.y - start_y)
	var landed := player.is_on_floor()
	await _discard_fixture(fixture)
	return {"grounded": grounded, "landed": landed, "ratio": ratio, "first_vy": first_vy, "apex": apex}


func _test_no_air_charge() -> String:
	_release_actions()
	var fixture := _make_floor_fixture(Vector3(0.0, 0.05, 0.0))
	var player := fixture.get_node("SlimePlayer") as SlimeController
	await _physics_steps(5)
	Input.action_press(&"jump")
	await _physics_steps(48)
	Input.action_release(&"jump")
	await _physics_steps(6)
	var airborne_before := not player.is_on_floor() and player.velocity.y > 0.0
	Input.action_press(&"jump")
	await _physics_steps(20)
	var air_ratio := player.get_jump_charge_ratio()
	var velocity_before_release := player.velocity.y
	Input.action_release(&"jump")
	await _physics_steps(1)
	var velocity_after_release := player.velocity.y
	var still_airborne := not player.is_on_floor()
	await _physics_steps(75)
	var landed := player.is_on_floor()
	print("M03 air input: airborne=%s/%s ratio=%.2f vy %.3f -> %.3f landed=%s" % [str(airborne_before), str(still_airborne), air_ratio, velocity_before_release, velocity_after_release, str(landed)])
	await _discard_fixture(fixture)
	if not airborne_before or not still_airborne:
		return "airborne repeat fixture did not remain in the air"
	if air_ratio > 0.05 or velocity_after_release > velocity_before_release + 0.5:
		return "airborne hold charged or produced a second jump"
	if not landed:
		return "player did not land after airborne input"
	return ""


func _test_pause_charge_reset() -> String:
	_release_actions()
	var fixture := _make_floor_fixture(Vector3(0.0, 0.05, 0.0))
	var player := fixture.get_node("SlimePlayer") as SlimeController
	await _physics_steps(5)
	Input.action_press(&"jump")
	await _physics_steps(30)
	var charge_before_pause := player.get_jump_charge_ratio()
	var grounded_before_pause := player.is_on_floor()
	# Match gameplay pause order: clear the buffered action before pausing the tree.
	player.clear_action_buffer()
	paused = true
	await create_timer(0.12, true, false).timeout
	var paused_charge := player.get_jump_charge_ratio()
	var paused_grounded := player.is_on_floor()
	paused = false
	await _physics_steps(4)
	var resumed_charge := player.get_jump_charge_ratio()
	Input.action_release(&"jump")
	await _physics_steps(2)
	var delayed_jump := not player.is_on_floor() or player.velocity.y > 0.5
	Input.action_press(&"jump")
	await _physics_steps(1)
	Input.action_release(&"jump")
	await _physics_steps(1)
	var fresh_jump_velocity := player.velocity.y
	print("M04 pause: charge before=%.2f during=%.2f resumed=%.2f grounded=%s/%s delayed=%s fresh vy=%.3f" % [charge_before_pause, paused_charge, resumed_charge, str(grounded_before_pause), str(paused_grounded), str(delayed_jump), fresh_jump_velocity])
	await _discard_fixture(fixture)
	if not grounded_before_pause or charge_before_pause < 0.4:
		return "pause fixture did not reach a grounded charge"
	if paused_charge > 0.01 or not paused_grounded or resumed_charge > 0.01 or delayed_jump:
		return "cleared charge resumed or launched after unpausing and releasing jump"
	if fresh_jump_velocity < 5.0:
		return "a fresh press and release did not jump after pause"
	return ""

func _on_passage_enter(body: Node3D, player: SlimeController, area: Area3D) -> void:
	if body == player:
		player.set_low_passage_active(area, true)


func _on_passage_exit(body: Node3D, player: SlimeController, area: Area3D) -> void:
	if body == player:
		player.set_low_passage_active(area, false)


func _make_floor_fixture(spawn: Vector3, fixed_camera: bool = false) -> Node3D:
	var fixture := Node3D.new()
	fixture.name = "MovementFixture"
	if fixed_camera:
		fixture.set_meta(&"isometric_camera_center", Vector3(0.0, 0.45, -3.0))
	_add_static_box(fixture, "Floor", Vector3(0.0, -0.2, -3.0), Vector3(10.0, 0.4, 20.0))
	var player := PLAYER_SCENE.instantiate() as SlimeController
	player.name = "SlimePlayer"
	player.position = spawn
	fixture.add_child(player)
	root.add_child(fixture)
	return fixture


func _add_static_box(parent: Node3D, name: String, center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	parent.add_child(body)
	return body


func _discard_fixture(fixture: Node) -> void:
	_release_actions()
	fixture.queue_free()
	await _physics_steps(2)


func _release_actions() -> void:
	for action in [&"jump", &"move_forward", &"move_back", &"move_left", &"move_right"]:
		Input.action_release(action)


func _physics_steps(count: int) -> void:
	for tick in range(count):
		await physics_frame
		await process_frame
