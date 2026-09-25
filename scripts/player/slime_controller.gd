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
const CHARGED_JUMP_SPEED := 8.4
const JUMP_CHARGE_MIN_SECONDS := 0.15
const JUMP_CHARGE_FULL_SECONDS := 0.70
const GRAVITY := 20.0
const STANDING_COLLISION_HEIGHT := 0.80
const STANDING_COLLISION_CENTER_Y := 0.40
const COMPRESSED_COLLISION_HEIGHT := 0.50
const COMPRESSED_COLLISION_RADIUS := 0.24
const COMPRESSED_COLLISION_CENTER_Y := 0.25
const STANDING_CAMERA_HEIGHT := 1.42
const COMPRESSED_CAMERA_HEIGHT := 0.48
const COMPRESSED_CAMERA_DISTANCE := 2.70
const COYOTE_SECONDS := 0.10
const JUMP_BUFFER_SECONDS := 0.12
const MOUSE_SENSITIVITY := 0.0025
const BODY_TURN_RATE := 10.0
const MAX_HEALTH := 100
const HURT_PROTECTION := 0.45
const HIT_REACTION_SECONDS := 0.36
const ABSORB_RADIUS := 1.6
const ABSORB_SECONDS := 0.55
const WHIP_RANGE := 2.0
const WHIP_DAMAGE := 10
const WHIP_HALF_ANGLE_COS := 0.642788

@export_range(0.0, 1.0, 0.01) var walk_visual_strength := 0.20

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var visual_root: Node3D = $VisualRoot
@onready var hero_visual: MeshInstance3D = $VisualRoot/SlimeHeroModelV5
@onready var camera_yaw: Node3D = $CameraYaw
@onready var camera_pitch: Node3D = $CameraYaw/CameraPitch
@onready var spring_arm: SpringArm3D = $CameraYaw/CameraPitch/SpringArm3D
@onready var camera: Camera3D = $CameraYaw/CameraPitch/SpringArm3D/Camera3D

var _coyote_left := 0.0
var _jump_buffer_left := 0.0
var _jump_charging := false
var _jump_charge_seconds := 0.0
var _jump_impulse_pending := 0.0
var _low_passage_sources: Dictionary = {}
var _is_compressed := false
var _standing_collision_shape: CapsuleShape3D
var _compressed_collision_shape: CapsuleShape3D
var _landing_pulse := 0.0
var health := MAX_HEALTH
var equipped_ability: StringName = &""
var second_slot_ability: StringName = &""
var unlocked_slots := 1
var learned_abilities: Dictionary = {}
var _hit_pulse := 0.0
var _hit_local_direction := Vector3.BACK
var _hit_flash_light: OmniLight3D
var _ground_trail: SlimeGroundTrail
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
var _whip_visual: SlimeWhipVisual
var _whip_rng := RandomNumberGenerator.new()
var _whip_variants_left: Array[int] = []
var _whip_variant := SlimeWhipVisual.VARIANT_RIGHT
var _last_whip_variant := -1
var _shell_visual: MeshInstance3D
var _absorb_source: Node3D
var _absorb_elapsed := 0.0
var _absorb_requires_release := false
var _received_casts: Dictionary = {}
var _visual_time := 0.0
var _visual_rest_position := Vector3.ZERO
var _camera_pitch_desired := 0.0
var _spring_rest_length := 0.0


