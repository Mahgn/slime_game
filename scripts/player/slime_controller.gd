extends CharacterBody3D
class_name SlimeController

signal health_changed(current: int, maximum: int)
signal died
signal damaged
signal ability_unlocked(ability_id: StringName)
signal absorb_progress_changed(progress: float, source: Node3D)
signal projectile_requested(origin: Vector3, direction: Vector3, damage: int, speed: float, max_range: float, cast_key: String, slow_factor: float, slow_seconds: float)
signal spikes_requested(origin: Vector3, direction: Vector3, cast_key: String)
signal whip_hit(position: Vector3)
signal action_started(action_id: StringName)
signal info_requested(message: String)
signal loadout_changed
signal slots_changed(count: int)
signal shell_blocked

const ABILITY: AbilityDefinition = preload("res://data/abilities/sticky_spit.tres")
const SPIKES: AbilityDefinition = preload("res://data/abilities/slime_spikes.tres")
const SHELL: AbilityDefinition = preload("res://data/abilities/elastic_shell.tres")
const KNOWN_ABILITIES: Array[StringName] = [&"sticky_spit", &"slime_spikes", &"elastic_shell"]

const MOVE_SPEED := 5.2
const GROUND_ACCELERATION := 28.0
const GROUND_BRAKING := 38.0
const AIR_ACCELERATION := 18.2
const JUMP_SPEED := 6.4
const GRAVITY := 20.0
const COYOTE_SECONDS := 0.10
const JUMP_BUFFER_SECONDS := 0.12
const MOUSE_SENSITIVITY := 0.0025
const MAX_HEALTH := 100
const HURT_PROTECTION := 0.45
const ABSORB_RADIUS := 1.6
const ABSORB_SECONDS := 0.55
const WHIP_RANGE := 2.0
const WHIP_DAMAGE := 10
const WHIP_HALF_ANGLE_COS := 0.642788

@onready var visual_root: Node3D = $VisualRoot
@onready var body_mesh: MeshInstance3D = $VisualRoot/Body
@onready var camera_yaw: Node3D = $CameraYaw
@onready var camera_pitch: Node3D = $CameraYaw/CameraPitch
@onready var spring_arm: SpringArm3D = $CameraYaw/CameraPitch/SpringArm3D
@onready var camera: Camera3D = $CameraYaw/CameraPitch/SpringArm3D/Camera3D

var _coyote_left := 0.0
var _jump_buffer_left := 0.0
var _landing_pulse := 0.0
var health := MAX_HEALTH
var equipped_ability: StringName = &""
var second_slot_ability: StringName = &""
var unlocked_slots := 1
var learned_abilities: Dictionary = {}
var _hit_pulse := 0.0
var _hurt_protection_left := 0.0
var _cooldowns: Dictionary = {}
var _action: StringName = &""
var _phase: StringName = &""
var _phase_left := 0.0
var _buffered_action: StringName = &""
var _cast_sequence := 0
var _cast_key := ""
var _action_direction := Vector3.FORWARD
var _action_aim_point := Vector3.ZERO
var _whip_visual: Node3D
var _shell_visual: MeshInstance3D
var _absorb_source: Node3D
var _absorb_elapsed := 0.0
var _absorb_requires_release := false
var _received_casts: Dictionary = {}
var _visual_time := 0.0
var _back_core: MeshInstance3D
var _back_core_material: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"player")
	floor_snap_length = 0.20
	floor_max_angle = deg_to_rad(45.0)
	spring_arm.add_excluded_object(get_rid())
	_build_slime_visual()
	_create_whip_visual()
	_create_shell_visual()
	health_changed.emit(health, MAX_HEALTH)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw.rotation.y -= event.screen_relative.x * MOUSE_SENSITIVITY
		camera_pitch.rotation.x = clampf(
			camera_pitch.rotation.x - event.screen_relative.y * MOUSE_SENSITIVITY,
			deg_to_rad(-65.0),
			deg_to_rad(20.0)
		)


