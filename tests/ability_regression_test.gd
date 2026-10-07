extends SceneTree

const PLAYER_SCENE = preload("res://scenes/player/slime_player.tscn")
const SPROUT_SCENE = preload("res://scenes/enemies/stone_sprout.tscn")
const INPUT_SETUP = preload("res://scripts/input_setup.gd")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	INPUT_SETUP.install()
	_report("T10", await _test_t10())
	_report("T11", await _test_t11())
	_report("T12", await _test_t12())
	_report("T13", await _test_t13())
	_report("T14", await _test_t14())
	_report("T15", await _test_t15())
	print("ABILITIES_RESULT failures=%d" % _failures)
	quit(0 if _failures == 0 else 1)


func _report(test_id: String, problem: String) -> void:
	if problem.is_empty():
		print("PASS %s" % test_id)
	else:
		_failures += 1
		print("FAIL %s: %s" % [test_id, problem])


func _fixture() -> Node3D:
	var fixture := Node3D.new()
	fixture.name = "S4Fixture"
	root.add_child(fixture)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(18.0, 0.4, 18.0)
	floor_shape.shape = box
	floor_body.position.y = -0.2
	floor_body.add_child(floor_shape)
	fixture.add_child(floor_body)
	var player := PLAYER_SCENE.instantiate() as SlimeController
	player.name = "SlimePlayer"
	player.position = Vector3(0.0, 0.05, 0.0)
	fixture.add_child(player)
	return fixture


func _add_sprout(fixture: Node3D, at: Vector3) -> BorrowableEnemy:
	var enemy := SPROUT_SCENE.instantiate() as BorrowableEnemy
	enemy.position = at
	fixture.add_child(enemy)
	return enemy


func _spikes(fixture: Node3D, owner_body: CollisionObject3D, team: StringName, origin: Vector3, direction: Vector3, cast_key: String, damage: int) -> SpikeLine:
	var line := SpikeLine.new()
	line.configure(owner_body, team, origin, direction, cast_key, damage)
	fixture.add_child(line)
	return line


func _steps(count: int) -> void:
	for tick in count:
		await physics_frame


func _discard(fixture: Node3D) -> void:
	paused = false
	Input.action_release(&"interact")
	fixture.queue_free()
	await _steps(3)


func _test_t10() -> String:
	var fixture := _fixture()
	var player := fixture.get_node("SlimePlayer") as SlimeController
	await _steps(3)
	var first := player.grant_ability(&"sticky_spit")
	var second := player.grant_ability(&"elastic_shell")
	var third := player.grant_ability(&"slime_spikes")
	var duplicate := player.grant_ability(&"elastic_shell")
	var before := player.unlocked_slots == 1 and player.equipped_ability == &"sticky_spit" and player.second_slot_ability == &"" and player.learned_abilities.size() == 3
	var core := player.unlock_second_slot()
	var duplicate_core := player.unlock_second_slot()
	var after := player.unlocked_slots == 2 and player.second_slot_ability == &"slime_spikes" or player.second_slot_ability == &"elastic_shell"
	var no_duplicate_slots := not player.equip_ability(2, &"sticky_spit")
	await _discard(fixture)
	if not first or not second or not third or duplicate or not before or not core or duplicate_core or not after or not no_duplicate_slots:
		return "collection, first empty slot, duplicate, or one-time core contract failed"
	return ""


func _test_t11() -> String:
	var fixture := _fixture()
	var player := fixture.get_node("SlimePlayer") as SlimeController
	await _steps(3)
	player.grant_ability(&"sticky_spit")
	player.unlock_second_slot()
	var started := player.request_action(&"sticky_spit")
	await _steps(13)
	var before := player.cooldown_remaining(&"sticky_spit")
	var unequipped := player.equip_ability(1, &"")
	await _steps(20)
	var while_unequipped := player.cooldown_remaining(&"sticky_spit")
	var moved := player.equip_ability(2, &"sticky_spit")
	var after := player.cooldown_remaining(&"sticky_spit")
	await _discard(fixture)
	if not started or before <= 0.0 or not unequipped or not moved or while_unequipped <= 0.0 or after >= before or absf(after - while_unequipped) > 0.05:
		return "cooldown reset or stopped when sticky_spit moved between slots"
	return ""