func _ready() -> void:
	add_to_group(&"player")
	floor_snap_length = 0.20
	floor_max_angle = deg_to_rad(45.0)
	spring_arm.add_excluded_object(get_rid())
	_whip_rng.randomize()
	_visual_rest_position = visual_root.position
	_camera_pitch_desired = camera_pitch.rotation.x
	_spring_rest_length = spring_arm.spring_length
	_standing_collision_shape = collision_shape.shape as CapsuleShape3D
	_compressed_collision_shape = CapsuleShape3D.new()
	_compressed_collision_shape.radius = COMPRESSED_COLLISION_RADIUS
	_compressed_collision_shape.height = COMPRESSED_COLLISION_HEIGHT
	_create_hit_flash()
	_create_ground_trail()
	_create_whip_visual()
	hero_visual.call("setup", self, _whip_visual)
	_create_shell_visual()
	health_changed.emit(health, MAX_HEALTH)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw.rotation.y -= event.screen_relative.x * MOUSE_SENSITIVITY
		_camera_pitch_desired = clampf(
			_camera_pitch_desired - event.screen_relative.y * MOUSE_SENSITIVITY,
			deg_to_rad(-65.0),
			deg_to_rad(20.0)
		)
		if not _is_compressed:
			camera_pitch.rotation.x = _camera_pitch_desired


func _physics_process(delta: float) -> void:
	if health <= 0:
		return
	_update_compression(delta)
	_follow_camera_heading(delta)
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

	_update_jump_input(delta, was_on_floor)

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

	if _jump_impulse_pending > 0.0:
		velocity.y = _jump_impulse_pending
		_jump_impulse_pending = 0.0
	elif not was_on_floor:
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = minf(velocity.y, 0.0)

	var impact_speed := -velocity.y
	move_and_slide()
	_whip_visual.refresh_contact(_phase if _action == &"slime_whip" else &"", _phase_left, _whip_variant, get_rid())
	if not was_on_floor and is_on_floor():
		_landing_pulse = 0.14
		_ground_trail.add_landing_splash(impact_speed)
	_update_absorption(delta)



func set_low_passage_active(source: Node, active: bool) -> void:
	if not is_instance_valid(source):
		return
	var source_id := source.get_instance_id()
	if active:
		_low_passage_sources[source_id] = weakref(source)
	else:
		_low_passage_sources.erase(source_id)


func is_compressed() -> bool:
	return _is_compressed


func get_jump_charge_ratio() -> float:
	if not _jump_charging:
		return 0.0
	return clampf(_jump_charge_seconds / JUMP_CHARGE_FULL_SECONDS, 0.0, 1.0)


func _update_compression(delta: float) -> void:
	for source_id: int in _low_passage_sources.keys():
		var source_ref := _low_passage_sources[source_id] as WeakRef
		if source_ref.get_ref() == null:
			_low_passage_sources.erase(source_id)
	if not _low_passage_sources.is_empty() and not _is_compressed:
		collision_shape.shape = _compressed_collision_shape
		collision_shape.position.y = COMPRESSED_COLLISION_CENTER_Y
		_is_compressed = true
	elif _low_passage_sources.is_empty() and _is_compressed and _can_stand():
		collision_shape.shape = _standing_collision_shape
		collision_shape.position.y = STANDING_COLLISION_CENTER_Y
		_is_compressed = false
	var camera_height := COMPRESSED_CAMERA_HEIGHT if _is_compressed else STANDING_CAMERA_HEIGHT
	camera_yaw.position.y = move_toward(camera_yaw.position.y, camera_height, 8.0 * delta)
	var pitch_target := 0.0 if _is_compressed else _camera_pitch_desired
	camera_pitch.rotation.x = move_toward(camera_pitch.rotation.x, pitch_target, 8.0 * delta)
	var arm_target := COMPRESSED_CAMERA_DISTANCE if _is_compressed else _spring_rest_length
	spring_arm.spring_length = move_toward(spring_arm.spring_length, arm_target, 8.0 * delta)


