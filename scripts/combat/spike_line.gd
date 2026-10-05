extends Node3D
class_name SpikeLine

signal hit_target(at: Vector3, empowered: bool)

const SEGMENTS := 5
const STEP := 1.0
const HALF_WIDTH := 0.52
const LIFETIME := 0.38
const PLAYER_VISUAL_LIFETIME := 1.55
const PLAYER_GEL_SHADER := preload("res://assets/shaders/slime_spike_gel.gdshader")

var owner_body: CollisionObject3D
var team: StringName = &"player"
var direction := Vector3.FORWARD
var cast_key := ""
var damage := 22

var _lifetime_left := LIFETIME
var _visual_age := 0.0
var _affected: Dictionary = {}
var _origin := Vector3.ZERO
var _player_centers: Array[Vector3] = []
var _combo_centers: Array[Vector3] = []
var _player_visual: Node3D
var _player_material: ShaderMaterial
var _player_ridges: Array[MeshInstance3D] = []


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
	if _lifetime_left <= 0.0:
		return 0
	if team == &"player":
		_player_centers.clear()
		_combo_centers.clear()
		_player_ridges.clear()
		if is_instance_valid(_player_visual):
			remove_child(_player_visual)
			_player_visual.queue_free()
			_player_visual = null
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
	if team == &"player" and built > 0:
		_build_player_visual()
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
	if team == &"player":
		_combo_centers.append(center)
		return
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
	if team == &"player":
		_player_centers.append(center)
		return
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


func _build_player_visual() -> void:
	_visual_age = 0.0
	_player_visual = Node3D.new()
	_player_visual.name = "PlayerGel"
	add_child(_player_visual)
	_player_material = ShaderMaterial.new()
	_player_material.shader = PLAYER_GEL_SHADER

	var foundation := MeshInstance3D.new()
	foundation.name = "ConnectedSlimeBase"
	foundation.mesh = _make_player_base_mesh()
	foundation.material_override = _player_material
	foundation.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_player_visual.add_child(foundation)

	var side := direction.cross(Vector3.UP).normalized()
	var heights := [0.62, 0.81, 0.78, 1.14, 0.98]
	var sways := [-0.26, 0.22, -0.27, 0.23, -0.25]
	var curls := [0.32, -0.17, 0.39, -0.12, 0.26]
	var side_curls := [-0.10, 0.13, 0.08, -0.14, 0.11]
	for index in _player_centers.size():
		var center: Vector3 = _player_centers[index]
		var sway: float = sways[index]
		_add_player_ridge(center + side * sway, direction, heights[index], 0.39 + float(index % 3) * 0.025, 0.18, curls[index], side_curls[index])
		# Low rounded folds interrupt the repeated tall silhouette.
		_add_player_ridge(center + side * (-(0.54 + float(index % 3) * 0.025) if sway > 0.0 else (0.54 + float(index % 3) * 0.025)) - direction * 0.12, direction.rotated(Vector3.UP, float(index % 3 - 1) * 0.18), 0.18 + float(index % 3) * 0.045, 0.30, 0.13, 0.07, -sway * 0.4)

	# Sticky-hit splashes grow from the same gel base. They have no hit logic.
	for center in _combo_centers:
		_add_player_ridge(center + side * 0.12, direction.rotated(Vector3.UP, 0.48), 0.98, 0.38, 0.20, 0.32, 0.13)
		_add_player_ridge(center - side * 0.20, direction.rotated(Vector3.UP, -0.43), 0.77, 0.34, 0.18, -0.24, -0.11)
		_add_player_ridge(center - direction * 0.18, direction, 0.42, 0.37, 0.23, 0.12, 0.0)

