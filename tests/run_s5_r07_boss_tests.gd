extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var room: Node3D = load("res://scenes/r07_guardian.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await _steps(8)
	var player: SlimeController = room.get_node("SlimePlayer")
	var boss: ExitGuardian = room.get_node("ExitGuardian")
	var entry: bool = room.get("stage") == &"r07_fight" and boss.health == 180 and get_nodes_in_group(&"enemies").size() == 1
	var telegraph := false
	for tick in 400:
		await physics_frame
		if boss.get("_phase") == &"windup":
			telegraph = boss.get("_warning_line").visible
			break
	var warning_duration := false
	if telegraph:
		await _steps(30)
		warning_duration = boss.get("_phase") == &"windup"
		await _steps(40)
	var recovery: bool = boss.get("_phase") == &"recovery" and boss.get("_attack_index") == 1
	boss.set_physics_process(false)
	player.set_physics_process(false)
	player.global_position = boss.global_position + Vector3(0.0, 0.0, 2.0)
	player.velocity = Vector3.ZERO
	player.set("_hurt_protection_left", 0.0)
	var start_hp := player.health
	room.call("_add_spikes", boss, &"enemy", boss.global_position, Vector3.BACK, "boss_line_ground", 14)
	await _steps(2)
	var line_hit := player.health == start_hp - 14
	player.global_position.y = 1.2
	player.set("_hurt_protection_left", 0.0)
	room.call("_add_spikes", boss, &"enemy", boss.global_position, Vector3.BACK, "boss_line_jump", 14)
	await _steps(2)
	var line_jump := player.health == start_hp - 14
	boss.set("_attack_index", 1)
	boss.set("_locked_direction", Vector3.BACK)
	player.set("_hurt_protection_left", 0.0)
	boss.call("_strike")
	var arc_airborne := player.health == start_hp - 30
	boss.set("_attack_index", 2)
	player.set("_hurt_protection_left", 0.0)
	boss.call("_strike")
	var radial_jump := player.health == start_hp - 30
	player.global_position.y = 0.05
	player.set("_hurt_protection_left", 0.0)
	boss.call("_strike")
	var radial_ground := player.health == start_hp - 50
	player.set("_hurt_protection_left", 0.0)
	player.set("_action", &"elastic_shell")
	player.set("_phase", &"guard")
	boss.set("_attack_index", 1)
	boss.call("_strike")
	var shell: bool = player.health == start_hp - 50 and player.get("_phase") == &"recovery"
	player.set("_action", &"")
	player.set("_phase", &"")
	boss.receive_hit(12, "combo_spit", &"player")
	boss.apply_sticky(0.55, 3.0)
	var sticky_cap := absf(float(boss.get("_sticky_factor")) - 0.75) < 0.001
	room.call("_add_spikes", player, &"player", boss.global_position + Vector3(0.0, 0.0, 2.0), Vector3.FORWARD, "combo_spikes", 22)
	await _steps(2)
	var combo := boss.health == 135 and boss.get_sticky_time_left() == 0.0
	var duplicate := not boss.receive_hit(22, "combo_spikes", &"player") and boss.health == 135
	var old_attack := Node3D.new()
	old_attack.add_to_group(&"enemy_attacks")
	room.add_child(old_attack)
	boss.receive_hit(135, "boss_final", &"player")
	await _steps(3)
	var cleared: bool = room.get("stage") == &"r07_exit" and room.get_node("ExitGate").collision_layer == 0 and get_nodes_in_group(&"enemy_attacks").is_empty() and get_nodes_in_group(&"absorb_sources").is_empty()
	var ok: bool = entry and telegraph and warning_duration and recovery and line_hit and line_jump and arc_airborne and radial_jump and radial_ground and shell and sticky_cap and combo and duplicate and cleared
	print("R07_BOSS entry=%s telegraph=%s warning=%s recovery=%s line=%s jump=%s arc=%s radial_jump=%s radial_ground=%s shell=%s sticky=%s combo=%s duplicate=%s cleared=%s" % [entry, telegraph, warning_duration, recovery, line_hit, line_jump, arc_airborne, radial_jump, radial_ground, shell, sticky_cap, combo, duplicate, cleared])
	print("PASS S5_R07_BOSS" if ok else "FAIL S5_R07_BOSS")
	paused = false
	quit(0 if ok else 1)

func _steps(count: int) -> void:
	for tick in count:
		await physics_frame
