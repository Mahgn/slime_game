extends SceneTree

# A virtual player, not a pacing estimate for a human playthrough. The harness
# only writes Input/pointer and invokes normal actions, interaction and retry.
# Run: godot --headless --path . --script tests/keepers_world_combat_test.gd
# Native screenshots: omit --headless and append -- --capture
# Alternate branch: append -- --alternate (cistern + armory).
# Sensitivity run: append -- --delayed (sampled decisions, not a novice model).
var run_scene := "res://scenes/keepers/keepers_world.tscn"
var output_folder := "res://output/keepers_seamless_2026_10_08/"
const DEFAULT_PATH := ["entry", "junction", "furnace", "cinder_gallery", "hub", "garden", "root_cellar", "gauntlet", "summit"]
const ALTERNATE_PATH := ["entry", "junction", "cistern", "pump_room", "hub", "armory", "barracks", "gauntlet", "summit"]
const MAX_FRAMES := 48000
const RETRIES_PER_ROOM := 2
const DELAYED_DECISION_SECONDS := 0.18
const DELAYED_WHIP_SECONDS := 0.75
const MOVE_ACTIONS := [&"move_right", &"move_left", &"move_back", &"move_forward"]

var level: SlimeKeepersWorld
var route: Array = DEFAULT_PATH.duplicate()
var facility := false
var capture := false
var delayed := false
var frames := 0
var done := false
var started_msec := 0
var failures: Array[String] = []
var checks: Array[Dictionary] = []
var attempts: Array[Dictionary] = []
var events: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var deaths: Dictionary = {}
var actions: Dictionary = {}
var resolved_hits := {"slime_whip": 0, "sticky_spit": 0, "slime_spikes": 0}
var enemy_records: Dictionary = {}
var active_attempt: Dictionary = {}
var player_damage_taken := 0
var enemy_damage_observed := 0
var physical_distance := 0.0
var focus_resumes := 0
var jump_requests := 0
var absorb_hold_frames := 0
var door_interactions := 0
var room_elapsed_including_retries: Dictionary = {}
var _last_elapsed := 0.0
var _tracked_player_id := 0
var _previous_health := 100
var _previous_position := Vector3.ZERO
var _previous_room := ""
var _move_wish := Vector3.ZERO
var _jump_down := false
var _last_jump_frame := -100
var _stall_frames := 0
var _escape_until := 0
var _orbit_sign := 1.0
var _captured_waves: Dictionary = {}
var _next_combat_decision_at := 0.0
var _next_whip_at := 0.0
var _last_whip_started_at := -1.0
var _minimum_whip_interval := -1.0
var combat_decision_updates := 0
var _nav_until := 0
var _nav_goal := Vector3.INF
var _nav_points := PackedVector3Array()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	capture = args.has("--capture") and DisplayServer.get_name() != "headless"
	delayed = args.has("--delayed")
	if args.has("--alternate"):
		route = ALTERNATE_PATH.duplicate()
	facility = args.has("--facility")
	if facility:
		run_scene = "res://scenes/keepers/keepers_facility.tscn"
		output_folder = "res://output/keepers_finalization_2026_10_08/"
		route = ["entry","cistern","pump_room","hub","armory","summit"] if args.has("--alternate") else ["entry","furnace","hub","garden","summit"]
	for arg: String in args:
		if arg.begins_with("--output=res://output/"):
			output_folder = arg.trim_prefix("--output=").trim_suffix("/")+"/"
	started_msec = Time.get_ticks_msec()
	node_added.connect(_observe_effect)
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_folder + _output_stem() + "_images"))
	SlimeGameSettings.current().load_settings(output_folder + _output_stem() + "_settings.cfg")
	var watchdog := Timer.new()
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.wait_time = 720.0
	watchdog.one_shot = true
	root.add_child(watchdog)
	watchdog.timeout.connect(func() -> void: _finish("TIMEOUT", "720 s wall-clock watchdog", 124))
	watchdog.start()
	if change_scene_to_file(run_scene) != OK:
		_finish("FAIL", "Cannot open run scene", 1)
		return
	await _ticks(12)
	level = current_scene as SlimeKeepersWorld
	if not is_instance_valid(level):
		_finish("FAIL", "Run scene has no SlimeKeepersWorld", 1)
		return
	if not is_instance_valid(level.geometry) or not is_instance_valid(level.navigation) or level.room_roots.size() != (10 if facility else 15) or level._transitioning:
		_finish("FAIL", "World initialization failed; see script errors", 1)
		return
	_bind_player()
	_check(level.room_id == "entry" and level.player.unlocked_slots == 1, "Normal entry, one slot")
	for index in route.size():
		if done:
			return
		var room: String = route[index]
		if level.room_id != room:
			_finish("FAIL", "Unexpected room: " + level.room_id + ", wanted " + room, 1)
			return
		if not await _clear_room():
			return
		if room == ("entry" if facility else "junction"):
			if not await _absorb(&"sticky_spit"):
				_finish("FAIL", "Could not absorb sticky_spit through held E", 1)
				return
			# Nearby remains can legitimately yield shell before spit. Learning
			# does not replace an occupied slot; choose the skill as a player can
			# through the normal safe-room loadout (same contract as spikes).
			_check(level.combat.equip_ability(1,&"sticky_spit") and level.player.get_slot_ability(1)==&"sticky_spit","Safe normal loadout equips absorbed spit in slot one")
		if room == "hub":
			if not await _absorb(&"slime_spikes"):
				_finish("FAIL", "Could not absorb slime_spikes through held E", 1)
				return
			_check(level.combat.equip_ability(1, &"slime_spikes"), "Safe normal loadout equips learned spikes in slot one")
		await _shot(room + "-cleared")
		var destination: String = route[index + 1] if index + 1 < route.size() else "VICTORY"
		if not await _travel(destination):
			_finish("FAIL", "Physical continuous passage failed: " + room + " -> " + destination, 1)
			return
	_check(level.victory and level.finished, "Real guardian defeat and summit exit complete route")
	for room: String in route:
		_check(level.cleared.has(room), "Combat-cleared room: " + room)
	for ability: StringName in [&"sticky_spit", &"slime_spikes"]:
		_check(level.player.has_learned(ability), "Learned through absorption: " + String(ability))
	for ability: String in ["slime_whip", "sticky_spit", "slime_spikes"]:
		_check(int(actions.get(ability, 0)) > 0, "Real action started: " + ability)
		_check(int(resolved_hits.get(ability, 0)) > 0, "Runtime reported a hit: " + ability)
	_check(enemy_damage_observed > 0 and physical_distance > 30.0, "Observed real enemy HP loss and physical travel")
	_check(level.secrets_found.is_empty() and level.player.unlocked_slots == 1, "Main branch completed without secret second slot")
	if delayed:
		_check(_minimum_whip_interval >= DELAYED_WHIP_SECONDS - 0.0001, "Delayed policy observed minimum whip interval")
	await _shot("victory")
	_finish("PASS" if failures.is_empty() else "FAIL", "Completed virtual combat route", 0 if failures.is_empty() else 1)