func _make_player_base_mesh() -> ArrayMesh:
	var knots: Array[Vector3] = []
	var knot_widths: Array[float] = []
	knots.append(_player_centers[0] - direction * 0.27)
	knot_widths.append(0.10)
	for index in _player_centers.size():
		var center: Vector3 = _player_centers[index]
		knots.append(center)
		knot_widths.append(0.62)
		if index + 1 < _player_centers.size():
			knots.append((center + _player_centers[index + 1]) * 0.5)
			knot_widths.append(0.28)
	knots.append(_player_centers.back() + direction * 0.27)
	knot_widths.append(0.10)

	# Small, uneven lobes remain connected. Extra rows let unsupported triangles
	# stop at a real ledge rather than bridging across empty space.
	var path: Array[Vector3] = []
	var widths: Array[float] = []
	for knot in knots.size() - 1:
		for subdivision in 2:
			var t := float(subdivision) * 0.5
			path.append(knots[knot].lerp(knots[knot + 1], t))
			widths.append(lerpf(knot_widths[knot], knot_widths[knot + 1], t))
	path.append(knots.back())
	widths.append(knot_widths.back())

	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var supported: Array[bool] = []
	var side := direction.cross(Vector3.UP).normalized()
	var cross_section := [-1.0, -0.55, 0.0, 0.55, 1.0]
	for row in path.size():
		var left_width: float = widths[row] * (0.82 + 0.22 * sin(float(row) * 1.67 + 0.3))
		var right_width: float = widths[row] * (0.82 + 0.21 * sin(float(row) * 1.94 + 1.7))
		var side_shift := side * 0.040 * sin(float(row) * 1.23)
		for column in cross_section.size():
			var lateral: float = cross_section[column]
			var spread: float = left_width if lateral < 0.0 else right_width
			var world_point: Vector3 = path[row] + side_shift + side * lateral * spread
			var ground := _visual_ground_hit(world_point, path[row].y)
			var is_supported := not ground.is_empty()
			supported.append(is_supported)
			if is_supported:
				world_point.y = (ground["position"] as Vector3).y
			var shape := 1.0 - absf(lateral)
			var height := 0.006 + 0.032 * shape * shape + 0.004 * shape * sin(float(row) * 1.31)
			points.append(to_local(world_point) + Vector3.UP * height)
			normals.append((Vector3.UP + side * lateral * 0.28).normalized())
			var base_color := Color(0.055, 0.36, 0.42).lerp(Color(0.16, 0.63, 0.57), shape * 0.75)
			base_color *= 0.94 + 0.055 * sin(float(row) * 1.27 + lateral * 1.8)
			base_color.a = 0.0
			colors.append(base_color)
			uvs.append(Vector2(float(column) / 4.0, float(row) / float(path.size() - 1)))
	for row in path.size() - 1:
		for column in 4:
			var a := row * 5 + column
			var b := a + 5
			if supported[a] and supported[a + 1] and supported[b]:
				indices.append_array(PackedInt32Array([a, a + 1, b]))
			if supported[a + 1] and supported[b + 1] and supported[b]:
				indices.append_array(PackedInt32Array([a + 1, b + 1, b]))
	return _make_mesh(points, normals, colors, uvs, indices)

