extends SceneTree

const COURSE_SCENE = preload("res://scenes/art_review/slime_platform_course.tscn")
var failed := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var course := COURSE_SCENE.instantiate()
	root.add_child(course)
	await _steps(5)
	var player: SlimeController = course.player
	course._fragile_wall.receive_hit(30, "probe:whip", &"player")
	for start_z in [-9.85, -10.05, -10.25]:
		Input.action_release(&"jump")
		Input.action_release(&"move_forward")
		player.global_position = Vector3(0.0, 1.85, start_z)
		player.velocity = Vector3.ZERO
		course._press_frozen_left = 0.0
		course._press_motion_time = course.PRESS_PERIOD * 0.75
		await _steps(8)
		course._on_sticky_applied()
		var grounded := player.is_on_floor()
		var health_before := player.health
		Input.action_press(&"jump")
		await _steps(42)
		Input.action_release(&"jump")
		Input.action_press(&"move_forward")
		var farthest_z := player.global_position.z
		for tick in 110:
			await _steps(1)
			farthest_z = minf(farthest_z, player.global_position.z)
			if player.health < health_before:
				break
		Input.action_release(&"move_forward")
		await _steps(10)
		var bypassed: bool = farthest_z < course.TRAP_Z - 0.8
		print("PROBE start=%.2f grounded=%s farthest=%.2f hp=%d bypassed=%s" % [start_z, str(grounded), farthest_z, player.health, str(bypassed)])
		if not grounded or bypassed:
			failed += 1
	print("SUMMARY: %d failed" % failed)
	quit(1 if failed > 0 else 0)

func _steps(count: int) -> void:
	for tick in count:
		await physics_frame