func _clear_room() -> bool:
	var room := level.room_id
	for attempt_index in RETRIES_PER_ROOM + 1:
		_bind_player()
		_next_combat_decision_at = level.elapsed_seconds
		active_attempt = {
			"room": room, "attempt": attempt_index + 1,
			"start_elapsed_seconds": level.elapsed_seconds, "start_frame": frames,
			"start_health": level.player.health, "damage_taken_at_start": player_damage_taken,
			"status": "RUNNING"
		}
		_event("attempt_started", {"attempt": attempt_index + 1})
		_orbit_sign = 1.0 if attempt_index % 2 == 0 else -1.0
		while not done and not level.finished and not level.room_is_safe():
			_combat_step()
			await _ticks(1)
			var wave_key := "%s-%d-wave%d" % [room, attempt_index + 1, level.wave_index]
			if capture and level.alive_enemies().size() > 0 and not _captured_waves.has(wave_key):
				_captured_waves[wave_key] = true
				await _shot(wave_key)
		if done:
			return false
		_release_input()
		if level.player.is_alive() and level.room_is_safe():
			_close_attempt("CLEARED")
			_check(true, "Actual combat cleared %s, attempt %d" % [room, attempt_index + 1])
			return true
		deaths[room] = int(deaths.get(room, 0)) + 1
		_close_attempt("DEATH")
		_event("death", {"attempt": attempt_index + 1})
		await _shot("%s-death%d" % [room, attempt_index + 1])
		if attempt_index >= RETRIES_PER_ROOM:
			_finish("FAIL", "Death retry budget exhausted in " + room, 1)
			return false
		# This is the same room-entry retry available to a dead player. It creates
		# a new actor and restores the runtime snapshot; the test changes no HP.
		level.retry_room()
		await _ticks(12)
		if level.finished or level.room_id != room or not level.player.is_alive():
			_finish("FAIL", "Normal retry did not restore " + room, 1)
			return false
	return false


