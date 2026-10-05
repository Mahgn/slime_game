extends MeshInstance3D
class_name SlimeStickyMark

const SEGMENTS := 24


func _ready() -> void:
	var gel := StandardMaterial3D.new()
	gel.albedo_color = Color.WHITE
	gel.roughness = 0.26
	gel.emission_enabled = true
	gel.emission = Color(0.23, 0.79, 0.65)
	gel.emission_energy_multiplier = 1.1
	gel.metallic = 0.0
	gel.vertex_color_use_as_albedo = true
	gel.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = gel
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


func place_on_hit(hit_point: Vector3, hit_normal: Vector3, collider: CollisionObject3D, curved: bool = false) -> void:
	if not is_instance_valid(collider):
		return
	var normal := hit_normal.normalized()
	if normal.length_squared() < 0.5:
		normal = Vector3.BACK
	global_position = hit_point + normal * (0.045 if curved else 0.007)
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.BACK
	look_at(global_position - normal, up)
	mesh = _build_mesh(collider, normal, curved)


func _build_mesh(collider: CollisionObject3D, normal: Vector3, curved: bool) -> ArrayMesh:
	var max_radius := 0.25 if curved else 0.22
	var outline := PackedFloat32Array()
	var space := get_world_3d().direct_space_state
	for segment in SEGMENTS:
		var angle := TAU * float(segment) / float(SEGMENTS)
		var lobe := 1.0 + 0.12 * sin(angle * 3.0 + 0.45) + 0.07 * sin(angle * 7.0 - 0.9)
		var supported := 0.0
		for step in 8:
			var radius := max_radius * lobe * float(8 - step) / 8.0
			var sample := to_global(_edge_point(angle, radius, 0.0))
			var ray := PhysicsRayQueryParameters3D.create(sample + normal * 0.12, sample - normal * 0.18, 4)
			var found := space.intersect_ray(ray)
			if not found.is_empty() and found["collider"] == collider:
				var found_normal: Vector3 = found["normal"]
				if found_normal.dot(normal) > 0.75:
					supported = radius
					break
		outline.append(supported)
	var vertices := PackedVector3Array([Vector3(0.0, 0.0, 0.034)])
	var normals := PackedVector3Array([Vector3.BACK])
	var colors := PackedColorArray([Color(0.40, 0.95, 0.80)])
	var indices := PackedInt32Array()
	for ring in 3:
		for segment in SEGMENTS:
			var angle := TAU * float(segment) / float(SEGMENTS)
			var ring_ratio: float = 0.36 if ring == 0 else (0.77 if ring == 1 else 1.0)
			var radius: float = outline[segment] * ring_ratio
			var height: float = 0.026 if ring == 0 else (0.012 if ring == 1 else (-0.018 if curved else 0.001))
			vertices.append(_edge_point(angle, radius, height))
			normals.append(Vector3(cos(angle) * 0.15, sin(angle) * 0.15, 1.0).normalized())
			var ring_color := Color(0.35, 0.91, 0.76) if ring == 0 else (Color(0.28, 0.85, 0.70) if ring == 1 else Color(0.19, 0.68, 0.58))
			colors.append(ring_color)
	for segment in SEGMENTS:
		var next_segment := (segment + 1) % SEGMENTS
		indices.append_array(PackedInt32Array([0, 1 + segment, 1 + next_segment]))
		for ring in 2:
			var inner := 1 + ring * SEGMENTS + segment
			var inner_next := 1 + ring * SEGMENTS + next_segment
			var outer := inner + SEGMENTS
			var outer_next := inner_next + SEGMENTS
			indices.append_array(PackedInt32Array([inner, outer, inner_next, inner_next, outer, outer_next]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return built


func _edge_point(angle: float, radius: float, height: float) -> Vector3:
	var down := pow(maxf(0.0, -sin(angle)), 8.0)
	return Vector3(cos(angle) * radius, sin(angle) * radius - radius * down * 0.16, height)
