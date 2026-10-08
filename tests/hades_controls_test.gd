extends SceneTree

const PLAYER := preload("res://scenes/player/slime_player.tscn")
const DIRECTIONS := {
	"W": Vector2(0, -1), "A": Vector2(-1, 0),
	"S": Vector2(0, 1), "D": Vector2(1, 0),
	"WA": Vector2(-1, -1), "WD": Vector2(1, -1),
	"SA": Vector2(-1, 1), "SD": Vector2(1, 1),
}
var failures := 0
var assertions := 0
var ticks := 60
var samples: Array[Dictionary] = []
var fixture: Node3D
var player: SlimeController


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("ticks="):
			ticks = int(argument.trim_prefix("ticks="))
	Engine.physics_ticks_per_second = ticks
	call_deferred("_run")


func _run() -> void:
	var watchdog := create_timer(40.0, true)
	watchdog.timeout.connect(func() -> void: printerr("FAIL controls watchdog"); quit(124))
	preload("res://scripts/input_setup.gd").install()
	fixture = Node3D.new()
	fixture.set_meta(&"isometric_dressing_owned", true)
	root.add_child(fixture)
	_box("Floor", Vector3(0, -0.2, 0), Vector3(40, 0.4, 40))
	player = PLAYER.instantiate() as SlimeController
	fixture.add_child(player)
	await _frames(6)
	for label: String in DIRECTIONS:
		await _direction_trial(label, DIRECTIONS[label])
	var acceleration_times: Array[float] = []
	var braking_times: Array[float] = []
	for sample in samples:
		acceleration_times.append(sample["acceleration_seconds"])
		braking_times.append(sample["braking_seconds"])
	_check(acceleration_times.max() - acceleration_times.min() <= 1.1 / ticks, "equal acceleration in all eight directions")
	_check(braking_times.max() - braking_times.min() <= 1.1 / ticks, "equal braking in all eight directions")
	await _reset()
	_set_axes(Vector2(-1, 1))
	await _frames(ticks / 2)
	_set_axes(Vector2(1, -1))
	var reverse_ticks := 0
	while player.velocity.z > -5.0 and reverse_ticks < ticks:
		await _frames(1)
		reverse_ticks += 1
	_check(float(reverse_ticks) / ticks <= 0.20, "opposite input reaches full speed within 0.20 s")
	await _reset()
	var camera_basis := player.presentation.camera.global_basis
	player.grant_ability(&"sticky_spit")
	player.controls.pointer = player.presentation.camera.unproject_position(Vector3(0, 0.65, -5))
	var shots: Array[Vector3] = []
	player.projectile_requested.connect(func(_origin: Vector3, direction: Vector3, _damage: int, _speed: float, _range: float, _key: String, _slow: float, _seconds: float) -> void: shots.append(direction))
	_set_axes(Vector2(-1, 1))
	Input.action_press(&"ability_slot_1")
	await _frames(1)
	Input.action_release(&"ability_slot_1")
	var attack_direction := player._action_direction
	player.controls.pointer = player.presentation.camera.unproject_position(Vector3(5, 0.65, 0))
	await _frames(int(ticks * 0.25))
	_check(shots.size() == 1 and shots[0].dot(Vector3.FORWARD) > 0.95, "spit aims at cursor while moving away")
	_check(attack_direction.dot(player._action_direction) > 0.999, "started attack keeps its direction after cursor moves")
	_check(player.velocity.z > 0 and player.velocity.length() > 3.0, "movement remains independent during attack")
	_check(player.presentation.camera.global_basis.is_equal_approx(camera_basis), "movement and aiming do not turn camera")
	var paused_position := player.global_position
	var cooldown := player.cooldown_remaining(&"sticky_spit")
	player.clear_action_buffer()
	paused = true
	await _frames(5)
	_check(player.global_position.is_equal_approx(paused_position) and is_equal_approx(player.cooldown_remaining(&"sticky_spit"), cooldown), "pause freezes movement and cooldown")
	paused = false
	await _reset()
	var wall := _box("Wall", Vector3(0, 1, -2), Vector3(4, 2, 0.2))
	_set_axes(Vector2(1, -1))
	await _frames(ticks / 2)
	_check(player.global_position.z > -1.6 and player.global_position.z < -1.0, "fast movement remains blocked by physical wall")
	wall.queue_free()
	_release()
	var output := "res://output/hades_controls_2026_10_06/metrics-%d.json" % ticks
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({"physics_ticks": ticks, "samples": samples, "reverse_seconds": float(reverse_ticks) / ticks, "assertions": assertions, "failures": failures}, "\t") + "\n")
	fixture.queue_free()
	await _frames(2)
	print("HADES_CONTROLS_RESULT assertions=%d failures=%d ticks=%d" % [assertions, failures, ticks])
	quit(0 if failures == 0 else 1)


func _direction_trial(label: String, axes: Vector2) -> void:
	await _reset()
	var start := player.global_position
	_set_axes(axes)
	var acceleration_ticks := 0
	while Vector2(player.velocity.x, player.velocity.z).length() < 5.199 and acceleration_ticks < ticks:
		await _frames(1)
		acceleration_ticks += 1
	await _frames(ticks / 4)
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var displacement := player.presentation.camera.unproject_position(player.global_position) - player.presentation.camera.unproject_position(start)
	_check(displacement.normalized().dot(axes.normalized()) > 0.96, label + " projects in the requested screen direction")
	_check(absf(speed - 5.2) < 0.01, label + " world speed remains 5.2 m/s")
	_check(float(acceleration_ticks) / ticks <= 0.105, label + " reaches full speed within 0.105 s")
	_set_axes(Vector2.ZERO)
	var stop_start := player.global_position
	var braking_ticks := 0
	while Vector2(player.velocity.x, player.velocity.z).length() > 0.001 and braking_ticks < ticks:
		await _frames(1)
		braking_ticks += 1
	_check(float(braking_ticks) / ticks <= 0.085, label + " stops within 0.085 s")
	_check(player.global_position.distance_to(stop_start) < 0.20, label + " stopping distance below 0.20 m")
	var sample := {"direction": label, "speed": speed, "acceleration_seconds": float(acceleration_ticks) / ticks, "braking_seconds": float(braking_ticks) / ticks, "stopping_distance": player.global_position.distance_to(stop_start)}
	samples.append(sample)
	print("METRIC ", JSON.stringify(sample))


func _reset() -> void:
	_release()
	await _frames(int(ticks * 0.5))
	player.global_position = Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
	await _frames(5)


func _set_axes(axes: Vector2) -> void:
	_release()
	if axes.x < 0: Input.action_press(&"move_left")
	if axes.x > 0: Input.action_press(&"move_right")
	if axes.y < 0: Input.action_press(&"move_forward")
	if axes.y > 0: Input.action_press(&"move_back")


func _release() -> void:
	for action in [&"move_left", &"move_right", &"move_forward", &"move_back", &"ability_slot_1"]:
		Input.action_release(action)


func _box(label: String, position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = position
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	fixture.add_child(body)
	return body


func _frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func _check(value: bool, label: String) -> void:
	assertions += 1
	print(("PASS " if value else "FAIL ") + label)
	if not value: failures += 1