func _combat_step() -> void:
	Input.action_release(&"interact")
	if _jump_down:
		Input.action_release(&"jump")
		_jump_down = false
	# Sample combat observations and commands at this interval. The previous
	# movement Input remains held between decisions; jump releases still happen
	# next physics step. This is decision sampling, not fixed human reaction lag.
	if delayed and level.elapsed_seconds + 0.00001 < _next_combat_decision_at:
		return
	_next_combat_decision_at = level.elapsed_seconds + DELAYED_DECISION_SECONDS
	combat_decision_updates += 1
	var enemies := level.alive_enemies()
	for enemy: Node3D in enemies:
		_watch_enemy(enemy)
	var target := _choose_target(enemies)
	var goal: Vector3 = level.current_room().spawn
	if facility and not is_instance_valid(target):
		goal = level.encounter_focus(level.room_id)
	if is_instance_valid(target):
		goal = target.global_position
		level.player.controls.pointer = level.player.presentation.camera.unproject_position(goal + Vector3.UP * 0.65)
		_request_attack(target)
		_request_dodge_jump(enemies)
	var wish := _best_motion(goal, enemies, is_instance_valid(target))
	_set_motion(wish)


func _choose_target(enemies: Array) -> Node3D:
	var chosen: Node3D
	var best := INF
	for enemy: Node3D in enemies:
		var score := _horizontal_distance(enemy.global_position, level.player.global_position)
		if enemy is Spitter:
			score -= 1.1
		score += float(enemy.get("health")) * 0.008
		if score < best:
			best = score
			chosen = enemy
	return chosen


func _request_attack(target: Node3D) -> void:
	var hero := level.player
	if hero._action != &"" or not hero.is_alive():
		return
	var distance := _horizontal_distance(hero.global_position, target.global_position)
	var ability := hero.get_slot_ability(1)
	if ability == &"sticky_spit" and distance >= 1.85 and distance < 11.5 and hero.cooldown_remaining(ability) <= 0.0:
		hero.request_action(ability)
	elif ability == &"slime_spikes" and hero.is_on_floor() and distance > 1.9 and distance < 5.4 and hero.cooldown_remaining(ability) <= 0.0:
		hero.request_action(ability)
	elif distance < 1.8 and (not delayed or level.elapsed_seconds >= _next_whip_at):
		if hero.request_action(&"slime_whip") and delayed:
			_next_whip_at = level.elapsed_seconds + DELAYED_WHIP_SECONDS