func _test_t12() -> String:
	var fixture := _fixture()
	var player := fixture.get_node("SlimePlayer") as SlimeController
	var enemy := _add_sprout(fixture, Vector3(0.0, 0.05, -2.0))
	await _steps(3)
	enemy.apply_sticky(0.55, 1.0)
	await _steps(15)
	var first_left := enemy.get_sticky_time_left()
	enemy.apply_sticky(0.55, 3.0)
	var refreshed := enemy.get_sticky_time_left() > first_left and is_equal_approx(enemy.current_move_speed(), 0.88)
	var line := _spikes(fixture, player, &"player", player.global_position, Vector3.FORWARD, "combo_once", 22)
	var damaged_once := enemy.health == 17 and enemy.get_sticky_time_left() == 0.0
	var repeat_segments := line.build_line()
	var still_once := enemy.health == 17 and repeat_segments == 5
	await _discard(fixture)
	fixture = _fixture()
	player = fixture.get_node("SlimePlayer") as SlimeController
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.position = Vector3(0.0, 0.8, -2.5)
	var collider := CollisionShape3D.new()
	var block := BoxShape3D.new()
	block.size = Vector3(1.4, 1.6, 0.3)
	collider.shape = block
	wall.add_child(collider)
	fixture.add_child(wall)
	await _steps(3)
	line = _spikes(fixture, player, &"player", player.global_position, Vector3.FORWARD, "wall_stop", 22)
	var stopped_at_wall := line.build_line() == 2
	await _discard(fixture)
	if not refreshed or not damaged_once or not still_once or not stopped_at_wall:
		return "sticky refresh, 33-damage combo, consumption, or unique-target hit failed"
	return ""


func _test_t13() -> String:
	var fixture := _fixture()
	var player := fixture.get_node("SlimePlayer") as SlimeController
	await _steps(3)
	player.grant_ability(&"elastic_shell")
	var weak_started := player.request_action(&"elastic_shell")
	await _steps(7)
	var guard_active: bool = player.get("_phase") == &"guard"
	var weak_hit := player.receive_hit(18, "weak", &"enemy")
	var weak_hp := player.health
	var consumed: bool = player.get("_phase") == &"recovery"
	var next_hit := player.receive_hit(35, "after_weak", &"enemy")
	var after_weak_hp := player.health
	await _discard(fixture)
	fixture = _fixture()
	player = fixture.get_node("SlimePlayer") as SlimeController
	await _steps(3)
	player.grant_ability(&"elastic_shell")
	var strong_started := player.request_action(&"elastic_shell")
	await _steps(7)
	var strong_hit := player.receive_hit(35, "strong", &"enemy")
	var strong_hp := player.health
	await _discard(fixture)
	if not weak_started or not guard_active or not weak_hit or weak_hp != 100 or not consumed or not next_hit or after_weak_hp != 65 or not strong_started or not strong_hit or strong_hp != 90:
		return "one-hit shell did not absorb 18/25 or pass 10 of 35"
	return ""


func _test_t14() -> String:
	var fixture := _fixture()
	var player := fixture.get_node("SlimePlayer") as SlimeController
	player.position.z = -2.0
	var owner_body := StaticBody3D.new()
	fixture.add_child(owner_body)
	await _steps(3)
	_spikes(fixture, owner_body, &"enemy", owner_body.global_position, Vector3.FORWARD, "ground", 14)
	var ground_hp := player.health
	await _discard(fixture)
	fixture = _fixture()
	player = fixture.get_node("SlimePlayer") as SlimeController
	player.position = Vector3(0.0, 1.0, -2.0)
	owner_body = StaticBody3D.new()
	fixture.add_child(owner_body)
	await _steps(1)
	_spikes(fixture, owner_body, &"enemy", owner_body.global_position, Vector3.FORWARD, "jumped", 14)
	var airborne_hp := player.health
	await _discard(fixture)
	if ground_hp != 86 or airborne_hp != 100:
		return "low spike hit did not use actual hurtbox bottom: ground=%d air=%d" % [ground_hp, airborne_hp]
	return ""


func _test_t15() -> String:
	var fixture := preload("res://tests/helpers/combat_fixture.tscn").instantiate()
	root.add_child(fixture)
	await _steps(3)
	var player: SlimeController = fixture.player
	player.grant_ability(&"elastic_shell")
	player.request_action(&"elastic_shell")
	await _steps(7)
	var guard_before: StringName = player.get("_phase")
	var cooldown_before := player.cooldown_remaining(&"elastic_shell")
	fixture._pause_game()
	await _steps(60)
	var frozen: bool = player.get("_phase") == guard_before and is_equal_approx(player.cooldown_remaining(&"elastic_shell"), cooldown_before)
	fixture._pause_panel._open_settings()
	fixture.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var still_paused := paused
	fixture._resume_game()
	await _steps(12)
	var resumed := not paused and player.cooldown_remaining(&"elastic_shell") < cooldown_before
	await _discard(fixture)
	if guard_before != &"guard" or cooldown_before <= 0.0 or not frozen or not still_paused or not resumed:
		return "shell deadline or focus-loss pause failed"
	return ""
