extends SceneTree

const SCENE := "res://scenes/levels/first_floor.tscn"

var failures: Array[String] = []

# Scenario automation must keep running if the human focuses another app.
# Production focus-loss pause is checked by first_floor_integration_test.gd.
class FocusStableFloor:
	extends FirstFloorGame
	func _notification(what: int) -> void:
		if what != NOTIFICATION_APPLICATION_FOCUS_OUT:
			super._notification(what)


func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	var packed := load(SCENE) as PackedScene
	if packed == null:
		printerr("FAIL: не загрузился первый этаж")
		quit(1)
		return
	var watchdog := Timer.new()
	watchdog.wait_time = 100
	watchdog.one_shot = true
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(watchdog)
	watchdog.timeout.connect(func() -> void: printerr("FAIL: integration watchdog"); quit(1))
	watchdog.start()
	var floor := packed.instantiate()
	floor.set_script(FocusStableFloor)
	root.add_child(floor)
	current_scene = floor
	await _frames(4)
	var player := floor.get_node("OurSlime") as SlimeController
	if player == null:
		failures.append("Не создан контроллер слайма второго разработчика.")
		_finish()
		return
	var blockout := floor.get_node("OpeningCyclopsBlockout")
	if blockout.get_child_count() < 45:
		failures.append("Маршрут содержит меньше 45 блоков Cyclops.")
	var camera := player.get_node_or_null("CameraYaw/CameraPitch/SpringArm3D/Camera3D") as Camera3D
	if camera == null or not camera.current:
		failures.append("Нет активной третьеличной камеры на SpringArm3D.")
	else:
		var old_yaw := player.camera_yaw.rotation.y
		var old_pitch := player.camera_pitch.rotation.x
		var look := InputEventMouseMotion.new()
		look.screen_relative = Vector2(80, -40)
		player._input(look)
		await _frames(2)
		if DisplayServer.get_name() == "headless":
			print("NOT_RUN: captured mouse camera input requires a window")
		elif absf(player.camera_yaw.rotation.y - old_yaw) < 0.01 or absf(player.camera_pitch.rotation.x - old_pitch) < 0.01:
			failures.append("Движение мыши не повернуло камеру.")
		player.camera_yaw.rotation.y = 0.0
		player.rotation.y = 0.0
	var enemies: Array[Node3D] = []
	var first_spitter: Spitter
	for child in floor.get_children():
		if child is Spitter or child is BorrowableEnemy:
			enemies.append(child)
			child.process_mode = Node.PROCESS_MODE_DISABLED
			if first_spitter == null and child is Spitter:
				first_spitter = child as Spitter
	if enemies.size() < 8 or first_spitter == null:
		failures.append("Не появились боевые встречи второго разработчика.")
	else:
		await _check_combat(player, first_spitter, floor)
	_check_hero_feedback(player)
	await _check_route(player, floor)
	_finish()