func _visual_ground_hit(point: Vector3, expected_y: float) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.24, point + Vector3.DOWN * 0.24, 1, [owner_body.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var hit_position: Vector3 = hit["position"]
	var hit_normal: Vector3 = hit["normal"]
	if hit_normal.y < 0.70 or absf(hit_position.y - expected_y) > 0.12:
		return {}
	return hit


func _safe_ridge_scale(center: Vector3, axis: Vector3, length_radius: float, side_radius: float, forward_curl: float, side_curl: float) -> float:
	var side := axis.cross(Vector3.UP).normalized()
	var forward_extent := length_radius + absf(forward_curl) * 0.6
	var side_extent := side_radius + absf(side_curl) * 0.6
	for factor in [1.0, 0.80, 0.60, 0.40, 0.25, 0.12]:
		var offsets: Array[Vector3] = [
			axis * forward_extent * factor,
			-axis * forward_extent * factor,
			side * side_extent * factor,
			-side * side_extent * factor,
		]
		var all_supported := true
		for offset in offsets:
			if _visual_ground_hit(center + offset, center.y).is_empty():
				all_supported = false
				break
		if all_supported:
			return factor
	return 0.10


func _add_player_ridge(center: Vector3, axis: Vector3, height: float, length_radius: float, side_radius: float, forward_curl: float, side_curl: float) -> void:
	var support := _visual_ground_hit(center, center.y)
	if support.is_empty():
		var nearest_distance := INF
		for checked_center in _player_centers:
			var distance := center.distance_squared_to(checked_center)
			if distance < nearest_distance:
				nearest_distance = distance
				center = checked_center
	else:
		center.y = (support["position"] as Vector3).y
	axis = axis.normalized()
	var footprint_scale := _safe_ridge_scale(center, axis, length_radius, side_radius, forward_curl, side_curl)
	var ridge := MeshInstance3D.new()
	ridge.name = "GelCrest"
	ridge.mesh = _make_player_ridge_mesh(axis, height, length_radius * footprint_scale, side_radius * footprint_scale, forward_curl * footprint_scale, side_curl * footprint_scale)
	ridge.material_override = _player_material
	ridge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ridge.position = to_local(center) + Vector3.UP * 0.012
	ridge.scale.y = 0.20
	_player_visual.add_child(ridge)
	_player_ridges.append(ridge)


func _make_player_ridge_mesh(axis: Vector3, height: float, length_radius: float, side_radius: float, forward_curl: float, side_curl: float) -> ArrayMesh:
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var side := axis.cross(Vector3.UP).normalized()
	var levels := [0.0, 0.12, 0.30, 0.49, 0.67, 0.80, 0.90, 0.96, 1.0]
	var radii := [0.86, 1.0, 0.94, 0.82, 0.69, 0.55, 0.38, 0.21, 0.025]
	const SIDES := 14
	for ring in levels.size():
		var t: float = levels[ring]
		var bend := axis * (forward_curl * t * t - 0.035 * sin(t * PI)) + side * (side_curl * t * t + 0.025 * sin(t * TAU + height * 3.0))
		var ring_center := bend + Vector3.UP * height * t
		for sector in SIDES + 1:
			var angle := TAU * float(sector) / float(SIDES)
			var along := cos(angle)
			var across := sin(angle)
			var irregularity := 1.0 + 0.085 * sin(angle * 3.0 + float(ring) * 0.71 + height * 4.0) + 0.035 * cos(angle * 5.0 + float(ring))
			var long_radius: float = length_radius * radii[ring] * irregularity
			var wide_radius: float = side_radius * radii[ring] * (1.0 + 0.075 * cos(angle * 2.0 + float(ring)))
			points.append(ring_center + axis * along * long_radius + side * across * wide_radius)
			normals.append((axis * along / maxf(length_radius, 0.02) + side * across / maxf(side_radius, 0.02) + Vector3.UP * (0.12 + t * t * 1.2)).normalized())
			var shade := 0.04 * sin(angle * 2.0 + height * 5.0 + float(ring) * 0.5)
			colors.append(Color(0.055, 0.38, 0.44).lerp(Color(0.31, 0.82, 0.68), clampf(t * 0.88 + 0.06 + shade, 0.0, 1.0)))
			uvs.append(Vector2(float(sector) / float(SIDES), t))
	for ring in levels.size() - 1:
		for sector in SIDES:
			var lower := ring * (SIDES + 1) + sector
			var upper := lower + SIDES + 1
			indices.append_array(PackedInt32Array([lower, upper, lower + 1, lower + 1, upper, upper + 1]))
	var tip := points.size()
	points.append(axis * forward_curl * 1.04 + side * side_curl * 1.04 + Vector3.UP * (height + 0.004))
	normals.append(Vector3.UP)
	colors.append(Color(0.32, 0.82, 0.68))
	uvs.append(Vector2(0.5, 1.0))
	for sector in SIDES:
		var edge := (levels.size() - 1) * (SIDES + 1) + sector
		indices.append_array(PackedInt32Array([edge, tip, edge + 1]))
	return _make_mesh(points, normals, colors, uvs, indices)

func _make_mesh(points: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, uvs: PackedVector2Array, indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	if not indices.is_empty():
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


func _animate_player_visual() -> void:
	var elapsed := clampf(_visual_age, 0.0, PLAYER_VISUAL_LIFETIME)
	var rise := smoothstep(0.0, 0.11, elapsed)
	var settle := smoothstep(0.94, PLAYER_VISUAL_LIFETIME, elapsed)
	for index in _player_ridges.size():
		var ridge := _player_ridges[index]
		var wobble := 0.06 * sin(elapsed * (27.0 + float(index % 4) * 2.0)) * exp(-elapsed * 10.0)
		ridge.scale = Vector3(1.10 - rise * 0.10, (0.20 + rise * 0.80 + wobble) * (1.0 - settle * 0.90), 1.10 - rise * 0.10)
	_player_material.set_shader_parameter("fade", 1.0 - smoothstep(1.18, PLAYER_VISUAL_LIFETIME, elapsed))

func _physics_process(delta: float) -> void:
	_lifetime_left = maxf(0.0, _lifetime_left - delta)
	if is_instance_valid(_player_visual):
		_visual_age += delta
		_animate_player_visual()
	if _lifetime_left <= 0.0 and (not is_instance_valid(_player_visual) or _visual_age >= PLAYER_VISUAL_LIFETIME):
		queue_free()
