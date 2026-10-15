extends SceneTree

# Damage confirmation must follow actual HP loss, never an attack request or
# a projectile merely resolving against a mechanism. Headless checks do not
# establish whether the effect looks or sounds good.
const PLAYER_SCENE := preload("res://scenes/player/slime_player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemies/spitter.tscn")
const INPUT_SETUP := preload("res://scripts/input_setup.gd")
const OUTPUT := "res://output/combat_juice_2026_10_14/"
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var level: SlimeKeepersWorld
var original_time_scale := 1.0
var done := false


func _initialize() -> void:
	original_time_scale = Engine.time_scale
	call_deferred("_run")


func _run() -> void:
	INPUT_SETUP.install()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	SlimeGameSettings.current().load_settings(OUTPUT + "impact-test-settings.cfg")
	create_timer(90.0, true, false, true).timeout.connect(func() -> void:
		_check(false, "watchdog: focused impact tests finish within 90 seconds")
		_finish())
	await _test_damage_contracts()
	await _test_dungeon_pipeline()
	_finish()


func _test_damage_contracts() -> void:
	var fixture := Node3D.new()
	fixture.name = "ImpactFixture"
	root.add_child(fixture)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.position.y = -0.2
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30.0, 0.4, 30.0)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	fixture.add_child(floor_body)
	var hero := PLAYER_SCENE.instantiate() as SlimeController
	fixture.add_child(hero)
	var combat := SlimeCombatRuntime.new()
	fixture.add_child(combat)
	combat.bind_player(hero)
	var feedback: Node = combat.get("feedback")
	_check(is_instance_valid(feedback), "binding hero creates feedback owned by combat runtime")
	if not is_instance_valid(feedback):
		fixture.queue_free()
		await process_frame
		return
	var enemy := ENEMY_SCENE.instantiate() as Spitter
	enemy.position = Vector3(0.0, 0.0, -1.2)
	fixture.add_child(enemy)
	enemy.set_physics_process(false)
	combat.bind_enemy(enemy)
	var events: Array[Dictionary] = []
	enemy.impact_received.connect(func(at: Vector3, lethal: bool) -> void: events.append({"at": at, "lethal": lethal}))
	await _frames(6)
	hero.set_physics_process(false)
	hero._action_direction = Vector3.FORWARD
	hero._cast_key = "impact-real-whip"
	var before := _count(feedback)
	hero._do_whip_hit()
	_check(enemy.health == 20 and _count(feedback) == before + 1, "real whip applies unchanged 10 damage and exactly one impact")
	_check(events.size() == 1 and not events[0].lethal and events[0].at.is_finite(), "enemy signal identifies nonlethal impact at a finite position")
	hero._do_whip_hit()
	_check(enemy.health == 20 and _count(feedback) == before + 1, "repeated active whip frame cannot duplicate damage or impact")
	before = _count(feedback)
	_check(not enemy.receive_hit(1, "wrong-team", &"enemy") and not enemy.receive_hit(0, "zero", &"player") and not enemy.receive_hit(1, "", &"player"), "wrong team, zero damage and empty cast are rejected")
	_check(_count(feedback) == before and events.size() == 1, "rejected hits emit neither enemy signal nor damage feedback")
	enemy.position = Vector3(0.0, 0.0, -5.0)
	hero._cast_key = "impact-miss"
	hero._do_whip_hit()
	_check(_count(feedback) == before and enemy.health == 20, "out-of-range whip miss has no damage feedback")
	enemy.position.z = -1.6
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.position = Vector3(0.0, 1.0, -0.8)
	var wall_collider := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(4.0, 2.0, 0.2)
	wall_collider.shape = wall_box
	wall.add_child(wall_collider)
	fixture.add_child(wall)
	await _frames(2)
	hero._cast_key = "impact-wall"
	hero._do_whip_hit()
	_check(_count(feedback) == before and enemy.health == 20, "physical wall blocks both whip damage and its impact")
	wall.queue_free()
	var armorer := BorrowableEnemy.new()
	armorer.position = Vector3(5.0, 0.0, 0.0)
	fixture.add_child(armorer)
	armorer.set_physics_process(false)
	combat.bind_enemy(armorer)
	armorer._set_phase(&"shell", 1.0)
	_check(armorer.receive_hit(10, "guard-block", &"player") and armorer.health == 40, "armorer accepts shell contact without losing HP")
	_check(_count(feedback) == before, "fully absorbed shell contact has no damage impact")
	armorer.receive_hit(5, "guard-open", &"player")
	_check(armorer.health == 35 and _count(feedback) == before + 1, "armorer HP loss emits one impact after shell is consumed")
	var guardian := ExitGuardian.new()
	guardian.position = Vector3(-5.0, 0.0, 0.0)
	fixture.add_child(guardian)
	guardian.set_physics_process(false)
	combat.bind_enemy(guardian)
	before = _count(feedback)
	guardian.receive_hit(4, "guardian-impact", &"player")
	guardian.receive_hit(4, "guardian-impact", &"player")
	_check(guardian.health == 176 and _count(feedback) == before + 1, "guardian emits one impact for one accepted cast")
	before = _count(feedback)
	enemy.receive_hit(999, "impact-lethal", &"player")
	_check(events.size() == 2 and events[1].lethal and _count(feedback) == before + 1, "lethal hit emits one lethal confirmation before enemy cleanup")
	_check(not enemy.receive_hit(1, "after-death", &"player") and _count(feedback) == before + 1, "dead enemy cannot confirm another impact")
	before = _count(feedback)
	hero._action = &"elastic_shell"
	hero._phase = &"guard"
	_check(hero.receive_hit(10, "hero-block", &"enemy") and hero.health == 100 and _count(feedback) == before, "player guard without HP loss does not trigger damage feedback")
	hero._action = &""
	hero._phase = &""
	hero.receive_hit(5, "hero-damage", &"enemy", Vector3.RIGHT)
	hero.receive_hit(5, "hero-damage", &"enemy", Vector3.RIGHT)
	_check(hero.health == 95 and _count(feedback) == before + 1, "player damage and duplicate rejection use actual HP loss")
	await _wait_wall(0.35)
	_check(not feedback.call("hitstop_active") and is_equal_approx(Engine.time_scale, original_time_scale), "hitstop releases to original time scale without another attack")
	await _wait_wall(0.65)
	_check(feedback.call("active_burst_count") == 0, "expired impact bursts remove themselves")
	feedback.call("play_impact", hero.global_position + Vector3.UP, Vector3.FORWARD, false)
	_check(feedback.call("hitstop_active"), "fresh damage feedback starts a bounded temporal accent")
	paused = true
	await process_frame
	var snapshot := _visual_snapshot(feedback)
	var paused_ages := _burst_ages(feedback)
	await _wait_wall(0.15)
	_check(is_equal_approx(Engine.time_scale, original_time_scale) and not feedback.call("hitstop_active"), "opening pause releases temporary global time scale")
	_check(snapshot == _visual_snapshot(feedback) and int(feedback.call("active_burst_count")) > 0 and paused_ages == _burst_ages(feedback), "pause freezes impact visual state and lifetime")
	paused = false
	await _wait_wall(0.65)
	_check(feedback.call("active_burst_count") == 0, "paused burst resumes and cleans up after unpausing")
	for index: int in 48:
		feedback.call("play_impact", Vector3.UP, Vector3.FORWARD, index % 3 == 0)
	_check(int(feedback.call("active_burst_count")) <= 24, "simultaneous multi-target impacts have a bounded visual population")
	await _wait_wall(0.15)
	_check(not feedback.call("hitstop_active") and is_equal_approx(Engine.time_scale, original_time_scale), "multi-target batch does not stack indefinite hitstop")
	await _wait_wall(0.6)
	await _test_clear_transients(combat, feedback, guardian, armorer)
	Engine.time_scale = 0.8
	feedback.call("play_impact", Vector3.UP, Vector3.FORWARD, false)
	_check(not feedback.call("hitstop_active") and is_equal_approx(Engine.time_scale, 0.8), "impact does not take over an external nondefault time scale")
	Engine.time_scale = original_time_scale
	feedback.call("play_impact", Vector3.UP, Vector3.FORWARD, false)
	_check(feedback.call("hitstop_active"), "teardown scenario begins while hitstop is actually active")
	combat.free()
	_check(is_equal_approx(Engine.time_scale, original_time_scale), "deleting combat during active hitstop restores global time scale")
	fixture.queue_free()
	await _frames(3)


