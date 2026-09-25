extends Node3D
class_name SpikeLine

signal hit_target(at: Vector3, empowered: bool)

const SEGMENTS := 5
const STEP := 1.0
const HALF_WIDTH := 0.52
const LIFETIME := 0.38

var owner_body: CollisionObject3D
var team: StringName = &"player"
var direction := Vector3.FORWARD
var cast_key := ""
var damage := 22

var _lifetime_left := LIFETIME
var _affected: Dictionary = {}
var _origin := Vector3.ZERO


func configure(new_owner: CollisionObject3D, new_team: StringName, new_origin: Vector3, new_direction: Vector3, new_cast_key: String, new_damage: int) -> void:
	owner_body = new_owner
	team = new_team
	_origin = new_origin
	direction = Vector3(new_direction.x, 0.0, new_direction.z).normalized()
	cast_key = new_cast_key
	damage = new_damage


func _ready() -> void:
	global_position = _origin
	add_to_group(&"temporary_effects")
	if team == &"enemy":
		add_to_group(&"enemy_attacks")
	if not is_instance_valid(owner_body) or direction.length_squared() < 0.9 or cast_key.is_empty():
		queue_free()
		return
	build_line()


func build_line() -> int:
	var base_height := global_position.y
	var previous := global_position
	var built := 0
	for index in SEGMENTS:
		var candidate := global_position + direction * (float(index) + 1.0) * STEP
		var wall_query := PhysicsRayQueryParameters3D.create(previous + Vector3.UP * 0.34, candidate + Vector3.UP * 0.34, 1)
		wall_query.exclude = [owner_body.get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(wall_query).is_empty():
			break
		var ground_query := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 0.8, candidate + Vector3.DOWN * 1.0, 1)
		ground_query.exclude = [owner_body.get_rid()]
		var ground := get_world_3d().direct_space_state.intersect_ray(ground_query)
		if ground.is_empty() or absf(float(ground["position"].y) - base_height) > 0.35 or ground["normal"].y < 0.7:
			break
		var center: Vector3 = ground["position"]
		_add_segment(center, index)
		_hit_targets(center)
		previous = center
		built += 1
	return built


func _hit_targets(center: Vector3) -> void:
	var group: StringName = &"enemies" if team == &"player" else &"player"
	for target_node: Node in get_tree().get_nodes_in_group(group) + (get_tree().get_nodes_in_group(&"training_targets") if team == &"player" else []):
		if not is_instance_valid(target_node) or not target_node is Node3D or not target_node.has_method("receive_hit"):
			continue
		var target := target_node as Node3D
		if target == owner_body or _affected.has(target.get_instance_id()):
			continue
		var offset := target.global_position - center
		offset.y = 0.0
		if absf(offset.dot(direction)) > HALF_WIDTH + 0.40 or absf(offset.dot(direction.cross(Vector3.UP))) > HALF_WIDTH + 0.40:
			continue
		if team == &"enemy" and target.global_position.y - center.y > 0.45:
			continue
		var ray := PhysicsRayQueryParameters3D.create(center + Vector3.UP * 0.25, target.global_position + Vector3.UP * 0.25, 1)
		ray.exclude = [owner_body.get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		var sticky := team == &"player" and target.has_method("get_sticky_time_left") and float(target.call("get_sticky_time_left")) > 0.0
		var hit_damage := 33 if sticky else damage
		var did_hit := (target as SlimeController).receive_hit(hit_damage, cast_key, team, (target.global_position - _origin).normalized()) if target is SlimeController else bool(target.call("receive_hit", hit_damage, cast_key, team))
		if did_hit:
			_affected[target.get_instance_id()] = true
			if sticky and is_instance_valid(target) and target.has_method("clear_sticky"):
				target.call("clear_sticky")
			if sticky:
				_add_combo_splash(center)
			hit_target.emit(center, sticky)


func _add_combo_splash(center: Vector3) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.72, 1.0, 0.92)
	material.emission_enabled = true
	material.emission = Color(0.34, 0.94, 0.78)
	material.emission_energy_multiplier = 1.6
	for side in [-0.48, 0.0, 0.48]:
		var splash := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.16
		cone.height = 1.1 if side == 0.0 else 0.75
		splash.mesh = cone
		splash.position = to_local(center + direction.cross(Vector3.UP) * side + Vector3.UP * cone.height * 0.5)
		splash.material_override = material
		add_child(splash)


func _add_segment(center: Vector3, index: int) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.23, 0.88, 0.68) if team == &"player" else Color(0.92, 0.52, 0.26)
	material.emission_enabled = true
	material.emission = material.albedo_color * 0.55
	for side in [-0.29, 0.0, 0.29]:
		var spike := MeshInstance3D.new()
		var shape := CylinderMesh.new()
		shape.top_radius = 0.0
		shape.bottom_radius = 0.16 if side != 0.0 else 0.23
		shape.height = 0.42 if side != 0.0 else 0.66
		spike.mesh = shape
		spike.material_override = material
		spike.position = to_local(center + direction.cross(Vector3.UP) * side + Vector3.UP * shape.height * 0.5)
		spike.rotation.y = float(index) * 0.27
		add_child(spike)


func _physics_process(delta: float) -> void:
	_lifetime_left -= delta
	if _lifetime_left <= 0.0:
		queue_free()
