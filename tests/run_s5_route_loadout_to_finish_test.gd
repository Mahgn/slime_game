extends SceneTree

# Continuous R04→R07 transition/checkpoint check for a chosen two-slot build.
# Route transitions are isolated from enemy AI, while R05 and R07 exercise
# damage through the same input actions as the player.
const STORE_SCRIPT = preload("res://scripts/progression/checkpoint_store.gd")
const LOADOUTS := {
	"no_spit": [&"elastic_shell", &"slime_spikes"],
	"spit_spikes": [&"sticky_spit", &"slime_spikes"],
}
const FRAME_DIR := "res://output/S5/route_loadouts/"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var case_name := "no_spit"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("case="):
			case_name = argument.trim_prefix("case=")
	if not LOADOUTS.has(case_name):
		await _finish(false, "unknown case %s" % case_name)
		return
	var slots: Array = LOADOUTS[case_name]
	var store: CheckpointStore = STORE_SCRIPT.new()
	var entry := {
		"save_version": 1,
		"checkpoint_room_id": "R04",
		"learned_abilities": ["sticky_spit", "elastic_shell"],
		"unlocked_slots": 1,
		"loadout": ["elastic_shell", ""],
		"collected_cores": [],
		"completed_rooms": ["R01", "R02", "R03"],
		"slice_complete": false,
	}
	if not store.write_checkpoint(entry)["ok"]:
		await _finish(false, "R04 entry write")
		return
	set_meta(&"checkpoint_active", true)
	var room := (load("res://scenes/r04_core_trial.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await _steps(8)
	var player := room.get_node("SlimePlayer") as SlimeController
	if room.get("stage") != &"core" or player.get_slot_ability(1) != &"elastic_shell":
		await _finish(false, "R04 entry restore")
		return
	var core: Node3D = room.get("_core")
	if not is_instance_valid(core):
		await _finish(false, "R04 core missing")
		return
	player.global_position = core.global_position + Vector3(0.0, 0.05, 1.0)
	player.velocity = Vector3.ZERO
	await _steps(7)
	Input.action_press(&"interact")
	await _steps(39)
	Input.action_release(&"interact")
	await _steps(143)
	if player.unlocked_slots != 2:
		await _finish(false, "R04 core did not open second slot")
		return
	var sprout: BorrowableEnemy
	for enemy: Node in get_nodes_in_group(&"enemies"):
		if enemy is BorrowableEnemy and enemy.kind == "sprout":
			sprout = enemy
			break
	if not is_instance_valid(sprout):
		await _finish(false, "R04 Sprout missing")
		return
	sprout.player_target = null
	var r04_hits := await _defeat_enemy_with_whip(player, sprout)
	if r04_hits != 5:
		await _finish(false, "R04 Sprout took %d player whips, expected five" % r04_hits)
		return
	print("R04_SPROUT case=%s whip_hits=%d" % [case_name, r04_hits])
	await _steps(5)
	var source := _find_source(&"slime_spikes")
	if not is_instance_valid(source):
		await _finish(false, "R04 spike source missing")
		return
	await _absorb(player, source)
	if room.get("stage") != &"r04_exit" or not player.has_learned(&"slime_spikes"):
		await _finish(false, "R04 skill not absorbed")
		return
	player.equip_ability(1, &"")
	player.equip_ability(2, &"")
	if not player.equip_ability(1, slots[0]) or not player.equip_ability(2, slots[1]):
		await _finish(false, "R04 loadout selection")
		return
	player.global_position = Vector3(0.0, 0.05, -8.2)
	player.velocity = Vector3.ZERO
	await _steps(125)
	Input.action_press(&"interact")
	var reached_r05 := await _wait_scene("res://scenes/r05_mixed.tscn", 130)
	Input.action_release(&"interact")
	if not reached_r05 or not _saved(store, "R05", slots, false):
		await _finish(false, "R04→R05 transfer/save")
		return
	room = current_scene
	player = room.get_node("SlimePlayer") as SlimeController
	if not _has_loadout(player, slots):
		await _finish(false, "R05 loadout lost")
		return
	var mixed_sprout: BorrowableEnemy
	for candidate: Node in get_nodes_in_group(&"enemies"):
		candidate.set("player_target", null)
		if candidate is BorrowableEnemy and candidate.kind == "sprout":
			mixed_sprout = candidate
	if not is_instance_valid(mixed_sprout):
		await _finish(false, "R05 Sprout missing")
		return
	player.global_position = mixed_sprout.global_position + Vector3(0.0, 0.05, 3.2)
	player.velocity = Vector3.ZERO
	await _steps(8)
	var health_before := mixed_sprout.health
	if case_name == "spit_spikes":
		await _press_action(&"ability_slot_1")
		await _steps(28)
		if mixed_sprout.health >= health_before or mixed_sprout.get_sticky_time_left() <= 0.0:
			await _finish(false, "R05 equipped spit did not hit and stick")
			return
	var health_before_spikes := mixed_sprout.health
	await _press_action(&"ability_slot_2")
	await _steps(28)
	var spike_damage := health_before_spikes - mixed_sprout.health
	var expected_spike_damage := 33 if case_name == "spit_spikes" else 22
	if spike_damage != expected_spike_damage:
		await _finish(false, "R05 equipped spikes damage=%d expected=%d" % [spike_damage, expected_spike_damage])
		return
	if case_name == "spit_spikes" and mixed_sprout.get_sticky_time_left() > 0.0:
		await _finish(false, "R05 sticky bonus was not consumed")
		return
	_save_frame("%s_r05_combat.png" % case_name)
	var whip_damage := 0
	if case_name == "no_spit":
		await _steps(25)
		player.global_position = mixed_sprout.global_position + Vector3(0.0, 0.05, 1.45)
		player.velocity = Vector3.ZERO
		await _steps(8)
		var health_before_whip := mixed_sprout.health
		await _press_action(&"attack_primary")
		await _steps(12)
		whip_damage = health_before_whip - mixed_sprout.health
		if whip_damage != SlimeController.WHIP_DAMAGE:
			await _finish(false, "R05 whip damage=%d expected=%d" % [whip_damage, SlimeController.WHIP_DAMAGE])
			return
	print("R05_COMBAT case=%s spit_damage=%d spike_damage=%d whip_damage=%d sticky_combo=%s" % [case_name, health_before - health_before_spikes, spike_damage, whip_damage, case_name == "spit_spikes"])
	var combat_targets: Array[Node3D] = []
	for enemy: Node in get_nodes_in_group(&"enemies"):
		if enemy is Spitter or enemy is BorrowableEnemy:
			combat_targets.append(enemy as Node3D)
	var enemy_count := 0
	var r05_whips := 0
	for enemy: Node3D in combat_targets:
		var hits := await _defeat_enemy_with_whip(player, enemy)
		if hits <= 0:
			await _finish(false, "R05 player whip did not defeat %s" % enemy.name if is_instance_valid(enemy) else "R05 enemy vanished before defeat")
			return
		enemy_count += 1
		r05_whips += hits
	await _steps(90)
	if enemy_count != 3 or room.get("stage") != &"complete":
		await _finish(false, "R05 clear")
		return
	print("R05_CLEAR case=%s enemies=%d finishing_whips=%d" % [case_name, enemy_count, r05_whips])
	room.call("_enter_r06")
	if not await _wait_scene("res://scenes/r06_press.tscn", 30) or not _saved(store, "R06", slots, false):
		await _finish(false, "R05→R06 transfer/save")
		return
	room = current_scene
	player = room.get_node("SlimePlayer") as SlimeController
	if not _has_loadout(player, slots):
		await _finish(false, "R06 loadout lost")
		return
	player.global_position = Vector3(0.0, 0.05, 2.6)
	player.velocity = Vector3.ZERO
	await _steps(4)
	var natural_open := false
	for tick in 240:
		if room.get("press_phase") == &"open" and float(room.get("phase_left")) > 2.2 and is_zero_approx(float(room.get("sticky_open_left"))):
			natural_open = true
			break
		await physics_frame
	if not natural_open:
		await _finish(false, "R06 natural press opening")
		return
	Input.action_press(&"move_forward")
	for tick in 85:
		await physics_frame
		if player.global_position.z < -1.6:
			break
	Input.action_release(&"move_forward")
	var press_clear := player.global_position.z < -1.6 and player.health == 100 and is_zero_approx(float(room.get("sticky_open_left")))
	if not press_clear:
		await _finish(false, "R06 press crossing")
		return
	player.global_position = Vector3(0.0, 0.05, -2.0)
	player.velocity = Vector3.ZERO
	await _steps(4)
	Input.action_press(&"move_forward")
	Input.action_press(&"jump")
	await _steps(2)
	Input.action_release(&"jump")
	await _steps(40)
	Input.action_release(&"move_forward")
	var gap_clear := player.global_position.z < -4.8 and player.global_position.y > -0.5 and player.health == 100
	if not gap_clear:
		await _finish(false, "R06 gap jump")
		return
	player.global_position = Vector3(0.0, 0.05, -7.55)
	player.velocity = Vector3.ZERO
	await _steps(8)
	Input.action_press(&"interact")
	await _steps(2)
	Input.action_release(&"interact")
	if room.get("stage") != &"complete":
		await _finish(false, "R06 exit")
		return
	room.call("_enter_r07")
	if not await _wait_scene("res://scenes/r07_guardian.tscn", 30) or not _saved(store, "R07", slots, false):
		await _finish(false, "R06→R07 transfer/save")
		return
	room = current_scene
	player = room.get_node("SlimePlayer") as SlimeController
	if not _has_loadout(player, slots):
		await _finish(false, "R07 loadout lost")
		return
	var boss: ExitGuardian = room.get_node("ExitGuardian")
	boss.player_target = null
	player.global_position = boss.global_position + Vector3(0.0, 0.05, 1.5)
	player.velocity = Vector3.ZERO
	await _steps(8)
	var boss_hits := 0
	for strike in 18:
		await _press_action(&"attack_primary")
		await _steps(35)
		boss_hits += 1
		var expected_health := ExitGuardian.MAX_HEALTH - boss_hits * SlimeController.WHIP_DAMAGE
		if expected_health > 0 and (not is_instance_valid(boss) or boss.health != expected_health):
			await _finish(false, "R07 whip %d did not deal 10 damage" % boss_hits)
			return
		if strike == 2:
			_save_frame("%s_guardian_combat.png" % case_name)
	if room.get("stage") != &"r07_exit" or is_instance_valid(boss):
		await _finish(false, "R07 boss survived player whip or gate closed")
		return
	_save_frame("%s_exit_open.png" % case_name)
	player.global_position = Vector3(0.0, 0.05, -10.4)
	player.velocity = Vector3.ZERO
	await _steps(8)
	Input.action_press(&"interact")
	await _steps(2)
	Input.action_release(&"interact")
	var complete: bool = room.get("stage") == &"complete" and _saved(store, "R07", slots, true)
	print("S5_ROUTE_LOADOUT case=%s enemies=%d guardian_whips=%d natural_open=%s press=%s gap=%s complete=%s" % [case_name, enemy_count, boss_hits, natural_open, press_clear, gap_clear, complete])
	print("PASS S5_ROUTE_LOADOUT_%s" % case_name if complete else "FAIL S5_ROUTE_LOADOUT_%s" % case_name)
	await _finish(complete, "R07 completion")


func _has_loadout(player: SlimeController, slots: Array) -> bool:
	return player.unlocked_slots == 2 and player.get_slot_ability(1) == slots[0] and player.get_slot_ability(2) == slots[1]


func _saved(store: CheckpointStore, room_id: String, slots: Array, complete: bool) -> bool:
	var result := store.read_checkpoint()
	if result["status"] != "ok":
		return false
	var snapshot: Dictionary = result["snapshot"]
	return snapshot["checkpoint_room_id"] == room_id and snapshot["loadout"] == [String(slots[0]), String(slots[1])] and snapshot["slice_complete"] == complete


func _find_source(ability_id: StringName) -> AbsorbSource:
	for candidate: Node in get_nodes_in_group(&"absorb_sources"):
		if candidate is AbsorbSource and candidate.ability_id == ability_id:
			return candidate
	return null


func _absorb(player: SlimeController, source: AbsorbSource) -> void:
	for tick in 80:
		if player.get("_action") == &"":
			break
		await physics_frame
	player.global_position = source.global_position + Vector3(0.0, 0.05, 1.0)
	player.velocity = Vector3.ZERO
	await _steps(7)
	Input.action_press(&"interact")
	await _steps(39)
	Input.action_release(&"interact")
	await _steps(6)


func _wait_scene(path: String, ticks: int) -> bool:
	for tick in ticks:
		await physics_frame
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path:
			return true
	return false


func _steps(count: int) -> void:
	for tick in count:
		await physics_frame


func _press_action(action: StringName) -> void:
	Input.action_press(action)
	await _steps(2)
	Input.action_release(action)


func _defeat_enemy_with_whip(player: SlimeController, enemy: Node3D) -> int:
	var hits := 0
	var remaining_health := int(enemy.get("health"))
	while remaining_health > 0 and hits < 8:
		var ready := false
		for tick in 80:
			if player.get("_action") == &"":
				ready = true
				break
			await physics_frame
		if not ready or not is_instance_valid(enemy):
			return -1
		player.global_position = enemy.global_position + Vector3(0.0, 0.05, 1.45)
		player.velocity = Vector3.ZERO
		await _steps(8)
		var health_before_hit := int(enemy.get("health"))
		await _press_action(&"attack_primary")
		await _steps(12)
		var expected_health := maxi(0, health_before_hit - SlimeController.WHIP_DAMAGE)
		if is_instance_valid(enemy):
			if int(enemy.get("health")) != expected_health:
				return -1
		elif expected_health != 0:
			return -1
		hits += 1
		remaining_health = expected_health
	return hits if remaining_health == 0 else -1


func _save_frame(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FRAME_DIR))
	if directory_error != OK:
		push_error("Could not create capture directory: %d" % directory_error)
		return
	var image := root.get_texture().get_image()
	var result := image.save_png(ProjectSettings.globalize_path(FRAME_DIR + filename))
	if result != OK:
		push_error("Could not save %s: %d" % [filename, result])


func _finish(passed: bool, reason: String) -> void:
	if not passed:
		print("FAIL S5_ROUTE_LOADOUT %s" % reason)
	for action: StringName in [&"interact", &"move_forward", &"jump", &"attack_primary", &"ability_slot_1", &"ability_slot_2"]:
		if InputMap.has_action(action):
			Input.action_release(action)
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(current_scene):
		var old_room := current_scene
		current_scene = null
		old_room.queue_free()
	await _steps(12)
	quit(0 if passed else 1)