func _test_clear_transients(combat: SlimeCombatRuntime, feedback: Node, guardian: ExitGuardian, armorer: BorrowableEnemy) -> void:
	# These are real runtime-owned shots/sources, the same children old rooms
	# remove when transitioning. Feedback must survive that cleanup.
	combat._add_projectile(combat.player, &"player", Vector3(0.0, 2.0, 0.0), Vector3.UP, 1, 1.0, 100.0, "clear-shot", 1.0, 0.0)
	var projectile: Node
	for child: Node in combat.get_children():
		if child is SpitProjectile:
			projectile = child
			break
	feedback.call("play_impact", Vector3.UP, Vector3.FORWARD, false)
	var feedback_id := feedback.get_instance_id()
	var stale_stop_serial := int(feedback.get("_stop_serial"))
	_check(is_instance_valid(projectile) and feedback.call("hitstop_active") and int(feedback.call("active_burst_count")) > 0, "room cleanup scenario has a live projectile, burst and active hitstop")
	combat.clear_transients()
	_check(is_instance_valid(feedback) and feedback.get_instance_id() == feedback_id and combat.feedback == feedback and not feedback.is_queued_for_deletion(), "deferred room cleanup preserves the existing feedback node")
	_check(not feedback.call("hitstop_active") and int(feedback.call("active_burst_count")) == 0 and is_equal_approx(Engine.time_scale, original_time_scale), "room cleanup clears all bursts and immediately restores game time")
	_check(projectile.is_queued_for_deletion() and projectile.process_mode == Node.PROCESS_MODE_DISABLED, "deferred room cleanup disables the real projectile before deletion")
	await process_frame
	await process_frame
	_check(not is_instance_valid(projectile) and combat.get_child_count() == 1, "transient projectiles and absorption sources are deleted while feedback stays")
	var before := _count(feedback)
	var guardian_hp := guardian.health
	guardian.receive_hit(1, "after-room-clear", &"player")
	_check(guardian.health == guardian_hp - 1 and _count(feedback) == before + 1 and feedback.call("hitstop_active"), "actual damage starts a fresh impact through preserved runtime wiring")
	# Deliver the old timer's exact callback after the new stop has started.
	# Direct delivery makes this ordering deterministic even on a slow host.
	feedback.call("_release_stop_serial", stale_stop_serial)
	_check(feedback.call("hitstop_active") and Engine.time_scale < original_time_scale, "stale pre-cleanup timer callback cannot release the new hitstop")
	combat._add_projectile(combat.player, &"player", Vector3(0.0, 2.0, 0.0), Vector3.UP, 1, 1.0, 100.0, "immediate-clear-shot", 1.0, 0.0)
	combat.clear_transients(true)
	_check(combat.get_child_count() == 1 and is_instance_valid(feedback) and feedback.get_instance_id() == feedback_id and int(feedback.call("active_burst_count")) == 0 and is_equal_approx(Engine.time_scale, original_time_scale), "immediate room cleanup preserves feedback and restores time without queued transients")
	before = _count(feedback)
	var armorer_hp := armorer.health
	armorer.receive_hit(1, "after-immediate-clear", &"player")
	_check(armorer.health == armorer_hp - 1 and _count(feedback) == before + 1 and feedback.call("hitstop_active"), "damage feedback remains usable after immediate room cleanup")
	await _wait_wall(0.2)
	_check(not feedback.call("hitstop_active") and is_equal_approx(Engine.time_scale, original_time_scale), "new hitstop releases normally after both cleanup modes")


