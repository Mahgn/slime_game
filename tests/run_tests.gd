extends SceneTree


const REQUIRED_SCENES: Array[String] = [
	"res://scenes/main.tscn",
	"res://scenes/levels/combat_lab.tscn",
	"res://scenes/player/slime_player.tscn",
]
const REQUIRED_SCRIPTS: Array[String] = [
	"res://scripts/main.gd",
	"res://scripts/levels/combat_lab.gd",
	"res://scripts/player/slime_controller.gd",
	"res://scripts/input_setup.gd",
]
const CONTENT_DIRS: Array[String] = ["res://scenes", "res://scripts", "res://data"]
const PLAYER_SCENE := "res://scenes/player/slime_player.tscn"
const SPITTER_SCENE := "res://scenes/enemies/spitter.tscn"
const SOURCE_SCENE := "res://scenes/interactables/absorb_source.tscn"
const PROJECTILE_SCENE := "res://scenes/abilities/spit_projectile.tscn"

var _failures := 0
var _finished := false
var _enemy_shots: Dictionary = {}
var _unlocks := 0
var _fixture_player_projectiles := 0
var _watchdog: Timer


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_watchdog = Timer.new()
	_watchdog.name = "TestWatchdog"
	_watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	_watchdog.one_shot = true
	_watchdog.wait_time = 120.0
	root.add_child(_watchdog)
	_watchdog.timeout.connect(_on_timeout)
	_watchdog.start()
	var t01 := await _test_t01()
	_report("T01", t01)
	if not t01.is_empty():
		print("NOT_RUN T02-T09B, T03A: T01 failed; physics fixtures cannot be trusted")
		call_deferred("_finish")
		return

	_report("T02", await _test_t02())
	_report("T03", await _test_t03())
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN T03A: captured mouse requires a window")
	else:
		_report("T03A", await _test_t03a_mouse_camera())
	_report("T04", await _test_t04())
	_report("T05", await _test_t05())
	_report("T06", await _test_t06())
	_report("T07", await _test_t07())
	_report("T08", await _test_t08())
	_report("T09", await _test_t09())
	_report("T09A", await _test_t09a())
	_report("T09B", await _test_t09b())
	_report("R02", await _test_r02_cycle())
	call_deferred("_finish")


func _on_timeout() -> void:
	if _finished:
		return
	print("FAIL TIMEOUT: test runner exceeded 120 seconds")
	_watchdog.free()
	quit(124)