func _request_dodge_jump(enemies: Array) -> void:
	var hero := level.player
	if not hero.is_on_floor() or frames - _last_jump_frame < 45:
		return
	for enemy: Node3D in enemies:
		if enemy.get_attack_phase() != &"windup" or float(enemy.get("_phase_left")) > 0.30:
			continue
		var line_or_radial: bool = (enemy is BorrowableEnemy and enemy.kind == "sprout") or (enemy is ExitGuardian and enemy._attack_index != 1)
		if line_or_radial and _horizontal_distance(hero.global_position, enemy.global_position) < 6.0:
			Input.action_press(&"jump")
			_jump_down = true
			_last_jump_frame = frames
			jump_requests += 1
			return


func _best_motion(goal: Vector3, enemies: Array, fight: bool) -> Vector3:
	var hero := level.player
	var at := hero.global_position
	if not level.navigation.can_travel(at, goal):
		if frames >= _nav_until or goal.distance_to(_nav_goal) > 1.5:
			_nav_points = level.navigation.path_between(at, goal)
			_nav_until = frames + 18
			_nav_goal = goal
		while _nav_points.size() > 0 and _horizontal_distance(at, _nav_points[0]) < 0.7:
			_nav_points.remove_at(0)
		if _nav_points.size() > 0:
			goal = _nav_points[0]
			fight = false
	var toward := goal - at
	toward.y = 0.0
	var desired := toward.normalized() if toward.length() > (1.25 if fight else 0.35) else Vector3.ZERO
	if frames < _escape_until:
		desired = (Vector3(-desired.z, 0, desired.x) * _orbit_sign).normalized()
	var candidates: Array[Vector3] = [desired, Vector3.ZERO]
	for index in 16:
		var angle := TAU * float(index) / 16.0
		candidates.append(Vector3(cos(angle), 0, sin(angle)))
	var speed := SlimeController.MOVE_SPEED * (0.75 if hero._action != &"" else 1.0)
	var best := INF
	var selected := Vector3.ZERO
	var horizon := 0.28 if fight else 0.07
	for wish: Vector3 in candidates:
		var predicted := at + wish * speed * horizon
		var distance := _horizontal_distance(predicted, goal)
		var score := absf(distance - 1.28) * 2.0 if fight else distance * 3.0
		score -= wish.dot(desired) * 0.6
		# The driver obeys real support and walls, never the old arena bounds.
		if not _supported(predicted):
			score += 150.0
		if wish.length_squared() > 0.1 and _wall_ahead(at, wish, speed * horizon + 0.25):
			score += 100.0
		for enemy: Node3D in enemies:
			score += _enemy_danger(enemy, predicted)
			score += maxf(0.0, (1.15 if enemy is ExitGuardian else 0.8) - _horizontal_distance(predicted, enemy.global_position)) * 20.0
		score += _projectile_danger(at, wish * speed)
		# A consistent tangent avoids oscillating across an incoming shot.
		if fight and toward.length_squared() > 0.1:
			var tangent := Vector3(-toward.z, 0, toward.x).normalized() * _orbit_sign
			score -= wish.dot(tangent) * 0.08
		if score < best:
			best = score
			selected = wish
	return selected


func _enemy_danger(enemy: Node3D, predicted: Vector3) -> float:
	if enemy.get_attack_phase() != &"windup":
		return 0.0
	if enemy is BorrowableEnemy and enemy._phase == &"shell":
		return 0.0
	var left := float(enemy.get("_phase_left"))
	if left > 0.62:
		return 0.0
	var delta := predicted - enemy.global_position
	delta.y = 0.0
	var distance := delta.length()
	var aim: Vector3 = enemy.get("_locked_direction") if bool(enemy.get("_aim_locked")) else level.player.global_position - enemy.global_position
	aim.y = 0.0
	aim = aim.normalized()
	if enemy is BorrowableEnemy and enemy.kind == "armorer":
		return 24.0 * maxf(0.0, 2.6 - distance) if not bool(enemy.get("_aim_locked")) or aim.dot(delta.normalized()) > 0.15 else 0.0
	if enemy is ExitGuardian:
		if enemy._attack_index == 2:
			return 35.0 * maxf(0.0, 3.5 - distance)
		if enemy._attack_index == 1:
			return 28.0 * maxf(0.0, 3.1 - distance) if not enemy._aim_locked or aim.dot(delta.normalized()) > 0.3 else 0.0
	var along := delta.dot(aim)
	var across := absf(delta.dot(Vector3(-aim.z, 0, aim.x)))
	var reach := 11.0 if enemy is Spitter else 6.0
	if along > -0.2 and along < reach:
		return (14.0 if enemy is Spitter else 28.0) * maxf(0.0, 1.15 - across)
	return 0.0


