extends Node
class_name SlimeKeepersWorldNavigation

# Small authored graph for this world only. Geometry remains the authority:
# links need capsule-width clearance, a walkable floor and continuous support.
const LINK_RANGE := 12.0
const GRAPH_CLEARANCE := 0.88
const FLOOR_SAMPLE_STEP := 0.5
const PATH_REFRESH_SECONDS := 0.3

var build_stats: Dictionary = {}
var _world: World3D
var _graph := AStar3D.new()
var _points: Array[Vector3] = []
var _paths: Dictionary = {}
var _clock := 0.0


func _physics_process(delta: float) -> void:
	_clock += delta


func build(rooms: Dictionary, connections: Array, world: World3D) -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_world = world
	_graph.clear()
	_points.clear()
	_paths.clear()
	for room: Dictionary in rooms.values():
		for key: String in ["spawn", "enemy_spawns", "walk_points"]:
			_collect(room.get(key))
		_collect_paths(room.get("port_paths", {}))
		var ports: Dictionary = room.get("ports", {})
		for port: Dictionary in ports.values():
			_collect(port.get("position"))
	for connection: Dictionary in connections:
		_collect_paths(connection.get("path"))
	for index in _points.size():
		_graph.add_point(index, _points[index])
	var edges := 0
	for first in _points.size():
		for second in range(first + 1, _points.size()):
			if _points[first].distance_to(_points[second]) <= LINK_RANGE and can_travel(_points[first], _points[second], GRAPH_CLEARANCE):
				_graph.connect_points(first, second)
				edges += 1
	var isolated: Array[Vector3] = []
	for index in _points.size():
		if _graph.get_point_connections(index).is_empty():
			isolated.append(_points[index])
	build_stats = {"points": _points.size(), "edges": edges, "isolated_points": isolated, "graph_clearance": GRAPH_CLEARANCE}
	print("KEEPERS_NAV points=%d edges=%d isolated=%d" % [_points.size(), edges, isolated.size()])


func _collect(value: Variant) -> void:
	if value is Vector3:
		var point: Vector3 = value
		for existing: Vector3 in _points:
			if existing.distance_squared_to(point) < 0.01:
				return
		_points.append(point)
	elif value is Array or value is PackedVector3Array:
		for item: Variant in value:
			_collect(item)
	elif value is Dictionary:
		for item: Variant in value.values():
			_collect(item)


func _collect_paths(value: Variant) -> void:
	if value is Dictionary:
		for path: Variant in value.values():
			_collect_paths(path)
	elif value is Array or value is PackedVector3Array:
		_collect(value)
		for index in range(1, value.size()):
			var a: Vector3 = value[index - 1]
			var b: Vector3 = value[index]
			# Long straight corridors may have only their authored corners.
			# Add graph samples without inventing links through an obstacle.
			var sections := maxi(1, ceili(a.distance_to(b) / (LINK_RANGE * 0.5)))
			for step in range(1, sections):
				_collect(a.lerp(b, float(step) / float(sections)))


func steer(enemy: CharacterBody3D, wish: Vector3) -> Vector3:
	if wish.length_squared() < 0.001 or not is_instance_valid(_world):
		return wish
	var target := enemy.get("player_target") as Node3D
	if not is_instance_valid(target):
		return wish
	var goal := target.global_position
	var id := enemy.get_instance_id()
	var cached: Dictionary = _paths.get(id, {})
	if cached.is_empty() or _clock >= float(cached.get("until", 0.0)) or goal.distance_squared_to(cached.get("goal", goal)) > 1.0:
		var radius := 0.52
		for child: Node in enemy.get_children():
			if child is CollisionShape3D and child.shape is CapsuleShape3D:
				radius = child.shape.radius * maxf(child.global_basis.x.length(), child.global_basis.z.length()) + 0.03
				break
		var path := _find_path(enemy.global_position, goal, radius, radius + 0.5)
		cached = {"until": _clock + PATH_REFRESH_SECONDS, "goal": goal, "path": path, "index": 0}
		_paths[id] = cached
		if _paths.size() > 96:
			for old_id: int in _paths.keys():
				if not is_instance_valid(instance_from_id(old_id)):
					_paths.erase(old_id)
	var route: PackedVector3Array = cached.path
	var index: int = cached.index
	while index < route.size() and _horizontal_distance(enemy.global_position, route[index]) < 0.4 and absf(enemy.global_position.y - route[index].y) < 0.45:
		index += 1
		cached.index = index
	if index >= route.size():
		return Vector3.ZERO
	var toward := route[index] - enemy.global_position
	toward.y = 0.0
	return toward.normalized()


func path_between(from: Vector3, to: Vector3, clearance: float = 0.32) -> PackedVector3Array:
	return _find_path(from, to, clearance, 0.0)


