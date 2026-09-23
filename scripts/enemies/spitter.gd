extends CharacterBody3D
class_name Spitter

signal projectile_requested(source: Spitter, origin: Vector3, direction: Vector3, damage: int, speed: float, max_range: float, cast_key: String)
signal died(source: Spitter, ability_id: StringName, death_position: Vector3)
signal phase_changed(source: Spitter, phase: StringName)

const PROFILE = preload("res://data/abilities/sticky_spit.tres")
const BASE_SPEED := 2.5
const MAX_HEALTH := 30
const GRAVITY := 20.0
const ENGAGE_DISTANCE := 7.0
const RETREAT_DISTANCE := 4.0
const AIM_LOCK_SECONDS := 0.20
const MAX_SHOT_RANGE := 18.0

enum Phase { IDLE, WINDUP, RECOVERY, DEAD }

@onready var body_visual: MeshInstance3D = $VisualRoot/Body
@onready var muzzle: Marker3D = $VisualRoot/Muzzle
@onready var charge: MeshInstance3D = $VisualRoot/Muzzle/Charge
@onready var charge_ring: MeshInstance3D = $VisualRoot/Muzzle/ChargeRing
@onready var fire_flash: MeshInstance3D = $VisualRoot/Muzzle/FireFlash
@onready var ground_warning: MeshInstance3D = $GroundWarning
@onready var left_pouch: MeshInstance3D = $VisualRoot/LeftPouch
@onready var right_pouch: MeshInstance3D = $VisualRoot/RightPouch
@onready var sticky_marker: MeshInstance3D = $VisualRoot/StickyMarker
@onready var hit_flash: MeshInstance3D = $VisualRoot/HitFlash

var player_target: Node3D
var attack_permission: Callable
var health := MAX_HEALTH
var _phase := Phase.IDLE
var _phase_left := 0.0
var _aim_locked := false
var _locked_direction := Vector3.FORWARD
var _shot_count := 0
var _hit_casts: Dictionary = {}
var _sticky_left := 0.0
var _sticky_factor := 1.0
var _hit_flash_left := 0.0
var _fire_flash_left := 0.0


func _ready() -> void:
	add_to_group(&"enemies")
	floor_snap_length = 0.20
	charge.visible = false
	charge_ring.visible = false
	fire_flash.visible = false
	ground_warning.visible = false
	sticky_marker.visible = false
	hit_flash.visible = false


func _physics_process(delta: float) -> void:
	if _phase == Phase.DEAD:
		return
	_tick_status(delta)
	var target_valid := _has_live_target()
	var toward := Vector3.ZERO
	var distance := INF
	if target_valid:
		toward = player_target.global_position - global_position
		toward.y = 0.0
		distance = toward.length()
		if distance > 0.01:
			toward /= distance
		if not _aim_locked:
			_face(toward, delta)
	_move(toward, distance, delta)
	if not target_valid:
		if _phase == Phase.WINDUP:
			_set_phase(Phase.IDLE, 0.0)
		return
	if _phase == Phase.IDLE:
		if distance <= ENGAGE_DISTANCE and _has_line_of_sight() and (not attack_permission.is_valid() or attack_permission.call(self)):
			_set_phase(Phase.WINDUP, PROFILE.enemy_windup)
	elif _phase == Phase.WINDUP:
		_phase_left -= delta
		if not _aim_locked and _phase_left <= AIM_LOCK_SECONDS:
			_aim_locked = true
			_locked_direction = _direction_to_target()
		if _phase_left <= 0.0:
			_fire()
			_set_phase(Phase.RECOVERY, PROFILE.enemy_recovery)
	elif _phase == Phase.RECOVERY:
		_phase_left -= delta
		if _phase_left <= 0.0:
			_set_phase(Phase.IDLE, 0.0)


func _process(delta: float) -> void:
	if _phase == Phase.DEAD:
		return
	_hit_flash_left = maxf(0.0, _hit_flash_left - delta)
	_fire_flash_left = maxf(0.0, _fire_flash_left - delta)
	hit_flash.visible = _hit_flash_left > 0.0
	fire_flash.visible = _fire_flash_left > 0.0
	if fire_flash.visible:
		fire_flash.scale = Vector3.ONE * (0.7 + _fire_flash_left / 0.12 * 1.8)
	var target_scale := Vector3.ONE
	var pouch_swell := 0.0
	if _phase == Phase.WINDUP:
		var progress: float = clampf(1.0 - _phase_left / PROFILE.enemy_windup, 0.0, 1.0)
		target_scale = Vector3(1.0 + progress * 0.20, 1.0 + progress * 0.32, 1.0 + progress * 0.20)
		pouch_swell = progress
		charge.scale = Vector3.ONE * (0.8 + progress * 1.8)
		charge_ring.scale = Vector3.ONE * (1.35 - progress * 0.52)
		ground_warning.scale = Vector3.ONE * (1.0 + progress * 0.65)
	body_visual.scale = body_visual.scale.lerp(target_scale, minf(1.0, delta * 12.0))
	var pouch_scale := Vector3(1.0 + pouch_swell * 0.34, 1.0 + pouch_swell * 0.32, 1.0 + pouch_swell * 0.55)
	left_pouch.scale = left_pouch.scale.lerp(pouch_scale, minf(1.0, delta * 16.0))
	right_pouch.scale = right_pouch.scale.lerp(pouch_scale, minf(1.0, delta * 16.0))
	sticky_marker.visible = _sticky_left > 0.0
	sticky_marker.rotation.y += delta * 2.0