func _projectile_danger(at: Vector3, velocity: Vector3) -> float:
	var penalty := 0.0
	for projectile: Node in get_nodes_in_group(&"enemy_projectiles"):
		if not is_instance_valid(projectile) or not projectile is SpitProjectile:
			continue
		var relative: Vector3 = at - projectile.global_position
		relative.y = 0.0
		var approach: Vector3 = projectile.direction * projectile.speed - velocity
		approach.y = 0.0
		if approach.length_squared() < 0.1:
			continue
		var when: float = relative.dot(approach) / approach.length_squared()
		if when < 0.0 or when > 0.42:
			continue
		var miss: float = (relative - approach * when).length()
		penalty += 38.0 * maxf(0.0, 0.78 - miss)
	return penalty


func _wall_ahead(at: Vector3, wish: Vector3, distance: float) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.42, at + wish * distance + Vector3.UP * 0.42, 1)
	ray.exclude = [level.player.get_rid()]
	return not level.player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


func _drive(at: Vector3, tolerance: float = 0.45) -> bool:
	for unused in 1000:
		if done or not level.player.is_alive():
			return false
		if _horizontal_distance(level.player.global_position, at) < tolerance:
			_set_motion(Vector3.ZERO)
			await _ticks(8)
			for landing_frame in 45:
				if level.player.is_on_floor():
					break
				await _ticks(1)
			return level.player.is_on_floor()
		_set_motion(_best_motion(at, [], false))
		await _ticks(1)
	_set_motion(Vector3.ZERO)
	_event("walk_timeout", {"target": _v3(at), "position": _v3(level.player.global_position)})
	return false


func _absorb(ability: StringName) -> bool:
	if level.player.has_learned(ability):
		return true
	for retry in 4:
		var source: AbsorbSource
		var nearest := INF
		for candidate: Node in get_nodes_in_group(&"absorb_sources"):
			if candidate is AbsorbSource and candidate.ability_id == ability and not candidate.is_claimed():
				var distance := _horizontal_distance(candidate.global_position, level.player.global_position)
				if distance < nearest:
					nearest = distance
					source = candidate
		if not is_instance_valid(source):
			_event("missing_source", {"ability": String(ability)})
			return false
		var source_at := source.global_position
		var stand := source_at + (level.player.global_position - source_at).normalized() * 0.65
		if not await _drive(stand, 0.3):
			return false
		await _hold_absorb()
		if level.player.has_learned(ability):
			_check(true, "Real held E absorbed " + String(ability))
			return true
	return false


func _hold_absorb() -> void:
	_set_motion(Vector3.ZERO)
	Input.action_release(&"interact")
	await _ticks(3)
	Input.action_press(&"interact")
	for unused in 48:
		absorb_hold_frames += 1
		await _ticks(1)
		if done:
			break
	Input.action_release(&"interact")
	await _ticks(3)


