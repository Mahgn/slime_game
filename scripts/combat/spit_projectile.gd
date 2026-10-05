extends Node3D
class_name SpitProjectile

signal resolved(hit_position: Vector3, damaged_target: bool)

const PLAYER_GEL_SHADER := preload("res://assets/shaders/slime_spit_gel.gdshader")

class SpitSplash:
	extends MeshInstance3D

	var gel_material: StandardMaterial3D
	var age := 0.0
	const DURATION := 0.42

	func _process(delta: float) -> void:
		age += delta
		var progress := clampf(age / DURATION, 0.0, 1.0)
		var color := gel_material.albedo_color
		color.a = 0.78 * pow(1.0 - progress, 1.4)
		gel_material.albedo_color = color
		var growth := lerpf(0.62, 1.05, smoothstep(0.0, 1.0, progress))
		scale = Vector3.ONE * growth
		if progress >= 1.0:
			queue_free()


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
var _gel_material: ShaderMaterial
var _droplets: Array[MeshInstance3D] = []
var _visual_age := 0.0


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
	_gel_material = ShaderMaterial.new()
	_gel_material.shader = PLAYER_GEL_SHADER
	var blob_mesh := _make_player_blob_mesh()
	var body := MeshInstance3D.new()
	body.name = "Gel"
	body.mesh = blob_mesh
	body.material_override = _gel_material
	visual.add_child(body)
	for i in 2:
		var drop := MeshInstance3D.new()
		drop.name = "TailDroplet%d" % i
		drop.mesh = blob_mesh
		drop.material_override = _gel_material
		drop.scale = Vector3.ONE * (0.27 if i == 0 else 0.16)
		visual.add_child(drop)
		_droplets.append(drop)
	_update_droplets()


