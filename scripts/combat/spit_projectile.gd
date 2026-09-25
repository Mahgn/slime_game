extends Node3D
class_name SpitProjectile

signal resolved(hit_position: Vector3, damaged_target: bool)

var owner_body: CollisionObject3D
var team: StringName
var direction := Vector3.FORWARD
var speed := 0.0
var damage := 0
var max_range := 18.0
var slow_factor := 1.0
var slow_seconds := 0.0
var cast_key := ""

var _travelled := 0.0


func configure(
	new_owner: CollisionObject3D,
	new_team: StringName,
	new_direction: Vector3,
	new_speed: float,
	new_damage: int,
	new_range: float,
	new_cast_key: String,
	new_slow_factor: float = 1.0,
	new_slow_seconds: float = 0.0
) -> void:
	owner_body = new_owner
	team = new_team
	direction = new_direction.normalized()
	speed = new_speed
	damage = new_damage
	max_range = new_range
	cast_key = new_cast_key
	slow_factor = new_slow_factor
	slow_seconds = new_slow_seconds


func _ready() -> void:
	add_to_group(&"projectiles")
	if team == &"enemy":
		add_to_group(&"enemy_projectiles")
	var visual := Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	var forward := direction if direction.length_squared() > 0.001 else Vector3.FORWARD
	var up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.95 else Vector3.BACK
	visual.look_at(visual.global_position + forward, up)
	if team == &"player":
		_create_player_visual(visual)
	else:
		_create_enemy_visual(visual)


func _create_player_visual(visual: Node3D) -> void:
	var core := _glow_material(Color(0.24, 0.95, 0.85), 1.1)
	var mist := _glow_material(Color(0.08, 0.72, 0.66), 0.7, 0.28)
	var droplets := _glow_material(Color(0.52, 1.0, 0.89), 0.9)
	_add_sphere(visual, "Mist", 0.23, Vector3.ZERO, mist)
	_add_sphere(visual, "Core", 0.145, Vector3.ZERO, core)
	_add_sphere(visual, "DropletNear", 0.095, Vector3(0.06, 0.02, 0.29), droplets)
	_add_sphere(visual, "DropletMid", 0.065, Vector3(-0.05, -0.015, 0.48), core)
	_add_sphere(visual, "DropletFar", 0.04, Vector3(0.01, 0.015, 0.64), droplets)
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.17
	ring.outer_radius = 0.22
	ring.ring_segments = 8
	ring.rings = 24
	rim.mesh = ring
	rim.rotation.x = PI / 2.0
	rim.material_override = droplets
	visual.add_child(rim)


func _create_enemy_visual(visual: Node3D) -> void:
	var core := _glow_material(Color(1.0, 0.42, 0.12), 1.2)
	var glow := _glow_material(Color(1.0, 0.27, 0.06), 0.8, 0.32)
	var trail := _glow_material(Color(1.0, 0.6, 0.12), 0.9)
	_add_sphere(visual, "Glow", 0.23, Vector3.ZERO, glow)
	_add_sphere(visual, "Core", 0.15, Vector3.ZERO, core)
	var streak := MeshInstance3D.new()
	streak.name = "Streak"
	var streak_mesh := CapsuleMesh.new()
	streak_mesh.radius = 0.075
	streak_mesh.height = 0.58
	streak.mesh = streak_mesh
	streak.position.z = 0.27
	streak.rotation.x = PI / 2.0
	streak.material_override = trail
	visual.add_child(streak)
	_add_sphere(visual, "TailGlow", 0.12, Vector3(0, 0, 0.55), glow)


func _glow_material(color: Color, energy: float, alpha: float = 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


func _add_sphere(visual: Node3D, mesh_name: String, radius: float, offset: Vector3, material: Material) -> void:
	var part := MeshInstance3D.new()
	part.name = mesh_name
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	part.mesh = sphere
	part.position = offset
	part.material_override = material
	visual.add_child(part)


func _physics_process(delta: float) -> void:
	if direction.length_squared() < 0.9:
		queue_free()
		return
	var distance := minf(speed * delta, max_range - _travelled)
	if distance <= 0.0:
		queue_free()
		return
	var next_position := global_position + direction * distance
	var mask := 1 | (4 if team == &"player" else 2)
	var query := PhysicsRayQueryParameters3D.create(global_position, next_position, mask)
	query.hit_from_inside = true
	if is_instance_valid(owner_body):
		query.exclude = [owner_body.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit["position"]
		var damaged := false
		var target: Object = hit["collider"]
		if is_instance_valid(target) and target.has_method("receive_hit"):
			if target is SlimeController:
				damaged = (target as SlimeController).receive_hit(damage, cast_key, team, direction)
			else:
				damaged = target.call("receive_hit", damage, cast_key, team)
			if damaged and team == &"player" and target.has_method("apply_sticky"):
				target.call("apply_sticky", slow_factor, slow_seconds)
		resolved.emit(global_position, damaged)
		queue_free()
		return
	global_position = next_position
	_travelled += distance
	if _travelled >= max_range - 0.001:
		queue_free()