func _physics_process(delta: float) -> void:
	if health <= 0:
		return
	_hurt_protection_left = maxf(0.0, _hurt_protection_left - delta)
	for ability_id: StringName in _cooldowns.keys():
		_cooldowns[ability_id] = maxf(0.0, float(_cooldowns[ability_id]) - delta)
	_advance_action(delta)
	if Input.is_action_just_pressed(&"attack_primary"):
		request_action(&"slime_whip")
	if Input.is_action_just_pressed(&"ability_slot_1"):
		_request_slot_action(1)
	if Input.is_action_just_pressed(&"ability_slot_2"):
		_request_slot_action(2)
	var was_on_floor := is_on_floor()
	if was_on_floor:
		_coyote_left = COYOTE_SECONDS
	else:
		_coyote_left = maxf(0.0, _coyote_left - delta)

	if Input.is_action_just_pressed(&"jump"):
		_jump_buffer_left = JUMP_BUFFER_SECONDS
		cancel_absorb()
	else:
		_jump_buffer_left = maxf(0.0, _jump_buffer_left - delta)

	var axes := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var move_direction := camera_yaw.global_basis.x * axes.x + camera_yaw.global_basis.z * axes.y
	move_direction.y = 0.0
	move_direction = move_direction.normalized()
	var action_speed := 1.0
	if _action == &"elastic_shell":
		action_speed = 0.70
	elif _action != &"":
		action_speed = 0.75
	var target_velocity := move_direction * MOVE_SPEED * action_speed
	var acceleration := AIR_ACCELERATION
	if was_on_floor:
		acceleration = GROUND_ACCELERATION if axes.length_squared() > 0.0 else GROUND_BRAKING
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)

	if _jump_buffer_left > 0.0 and _coyote_left > 0.0:
		velocity.y = JUMP_SPEED
		_jump_buffer_left = 0.0
		_coyote_left = 0.0
	elif not was_on_floor:
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = minf(velocity.y, 0.0)

	move_and_slide()
	if not was_on_floor and is_on_floor():
		_landing_pulse = 0.14
	_update_absorption(delta)


func _process(delta: float) -> void:
	_visual_time += delta
	_landing_pulse = maxf(0.0, _landing_pulse - delta)
	_hit_pulse = maxf(0.0, _hit_pulse - delta)
	var speed_ratio := clampf(Vector2(velocity.x, velocity.z).length() / MOVE_SPEED, 0.0, 1.0)
	var breath := sin(_visual_time * 2.6) * 0.018
	var crawl := sin(_visual_time * 10.0) * speed_ratio
	var target_scale := Vector3(1.0 + breath + speed_ratio * 0.04, 1.0 - breath - speed_ratio * 0.07 + crawl * 0.025, 1.0 + breath + speed_ratio * 0.04)
	if not is_on_floor():
		target_scale = Vector3(0.93, 1.13, 0.93)
	if _landing_pulse > 0.0:
		target_scale = Vector3(1.12, 0.80, 1.12)
	if _hit_pulse > 0.0:
		target_scale = Vector3(1.18, 0.78, 1.18)
	if _action == &"slime_whip" and _phase == &"active":
		target_scale = Vector3(0.87, 1.04, 1.18)
	elif _action == &"sticky_spit" and _phase == &"preparation":
		target_scale = Vector3(1.12, 0.90, 1.12)
	elif _action == &"slime_spikes" and _phase == &"preparation":
		target_scale = Vector3(1.16, 0.84, 1.16)
	elif _action == &"elastic_shell" and _phase == &"guard":
		target_scale = Vector3(0.93, 1.08, 0.93)
	if _absorb_elapsed > 0.0:
		target_scale += Vector3(0.035, -0.025, 0.035) * sin(_visual_time * 13.0)
	visual_root.scale = visual_root.scale.lerp(target_scale, minf(1.0, delta * 12.0))
	var sway := crawl * 0.055 - velocity.x * 0.012
	if _hit_pulse > 0.0:
		sway += sin(_visual_time * 44.0) * 0.12
	visual_root.rotation.z = lerpf(visual_root.rotation.z, sway, minf(1.0, delta * 8.0))
	if is_instance_valid(_back_core):
		_back_core.scale = Vector3.ONE * (1.0 + 0.08 * sin(_visual_time * (5.0 if equipped_ability != &"" else 2.6)))
	if is_instance_valid(_shell_visual) and _shell_visual.visible:
		_shell_visual.scale = Vector3.ONE * (1.0 + 0.04 * sin(_visual_time * 11.0))


func is_alive() -> bool:
	return health > 0


func clear_action_buffer() -> void:
	_buffered_action = &""


