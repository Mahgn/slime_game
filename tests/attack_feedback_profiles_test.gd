extends SceneTree

# Integration checks exercise real attack requests and physics contacts. They do
# not establish subjective quality of sound, particles or camera movement.
const PLAYER_SCENE := preload("res://scenes/player/slime_player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemies/spitter.tscn")
const DUNGEON_PLAYER := preload("res://scripts/dungeon/dungeon_player.gd")
const DUNGEON_COMBAT := preload("res://scripts/dungeon/dungeon_combat.gd")
const MEMBRANE := preload("res://scripts/dungeon/dungeon_membrane.gd")
const PROFILES := preload("res://scripts/combat/impact_profiles.gd")
const SOUND := preload("res://scripts/audio/sound_playback.gd")
const INPUT_SETUP := preload("res://scripts/input_setup.gd")
const OUTPUT := "res://output/attack_profiles_2026_10_14/"
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var done := false
var original_time_scale := 1.0


func _initialize() -> void:
	original_time_scale = Engine.time_scale
	call_deferred("_run")


func _run() -> void:
	INPUT_SETUP.install()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	SlimeGameSettings.current().load_settings(OUTPUT + "profile-test-settings.cfg")
	create_timer(90.0, true, false, true).timeout.connect(func() -> void:
		_check(false, "watchdog: profile checks complete within 90 seconds")
		_finish())
	var before := _profile_snapshot()
	_test_sound_variation()
	await _test_projectile(&"acid_spit", &"sticky_spit", PROFILES.ACID, 18)
	await _test_projectile(&"sticky_spit", &"acid_spit", PROFILES.WEB, 12)
	await _test_custom_profile()
	await _test_whip()
	await _test_spikes(false)
	await _test_spikes(true)
	await _test_enemy_projectile()
	await _test_enemy_projectile(true)
	await _test_blocked_damage()
	await _test_environment_contact()
	_check(before == _profile_snapshot(), "hits, contacts, death and cleanup leave shared profile Resources unchanged")
	_finish()


func _fixture() -> Dictionary:
	var fixture := Node3D.new()
	fixture.name = "AttackProfileFixture"
	root.add_child(fixture)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	floor_body.position.y = -0.2
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(30.0, 0.4, 30.0)
	collider.shape = shape
	floor_body.add_child(collider)
	fixture.add_child(floor_body)
	var hero := PLAYER_SCENE.instantiate() as SlimeController
	hero.set_script(DUNGEON_PLAYER)
	fixture.add_child(hero)
	var combat := DUNGEON_COMBAT.new() as SlimeCombatRuntime
	fixture.add_child(combat)
	# Only room threat polling requires a full route; attack wiring is unchanged.
	combat.set_physics_process(false)
	combat.bind_player(hero)
	var enemy := ENEMY_SCENE.instantiate() as Spitter
	enemy.position = Vector3(0.0, 0.0, -4.0)
	fixture.add_child(enemy)
	enemy.set_physics_process(false)
	combat.bind_enemy(enemy)
	var events: Array[Dictionary] = []
	var exit_state: Dictionary = {}
	enemy.attack_impact_received.connect(func(at: Vector3, lethal: bool, profile: SlimeImpactProfile, direction: Vector3) -> void:
		events.append({"at": at, "lethal": lethal, "profile": profile, "direction": direction}))
	enemy.tree_exiting.connect(func() -> void:
		exit_state.health = enemy.health
		exit_state.sticky = enemy.get_sticky_time_left())
	return {"root": fixture, "hero": hero, "combat": combat, "enemy": enemy, "events": events, "exit_state": exit_state, "feedback": combat.feedback}


