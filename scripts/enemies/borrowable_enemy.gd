extends CharacterBody3D
class_name BorrowableEnemy

signal died(source: BorrowableEnemy, ability_id: StringName, death_position: Vector3)
signal phase_changed(source: BorrowableEnemy, phase: StringName)
signal spikes_requested(source: BorrowableEnemy, origin: Vector3, direction: Vector3, cast_key: String)

const GRAVITY := 20.0

@export_enum("armorer", "sprout") var kind := "armorer"
var player_target: SlimeController
var attack_permission: Callable
var health := 40

var _phase: StringName = &"approach"
var _phase_left := 0.0
var _shield_raised := false
var _aim_locked := false
var _locked_direction := Vector3.FORWARD
var _cast_sequence := 0
var _hit_casts: Dictionary = {}
var _sticky_left := 0.0
var _sticky_factor := 1.0
var _body: MeshInstance3D
var _warning: MeshInstance3D
var _shield: MeshInstance3D
var _hit_flash: MeshInstance3D
var _hit_flash_left := 0.0
var _cracks: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group(&"enemies")
	collision_layer = 4
	collision_mask = 3
	floor_snap_length = 0.2
	health = 40 if kind == "armorer" else 50
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.48 if kind == "armorer" else 0.52
	shape.height = 1.35
	collider.shape = shape
	collider.position.y = 0.675
	add_child(collider)
	_build_visual()


func _physics_process(delta: float) -> void:
	if _phase == &"dead":
		return
	_sticky_left = maxf(0.0, _sticky_left - delta)
	if _sticky_left <= 0.0:
		_sticky_factor = 1.0
	var has_target := is_instance_valid(player_target) and player_target.is_alive()
	if not has_target:
		if _phase == &"shell" or _phase == &"windup":
			_set_phase(&"approach", 0.0)
		_move(Vector3.ZERO, delta)
		return
	var toward := player_target.global_position - global_position
	toward.y = 0.0
	var distance := toward.length()
	toward = toward.normalized() if distance > 0.01 else Vector3.ZERO
	if not _aim_locked and toward.length_squared() > 0.5:
		rotation.y = lerp_angle(rotation.y, atan2(-toward.x, -toward.z), minf(1.0, delta * 6.0))
	_move(toward if distance > (1.6 if kind == "armorer" else 4.0) else Vector3.ZERO, delta)
	if _phase == &"approach":
		var engage_distance := 2.0 if kind == "armorer" else 7.0
		if distance <= engage_distance and _has_line_of_sight() and (not attack_permission.is_valid() or attack_permission.call(self)):
			_set_phase(&"shell" if kind == "armorer" else &"windup", 1.0 if kind == "armorer" else 0.95)
	elif _phase == &"shell":
		_phase_left -= delta
		if _phase_left <= 0.0:
			_set_phase(&"windup", 0.65)
	elif _phase == &"windup":
		_phase_left -= delta
		if not _aim_locked and _phase_left <= 0.20:
			_aim_locked = true
			_locked_direction = toward
		if _phase_left <= 0.0:
			_attack()
			_set_phase(&"recovery", 1.0 if kind == "armorer" else 1.5)
	elif _phase == &"recovery":
		_phase_left -= delta
		if _phase_left <= 0.0:
			_set_phase(&"approach", 0.0)


func _move(wish: Vector3, delta: float) -> void:
	var direction := wish
	if direction.length_squared() > 0.5:
		var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.55, global_position + direction * 1.25 + Vector3.UP * 0.55, 1)
		ray.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			var left := Vector3(-direction.z, 0.0, direction.x)
			var right := -left
			var left_ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.55, global_position + (direction + left).normalized() * 1.25 + Vector3.UP * 0.55, 1)
			var right_ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.55, global_position + (direction + right).normalized() * 1.25 + Vector3.UP * 0.55, 1)
			left_ray.exclude = [get_rid()]
			right_ray.exclude = [get_rid()]
			direction = (direction + left).normalized() if get_world_3d().direct_space_state.intersect_ray(left_ray).is_empty() else ((direction + right).normalized() if get_world_3d().direct_space_state.intersect_ray(right_ray).is_empty() else Vector3.ZERO)
	var speed := 2.8 if kind == "armorer" else 1.6
	if _phase == &"windup" or _phase == &"shell":
		speed *= 0.35
	velocity.x = move_toward(velocity.x, direction.x * speed * _sticky_factor, delta * 14.0)
	velocity.z = move_toward(velocity.z, direction.z * speed * _sticky_factor, delta * 14.0)
	velocity.y = minf(velocity.y, 0.0) if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()


func _has_line_of_sight() -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.7, player_target.global_position + Vector3.UP * 0.5, 3)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == player_target


func _attack() -> void:
	if not is_instance_valid(player_target) or not player_target.is_alive():
		return
	_cast_sequence += 1
	var cast_key := "enemy_%d_%d" % [get_instance_id(), _cast_sequence]
	if kind == "sprout":
		spikes_requested.emit(self, global_position, _locked_direction, cast_key)
	else:
		var offset := player_target.global_position - global_position
		offset.y = 0.0
		if offset.length() <= 2.1 and _locked_direction.dot(offset.normalized()) >= 0.35 and _has_line_of_sight():
			player_target.receive_hit(12, cast_key, &"enemy", player_target.global_position - global_position)


