extends SceneTree

# Native A/B probe of the authored dungeon: real actors, real collision and slot
# input. Relocation selects a reproducible starting point; routes use movement.
const SCENE := "res://scenes/visibility_combat/visibility_combat.tscn"
const MOVES: Array[StringName] = [&"move_right", &"move_left", &"move_back", &"move_forward"]
var out := "res://output/visibility_combat_2026_10_15/geometry/"
var part := "geometry"
var capture := false
var level: Node3D
var checks: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var visibility: Array[Dictionary] = []
var records: Array[Dictionary] = []
var projectile_events: Array[Dictionary] = []
var frames: Array[float] = []
var sampling := false
var last_draw := 0
var finished := false
var fade_trace: Array[Dictionary] = []
var last_amounts: Dictionary = {}
var last_update_time := 0.0
var fade_continuous := true
var initial_layout: Array = []


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--capture": capture = true
		if argument.begins_with("--part="): part = argument.trim_prefix("--part=")
		if argument.begins_with("--output=res://output/"):
			out = argument.trim_prefix("--output=").trim_suffix("/") + "/"
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out + "images"))
	SlimeGameSettings.current().load_settings(out + "settings.cfg")
	SlimeGameSettings.current().camera_shake = 0.0
	create_timer(235.0, true).timeout.connect(func() -> void:
		_check(false, "bounded 235 second watchdog")
		_finish())
	node_added.connect(_watch_projectile)
	if DisplayServer.get_name() == "headless": capture = false
	else:
		root.size = Vector2i(1280, 720)
		DisplayServer.window_set_size(root.size)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		RenderingServer.frame_post_draw.connect(_sample_frame)
	for mode: int in 2:
		if not await _fresh_scene(mode): _finish(); return
		if part == "combat": await _combat_mode(mode)
		else: await _geometry_mode(mode)
	if part == "geometry":
		_check(fade_continuous, "both physical crossings have time-bounded section fade changes")
	_finish()


func _fresh_scene(mode: int) -> bool:
	_release()
	paused = false
	seed(4873)
	var error: Error = change_scene_to_file(SCENE)
	_check(error == OK, "mode %d real dungeon comparison loads" % mode)
	if error != OK: return false
	await _ticks(3)
	level = current_scene as Node3D
	for tick: int in 900:
		if is_instance_valid(level) and bool(level.get("ready_for_comparison")): break
		await _ticks(1)
	var ready: bool = is_instance_valid(level) and bool(level.get("ready_for_comparison"))
	_check(ready, "mode %d dungeon construction and render warmup finish" % mode)
	if not ready: return false
	level.set_test_ai_paused(true)
	level.set_compare_mode(mode)
	# Existing fixed-angle scenarios keep their explicit quarter-turn fixture.
	level.set_camera_mode(0)
	level.start_comparison()
	await _ticks(55)
	var enemies: Array = level.comparison_enemies()
	_check(enemies.size() == 4 and enemies.all(func(enemy: Spitter) -> bool: return enemy.health == Spitter.MAX_HEALTH), "mode %d starts with four original full-health creatures" % mode)
	var layout: Array = []
	for enemy: Spitter in enemies: layout.append([enemy.global_position, enemy.drop_ability_id, enemy.health])
	if initial_layout.is_empty(): initial_layout = layout
	_check(layout == initial_layout, "mode %d restores exactly the same four creature positions, types and health" % mode)
	_check(level.player is SlimeDungeonPlayer and level.player.get_slot_ability(1) == &"acid_spit" and level.player.get_ability_level(&"acid_spit") == 1, "mode %d uses actual rank-one dungeon acid and controller" % mode)
	_check(level.membrane.intact and level.membrane.strength == 2, "mode %d starts with the same closed two-hit membrane" % mode)
	return true


