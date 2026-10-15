extends SceneTree

# This is a native render/physics probe for the separate visibility workshop.
# It does not change the dungeon, save files or player input implementation.
const SCENE := "res://scenes/visibility_lab/visibility_lab.tscn"
const MOVES: Array[StringName] = [&"move_right", &"move_left", &"move_back", &"move_forward"]
const FIXTURES: Array[String] = ["corridor", "corner", "junction", "column", "arch", "bridge"]
var out := "res://output/visibility_lab_2026_10_15/native/"
var capture := false
var combat_only := false
var level: Node3D
var checks: Array[Dictionary] = []
var records: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var frames: Array[float] = []
var last_draw := 0
var sampling := false
var finished := false
var aim_verified := false
var fade_trace: Array[Dictionary] = []
var last_fade_values: Dictionary = {}
var last_fade_sample := 0
var last_fade_update_time := 0.0
var continuous_routes := true


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--capture": capture = true
		if argument == "--combat-only": combat_only = true
		if argument.begins_with("--output=res://output/"):
			out = argument.trim_prefix("--output=").trim_suffix("/") + "/"
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out + "images"))
	SlimeGameSettings.current().load_settings(out + "settings.cfg")
	SlimeGameSettings.current().camera_shake = 0.0
	seed(4873)
	create_timer(45.0 if combat_only else 240.0, true).timeout.connect(func() -> void:
		_check(false, "bounded runtime watchdog")
		_finish())
	if DisplayServer.get_name() == "headless":
		capture = false
	else:
		root.size = Vector2i(1280, 720)
		DisplayServer.window_set_size(root.size)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		RenderingServer.frame_post_draw.connect(_sample_frame)
	var error: Error = change_scene_to_file(SCENE)
	_check(error == OK, "workshop scene loads")
	if error != OK: _finish(); return
	await _ticks(30)
	level = current_scene as Node3D
	_check(is_instance_valid(level) and level.get("player") is SlimeController, "real player and workshop initialize")
	if not is_instance_valid(level) or not level.get("player") is SlimeController:
		_finish(); return
	_check(_view().quarter_turns_enabled, "workshop uses accepted four-angle camera")
	if combat_only:
		await _combat_checks()
		_finish()
		return
	for fixture: int in FIXTURES.size():
		await _fixture_checks(fixture)
	await _physical_wall_check()
	await _pause_checks()
	await _bridge_checks()
	await _switch_checks()
	_check(aim_verified, "at least one occluded real actor is selected through a revealed wall")
	_check(continuous_routes, "physical routes never produce an instantaneous section visibility jump")
	_finish()


func _fixture_checks(index: int) -> void:
	level.select_fixture(index, 0)
	level.set_mode(1)
	_freeze_enemy()
	await _ticks(10)
	var signature: Dictionary = _geometry_signature()
	var route: Array = level.geometry.route.duplicate()
	var probe: Vector3 = level.geometry.probes[0] if not level.geometry.probes.is_empty() else level.geometry.spawn
	level.reset_player(probe)
	await _set_angle(0)
	await _ticks(30)
	var any_reveal := false
	var material_sync := true
	var settled := true
	var bases: Array[Basis] = []
	for angle: int in 4:
		if angle != 0:
			await _quarter_turn("%s-%d" % [FIXTURES[index], angle], index == 1)
		bases.append(_view().camera.global_basis)
		await _ticks(60)
		any_reveal = any_reveal or _revealed_count() > 0
		material_sync = material_sync and _materials_match()
		settled = settled and await _stable_sections(8)
		if index == 4:
			_enemy_visibility_checks(angle)
		await _shot("%s-reveal-angle-%d" % [FIXTURES[index], angle], index, 0, 1, angle)
		if not aim_verified and _revealed_count() > 0:
			await _try_aim_probe()
		if angle == 0:
			await _walk_route(route, "%s-angle-%d-forward" % [FIXTURES[index], angle])
			var backward: Array = route.duplicate()
			backward.reverse()
			await _walk_route(backward, "%s-angle-%d-return" % [FIXTURES[index], angle], false)
			level.reset_player(probe)
			await _ticks(30)
	_check(_distinct_bases(bases), FIXTURES[index] + " shows four different actual camera bases")
	_check(any_reveal, FIXTURES[index] + " actually reveals an authored obstructing section")
	_check(material_sync, FIXTURES[index] + " section walls, tops and decoration share the same smooth material amount")
	_check(settled, FIXTURES[index] + " settled section targets do not oscillate while stationary")
	_check(_geometry_signature() == signature, FIXTURES[index] + " visual reveal preserves every collider and shape")
	await _set_angle(0)
	level.set_mode(0)
	await _ticks(35)
	_check(_revealed_count() == 0 and _materials_match(), FIXTURES[index] + " full-wall mode restores all sections")
	await _shot(FIXTURES[index] + "-full", index, 0, 0, 0)
	var low_pitch: float = asin(_view().camera.global_basis.z.y)
	level.set_mode(2)
	await _ticks(35)
	var high_pitch: float = asin(_view().camera.global_basis.z.y)
	_check(high_pitch > low_pitch + deg_to_rad(15.0) and _revealed_count() == 0, FIXTURES[index] + " high camera raises pitch while keeping full walls")
	await _shot(FIXTURES[index] + "-high", index, 0, 2, 0)
	level.select_fixture(index, 1)
	level.set_mode(1)
	_freeze_enemy()
	level.reset_player(level.geometry.probes[0] if not level.geometry.probes.is_empty() else level.geometry.spawn)
	await _set_angle(0)
	await _ticks(40)
	_check(_materials_match(), FIXTURES[index] + " timber theme uses the same section reveal contract")
	await _shot(FIXTURES[index] + "-timber", index, 1, 1, 0)


