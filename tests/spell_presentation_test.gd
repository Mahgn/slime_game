extends SceneTree

# Real action transitions and projectiles; no input, physics or balance override
# is introduced by presentation. This does not judge artistic or audio quality.
const PLAYER := preload("res://scenes/player/slime_player.tscn")
const DUNGEON_PLAYER := preload("res://scripts/dungeon/dungeon_player.gd")
const INPUT_SETUP := preload("res://scripts/input_setup.gd")
const OUT := "res://output/spell_juice_2026_10_15/"
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var done := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	INPUT_SETUP.install()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	SlimeGameSettings.current().load_settings(OUT + "test-settings.cfg")
	create_timer(90.0, true, false, true).timeout.connect(func() -> void:
		_check(false, "watchdog: spell presentation checks finish within 90 seconds")
		_finish())
	for ability: StringName in [&"acid_spit", &"sticky_spit", &"slime_spikes", &"elastic_shell"]:
		await _test_cast(ability)
	await _test_rejection_and_death()
	await _test_trail(&"acid_spit")
	await _test_trail(&"sticky_spit")
	_finish()


func _fixture() -> Dictionary:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var floor_body := StaticBody3D.new()
	floor_body.position.y = -0.2
	floor_body.collision_layer = 1
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 0.4, 40.0)
	collision.shape = box
	floor_body.add_child(collision)
	fixture.add_child(floor_body)
	var hero := PLAYER.instantiate() as SlimeController
	hero.set_script(DUNGEON_PLAYER)
	fixture.add_child(hero)
	var combat := SlimeCombatRuntime.new()
	fixture.add_child(combat)
	combat.bind_player(hero)
	return {"root": fixture, "hero": hero, "combat": combat}


func _equip(hero: SlimeController, ability: StringName) -> void:
	# Fixture can exercise legacy shell/spikes on the current dungeon hero too.
	hero.learned_abilities[ability] = 1
	hero.equipped_ability = ability
	hero._cooldowns.clear()


func _cast(hero: SlimeController, ability: StringName) -> bool:
	if not hero.request_action(ability):
		return false
	hero._action_direction = Vector3.FORWARD
	hero._action_aim_point = hero.global_position + Vector3(0.0, 0.65, -15.0)
	return true