func _can_stand() -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _standing_collision_shape
	query.transform = Transform3D(global_basis, global_position + Vector3.UP * (STANDING_COLLISION_CENTER_Y + 0.015))
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _update_jump_input(delta: float, was_on_floor: bool) -> void:
	if _is_compressed:
		_jump_buffer_left = 0.0
		_jump_charging = false
		_jump_charge_seconds = 0.0
		_jump_impulse_pending = 0.0
		return
	if Input.is_action_just_pressed(&"jump"):
		_jump_buffer_left = JUMP_BUFFER_SECONDS
		cancel_absorb()
	else:
		_jump_buffer_left = maxf(0.0, _jump_buffer_left - delta)
	if not _jump_charging and _jump_buffer_left > 0.0 and _coyote_left > 0.0:
		_jump_charging = true
		_jump_charge_seconds = 0.0
		_jump_buffer_left = 0.0
	if not _jump_charging:
		return
	if was_on_floor:
		_jump_charge_seconds = minf(_jump_charge_seconds + delta, JUMP_CHARGE_FULL_SECONDS)
	if Input.is_action_just_released(&"jump") or not Input.is_action_pressed(&"jump"):
		if _coyote_left > 0.0:
			var charge := clampf((_jump_charge_seconds - JUMP_CHARGE_MIN_SECONDS) / (JUMP_CHARGE_FULL_SECONDS - JUMP_CHARGE_MIN_SECONDS), 0.0, 1.0)
			_jump_impulse_pending = lerpf(JUMP_SPEED, CHARGED_JUMP_SPEED, smoothstep(0.0, 1.0, charge))
			_coyote_left = 0.0
		_jump_charging = false
		_jump_charge_seconds = 0.0
	elif _coyote_left <= 0.0:
		_jump_charging = false
		_jump_charge_seconds = 0.0

func _follow_camera_heading(delta: float) -> void:
	# Transfer the camera's local yaw to the physical body without changing
	# the camera's world heading or the camera-relative movement vector.
	var yaw_gap := wrapf(camera_yaw.rotation.y, -PI, PI)
	var turn := yaw_gap * minf(1.0, delta * BODY_TURN_RATE)
	rotation.y = wrapf(rotation.y + turn, -PI, PI)
	camera_yaw.rotation.y = wrapf(camera_yaw.rotation.y - turn, -PI, PI)
	if _action != &"":
		var local_aim := global_basis.inverse() * _action_direction
		visual_root.rotation.y = atan2(-local_aim.x, -local_aim.z)
	else:
		visual_root.rotation.y = lerp_angle(visual_root.rotation.y, 0.0, minf(1.0, delta * BODY_TURN_RATE))