func _geometry_mode(mode: int) -> void:
	var signature: Dictionary = _geometry_signature()
	var actor_state: Array = _actor_state()
	var wave_state: Dictionary = level.encounters.duplicate(true)
	for angle: int in 4:
		await _angle(angle)
		for spot: Dictionary in [{"id": "west", "at": Vector3(-5.5, 0, -18)}, {"id": "threshold", "at": Vector3(-0.6, 0, -18)}, {"id": "east", "at": Vector3(5.5, 0, -18)}]:
			level._reset_position(spot.at)
			await _ticks(55)
			var record: Dictionary = _visibility_record(mode, angle, spot.id)
			visibility.append(record)
			if mode == 1:
				_check(record.points.all(func(point: Dictionary) -> bool: return bool(point.clear) or not bool(point.required)), "revealed %s angle %d clears architecture over hero and nearby enemy bodies and warning floors" % [spot.id, angle])
			_check(_ghost_contract(mode), "mode %d %s angle %d barrier cues retain full collision height and thickness" % [mode, spot.id, angle])
			await _shot("mode-%d-%s-angle-%d" % [mode, spot.id, angle], mode, angle)
	_check(_geometry_signature() == signature, "mode %d four-angle visual comparison preserves every geometry collider" % mode)
	var actor_after: Array = _actor_state()
	_check(actor_after == actor_state, "mode %d camera and reveal never change frozen enemy HP or spawn" % mode)
	_check(level.encounters == wave_state, "mode %d camera and reveal never change encounter waves" % mode)
	if actor_after != actor_state or level.encounters != wave_state:
		records.append({"case": "state-difference", "mode": mode, "actors_before": actor_state, "actors_after": actor_after, "encounters_before": wave_state, "encounters_after": level.encounters.duplicate(true)})
	level.set_compare_mode(1 - mode)
	await _ticks(60)
	_check(_geometry_signature() == signature and _actor_state() == actor_state, "mode %d switching A/B changes neither collision nor enemy state" % mode)
	level.set_compare_mode(mode)
	await _ticks(60)
	await _angle(0)
	await _wall_motion(mode)
	await _open_membrane(mode)
	if not level.membrane.intact:
		await _cross(Vector3(-6, 0, -18), Vector3(6.5, 0, -18), "mode-%d-forward" % mode)
		await _cross(Vector3(6.5, 0, -18), Vector3(-6, 0, -18), "mode-%d-return" % mode)
		level._reset_position(Vector3(0, 0, -18))
		await _ticks(55)
		await _shot("mode-%d-open-passage" % mode, mode, 0)
	await _pause(mode)


func _wall_motion(mode: int) -> void:
	level._reset_position(Vector3(-5.5, 0, -21))
	await _ticks(40)
	var probe: Dictionary = _world_ray(Vector3(-5.5, 0.7, -21), Vector3(7, 0.7, -21))
	_check(not probe.is_empty() and absf(float(probe.position.x) + 3.0) < 1.0, "mode %d independent world ray finds the full furnace east wall" % mode)
	_walk_towards(Vector3(2, 0, -21))
	await _ticks(75)
	_release()
	_check(level.player.global_position.x < -3.2, "mode %d ordinary walking cannot cross the visually represented solid wall" % mode)
	level._reset_position(Vector3(-4.8, 0, -21))
	await _ticks(10)
	Input.action_press(&"jump")
	await _ticks(48)
	var charged: float = level.player.get_jump_charge_ratio()
	Input.action_release(&"jump")
	_walk_towards(Vector3(2, 0, -21))
	var highest := 0.0
	var furthest := -100.0
	for tick: int in 95:
		await _ticks(1)
		highest = maxf(highest, level.player.global_position.y)
		furthest = maxf(furthest, level.player.global_position.x)
		if tick == 17: await _shot("mode-%d-wall-jump" % mode, mode, 0)
	_release()
	_check(charged > 0.99 and highest > 1.0 and furthest < -3.2 and level.player.is_on_floor(), "mode %d a fully charged real jump rises and lands without crossing the high wall" % mode)
	records.append({"case": "wall-jump", "mode": mode, "peak_y": highest, "furthest_x": furthest, "charge": charged})