func _test_dungeon_pipeline() -> void:
	change_scene_to_file("res://scenes/dungeon/dungeon_route.tscn")
	await _frames(20)
	level = current_scene as SlimeKeepersWorld
	if not is_instance_valid(level):
		_check(false, "real dungeon initializes for impact integration")
		return
	for tick: int in 750:
		if not bool(level.get("_transitioning")):
			break
		await _frames(1)
	_check(not bool(level.get("_transitioning")), "real dungeon completes initialization")
	for room_id: String in level.rooms:
		for actor: Node3D in level.alive_enemies(room_id):
			actor.set_physics_process(false)
	level._pause_panel.hide()
	paused = false
	var hero := level.player as SlimeDungeonPlayer
	var feedback: Node = level.combat.get("feedback")
	var enemy := level.alive_enemies("barracks")[0] as Spitter
	level._reset_position(enemy.global_position + Vector3(1.6, 0.05, 0.0))
	await _frames(8)
	hero.grant_ability(&"acid_spit")
	var hp := enemy.health
	var before := _count(feedback)
	var physical_root := enemy.global_transform
	var creature_art: Node3D = enemy.get("_creature_art")
	var art_basis := creature_art.global_basis
	_check(await _cast_at(&"acid_spit", enemy.global_position + Vector3.UP * 0.65), "real dungeon player requests acquired acid attack")
	var saw_art_reaction := false
	for tick: int in 100:
		await _frames(1)
		var art: Node3D = enemy.get("_creature_art")
		if enemy.health < hp and is_instance_valid(art):
			saw_art_reaction = saw_art_reaction or not art.global_basis.is_equal_approx(art_basis)
		if enemy.health < hp and saw_art_reaction:
			break
	_check(enemy.health == hp - 18 and _count(feedback) == before + 1, "real acid projectile confirms exactly one 18-HP impact")
	_check(saw_art_reaction, "dungeon creature reacts in visible replacement art")
	_check(enemy.global_transform.is_equal_approx(physical_root), "creature hit reaction leaves frozen physical root and collider transform unchanged")
	await _wait_wall(0.8)
	var membrane: Node3D = level.get("membrane")
	level._reset_position(Vector3(-1.8, 0.0, -18.0))
	await _frames(8)
	before = _count(feedback)
	_check(bool(membrane.get("intact")), "real organic barrier starts intact")
	_check(await _cast_at(&"acid_spit", membrane.global_position + Vector3.UP * 0.65), "real acid projectile is requested at organic mechanism")
	for tick: int in 100:
		await _frames(1)
		if int(membrane.get("strength")) < 2:
			break
	_check(int(membrane.get("strength")) == 1 and bool(membrane.get("intact")), "first-rank acid damages barrier without skipping its strength")
	_check(_count(feedback) == before, "partial mechanism activation is not reported as enemy damage")
	await _wait_wall(0.8)
	hero.grant_ability(&"acid_spit")
	_check(await _cast_at(&"acid_spit", membrane.global_position + Vector3.UP * 0.65), "ranked acid projectile is requested at weakened barrier")
	for tick: int in 100:
		await _frames(1)
		if not bool(membrane.get("intact")):
			break
	_check(not bool(membrane.get("intact")), "acid projectile activates actual dungeon mechanism")
	_check(_count(feedback) == before, "mechanism activation is not misreported as enemy damage feedback")
	await _wait_wall(0.2)
	current_scene.queue_free()
	await _frames(3)
	_check(is_equal_approx(Engine.time_scale, original_time_scale), "leaving dungeon preserves normal global time scale")