func _travel(destination: String) -> bool:
	var from_room: String = level.room_id
	if destination == "VICTORY":
		for point: Vector3 in level.current_room().walk_points:
			if not await _drive(point):
				return false
		if not await _drive(level.current_room().exit_point):
			return false
		for retry in 3:
			if is_instance_valid(level.player.get_nearest_absorb_source()):
				await _hold_absorb()
			level.try_interact()
			await _ticks(4)
			if level.victory:
				return true
		return false
	var points: Array = level.rooms[from_room].port_paths[destination].duplicate()
	for edge: Dictionary in level.connections:
		if edge.a == from_room and edge.b == destination:
			points.append_array(edge.path)
		elif edge.b == from_room and edge.a == destination:
			var backwards: Array = edge.path.duplicate()
			backwards.reverse()
			points.append_array(backwards)
	var arrival: Array = level.rooms[destination].port_paths[from_room].duplicate()
	arrival.reverse()
	points.append_array(arrival)
	var actor_id := level.player.get_instance_id()
	for point: Vector3 in points:
		if not await _drive(point, 0.45):
			return false
	_check(level.room_id == destination and level.player.get_instance_id() == actor_id, "Walked continuously without E: " + from_room + " -> " + destination)
	return level.room_id == destination


func _supported(at: Vector3) -> bool:
	# Ordinary walking may step off a table reached by a real dodge jump.
	# Requiring same-height support traps the driver on the tabletop.
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 1.6, 1)
	var hit := level.player.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and (hit.normal as Vector3).y > 0.65


func _set_motion(wish: Vector3) -> void:
	_move_wish = wish
	if not is_instance_valid(level) or not is_instance_valid(level.player):
		return
	var axes := level.player.controls.world_direction_to_screen_axes(wish)
	Input.action_press(&"move_right", maxf(0, axes.x))
	Input.action_press(&"move_left", maxf(0, -axes.x))
	Input.action_press(&"move_back", maxf(0, axes.y))
	Input.action_press(&"move_forward", maxf(0, -axes.y))


func _release_input() -> void:
	for action: StringName in MOVE_ACTIONS + [&"interact", &"jump", &"attack_primary", &"ability_slot_1", &"ability_slot_2"]:
		Input.action_release(action)
	_move_wish = Vector3.ZERO
	_jump_down = false


func _ticks(count: int) -> void:
	for unused in count:
		if done:
			return
		await physics_frame
		await process_frame
		frames += 1
		if is_instance_valid(level) and is_instance_valid(level.player):
			_bind_player()
			# Native focus changes should not hang an unattended test. Resume via
			# the normal pause action, never during death/victory or loadout UI.
			if paused and not level.finished and not level.hud.loadout_open:
				level._resume_game()
				focus_resumes += 1
				_event("test_resumed_focus_pause")
			var distance := _horizontal_distance(_previous_position, level.player.global_position)
			if _previous_room == level.room_id and distance < 0.5:
				physical_distance += distance
				_stall_frames = _stall_frames + 1 if _move_wish.length_squared() > 0.2 and distance < 0.006 else 0
			if _stall_frames > 45:
				_escape_until = frames + 40
				_stall_frames = 0
				_orbit_sign *= -1.0
			_previous_position = level.player.global_position
			_previous_room = level.room_id
			room_elapsed_including_retries[level.room_id] = float(room_elapsed_including_retries.get(level.room_id, 0.0)) + maxf(0.0, level.elapsed_seconds - _last_elapsed)
			_last_elapsed = level.elapsed_seconds
			for enemy: Node3D in level.alive_enemies():
				_watch_enemy(enemy)
			if frames % 600 == 0:
				print("WORLD_COMBAT_PROGRESS room=%s hp=%d wave=%d enemies=%d simulated=%.2f frames=%d" % [level.room_id, level.player.health, level.wave_index, level.alive_enemies().size(), level.elapsed_seconds, frames])
		if frames >= MAX_FRAMES:
			_finish("TIMEOUT", "48000 physics-step harness budget exhausted", 124)
			return