func _open_membrane(mode: int) -> void:
	level._reset_position(Vector3(-2.0, 0, -18))
	await _ticks(35)
	var initial_events: int = projectile_events.size()
	for shot: int in 2:
		await _acid_at(Vector3(0.5, level.player._combat_origin_height(), -18))
		for tick: int in 75:
			await _ticks(1)
			if int(level.membrane.strength) < 2 - shot: break
		_check(level.membrane.strength == 1 - shot, "mode %d acid projectile %d actually weakens the membrane" % [mode, shot + 1])
	_check(not level.membrane.intact and level.membrane.collision_layer == 0 and not level.membrane.visible, "mode %d two real rank-one acid hits open the passage visually and physically" % mode)
	var hits := 0
	for event: Dictionary in projectile_events.slice(initial_events):
		if event.kind == "resolved" and event.team == "player" and bool(event.damaged) and absf(float(event.position[0]) - 0.5) < 0.4: hits += 1
	_check(hits == 2, "mode %d membrane opening is evidenced by two projectile collisions, without directly invoking its property handler" % mode)


func _combat_mode(mode: int) -> void:
	await _angle(0)
	await _open_membrane(mode)
	# Same four actors and authored collision; only the selected projectile target
	# is relocated for the blocked/unblocked control experiment.
	var enemies: Array = level.comparison_enemies()
	var target: Spitter = enemies[2] as Spitter
	level._reset_position(Vector3(-5.5, 0, -21))
	target.global_position = Vector3(7, 0.04, -21)
	await _ticks(45)
	var hp_before: int = target.health
	var event_start: int = projectile_events.size()
	await _acid_at(Vector3(7, level.player._combat_origin_height(), -21))
	_check(level.barrier_feedback.blocked, "mode %d actual aiming displays the blocked shot cue at the wall" % mode)
	await _ticks(80)
	var wall_hit := false
	for event: Dictionary in projectile_events.slice(event_start):
		if event.kind == "resolved" and event.team == "player" and not bool(event.damaged) and absf(float(event.position[0]) + 3.0) < 0.9: wall_hit = true
	_check(wall_hit and target.health == hp_before, "mode %d actual acid projectile hits the full wall and cannot damage the creature behind it" % mode)
	await _shot("mode-%d-shot-blocked" % mode, mode, 0)
	target.global_position = Vector3(-5.5, 0.04, -24.5)
	await _ticks(35)
	var control_ray: Dictionary = _world_ray(level.player.global_position + Vector3.UP * 0.65, target.global_position + Vector3.UP * 0.65)
	_check(control_ray.is_empty(), "mode %d control target has an independently clear world shot line" % mode)
	await _acid_at(target.global_position + Vector3.UP * 0.45)
	_check(not level.barrier_feedback.blocked, "mode %d a clear line to the creature removes the blocked shot cue" % mode)
	for tick: int in 85:
		await _ticks(1)
		if target.health < hp_before: break
	_check(target.health == hp_before - 18, "mode %d the same actual rank-one acid deals 18 damage on the clear side of the wall" % mode)
	await _shot("mode-%d-shot-clear" % mode, mode, 0)
	# Aim beyond a wall, but put a live creature before that wall. The cue must
	# report the first real projectile contact rather than ignore enemy bodies.
	target.global_position = Vector3(-4.3, 0.04, -21)
	await _ticks(25)
	event_start = projectile_events.size()
	await _acid_at(Vector3(7, level.player._combat_origin_height(), -21))
	_check(not level.barrier_feedback.blocked, "mode %d nearer creature before a distant wall suppresses the blocked-shot cue" % mode)
	await _ticks(60)
	var nearer_hit := false
	for event: Dictionary in projectile_events.slice(event_start):
		if event.kind == "resolved" and event.team == "player" and bool(event.damaged) and float(event.position[0]) < -3.5: nearer_hit = true
	_check(nearer_hit and (not is_instance_valid(target) or not target.is_alive()), "mode %d real acid hits the nearer creature before the wall" % mode)
	# A capsule can stand close enough that the authored muzzle offset starts
	# inside the solid. Both feedback and the real projectile must still block.
	level._reset_position(Vector3(-3.84, 0, -21))
	await _ticks(35)
	event_start = projectile_events.size()
	await _acid_at(Vector3(7, level.player._combat_origin_height(), -21))
	_check(level.barrier_feedback.blocked, "mode %d shot cue detects a muzzle starting inside the wall volume" % mode)
	await _ticks(50)
	var inside_hit := false
	for event: Dictionary in projectile_events.slice(event_start):
		if event.kind == "resolved" and event.team == "player" and not bool(event.damaged) and absf(float(event.position[0]) + 3.0) < 0.6: inside_hit = true
	_check(inside_hit, "mode %d real projectile starting inside the wall resolves there without escaping through it" % mode)
	await _shot("mode-%d-muzzle-blocked" % mode, mode, 0)
	# A fresh reload prevents the projectile control from biasing the live A/B.
	if not await _fresh_scene(mode): return
	await _open_membrane(mode)
	level._reset_position(Vector3(-5.5, 0, -18))
	await _ticks(35)
	enemies = level.comparison_enemies()
	var windups: Dictionary = {}
	var releases: Dictionary = {}
	for enemy: Spitter in enemies:
		var id: String = String(enemy.get_path())
		enemy.phase_changed.connect(func(_actor: Spitter, phase: StringName) -> void:
			if phase == &"windup": windups[id] = int(windups.get(id, 0)) + 1)
		enemy.projectile_requested.connect(func(_actor: Spitter, _origin: Vector3, _direction: Vector3, _damage: int, _speed: float, _range: float, _key: String) -> void:
			releases[id] = int(releases.get(id, 0)) + 1)
	level.set_test_ai_paused(false)
	await _begin_sample()
	var pause_done := false
	var frame_warnings := 0
	for tick: int in 660:
		# Identical physical intent across modes, short west/east patrol; no invulnerability.
		var destination := Vector3(-5.2 if tick < 170 or tick >= 500 else 5.8, 0, -18)
		if level.player.global_position.distance_to(destination) > 0.35: _walk_towards(destination)
		else: _release()
		await _ticks(1)
		for enemy: Spitter in enemies:
			if enemy.get_attack_phase() == &"windup" and enemy.ground_warning.visible: frame_warnings += 1
		if not pause_done and not get_nodes_in_group(&"enemy_projectiles").is_empty():
			sampling = false
			await _pause(mode)
			await _shot("mode-%d-live-warning" % mode, mode, 0)
			last_draw = Time.get_ticks_usec()
			sampling = true
			pause_done = true
		if not level.player.is_alive(): break
	_release()
	_end_sample("mode-%d-multiple-enemy-combat" % mode)
	_check(windups.size() >= 2 and releases.size() >= 2 and frame_warnings > 10, "mode %d at least two real creatures prepare visible warnings and release real projectiles" % mode)
	_check(pause_done, "mode %d live encounter includes projectile pause verification" % mode)
	records.append({"case": "live-combat", "mode": mode, "windups_by_enemy": windups, "releases_by_enemy": releases, "warning_frames": frame_warnings, "hero_hp_after": level.player.health, "hero_end": _vec(level.player.global_position)})
	await _shot("mode-%d-live-end" % mode, mode, 0)


