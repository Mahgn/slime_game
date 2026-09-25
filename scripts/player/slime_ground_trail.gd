extends MeshInstance3D
class_name SlimeGroundTrail

# World-space visual owned by one player. No collision or gameplay state.
const SAMPLE_DISTANCE := 0.10
const MAX_SAMPLE_GAP := 0.42
const MAX_HEIGHT_GAP := 0.24
const MIN_SPEED := 0.42
const MAX_LENGTH := 3.25
const LIFETIME := 2.3
const TAIL_FADE := 1.1
const TAPER_LENGTH := 0.72
const WIDTH := 0.83
const GRID_STEP := 0.075
const DRAW_INTERVAL := 1.0 / 30.0
const EDGE_SOFTNESS := 0.075
const CORNER_DOT_LIMIT := 0.995
const SURFACE_OFFSET := 0.045
const SUPPORT_RAY_HEIGHT := 0.22
const SUPPORT_HEIGHT_TOLERANCE := 0.07
const SUPPORT_NORMAL_DOT := 0.90
const MAX_SUPPORT_CACHE_ENTRIES := 4096
const MAX_SAMPLES := 90
const SPLASH_LIFETIME := 1.8
const MAX_SPLASHES := 4
const TRAIL_MATERIAL := preload("res://assets/shaders/slime_ground_trail.gdshader")

var _player: SlimeController
var _surface := ArrayMesh.new()
var _vertices := PackedVector3Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
var _material := ShaderMaterial.new()
var _samples: Array[Dictionary] = []
var _splashes: Array[Dictionary] = []
var _support_cache: Dictionary = {}
var _support_rays_last_draw := 0
var _age := 0.0
var _last_draw_age := -1.0
var _needs_break := true


func setup(player: SlimeController) -> void:
	_player = player


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _surface
	_material.shader = TRAIL_MATERIAL
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _physics_process(delta: float) -> void:
	_age += delta
	while not _samples.is_empty() and _age - float(_samples[0]["time"]) >= LIFETIME:
		_samples.pop_front()
	while not _splashes.is_empty() and _age - float(_splashes[0]["time"]) >= SPLASH_LIFETIME:
		_splashes.pop_front()
	if _samples.is_empty():
		_needs_break = true
	else:
		_mark_first_as_start()

	if is_instance_valid(_player) and _player.is_alive() and _player.is_on_floor():
		var horizontal_speed := Vector2(_player.velocity.x, _player.velocity.z).length()
		# Keep the current strip through brief stops; jumping still starts a new strip.
		if horizontal_speed >= MIN_SPEED:
			_sample_ground()
	else:
		_needs_break = true
	if _age - _last_draw_age >= DRAW_INTERVAL:
		_draw_effect()
		_last_draw_age = _age


func add_landing_splash(impact_speed: float) -> void:
	if impact_speed < 2.5 or not is_instance_valid(_player):
		return
	var hit := _ground_hit()
	if hit.is_empty():
		return
	var point: Vector3 = hit["position"]
	var trailing := Vector3(-_player.velocity.x, 0.0, -_player.velocity.z)
	if trailing.length_squared() < 0.01:
		trailing = _player.global_basis.z
	var shifted_hit := _ground_hit_at(_player.global_position + trailing.normalized() * 0.20)
	if not shifted_hit.is_empty():
		point = shifted_hit["position"]
	_splashes.append({
		"position": point,
		"normal": hit["normal"],
		"time": _age,
		"radius": clampf(0.55 + impact_speed * 0.014, 0.61, 0.72),
		"phase": point.x * 2.3 + point.z * 1.7,
	})
	if _splashes.size() > MAX_SPLASHES:
		_splashes.pop_front()


func _ground_hit() -> Dictionary:
	return _ground_hit_at(_player.global_position)


func _ground_hit_at(origin: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.55, origin + Vector3.DOWN * 0.8, 1, [_player.get_rid()])
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.70:
		return {}
	return hit


