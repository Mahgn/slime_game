extends SceneTree

const ROOM = preload("res://scenes/r03_armorer.tscn")
const OUTPUT := "res://output/S7/armorer_art/"

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	set_meta(&"checkpoint_active", false)
	var room := ROOM.instantiate()
	root.add_child(room)
	var player := room.get_node("SlimePlayer") as SlimeController
	var enemy: BorrowableEnemy
	for candidate in get_nodes_in_group(&"enemies"):
		if candidate is BorrowableEnemy and candidate.kind == "armorer":
			enemy = candidate as BorrowableEnemy
			break
	if enemy == null:
		push_error("R03 Armorer not found")
		quit(1)
		return
	var visual := enemy.get_node_or_null("ArmorerVisual") as ArmorerVisual
	if visual == null:
		push_error("Armorer visual not found")
		quit(1)
		return
	enemy.player_target = null
	enemy.set_physics_process(false)
	enemy.set_process(false)
	enemy.rotation.y = PI
	player.global_position = Vector3(0.0, 0.05, 3.0)
	player.velocity = Vector3.ZERO
	player.set_physics_process(false)
	var inspection := Camera3D.new()
	inspection.name = "ArmorerInspectionCamera"
	inspection.fov = 48.0
	inspection.position = enemy.global_position + Vector3(1.38, 1.48, 2.55)
	room.add_child(inspection)
	inspection.look_at(enemy.global_position + Vector3.UP * 0.62)
	inspection.current = true
	visual.animate(0.016, Vector3.ZERO, false)
	await _frames(6)
	await _save("01_front_three_quarter.png")
	inspection.position = enemy.global_position + Vector3(2.7, 1.35, 0.18)
	inspection.look_at(enemy.global_position + Vector3.UP * 0.62)
	await _save("02_side.png")
	inspection.position = enemy.global_position + Vector3(1.38, 1.48, 2.55)
	inspection.look_at(enemy.global_position + Vector3.UP * 0.62)
	enemy._set_phase(&"shell", 1.0)
	visual.animate(0.25, Vector3.ZERO, false)
	await _save("03_guard.png")
	var hp_before := enemy.health
	enemy.receive_hit(10, "capture_block", &"player")
	visual.animate(0.12, Vector3.ZERO, false)
	if enemy.health != hp_before or enemy._shield_raised:
		_failures += 1
		print("FAIL GUARD_BLOCK hp=%d before=%d raised=%s" % [enemy.health, hp_before, enemy._shield_raised])
	else:
		print("PASS GUARD_BLOCK hp=%d" % enemy.health)
	await _save("04_guard_consumed.png")
	enemy._set_phase(&"windup", 0.65)
	visual.animate(0.25, Vector3.ZERO, false)
	await _save("05_windup.png")
	enemy.receive_hit(10, "capture_hurt", &"player")
	visual.animate(0.016, Vector3.ZERO, true)
	await _save("06_hurt.png")
	inspection.current = false
	player.camera.current = true
	await _frames(3)
	await _save("07_game_camera_r03.png")
	room.queue_free()
	await _frames(3)
	print("ARMORER_CAPTURE failures=%d" % _failures)
	call_deferred("quit", 0 if _failures == 0 else 1)


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var code := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + file_name))
	print("CAPTURE %s code=%d" % [file_name, code])
	if code != OK:
		_failures += 1


func _frames(count: int) -> void:
	for index in count:
		await process_frame