func _acid_at(point: Vector3) -> void:
	for tick: int in 240:
		if level.player.cooldown_remaining(&"acid_spit") <= 0.0 and level.player._action == &"": break
		await _ticks(1)
	var pointer: Vector2 = _view().camera.unproject_position(point)
	var motion := InputEventMouseMotion.new()
	motion.position = pointer
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	level.player.controls.pointer = pointer
	await _ticks(2)
	Input.action_press(&"ability_slot_1")
	await _ticks(2)
	Input.action_release(&"ability_slot_1")


func _pause(mode: int) -> void:
	_release()
	var snapshot: Array = []
	for enemy: Spitter in level.comparison_enemies(): snapshot.append([enemy.global_position, enemy._phase_left, enemy.health])
	var flight: Dictionary = {}
	for projectile: Node in get_nodes_in_group(&"projectiles"):
		if projectile is SpitProjectile: flight[projectile.get_instance_id()] = [projectile.global_position, projectile._travelled]
	var hero: Array = [level.player.global_position, level.player.health, level.player.cooldown_remaining(&"acid_spit")]
	var reveal_before: Dictionary = _amounts()
	var reveal_time: float = level.reveal.elapsed_update_time
	paused = true
	await _ticks(20)
	var after: Array = []
	for enemy: Spitter in level.comparison_enemies(): after.append([enemy.global_position, enemy._phase_left, enemy.health])
	var flight_same := true
	for id: int in flight:
		var node: Node = instance_from_id(id)
		flight_same = flight_same and is_instance_valid(node) and node.global_position.is_equal_approx(flight[id][0]) and is_equal_approx(node._travelled, flight[id][1])
	_check(snapshot == after and flight_same and hero == [level.player.global_position, level.player.health, level.player.cooldown_remaining(&"acid_spit")], "mode %d pause freezes real actors, active shots, health and cooldown" % mode)
	_check(_amounts() == reveal_before and is_equal_approx(reveal_time, float(level.reveal.elapsed_update_time)), "mode %d pause freezes the actual architectural transition" % mode)
	_check(not level._mode_row.visible, "mode %d pause hides A/B controls so input cannot bypass the pause" % mode)
	paused = false