func receive_hit(amount: int, cast_key: String, source_team: StringName) -> bool:
	if _phase == &"dead" or source_team != &"player" or amount <= 0 or cast_key.is_empty() or _hit_casts.has(cast_key):
		return false
	_hit_casts[cast_key] = true
	if _shield_raised:
		amount = maxi(0, amount - 25)
		_shield_raised = false
		_shield.visible = false
	if amount > 0:
		health = maxi(0, health - amount)
		_hit_flash_left = 0.14
	if health == 0:
		_die()
	return true


func apply_sticky(factor: float, seconds: float) -> void:
	if _phase == &"dead" or seconds <= 0.0:
		return
	_sticky_factor = clampf(factor, 0.1, 1.0)
	_sticky_left = seconds


func clear_sticky() -> void:
	_sticky_left = 0.0
	_sticky_factor = 1.0


func get_sticky_time_left() -> float:
	return _sticky_left


func current_move_speed() -> float:
	return (2.8 if kind == "armorer" else 1.6) * _sticky_factor


func get_attack_phase() -> StringName:
	return &"windup" if _phase == &"shell" or _phase == &"windup" else _phase


func is_alive() -> bool:
	return _phase != &"dead"


func _set_phase(next_phase: StringName, seconds: float) -> void:
	_phase = next_phase
	_phase_left = seconds
	_aim_locked = false
	_shield_raised = next_phase == &"shell"
	_shield.visible = _shield_raised
	_warning.visible = next_phase == &"windup" or next_phase == &"shell"
	for crack in _cracks:
		crack.visible = next_phase == &"windup"
	phase_changed.emit(self, get_attack_phase())


func _die() -> void:
	_phase = &"dead"
	collision_layer = 0
	set_physics_process(false)
	set_process(false)
	phase_changed.emit(self, &"dead")
	died.emit(self, &"elastic_shell" if kind == "armorer" else &"slime_spikes", global_position)
	queue_free()


func _process(delta: float) -> void:
	_hit_flash_left = maxf(0.0, _hit_flash_left - delta)
	_hit_flash.visible = _hit_flash_left > 0.0
	if _warning.visible:
		_warning.scale = Vector3.ONE * (1.0 + 0.12 * sin(Time.get_ticks_msec() * 0.02))


func _build_visual() -> void:
	var root := Node3D.new()
	root.position.y = 0.7
	root.name = "VisualRoot"
	add_child(root)
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color(0.37, 0.47, 0.62) if kind == "armorer" else Color(0.48, 0.43, 0.32)
	body_material.roughness = 0.74
	_body = MeshInstance3D.new()
	_body.mesh = SphereMesh.new()
	_body.scale = Vector3(0.60, 0.64, 0.55) if kind == "armorer" else Vector3(0.60, 0.82, 0.58)
	_body.material_override = body_material
	root.add_child(_body)
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.64, 0.85, 0.96) if kind == "armorer" else Color(0.93, 0.67, 0.33)
	accent.emission_enabled = true
	accent.emission = accent.albedo_color * 0.6
	for side in [-1.0, 1.0]:
		var crest := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.18
		cone.height = 0.55
		crest.mesh = cone
		crest.position = Vector3(side * 0.29, 0.52, -0.02)
		crest.material_override = accent
		root.add_child(crest)
	var eye := MeshInstance3D.new()
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.11
	eye_mesh.height = 0.22
	eye.mesh = eye_mesh
	eye.position = Vector3(0.0, 0.13, -0.52)
	eye.material_override = accent
	root.add_child(eye)
	_shield = MeshInstance3D.new()
	var shield_mesh := SphereMesh.new()
	shield_mesh.radius = 0.76
	shield_mesh.height = 1.52
	_shield.mesh = shield_mesh
	_shield.position.y = 0.72
	var shield_material := StandardMaterial3D.new()
	shield_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shield_material.albedo_color = Color(0.56, 0.84, 1.0, 0.34)
	shield_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shield.material_override = shield_material
	_shield.visible = false
	add_child(_shield)
	_warning = MeshInstance3D.new()
	var warning_mesh := TorusMesh.new()
	warning_mesh.inner_radius = 0.55
	warning_mesh.outer_radius = 0.68
	_warning.mesh = warning_mesh
	_warning.position.y = 0.04
	_warning.material_override = accent
	_warning.visible = false
	add_child(_warning)
	if kind == "sprout":
		var crack_material := StandardMaterial3D.new()
		crack_material.albedo_color = Color(1.0, 0.57, 0.18)
		crack_material.emission_enabled = true
		crack_material.emission = Color(0.9, 0.33, 0.06)
		crack_material.emission_energy_multiplier = 1.3
		for index in 5:
			var crack := MeshInstance3D.new()
			var bar := BoxMesh.new()
			bar.size = Vector3(0.82, 0.022, 0.13)
			crack.mesh = bar
			crack.material_override = crack_material
			crack.position = Vector3(0.0, 0.035, -float(index + 1))
			crack.rotation.y = float(index) * 0.28
			crack.visible = false
			add_child(crack)
			_cracks.append(crack)
	_hit_flash = MeshInstance3D.new()
	_hit_flash.mesh = _body.mesh
	_hit_flash.position = root.position
	_hit_flash.scale = _body.scale * 1.04
	_hit_flash.material_override = accent
	_hit_flash.visible = false
	add_child(_hit_flash)