func _find_path(from: Vector3, to: Vector3, clearance: float, stand_off: float) -> PackedVector3Array:
	if not is_instance_valid(_world):
		return PackedVector3Array()
	var start_ground := _ground(from)
	var target_ground := _ground(to)
	if start_ground.is_empty() or target_ground.is_empty():
		return PackedVector3Array()
	var start: Vector3 = start_ground.position
	var goal: Vector3 = target_ground.position
	var direct_end := _approach_point(start, goal, stand_off)
	if _target_visible(start, goal, stand_off) and can_travel(start, direct_end, clearance):
		return PackedVector3Array([start, direct_end])
	if _points.is_empty():
		return PackedVector3Array()
	var start_id := _points.size()
	var end_id := start_id + 1
	_graph.add_point(start_id, start)
	_graph.add_point(end_id, goal)
	var start_candidates := _nearby_points(start)
	var end_candidates := _nearby_points(goal)
	var linked := 0
	for index: int in start_candidates:
		if can_travel(start, _points[index], clearance):
			_graph.connect_points(start_id, index)
			linked += 1
			if linked >= 6:
				break
	linked = 0
	for index: int in end_candidates:
		var approach := _approach_point(_points[index], goal, stand_off)
		if _target_visible(_points[index], goal, stand_off) and can_travel(_points[index], approach, clearance):
			_graph.connect_points(index, end_id)
			linked += 1
			if linked >= 6:
				break
	var route := _graph.get_point_path(start_id, end_id)
	_graph.remove_point(start_id)
	_graph.remove_point(end_id)
	if route.size() >= 2 and stand_off > 0.0:
		route[route.size() - 1] = _approach_point(route[route.size() - 2], goal, stand_off)
	return route


func _nearby_points(at: Vector3) -> Array[int]:
	var candidates: Array[int] = []
	for index in _points.size():
		if at.distance_to(_points[index]) <= LINK_RANGE:
			candidates.append(index)
	candidates.sort_custom(func(a: int, b: int) -> bool: return at.distance_squared_to(_points[a]) < at.distance_squared_to(_points[b]))
	return candidates


func _approach_point(from: Vector3, target: Vector3, stand_off: float) -> Vector3:
	if stand_off <= 0.0:
		return target
	var offset := target - from
	offset.y = 0.0
	var distance := offset.length()
	if distance <= stand_off:
		return from
	var point := target - offset.normalized() * stand_off
	var ground := _ground(point)
	return ground.position if not ground.is_empty() else point


func _target_visible(from: Vector3, to: Vector3, stand_off: float) -> bool:
	# For a combat endpoint, stop outside the player's capsule, but still
	# require sight of the actual player. A wall must not count as arrival.
	return stand_off <= 0.0 or _wall_clear(from + Vector3.UP * 0.65, to + Vector3.UP * 0.65)


func can_travel(a: Vector3, b: Vector3, clearance: float = 0.32) -> bool:
	if not is_instance_valid(_world):
		return false
	var length := _horizontal_distance(a, b)
	if length < 0.02:
		return absf(a.y - b.y) < 0.15 and not _ground(a).is_empty()
	var forward := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	var side := Vector3(-forward.z, 0, forward.x)
	# Fast rejection before the more expensive floor probes.
	for offset in [-clearance, 0.0, clearance]:
		if not _wall_clear(a + side * offset + Vector3.UP * 0.6, b + side * offset + Vector3.UP * 0.6):
			return false
	var steps := maxi(1, ceili(length / FLOOR_SAMPLE_STEP))
	var previous: Vector3
	var previous_normal := Vector3.UP
	for index in steps + 1:
		var at := a.lerp(b, float(index) / float(steps))
		var center := _ground(at)
		if center.is_empty():
			return false
		var floor_at: Vector3 = center.position
		var normal: Vector3 = center.normal
		if index > 0:
			var rise := absf(floor_at.y - previous.y)
			if rise > length / float(steps) + 0.035:
				return false
			if rise > 0.12 and normal.y > 0.98 and previous_normal.y > 0.98:
				return false
		for offset in [-clearance, clearance]:
			var support := _ground(at + side * offset)
			if support.is_empty():
				return false
			var expected_y: float = floor_at.y - (normal.x * side.x + normal.z * side.z) * float(offset) / normal.y
			if absf(float(support.position.y) - expected_y) > 0.23:
				return false
		if index > 0:
			for offset in [-clearance, 0.0, clearance]:
				# Low walls count too. Follow the measured floor over real ramps.
				if not _wall_clear(previous + side * offset + Vector3.UP * 0.12, floor_at + side * offset + Vector3.UP * 0.12):
					return false
		previous = floor_at
		previous_normal = normal
	return true


func _ground(at: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.8, at + Vector3.DOWN * 3.5, 1)
	var hit := _world.direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit if float(hit.normal.y) >= 0.707 else {}
	# A ray exactly on a trimesh diagonal can miss both triangles. Require
	# matching support on all four sides within 3 mm, not a permissive edge ray.
	var agreed: Dictionary = {}
	var height := 0.0
	for offset: Vector3 in [Vector3(0.003,0,0), Vector3(-0.003,0,0), Vector3(0,0,0.003), Vector3(0,0,-0.003)]:
		query.from = at + offset + Vector3.UP * 0.8
		query.to = at + offset + Vector3.DOWN * 3.5
		var sample := _world.direct_space_state.intersect_ray(query)
		if sample.is_empty() or float(sample.normal.y) < 0.707:
			return {}
		var normal: Vector3 = sample.normal
		if not agreed.is_empty() and (sample.collider != agreed.collider or normal.dot(agreed.normal) < 0.995 or absf(float(sample.position.y) - float(agreed.position.y)) > 0.02):
			return {}
		if agreed.is_empty():
			agreed = sample
		height += float(sample.position.y)
	if agreed.is_empty():
		return {}
	agreed.position = Vector3(at.x, height * 0.25, at.z)
	return agreed


func _wall_clear(a: Vector3, b: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(a, b, 1)
	return _world.direct_space_state.intersect_ray(query).is_empty()


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