func _sample_ground() -> void:
	var hit := _ground_hit()
	if hit.is_empty():
		_needs_break = true
		return
	var point: Vector3 = hit["position"]
	var distance := 0.0
	var travel := 0.0
	if not _samples.is_empty():
		var previous: Vector3 = _samples.back()["position"]
		distance = point.distance_to(previous)
		travel = float(_samples.back()["travel"])
		if not _needs_break and distance < SAMPLE_DISTANCE:
			return
		if distance > MAX_SAMPLE_GAP or absf(point.y - previous.y) > MAX_HEIGHT_GAP:
			_needs_break = true
		if _needs_break:
			travel = 0.0
		else:
			travel += distance
	_samples.append({"position": point, "normal": hit["normal"], "time": _age, "break": _needs_break, "travel": travel})
	_needs_break = false
	_trim_length()


func _trim_length() -> void:
	var length := 0.0
	for index in range(1, _samples.size()):
		if not bool(_samples[index]["break"]):
			length += (_samples[index]["position"] as Vector3).distance_to(_samples[index - 1]["position"] as Vector3)
	while length > MAX_LENGTH and _samples.size() > 1:
		if not bool(_samples[1]["break"]):
			length -= (_samples[1]["position"] as Vector3).distance_to(_samples[0]["position"] as Vector3)
		_samples.pop_front()
		_mark_first_as_start()
	while _samples.size() > MAX_SAMPLES:
		_samples.pop_front()
		_mark_first_as_start()


func _mark_first_as_start() -> void:
	if not _samples.is_empty() and not bool(_samples[0]["break"]):
		var first := _samples[0]
		first["break"] = true
		_samples[0] = first


func _draw_effect() -> void:
	_surface.clear_surfaces()
	_vertices.clear()
	_colors.clear()
	_indices.clear()
	_support_rays_last_draw = 0
	if _support_cache.size() > MAX_SUPPORT_CACHE_ENTRIES or (_samples.is_empty() and _splashes.is_empty()):
		_support_cache.clear()
	var coverage := _build_coverage()
	if coverage.is_empty():
		return
	var cells: Dictionary = {}
	for grid_key in coverage:
		var data: Dictionary = coverage[grid_key]
		if float(data["alpha"]) <= 0.001:
			continue
		var key: Vector2i = grid_key
		for dx in [-1, 0]:
			for dz in [-1, 0]:
				cells[Vector2i(key.x + dx, key.y + dz)] = true
	if cells.is_empty():
		return

	# Give transparent border vertices one shared height so adjacent cells meet.
	for cell_key in cells:
		var cell: Vector2i = cell_key
		var corners: Array[Vector2i] = [cell, cell + Vector2i(1, 0), cell + Vector2i(1, 1), cell + Vector2i(0, 1)]
		var height := 0.0
		var normal := Vector3.ZERO
		var count := 0
		for corner in corners:
			if coverage.has(corner):
				var data: Dictionary = coverage[corner]
				height += float(data["height"])
				normal += data["normal"] as Vector3
				count += 1
		if count == 0:
			continue
		height /= float(count)
		normal = normal.normalized()
		for corner in corners:
			if not coverage.has(corner):
				coverage[corner] = {"alpha": 0.0, "height": height, "normal": normal, "color": Color(0.20, 0.78, 0.50)}


	# Both the crawl strip and landing splash use this mesh. Check the actual
	# floor under every grid corner so neither effect can bridge a platform edge.
	var support: Dictionary = {}
	var vertex_indices: Dictionary = {}
	for cell_key in cells:
		var cell: Vector2i = cell_key
		var corners: Array[Vector2i] = [cell, cell + Vector2i(1, 0), cell + Vector2i(1, 1), cell + Vector2i(0, 1)]
		for corner in corners:
			if not support.has(corner):
				support[corner] = _surface_support(corner, coverage[corner])
		_append_supported_triangle(corners[0], corners[1], corners[2], coverage, support, vertex_indices)
		_append_supported_triangle(corners[0], corners[2], corners[3], coverage, support, vertex_indices)
	if _indices.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _indices
	_surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