func _request_slot_action(slot: int) -> void:
	if slot == 2 and unlocked_slots < 2:
		info_requested.emit("Найди ядро для второй ячейки")
		return
	var ability_id := get_slot_ability(slot)
	if ability_id == &"":
		info_requested.emit("Слот пуст. Поглоти врага или выбери навык в коллекции")
		return
	request_action(ability_id)


func request_action(action_id: StringName) -> bool:
	if health <= 0:
		return false
	if action_id != &"slime_whip" and action_id != equipped_ability and action_id != second_slot_ability:
		return false
	if action_id == &"slime_spikes" and not is_on_floor():
		info_requested.emit("Шипы доступны только на земле")
		return false
	if _action != &"":
		if _phase == &"recovery" and _phase_left <= 0.12 and _buffered_action == &"":
			_buffered_action = action_id
		return false
	if cooldown_remaining(action_id) > 0.0:
		return false
	cancel_absorb()
	_action = action_id
	_phase = &"preparation"
	match action_id:
		&"slime_whip":
			_phase_left = 0.12
		&"sticky_spit":
			_phase_left = 0.18
		&"slime_spikes":
			_phase_left = 0.35
		&"elastic_shell":
			_phase_left = 0.10
	_cast_sequence += 1
	_cast_key = "%d:%d:%s" % [get_instance_id(), _cast_sequence, action_id]
	_action_aim_point = _get_camera_aim_point()
	_action_direction = _action_aim_point - (global_position + Vector3(0.0, 0.65, 0.0))
	_action_direction.y = 0.0
	_action_direction = _action_direction.normalized()
	if _action_direction.length_squared() < 0.01:
		_action_direction = -camera_yaw.global_basis.z
		_action_direction.y = 0.0
		_action_direction = _action_direction.normalized()
	visual_root.rotation.y = atan2(-_action_direction.x, -_action_direction.z)
	_whip_visual.rotation.y = visual_root.rotation.y
	action_started.emit(action_id)
	return true


func _advance_action(delta: float) -> void:
	if _action == &"":
		return
	_phase_left -= delta
	if _phase_left > 0.0:
		return
	if _phase == &"preparation":
		if _action == &"elastic_shell":
			_phase = &"guard"
			_phase_left = 1.20
			_cooldowns[_action] = SHELL.player_cooldown
			_shell_visual.visible = true
		else:
			_phase = &"active"
			_phase_left = 0.08 if _action == &"slime_whip" else (0.15 if _action == &"slime_spikes" else 0.04)
			match _action:
				&"slime_whip":
					_whip_visual.visible = true
					_do_whip_hit()
				&"sticky_spit":
					_cooldowns[_action] = ABILITY.player_cooldown
					_release_spit()
				&"slime_spikes":
					_cooldowns[_action] = SPIKES.player_cooldown
					spikes_requested.emit(global_position, _action_direction, _cast_key)
	elif _phase == &"active" or _phase == &"guard":
		_whip_visual.visible = false
		_shell_visual.visible = false
		_phase = &"recovery"
		_phase_left = 0.35 if _action == &"slime_whip" else (0.25 if _action == &"slime_spikes" else 0.20)
	else:
		_action = &""
		_phase = &""
		_phase_left = 0.0
		if _buffered_action != &"":
			var next_action := _buffered_action
			_buffered_action = &""
			request_action(next_action)


func _do_whip_hit() -> void:
	var origin := global_position + Vector3(0.0, 0.65, 0.0)
	for enemy: Node in get_tree().get_nodes_in_group(&"enemies") + get_tree().get_nodes_in_group(&"training_targets"):
		if not is_instance_valid(enemy) or not enemy is Node3D or not enemy.has_method("receive_hit"):
			continue
		var target := enemy as Node3D
		var target_point := target.global_position + Vector3(0.0, 0.7, 0.0)
		var horizontal := target_point - origin
		horizontal.y = 0.0
		if horizontal.length() > WHIP_RANGE or horizontal.length_squared() < 0.001:
			continue
		if _action_direction.dot(horizontal.normalized()) < WHIP_HALF_ANGLE_COS:
			continue
		var wall_query := PhysicsRayQueryParameters3D.create(origin, target_point, 1)
		wall_query.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(wall_query).is_empty():
			continue
		if target.call("receive_hit", WHIP_DAMAGE, _cast_key, &"player"):
			whip_hit.emit(target_point)