func _quarter_turn(label: String, take_middle: bool = false) -> void:
	var view: SlimeIsometricPresentation = _view()
	var start: float = view.camera_yaw
	var accepted: bool = view.request_quarter_turn(1)
	var previous := 0.0
	var monotonic := true
	var intermediate := 0
	for tick: int in 26:
		await _ticks(1)
		var amount: float = wrapf(view.camera_yaw - start, 0.0, TAU)
		monotonic = monotonic and amount >= previous - 0.0001 and amount <= PI * 0.5 + 0.0001
		if amount > 0.001 and amount < PI * 0.5 - 0.001: intermediate += 1
		previous = amount
		if take_middle and tick == 7: await _shot(label + "-turning", 1, 0, 1, -1)
	_check(accepted and monotonic and intermediate >= 4 and not view.is_camera_turning(), label + " camera turns smoothly without overshoot")


func _set_angle(angle: int) -> void:
	var target: float = float(angle) * PI * 0.5
	for attempt: int in 4:
		if absf(wrapf(_view().camera_yaw - target, -PI, PI)) < 0.001: return
		_view().request_quarter_turn(1)
		await _ticks(25)
	_check(false, "camera reaches requested quarter angle")


func _walk_route(route: Array, label: String, relocate_start: bool = true) -> void:
	if route.size() < 2:
		_check(false, label + " has a physical route")
		return
	if relocate_start: level.reset_player(route[0])
	await _ticks(20)
	var geometry_id: int = level.geometry.get_instance_id()
	var reached := true
	var upper_support_seen := false
	var upper_floor_visible := true
	var largest_upper_amount := 0.0
	last_fade_values = _section_amounts()
	last_fade_sample = Time.get_ticks_usec()
	last_fade_update_time = float(level.reveal.elapsed_update_time)
	await _begin_sample()
	for waypoint: Vector3 in route.slice(1):
		var arrived := false
		for tick: int in 360:
			var offset: Vector3 = waypoint - level.player.global_position
			var height_difference: float = absf(offset.y)
			offset.y = 0.0
			if offset.length() < 0.24 and height_difference < 0.3 and level.player.is_on_floor():
				arrived = true
				break
			_walk_towards(waypoint)
			await _ticks(1)
			_trace_fade(label)
			if level.player.is_on_floor() and float(level.reveal.support_y) > 3.08:
				upper_support_seen = true
				for section: Dictionary in level.reveal.sections.values():
					if section.get("role", "") == "overhead":
						var amount: float = float(section.amount)
						largest_upper_amount = maxf(largest_upper_amount, amount)
						upper_floor_visible = upper_floor_visible and amount < 0.02
		if not arrived:
			reached = false
			print("VISIBILITY_ROUTE_BLOCKED ", label, " position=", level.player.global_position, " target=", waypoint)
			break
	_release()
	_end_sample(label, reached)
	_check(reached and geometry_id == level.geometry.get_instance_id(), label + " walks the complete route with real player movement")
	if label.begins_with("bridge-upper-"):
		_check(upper_support_seen and upper_floor_visible, label + " deck is already visible on first upper landing and every grounded upper step")
		if not upper_floor_visible:
			print("VISIBILITY_UPPER_LANDING_AMOUNT ", label, " maximum=", largest_upper_amount)