# Each world-grid vertex keeps the strongest deposit, so revisits never stack alpha.
func _build_coverage() -> Dictionary:
	var coverage: Dictionary = {}
	var run_head_travel := 0.0
	for index in range(_samples.size() - 1, 0, -1):
		if index == _samples.size() - 1 or bool(_samples[index + 1]["break"]):
			run_head_travel = float(_samples[index]["travel"])
		if bool(_samples[index]["break"]):
			continue
		var start: Dictionary = _samples[index - 1]
		var finish: Dictionary = _samples[index]
		var tail_anchor := maxf(0.0, run_head_travel - MAX_LENGTH)
		_raster_segment(coverage, start, finish, tail_anchor)
		if index >= 2 and not bool(start["break"]):
			var before: Vector3 = _samples[index - 2]["position"]
			var corner: Vector3 = start["position"]
			var after: Vector3 = finish["position"]
			var incoming := Vector2(corner.x - before.x, corner.z - before.z).normalized()
			var outgoing := Vector2(after.x - corner.x, after.z - corner.z).normalized()
			if incoming.length_squared() > 0.001 and outgoing.length_squared() > 0.001 and incoming.dot(outgoing) < CORNER_DOT_LIMIT:
				_raster_corner(coverage, start, tail_anchor, incoming, outgoing)
	for splash in _splashes:
		_raster_splash(coverage, splash)
	return coverage


func _raster_segment(coverage: Dictionary, start: Dictionary, finish: Dictionary, tail_anchor: float) -> void:
	var a: Vector3 = start["position"]
	var b: Vector3 = finish["position"]
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var direction := b2 - a2
	var length_squared := direction.length_squared()
	if length_squared < 0.0001:
		return
	var margin := WIDTH * 0.5 + EDGE_SOFTNESS
	var min_x := floori((minf(a.x, b.x) - margin) / GRID_STEP)
	var max_x := ceili((maxf(a.x, b.x) + margin) / GRID_STEP)
	var min_z := floori((minf(a.z, b.z) - margin) / GRID_STEP)
	var max_z := ceili((maxf(a.z, b.z) + margin) / GRID_STEP)
	var first_normal: Vector3 = start["normal"]
	var last_normal: Vector3 = finish["normal"]
	for gx in range(min_x, max_x + 1):
		for gz in range(min_z, max_z + 1):
			var world := Vector2(float(gx) * GRID_STEP, float(gz) * GRID_STEP)
			var fraction := (world - a2).dot(direction) / length_squared
			if fraction < 0.0 or fraction > 1.0:
				continue
			var nearest := a2 + direction * fraction
			var lateral := world.distance_to(nearest)
			var travel := lerpf(float(start["travel"]), float(finish["travel"]), fraction) - tail_anchor
			var taper := smoothstep(0.0, TAPER_LENGTH, travel)
			var radius := WIDTH * 0.5 * taper * (0.95 + 0.05 * sin(travel * 6.2 + 2.0))
			var edge := 1.0 - smoothstep(maxf(0.0, radius - EDGE_SOFTNESS), radius + EDGE_SOFTNESS, lateral)
			var tip := smoothstep(0.0, 0.24, travel)
			var stamp_time := lerpf(float(start["time"]), float(finish["time"]), fraction)
			var fade := clampf((LIFETIME - (_age - stamp_time)) / TAIL_FADE, 0.0, 1.0)
			var alpha := 0.43 * edge * tip * fade
			if alpha <= 0.001:
				continue
			var normal := first_normal.lerp(last_normal, fraction).normalized()
			var nearest3 := a.lerp(b, fraction)
			var height := nearest3.y - (normal.x * (world.x - nearest3.x) + normal.z * (world.y - nearest3.z)) / normal.y
			_offer_coverage(coverage, Vector2i(gx, gz), alpha, height, normal, Color(0.24, 0.82, 0.53))