func _test_projectile(ability: StringName, replacement: StringName, expected: SlimeImpactProfile, damage: int) -> void:
	var f := _fixture()
	var hero := f.hero as SlimeDungeonPlayer
	var enemy := f.enemy as Spitter
	var combat := f.combat as SlimeCombatRuntime
	hero.grant_ability(ability)
	hero.grant_ability(replacement)
	_check(hero.get_ability_definition(ability).impact_profile == expected, "%s: ranked ability definition shares its immutable presentation profile" % ability)
	await _frames(4)
	_check(_cast_at(hero, ability, enemy.global_position + Vector3.UP * 0.65), "%s: real player attack starts" % ability)
	var projectile: SpitProjectile
	for tick in 50:
		await _frames(1)
		projectile = _projectile(combat)
		if projectile != null:
			break
	_check(is_instance_valid(projectile), "%s: cast creates a physical projectile" % ability)
	if is_instance_valid(projectile):
		projectile.set_physics_process(false)
		_check(projectile.impact_profile == expected, "%s: launched projectile captures its attack profile" % ability)
		await _frames(24)
		_check(hero.equip_ability(1, replacement), "%s: loadout changes while original projectile is airborne" % ability)
		projectile.set_physics_process(true)
		await _wait_for_events(f.events, 1)
		_check(enemy.health == 30 - damage and f.events.size() == 1, "%s: one actual collision causes the original damage exactly once" % ability)
		_check(_event_has_profile(f.events, expected), "%s: hit keeps original profile after loadout changes" % ability)
		_check(_has_burst(f.feedback, expected, false), "%s: runtime presents the correct confirmed-hit particles" % ability)
		_check(f.feedback.impact_count == 1 and f.feedback.contact_count == 0, "%s: actor hit is not duplicated as a surface contact" % ability)
		if ability == &"sticky_spit":
			_check(enemy.get_sticky_time_left() > 0.0, "web projectile still applies its gameplay slowdown")
	await _discard(f)


func _test_whip() -> void:
	var f := _fixture()
	var hero := f.hero as SlimeController
	var enemy := f.enemy as Spitter
	enemy.position.z = -1.12
	await _frames(4)
	_check(_cast_at(hero, &"slime_whip", enemy.global_position + Vector3.UP * 0.65), "whip: real action starts")
	await _wait_for_events(f.events, 1)
	_check(enemy.health == 20 and f.events.size() == 1, "whip: real action deals its original 10 damage once")
	_check(_event_has_profile(f.events, PROFILES.WHIP) and _has_burst(f.feedback, PROFILES.WHIP, false), "whip: warm sharp profile reaches damage feedback")
	await _frames(35)
	_check(f.feedback.impact_count == 1, "whip: active swing does not repeat feedback against its first target")
	await _discard(f)


func _test_custom_profile() -> void:
	var f := _fixture()
	var hero := f.hero as SlimeDungeonPlayer
	hero.grant_ability(&"sticky_spit")
	var definition := hero.get_ability_definition(&"sticky_spit")
	var custom := PROFILES.WEB.duplicate(true) as SlimeImpactProfile
	custom.profile_id = &"test_custom_thread"
	custom.primary_color = Color("c8b0f4")
	definition.impact_profile = custom
	await _frames(4)
	_check(_cast_at(hero, &"sticky_spit", f.enemy.global_position + Vector3.UP * 0.65), "custom profile: ability with a new Resource starts through ordinary player action")
	await _wait_for_events(f.events, 1)
	_check(f.enemy.health == 18 and _event_has_profile(f.events, custom) and _has_burst(f.feedback, custom, false), "custom profile: new data reaches projectile, damage and renderer without registry or attack-code changes")
	_check(PROFILES.WEB.profile_id != custom.profile_id and PROFILES.WEB.primary_color != custom.primary_color, "custom profile: per-definition authoring leaves shared built-in profile intact")
	await _discard(f)


func _test_spikes(combo: bool) -> void:
	var f := _fixture()
	var hero := f.hero as SlimeController
	var enemy := f.enemy as Spitter
	enemy.position.z = -2.0
	# Dungeon currently lends two spit abilities, but the shared player still
	# supports the existing spike action. Equip it to cover that retained path.
	hero.learned_abilities[&"slime_spikes"] = true
	hero.equipped_ability = &"slime_spikes"
	if combo:
		enemy.apply_sticky(0.55, 3.0)
	await _frames(5)
	_check(_cast_at(hero, &"slime_spikes", enemy.global_position), "spikes%s: real grounded action starts" % (" combo" if combo else ""))
	await _wait_for_events(f.events, 1)
	var remaining_hp: int = enemy.health if is_instance_valid(enemy) else int(f.exit_state.get("health", -1))
	_check(remaining_hp == (0 if combo else 8) and f.events.size() == 1, "spikes%s: damage and one-hit-per-target contract are preserved" % (" combo" if combo else ""))
	_check(_event_has_profile(f.events, PROFILES.SPIKES) and _has_burst(f.feedback, PROFILES.SPIKES, false), "spikes%s: upward debris profile reaches confirmed damage" % (" combo" if combo else ""))
	if combo:
		var sticky_left: float = enemy.get_sticky_time_left() if is_instance_valid(enemy) else float(f.exit_state.get("sticky", -1.0))
		_check(f.events.size() == 1 and bool(f.events[0].lethal) and sticky_left == 0.0, "spikes combo: consumes sticky status and keeps lethal impact")
	var before: int = f.feedback.impact_count
	for child: Node in f.combat.get_children():
		if child is SpikeLine:
			(child as SpikeLine).build_line()
	_check(f.feedback.impact_count == before, "spikes: rebuilding overlapping segments never duplicates the same target's impact")
	await _discard(f)