func _pause_checks() -> void:
	level.select_fixture(1, 0)
	level.set_mode(0)
	_freeze_enemy()
	level.reset_player(level.geometry.probes[0])
	await _set_angle(0)
	await _ticks(25)
	level.set_mode(1)
	_view().request_quarter_turn(1)
	await _ticks(5)
	var before: Dictionary = _section_amounts()
	var yaw: float = _view().camera_yaw
	paused = true
	await _ticks(12)
	_check(before == _section_amounts() and is_equal_approx(yaw, _view().camera_yaw), "pause freezes reveal and an in-progress camera turn")
	paused = false
	await _ticks(45)
	_check(not _view().is_camera_turning() and _materials_match(), "resume completes the same turn and synchronized reveal")


func _physical_wall_check() -> void:
	level.select_fixture(0, 0)
	level.set_mode(1)
	_freeze_enemy()
	level.reset_player(Vector3.ZERO)
	await _set_angle(0)
	await _ticks(45)
	var chosen: Dictionary = {}
	for section: Dictionary in level.geometry.sections:
		if section.role == "wall" and float(level.reveal.sections[section.id].amount) > 0.98:
			chosen = section
			break
	_check(not chosen.is_empty(), "physical wall probe starts with a visually revealed corridor wall")
	if chosen.is_empty(): return
	var center: Vector3 = chosen.bounds.get_center()
	var target := Vector3(center.x * 2.0, 0.0, 0.0)
	var contact := false
	for tick: int in 40:
		_walk_towards(target)
		await _ticks(1)
		for collision: int in level.player.get_slide_collision_count():
			contact = contact or level.player.get_slide_collision(collision).get_collider() == chosen.body
	_release()
	_check(contact and absf(level.player.global_position.x) < absf(center.x), "normal movement stops at the revealed wall instead of crossing its collider")
	var origin := Vector3(0.0, 0.85, 0.0)
	var destination := Vector3(center.x * 2.0, 0.85, 0.0)
	var query := PhysicsRayQueryParameters3D.create(origin, destination, 1)
	var hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(query)
	_check(not hit.is_empty() and hit.collider == chosen.body, "ordinary combat world ray still hits the revealed wall")