func _process(delta: float) -> void:
	if health <= 0:
		return
	_visual_time += delta
	_landing_pulse = maxf(0.0, _landing_pulse - delta)
	_hit_pulse = maxf(0.0, _hit_pulse - delta)
	var hit_pose := 0.0
	if _hit_pulse > 0.0:
		var hit_progress := 1.0 - _hit_pulse / HIT_REACTION_SECONDS
		hit_pose = cos(hit_progress * PI * 1.2) * pow(1.0 - hit_progress, 2.0)
		_set_hit_flash_strength(pow(1.0 - hit_progress, 3.0))
	else:
		_set_hit_flash_strength(0.0)
	var speed_ratio := clampf(Vector2(velocity.x, velocity.z).length() / MOVE_SPEED, 0.0, 1.0)
	var breath := sin(_visual_time * 2.6) * 0.018
	var crawl := sin(_visual_time * 10.0) * speed_ratio
	var whip_windup := 0.0
	var whip_strike := 0.0
	var whip_recoil := 0.0
	if _action == &"slime_whip":
		match _phase:
			&"preparation":
				var progress := clampf(1.0 - _phase_left / SlimeWhipVisual.PREPARATION_SECONDS, 0.0, 1.0)
				whip_windup = smoothstep(0.0, 1.0, progress)
			&"active":
				var progress := clampf(1.0 - _phase_left / SlimeWhipVisual.ACTIVE_SECONDS, 0.0, 1.0)
				whip_strike = 1.0 - 0.18 * progress
			&"recovery":
				var progress := clampf(1.0 - _phase_left / SlimeWhipVisual.RECOVERY_SECONDS, 0.0, 1.0)
				whip_recoil = 0.65 * pow(1.0 - smoothstep(0.0, 0.65, progress), 2.0)
	var target_scale := Vector3(1.0 + breath + speed_ratio * 0.04 * walk_visual_strength, 1.0 - breath + (-speed_ratio * 0.07 + crawl * 0.025) * walk_visual_strength, 1.0 + breath + speed_ratio * 0.04 * walk_visual_strength)
	if not is_on_floor():
		target_scale = Vector3(0.93, 1.13, 0.93)
	if _landing_pulse > 0.0:
		target_scale = Vector3(1.12, 0.80, 1.12)

	if _action == &"sticky_spit" and _phase == &"preparation":
		target_scale = Vector3(1.12, 0.90, 1.12)
	elif _action == &"slime_spikes" and _phase == &"preparation":
		target_scale = Vector3(1.16, 0.84, 1.16)
	elif _action == &"elastic_shell" and _phase == &"guard":
		target_scale = Vector3(0.93, 1.08, 0.93)
	if _absorb_elapsed > 0.0:
		target_scale += Vector3(0.035, -0.025, 0.035) * sin(_visual_time * 13.0)
	var charge_squeeze := smoothstep(0.0, 1.0, get_jump_charge_ratio())
	if _jump_charging and not _is_compressed:
		target_scale += Vector3(0.040, -0.100, 0.040) * charge_squeeze
	target_scale += Vector3(0.04, -0.05, 0.04) * hit_pose
	if _is_compressed:
		target_scale = Vector3(minf(target_scale.x, 1.02), minf(target_scale.y, 0.58), minf(target_scale.z, 1.02))
	# The strike reads through weight transfer and lean; the cube itself stays nearly rigid.
	target_scale += Vector3(0.025, -0.030, 0.018) * whip_windup
	target_scale += Vector3(-0.015, 0.012, 0.025) * whip_strike
	visual_root.scale = visual_root.scale.lerp(target_scale, minf(1.0, delta * (24.0 if _action == &"slime_whip" else 12.0)))
	var pose_blend := minf(1.0, delta * (42.0 if _hit_pulse > 0.0 else 28.0))
	var side_sign := -1.0 if _whip_variant == SlimeWhipVisual.VARIANT_LEFT else (0.0 if _whip_variant == SlimeWhipVisual.VARIANT_OVERHEAD else 1.0)
	var overhead := _whip_variant == SlimeWhipVisual.VARIANT_OVERHEAD
	var pose_offset := Vector3(side_sign * (0.075 * whip_windup - 0.095 * whip_strike), (-0.035 if overhead else -0.020) * whip_windup + (0.012 if overhead else 0.0) * whip_strike, (0.085 if overhead else 0.070) * whip_windup - (0.140 if overhead else 0.120) * whip_strike - 0.035 * whip_recoil)
	pose_offset += _hit_local_direction * (0.16 * hit_pose) + Vector3(0.0, -0.03 * hit_pose, 0.0)
	var rest_position := _visual_rest_position
	if _is_compressed:
		rest_position.y = COMPRESSED_COLLISION_CENTER_Y
	elif _jump_charging:
		rest_position.y -= 0.045 * charge_squeeze
	visual_root.position = visual_root.position.lerp(rest_position + pose_offset, pose_blend)
	visual_root.rotation.x = lerpf(visual_root.rotation.x, (0.14 if overhead else 0.10) * whip_windup - (0.22 if overhead else 0.18) * whip_strike - 0.035 * whip_recoil + _hit_local_direction.z * 0.19 * hit_pose, pose_blend)
	var local_velocity := global_basis.inverse() * velocity
	var sway := (crawl * 0.055 - local_velocity.x * 0.012) * walk_visual_strength

	visual_root.rotation.z = lerpf(visual_root.rotation.z, sway + side_sign * (0.14 * whip_windup - 0.17 * whip_strike - 0.035 * whip_recoil) - _hit_local_direction.x * 0.19 * hit_pose, pose_blend if _action == &"slime_whip" or _hit_pulse > 0.0 else minf(1.0, delta * 8.0))
	if is_instance_valid(_shell_visual) and _shell_visual.visible:
		_shell_visual.scale = Vector3(1.0, 0.35 if _is_compressed else 1.0, 1.0) * (1.0 + 0.04 * sin(_visual_time * 11.0))
	_shell_visual.position.y = COMPRESSED_COLLISION_CENTER_Y if _is_compressed else 0.70
	_whip_visual.set_phase(_phase if _action == &"slime_whip" else &"", _phase_left, _whip_variant)