func _finish() -> void:
	_finished = true
	_release_actions()
	paused = false
	_watchdog.stop()
	_watchdog.free()
	print("SUMMARY: %d failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _report(test_id: String, problem: String) -> void:
	if problem.is_empty():
		print("PASS %s" % test_id)
	else:
		_failures += 1
		print("FAIL %s: %s" % [test_id, problem])


func _test_t01() -> String:
	var problems := PackedStringArray()
	var paths: Array[String] = REQUIRED_SCENES + REQUIRED_SCRIPTS
	for directory in CONTENT_DIRS:
		_collect_resource_paths(directory, paths)
	paths.sort()
	var scene_paths: Array[String] = []
	for path in paths:
		var resource := load(path)
		if resource == null:
			problems.append("could not load %s" % path)
		elif path.ends_with(".tscn") and not resource is PackedScene:
			problems.append("not a PackedScene: %s" % path)
		elif path.ends_with(".gd") and not resource is Script:
			problems.append("not a Script: %s" % path)
		elif path.ends_with(".tscn"):
			scene_paths.append(path)
	if not problems.is_empty():
		return "; ".join(problems)

	for path in scene_paths:
		var scene := load(path) as PackedScene
		var instance := scene.instantiate()
		if instance == null:
			problems.append("could not instantiate %s" % path)
			continue
		root.add_child(instance)
		await _physics_steps(2)
		if path == "res://scenes/main.tscn":
			if not instance.get_node_or_null("SlimePlayer") is CharacterBody3D:
				problems.append("main scene has no working SlimePlayer")
		instance.queue_free()
		await _physics_steps(2)
	paused = false
	return "; ".join(problems)


func _test_t03a_mouse_camera() -> String:
	var main := _add_main_instance()
	await process_frame
	await process_frame
	var player := main.get_node("SlimePlayer") as SlimeController
	var initial_yaw := player.camera_yaw.rotation.y
	var initial_pitch := player.camera_pitch.rotation.x
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_send_mouse_motion(Vector2(100.0, -40.0))
	await process_frame
	var moved_yaw := player.camera_yaw.rotation.y
	var moved_pitch := player.camera_pitch.rotation.x

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_send_mouse_motion(Vector2(100.0, -40.0))
	await process_frame
	var visible_still := is_equal_approx(player.camera_yaw.rotation.y, moved_yaw) and is_equal_approx(player.camera_pitch.rotation.x, moved_pitch)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_send_pause_action()
	await process_frame
	var paused_now := paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
	_send_mouse_motion(Vector2(100.0, -40.0))
	await process_frame
	var paused_still := is_equal_approx(player.camera_yaw.rotation.y, moved_yaw) and is_equal_approx(player.camera_pitch.rotation.x, moved_pitch)
	_send_pause_action()
	await process_frame
	var resumed := not paused and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_send_mouse_motion(Vector2(100.0, -40.0))
	await process_frame
	var resumed_turn := absf(player.camera_yaw.rotation.y - moved_yaw) > 0.01
	print("T03A mouse: captured=%s yaw %.3f -> %.3f pitch %.3f -> %.3f visible-still=%s paused=%s paused-still=%s resumed=%s resumed-turn=%s" % [str(captured), initial_yaw, moved_yaw, initial_pitch, moved_pitch, str(visible_still), str(paused_now), str(paused_still), str(resumed), str(resumed_turn)])
	await _discard_fixture(main)
	if not captured:
		return "main scene did not capture the mouse"
	if absf(moved_yaw - initial_yaw) <= 0.01 or absf(moved_pitch - initial_pitch) <= 0.01:
		return "camera did not turn from mouse motion over the full-screen HUD"
	if not visible_still:
		return "camera turned while cursor was visible"
	if not paused_now or not paused_still:
		return "camera turned or mouse remained captured during pause"
	if not resumed or not resumed_turn:
		return "camera did not resume mouse turning after pause"
	return ""


func _collect_resource_paths(directory: String, paths: Array[String]) -> void:
	var access := DirAccess.open(directory)
	if access == null:
		return
	for filename in access.get_files():
		if filename.ends_with(".tscn") or filename.ends_with(".tres") or filename.ends_with(".gd"):
			var path := directory.path_join(filename)
			if not paths.has(path):
				paths.append(path)
	for child in access.get_directories():
		_collect_resource_paths(directory.path_join(child), paths)


func _test_t02() -> String:
	var straight: Dictionary = await _motion_trial(false)
	var diagonal: Dictionary = await _motion_trial(true)
	if not straight["grounded"] or not diagonal["grounded"]:
		return "player did not remain on the physical floor"
	var straight_full: float = straight["full"]
	var diagonal_full: float = diagonal["full"]
	var straight_steady: float = straight["steady"]
	var diagonal_steady: float = diagonal["steady"]
	if straight_full < 1.0 or diagonal_full < 1.0:
		return "movement was too small: straight=%.3f m, diagonal=%.3f m" % [straight_full, diagonal_full]
	var full_difference := absf(straight_full - diagonal_full) / straight_full
	var steady_difference := absf(straight_steady - diagonal_steady) / straight_steady
	print("T02 distances: 70 ticks straight=%.3f m diagonal=%.3f m; last 50 ticks straight=%.3f m diagonal=%.3f m" % [straight_full, diagonal_full, straight_steady, diagonal_steady])
	if full_difference > 0.08 or steady_difference > 0.03:
		return "diagonal speed bonus: full difference=%.1f%%, steady difference=%.1f%%" % [full_difference * 100.0, steady_difference * 100.0]
	return ""


func _motion_trial(diagonal: bool) -> Dictionary:
	var fixture := _make_fixture(Vector3(0.0, -0.2, 0.0), Vector3(30.0, 0.4, 30.0), Vector3(0.0, 0.05, 8.0))
	var player := fixture.get_node("SlimePlayer") as CharacterBody3D
	await _physics_steps(5)
	var initially_grounded := player.is_on_floor()
	var start := player.global_position
	Input.action_press(&"move_forward")
	if diagonal:
		Input.action_press(&"move_right")
	await _physics_steps(20)
	var warmup_end := player.global_position
	await _physics_steps(50)
	var end := player.global_position
	var grounded := initially_grounded and player.is_on_floor()
	var full_distance := Vector2(end.x - start.x, end.z - start.z).length()
	var steady_distance := Vector2(end.x - warmup_end.x, end.z - warmup_end.z).length()
	await _discard_fixture(fixture)
	return {"full": full_distance, "steady": steady_distance, "grounded": grounded}


func _test_t03() -> String:
	var problems := PackedStringArray()
	var jump_problem := await _jump_and_repeat_in_air()
	if not jump_problem.is_empty():
		problems.append(jump_problem)
	var coyote_now: Dictionary = await _edge_jump(0)
	var coyote_late: Dictionary = await _edge_jump(8)
	if not coyote_now["left_edge"] or not coyote_late["left_edge"]:
		problems.append("could not leave the physical ledge")
	else:
		if coyote_now["jump_velocity"] < 5.0:
			problems.append("jump immediately after leaving ledge did not use coyote time")
		if coyote_late["jump_velocity"] > 0.5:
			problems.append("jump remained available after coyote time expired")
	var buffer_problem := await _jump_buffer()
	if not buffer_problem.is_empty():
		problems.append(buffer_problem)
	return "; ".join(problems)


func _jump_and_repeat_in_air() -> String:
	var fixture := _make_fixture(Vector3(0.0, -0.2, 0.0), Vector3(20.0, 0.4, 20.0), Vector3(0.0, 0.05, 0.0))
	var player := fixture.get_node("SlimePlayer") as CharacterBody3D
	await _physics_steps(5)
	var grounded := player.is_on_floor()
	Input.action_press(&"jump")
	await _physics_steps(1)
	var first_velocity := player.velocity.y
	Input.action_release(&"jump")
	await _physics_steps(9)
	var before_repeat := player.velocity.y
	var in_air := not player.is_on_floor()
	Input.action_press(&"jump")
	await _physics_steps(1)
	var after_repeat := player.velocity.y
	Input.action_release(&"jump")
	await _physics_steps(55)
	var landed := player.is_on_floor()
	await _discard_fixture(fixture)
	print("T03 jump: first vy=%.3f, repeat vy %.3f -> %.3f, landed=%s" % [first_velocity, before_repeat, after_repeat, str(landed)])
	if not grounded or first_velocity < 5.0:
		return "ground jump did not produce the expected upward impulse"
	if not in_air or after_repeat > before_repeat + 0.5:
		return "airborne repeat produced an extra jump"
	if not landed:
		return "player did not return to the physical floor"
	return ""


func _edge_jump(delay_ticks: int) -> Dictionary:
	var fixture := _make_fixture(Vector3(-3.0, -0.2, 0.0), Vector3(6.0, 0.4, 8.0), Vector3(-0.75, 0.05, 0.0))
	var player := fixture.get_node("SlimePlayer") as CharacterBody3D
	await _physics_steps(5)
	Input.action_press(&"move_right")
	var ticks := 0
	while player.is_on_floor() and ticks < 45:
		await _physics_steps(1)
		ticks += 1
	Input.action_release(&"move_right")
	var left_edge := not player.is_on_floor() and ticks < 45
	await _physics_steps(delay_ticks)
	Input.action_press(&"jump")
	await _physics_steps(1)
	var jump_velocity := player.velocity.y
	Input.action_release(&"jump")
	await _discard_fixture(fixture)
	print("T03 ledge: delay=%d ticks, left=%s, jump vy=%.3f" % [delay_ticks, str(left_edge), jump_velocity])
	return {"left_edge": left_edge, "jump_velocity": jump_velocity}


func _jump_buffer() -> String:
	var fixture := _make_fixture(Vector3(0.0, -0.2, 0.0), Vector3(20.0, 0.4, 20.0), Vector3(0.0, 0.65, 0.0))
	var player := fixture.get_node("SlimePlayer") as CharacterBody3D
	await _physics_steps(1)
	var ticks := 0
	while player.global_position.y > 0.40 and not player.is_on_floor() and ticks < 45:
		await _physics_steps(1)
		ticks += 1
	var airborne := not player.is_on_floor()
	Input.action_press(&"jump")
	await _physics_steps(1)
	Input.action_release(&"jump")
	var buffered_jump := false
	for i in range(15):
		await _physics_steps(1)
		if player.velocity.y > 5.0:
			buffered_jump = true
			break
	await _discard_fixture(fixture)
	print("T03 buffer: early press airborne=%s, triggered=%s" % [str(airborne), str(buffered_jump)])
	if not airborne:
		return "buffer test was already grounded at early press"
	if not buffered_jump:
		return "early jump press shortly before landing was not buffered"
	return ""


func _test_t04() -> String:
	var fixture := _make_fixture(Vector3(0.0, -0.2, 0.0), Vector3(20.0, 0.4, 20.0), Vector3.ZERO)
	var player := fixture.get_node("SlimePlayer") as SlimeController
	var enemy := _add_enemy(fixture, Vector3(0.0, 0.0, -1.5))
	await _physics_steps(5)
	if not player.request_action(&"slime_whip"):
		await _discard_fixture(fixture)
		return "first whip did not start"
	await _physics_steps(9)
	var after_first := enemy.health
	player.call("_do_whip_hit")
	player.call("_do_whip_hit")
	var after_rechecks := enemy.health
	await _physics_steps(30)
	var second_started := player.request_action(&"slime_whip")
	await _physics_steps(9)
	var after_second := enemy.health
	await _discard_fixture(fixture)
	print("T04 HP: first=%d, repeated checks=%d, second cast=%d" % [after_first, after_rechecks, after_second])
	if after_first != 20 or after_rechecks != 20:
		return "same whip cast did not apply exactly 10 damage once"
	if not second_started or after_second != 10:
		return "a new whip cast did not apply a separate 10 damage"
	return ""


func _test_t05() -> String:
	var fixture := _make_fixture(Vector3(0.0, -0.2, 0.0), Vector3(20.0, 0.4, 20.0), Vector3.ZERO)
	var player := fixture.get_node("SlimePlayer") as SlimeController
	var enemy := _add_enemy(fixture, Vector3(0.0, 0.0, -1.7))
	_add_wall(fixture, Vector3(0.0, 1.0, -0.85), Vector3(2.0, 2.0, 0.2))
	await _physics_steps(5)
	player.request_action(&"slime_whip")
	await _physics_steps(10)
	var after_whip := enemy.health
	var projectile := _add_projectile(fixture, player, Vector3(0.0, 0.65, -0.5), Vector3.FORWARD, "wall_projectile")
	await _physics_steps(12)
	var after_projectile := enemy.health
	var projectile_gone := not is_instance_valid(projectile)
	await _discard_fixture(fixture)
	print("T05 HP behind wall: whip=%d, projectile=%d, projectile resolved=%s" % [after_whip, after_projectile, str(projectile_gone)])
	if after_whip != 30 or after_projectile != 30:
		return "wall did not block whip or projectile damage"
	if not projectile_gone:
		return "projectile did not terminate on the wall"
	return ""


func _test_t06() -> String:
	_enemy_shots.clear()
	var fixture := _make_fixture(Vector3(0.0, -0.2, 0.0), Vector3(20.0, 0.4, 20.0), Vector3.ZERO)
	var player := fixture.get_node("SlimePlayer") as SlimeController
	var first := _add_enemy(fixture, Vector3(-2.0, 0.0, -5.0))
	var second := _add_enemy(fixture, Vector3(2.0, 0.0, -5.0))
	first.projectile_requested.connect(_record_enemy_projectile)
	second.projectile_requested.connect(_record_enemy_projectile)
	var first_id := first.get_instance_id()
	var second_id := second.get_instance_id()
	await _physics_steps(5)
	first.player_target = player
	await _physics_steps(47)
	var first_phase := first.get_attack_phase()
	var second_phase := second.get_attack_phase()
	var first_count := int(_enemy_shots.get(first_id, 0))
	second.player_target = player
	await _physics_steps(1)
	var second_started := second.get_attack_phase()
	await _physics_steps(47)
	var final_first_count := int(_enemy_shots.get(first_id, 0))
	var final_second_count := int(_enemy_shots.get(second_id, 0))
	await _discard_fixture(fixture)
	print("T06 independent phases: first=%s second=%s then second=%s; shots=%d/%d" % [first_phase, second_phase, second_started, final_first_count, final_second_count])
	if first_phase != &"recovery" or second_phase != &"idle" or first_count != 1:
		return "first enemy's attack phase leaked to the idle second enemy"
	if second_started != &"windup" or final_first_count != 1 or final_second_count != 1:
		return "second enemy could not run its own attack and cooldown"
	return ""


func _test_t07() -> String:
	_unlocks = 0
	var fixture := _make_fixture(Vector3(0.0, -0.2, 0.0), Vector3(20.0, 0.4, 20.0), Vector3.ZERO)
	var player := fixture.get_node("SlimePlayer") as SlimeController
	var source := _add_source(fixture, Vector3(0.0, 0.0, -1.0))
	player.ability_unlocked.connect(_record_unlock)
	await _physics_steps(5)
	Input.action_press(&"interact")
	await _physics_steps(20)
	var early_ability := player.equipped_ability
	Input.action_press(&"move_right")
	await _physics_steps(1)
	Input.action_release(&"move_right")
	await _physics_steps(40)
	var interrupted_ability := player.equipped_ability
	Input.action_release(&"interact")
	await _physics_steps(2)
	Input.action_press(&"interact")
	await _physics_steps(36)
	Input.action_release(&"interact")
	var final_ability := player.equipped_ability
	var claimed := source.is_claimed()
	var second_claim := source.claim()
	var grants := _unlocks
	await _discard_fixture(fixture)
	print("T07 absorb: early=%s interrupted=%s final=%s claimed=%s duplicate=%s unlocks=%d" % [early_ability, interrupted_ability, final_ability, str(claimed), str(second_claim), grants])
	if early_ability != &"" or interrupted_ability != &"":
		return "interrupted hold granted the ability"
	if final_ability != &"sticky_spit" or not claimed:
		return "completed hold did not atomically grant sticky_spit and claim the source"
	if second_claim or grants != 1:
		return "the source granted the ability more than once"
	return ""


func _test_t08() -> String:
	_enemy_shots.clear()
	var fixture := _make_fixture(Vector3(0.0, -0.2, 0.0), Vector3(20.0, 0.4, 20.0), Vector3.ZERO)
	var player := fixture.get_node("SlimePlayer") as SlimeController
	var enemy := _add_enemy(fixture, Vector3(0.0, 0.0, -5.0))
	enemy.projectile_requested.connect(_record_enemy_projectile)
	var enemy_id := enemy.get_instance_id()
	await _physics_steps(55)
	var no_target_idle := enemy.get_attack_phase() == &"idle" and int(_enemy_shots.get(enemy_id, 0)) == 0
	enemy.player_target = player
	await _physics_steps(5)
	var was_winding_up := enemy.get_attack_phase() == &"windup"
	player.queue_free()
	await _physics_steps(55)
	var after_target_removed := int(_enemy_shots.get(enemy_id, 0))
	await _discard_fixture(fixture)

	_enemy_shots.clear()
	fixture = _make_fixture(Vector3(0.0, -0.2, 0.0), Vector3(20.0, 0.4, 20.0), Vector3.ZERO)
	player = fixture.get_node("SlimePlayer") as SlimeController
	enemy = _add_enemy(fixture, Vector3(0.0, 0.0, -5.0), player)
	enemy.projectile_requested.connect(_record_enemy_projectile)
	enemy_id = enemy.get_instance_id()
	await _physics_steps(5)
	var owner_winding_up := enemy.get_attack_phase() == &"windup"
	var lethal_hit := enemy.receive_hit(30, "owner_death", &"player")
	await _physics_steps(55)
	var after_owner_death := int(_enemy_shots.get(enemy_id, 0))
	await _discard_fixture(fixture)
	print("T08 no target=%s, target removed during windup shots=%d, owner dead=%s shots=%d" % [str(no_target_idle), after_target_removed, str(lethal_hit), after_owner_death])
	if not no_target_idle or not was_winding_up or after_target_removed != 0:
		return "missing or removed target caused a delayed attack"
	if not owner_winding_up or not lethal_hit or after_owner_death != 0:
		return "dead owner caused a delayed attack"
	return ""


func _test_t09() -> String:
	var scene := load("res://scenes/main.tscn") as PackedScene
	if change_scene_to_packed(scene) != OK:
		return "could not open main scene as current_scene"
	await _physics_steps(3)
	var problem := ""
	for iteration in range(10):
		var old_main := current_scene
		if not is_instance_valid(old_main):
			problem = "main scene missing before restart %d" % iteration
			break
		var player := old_main.get_node("SlimePlayer") as SlimeController
		var first_enemy := old_main.get("first_enemy") as Spitter
		player.grant_ability(&"sticky_spit")
		first_enemy.apply_sticky(0.55, 3.0)
		old_main.call("_add_projectile", first_enemy, &"enemy", Vector3(3.0, 1.0, -6.0), Vector3.FORWARD, 8, 9.0, 18.0, "restart_%d" % iteration, 1.0, 0.0)
		if not player.receive_hit(100, "death_%d" % iteration, &"enemy"):
			problem = "could not enter death state before restart %d" % iteration
			break
		_send_restart_key()
		await _physics_steps(4)
		var fresh := current_scene
		if not is_instance_valid(fresh) or fresh == old_main:
			problem = "scene did not reload on repeat %d" % iteration
			break
		var fresh_player := fresh.get_node("SlimePlayer") as SlimeController
		var fresh_enemy := fresh.get("first_enemy") as Spitter
		if fresh_player.health != 100 or fresh_player.equipped_ability != &"" or not is_instance_valid(fresh_enemy) or not fresh_enemy.is_alive():
			problem = "HP, slot, or first enemy not reset on repeat %d" % iteration
			break
		if fresh.get("stage") != &"first_fight" or paused:
			problem = "room stage or pause state not reset on repeat %d" % iteration
			break
		if get_nodes_in_group(&"enemies").size() != 1 or not get_nodes_in_group(&"projectiles").is_empty() or not get_nodes_in_group(&"absorb_sources").is_empty():
			problem = "old enemies, projectiles, or sources survived repeat %d" % iteration
			break
	unload_current_scene()
	await _physics_steps(2)
	print("T09 restart loop: %s" % ("10 clean repeats" if problem.is_empty() else problem))
	return problem


func _test_t09a() -> String:
	_fixture_player_projectiles = 0
	var fixture := _make_fixture(Vector3(0.0, -0.2, 0.0), Vector3(30.0, 0.4, 30.0), Vector3.ZERO)
	var player := fixture.get_node("SlimePlayer") as SlimeController
	var source := _add_source(fixture, Vector3(0.0, 0.0, -1.0))
	var enemy := _add_enemy(fixture, Vector3(0.0, 0.0, -5.0))
	player.projectile_requested.connect(_on_fixture_player_projectile.bind(player, fixture))
	await _physics_steps(5)
	player.camera_pitch.rotation.x = 0.0
	var unavailable_before := not player.request_action(&"sticky_spit") and player.cooldown_remaining(&"sticky_spit") == 0.0
	Input.action_press(&"interact")
	await _physics_steps(36)
	Input.action_release(&"interact")
	await _physics_steps(2)
	var absorbed := player.equipped_ability == &"sticky_spit" and source.is_claimed()
	var first_started := player.request_action(&"sticky_spit")
	await _physics_steps(45)
	var first_hp := enemy.health
	var slow_speed := enemy.current_move_speed()
	var sticky_left := enemy.get_sticky_time_left()
	var cooldown_left := player.cooldown_remaining(&"sticky_spit")
	var blocked_during_cooldown := not player.request_action(&"sticky_spit")
	var wait_ticks := 0
	while player.cooldown_remaining(&"sticky_spit") > 0.0 and wait_ticks < 180:
		await _physics_steps(1)
		wait_ticks += 1
	var second_started := player.request_action(&"sticky_spit")
	await _physics_steps(45)
	var second_hp := enemy.health
	await _physics_steps(200)
	var restored_speed := enemy.current_move_speed()
	var final_sticky_left := enemy.get_sticky_time_left()
	var shots := _fixture_player_projectiles
	await _discard_fixture(fixture)
	print("T09A spit: first HP=%d speed=%.3f sticky=%.2f cd=%.2f; second HP=%d shots=%d; restored speed=%.3f" % [first_hp, slow_speed, sticky_left, cooldown_left, second_hp, shots, restored_speed])
	if not unavailable_before or not absorbed or not first_started:
		return "sticky_spit availability or absorption failed"
	if first_hp != 18 or not is_equal_approx(slow_speed, 1.375) or sticky_left <= 0.0:
		return "first spit did not deal 12 damage once and apply 55% speed for 3 seconds"
	if cooldown_left <= 0.0 or not blocked_during_cooldown or wait_ticks >= 180 or not second_started:
		return "2.5-second owner cooldown did not block and then allow a new cast"
	if second_hp != 6 or shots != 2:
		return "second spit did not produce one separate 12-damage hit"
	if not is_equal_approx(restored_speed, 2.5) or final_sticky_left > 0.0:
		return "sticky movement did not return to normal after its duration"
	return ""


func _test_t09b() -> String:
	_enemy_shots.clear()
	var main := _add_main_instance()
	await _physics_steps(5)
	var player := main.get_node("SlimePlayer") as SlimeController
	var enemy := main.get("first_enemy") as Spitter
	enemy.projectile_requested.connect(_record_enemy_projectile)
	var enemy_id := enemy.get_instance_id()
	player.grant_ability(&"sticky_spit")
	enemy.apply_sticky(0.55, 3.0)
	player.request_action(&"sticky_spit")
	await _physics_steps(13)
	var projectile := main.call("_add_projectile", enemy, &"enemy", Vector3(3.0, 1.0, 0.0), Vector3.BACK, 8, 9.0, 18.0, "pause_flight", 1.0, 0.0) as SpitProjectile
	await _physics_steps(1)
	_send_pause_action()
	await _physics_steps(1)
	var pause_entered := paused
	var position_before := projectile.global_position
	var cooldown_before := player.cooldown_remaining(&"sticky_spit")
	var sticky_before := enemy.get_sticky_time_left()
	var phase_before := enemy.get_attack_phase()
	await _physics_steps(60)
	var frozen := is_instance_valid(projectile) and projectile.global_position.distance_to(position_before) < 0.001
	frozen = frozen and absf(player.cooldown_remaining(&"sticky_spit") - cooldown_before) < 0.001
	frozen = frozen and absf(enemy.get_sticky_time_left() - sticky_before) < 0.001 and enemy.get_attack_phase() == phase_before
	_send_pause_action()
	await _physics_steps(1)
	await _physics_steps(40)
	var resumed := not paused and is_instance_valid(projectile) and projectile.global_position.distance_to(position_before) > 1.0
	var enemy_shots_after_resume := int(_enemy_shots.get(enemy_id, 0))
	var cooldown_resumed := player.cooldown_remaining(&"sticky_spit") < cooldown_before
	var sticky_resumed := enemy.get_sticky_time_left() < sticky_before
	await _discard_fixture(main)

	main = _add_main_instance()
	await _physics_steps(3)
	player = main.get_node("SlimePlayer") as SlimeController
	enemy = main.get("first_enemy") as Spitter
	enemy.receive_hit(30, "pause_source", &"player")
	player.global_position = Vector3(0.0, 0.05, 1.1)
	player.velocity = Vector3.ZERO
	await _physics_steps(5)
	var source := main.get("first_source") as AbsorbSource
	Input.action_press(&"interact")
	await _physics_steps(20)
	var early_unlocked := player.equipped_ability != &""
	_send_pause_action()
	await _physics_steps(1)
	var absorb_paused := paused
	await _physics_steps(45)
	_send_pause_action()
	await _physics_steps(1)
	await _physics_steps(25)
	var continued_hold_unlocked := player.equipped_ability != &"" or source.is_claimed()
	Input.action_release(&"interact")
	await _physics_steps(2)
	Input.action_press(&"interact")
	await _physics_steps(36)
	var fresh_hold_unlocked := player.equipped_ability == &"sticky_spit" and source.is_claimed()
	await _discard_fixture(main)
	print("T09B pause: entered=%s frozen=%s resumed=%s shots=%d cd/status resumed=%s/%s; absorb paused=%s continued=%s fresh=%s" % [str(pause_entered), str(frozen), str(resumed), enemy_shots_after_resume, str(cooldown_resumed), str(sticky_resumed), str(absorb_paused), str(continued_hold_unlocked), str(fresh_hold_unlocked)])
	if phase_before != &"windup" or cooldown_before <= 0.0 or sticky_before <= 0.0:
		return "pause fixture did not reach windup, cooldown, and sticky status"
	if not pause_entered or not frozen or not resumed or enemy_shots_after_resume != 1 or not cooldown_resumed or not sticky_resumed:
		return "windup, projectile, cooldown, or sticky status advanced during pause or failed after resume"
	if early_unlocked or not absorb_paused or continued_hold_unlocked or not fresh_hold_unlocked:
		return "pause did not reset E hold and require a fresh press"
	return ""


func _test_r02_cycle() -> String:
	_enemy_shots.clear()
	var main := _add_main_instance()
	var player := main.get_node("SlimePlayer") as SlimeController
	var first := main.get("first_enemy") as Spitter
	first.projectile_requested.connect(_record_enemy_projectile)
	var first_id := first.get_instance_id()
	await _physics_steps(55)
	var first_shots := int(_enemy_shots.get(first_id, 0))
	first.player_target = null
	player.global_position = Vector3(0.0, 0.05, 1.55)
	player.velocity = Vector3.ZERO
	await _physics_steps(3)
	var whip_actions := 0
	for cast in range(3):
		if player.request_action(&"slime_whip"):
			whip_actions += 1
		await _physics_steps(36)
	var first_killed: bool = main.get("stage") == &"absorb" and not is_instance_valid(first)
	var source := main.get("first_source") as AbsorbSource
	var stray_wait := 0
	while not get_nodes_in_group(&"enemy_projectiles").is_empty() and stray_wait < 160:
		await _physics_steps(1)
		stray_wait += 1
	player.global_position = Vector3(0.0, 0.05, 1.1)
	player.velocity = Vector3.ZERO
	await _physics_steps(4)
	Input.action_press(&"interact")
	await _physics_steps(36)
	Input.action_release(&"interact")
	var absorbed := player.equipped_ability == &"sticky_spit" and is_instance_valid(source) and source.is_claimed()
	player.global_position = Vector3(0.0, 0.05, -3.0)
	player.velocity = Vector3.ZERO
	var spawn_wait := 0
	while not is_instance_valid(main.get("second_enemy")) and spawn_wait < 180:
		await _physics_steps(1)
		spawn_wait += 1
	var second := main.get("second_enemy") as Spitter
	var second_spawned: bool = is_instance_valid(second) and main.get("stage") == &"second_fight"
	var second_hp_after_spit := -1
	var completed := false
	if second_spawned:
		second.player_target = null
		var toward_second := second.global_position - player.global_position
		toward_second.y = 0.0
		player.camera_yaw.rotation.y = atan2(-toward_second.x, -toward_second.z)
		player.camera_pitch.rotation.x = 0.0
		await _physics_steps(3)
		player.request_action(&"sticky_spit")
		await _physics_steps(55)
		second_hp_after_spit = second.health
		var from_enemy := player.global_position - second.global_position
		from_enemy.y = 0.0
		player.global_position = second.global_position + from_enemy.normalized() * 1.5
		player.velocity = Vector3.ZERO
		await _physics_steps(4)
		for cast in range(2):
			player.request_action(&"slime_whip")
			await _physics_steps(36)
		completed = main.get("stage") == &"complete" and paused
	await _discard_fixture(main)
	print("R02 full loop: enemy shots=%d whips=%d first killed=%s source=%s second spawn=%s second HP after spit=%d complete=%s" % [first_shots, whip_actions, str(first_killed), str(absorbed), str(second_spawned), second_hp_after_spit, str(completed)])
	if first_shots < 1 or whip_actions != 3 or not first_killed:
		return "first enemy did not show its shot and die to three real whips"
	if stray_wait >= 160 or not absorbed:
		return "old projectiles did not resolve or the source was not absorbed"
	if not second_spawned or second_hp_after_spit != 18:
		return "second enemy did not spawn after safe window or take 12 spit damage"
	if not completed:
		return "second enemy was not defeated and room did not complete"
	return ""


func _add_main_instance() -> Node3D:
	var scene := load("res://scenes/main.tscn") as PackedScene
	var main := scene.instantiate() as Node3D
	root.add_child(main)
	return main


func _send_restart_key() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_R
	event.pressed = true
	Input.parse_input_event(event)
	event = InputEventKey.new()
	event.physical_keycode = KEY_R
	event.pressed = false
	Input.parse_input_event(event)


func _send_pause_action() -> void:
	var event := InputEventAction.new()
	event.action = &"pause"
	event.pressed = true
	Input.parse_input_event(event)
	event = InputEventAction.new()
	event.action = &"pause"
	event.pressed = false
	Input.parse_input_event(event)


func _send_mouse_motion(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = Vector2(root.size) * 0.5
	event.global_position = event.position
	event.relative = relative
	event.screen_relative = relative
	Input.parse_input_event(event)


func _on_fixture_player_projectile(origin: Vector3, direction: Vector3, damage: int, speed: float, max_range: float, cast_key: String, slow_factor: float, slow_seconds: float, owner: SlimeController, fixture: Node3D) -> void:
	_fixture_player_projectiles += 1
	var scene := load(PROJECTILE_SCENE) as PackedScene
	var projectile := scene.instantiate() as SpitProjectile
	projectile.configure(owner, &"player", direction, speed, damage, max_range, cast_key, slow_factor, slow_seconds)
	fixture.add_child(projectile)
	projectile.global_position = origin


func _record_enemy_projectile(source: Spitter, _origin: Vector3, _direction: Vector3, _damage: int, _speed: float, _max_range: float, _cast_key: String) -> void:
	var key := source.get_instance_id()
	_enemy_shots[key] = int(_enemy_shots.get(key, 0)) + 1


func _record_unlock(_ability_id: StringName) -> void:
	_unlocks += 1


func _add_enemy(fixture: Node3D, position: Vector3, target: Node3D = null) -> Spitter:
	var scene := load(SPITTER_SCENE) as PackedScene
	var enemy := scene.instantiate() as Spitter
	enemy.position = position
	enemy.player_target = target
	fixture.add_child(enemy)
	return enemy


func _add_source(fixture: Node3D, position: Vector3) -> AbsorbSource:
	var scene := load(SOURCE_SCENE) as PackedScene
	var source := scene.instantiate() as AbsorbSource
	source.position = position
	fixture.add_child(source)
	return source


func _add_projectile(fixture: Node3D, owner: CollisionObject3D, position: Vector3, direction: Vector3, cast_key: String) -> SpitProjectile:
	var scene := load(PROJECTILE_SCENE) as PackedScene
	var projectile := scene.instantiate() as SpitProjectile
	projectile.position = position
	projectile.configure(owner, &"player", direction, 14.0, 12, 18.0, cast_key, 0.55, 3.0)
	fixture.add_child(projectile)
	return projectile


func _add_wall(fixture: Node3D, center: Vector3, size: Vector3) -> void:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.position = center
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	wall.add_child(collider)
	fixture.add_child(wall)


func _make_fixture(floor_center: Vector3, floor_size: Vector3, spawn: Vector3) -> Node3D:
	var fixture := Node3D.new()
	fixture.name = "S1PhysicsFixture"
	var floor := StaticBody3D.new()
	floor.name = "Floor"
	floor.collision_layer = 1
	floor.collision_mask = 0
	floor.position = floor_center
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = floor_size
	collision.shape = shape
	floor.add_child(collision)
	fixture.add_child(floor)
	var player_scene := load(PLAYER_SCENE) as PackedScene
	var player := player_scene.instantiate() as CharacterBody3D
	player.name = "SlimePlayer"
	player.position = spawn
	fixture.add_child(player)
	root.add_child(fixture)
	return fixture


func _discard_fixture(fixture: Node) -> void:
	_release_actions()
	paused = false
	fixture.queue_free()
	await _physics_steps(2)


func _release_actions() -> void:
	for action in [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"interact", &"attack_primary", &"ability_slot_1"]:
		Input.action_release(action)


func _physics_steps(count: int) -> void:
	for i in range(count):
		await create_timer(0.0, true, true).timeout