func _bridge_checks() -> void:
	level.select_fixture(5, 0)
	level.set_mode(1)
	_freeze_enemy()
	level.reset_player(Vector3(0.0, 0.0, 0.0))
	await _set_angle(0)
	await _ticks(45)
	var overhead_revealed := false
	for section: Dictionary in level.geometry.sections:
		if section.get("role", "") == "overhead" and level.reveal.sections.has(section.id):
			overhead_revealed = overhead_revealed or float(level.reveal.sections[section.id].amount) > 0.95
	_check(overhead_revealed, "bridge reveals the overhead deck from the lower passage")
	var support: float = level.reveal.support_y
	var start_y: float = level.player.global_position.y
	var peak := 0.0
	var same_support := true
	Input.action_press(&"jump")
	await _ticks(24)
	Input.action_release(&"jump")
	for tick: int in 75:
		await _ticks(1)
		peak = maxf(peak, level.player.global_position.y - start_y)
		same_support = same_support and absf(float(level.reveal.support_y) - support) < 0.05
	_check(peak > 0.5 and level.player.is_on_floor(), "real charged jump takes off and lands below bridge")
	_check(same_support, "jumping does not select the upper floor as the occupied support")
	await _shot("bridge-lower", 5, 0, 1, 0)
	level.reset_player(level.geometry.upper_spawn)
	await _ticks(50)
	var floor_kept := true
	for section: Dictionary in level.geometry.sections:
		if section.get("role", "") == "overhead" and level.reveal.sections.has(section.id):
			floor_kept = floor_kept and float(level.reveal.sections[section.id].amount) < 0.01
	_check(floor_kept and level.player.is_on_floor() and level.player.global_position.y > 3.0, "occupied bridge deck stays visible and supports the real player")
	await _shot("bridge-upper", 5, 0, 1, 0)
	if level.geometry.get("upper_route") is Array:
		await _walk_route(level.geometry.upper_route, "bridge-upper-forward")
		_check(level.player.is_on_floor() and level.player.global_position.y > 3.0 and float(level.reveal.support_y) > 3.0, "walking the real ramp reaches the supported upper deck")
		var back: Array = level.geometry.upper_route.duplicate()
		back.reverse()
		await _walk_route(back, "bridge-upper-return", false)
		_check(level.player.is_on_floor() and absf(level.player.global_position.y) < 0.2 and absf(float(level.reveal.support_y)) < 0.2, "returning down the real ramp reaches lower ground without relocation")
	level.reset_player(Vector3(6.5, 1.6, 3.0))
	await _ticks(45)
	_check(level.player.is_on_floor() and absf(float(level.reveal.support_y) - 1.6) < 0.2 and level.reveal.protected_points.size() > 2, "mid-ramp support protects surrounding walkable space beyond the hero center")


func _combat_checks() -> void:
	# This separate --combat-only run uses the actual workshop actors, player input,
	# camera aim, runtime bindings and projectile collisions. No direct HP mutation.
	level.select_fixture(0, 0)
	level.set_mode(1)
	level.set_combat(false)
	level.reset_player(Vector3(0.0, 0.0, 2.0))
	level.enemy.global_position = Vector3(0.0, 0.04, 0.0)
	await _set_angle(0)
	await _ticks(45)
	var hp_before: int = level.enemy.health
	var expected: Vector3 = level.enemy.global_position + Vector3.UP * 0.45
	var pointer: Vector2 = _view().camera.unproject_position(expected)
	var motion := InputEventMouseMotion.new()
	motion.position = pointer
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	level.player.controls.pointer = pointer
	await _ticks(2)
	_check(level.player.controls.get_aim_point().distance_to(expected) < 0.01, "real workshop camera aim selects the combat target")
	Input.action_press(&"ability_slot_1")
	await _ticks(2)
	Input.action_release(&"ability_slot_1")
	var player_projectile_seen := false
	for tick: int in 90:
		await _ticks(1)
		for node: Node in get_nodes_in_group(&"projectiles"):
			if node is SpitProjectile and node.team == &"player": player_projectile_seen = true
		if level.enemy.health < hp_before: break
	_check(player_projectile_seen and level.enemy.health == hp_before - 12, "slot input emits a real player projectile and deals the authored 12 damage")
	_check(level.enemy.get_sticky_time_left() > 0.0, "actual projectile applies its normal slowing effect")
	await _shot("combat-player-hit", 0, 0, 1, 0)
	# Fresh participants clear the player's previous attack and enemy slow state.
	level.select_fixture(0, 0)
	level.set_mode(1)
	level.set_combat(false)
	level.reset_player(Vector3(0.0, 0.0, 3.0))
	level.enemy.global_position = Vector3(0.0, 0.04, -2.0)
	await _ticks(45)
	level.set_combat(true)
	var windup_seen := false
	for tick: int in 60:
		await _ticks(1)
		if level.enemy.get_attack_phase() == &"windup": windup_seen = true; break
	_check(windup_seen and level.enemy.ground_warning.visible, "live enemy AI enters windup and displays its real attack warning")
	if not windup_seen: return
	var phase_left: float = level.enemy._phase_left
	var enemy_position: Vector3 = level.enemy.global_position
	paused = true
	await _ticks(15)
	_check(is_equal_approx(phase_left, level.enemy._phase_left) and enemy_position.is_equal_approx(level.enemy.global_position), "pause freezes actual enemy windup and movement")
	paused = false
	await _shot("combat-enemy-warning", 0, 0, 1, 0)
	var projectile: SpitProjectile
	for tick: int in 100:
		await _ticks(1)
		for node: Node in get_nodes_in_group(&"enemy_projectiles"):
			if node is SpitProjectile: projectile = node as SpitProjectile; break
		if is_instance_valid(projectile): break
	_check(is_instance_valid(projectile) and level.enemy._shot_count > 0, "live enemy completes windup and releases its bound projectile")
	if not is_instance_valid(projectile): return
	var projectile_position: Vector3 = projectile.global_position
	var travelled: float = projectile._travelled
	var hero_hp: int = level.player.health
	paused = true
	await _ticks(15)
	_check(is_instance_valid(projectile) and projectile.global_position.is_equal_approx(projectile_position) and is_equal_approx(projectile._travelled, travelled) and level.player.health == hero_hp, "pause freezes a live enemy projectile before impact")
	paused = false
	for tick: int in 90:
		await _ticks(1)
		if level.player.health < hero_hp: break
	_check(level.player.health == hero_hp - 8, "resumed enemy projectile physically hits the player for its authored 8 damage")
	await _shot("combat-enemy-hit", 0, 0, 1, 0)
	var old_combat: WeakRef = weakref(level.combat)
	level.select_fixture(1, 0)
	level.set_combat(false)
	await _ticks(5)
	_check(old_combat.get_ref() == null and get_nodes_in_group(&"enemy_projectiles").is_empty(), "switching workshop fixture clears previous combat runtime and enemy projectiles")


