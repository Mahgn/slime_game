extends SceneTree

const PLAYER = preload("res://scenes/player/slime_player.tscn")
const SPITTER = preload("res://scenes/enemies/spitter.tscn")
const PROJECTILE = preload("res://scenes/abilities/spit_projectile.tscn")
const SOURCE = preload("res://scenes/interactables/absorb_source.tscn")
var failures := 0
var shots := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var watchdog := Timer.new()
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.wait_time = 45.0
	watchdog.one_shot = true
	root.add_child(watchdog)
	watchdog.timeout.connect(func() -> void: printerr("FAIL isometric watchdog"); quit(124))
	watchdog.start()
	preload("res://scripts/input_setup.gd").install()
	set_meta(&"checkpoint_active", false)
	var fixture := Node3D.new()
	root.add_child(fixture)
	var floor_body := StaticBody3D.new()
	floor_body.position.y = -0.2
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 0.4, 40)
	collision.shape = box
	floor_body.add_child(collision)
	fixture.add_child(floor_body)
	var roof := StaticBody3D.new()
	roof.position = Vector3(0, 3, 0)
	var roof_collision := CollisionShape3D.new()
	var roof_box := BoxShape3D.new()
	roof_box.size = Vector3(8, 0.3, 8)
	roof_collision.shape = roof_box
	roof.add_child(roof_collision)
	var roof_visual := MeshInstance3D.new()
	var roof_mesh := BoxMesh.new()
	roof_mesh.size = roof_box.size
	roof_visual.mesh = roof_mesh
	roof.add_child(roof_visual)
	fixture.add_child(roof)
	var player := PLAYER.instantiate() as SlimeController
	player.position = Vector3(0, 0.05, 0)
	fixture.add_child(player)
	var combat := preload("res://scripts/combat/combat_runtime.gd").new()
	fixture.add_child(combat)
	combat.bind_player(player)
	await _frames(8)
	_check(player.presentation.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "orthographic camera")
	var stable_camera := true
	for sample in 4:
		await physics_frame
		await process_frame
		var offset := player.presentation.camera.global_position - (player.global_position + Vector3.UP * 0.45)
		stable_camera = stable_camera and offset.distance_to(Vector3(12.0, 13.9, 12.0)) < 0.1
	_check(stable_camera, "camera stays in the isometric position between physics and rendering")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "free pointer")
	_check(not roof_visual.visible and not roof_collision.disabled and roof.collision_layer == 1, "overhead floor hidden while solid collision remains")
	var upper_enemy := SPITTER.instantiate() as Spitter
	upper_enemy.position = Vector3(0, 3.05, 0)
	fixture.add_child(upper_enemy)
	upper_enemy.set_physics_process(false)
	player.presentation._update_occlusion()
	_check(not upper_enemy.visible and upper_enemy.collision_layer != 0, "upper enemy hidden without disabling combat collision")
	player.controls.pointer = player.presentation.camera.unproject_position(upper_enemy.global_position + Vector3.UP * 0.45)
	_check(is_equal_approx(player.controls.get_aim_point().y, player.global_position.y + player._combat_origin_height()), "cursor ignores hidden upper enemy")
	upper_enemy.global_position = Vector3(4, 0.05, 0)
	player.presentation._update_occlusion()
	_check(upper_enemy.visible, "enemy visibility restored on current floor")
	upper_enemy.queue_free()
	await _frames(2)
	var basis := player.presentation.camera.global_basis
	var initial := player.global_position
	Input.action_press(&"move_right")
	await _frames(24)
	Input.action_release(&"move_right")
	await _frames(20)
	var move := player.global_position - initial
	_check(move.dot(basis.x) > 1.0 and absf(move.dot(basis.z)) < 0.15, "D moves to screen right")
	initial = player.global_position
	Input.action_press(&"move_forward")
	await _frames(24)
	Input.action_release(&"move_forward")
	await _frames(20)
	move = player.global_position - initial
	_check(move.dot(basis.y) > 0.4 and absf(move.dot(basis.x)) < 0.15, "W moves to screen top")
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(450, 250)
	motion.relative = Vector2(100, -40)
	Input.parse_input_event(motion)
	await _frames(2)
	_check(player.presentation.camera.global_basis.is_equal_approx(basis), "pointer does not rotate camera")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	Input.parse_input_event(wheel)
	await _frames(20)
	_check(player.presentation.camera.size < 12.4, "mouse wheel zoom")
	player.global_position = Vector3.ZERO
	player.velocity = Vector3.ZERO
	await _frames(10)
	var enemy := SPITTER.instantiate() as Spitter
	enemy.position = Vector3(0, 0.05, -1.35)
	fixture.add_child(enemy)
	enemy.set_physics_process(false)
	var events := {"died": false}
	combat.bind_enemy(enemy)
	combat.source_created.connect(func(drop: AbsorbSource) -> void:
		events["died"] = true
		drop.name = "DroppedAbility")
	await _frames(4)
	player.controls.pointer = player.presentation.camera.unproject_position(enemy.global_position + Vector3.UP * 0.45)
	var aim := player.controls.get_aim_point()
	_check(Vector2(aim.x, aim.z).distance_to(Vector2(enemy.position.x, enemy.position.z)) < 0.2, "cursor picks enemy")
	_check(player.request_action(&"slime_whip"), "whip begins toward cursor")
	await _frames(50)
	_check(enemy.health == 20, "real whip deals one hit")
	for iteration in range(2):
		player.request_action(&"slime_whip")
		await _frames(50)
	_check(events["died"], "three actual whip actions kill Spitter")
	var source := combat.get_node("DroppedAbility") as AbsorbSource
	await _frames(5)
	Input.action_press(&"interact")
	await _frames(36)
	Input.action_release(&"interact")
	_check(player.equipped_ability == &"sticky_spit" and source.is_claimed(), "hold E absorbs and fills slot")
	var target := SPITTER.instantiate() as Spitter
	target.position = Vector3(2.0, 0.05, -4.0)
	fixture.add_child(target)
	target.set_physics_process(false)
	combat.bind_enemy(target)
	player.projectile_requested.connect(func(_origin: Vector3, _direction: Vector3, _damage: int, _speed: float, _max_range: float, _key: String, _slow: float, _seconds: float) -> void: shots += 1)
	await _frames(4)
	player.controls.pointer = player.presentation.camera.unproject_position(target.global_position + Vector3.UP * 0.45)
	Input.action_press(&"ability_slot_1")
	await _frames(45)
	Input.action_release(&"ability_slot_1")
	_check(shots == 1 and target.health == 18, "slot input launches real projectile at cursor enemy")
	var cooldown := player.cooldown_remaining(&"sticky_spit")
	_check(cooldown > 0 and not player.request_action(&"sticky_spit"), "owner cooldown preserved")
	paused = true
	await _frames(20)
	_check(is_equal_approx(cooldown, player.cooldown_remaining(&"sticky_spit")), "pause freezes cooldown")
	paused = false
	await _frames(4)
	_check(player.cooldown_remaining(&"sticky_spit") < cooldown, "resume advances cooldown")
	Input.action_press(&"jump")
	await _frames(3)
	Input.action_release(&"jump")
	await _frames(10)
	_check(player.global_position.y > 0.4, "physical jump preserved")
	fixture.queue_free()
	await _frames(3)
	print("ISOMETRIC_RESULT failures=%d" % failures)
	quit(0 if failures == 0 else 1)


func _check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value:
		failures += 1


func _frames(count: int) -> void:
	for index in range(count):
		await physics_frame