func _get_camera_aim_point() -> Vector3:
	var viewport_center := get_viewport().get_visible_rect().size * 0.5
	var ray_origin := camera.project_ray_origin(viewport_center)
	var ray_direction := camera.project_ray_normal(viewport_center)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 40.0, 5)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else ray_origin + ray_direction * 40.0


func _release_spit() -> void:
	var origin := global_position + Vector3(0.0, 0.65, 0.0) + _action_direction * 0.5
	var direction := (_action_aim_point - origin).normalized()
	if direction.length_squared() < 0.9:
		direction = _action_direction
	projectile_requested.emit(origin, direction, ABILITY.player_damage, ABILITY.player_projectile_speed, ABILITY.player_projectile_range, _cast_key, ABILITY.slow_factor, ABILITY.slow_seconds)


func cooldown_remaining(ability_id: StringName) -> float:
	return float(_cooldowns.get(ability_id, 0.0))


func receive_hit(amount: int, cast_key: String, source_team: StringName) -> bool:
	if health <= 0 or source_team != &"enemy" or amount <= 0 or cast_key.is_empty() or _hurt_protection_left > 0.0:
		return false
	if _received_casts.has(cast_key):
		return false
	_received_casts[cast_key] = true
	if _action == &"elastic_shell" and _phase == &"guard":
		amount = maxi(0, amount - 25)
		_phase = &"recovery"
		_phase_left = 0.20
		_shell_visual.visible = false
		shell_blocked.emit()
		if amount == 0:
			return true
	health = maxi(0, health - amount)
	_hurt_protection_left = HURT_PROTECTION
	_hit_pulse = 0.15
	cancel_absorb()
	damaged.emit()
	health_changed.emit(health, MAX_HEALTH)
	if health == 0:
		_action = &""
		_phase = &""
		_buffered_action = &""
		_whip_visual.visible = false
		_shell_visual.visible = false
		visual_root.scale = Vector3(1.24, 0.56, 1.24)
		visual_root.rotation.z = 0.35
		died.emit()
	return true


func apply_environment_damage(amount: int) -> void:
	if health <= 0 or amount <= 0:
		return
	health = maxi(0, health - amount)
	_hit_pulse = 0.15
	cancel_absorb()
	damaged.emit()
	health_changed.emit(health, MAX_HEALTH)
	if health == 0:
		_action = &""
		_phase = &""
		_buffered_action = &""
		_whip_visual.visible = false
		_shell_visual.visible = false
		visual_root.scale = Vector3(1.24, 0.56, 1.24)
		visual_root.rotation.z = 0.35
		died.emit()


func grant_ability(ability_id: StringName) -> bool:
	if not KNOWN_ABILITIES.has(ability_id) or learned_abilities.has(ability_id):
		return false
	learned_abilities[ability_id] = true
	if equipped_ability == &"":
		equipped_ability = ability_id
	elif unlocked_slots >= 2 and second_slot_ability == &"":
		second_slot_ability = ability_id
	if is_instance_valid(_back_core_material):
		_back_core_material.albedo_color = Color(0.26, 0.96, 0.92)
		_back_core_material.emission = Color(0.08, 0.62, 0.69)
	ability_unlocked.emit(ability_id)
	loadout_changed.emit()
	return true


func has_learned(ability_id: StringName) -> bool:
	return learned_abilities.has(ability_id)


func get_slot_ability(slot: int) -> StringName:
	if slot == 1:
		return equipped_ability
	if slot == 2 and unlocked_slots >= 2:
		return second_slot_ability
	return &""


func unlock_second_slot() -> bool:
	if unlocked_slots >= 2:
		return false
	unlocked_slots = 2
	for ability_id: StringName in KNOWN_ABILITIES:
		if learned_abilities.has(ability_id) and ability_id != equipped_ability:
			second_slot_ability = ability_id
			break
	slots_changed.emit(unlocked_slots)
	loadout_changed.emit()
	return true


func equip_ability(slot: int, ability_id: StringName) -> bool:
	if slot < 1 or slot > unlocked_slots:
		return false
	if ability_id != &"" and not learned_abilities.has(ability_id):
		return false
	if ability_id != &"" and get_slot_ability(3 - slot) == ability_id:
		return false
	if slot == 1:
		equipped_ability = ability_id
	else:
		second_slot_ability = ability_id
	loadout_changed.emit()
	return true


