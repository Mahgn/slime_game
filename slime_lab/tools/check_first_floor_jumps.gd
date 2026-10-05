extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	var floor := (load("res://scenes/first_floor.tscn") as PackedScene).instantiate()
	root.add_child(floor)
	current_scene = floor
	await physics_frame
	for child in floor.get_children():
		if child is Spitter or child is BorrowableEnemy:
			child.process_mode = Node.PROCESS_MODE_DISABLED
	var player := floor.get_node("OurSlime") as SlimeController
	await _jump(player, "R04 → промежуточная ступень", Vector3(19.4, 3.25, -37.6), -3.0 * PI / 4.0, 4.0, Vector3(21.6, 0, -35.5))
	await _jump(player, "ступень → R05", Vector3(22.0, 4.05, -34.6), -3.0 * PI / 4.0, 4.8, Vector3(24.2, 0, -32.4))
	await _jump(player, "R08 короткий путь 1", Vector3(6.0, 7.45, -10.5), 0.0, 7.4, Vector3(6.0, 0, -13.5))
	await _jump(player, "R08 короткий путь 2", Vector3(6.0, 7.45, -15.2), 0.0, 7.4, Vector3(6.0, 0, -18.2))
	await _charged_jump(player)
	await _low_passage(player)
	if failures.is_empty():
		print("PASS: обычные и заряженный прыжки, низкий проход и обе ветки R08 работают.")
		quit(0)
		return
	for failure in failures:
		printerr("FAIL: " + failure)
	quit(1)


func _jump(player: SlimeController, title: String, at: Vector3, heading: float, expected_y: float, minimum: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.rotation.y = heading
	player.camera_yaw.rotation.y = 0.0
	for frame in range(22):
		await physics_frame
	if not player.is_on_floor():
		failures.append("%s: старт без опоры, %s" % [title, str(player.global_position)])
		return
	Input.action_press("move_forward")
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	for frame in range(36):
		await physics_frame
	Input.action_release("move_forward")
	for frame in range(8):
		await physics_frame
	if not player.is_on_floor() or absf(player.global_position.y - expected_y) > 0.35:
		failures.append("%s: нет посадки на %.1f м, позиция %s" % [title, expected_y, str(player.global_position)])
	elif absf(player.global_position.x - minimum.x) > 1.6 or absf(player.global_position.z - minimum.z) > 1.6:
		failures.append("%s: посадка слишком далеко от цели, %s" % [title, str(player.global_position)])


func _charged_jump(player: SlimeController) -> void:
	player.global_position = Vector3(16.0, 3.25, -40.0)
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.0
	player.camera_yaw.rotation.y = 0.0
	for frame in range(25):
		await physics_frame
	Input.action_press("jump")
	for frame in range(42):
		await physics_frame
	if not player.is_on_floor() or player.get_jump_charge_ratio() < 0.8:
		failures.append("Удержание пробела не зарядило прыжок на земле.")
	Input.action_release("jump")
	var peak := player.global_position.y
	for frame in range(32):
		await physics_frame
		peak = maxf(peak, player.global_position.y)
	if peak < 4.65:
		failures.append("Заряженный прыжок не поднял Слизи выше обычного: %.2f" % peak)


func _low_passage(player: SlimeController) -> void:
	var roof_visual := current_scene.get_node_or_null("FirstFloorRoute/R08LowPassage/LowRoof/Stone") as MeshInstance3D
	if roof_visual == null:
		failures.append("Не найдена визуальная крыша низкого прохода R08.")
		return
	player.global_position = Vector3(-3.5, 7.45, -12.7)
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.0
	player.camera_yaw.rotation.y = 0.0
	for frame in range(24):
		await physics_frame
	if not player.is_on_floor():
		failures.append("Подход к низкому проходу R08 без опоры.")
		return
	Input.action_press("move_forward")
	for frame in range(46):
		await physics_frame
	Input.action_release("move_forward")
	if not player.is_compressed() or player.global_position.z > -14.6:
		failures.append("Слизи не сжался при входе под потолок R08: %s" % str(player.global_position))
	if roof_visual.visible:
		failures.append("Крыша низкого прохода закрывает камере Слизь при сжатии.")
	Input.action_press("move_forward")
	for frame in range(78):
		await physics_frame
	Input.action_release("move_forward")
	for frame in range(15):
		await physics_frame
	if player.is_compressed() or player.global_position.z > -19.0:
		failures.append("Слизи не прошёл низкий участок или не распрямился на выходе: %s" % str(player.global_position))
	if not roof_visual.visible:
		failures.append("Крыша низкого прохода не появилась после выхода Слизи.")
