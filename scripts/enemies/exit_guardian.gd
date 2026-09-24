extends CharacterBody3D
class_name ExitGuardian

signal died
signal health_changed(current: int, maximum: int)
signal phase_changed(source: Node, phase: StringName)
signal line_requested(source: ExitGuardian, origin: Vector3, direction: Vector3, cast_key: String)

const MAX_HEALTH := 180
const GRAVITY := 20.0
const MOVE_SPEED := 1.9
const RECOVERY_SECONDS := 1.3
const WINDUP_SECONDS := [1.0, 0.8, 1.1]
const ENGAGE_DISTANCE := [5.2, 2.55, 2.85]
const ATTACK_IDS: Array[StringName] = [&"line", &"arc", &"radial"]

var player_target: SlimeController
var health := MAX_HEALTH
var _phase: StringName = &"approach"
var _phase_left := 0.0
var _attack_index := 0
var _locked_direction := Vector3.FORWARD
var _aim_locked := false
var _cast_sequence := 0
var _received_casts: Dictionary = {}
var _sticky_left := 0.0
var _sticky_factor := 1.0
var _hit_flash_left := 0.0
var _body: MeshInstance3D
var _body_material: StandardMaterial3D
var _sticky_mark: MeshInstance3D
var _warning_line: MeshInstance3D
var _warning_arc: Node3D
var _warning_radial: MeshInstance3D


func _ready() -> void:
	add_to_group(&"enemies")
	collision_layer = 4
	collision_mask = 3
	floor_snap_length = 0.2
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.82
	shape.height = 2.25
	collider.shape = shape
	collider.position.y = 1.13
	add_child(collider)
	_build_visual()
	health_changed.emit(health, MAX_HEALTH)


func _physics_process(delta: float) -> void:
	if _phase == &"dead":
		return
	_sticky_left = maxf(0.0, _sticky_left - delta)
	if _sticky_left <= 0.0:
		_sticky_factor = 1.0
	_sticky_mark.visible = _sticky_left > 0.0
	if not is_instance_valid(player_target) or not player_target.is_alive():
		_move(Vector3.ZERO, delta)
		return
	var to_player := player_target.global_position - global_position
	to_player.y = 0.0
	var distance := to_player.length()
	var toward := to_player.normalized() if distance > 0.01 else Vector3.FORWARD
	if _phase == &"approach":
		if distance > ENGAGE_DISTANCE[_attack_index] or not _has_line_of_sight():
			_move(toward, delta)
		else:
			_move(Vector3.ZERO, delta)
			_start_windup()
	elif _phase == &"windup":
		if not _aim_locked:
			_face(toward, delta)
		_move(Vector3.ZERO, delta)
		_phase_left -= delta
		if not _aim_locked and _phase_left <= 0.20:
			_aim_locked = true
			_locked_direction = -global_basis.z
			_locked_direction.y = 0.0
			_locked_direction = _locked_direction.normalized()
		if _phase_left <= 0.0:
			_strike()
			_attack_index = (_attack_index + 1) % ATTACK_IDS.size()
			_set_phase(&"recovery", RECOVERY_SECONDS)
	else:
		_move(Vector3.ZERO, delta)
		_phase_left -= delta
		if _phase_left <= 0.0:
			_set_phase(&"approach", 0.0)


func _process(delta: float) -> void:
	_hit_flash_left = maxf(0.0, _hit_flash_left - delta)
	_body_material.albedo_color = Color(0.97, 0.91, 0.67) if _hit_flash_left > 0.0 else Color(0.47, 0.40, 0.30)


func _move(wish: Vector3, delta: float) -> void:
	var speed := MOVE_SPEED * _sticky_factor
	velocity.x = move_toward(velocity.x, wish.x * speed, delta * 12.0)
	velocity.z = move_toward(velocity.z, wish.z * speed, delta * 12.0)
	velocity.y = minf(velocity.y, 0.0) if is_on_floor() else velocity.y - GRAVITY * delta
	if wish.length_squared() > 0.5:
		_face(wish, delta)
	move_and_slide()


func _face(direction: Vector3, delta: float) -> void:
	if direction.length_squared() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(1.0, delta * 5.5))


func _has_line_of_sight() -> bool:
	if not is_instance_valid(player_target):
		return false
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.0, player_target.global_position + Vector3.UP * 0.45, 3)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == player_target


func _start_windup() -> void:
	_aim_locked = false
	_set_phase(&"windup", WINDUP_SECONDS[_attack_index])


func _set_phase(next_phase: StringName, seconds: float) -> void:
	_phase = next_phase
	_phase_left = seconds
	_warning_line.visible = next_phase == &"windup" and _attack_index == 0
	_warning_arc.visible = next_phase == &"windup" and _attack_index == 1
	_warning_radial.visible = next_phase == &"windup" and _attack_index == 2
	phase_changed.emit(self, next_phase)