func _create_ground_trail() -> void:
	_ground_trail = SlimeGroundTrail.new()
	_ground_trail.name = "GroundTrail"
	_ground_trail.setup(self)
	add_child(_ground_trail)


func _create_hit_flash() -> void:
	_hit_flash_light = OmniLight3D.new()
	_hit_flash_light.name = "HitFlash"
	_hit_flash_light.light_color = Color(1.0, 0.60, 0.50)
	_hit_flash_light.omni_range = 1.2
	_hit_flash_light.omni_attenuation = 2.0
	_hit_flash_light.position = Vector3(0.0, 0.10, 0.42)
	visual_root.add_child(_hit_flash_light)
	_set_hit_flash_strength(0.0)


func _set_hit_flash_strength(strength: float) -> void:
	_hit_flash_light.light_energy = 1.5 * strength
	_hit_flash_light.visible = strength > 0.001

func _start_hit_reaction(incoming_direction: Vector3 = Vector3.ZERO) -> void:
	var horizontal := Vector3(incoming_direction.x, 0.0, incoming_direction.z)
	if horizontal.length_squared() < 0.001:
		horizontal = global_basis.z
	_hit_local_direction = global_basis.inverse() * horizontal.normalized()
	_hit_local_direction.y = 0.0
	_hit_local_direction = _hit_local_direction.normalized()
	_hit_pulse = HIT_REACTION_SECONDS
	_set_hit_flash_strength(1.0)


func is_alive() -> bool:
	return health > 0


func clear_action_buffer() -> void:
	_buffered_action = &""
	_jump_buffer_left = 0.0
	_jump_charging = false
	_jump_charge_seconds = 0.0
	_jump_impulse_pending = 0.0


func _request_slot_action(slot: int) -> void:
	if slot == 2 and unlocked_slots < 2:
		info_requested.emit("Найди ядро для второй ячейки")
		return
	var ability_id := get_slot_ability(slot)
	if ability_id == &"":
		info_requested.emit("Слот пуст. Поглоти врага или выбери навык в коллекции")
		return
	request_action(ability_id)