func _cross(start: Vector3, destination: Vector3, label: String) -> void:
	level._reset_position(start)
	await _ticks(30)
	last_amounts = _amounts()
	last_update_time = float(level.reveal.elapsed_update_time)
	await _begin_sample()
	var arrived := false
	for tick: int in 240:
		var offset: Vector3 = destination - level.player.global_position
		offset.y = 0.0
		if offset.length() < 0.3: arrived = true; break
		_walk_towards(destination)
		await _ticks(1)
		_trace_fade(label)
	_release()
	_end_sample(label)
	_check(arrived and level.player.is_on_floor(), label + " normal controller physically crosses the opened passage")


func _ghost_contract(mode: int) -> bool:
	var valid := true
	for section: Dictionary in level.reveal.pilot_sections:
		var shape: CollisionShape3D = section.collision_shape
		var ghost: MeshInstance3D = section.ghost
		if not is_instance_valid(ghost) or not shape.shape is BoxShape3D: return false
		var parts: Array = section.get("ghost_parts", [])
		if parts.is_empty(): return false
		var bounds := AABB()
		var first := true
		for part: MeshInstance3D in parts:
			var source: MeshInstance3D = part.get_meta(&"source_mesh", null) as MeshInstance3D
			if not is_instance_valid(source): return false
			valid = valid and part.mesh == source.mesh and part.global_transform.is_equal_approx(source.global_transform)
			valid = valid and part.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			valid = valid and part.find_children("*", "CollisionObject3D", true, false).is_empty()
			var world_bounds: AABB = part.global_transform * part.get_aabb()
			bounds = world_bounds if first else bounds.merge(world_bounds)
			first = false
		valid = valid and bounds.size.y >= (shape.shape as BoxShape3D).size.y - 0.05
		if mode == 0: valid = valid and not ghost.visible and float(section.reveal_amount) < 0.001
		elif float(section.reveal_amount) > 0.98: valid = valid and ghost.visible and bounds.size.y > 3.0
	return valid


func _amounts() -> Dictionary:
	var result: Dictionary = {}
	for section: Dictionary in level.reveal.pilot_sections:
		result[section.id] = float(section.reveal_amount)
	return result


func _trace_fade(label: String) -> void:
	var now: float = float(level.reveal.elapsed_update_time)
	var current: Dictionary = _amounts()
	var allowed: float = maxf(0.0, now - last_update_time) / 0.28 + 0.00001
	for key: String in current:
		if last_amounts.has(key): fade_continuous = fade_continuous and absf(current[key] - last_amounts[key]) <= allowed
	fade_trace.append({"route": label, "update_time": now, "position": _vec(level.player.global_position), "amounts": current})
	last_amounts = current
	last_update_time = now