func _switch_checks() -> void:
	var old_geometry: WeakRef = weakref(level.geometry)
	var old_reveal: WeakRef = weakref(level.reveal)
	level.select_fixture(0, 0)
	level.set_mode(1)
	_freeze_enemy()
	await _ticks(35)
	_check(old_geometry.get_ref() == null and old_reveal.get_ref() == null, "switching fixture frees previous geometry and section controller")
	_check(_materials_match() and level.reveal.sections.size() == level.geometry.sections.size(), "replacement fixture binds only its own current section materials")


func _try_aim_probe() -> void:
	var target := CharacterBody3D.new()
	target.name = "VisibilityAimProbe"
	target.collision_layer = 4
	target.collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.0
	capsule.radius = 0.25
	shape.shape = capsule
	shape.position.y = 0.5
	target.add_child(shape)
	level.add_child(target)
	var candidates: Array = level.geometry.probes.duplicate()
	candidates.append(level.player.global_position)
	for position: Vector3 in candidates:
		target.global_position = position
		await _ticks(2)
		var expected: Vector3 = position + Vector3.UP * 0.45
		var pointer: Vector2 = _view().camera.unproject_position(expected)
		var origin: Vector3 = _view().camera.project_ray_origin(pointer)
		var direction: Vector3 = _view().camera.project_ray_normal(pointer)
		var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 180.0, 5, [level.player.get_rid()])
		var hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or not hit.collider is StaticBody3D or not level.reveal.is_point_cut(hit.collider, hit.position): continue
		level.player.controls.pointer = pointer
		var aim: Vector3 = level.player.controls.get_aim_point()
		if aim.distance_to(expected) < 0.01:
			aim_verified = true
			_check(true, "camera aim passes a visually revealed wall and selects the real actor collider")
			# The same architectural collision remains solid for ordinary world rays.
			_check(hit.collider.collision_layer & 1 != 0, "revealed wall still belongs to the physical world collision layer")
			break
	target.queue_free()
	await _ticks(2)


func _enemy_visibility_checks(angle: int) -> void:
	var target: Vector3 = level.enemy.global_position
	if angle == 0:
		var offset: Vector3 = target - level.player.global_position
		offset.y = 0.0
		_check(offset.length() > 6.0 and offset.length() <= Spitter.ENGAGE_DISTANCE, "arch visibility probe contains a real threat beyond the former six meter cutoff")
	var body_clear: bool = _architecture_ray_clear(target + Vector3.UP * 0.65, "enemy-body-angle-%d" % angle)
	var floor_target := Vector3(target.x, 0.06, target.z)
	var floor_clear: bool = _architecture_ray_clear(floor_target, "enemy-floor-angle-%d" % angle)
	_check(body_clear and floor_clear, "arch angle %d camera rays reveal architecture over both enemy body and warning floor at 6.6 meters" % angle)