func cancel_absorb() -> void:
	if is_instance_valid(_absorb_source) or _absorb_elapsed > 0.0:
		_absorb_source = null
		_absorb_elapsed = 0.0
		_absorb_requires_release = true
		absorb_progress_changed.emit(0.0, null)


func cancel_absorb_for_pause() -> void:
	cancel_absorb()
	_absorb_requires_release = true


func _update_absorption(delta: float) -> void:
	if not Input.is_action_pressed(&"interact"):
		_absorb_requires_release = false
		cancel_absorb()
		return
	if _absorb_requires_release or _action != &"":
		return
	if Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back").length_squared() > 0.01 or not is_on_floor():
		cancel_absorb()
		return
	var source := _find_absorb_source()
	if source != _absorb_source:
		_absorb_source = source
		_absorb_elapsed = 0.0
	if not is_instance_valid(_absorb_source):
		return
	_absorb_elapsed += delta
	absorb_progress_changed.emit(minf(1.0, _absorb_elapsed / ABSORB_SECONDS), _absorb_source)
	if _absorb_elapsed >= ABSORB_SECONDS:
		var source_to_claim := _absorb_source
		var ability_id: StringName = source_to_claim.get("ability_id")
		if KNOWN_ABILITIES.has(ability_id) and not learned_abilities.has(ability_id) and source_to_claim.call("claim"):
			grant_ability(ability_id)
		cancel_absorb()


func _find_absorb_source() -> Node3D:
	var nearest: Node3D
	var nearest_distance := INF
	var origin := global_position + Vector3(0.0, 0.55, 0.0)
	for node: Node in get_tree().get_nodes_in_group(&"absorb_sources"):
		if not is_instance_valid(node) or not node is Node3D or node.call("is_claimed"):
			continue
		var ability_id: StringName = node.get("ability_id")
		if not KNOWN_ABILITIES.has(ability_id) or learned_abilities.has(ability_id):
			continue
		var candidate := node as Node3D
		var distance := global_position.distance_to(candidate.global_position)
		if distance > ABSORB_RADIUS:
			continue
		var query := PhysicsRayQueryParameters3D.create(origin, candidate.global_position + Vector3(0.0, 0.4, 0.0), 1)
		query.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		if distance < nearest_distance or (is_equal_approx(distance, nearest_distance) and is_instance_valid(nearest) and candidate.get_instance_id() < nearest.get_instance_id()):
			nearest = candidate
			nearest_distance = distance
	return nearest


func get_nearest_absorb_source() -> Node3D:
	return _find_absorb_source()