func _bind_player() -> void:
	if level.player.get_instance_id() == _tracked_player_id:
		return
	_tracked_player_id = level.player.get_instance_id()
	_previous_health = level.player.health
	_previous_position = level.player.global_position
	_previous_room = level.room_id
	level.player.health_changed.connect(_on_player_health)
	level.player.action_started.connect(_on_action)
	level.player.whip_hit.connect(func(_at: Vector3) -> void: resolved_hits["slime_whip"] += 1)
	level.player.ability_unlocked.connect(func(ability: StringName) -> void: _event("ability_absorbed", {"ability": String(ability)}))


func _on_player_health(current: int, _maximum: int) -> void:
	player_damage_taken += maxi(0, _previous_health - current)
	_previous_health = current


func _on_action(action: StringName) -> void:
	var key := String(action)
	actions[key] = int(actions.get(key, 0)) + 1
	if action == &"slime_whip":
		if _last_whip_started_at >= 0.0:
			var interval := level.elapsed_seconds - _last_whip_started_at
			_minimum_whip_interval = interval if _minimum_whip_interval < 0.0 else minf(_minimum_whip_interval, interval)
		_last_whip_started_at = level.elapsed_seconds
	_event("action_started", {"ability": key})


func _observe_effect(node: Node) -> void:
	if node is SpitProjectile and node.team == &"player":
		node.resolved.connect(func(_at: Vector3, hit: bool) -> void:
			if hit:
				resolved_hits["sticky_spit"] += 1)
	elif node is SpikeLine and node.team == &"player":
		node.hit_target.connect(func(_at: Vector3, _empowered: bool) -> void: resolved_hits["slime_spikes"] += 1)


func _watch_enemy(enemy: Node3D) -> void:
	var id := enemy.get_instance_id()
	var hp := int(enemy.get("health"))
	if not enemy_records.has(id):
		var kind := "spitter" if enemy is Spitter else ("guardian" if enemy is ExitGuardian else String(enemy.get("kind")))
		enemy_records[id] = {"room": level.room_id, "attempt": active_attempt.get("attempt", 1), "kind": kind, "start_hp": hp, "last_hp": hp, "damage_observed": 0, "dead": false}
		if enemy is ExitGuardian:
			enemy.died.connect(_on_guardian_death.bind(enemy))
		else:
			enemy.died.connect(_on_enemy_death)
	var row: Dictionary = enemy_records[id]
	var loss := maxi(0, int(row.last_hp) - hp)
	row.damage_observed = int(row.damage_observed) + loss
	row.last_hp = hp
	enemy_damage_observed += loss


func _on_enemy_death(enemy: Node3D, _ability: StringName, _at: Vector3) -> void:
	_record_death(enemy)


func _on_guardian_death(enemy: Node3D) -> void:
	_record_death(enemy)


func _record_death(enemy: Node3D) -> void:
	_watch_enemy(enemy)
	enemy_records[enemy.get_instance_id()].dead = true
	_event("enemy_died", {"kind": enemy_records[enemy.get_instance_id()].kind})


func _close_attempt(status: String) -> void:
	if active_attempt.is_empty():
		return
	active_attempt.status = status
	active_attempt.end_elapsed_seconds = level.elapsed_seconds
	active_attempt.elapsed_seconds = level.elapsed_seconds - float(active_attempt.start_elapsed_seconds)
	active_attempt.end_frame = frames
	active_attempt.end_health = level.player.health
	active_attempt.damage_taken = player_damage_taken - int(active_attempt.damage_taken_at_start)
	active_attempt.wave_index = level.wave_index
	attempts.append(active_attempt.duplicate(true))
	active_attempt.clear()


func _shot(label: String) -> void:
	if not capture or done:
		return
	await _ticks(2)
	RenderingServer.force_draw()
	var file := output_folder + _output_stem() + "_images/" + label + ".png"
	var error := root.get_texture().get_image().save_png(file)
	shots.append({"path": file, "result": error, "frame": frames})
	if error != OK:
		_check(false, "Capture failed: " + label)