func receive_hit(amount: int, cast_key: String, source_team: StringName) -> bool:
	if _phase == Phase.DEAD or source_team != &"player" or amount <= 0 or cast_key.is_empty():
		return false
	if _hit_casts.has(cast_key):
		return false
	_hit_casts[cast_key] = true
	health = maxi(0, health - amount)
	_hit_flash_left = 0.12
	if health == 0:
		_die()
	return true


func apply_sticky(factor: float, seconds: float) -> void:
	if _phase == Phase.DEAD or seconds <= 0.0:
		return
	_sticky_factor = clampf(factor, 0.1, 1.0)
	_sticky_left = seconds
	sticky_marker.visible = true


func current_move_speed() -> float:
	return BASE_SPEED * _sticky_factor if _sticky_left > 0.0 else BASE_SPEED


func get_sticky_time_left() -> float:
	return _sticky_left


func clear_sticky() -> void:
	_sticky_left = 0.0
	_sticky_factor = 1.0
	sticky_marker.visible = false


func get_attack_phase() -> StringName:
	match _phase:
		Phase.WINDUP:
			return &"windup"
		Phase.RECOVERY:
			return &"recovery"
		Phase.DEAD:
			return &"dead"
	return &"idle"


func is_alive() -> bool:
	return _phase != Phase.DEAD


func _tick_status(delta: float) -> void:
	if _sticky_left > 0.0:
		_sticky_left = maxf(0.0, _sticky_left - delta)
		if _sticky_left == 0.0:
			_sticky_factor = 1.0
			sticky_marker.visible = false


func _has_live_target() -> bool:
	if not is_instance_valid(player_target) or not player_target.is_inside_tree():
		return false
	if player_target.has_method("is_alive"):
		return player_target.call("is_alive")
	return true


func _face(toward: Vector3, delta: float) -> void:
	if toward.length_squared() < 0.5:
		return
	var desired_yaw := atan2(-toward.x, -toward.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, minf(1.0, delta * 8.0))


func _move(toward: Vector3, distance: float, delta: float) -> void:
	var move_direction := Vector3.ZERO
	if distance > ENGAGE_DISTANCE - 0.5:
		move_direction = toward
	elif distance < RETREAT_DISTANCE and _can_retreat(-toward):
		move_direction = -toward
	var speed_multiplier := 0.35 if _phase == Phase.WINDUP else 1.0
	var target_velocity := move_direction * current_move_speed() * speed_multiplier
	velocity.x = move_toward(velocity.x, target_velocity.x, 14.0 * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, 14.0 * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = minf(velocity.y, 0.0)
	move_and_slide()


func _can_retreat(direction: Vector3) -> bool:
	if direction.length_squared() < 0.5:
		return false
	var next := global_position + direction * 0.85
	if absf(next.x) > 5.8 or absf(next.z) > 8.8:
		return false
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.55, next + Vector3.UP * 0.55, 1)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _has_line_of_sight() -> bool:
	var query := PhysicsRayQueryParameters3D.create(muzzle.global_position, player_target.global_position + Vector3.UP * 0.65, 3)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == player_target


func _direction_to_target() -> Vector3:
	if not _has_live_target():
		return -global_basis.z
	return (player_target.global_position + Vector3.UP * 0.65 - muzzle.global_position).normalized()


func _fire() -> void:
	if not _has_live_target():
		return
	_fire_flash_left = 0.12
	fire_flash.visible = true
	_shot_count += 1
	var cast_key := "enemy_%d_%d" % [get_instance_id(), _shot_count]
	projectile_requested.emit(self, muzzle.global_position, _locked_direction, PROFILE.enemy_damage, PROFILE.enemy_projectile_speed, MAX_SHOT_RANGE, cast_key)


func _set_phase(next_phase: Phase, duration: float) -> void:
	_phase = next_phase
	_phase_left = duration
	_aim_locked = false
	charge.visible = next_phase == Phase.WINDUP
	charge_ring.visible = next_phase == Phase.WINDUP
	ground_warning.visible = next_phase == Phase.WINDUP
	phase_changed.emit(self, get_attack_phase())


func _die() -> void:
	_phase = Phase.DEAD
	charge.visible = false
	charge_ring.visible = false
	ground_warning.visible = false
	fire_flash.visible = false
	sticky_marker.visible = false
	collision_layer = 0
	set_physics_process(false)
	set_process(false)
	phase_changed.emit(self, &"dead")
	died.emit(self, PROFILE.ability_id, global_position)
	queue_free()
