extends MeshInstance3D
class_name SlimeWallImpactMark

# A small world-space residue on a wall. The caller decides whether the hit
# belongs to a static, near-vertical surface; this node has no collision.
const LIFETIME := 1.8
const FADE_START := 0.62
const MAX_MARKS_PER_PARENT := 6
const REUSE_DISTANCE := 0.28
const SURFACE_OFFSET := 0.017
const BLOB_SEGMENTS := 20
const FACE_NORMAL_DOT_MIN := 0.95
const FACE_PLANE_TOLERANCE := 0.035
const CLIP_STEPS := 9
const TRAIL_SHADER := preload("res://assets/shaders/slime_ground_trail.gdshader")

var _surface := ArrayMesh.new()
var _material := ShaderMaterial.new()
var _vertices := PackedVector3Array()
var _base_colors := PackedColorArray()
var _indices := PackedInt32Array()
var _age := 0.0
var _opacity := 1.0
var _last_draw_opacity := -1.0
var _normal := Vector3.FORWARD


static func spawn(parent: Node, hit_position: Vector3, hit_normal: Vector3, tangent_hint: Vector3 = Vector3.ZERO) -> SlimeWallImpactMark:
	if not is_instance_valid(parent) or hit_normal.length_squared() < 0.5:
		return null
	var normal := hit_normal.normalized()
	var nearest: SlimeWallImpactMark
	var nearest_distance := REUSE_DISTANCE
	var marks: Array[SlimeWallImpactMark] = []
	for child in parent.get_children():
		if not child is SlimeWallImpactMark or child.is_queued_for_deletion():
			continue
		var mark := child as SlimeWallImpactMark
		marks.append(mark)
		var distance := mark.global_position.distance_to(hit_position + normal * SURFACE_OFFSET)
		if mark._normal.dot(normal) > 0.93 and distance < nearest_distance:
			nearest = mark
			nearest_distance = distance
	if nearest != null:
		nearest.place(hit_position, normal, tangent_hint)
		return nearest
	if marks.size() >= MAX_MARKS_PER_PARENT:
		var oldest := marks[0]
		for mark in marks:
			if mark._age > oldest._age:
				oldest = mark
		oldest.hide()
		oldest.queue_free()
	var created := SlimeWallImpactMark.new()
	created.name = "WallImpactMark"
	parent.add_child(created)
	created.place(hit_position, normal, tangent_hint)
	return created


static func clear_marks(parent: Node) -> void:
	if not is_instance_valid(parent):
		return
	for child in parent.get_children():
		if child is SlimeWallImpactMark and not child.is_queued_for_deletion():
			child.hide()
			child.queue_free()


func _ready() -> void:
	top_level = true
	mesh = _surface
	_material.shader = TRAIL_SHADER
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_to_group("slime_wall_impact_marks")


func place(hit_position: Vector3, hit_normal: Vector3, tangent_hint: Vector3 = Vector3.ZERO) -> void:
	if hit_normal.length_squared() < 0.5:
		return
	_normal = hit_normal.normalized()
	var right := Vector3.UP.cross(_normal)
	if right.length_squared() < 0.001:
		right = Vector3.FORWARD.cross(_normal)
	right = right.normalized()
	var up := _normal.cross(right).normalized()
	global_transform = Transform3D(Basis(right, up, _normal), hit_position + _normal * SURFACE_OFFSET)
	_age = 0.0
	_opacity = 1.0
	_last_draw_opacity = -1.0
	_build_shape(hit_position, right, up, tangent_hint)
	_clip_to_contact_face(hit_position)
	_draw_shape()
	show()


func get_opacity() -> float:
	return _opacity


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		hide()
		queue_free()
		return
	_opacity = 1.0 - smoothstep(FADE_START, LIFETIME, _age)
	if absf(_opacity - _last_draw_opacity) > 0.015:
		_draw_shape()


func _build_shape(hit_position: Vector3, right: Vector3, up: Vector3, tangent_hint: Vector3) -> void:
	_vertices.clear()
	_base_colors.clear()
	_indices.clear()
	var phase := hit_position.x * 5.37 + hit_position.y * 4.23 + hit_position.z * 6.11
	var tangent := tangent_hint - _normal * tangent_hint.dot(_normal)
	var smear_x := clampf(tangent.dot(right) * 0.022, -0.022, 0.022)
	var smear_y := clampf(tangent.dot(up) * 0.012, -0.012, 0.012)
	# One uneven flattened print and three thin drips. Combined footprint is
	# roughly 0.32 m wide and 0.35 m tall.
	_add_blob(Vector2(smear_x, smear_y), Vector2(0.15, 0.095), phase, 0.46)
	_add_blob(Vector2(-0.083, -0.143), Vector2(0.018, 0.064), phase + 1.1, 0.29)
	_add_blob(Vector2(0.006, -0.161), Vector2(0.022, 0.088), phase + 2.4, 0.34)
	_add_blob(Vector2(0.092, -0.131), Vector2(0.015, 0.051), phase + 4.0, 0.26)