func _check(passed: bool, label: String) -> void:
	checks.append({"pass": passed, "label": label})
	print(("PASS " if passed else "FAIL ") + label)
	if not passed:
		failures.append(label)


func _event(kind: String, details: Dictionary = {}) -> void:
	var row := {"event": kind, "frame": frames, "room": level.room_id if is_instance_valid(level) else "", "elapsed_seconds": level.elapsed_seconds if is_instance_valid(level) else 0.0}
	row.merge(details)
	events.append(row)


func _finish(status: String, reason: String, exit_code: int) -> void:
	if done:
		return
	done = true
	_release_input()
	if is_instance_valid(level) and not active_attempt.is_empty():
		_close_attempt(status)
	var report := {
		"status": status, "reason": reason, "exit_code": exit_code,
		"scope": "Virtual bot physical combat, not human completion time or visual acceptance",
		"mode": "delayed" if delayed else "optimal",
		"mode_interpretation": "Decision-frequency sensitivity only; not a calibrated novice or human reaction-time model",
		"route": route, "capture": capture, "display_server": DisplayServer.get_name(),
		"engine": Engine.get_version_info(), "physics_ticks_per_second": Engine.physics_ticks_per_second,
		"physics_steps_awaited": frames, "frame_budget": MAX_FRAMES,
		"wall_seconds": float(Time.get_ticks_msec() - started_msec) / 1000.0,
		"elapsed_seconds": level.elapsed_seconds if is_instance_valid(level) else 0.0,
		"elapsed_includes_failed_attempts": true, "human_five_minute_validation": "NOT_RUN",
		"runtime_room_seconds_successful_entries": "NOT_APPLICABLE: continuous world",
		"room_elapsed_including_retries": room_elapsed_including_retries,
		"attempts": attempts, "deaths_by_room": deaths, "max_retries_per_room": RETRIES_PER_ROOM,
		"player_damage_taken": player_damage_taken, "enemy_hp_damage_observed": enemy_damage_observed,
		"physical_distance_m": physical_distance, "actions_started": actions, "resolved_hits": resolved_hits,
		"jump_requests": jump_requests, "absorb_hold_frames": absorb_hold_frames,
		"door_interactions": door_interactions, "focus_resumes": focus_resumes,
		"decision_interval_seconds": DELAYED_DECISION_SECONDS if delayed else 0.0,
		"combat_decision_updates": combat_decision_updates,
		"whip_minimum_interval_policy_seconds": DELAYED_WHIP_SECONDS if delayed else 0.0,
		"whip_minimum_interval_observed_seconds": _minimum_whip_interval,
		"between_decisions": "Previous movement input continues; jump released next physics step; no inter-room waits added",
		"policy": {"movement": "Input WASD through controls basis", "aim": "camera projection to pointer", "attacks": "request_action only", "absorption": "held Input interact", "travel": "continuous walk; interaction only at final exit", "retry": "normal retry_room", "direct_damage_or_hp_cd_mutations": false},
		"cleared": level.cleared.keys() if is_instance_valid(level) else [],
		"learned": level.player.learned_abilities.keys() if is_instance_valid(level) else [],
		"victory": level.victory if is_instance_valid(level) else false,
		"enemy_records": enemy_records.values(), "checks": checks, "failures": failures,
		"events": events, "screenshots": shots
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_folder))
	var report_path := output_folder + _output_stem() + ".json"
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		printerr("FAIL cannot write ", report_path, ": ", FileAccess.get_open_error())
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("KEEPERS_COMBAT_%s: mode=%s; %s; simulated %.2f s; frames %d; deaths %s" % [status, report.mode, reason, report.elapsed_seconds, frames, str(deaths)])
	quit(exit_code)


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _output_stem() -> String:
	return ("combat-alternate" if OS.get_cmdline_user_args().has("--alternate") else "combat") + ("-delayed" if delayed else "")


func _v3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
