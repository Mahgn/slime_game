extends SceneTree

const COURSE_SCENE = preload("res://scenes/art_review/slime_platform_course.tscn")
var course: Node3D
var player: SlimeController
var _failed := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	course = COURSE_SCENE.instantiate()
	root.add_child(course)
	await _steps(5)
	player = course.player
	var wall: FragileWall = course._fragile_wall
	wall.receive_hit(30, "probe:slime_whip", &"player")
	await _steps(3)
	for spec in [
		["P1_P2_QUICK_FAILS", Vector3(0.0, 0.40, 3.15), 1, 0.5, 0.0, false],
		["P1_P2_CHARGED_PASSES", Vector3(0.0, 0.40, 3.15), 42, 0.5, 0.0, true],
		["P2_P3_CHARGED_PASSES", Vector3(0.0, 1.75, 0.05), 42, -4.05, -5.2, true],
		["P2_P3_QUICK_PASSES", Vector3(0.0, 1.75, 0.05), 1, -4.05, -5.2, true],
		["P4_P5_QUICK_FAILS", Vector3(0.0, 0.50, -7.2), 1, -9.3, 0.0, false],
		["P4_P5_CHARGED_PASSES", Vector3(0.0, 0.50, -7.2), 42, -9.3, 0.0, true],
	]:
		var result := await _attempt(spec[1], spec[2], spec[3], spec[4])
		print("PROBE %s result=%s" % [spec[0], str(result)])
		var landed: bool = bool(result["ground"]) and not bool(result["fell"]) and bool(result["floor"]) and absf(float(result["z"]) - float(spec[3])) < 0.8
		_check(spec[0], landed == spec[5])
	print("SUMMARY: %d failed" % _failed)
	quit(1 if _failed > 0 else 0)

func _attempt(start: Vector3, hold_ticks: int, target_z: float, initial_speed: float) -> Dictionary:
	Input.action_release(&"jump")
	Input.action_release(&"move_forward")
	player.global_position = start
	player.velocity = Vector3.ZERO
	await _steps(8)
	var ground := player.is_on_floor()
	var health_before := player.health
	Input.action_press(&"jump")
	await _steps(hold_ticks)
	var charge := player.get_jump_charge_ratio()
	Input.action_release(&"jump")
	player.velocity.z = initial_speed
	Input.action_press(&"move_forward")
	var apex := player.global_position.y
	var ticks := 0
	var fell := false
	while ticks < 85 and player.global_position.z > target_z + 0.24:
		await _steps(1)
		ticks += 1
		apex = maxf(apex, player.global_position.y)
		if player.health < health_before:
			fell = true
			break
	Input.action_release(&"move_forward")
	await _steps(45)
	return {"ground": ground, "charge": charge, "apex": apex, "z": player.global_position.z, "y": player.global_position.y, "floor": player.is_on_floor(), "fell": fell, "ticks": ticks}

func _steps(count: int) -> void:
	for tick in count:
		await physics_frame
func _check(label: String, condition: bool) -> void:
	if condition:
		print("PASS %s" % label)
	else:
		_failed += 1
		print("FAIL %s" % label)