func _add_blob(center: Vector2, radius: Vector2, phase: float, peak_alpha: float) -> void:
	var center_index := _vertices.size()
	_vertices.append(Vector3(center.x, center.y, 0.0))
	_base_colors.append(Color(0.24, 0.82, 0.53, peak_alpha))
	var ring_start := _vertices.size()
	for segment in range(BLOB_SEGMENTS + 1):
		var angle := TAU * float(segment) / float(BLOB_SEGMENTS)
		var roughness := 1.0 + 0.085 * sin(angle * 5.0 + phase) + 0.055 * sin(angle * 8.0 - phase * 0.7)
		var edge := Vector2(cos(angle) * radius.x, sin(angle) * radius.y) * roughness
		_vertices.append(Vector3(center.x + edge.x * 0.79, center.y + edge.y * 0.79, 0.0))
		_base_colors.append(Color(0.24, 0.82, 0.53, peak_alpha * 0.88))
		_vertices.append(Vector3(center.x + edge.x * 1.12, center.y + edge.y * 1.12, 0.0))
		_base_colors.append(Color(0.24, 0.82, 0.53, 0.0))
	for segment in range(BLOB_SEGMENTS):
		var inner := ring_start + segment * 2
		var outer := inner + 1
		var next_inner := inner + 2
		var next_outer := inner + 3
		_indices.append_array(PackedInt32Array([center_index, inner, next_inner]))
		_indices.append_array(PackedInt32Array([inner, outer, next_outer]))
		_indices.append_array(PackedInt32Array([inner, next_outer, next_inner]))


func _clip_to_contact_face(hit_position: Vector3) -> void:
	# Each triangle is clipped to the same physical wall face as the hit.
	# A center-only ray leaves the rim and drips hanging past a corner.
	var supported := PackedByteArray()
	for point in _vertices:
		supported.append(1 if _has_contact_face(point, hit_position) else 0)
	var edge_cache: Dictionary = {}
	var clipped_vertices := PackedVector3Array()
	var clipped_colors := PackedColorArray()
	var clipped_indices := PackedInt32Array()
	for triangle in range(0, _indices.size(), 3):
		var polygon: Array[Dictionary] = []
		for corner in range(3):
			var a := _indices[triangle + corner]
			var b := _indices[triangle + (corner + 1) % 3]
			var a_on_face := supported[a] != 0
			if a_on_face:
				polygon.append({"point": _vertices[a], "color": _base_colors[a]})
			if a_on_face != (supported[b] != 0):
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not edge_cache.has(key):
					edge_cache[key] = _contact_face_edge(a if a_on_face else b, b if a_on_face else a, hit_position)
				polygon.append(edge_cache[key])
		if polygon.size() < 3:
			continue
		var base := clipped_vertices.size()
		for vertex in polygon:
			clipped_vertices.append(vertex["point"])
			clipped_colors.append(vertex["color"])
		for corner in range(1, polygon.size() - 1):
			var a: Vector3 = polygon[0]["point"]
			var b: Vector3 = polygon[corner]["point"]
			var c: Vector3 = polygon[corner + 1]["point"]
			if (b - a).cross(c - a).length_squared() > 0.0000000001:
				clipped_indices.append_array(PackedInt32Array([base, base + corner, base + corner + 1]))
	_vertices = clipped_vertices
	_base_colors = clipped_colors
	_indices = clipped_indices


func _contact_face_edge(inside: int, outside: int, hit_position: Vector3) -> Dictionary:
	var inside_point := _vertices[inside]
	var outside_point := _vertices[outside]
	var on_fraction := 0.0
	var off_fraction := 1.0
	for step in range(CLIP_STEPS):
		var middle := (on_fraction + off_fraction) * 0.5
		if _has_contact_face(inside_point.lerp(outside_point, middle), hit_position):
			on_fraction = middle
		else:
			off_fraction = middle
	return {
		"point": inside_point.lerp(outside_point, on_fraction),
		"color": _base_colors[inside].lerp(_base_colors[outside], on_fraction),
	}


func _has_contact_face(local_point: Vector3, hit_position: Vector3) -> bool:
	var world_point := global_transform * local_point
	var query := PhysicsRayQueryParameters3D.create(
		world_point + _normal * 0.10,
		world_point - _normal * 0.11,
		1
	)
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var face_normal: Vector3 = hit["normal"]
	var face_position: Vector3 = hit["position"]
	return face_normal.dot(_normal) >= FACE_NORMAL_DOT_MIN and absf((face_position - hit_position).dot(_normal)) <= FACE_PLANE_TOLERANCE


func _draw_shape() -> void:
	_surface.clear_surfaces()
	if _indices.is_empty():
		_last_draw_opacity = _opacity
		return
	var colors := _base_colors.duplicate()
	for index in range(colors.size()):
		var color := colors[index]
		color.a *= _opacity
		colors[index] = color
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = _indices
	_surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_last_draw_opacity = _opacity