func _choose_whip_variant() -> void:
	if _whip_variants_left.is_empty():
		_whip_variants_left.append(SlimeWhipVisual.VARIANT_RIGHT)
		_whip_variants_left.append(SlimeWhipVisual.VARIANT_LEFT)
		_whip_variants_left.append(SlimeWhipVisual.VARIANT_OVERHEAD)
	var index := _whip_rng.randi_range(0, _whip_variants_left.size() - 1)
	if _whip_variants_left.size() == SlimeWhipVisual.VARIANT_COUNT and _whip_variants_left[index] == _last_whip_variant:
		index = (index + 1) % _whip_variants_left.size()
	_whip_variant = _whip_variants_left.pop_at(index)
	_last_whip_variant = _whip_variant


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
			_choose_whip_variant()
			_phase_left = SlimeWhipVisual.PREPARATION_SECONDS
		&"sticky_spit":
			_phase_left = 0.18
		&"slime_spikes":
			_phase_left = 0.35
		&"elastic_shell":
			_phase_left = 0.10
	_cast_sequence += 1
	_cast_key = "%d:%d:%s" % [get_instance_id(), _cast_sequence, action_id]
	_action_aim_point = _get_camera_aim_point()
	_action_direction = _action_aim_point - (global_position + Vector3(0.0, _combat_origin_height(), 0.0))
	_action_direction.y = 0.0
	_action_direction = _action_direction.normalized()
	if _action_direction.length_squared() < 0.01:
		_action_direction = -camera_yaw.global_basis.z
		_action_direction.y = 0.0
		_action_direction = _action_direction.normalized()
	var local_aim := global_basis.inverse() * _action_direction
	visual_root.rotation.y = atan2(-local_aim.x, -local_aim.z)
	if action_id == &"slime_whip":
		_whip_visual.set_phase(&"preparation", _phase_left, _whip_variant)
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
			_phase_left = SlimeWhipVisual.ACTIVE_SECONDS if _action == &"slime_whip" else (0.15 if _action == &"slime_spikes" else 0.04)
			match _action:
				&"slime_whip":
					_whip_visual.set_phase(&"active", _phase_left, _whip_variant)
					_do_whip_hit()
				&"sticky_spit":
					_cooldowns[_action] = ABILITY.player_cooldown
					_release_spit()
				&"slime_spikes":
					_cooldowns[_action] = SPIKES.player_cooldown
					spikes_requested.emit(global_position, _action_direction, _cast_key)
	elif _phase == &"active" or _phase == &"guard":
		_shell_visual.visible = false
		_phase = &"recovery"
		_phase_left = SlimeWhipVisual.RECOVERY_SECONDS if _action == &"slime_whip" else (0.25 if _action == &"slime_spikes" else 0.20)
		if _action == &"slime_whip":
			_whip_visual.set_phase(&"recovery", _phase_left, _whip_variant)
	else:
		_action = &""
		_phase = &""
		_phase_left = 0.0
		if _buffered_action != &"":
			var next_action := _buffered_action
			_buffered_action = &""
			request_action(next_action)


func _combat_origin_height() -> float:
	return 0.30 if _is_compressed else 0.65


func _do_whip_hit() -> void:
	var origin := global_position + Vector3(0.0, _combat_origin_height(), 0.0)
	for enemy: Node in get_tree().get_nodes_in_group(&"enemies") + get_tree().get_nodes_in_group(&"training_targets"):
		if not is_instance_valid(enemy) or not enemy is Node3D or not enemy.has_method("receive_hit"):
			continue
		var target := enemy as Node3D
		var target_point := target.global_position + Vector3(0.0, 0.30 if _is_compressed else 0.7, 0.0)
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
	var origin := global_position + Vector3(0.0, _combat_origin_height(), 0.0) + _action_direction * 0.5
	var direction := (_action_aim_point - origin).normalized()
	if direction.length_squared() < 0.9:
		direction = _action_direction
	projectile_requested.emit(origin, direction, ABILITY.player_damage, ABILITY.player_projectile_speed, ABILITY.player_projectile_range, _cast_key, ABILITY.slow_factor, ABILITY.slow_seconds)


func cooldown_remaining(ability_id: StringName) -> float:
	return float(_cooldowns.get(ability_id, 0.0))


func receive_hit(amount: int, cast_key: String, source_team: StringName, incoming_direction: Vector3 = Vector3.ZERO) -> bool:
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
	_start_hit_reaction(incoming_direction)
	cancel_absorb()
	damaged.emit()
	health_changed.emit(health, MAX_HEALTH)
	if health == 0:
		_finish_death()
	return true


func apply_environment_damage(amount: int) -> void:
	if health <= 0 or amount <= 0:
		return
	health = maxi(0, health - amount)
	_start_hit_reaction()
	cancel_absorb()
	damaged.emit()
	health_changed.emit(health, MAX_HEALTH)
	if health == 0:
		_finish_death()


func _finish_death() -> void:
	_action = &""
	_phase = &""
	_phase_left = 0.0
	clear_action_buffer()
	_whip_visual.visible = false
	_shell_visual.visible = false
	_set_hit_flash_strength(0.0)
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


func _create_whip_visual() -> void:
	_whip_visual = SlimeWhipVisual.new()
	_whip_visual.name = "SlimeWhip"
	_whip_visual.position = Vector3(0.0, 0.22, 0.0)
	visual_root.add_child(_whip_visual)


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