func _make_player_blob_mesh() -> ArrayMesh:
	var depths := PackedFloat32Array([-0.32, -0.285, -0.235, -0.16, -0.06, 0.05, 0.16, 0.28, 0.40, 0.52, 0.64, 0.72])
	var radii := PackedFloat32Array([0.012, 0.085, 0.147, 0.190, 0.205, 0.188, 0.153, 0.111, 0.069, 0.037, 0.019, 0.006])
	const SEGMENTS := 20
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for ring in depths.size():
		var before := maxi(ring - 1, 0)
		var after := mini(ring + 1, depths.size() - 1)
		var slope := (radii[after] - radii[before]) / maxf(depths[after] - depths[before], 0.001)
		for segment in SEGMENTS:
			var angle := TAU * float(segment) / float(SEGMENTS)
			var wave := 1.0 + 0.055 * sin(3.0 * angle + depths[ring] * 9.0) + 0.025 * sin(5.0 * angle - depths[ring] * 13.0)
			var radial := radii[ring] * wave
			vertices.append(Vector3(cos(angle) * radial, sin(angle) * radial * 0.92, depths[ring]))
			normals.append(Vector3(cos(angle), sin(angle), -slope).normalized())
		if ring == 0:
			continue
		var previous := (ring - 1) * SEGMENTS
		var current := ring * SEGMENTS
		for segment in SEGMENTS:
			var next_segment := (segment + 1) % SEGMENTS
			indices.append_array(PackedInt32Array([
				previous + segment, previous + next_segment, current + segment,
				previous + next_segment, current + next_segment, current + segment
			]))
	var front_center := vertices.size()
	vertices.append(Vector3(0.0, 0.0, depths[0]))
	normals.append(Vector3.FORWARD)
	var rear_center := vertices.size()
	vertices.append(Vector3(0.0, 0.0, depths[depths.size() - 1]))
	normals.append(Vector3.BACK)
	var last_ring := (depths.size() - 1) * SEGMENTS
	for segment in SEGMENTS:
		var next_segment := (segment + 1) % SEGMENTS
		indices.append_array(PackedInt32Array([front_center, next_segment, segment]))
		indices.append_array(PackedInt32Array([rear_center, last_ring + segment, last_ring + next_segment]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _update_droplets() -> void:
	for i in _droplets.size():
		var drift := sin(_visual_age * 12.0 - float(i) * 2.2)
		_droplets[i].position = Vector3(
			(0.055 if i == 0 else -0.085) + drift * 0.019,
			(0.013 if i == 0 else -0.025) + cos(_visual_age * 10.0 + float(i)) * 0.011,
			0.73 + float(i) * 0.23
		)
		_droplets[i].rotation.z = drift * 0.14


func _process(delta: float) -> void:
	if _gel_material == null:
		return
	_visual_age += delta
	_gel_material.set_shader_parameter("flow_time", _visual_age)
	_update_droplets()


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


func _spawn_player_splash(hit: Dictionary) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var surface_normal: Vector3 = hit.get("normal", Vector3.UP)
	if surface_normal.length_squared() < 0.5:
		surface_normal = -direction
	surface_normal = surface_normal.normalized()
	var splash := SpitSplash.new()
	splash.name = "SlimeSpitSplash"
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.23, 0.79, 0.65, 0.78)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.21
	material.metallic = 0.0
	material.emission_enabled = true
	material.emission = Color(0.09, 0.35, 0.30)
	material.emission_energy_multiplier = 0.10
	splash.material_override = material
	splash.gel_material = material
	parent.add_child(splash)
	splash.global_position = global_position + surface_normal * 0.026
	var up := Vector3.UP if absf(surface_normal.dot(Vector3.UP)) < 0.95 else Vector3.BACK
	splash.look_at(splash.global_position - surface_normal, up)
	splash.mesh = _make_splash_mesh(splash, hit, surface_normal)


func _make_splash_mesh(splash: Node3D, hit: Dictionary, surface_normal: Vector3) -> ArrayMesh:
	const SEGMENTS := 20
	var vertices := PackedVector3Array([Vector3(0.0, 0.0, 0.035)])
	var normals := PackedVector3Array([Vector3.BACK])
	var indices := PackedInt32Array()
	var outline := PackedFloat32Array()
	var max_radius := 0.28 if hit["collider"] is StaticBody3D else 0.20
	var collider: Object = hit["collider"]
	var space := get_world_3d().direct_space_state
	for segment in SEGMENTS:
		var angle := TAU * float(segment) / float(SEGMENTS)
		var lobe := 1.0 + 0.17 * sin(angle * 5.0 + 0.6) + 0.11 * sin(angle * 8.0 - 0.9)
		var supported_radius := 0.0
		for step in 6:
			var radius := max_radius * lobe * float(6 - step) / 6.0
			var sample := splash.to_global(Vector3(cos(angle) * radius, sin(angle) * radius * 0.82, 0.0))
			var probe := PhysicsRayQueryParameters3D.create(sample + surface_normal * 0.10, sample - surface_normal * 0.18, 1 | 4)
			var support := space.intersect_ray(probe)
			if not support.is_empty() and support["collider"] == collider:
				var support_normal: Vector3 = support["normal"]
				if support_normal.dot(surface_normal) > 0.78:
					supported_radius = radius
					break
		outline.append(supported_radius)
	for ring in 2:
		for segment in SEGMENTS:
			var angle := TAU * float(segment) / float(SEGMENTS)
			var radius := outline[segment] * (0.48 if ring == 0 else 1.0)
			vertices.append(Vector3(cos(angle) * radius, sin(angle) * radius * 0.82, 0.023 if ring == 0 else 0.0))
			normals.append(Vector3(cos(angle) * (0.23 if ring == 0 else 0.0), sin(angle) * (0.23 if ring == 0 else 0.0), 1.0).normalized())
	for segment in SEGMENTS:
		var next_segment := (segment + 1) % SEGMENTS
		var inner := 1 + segment
		var inner_next := 1 + next_segment
		var outer := 1 + SEGMENTS + segment
		var outer_next := 1 + SEGMENTS + next_segment
		indices.append_array(PackedInt32Array([0, inner, inner_next, inner, outer, outer_next, inner, outer_next, inner_next]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


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
		if team == &"player":
			_spawn_player_splash(hit)
		var damaged := false
		var target: Object = hit["collider"]
		if is_instance_valid(target) and target.has_method("receive_hit"):
			if target is SlimeController:
				damaged = (target as SlimeController).receive_hit(damage, cast_key, team, direction)
			else:
				damaged = target.call("receive_hit", damage, cast_key, team)
			if damaged and team == &"player" and target.has_method("apply_sticky"):
				if target.has_method("set_sticky_impact"):
					target.call("set_sticky_impact", hit["position"], hit["normal"])
				target.call("apply_sticky", slow_factor, slow_seconds)
		resolved.emit(global_position, damaged)
		queue_free()
		return
	global_position = next_position
	_travelled += distance
	if _travelled >= max_range - 0.001:
		queue_free()