func _build_slime_visual() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_size := Vector3(0.45, 0.40, 0.45)
	var core := half_size - Vector3.ONE * 0.16
	var faces: Array[Dictionary] = [
		{"normal": Vector3.BACK, "u": Vector3.RIGHT, "v": Vector3.UP},
		{"normal": Vector3.FORWARD, "u": Vector3.LEFT, "v": Vector3.UP},
		{"normal": Vector3.RIGHT, "u": Vector3.FORWARD, "v": Vector3.UP},
		{"normal": Vector3.LEFT, "u": Vector3.BACK, "v": Vector3.UP},
		{"normal": Vector3.UP, "u": Vector3.RIGHT, "v": Vector3.FORWARD},
		{"normal": Vector3.DOWN, "u": Vector3.RIGHT, "v": Vector3.BACK},
	]
	for face: Dictionary in faces:
		var normal: Vector3 = face["normal"]
		var u_axis: Vector3 = face["u"]
		var v_axis: Vector3 = face["v"]
		var normal_extent := normal.abs().dot(half_size)
		var u_extent := u_axis.abs().dot(half_size)
		var v_extent := v_axis.abs().dot(half_size)
		for row in 8:
			for column in 8:
				var u0 := (float(column) / 8.0 * 2.0 - 1.0) * u_extent
				var u1 := (float(column + 1) / 8.0 * 2.0 - 1.0) * u_extent
				var v0 := (float(row) / 8.0 * 2.0 - 1.0) * v_extent
				var v1 := (float(row + 1) / 8.0 * 2.0 - 1.0) * v_extent
				var center := normal * normal_extent
				var a := center + u_axis * u0 + v_axis * v0
				var b := center + u_axis * u1 + v_axis * v0
				var c := center + u_axis * u1 + v_axis * v1
				var d := center + u_axis * u0 + v_axis * v1
				_add_rounded_vertex(surface, a, core)
				_add_rounded_vertex(surface, c, core)
				_add_rounded_vertex(surface, b, core)
				_add_rounded_vertex(surface, a, core)
				_add_rounded_vertex(surface, d, core)
				_add_rounded_vertex(surface, c, core)
	body_mesh.mesh = surface.commit()

	_back_core_material = StandardMaterial3D.new()
	_back_core_material.albedo_color = Color(0.12, 0.36, 0.36)
	_back_core_material.roughness = 0.24
	_back_core_material.emission_enabled = true
	_back_core_material.emission = Color(0.04, 0.22, 0.22)
	_back_core_material.emission_energy_multiplier = 1.5
	var core_shape := SphereMesh.new()
	core_shape.radius = 0.105
	core_shape.height = 0.21
	_back_core = MeshInstance3D.new()
	_back_core.name = "AbilityCore"
	_back_core.mesh = core_shape
	_back_core.material_override = _back_core_material
	_back_core.position = Vector3(0.0, 0.10, 0.46)
	visual_root.add_child(_back_core)
	for side in [-1.0, 1.0]:
		var droplet := MeshInstance3D.new()
		droplet.name = "BackDroplet"
		droplet.mesh = core_shape
		droplet.material_override = _back_core_material
		droplet.position = Vector3(side * 0.21, -0.09, 0.42)
		droplet.scale = Vector3.ONE * 0.43
		visual_root.add_child(droplet)


func _add_rounded_vertex(surface: SurfaceTool, point: Vector3, core: Vector3) -> void:
	var nearest := Vector3(
		clampf(point.x, -core.x, core.x),
		clampf(point.y, -core.y, core.y),
		clampf(point.z, -core.z, core.z)
	)
	var normal := (point - nearest).normalized()
	surface.set_normal(normal)
	surface.add_vertex(nearest + normal * 0.16)


func _create_whip_visual() -> void:
	_whip_visual = Node3D.new()
	_whip_visual.name = "SlimeWhip"
	_whip_visual.position = Vector3(0.0, 0.65, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.24, 0.98, 0.72)
	material.emission_enabled = true
	material.emission = Color(0.09, 0.58, 0.34)
	material.emission_energy_multiplier = 1.1
	var base := Vector3(0.26, 0.25, -0.22)
	var bend := Vector3(0.78, 0.52, -1.10)
	var tip := Vector3(0.52, 0.25, -1.96)
	_add_whip_link(base, bend, 0.14, material)
	_add_whip_link(bend, tip, 0.17, material)
	_add_whip_joint(base, 0.14, material)
	_add_whip_joint(bend, 0.18, material)
	_add_whip_joint(tip, 0.23, material)
	_whip_visual.visible = false
	add_child(_whip_visual)


func _create_shell_visual() -> void:
	_shell_visual = MeshInstance3D.new()
	_shell_visual.name = "ElasticShell"
	var mesh := SphereMesh.new()
	mesh.radius = 0.70
	mesh.height = 1.40
	_shell_visual.mesh = mesh
	_shell_visual.position.y = 0.70
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.43, 0.83, 1.0, 0.28)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = true
	material.emission = Color(0.18, 0.57, 0.83)
	material.emission_energy_multiplier = 0.8
	_shell_visual.material_override = material
	_shell_visual.visible = false
	add_child(_shell_visual)


func _add_whip_link(start: Vector3, finish: Vector3, radius: float, material: Material) -> void:
	var segment := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = start.distance_to(finish)
	segment.mesh = shape
	segment.position = (start + finish) * 0.5
	segment.quaternion = Quaternion(Vector3.UP, (finish - start).normalized())
	segment.material_override = material
	_whip_visual.add_child(segment)


func _add_whip_joint(at: Vector3, radius: float, material: Material) -> void:
	var segment := MeshInstance3D.new()
	var shape := SphereMesh.new()
	shape.radius = 1.0
	shape.height = 2.0
	segment.mesh = shape
	segment.position = at
	segment.scale = Vector3.ONE * radius
	segment.material_override = material
	_whip_visual.add_child(segment)