func _test_cast(ability: StringName) -> void:
	var f := _fixture()
	var hero: SlimeController = f.hero
	await _frames(6)
	_equip(hero, ability)
	var shape: CapsuleShape3D = hero.collision_shape.shape
	var original_transform := hero.transform
	var original_shape := Vector2(shape.radius, shape.height)
	var expected: float = 0.10 if ability == &"elastic_shell" else (0.35 if ability == &"slime_spikes" else 0.18)
	_check(_cast(hero, ability), "%s: real action request starts" % ability)
	_check(is_equal_approx(hero._phase_left, expected), "%s: presentation leaves original preparation duration unchanged" % ability)
	await _frames(1)
	var snapshot: Dictionary = hero.spell_visual.snapshot()
	_check(snapshot.phase == &"charge" and snapshot.charge_visible and snapshot.profile == hero.get_impact_profile(ability), "%s: real preparation selects the authored charge profile" % ability)
	_check(int(snapshot.charge_count) == 1 and int(snapshot.release_count) == 0, "%s: charge starts once before release" % ability)
	var phase_left := hero._phase_left
	paused = true
	for tick in 5:
		await process_frame
	var paused_snapshot: Dictionary = hero.spell_visual.snapshot()
	_check(is_equal_approx(hero._phase_left, phase_left) and paused_snapshot.phase == snapshot.phase and paused_snapshot.release_count == snapshot.release_count, "%s: pause freezes preparation without a hidden release" % ability)
	paused = false
	_check(not _cast(hero, ability) and hero.spell_visual.snapshot().charge_count == 1, "%s: rejected duplicate input does not replay charge" % ability)
	for tick in 40:
		await _frames(1)
		if hero._phase != &"preparation":
			break
	snapshot = hero.spell_visual.snapshot()
	_check(int(snapshot.release_count) == 1 and not snapshot.charge_visible and snapshot.release_visible, "%s: first active or guard transition releases exactly one visual burst" % ability)
	_check(hero.transform.is_equal_approx(original_transform) and Vector2(shape.radius, shape.height).is_equal_approx(original_shape), "%s: charge and release never move the physical root or resize its collider" % ability)
	_check(f.combat.feedback.impact_count == 0 and not f.combat.feedback.hitstop_active(), "%s: casting into empty space gives no false damage feedback" % ability)
	if ability == &"elastic_shell":
		_check(hero._phase == &"guard" and is_equal_approx(hero._phase_left, 1.20), "shell: original 1.20 second guard duration is preserved")
		f.combat.clear_transients(true)
		_check(hero._phase == &"guard" and hero.spell_visual.snapshot().phase == &"idle", "shell: transient cleanup clears presentation while the existing guard keeps its gameplay state")
		var hp := hero.health
		_check(hero.receive_attack_hit(20, "spell-shell-20", &"enemy", Vector3.RIGHT, SlimeImpactProfiles.WEB), "shell: actual incoming hit is accepted by guard")
		snapshot = hero.spell_visual.snapshot()
		_check(hero.health == hp and snapshot.block_count == 1 and snapshot.phase == &"block", "shell: full block has its own response without HP loss")
		_check(f.combat.feedback.impact_count == 0 and not f.combat.feedback.hitstop_active(), "shell: successful block does not masquerade as damage")
	elif ability in [&"acid_spit", &"sticky_spit"]:
		var projectile := _projectile(f.combat)
		_check(is_instance_valid(projectile), "%s: original physical shot launches with the visual release" % ability)
		if is_instance_valid(projectile):
			_check(is_equal_approx(projectile.speed, 14.0) and is_equal_approx(projectile.max_range, 18.0), "%s: projectile speed and range are unchanged" % ability)
			_check(projectile.damage == (18 if ability == &"acid_spit" else 12), "%s: projectile damage is unchanged" % ability)
	else:
		var line := _spikes(f.combat)
		_check(is_instance_valid(line) and line.damage == 22 and line._player_centers.size() == 5, "spikes: release preserves five physical segments and 22 base damage")
		_check(SpikeLine.PLAYER_VISUAL_LIFETIME == 1.55 and SpikeLine.LIFETIME == 0.38, "spikes: presentation does not extend damage or visual lifetime")
	paused = true
	phase_left = hero._phase_left
	snapshot = hero.spell_visual.snapshot()
	for tick in 5:
		await process_frame
	paused_snapshot = hero.spell_visual.snapshot()
	_check(is_equal_approx(hero._phase_left, phase_left) and paused_snapshot.release_visible == snapshot.release_visible and paused_snapshot.release_count == snapshot.release_count, "%s: pause freezes the release or block effect" % ability)
	paused = false
	await _frames(100)
	snapshot = hero.spell_visual.snapshot()
	_check(snapshot.phase == &"idle" and not snapshot.charge_visible and not snapshot.release_visible and int(snapshot.release_count) == 1, "%s: recovery ends without another release or persistent effect" % ability)
	f.combat.clear_transients(true)
	f.root.queue_free()
	await _frames(3)


func _test_rejection_and_death() -> void:
	var f := _fixture()
	var hero: SlimeController = f.hero
	await _frames(6)
	_check(not hero.request_action(&"acid_spit") and hero.spell_visual.snapshot().charge_count == 0, "unavailable ability: rejected input never starts a charge")
	_equip(hero, &"acid_spit")
	hero._cooldowns[&"acid_spit"] = 3.0
	_check(not hero.request_action(&"acid_spit") and hero.spell_visual.snapshot().charge_count == 0, "cooldown: rejected input never starts a charge")
	hero._cooldowns.clear()
	_check(hero.request_action(&"slime_whip"), "whip: existing physical attack still starts normally")
	await _frames(45)
	_check(hero.spell_visual.snapshot().charge_count == 0 and hero.spell_visual.snapshot().release_count == 0, "whip: profile without spell stages does not acquire an extra orb or release sound")
	_check(_cast(hero, &"acid_spit"), "death fixture starts an actual acid preparation")
	await _frames(3)
	hero.apply_environment_damage(100)
	await _frames(2)
	var snapshot: Dictionary = hero.spell_visual.snapshot()
	_check(hero.health == 0 and snapshot.phase == &"idle" and not snapshot.charge_visible and not snapshot.release_visible, "death during preparation immediately clears charge")
	_check(int(snapshot.release_count) == 0 and _projectile(f.combat) == null, "cancelled preparation never releases a delayed projectile or burst")
	var visual: Node = hero.spell_visual
	f.root.queue_free()
	await _frames(3)
	_check(not is_instance_valid(visual), "removing the owner scene removes all cast visuals")