func _visibility_record(mode: int, angle: int, spot: String) -> Dictionary:
	var targets: Array[Dictionary] = [{"id": "hero", "body": level.player.global_position + Vector3.UP * 0.65, "floor": level.player.global_position + Vector3.UP * 0.08}]
	for index: int in level.comparison_enemies().size():
		var enemy: Spitter = level.comparison_enemies()[index]
		targets.append({"id": "enemy-%d" % index, "body": enemy.global_position + Vector3.UP * 0.65, "floor": enemy.global_position + Vector3.UP * 0.08})
	var points: Array[Dictionary] = []
	for target: Dictionary in targets:
		for kind: String in ["body", "floor"]:
			var ray: Dictionary = _architecture_ray(target[kind])
			var required: bool = String(target.id) == "hero" or Vector3(target.body).distance_to(level.player.global_position) <= Spitter.ENGAGE_DISTANCE + 1.0
			points.append({"id": target.id, "kind": kind, "clear": ray.clear, "required": required, "occluders": ray.occluders, "onscreen": Rect2(Vector2.ZERO, Vector2(root.size)).has_point(_view().camera.unproject_position(target[kind]))})
	return {"mode": mode, "angle": angle, "spot": spot, "points": points}


func _architecture_ray(target: Vector3) -> Dictionary:
	var camera: Camera3D = _view().camera
	var origin: Vector3 = camera.project_ray_origin(camera.unproject_position(target))
	var ignored: Array[RID] = [level.player.get_rid()]
	for actor: Spitter in level.comparison_enemies(): ignored.append(actor.get_rid())
	var occluders: Array[Dictionary] = []
	for step: int in 40:
		var query := PhysicsRayQueryParameters3D.create(origin, target + camera.global_basis.z * 0.008, 1, ignored)
		var hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty(): break
		var body: CollisionObject3D = hit.collider as CollisionObject3D
		var structural := false
		for section: Dictionary in level.geometry.cutaway.structural_sections:
			if section.get("body") == body or section.get("additional_bodies", []).has(body): structural = true; break
		if structural:
			occluders.append({"body": String(body.get_path()), "point": _vec(hit.position), "revealed": level.reveal.is_point_cut(body, hit.position)})
		ignored.append(body.get_rid())
	return {"clear": occluders.all(func(item: Dictionary) -> bool: return bool(item.revealed)), "occluders": occluders}


func _geometry_signature() -> Dictionary:
	var result: Dictionary = {}
	for body: StaticBody3D in level.geometry.find_children("*", "StaticBody3D", true, false):
		var shapes: Array = []
		for child: Node in body.get_children():
			if child is CollisionShape3D: shapes.append([child.disabled, child.shape.get_rid(), child.transform])
		result[String(body.get_path())] = [body.collision_layer, body.collision_mask, body.global_transform, shapes]
	return result


func _actor_state() -> Array:
	var result: Array = []
	for actor: Spitter in level.comparison_enemies(): result.append([actor.get_instance_id(), actor.global_position, actor.health, actor._phase, actor._phase_left])
	return result


func _world_ray(from: Vector3, to: Vector3) -> Dictionary:
	return level.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1, [level.player.get_rid()]))


func _angle(index: int) -> void:
	var target: float = index * PI * 0.5
	for attempt: int in 5:
		if absf(wrapf(_view().camera_yaw - target, -PI, PI)) < 0.001: return
		_view().request_quarter_turn(1)
		await _ticks(25)
	_check(false, "camera reaches requested actual quarter angle")


func _view() -> SlimeIsometricPresentation:
	return level.player.presentation as SlimeIsometricPresentation


func _walk_towards(target: Vector3) -> void:
	var direction: Vector3 = target - level.player.global_position
	direction.y = 0.0
	var axes: Vector2 = level.player.controls.world_direction_to_screen_axes(direction.normalized())
	Input.action_press(&"move_right", maxf(axes.x, 0.0))
	Input.action_press(&"move_left", maxf(-axes.x, 0.0))
	Input.action_press(&"move_back", maxf(axes.y, 0.0))
	Input.action_press(&"move_forward", maxf(-axes.y, 0.0))


