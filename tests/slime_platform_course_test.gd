extends SceneTree

const COURSE_SCENE = preload("res://scenes/art_review/slime_platform_course.tscn")
const PRESS_PERIOD := 2.2

var _failed := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var course := COURSE_SCENE.instantiate()
	root.add_child(course)
	await _steps(5)
	var player: SlimeController = course.player
	var wall: FragileWall = course._fragile_wall
	_check("C01_TWO_ABILITIES", player.get_slot_ability(1) == &"sticky_spit" and player.get_slot_ability(2) == &"slime_spikes" and player.unlocked_slots == 2)
	player.global_position = Vector3(0.0, 0.05, 14.0)
	await _steps(4)
	var hit_count := 0
	for hit in 3:
		if player.request_action(&"slime_whip"):
			hit_count += 1
		await _steps(52)
	_check("C02_WHIP_WALL", hit_count == 3 and not is_instance_valid(wall))
	player.global_position = Vector3(0.0, 0.05, 11.35)
	player.velocity = Vector3.ZERO
	await _steps(5)
	Input.action_press(&"move_forward")
	var compressed_inside := false
	for tick in 110:
		await _steps(1)
		if player.global_position.z < 11.0 and player.global_position.z > 8.0:
			compressed_inside = compressed_inside or player.is_compressed()
		if player.global_position.z < 6.1:
			break
	Input.action_release(&"move_forward")
	await _steps(12)
	_check("C03_WALL_HOLE", compressed_inside and player.global_position.z < 6.2 and not player.is_compressed())
	var health_before := player.health
	player.global_position = Vector3(0.0, -1.3, 2.2)
	player.velocity = Vector3.ZERO
	await _steps(2)
	_check("C04_PIT", player.health == health_before - 10 and player.global_position.z > 5.0)
	player.global_position = Vector3(0.0, 0.05, -13.15)
	player.velocity = Vector3.ZERO
	await _steps(5)
	var target: Node3D = course.get_node("StickyMechanism")
	course._press_motion_time = PRESS_PERIOD * 0.65
	await _steps(1)
	var low_before: float = course._press_beam.position.y
	_shoot_target(course, player, target, "course_test:sticky_spit_low")
	await _steps(20)
	var low_frozen: float = course._press_beam.position.y
	await _steps(25)
	_check("C05_LOW_IMPACT_FREEZES_IN_PLACE", course._press_frozen_left > 0.0 and low_before < 1.0 and absf(low_frozen - course._press_beam.position.y) < 0.001 and absf(low_frozen - course._frozen_height) < 0.001)
	health_before = player.health
	Input.action_press(&"jump")
	await _steps(42)
	Input.action_release(&"jump")
	Input.action_press(&"move_forward")
	for tick in 100:
		await _steps(1)
		if player.health < health_before:
			break
	Input.action_release(&"move_forward")
	_check("C06_LOW_PRESS_CANNOT_BE_JUMPED", player.health == health_before - 15 and player.global_position.z > course.TRAP_Z + 1.0)
	await _steps(245)
	_check("C07_PRESS_RESUMES", course._press_frozen_left <= 0.0 and absf(course._press_beam.position.y - low_frozen) > 0.05)
	course._press_motion_time = PRESS_PERIOD * 0.15
	await _steps(1)
	var high_before: float = course._press_beam.position.y
	_shoot_target(course, player, target, "course_test:sticky_spit_high")
	await _steps(20)
	var high_frozen: float = course._press_beam.position.y
	await _steps(25)
	_check("C08_HIGH_IMPACT_FREEZES_IN_PLACE", course._press_frozen_left > 0.0 and high_before > 2.3 and absf(high_frozen - course._press_beam.position.y) < 0.001 and absf(high_frozen - course._frozen_height) < 0.001)
	health_before = player.health
	Input.action_press(&"move_forward")
	for tick in 125:
		await _steps(1)
		if player.global_position.z < course.TRAP_Z - 1.0:
			break
	Input.action_release(&"move_forward")
	_check("C09_HIGH_PRESS_PASSABLE", player.global_position.z < course.TRAP_Z - 1.0 and player.health == health_before and course._press_frozen_left > 0.0)
	player.global_position = Vector3(0.0, 0.05, -17.65)
	player.velocity = Vector3.ZERO
	await _steps(5)
	var enemy: Spitter = course._course_enemy
	_check("C10_ONE_ENEMY", is_instance_valid(enemy) and get_nodes_in_group(&"enemies").size() == 1)
	if is_instance_valid(enemy):
		var enemy_health := enemy.health
		var started := player.request_action(&"slime_spikes")
		await _steps(25)
		_check("C11_SPIKES_COMBAT", started and is_instance_valid(enemy) and enemy.health < enemy_health)
		if is_instance_valid(enemy):
			enemy.receive_hit(30, "course_test:whip", &"player")
			await _steps(2)
	_check("C12_FINISH", course.stage == &"complete")
	print("SUMMARY: %d failed" % _failed)
	quit(1 if _failed > 0 else 0)

func _shoot_target(course: Node, player: SlimeController, target: Node3D, cast_key: String) -> void:
	var origin := player.global_position + Vector3.UP * 0.7
	var direction := (target.global_position - origin).normalized()
	course._on_player_projectile(origin, direction, 12, 12.0, 18.0, cast_key, 0.5, 2.0)

func _steps(count: int) -> void:
	for tick in count:
		await physics_frame

func _check(label: String, condition: bool) -> void:
	if condition:
		print("PASS %s" % label)
	else:
		_failed += 1
		print("FAIL %s" % label)