func _raster_corner(coverage: Dictionary, sample: Dictionary, tail_anchor: float, incoming: Vector2, outgoing: Vector2) -> void:
	var center: Vector3 = sample["position"]
	var normal: Vector3 = sample["normal"]
	var travel := float(sample["travel"]) - tail_anchor
	var taper := smoothstep(0.0, TAPER_LENGTH, travel)
	var radius := WIDTH * 0.5 * taper * (0.95 + 0.05 * sin(travel * 6.2 + 2.0))
	var tip := smoothstep(0.0, 0.24, travel)
	var fade := clampf((LIFETIME - (_age - float(sample["time"]))) / TAIL_FADE, 0.0, 1.0)
	if radius <= 0.001 or fade <= 0.001 or tip <= 0.001:
		return
	var margin := radius + EDGE_SOFTNESS
	var min_x := floori((center.x - margin) / GRID_STEP)
	var max_x := ceili((center.x + margin) / GRID_STEP)
	var min_z := floori((center.z - margin) / GRID_STEP)
	var max_z := ceili((center.z + margin) / GRID_STEP)
	for gx in range(min_x, max_x + 1):
		for gz in range(min_z, max_z + 1):
			var world := Vector2(float(gx) * GRID_STEP, float(gz) * GRID_STEP)
			var offset := world - Vector2(center.x, center.z)
			if offset.dot(incoming) <= 0.0 or offset.dot(outgoing) >= 0.0:
				continue
			var lateral := offset.length()
			var edge := 1.0 - smoothstep(maxf(0.0, radius - EDGE_SOFTNESS), radius + EDGE_SOFTNESS, lateral)
			var alpha := 0.43 * edge * tip * fade
			if alpha <= 0.001:
				continue
			var height := center.y - (normal.x * (world.x - center.x) + normal.z * (world.y - center.z)) / normal.y
			_offer_coverage(coverage, Vector2i(gx, gz), alpha, height, normal, Color(0.24, 0.82, 0.53))

func _raster_splash(coverage: Dictionary, splash: Dictionary) -> void:
	var elapsed := _age - float(splash["time"])
	var growth := 0.68 + 0.32 * smoothstep(0.0, 0.12, elapsed)
	var opacity := 1.0 - smoothstep(0.48, SPLASH_LIFETIME, elapsed)
	if opacity <= 0.001:
		return
	var center: Vector3 = splash["position"]
	var normal: Vector3 = splash["normal"]
	var radius := float(splash["radius"]) * growth
	var phase := float(splash["phase"])
	_raster_blob(coverage, center, normal, radius, phase, opacity, 0.48)
	var axis_x := normal.cross(Vector3.FORWARD).normalized()
	var axis_z := axis_x.cross(normal).normalized()
	for droplet in range(4):
		var angle := phase + float(droplet) * TAU / 4.0
		var offset := axis_x * cos(angle) + axis_z * sin(angle)
		var drop_center := center + offset * (radius * (1.12 + 0.10 * sin(phase + float(droplet))))
		_raster_blob(coverage, drop_center, normal, radius * (0.14 + 0.025 * float(droplet)), phase + float(droplet), opacity, 0.31)


func _raster_blob(coverage: Dictionary, center: Vector3, normal: Vector3, radius: float, phase: float, opacity: float, base_alpha: float) -> void:
	var margin := radius * 1.12 + EDGE_SOFTNESS
	var min_x := floori((center.x - margin) / GRID_STEP)
	var max_x := ceili((center.x + margin) / GRID_STEP)
	var min_z := floori((center.z - margin) / GRID_STEP)
	var max_z := ceili((center.z + margin) / GRID_STEP)
	var axis_x := normal.cross(Vector3.FORWARD).normalized()
	var axis_z := axis_x.cross(normal).normalized()
	for gx in range(min_x, max_x + 1):
		for gz in range(min_z, max_z + 1):
			var world := Vector2(float(gx) * GRID_STEP, float(gz) * GRID_STEP)
			var delta := Vector3(world.x - center.x, 0.0, world.y - center.z)
			var local := Vector2(delta.dot(axis_x), delta.dot(axis_z))
			var distance := local.length()
			var angle := atan2(local.y, local.x)
			var lobed_radius := radius * (0.86 + 0.10 * sin(angle * 5.0 + phase) + 0.07 * sin(angle * 8.0 - phase * 0.7))
			var edge := 1.0 - smoothstep(lobed_radius - EDGE_SOFTNESS, lobed_radius + EDGE_SOFTNESS, distance)
			var alpha := base_alpha * opacity * edge
			if alpha <= 0.001:
				continue
			var height := center.y - (normal.x * (world.x - center.x) + normal.z * (world.y - center.z)) / normal.y
			var middle := clampf(1.0 - distance / maxf(radius, 0.001), 0.0, 1.0)
			var color := Color(0.21 + 0.03 * middle, 0.80 + 0.06 * middle, 0.52 + 0.05 * middle)
			_offer_coverage(coverage, Vector2i(gx, gz), alpha, height, normal, color)


