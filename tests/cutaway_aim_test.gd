extends SceneTree

var failures := 0
var assertions := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var watchdog := create_timer(30.0)
	watchdog.timeout.connect(func() -> void: printerr("FAIL cutaway aim watchdog"); quit(124))
	var fixture := preload("res://tests/helpers/combat_fixture.tscn").instantiate()
	fixture.set_meta(&"isometric_dressing_owned", true)
	root.add_child(fixture)
	var player: SlimeController = fixture.player
	var cutaway := SlimeRoomCutaway.new()
	fixture.add_child(cutaway)
	player.presentation.room_cutaway = cutaway
	var wall := StaticBody3D.new()
	wall.position = Vector3(1, 1.5, 1)
	wall.rotation.y = PI / 4.0
	wall.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(9, 3, 0.2)
	collision.shape = shape
	wall.add_child(collision)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	mesh.mesh = box
	mesh.material_override = StandardMaterial3D.new()
	wall.add_child(mesh)
	fixture.add_child(wall)
	cutaway.register_section(&"test_upper", [mesh] as Array[MeshInstance3D], 2.0)
	var enemy: Spitter = fixture.spawn_spitter(Vector3(-0.65, 0.05, -0.65))
	enemy.set_physics_process(false)
	await _frames(12)
	var camera := player.presentation.camera
	var target := enemy.global_position + Vector3.UP * 0.45
	player.controls.pointer = camera.unproject_position(target)
	cutaway.set_enabled(false)
	_check(player.controls.get_aim_point().distance_to(target) > 0.10,
		"opaque wall prevents selecting the enemy behind its surface")
	cutaway.set_enabled(true)
	# The test floor is a synthetic lower route at y=0; select the authored
	# lower state directly so this fixture tests aiming, not floor selection.
	cutaway.lower_route = true
	cutaway.update_view(player, camera)
	await _frames(20)
	_check(player.controls.get_aim_point().distance_to(target) < 0.01,
		"enemy behind a revealed whole section is selected by the real camera ray")
	enemy.global_position = Vector3(1.2, 0.05, -1.2)
	await _frames(2)
	target = enemy.global_position + Vector3.UP * 0.45
	player.controls.pointer = camera.unproject_position(target)
	_check(player.controls.get_aim_point().distance_to(target) < 0.01,
		"revealed section passes aiming across its complete surface")
	cutaway.set_enabled(false)
	await _frames(20)
	_check(player.controls.get_aim_point().distance_to(target) > 0.10,
		"restored solid section blocks selecting enemies again")
	_check(mesh.visible and not collision.disabled and wall.collision_layer == 1,
		"section reveal keeps its mesh instance and physical collision")
	# A separate physical attack direction crosses the very same cuttable wall.
	wall.position = Vector3(0.6, 1.5, 0.6)
	enemy.global_position = Vector3(1.2, 0.05, 1.2)
	cutaway.set_enabled(true)
	cutaway.lower_route = true
	await _frames(20)
	player.controls.pointer = camera.unproject_position(enemy.global_position + Vector3.UP * 0.45)
	var health_before := enemy.health
	_check(player.request_action(&"slime_whip"), "real whip starts toward the enemy across the wall")
	await _frames(55)
	_check(enemy.health == health_before, "the revealed whole section still blocks actual whip damage")
	fixture.queue_free()
	await _frames(3)
	print("CUTAWAY_AIM_RESULT assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _check(value: bool, label: String) -> void:
	assertions += 1
	print(("PASS " if value else "FAIL ") + label)
	if not value:
		failures += 1