func _architecture_ray_clear(target: Vector3, label: String) -> bool:
	var camera: Camera3D = _view().camera
	var pointer: Vector2 = camera.unproject_position(target)
	var origin: Vector3 = camera.project_ray_origin(pointer)
	# Stop just before the selected surface; the floor under the target itself is
	# not an occluder. This uses real physics shapes, not the controller's bounds.
	var endpoint: Vector3 = target + camera.global_basis.z * 0.005
	var ignored: Array[RID] = [level.player.get_rid(), level.enemy.get_rid()]
	var clear := true
	var diagnostic: Array[Dictionary] = []
	for step: int in 32:
		var query := PhysicsRayQueryParameters3D.create(origin, endpoint, 1, ignored)
		var hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			if not clear: print("VISIBILITY_THREAT_RAY ", label, " ", JSON.stringify(diagnostic))
			return clear
		var collider: CollisionObject3D = hit.collider as CollisionObject3D
		if not is_instance_valid(collider):
			print("VISIBILITY_THREAT_RAY_INVALID_COLLIDER ", label)
			return false
		var architectural := false
		for section: Dictionary in level.geometry.sections:
			if section.body == collider:
				architectural = true
				break
		if architectural:
			var cut: bool = level.reveal.is_point_cut(collider, hit.position)
			clear = clear and cut
			diagnostic.append({"collider": String(collider.get_path()), "position": hit.position, "cut": cut})
		ignored.append(collider.get_rid())
	print("VISIBILITY_THREAT_RAY_LIMIT ", label, " ", JSON.stringify(diagnostic))
	return false


func _stable_sections(ticks: int) -> bool:
	var before: Dictionary = _section_amounts()
	await _ticks(ticks)
	return before == _section_amounts()


func _trace_fade(label: String) -> void:
	var now: int = Time.get_ticks_usec()
	var update_time: float = float(level.reveal.elapsed_update_time)
	var elapsed: float = update_time - last_fade_update_time
	var current: Dictionary = _section_amounts()
	# Sample the time actually delivered to the reveal controller. process_frame
	# signals precede node updates, and Godot can distribute elapsed wall time across
	# adjacent updates; wall-clock intervals between test samples are not that delta.
	var allowed: float = maxf(0.0, elapsed) / 0.28 + 0.00001
	for key: Variant in current:
		if last_fade_values.has(key):
			continuous_routes = continuous_routes and absf(float(current[key][0]) - float(last_fade_values[key][0])) <= allowed
	fade_trace.append({"route": label, "usec": now, "wall_delta_usec": now - last_fade_sample, "elapsed_update_time": update_time, "update_delta": elapsed, "position": level.player.global_position, "sections": current})
	last_fade_values = current
	last_fade_sample = now
	last_fade_update_time = update_time


func _materials_match() -> bool:
	for section: Dictionary in level.reveal.sections.values():
		var expected: float = smoothstep(0.0, 1.0, float(section.amount))
		for material: ShaderMaterial in section.materials:
			var actual: Variant = material.get_shader_parameter("cutaway_amount")
			if actual == null or not is_equal_approx(float(actual), expected): return false
	return true


func _section_amounts() -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in level.reveal.sections:
		var section: Dictionary = level.reveal.sections[key]
		result[key] = [float(section.amount), bool(section.get("wanted", false))]
	return result


func _revealed_count() -> int:
	var count := 0
	for section: Dictionary in level.reveal.sections.values():
		if float(section.amount) > 0.01: count += 1
	return count


func _geometry_signature() -> Dictionary:
	var result: Dictionary = {}
	for body: StaticBody3D in level.geometry.find_children("*", "StaticBody3D", true, false):
		var shapes: Array = []
		for child: Node in body.get_children():
			if child is CollisionShape3D:
				shapes.append([child.disabled, child.shape.get_rid(), child.transform])
		result[String(body.get_path())] = [body.collision_layer, body.collision_mask, body.global_transform, shapes]
	return result


func _distinct_bases(bases: Array[Basis]) -> bool:
	if bases.size() != 4: return false
	for first: int in 4:
		for second: int in range(first + 1, 4):
			if bases[first].is_equal_approx(bases[second]): return false
	return true