func _test_enemy_projectile(custom_override: bool = false) -> void:
	var f := _fixture()
	var hero := f.hero as SlimeController
	var enemy := f.enemy as Spitter
	var player_events: Array[Dictionary] = []
	hero.attack_impact_received.connect(func(at: Vector3, lethal: bool, profile: SlimeImpactProfile, direction: Vector3) -> void:
		player_events.append({"at": at, "lethal": lethal, "profile": profile, "direction": direction}))
	await _frames(4)
	var expected: SlimeImpactProfile = PROFILES.ACID
	var label := "enemy acid"
	if custom_override:
		expected = PROFILES.ACID.duplicate(true) as SlimeImpactProfile
		expected.profile_id = &"test_enemy_acid_override"
		expected.primary_color = Color("dfac55")
		enemy.attack_impact_profile = expected
		enemy.drop_ability_id = &"sticky_spit"
		label = "enemy custom override"
	else:
		enemy.drop_ability_id = &"acid_spit"
	var origin := enemy.global_position + Vector3.UP * 0.65 + Vector3.BACK * 0.6
	enemy.projectile_requested.emit(enemy, origin, Vector3.BACK, 7, 14.0, 18.0, "enemy-acid-profile")
	var projectile := _projectile(f.combat)
	_check(is_instance_valid(projectile) and projectile.impact_profile == expected, "%s: launched projectile captures the authored profile independently of the reward ability" % label)
	enemy.drop_ability_id = &"sticky_spit"
	if custom_override:
		enemy.drop_ability_id = &"acid_spit"
		enemy.attack_impact_profile = PROFILES.SPIKES
	await _wait_for_events(player_events, 1)
	_check(hero.health == 93 and player_events.size() == 1, "%s: real projectile reaches player and causes 7 HP damage once" % label)
	_check(_event_has_profile(player_events, expected) and _has_burst(f.feedback, expected, false), "%s: original profile survives changes to source override and reward before collision" % label)
	_check(f.feedback.impact_count == 1 and f.feedback.contact_count == 0, "player's legacy damaged signal does not duplicate typed impact feedback")
	await _discard(f)


func _test_blocked_damage() -> void:
	var f := _fixture()
	var hero := f.hero as SlimeController
	var enemy := f.enemy as Spitter
	await _frames(4)
	hero._action = &"elastic_shell"
	hero._phase = &"guard"
	hero._phase_left = 10.0
	var origin := enemy.global_position + Vector3.UP * 0.65 + Vector3.BACK * 0.6
	enemy.projectile_requested.emit(enemy, origin, Vector3.BACK, 7, 14.0, 18.0, "blocked-web-profile")
	for tick in 80:
		await _frames(1)
		if _projectile(f.combat) == null:
			break
	_check(hero.health == 100 and hero._phase != &"guard", "shell: the real enemy shot is consumed without HP loss")
	_check(f.feedback.impact_count == 0 and f.feedback.contact_count == 0 and not f.feedback.hitstop_active(), "fully blocked shot creates no damage or misleading wall impact")
	_check(not enemy.receive_attack_hit(0, "zero-profile", &"player", Vector3.FORWARD, PROFILES.ACID) and f.feedback.impact_count == 0, "zero damage produces no typed impact")
	await _discard(f)


func _test_environment_contact() -> void:
	var f := _fixture()
	var hero := f.hero as SlimeDungeonPlayer
	f.enemy.position.x = 8.0
	var membrane := MEMBRANE.new() as StaticBody3D
	membrane.position = Vector3(3.0, 0.0, 0.0)
	f.root.add_child(membrane)
	hero.grant_ability(&"acid_spit")
	await _frames(4)
	_check(_cast_at(hero, &"acid_spit", membrane.global_position + Vector3.UP * 0.65), "environment: real acid action targets membrane")
	for tick in 100:
		await _frames(1)
		if membrane.strength < 2:
			break
	_check(membrane.strength == 1 and membrane.intact, "environment: projectile still applies acid property to real membrane")
	_check(f.feedback.impact_count == 0 and f.feedback.contact_count == 1 and _has_burst(f.feedback, PROFILES.ACID, true), "environment: membrane contact has acid particles without reporting enemy damage")
	_check(not f.feedback.hitstop_active() and is_equal_approx(Engine.time_scale, original_time_scale) and hero.presentation.get_combat_camera_offset().is_zero_approx(), "environment: property contact never creates hitstop or camera kick")
	await _discard(f)