func _release() -> void:
	for action: StringName in MOVES:
		if InputMap.has_action(action): Input.action_release(action)
	if InputMap.has_action(&"jump"): Input.action_release(&"jump")
	if InputMap.has_action(&"ability_slot_1"): Input.action_release(&"ability_slot_1")


func _watch_projectile(node: Node) -> void:
	if not node is SpitProjectile: return
	var projectile := node as SpitProjectile
	var team: String = String(projectile.team)
	var key: String = projectile.cast_key
	projectile_events.append({"kind": "emitted", "team": team, "cast": key, "mode": int(level.compare_mode) if is_instance_valid(level) else -1})
	projectile.resolved.connect(func(at: Vector3, damaged: bool) -> void:
		projectile_events.append({"kind": "resolved", "team": team, "cast": key, "position": _vec(at), "damaged": damaged, "mode": int(level.compare_mode) if is_instance_valid(level) else -1}))


func _begin_sample() -> void:
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	frames.clear()
	last_draw = Time.get_ticks_usec()
	sampling = true


func _sample_frame() -> void:
	var now: int = Time.get_ticks_usec()
	if sampling: frames.append(float(now - last_draw) / 1000.0)
	last_draw = now


func _end_sample(label: String) -> void:
	sampling = false
	var sorted: Array[float] = frames.duplicate()
	sorted.sort()
	var record: Dictionary = {"case": label, "frames": sorted.size()}
	if not sorted.is_empty():
		record.merge({"median_ms": _percentile(sorted, 0.5), "p95_ms": _percentile(sorted, 0.95), "p99_ms": _percentile(sorted, 0.99), "max_ms": sorted[-1], "over_16_67_ms": sorted.filter(func(value: float) -> bool: return value > 16.67).size()})
	records.append(record)
	FileAccess.open(out + label + ".frames.json", FileAccess.WRITE).store_string(JSON.stringify(frames))


func _percentile(values: Array[float], quantile: float) -> float:
	return values[clampi(int(ceil(values.size() * quantile)) - 1, 0, values.size() - 1)]


func _shot(label: String, mode: int, angle: int) -> void:
	if not capture: return
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png(out + "images/" + label + ".png")
	shots.append({"file": "images/" + label + ".png", "mode": mode, "angle": angle, "saved": error == OK})
	_check(error == OK, "native capture " + label)


func _ticks(count: int) -> void:
	for tick: int in count:
		await physics_frame
		await process_frame


func _vec(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _check(ok: bool, label: String) -> void:
	checks.append({"pass": ok, "check": label})
	print("PASS " if ok else "FAIL ", label)


func _finish() -> void:
	if finished: return
	finished = true
	_release()
	paused = false
	var failures: int = checks.filter(func(item: Dictionary) -> bool: return not item.pass).size()
	var report: Dictionary = {"status": "PASS" if failures == 0 else "FAIL", "part": part, "checks": checks, "screenshots": shots, "visibility": visibility, "records": records, "projectiles": projectile_events, "engine": Engine.get_version_info(), "renderer": RenderingServer.get_current_rendering_method(), "device": RenderingServer.get_video_adapter_name(), "scope": "Real authored dungeon A/B, seeded original actors/controller/projectiles. Scripted native input, not physical mouse/user perception. World rays quantify structural occlusion only; they do not prove recognition of translucent boundaries. Frame intervals are native inter-draw wall times, not GPU measurements. Geometry probe freezes AI; combat probe enables AI without invulnerability. Relocation only selects initial probe positions."}
	FileAccess.open(out + "results.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	FileAccess.open(out + "fade-trace.json", FileAccess.WRITE).store_string(JSON.stringify(fade_trace))
	print("VISIBILITY_COMBAT_RESULT part=", part, " checks=", checks.size(), " failures=", failures)
	quit(1 if failures > 0 else 0)