func _check_combat(player: SlimeController, enemy: Spitter, floor: Node3D) -> void:
	player.global_position = Vector3(0, 0.05, 5)
	player.velocity = Vector3.ZERO
	enemy.global_position = Vector3(0, 0.05, 3.4)
	await _frames(20)
	var variants: Array[int] = []
	for attack in range(3):
		if not player.request_action(&"slime_whip"):
			failures.append("Контроллер отклонил удар хлыстом %d." % attack)
			break
		variants.append(int(player.get("_whip_variant")))
		await _frames(38)
	if variants.size() == 3 and (variants[0] == variants[1] or variants[0] == variants[2] or variants[1] == variants[2]):
		failures.append("Три анимации хлыста повторились в одном цикле.")
	if is_instance_valid(enemy) and enemy.health > 0:
		failures.append("Хлыст не нанёс урон Плевуну.")
	var source := floor.find_child("AbsorbSource", true, false) as AbsorbSource
	if source == null or source.ability_id != &"sticky_spit":
		failures.append("Плевун не оставил источник липкого плевка.")
	else:
		player.global_position = source.global_position + Vector3(0, 0.05, 0.7)
		player.velocity = Vector3.ZERO
		await _frames(12)
		Input.action_press("interact")
		await _frames(42)
		Input.action_release("interact")
		if not player.has_learned(&"sticky_spit") or player.get_slot_ability(1) != &"sticky_spit":
			failures.append("Удержание E не открыло липкий плевок в первом слоте.")
		if not floor.get("_r02_followup_spawned"):
			failures.append("После изучения плевка не появилась вторая учебная встреча R02.")
		for node in get_nodes_in_group(&"enemies"):
			if node is Spitter:
				node.process_mode = Node.PROCESS_MODE_DISABLED
	var projectile_count := {"value": 0}
	player.projectile_requested.connect(func(_origin: Vector3, _direction: Vector3, _damage: int, _speed: float, _range: float, _key: String, _factor: float, _seconds: float) -> void: projectile_count["value"] += 1)
	if player.request_action(&"sticky_spit"):
		await _frames(20)
		if projectile_count["value"] == 0:
			failures.append("Липкий плевок не создал снаряд.")
	else:
		failures.append("Не удалось вызвать изученный липкий плевок.")
	await _frames(25)
	player.grant_ability(&"elastic_shell")
	if player.unlocked_slots != 1:
		failures.append("Поглощение Панцирника незаконно открыло второй слот.")
	for candidate in get_nodes_in_group(&"enemies"):
		candidate.remove_from_group(&"enemies")
		candidate.queue_free()
	player.global_position = Vector3(19, 3.25, -41)
	player.velocity = Vector3.ZERO
	await _frames(50)
	Input.action_press("interact")
	await _frames(40)
	Input.action_release("interact")
	if player.unlocked_slots != 2 or player.get_slot_ability(2) != &"elastic_shell":
		failures.append("Удержание E у ядра не открыло второй слот.")
	var previous_health := player.health
	if player.request_action(&"elastic_shell"):
		await _frames(9)
		player.receive_hit(20, "test_shell_hit", &"enemy")
		if player.health != previous_health:
			failures.append("Панцирь не защитил от удара.")
	else:
		failures.append("Панцирь не запускается из второго слота.")
	await _frames(100)
	player.grant_ability(&"slime_spikes")
	if not player.equip_ability(2, &"slime_spikes"):
		failures.append("Не удалось выбрать шипы во втором слоте.")
	elif player.request_action(&"slime_spikes"):
		await _frames(25)
		if get_nodes_in_group(&"temporary_effects").is_empty():
			failures.append("Слизевые шипы не появились в мире.")
	else:
		failures.append("Слизевые шипы не запускаются.")


func _check_route(player: SlimeController, floor: Node3D) -> void:
	var samples := [
		["R02", Vector3(0, 4.2, -30), 2.6],
		["R03", Vector3(0, 4.8, -40), 3.2],
		["R04", Vector3(16, 4.8, -40), 3.2],
		["R05", Vector3(28, 6.4, -29), 4.8],
		["R06", Vector3(27, 7.8, -9), 6.2],
		["R07", Vector3(14, 8.4, -2), 6.8],
		["R08", Vector3(3, 9.0, -8), 7.4],
		["R09", Vector3(0, 9.0, -33), 7.4],
	]
	for sample in samples:
		player.global_position = sample[1]
		player.velocity = Vector3.ZERO
		await _frames(45)
		if not player.is_on_floor() or absf(player.global_position.y - sample[2]) > 0.4:
			failures.append("Нет опоры на %s: y=%.2f" % [sample[0], player.global_position.y])
	await _frames(40)
	player.global_position = Vector3(0, 7.45, -36.1)
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.0
	player.camera_yaw.rotation.y = 0.0
	await _frames(12)
	if not player.request_action(&"slime_whip"):
		failures.append("Хлыст не готов перед канатом.")
	else:
		await _frames(55)
		if not floor.get("_bridge_open"):
			failures.append("Хлыст не освободил канат R09.")
		var bridge_shape := (floor.get("_route_refs") as Dictionary)["bridge_shape"] as CollisionShape3D
		if bridge_shape.disabled:
			failures.append("Опущенный мост не получил коллизию.")
	player.global_position = Vector3(0, 7.45, -47)
	player.velocity = Vector3.ZERO
	await _frames(5)
	if not floor.get("_completed"):
		failures.append("Выход не завершает первый этаж.")


func _check_hero_feedback(player: SlimeController) -> void:
	var previous_health := player.health
	if not player.receive_hit(7, "hero_feedback_test", &"enemy", Vector3.RIGHT):
		failures.append("Обновлённый герой не принял направленный удар.")
	elif player.health != previous_health - 7 or player.get("_hit_pulse") <= 0.0:
		failures.append("У направленного удара нет отклика и потери здоровья.")
	player.health = player.MAX_HEALTH
	player.global_position = Vector3(0, 0.05, 5)
	if player.health != player.MAX_HEALTH or not player.has_learned(&"sticky_spit"):
		failures.append("Возврат к отметке не восстановил здоровье или потерял изученный навык.")


func _frames(count: int) -> void:
	for frame in range(count):
		await physics_frame


func _finish() -> void:
	if failures.is_empty():
		print("PASS: три хлыста, плевок, поглощение, ядро, панцирь, шипы, зоны, мост и выход")
		SlimeGameSettings.current().request_quit()
		return
	for failure in failures:
		printerr("FAIL: " + failure)
	quit(1)
