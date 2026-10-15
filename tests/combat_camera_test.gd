extends SceneTree

const PLAYER := preload("res://scenes/player/slime_player.tscn")
var failures := 0
var assertions := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	preload("res://scripts/input_setup.gd").install()
	var settings := SlimeGameSettings.current()
	var previous_shake := settings.camera_shake
	# Direct temporary values deliberately bypass persistent settings setters.
	settings.camera_shake = 0.0
	var fixture := Node3D.new()
	fixture.set_meta(&"isometric_camera_center", Vector3(0, 0.45, 0))
	fixture.set_meta(&"isometric_dressing_owned", true)
	root.add_child(fixture)
	var player := PLAYER.instantiate() as SlimeController
	fixture.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	var presentation := player.presentation
	presentation.set_process(false)
	var target := CharacterBody3D.new()
	target.collision_layer = 4
	target.position = Vector3(2, 0, -2)
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.0
	collision.shape = shape
	collision.position.y = 0.5
	target.add_child(collision)
	fixture.add_child(target)
	await _frames(2)
	var camera := presentation.camera
	var baseline := camera.global_transform
	presentation.play_combat_impact(Vector3.RIGHT)
	presentation._update_camera(0.01)
	_check(camera.global_transform.is_equal_approx(baseline), "zero shake prevents all combat camera motion")
	settings.camera_shake = 1.0
	player.controls.pointer = camera.unproject_position(target.global_position + Vector3.UP * 0.45)
	var actor_aim := player.controls.get_aim_point()
	_check(actor_aim.distance_to(target.global_position + Vector3.UP * 0.45) < 0.001, "fixture ray selects the real actor collider")
	presentation.play_combat_impact(Vector3.RIGHT, 3.0)
	presentation._update_camera(0.01)
	var peak := presentation.get_combat_camera_offset()
	_check(peak.length() > 0.001 and peak.length() <= 0.0551, "positive impact is visible and bounded even above strength one")
	_check(camera.global_basis.is_equal_approx(baseline.basis), "combat translation preserves the fixed camera basis")
	_check(player.controls.get_aim_point().distance_to(actor_aim) < 0.001, "camera translation preserves a stationary cursor's actor selection")
	# Also exercise the fallback combat plane away from an actor.
	presentation._update_camera(0.0)
	player.controls.pointer = camera.unproject_position(Vector3(-3, player._combat_origin_height(), -1))
	var plane_aim := player.controls.get_aim_point()
	presentation.play_combat_impact(Vector3(-0.8, 0.1, 0.6))
	var stable := true
	var bounded := true
	for index in 20:
		presentation._update_camera(0.01)
		stable = stable and player.controls.get_aim_point().distance_to(plane_aim) < 0.001
		bounded = bounded and presentation.get_combat_camera_offset().length() <= 0.0551
	_check(stable, "the ground aim stays fixed through the whole damped pulse")
	_check(bounded and camera.global_basis.is_equal_approx(baseline.basis), "all samples stay bounded without camera rotation")
	_check(presentation.get_combat_camera_offset() == Vector3.ZERO and camera.global_transform.is_equal_approx(baseline), "the pulse returns exactly to the original frame")
	presentation.play_combat_impact(Vector3.RIGHT)
	presentation._update_camera(0.01)
	var paused_transform := camera.global_transform
	var paused_offset := presentation.get_combat_camera_offset()
	presentation.set_process(true)
	paused = true
	await _frames(4)
	_check(camera.global_transform.is_equal_approx(paused_transform) and presentation.get_combat_camera_offset() == paused_offset, "game pause freezes the impact camera")
	presentation.play_combat_impact(Vector3.FORWARD)
	_check(presentation.get_combat_camera_offset() == paused_offset, "a paused impact request does not replace the rendered offset")
	paused = false
	presentation.set_process(false)
	presentation._update_camera(0.0)
	_check(presentation.get_combat_camera_offset() == Vector3.ZERO and camera.global_transform.is_equal_approx(baseline), "explicit checkpoint snap clears the impact")
	for index in 15:
		presentation.play_combat_impact(Vector3.RIGHT, 100.0)
		presentation._update_camera(0.002)
	_check(presentation.get_combat_camera_offset().length() <= 0.0551, "repeated contacts never accumulate camera drift")
	player.global_position += Vector3.RIGHT * 5.0
	presentation._update_camera(0.01)
	_check(presentation.get_combat_camera_offset() == Vector3.ZERO, "teleport clears the impact even with a fixed room center")
	presentation.play_combat_impact(Vector3.RIGHT)
	presentation._update_camera(0.01)
	paused = true
	settings.camera_shake = 0.0
	settings.changed.emit()
	_check(presentation.get_combat_camera_offset() == Vector3.ZERO and camera.global_transform.is_equal_approx(baseline), "disabling shake while paused immediately restores the frame")
	paused = false
	settings.camera_shake = previous_shake
	fixture.queue_free()
	await _frames(2)
	print("COMBAT_CAMERA_RESULT assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame


func _check(value: bool, label: String) -> void:
	assertions += 1
	print(("PASS " if value else "FAIL ") + label)
	if not value:
		failures += 1