func _test_trail(ability: StringName) -> void:
	var f := _fixture()
	var hero: SlimeController = f.hero
	await _frames(6)
	_equip(hero, ability)
	_cast(hero, ability)
	var shot: SpitProjectile
	for tick in 40:
		await _frames(1)
		shot = _projectile(f.combat)
		if is_instance_valid(shot):
			break
	if not is_instance_valid(shot):
		_check(false, "%s: trail fixture obtains a real projectile" % ability)
		f.root.queue_free()
		await _frames(3)
		return
	var trail: Node3D = shot._spell_trail
	_check(is_instance_valid(trail) and shot._spell_core != null, "%s: shot owns a core and bounded world-space trail" % ability)
	await _frames(8)
	_check(trail.active_sample_count() >= 2 and trail.active_sample_count() <= 10, "%s: actual flight produces multiple trail samples within the fixed pool" % ability)
	shot.set_physics_process(false)
	var at := shot.global_position
	var count: int = trail.active_sample_count()
	paused = true
	for tick in 5:
		await process_frame
	_check(shot.global_position == at and trail.active_sample_count() == count, "%s: pause preserves projectile and trail positions" % ability)
	paused = false
	for tick in 120:
		trail.advance(at, 1.0 / 60.0)
	_check(trail.active_sample_count() == 0, "%s: stationary samples expire instead of leaving a permanent streak" % ability)
	trail.reset_at(at)
	for tick in 30:
		at += Vector3.FORWARD * 0.2
		trail.advance(at, 1.0 / 60.0)
	_check(trail.active_sample_count() <= 10, "%s: continued flight cannot allocate an unbounded trail" % ability)
	trail.reset_at(at + Vector3.RIGHT * 20.0)
	_check(trail.active_sample_count() == 0, "%s: relocation resets old samples instead of drawing across the room" % ability)
	at += Vector3.RIGHT * 20.0
	for step in 18:
		for render_tick in 7:
			trail.advance(at, 1.0 / 480.0)
		at += Vector3.FORWARD * (14.0 / 60.0)
		trail.advance(at, 1.0 / 480.0)
	_check(trail.active_sample_count() >= 2 and trail.active_sample_count() <= 10, "%s: render rates above physics still produce a bounded visible trail" % ability)
	_check(f.combat.feedback.impact_count == 0, "%s: trail rendering never creates a damage event" % ability)
	f.combat.clear_transients(true)
	_check(not is_instance_valid(shot) and not is_instance_valid(trail), "%s: combat cleanup removes projectile and its trail together" % ability)
	f.root.queue_free()
	await _frames(3)


func _projectile(combat: Node) -> SpitProjectile:
	for child in combat.get_children():
		if child is SpitProjectile and not child.is_queued_for_deletion():
			return child
	return null


func _spikes(combat: Node) -> SpikeLine:
	for child in combat.get_children():
		if child is SpikeLine and not child.is_queued_for_deletion():
			return child
	return null


func _frames(count: int) -> void:
	for tick in count:
		await physics_frame
		await process_frame


func _check(passed: bool, label: String) -> void:
	checks.append({"check": label, "pass": passed})
	if not passed:
		failures.append(label)
	print("PASS " if passed else "FAIL ", label)


func _finish() -> void:
	if done:
		return
	done = true
	paused = false
	Engine.time_scale = 1.0
	FileAccess.open(OUT + "spell-presentation-checks.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures}, "\t"))
	print("SPELL_PRESENTATION_RESULT checks=%d failures=%d" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