func _strike() -> void:
	if not is_instance_valid(player_target) or not player_target.is_alive():
		return
	_cast_sequence += 1
	var cast_key := "guardian_%d_%d" % [get_instance_id(), _cast_sequence]
	if _attack_index == 0:
		line_requested.emit(self, global_position, _locked_direction, cast_key)
		return
	var delta := player_target.global_position - global_position
	delta.y = 0.0
	var distance := delta.length()
	if _attack_index == 1:
		if distance <= 2.65 and distance > 0.01 and _locked_direction.dot(delta.normalized()) >= 0.50 and _has_line_of_sight():
			player_target.receive_hit(16, cast_key, &"enemy")
	elif distance <= 3.0 and player_target.global_position.y - global_position.y <= 0.45 and _has_line_of_sight():
		player_target.receive_hit(20, cast_key, &"enemy")


func receive_hit(amount: int, cast_key: String, source_team: StringName) -> bool:
	if _phase == &"dead" or source_team != &"player" or amount <= 0 or cast_key.is_empty() or _received_casts.has(cast_key):
		return false
	_received_casts[cast_key] = true
	health = maxi(0, health - amount)
	_hit_flash_left = 0.14
	health_changed.emit(health, MAX_HEALTH)
	if health == 0:
		_die()
	return true


func apply_sticky(factor: float, seconds: float) -> void:
	if _phase == &"dead" or seconds <= 0.0:
		return
	_sticky_factor = maxf(0.75, clampf(factor, 0.1, 1.0))
	_sticky_left = seconds
	_sticky_mark.visible = true


func get_sticky_time_left() -> float:
	return _sticky_left


func clear_sticky() -> void:
	_sticky_left = 0.0
	_sticky_factor = 1.0
	_sticky_mark.visible = false


func is_alive() -> bool:
	return _phase != &"dead"


func get_attack_phase() -> StringName:
	return _phase


func _die() -> void:
	_phase = &"dead"
	collision_layer = 0
	set_physics_process(false)
	set_process(false)
	_warning_line.visible = false
	_warning_arc.visible = false
	_warning_radial.visible = false
	phase_changed.emit(self, &"dead")
	died.emit()
	queue_free()


func _build_visual() -> void:
	var root := Node3D.new()
	root.name = "VisualRoot"
	root.position.y = 1.04
	add_child(root)
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = Color(0.47, 0.40, 0.30)
	_body_material.roughness = 0.78
	_body = MeshInstance3D.new()
	_body.name = "Body"
	_body.mesh = SphereMesh.new()
	_body.scale = Vector3(1.12, 1.02, 0.92)
	_body.material_override = _body_material
	root.add_child(_body)
	var crown_material := _material(Color(0.68, 0.57, 0.39))
	for x in [-0.70, 0.0, 0.70]:
		var crown := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.bottom_radius = 0.27
		cone.top_radius = 0.0
		cone.height = 0.88 if x == 0.0 else 0.62
		crown.mesh = cone
		crown.position = Vector3(x, 1.0 + cone.height * 0.25, 0.0)
		crown.material_override = crown_material
		root.add_child(crown)
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.34
	sphere.height = 0.68
	core.mesh = sphere
	core.position = Vector3(0.0, 0.06, -0.87)
	core.material_override = _material(Color(1.0, 0.59, 0.27), true)
	root.add_child(core)
	_sticky_mark = MeshInstance3D.new()
	var sticky := TorusMesh.new()
	sticky.inner_radius = 0.91
	sticky.outer_radius = 1.03
	_sticky_mark.mesh = sticky
	_sticky_mark.position.y = -0.87
	_sticky_mark.material_override = _material(Color(0.18, 0.94, 0.75), true)
	_sticky_mark.visible = false
	root.add_child(_sticky_mark)
	_warning_line = _flat_box("LineWarning", Vector3(0.0, 0.04, -3.0), Vector3(1.04, 0.04, 5.0), Color(1.0, 0.55, 0.23))
	_warning_arc = Node3D.new()
	_warning_arc.name = "ArcWarning"
	add_child(_warning_arc)
	for degrees in [-48.0, -24.0, 0.0, 24.0, 48.0]:
		var stripe := _flat_box("ArcStripe", Vector3.ZERO, Vector3(0.24, 0.04, 2.45), Color(1.0, 0.31, 0.19), _warning_arc)
		stripe.rotation.y = deg_to_rad(degrees)
		stripe.position = stripe.basis * Vector3(0.0, 0.04, -1.28)
	_warning_radial = MeshInstance3D.new()
	_warning_radial.name = "RadialWarning"
	var ring := TorusMesh.new()
	ring.inner_radius = 2.78
	ring.outer_radius = 3.0
	_warning_radial.mesh = ring
	_warning_radial.position.y = 0.045
	_warning_radial.material_override = _material(Color(1.0, 0.40, 0.18), true)
	add_child(_warning_radial)
	_warning_line.visible = false
	_warning_arc.visible = false
	_warning_radial.visible = false


func _flat_box(label: String, at: Vector3, size: Vector3, tint: Color, parent: Node3D = null) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.name = label
	piece.position = at
	var box := BoxMesh.new()
	box.size = size
	piece.mesh = box
	var material := _material(tint, true)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.64
	piece.material_override = material
	(parent if parent != null else self).add_child(piece)
	return piece


func _material(tint: Color, glow: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.78
	if glow:
		material.emission_enabled = true
		material.emission = tint
		material.emission_energy_multiplier = 0.95
	return material