func _offer_coverage(coverage: Dictionary, key: Vector2i, alpha: float, height: float, normal: Vector3, color: Color) -> void:
	var previous: Dictionary = coverage.get(key, {})
	if not previous.is_empty() and float(previous["alpha"]) >= alpha:
		return
	coverage[key] = {"alpha": alpha, "height": height, "normal": normal, "color": color}


func _surface_support(key: Vector2i, data: Dictionary) -> Dictionary:
	var expected_height := float(data["height"])
	var expected_normal: Vector3 = data["normal"]
	var cache_key := Vector3i(key.x, roundi(expected_height / 0.12), key.y)
	var cached: Dictionary = _support_cache.get(cache_key, {})
	if not cached.is_empty() and absf(float(cached["expected_height"]) - expected_height) <= SUPPORT_HEIGHT_TOLERANCE and (cached["expected_normal"] as Vector3).dot(expected_normal) >= SUPPORT_NORMAL_DOT:
		return cached
	var result := {"supported": false, "height": expected_height, "normal": expected_normal, "expected_height": expected_height, "expected_normal": expected_normal}
	if not is_instance_valid(_player):
		return result
	var world := Vector3(float(key.x) * GRID_STEP, expected_height, float(key.y) * GRID_STEP)
	var query := PhysicsRayQueryParameters3D.create(world + Vector3.UP * SUPPORT_RAY_HEIGHT, world + Vector3.DOWN * SUPPORT_RAY_HEIGHT, 1, [_player.get_rid()])
	_support_rays_last_draw += 1
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var hit_position: Vector3 = hit["position"]
		var hit_normal: Vector3 = hit["normal"]
		if hit_normal.y >= 0.70 and absf(hit_position.y - expected_height) <= SUPPORT_HEIGHT_TOLERANCE and hit_normal.dot(expected_normal) >= SUPPORT_NORMAL_DOT:
			result["supported"] = true
			result["height"] = hit_position.y
			result["normal"] = hit_normal
	_support_cache[cache_key] = result
	return result


func _append_supported_triangle(a: Vector2i, b: Vector2i, c: Vector2i, coverage: Dictionary, support: Dictionary, vertex_indices: Dictionary) -> void:
	var a_support: Dictionary = support[a]
	var b_support: Dictionary = support[b]
	var c_support: Dictionary = support[c]
	if not bool(a_support["supported"]) or not bool(b_support["supported"]) or not bool(c_support["supported"]):
		return
	var a_data: Dictionary = coverage[a]
	var b_data: Dictionary = coverage[b]
	var c_data: Dictionary = coverage[c]
	if maxf(float(a_data["alpha"]), maxf(float(b_data["alpha"]), float(c_data["alpha"]))) <= 0.001:
		return
	_indices.append(_coverage_vertex_index(a, coverage, support, vertex_indices))
	_indices.append(_coverage_vertex_index(b, coverage, support, vertex_indices))
	_indices.append(_coverage_vertex_index(c, coverage, support, vertex_indices))


func _coverage_vertex_index(key: Vector2i, coverage: Dictionary, support: Dictionary, vertex_indices: Dictionary) -> int:
	if vertex_indices.has(key):
		return int(vertex_indices[key])
	var data: Dictionary = coverage[key]
	var floor: Dictionary = support[key]
	var point := Vector3(float(key.x) * GRID_STEP, float(floor["height"]), float(key.y) * GRID_STEP)
	point += (floor["normal"] as Vector3) * SURFACE_OFFSET
	var color: Color = data["color"]
	color.a = float(data["alpha"])
	var index := _vertices.size()
	_vertices.append(point)
	_colors.append(color)
	vertex_indices[key] = index
	return index