func _freeze_enemy() -> void:
	level.set_combat(false)
	if is_instance_valid(level.enemy):
		level.enemy.collision_layer = 0
		level.enemy.collision_mask = 0


func _view() -> SlimeIsometricPresentation:
	return level.player.presentation as SlimeIsometricPresentation


func _walk_towards(target: Vector3) -> void:
	var offset: Vector3 = target - level.player.global_position
	offset.y = 0.0
	var axes: Vector2 = level.player.controls.world_direction_to_screen_axes(offset.normalized())
	Input.action_press(&"move_right", maxf(axes.x, 0.0))
	Input.action_press(&"move_left", maxf(-axes.x, 0.0))
	Input.action_press(&"move_back", maxf(axes.y, 0.0))
	Input.action_press(&"move_forward", maxf(-axes.y, 0.0))


func _release() -> void:
	for action: StringName in MOVES: Input.action_release(action)
	Input.action_release(&"jump")


func _begin_sample() -> void:
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	frames.clear()
	last_draw = Time.get_ticks_usec()
	sampling = true


func _sample_frame() -> void:
	var now: int = Time.get_ticks_usec()
	if sampling: frames.append(float(now - last_draw) / 1000.0)
	last_draw = now


func _end_sample(label: String, reached: bool) -> void:
	sampling = false
	var sorted: Array[float] = frames.duplicate()
	sorted.sort()
	var record: Dictionary = {"route": label, "arrived": reached, "frames": sorted.size()}
	if not sorted.is_empty():
		record.merge({"median_ms": _percentile(sorted, 0.5), "p95_ms": _percentile(sorted, 0.95), "p99_ms": _percentile(sorted, 0.99), "max_ms": sorted[-1], "over_16_67_ms": sorted.filter(func(value: float) -> bool: return value > 16.67).size()})
	records.append(record)
	FileAccess.open(out + label + ".frames.json", FileAccess.WRITE).store_string(JSON.stringify(frames))


func _percentile(values: Array[float], amount: float) -> float:
	return values[clampi(int(ceil(values.size() * amount)) - 1, 0, values.size() - 1)]


func _shot(label: String, fixture: int, theme: int, mode: int, angle: int) -> void:
	if not capture: return
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png(out + "images/" + label + ".png")
	shots.append({"file": "images/" + label + ".png", "fixture": fixture, "theme": theme, "mode": mode, "angle": angle, "saved": error == OK})
	_check(error == OK, "native capture " + label)


func _ticks(count: int) -> void:
	for tick: int in count:
		await physics_frame
		await process_frame


func _check(ok: bool, label: String) -> void:
	checks.append({"pass": ok, "check": label})
	print("PASS " if ok else "FAIL ", label)


func _finish() -> void:
	if finished: return
	finished = true
	_release()
	paused = false
	var failed: bool = checks.any(func(item: Dictionary) -> bool: return not item.pass)
	var scope := "Six authored fixtures, two materials, actual four-angle camera, real movement forward/return at angle 0, lower/upper bridge and ramp traversal, jump and pause. Enemies frozen and their collisions disabled for route probes. Inter-draw wall time after warmup, without capture/relocation; not GPU timings, combat-load validation, physical mouse input or user visual acceptance."
	if combat_only:
		scope = "Separate brief combat smoke: real slot input and camera aim, player projectile damage/slow, live spitter AI warning and projectile, windup/projectile pause, damage on resume and fixture cleanup. First enemy frozen only for the player shot; second enemy live with original collisions. No sustained combat performance or user visual acceptance claim."
	var report: Dictionary = {"status": "FAIL" if failed else "PASS", "combat_only": combat_only, "checks": checks, "records": records, "screenshots": shots, "engine": Engine.get_version_info(), "renderer": RenderingServer.get_current_rendering_method(), "device": RenderingServer.get_video_adapter_name(), "scope": scope}
	FileAccess.open(out + "results.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	FileAccess.open(out + "fade-trace.json", FileAccess.WRITE).store_string(JSON.stringify(fade_trace))
	print("VISIBILITY_LAB_RESULT checks=", checks.size(), " failures=", checks.filter(func(item: Dictionary) -> bool: return not item.pass).size())
	quit(1 if failed else 0)