func _cast_at(ability: StringName, target: Vector3) -> bool:
	var hero := level.player
	hero._cooldowns[ability] = 0.0
	if not hero.request_action(ability):
		return false
	hero._action_aim_point = target
	hero._action_direction = (target - hero.global_position).normalized()
	return true


func _count(feedback: Node) -> int:
	return int(feedback.get("impact_count"))


func _visual_snapshot(node: Node) -> Array:
	var values: Array = []
	for child: Node in node.get_children():
		if child is Node3D:
			values.append([child.get_instance_id(), child.transform, child.visible])
		values.append_array(_visual_snapshot(child))
	return values


func _burst_ages(feedback: Node) -> Array[float]:
	var ages: Array[float] = []
	for burst: Dictionary in feedback.get("_bursts"):
		ages.append(float(burst.age))
	return ages


func _frames(count: int) -> void:
	for tick: int in count:
		await physics_frame
		await process_frame


func _wait_wall(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


func _check(ok: bool, label: String) -> void:
	checks.append({"check": label, "pass": ok})
	if not ok:
		failures.append(label)
	print("PASS " if ok else "FAIL ", label)


func _finish() -> void:
	if done:
		return
	done = true
	paused = false
	Engine.time_scale = original_time_scale
	var report := FileAccess.open(OUTPUT + "impact-checks.json", FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify({"checks": checks, "failures": failures}, "\t"))
	print("COMBAT_IMPACT_RESULT checks=%d failures=%d" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