func _test_sound_variation() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 27419
	var low := INF
	var high := -INF
	var unchanged := true
	for index in 1024:
		var pitch: float = SOUND.pitch_for(0.035, 1.0, rng)
		low = minf(low, pitch)
		high = maxf(high, pitch)
		unchanged = unchanged and is_equal_approx(SOUND.pitch_for(0.0, 1.0, rng), 1.0)
	_check(low >= 0.965 and high <= 1.035, "audio: optional random pitch stays within plus/minus 3.5 percent")
	_check(high - low > 0.04, "audio: successive effects actually vary within the authored small range")
	_check(unchanged and is_equal_approx(SOUND.pitch_for(0.0, 0.92, rng), 0.92), "audio: non-opted sounds keep exactly their authored pitch")
	seed(95331)
	var expected_gameplay_random := randf()
	seed(95331)
	for index in 100:
		SOUND.pitch_for(0.035)
	_check(randf() == expected_gameplay_random, "audio: cosmetic variation does not consume gameplay's global random sequence")
	var voice := AudioStreamPlayer.new()
	root.add_child(voice)
	var bounded := true
	for index in 200:
		SOUND.play_existing(voice, 0.035, 0.92)
		bounded = bounded and voice.pitch_scale >= 0.92 * 0.965 and voice.pitch_scale <= 0.92 * 1.035
	SOUND.play_existing(voice, 0.0, 0.92)
	_check(bounded and is_equal_approx(voice.pitch_scale, 0.92), "audio: reused non-combat voice varies from its base without accumulating drift, then opts out exactly")
	voice.queue_free()
	_check(PROFILES.ACID.impact_sound != PROFILES.WEB.impact_sound and PROFILES.WEB.impact_sound != PROFILES.SPIKES.impact_sound and PROFILES.SPIKES.impact_sound != PROFILES.WHIP.impact_sound, "attack families use distinct contact sounds, not one sample with pitch alone")
	_check(PROFILES.ACID.particle_style != PROFILES.WEB.particle_style and PROFILES.WEB.particle_style != PROFILES.SPIKES.particle_style and PROFILES.SPIKES.particle_style != PROFILES.WHIP.particle_style, "acid, web, spikes and whip have distinct particle shapes/movement styles")


func _profile_snapshot() -> Array:
	var values: Array = []
	for profile: Resource in [PROFILES.GENERIC, PROFILES.WHIP, PROFILES.ACID, PROFILES.WEB, PROFILES.SPIKES]:
		var fields: Dictionary = {}
		for property: Dictionary in profile.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_STORAGE:
				fields[property.name] = profile.get(property.name)
		values.append(fields)
	return values


func _cast_at(hero: SlimeController, ability: StringName, target: Vector3) -> bool:
	if not hero.request_action(ability):
		return false
	hero._action_aim_point = target
	hero._action_direction = (target - hero.global_position).normalized()
	hero._action_direction.y = 0.0
	hero._action_direction = hero._action_direction.normalized()
	return true


func _projectile(combat: Node) -> SpitProjectile:
	for child: Node in combat.get_children():
		if child is SpitProjectile and not child.is_queued_for_deletion():
			return child as SpitProjectile
	return null


func _event_has_profile(events: Array, profile: SlimeImpactProfile) -> bool:
	return events.size() == 1 and events[0].profile == profile and (events[0].direction as Vector3).length() > 0.5


func _has_burst(feedback: Node, profile: SlimeImpactProfile, contact: bool) -> bool:
	for burst: Dictionary in feedback.get("_bursts"):
		if burst.get("profile") == profile and bool(burst.get("contact", false)) == contact and burst.node.visible:
			return true
	return false


func _wait_for_events(events: Array, minimum: int) -> void:
	for tick in 100:
		if events.size() >= minimum:
			return
		await _frames(1)


func _discard(f: Dictionary) -> void:
	f.combat.clear_transients(true)
	_check(f.feedback.active_burst_count() == 0 and not f.feedback.hitstop_active() and is_equal_approx(Engine.time_scale, original_time_scale), "cleanup: typed impacts release all particles and global time")
	f.root.queue_free()
	await _frames(3)


func _frames(count: int) -> void:
	for tick in count:
		await physics_frame
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
	var report := FileAccess.open(OUTPUT + "attack-feedback-checks.json", FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify({"checks": checks, "failures": failures}, "\t"))
	print("ATTACK_FEEDBACK_PROFILES_RESULT checks=%d failures=%d" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
