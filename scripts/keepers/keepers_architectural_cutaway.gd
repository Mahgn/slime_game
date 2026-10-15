extends SlimeRoomCutaway

# Room ownership is measured on the floor, independently of jump height,
# camera smoothing and combat shake. The older facility remains full-height
# until its caller explicitly enables the dungeon's presentation experiment.
const VIEW_DIRECTION := Vector2(0.70710678118, 0.70710678118)
const VIEW_SLOPE := Vector2(12.0 / 13.9, 12.0 / 13.9)
const FOUNDATION_HEIGHT := 0.18
const REVEAL_SECONDS := 0.30
const RESTORE_SECONDS := 0.42
const ROOM_EXIT_MARGIN := 0.80
const PASSAGE_APPROACH := 1.75
const PASSAGE_EXIT_MARGIN := 0.80
const RELEASE_HOLD_SECONDS := 0.35
const AIM_REVEAL_THRESHOLD := 0.80
const OWN_ROOM_CLEARANCE := 0.50
const NEIGHBOUR_ROOM_CLEARANCE := 0.05
const PASSAGE_WALL_HALF_WIDTH := 0.45
const DOORWAY_INTERIOR_REACH := 1.35
const TARGET_BODY_HEIGHT := 0.95
const MIN_REVEAL_OVERLAP_AREA := 0.02

var structural_sections: Array[Dictionary] = []
var local_window: RefCounted
# Public, deterministic telemetry also used by the native transition test.
var room_amounts: Dictionary = {}
var room_targets: Dictionary = {}
var active_rooms: Array[String] = []
var room_polygons: Dictionary = {}
var room_bounds: Dictionary = {}
var connection_zones: Array[Dictionary] = []
var passage_regions: Array[Dictionary] = []

var _release_remaining: Dictionary = {}
var _body_sections: Dictionary = {}
var _section_renderer: Callable
var _crown_renderer: Callable


func configure_building(rooms: Dictionary, connections: Array) -> void:
	enabled = false
	lower_route = false
	room_amounts.clear()
	room_targets.clear()
	active_rooms.clear()
	room_polygons.clear()
	room_bounds.clear()
	connection_zones.clear()
	passage_regions.clear()
	_release_remaining.clear()
	_body_sections.clear()
	for id: String in rooms:
		var room: Dictionary = rooms[id]
		var center: Vector3 = room.center
		var polygon := PackedVector2Array()
		if room.has("footprint"):
			for vertex: Vector2 in room.footprint:
				polygon.append(vertex + Vector2(center.x, center.z))
		else:
			var half: Vector2 = room.half
			for vertex: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)]:
				polygon.append(vertex + Vector2(center.x, center.z))
		if polygon.size() < 3:
			continue
		var bounds := Rect2(polygon[0], Vector2.ZERO)
		for vertex: Vector2 in polygon:
			bounds = bounds.expand(vertex)
		room_polygons[id] = polygon
		room_bounds[id] = bounds
		room_amounts[id] = 0.0
		room_targets[id] = 0.0
		_release_remaining[id] = RELEASE_HOLD_SECONDS
	for connection: Dictionary in connections:
		var path := PackedVector2Array()
		for point: Vector3 in connection.path:
			path.append(Vector2(point.x, point.z))
		if path.size() >= 2:
			connection_zones.append({"a": String(connection.a), "b": String(connection.b),
				"path": path, "width": float(connection.width)})
			_register_passage_regions(connection, path)
	for section: Dictionary in structural_sections:
		var normal: Vector3 = section.get("normal", Vector3.ZERO)
		var horizontal := Vector2(normal.x, normal.z).normalized()
		section.faces_camera = horizontal.dot(VIEW_DIRECTION) > 0.05
		section.cut_height = float(section.get("cut_height", float(section.get("base_height", 0.0)) + FOUNDATION_HEIGHT))
		section.reveal_amount = 0.0
		var owners: Array[String] = []
		for owner: String in section.get("room_ids", [String(section.get("room_id", ""))]):
			if room_amounts.has(owner) and not owners.has(owner):
				owners.append(owner)
		section.room_ids = owners
		section.reveal_room_ids = _reveal_owners(section, owners)
		section.is_foreground = not section.reveal_room_ids.is_empty()
		var node: Node3D = section.get("node") as Node3D
		if is_instance_valid(node):
			node.show()
		var body: CollisionObject3D = section.get("body") as CollisionObject3D
		if is_instance_valid(body):
			_body_sections[body.get_instance_id()] = section
			# The controller never changes the physical wall or its layers.
			if body.has_meta(&"architectural_cut_height"):
				body.remove_meta(&"architectural_cut_height")
		for extra: CollisionObject3D in section.get("additional_bodies", []):
			_body_sections[extra.get_instance_id()] = section
	refresh_render()


func _reveal_owners(section: Dictionary, owners: Array[String]) -> Array[String]:
	var result: Array[String] = []
	var reasons: Dictionary = {}
	section.reveal_reasons = reasons
	if bool(section.get("keep_full", false)):
		return result
	if section.has("authored_reveal_room_ids"):
		for id: String in section.authored_reveal_room_ids:
			_add_reveal_owner(result, reasons, id, "authored_portal")
		return result
	if bool(section.faces_camera):
		for id: String in owners:
			_add_reveal_owner(result, reasons, id, "front_room")
	var body: CollisionObject3D = section.get("body") as CollisionObject3D
	if not is_instance_valid(body):
		return result
	var collision: CollisionShape3D = body.get_child(0) as CollisionShape3D if body.get_child_count() > 0 else null
	if collision == null or not collision.shape is BoxShape3D:
		return result
	var box := collision.shape as BoxShape3D
	var projected := PackedVector2Array()
	var top := float(section.get("top_height", body.global_position.y + box.size.y * 0.5))
	var body_plane := float(section.get("base_height", 0.0)) + TARGET_BODY_HEIGHT
	# Project the upper volume along the fixed camera rays onto floor and
	# body-height target planes. These fixed planes do not follow jumps.
	for x in [-box.size.x * 0.5, box.size.x * 0.5]:
		for z in [-box.size.z * 0.5, box.size.z * 0.5]:
			var world := collision.to_global(Vector3(x, 0.0, z))
			for target_height in [0.0, body_plane]:
				for height in [maxf(float(section.cut_height), target_height), top]:
					projected.append(Vector2(world.x, world.z) - VIEW_SLOPE * (height - target_height))
	var hull := Geometry2D.convex_hull(projected)
	section.reveal_projection = hull
	if hull.size() < 3:
		return result
	var projected_bounds := Rect2(hull[0], Vector2.ZERO)
	for vertex: Vector2 in hull:
		projected_bounds = projected_bounds.expand(vertex)
	for id: String in room_bounds:
		# A room's own back wall should remain where its projection only covers
		# the solid wall footprint. A rear passage rail, however, may project
		# into either of its TWO owning rooms: never skip owners wholesale.
		var clearance := OWN_ROOM_CLEARANCE if owners.has(id) else NEIGHBOUR_ROOM_CLEARANCE
		var inner: Rect2 = room_bounds[id].grow(-clearance)
		if not projected_bounds.intersects(inner):
			continue
		var footprint := PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)])
		if _overlaps_reveal_region(hull, footprint):
			_add_reveal_owner(result, reasons, id, "room_overlap")
	# Door gaps are playable space too. A jamb may cover only the corridor,
	# without projecting into either room's rectangle (furnace/cistern).
	# Bind that whole section to both rooms once at construction, so movement
	# on the threshold never changes its ownership or starts a separate fade.
	for region: Dictionary in passage_regions:
		if not projected_bounds.intersects(region.bounds):
			continue
		if _overlaps_reveal_region(hull, region.polygon):
			for id: String in region.room_ids:
				_add_reveal_owner(result, reasons, id, "passage_overlap")
	return result


func _register_passage_regions(connection: Dictionary, path: PackedVector2Array) -> void:
	var half_width := maxf(0.1, float(connection.width) * 0.5 - PASSAGE_WALL_HALF_WIDTH)
	for index in range(path.size() - 1):
		var direction := (path[index + 1] - path[index]).normalized()
		if direction.is_zero_approx():
			continue
		var across := Vector2(-direction.y, direction.x) * half_width
		var a := path[index] - direction * DOORWAY_INTERIOR_REACH
		var b := path[index + 1] + direction * DOORWAY_INTERIOR_REACH
		var polygon := PackedVector2Array([a - across, b - across, b + across, a + across])
		var bounds := Rect2(polygon[0], Vector2.ZERO)
		for vertex: Vector2 in polygon:
			bounds = bounds.expand(vertex)
		passage_regions.append({"polygon": polygon, "bounds": bounds,
			"room_ids": [String(connection.a), String(connection.b)]})


func _overlaps_reveal_region(hull: PackedVector2Array, polygon: PackedVector2Array) -> bool:
	for overlap: PackedVector2Array in Geometry2D.intersect_polygons(hull, polygon):
		if _polygon_area(overlap) > MIN_REVEAL_OVERLAP_AREA:
			return true
	return false


func _add_reveal_owner(owners: Array[String], reasons: Dictionary, id: String, reason: String) -> void:
	if not room_amounts.has(id):
		return
	if not owners.has(id):
		owners.append(id)
	if not reasons.has(id):
		reasons[id] = []
	if not reasons[id].has(reason):
		reasons[id].append(reason)


func _polygon_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for index in polygon.size():
		area += polygon[index].cross(polygon[(index + 1) % polygon.size()])
	return absf(area) * 0.5


func set_render_callbacks(section_callback: Callable, crown_callback: Callable) -> void:
	_section_renderer = section_callback
	_crown_renderer = crown_callback
	refresh_render()


func update_view(player: SlimeController, _camera: Camera3D, delta: float = 0.0) -> void:
	if local_window != null:
		local_window.update_view(player, _camera, delta)
		return
	if not is_instance_valid(player) or (is_inside_tree() and get_tree().paused):
		return
	advance(player.global_position, delta)


func advance(position: Vector3, delta: float) -> void:
	if not enabled:
		return
	var elapsed := maxf(delta, 0.0)
	var point := Vector2(position.x, position.z)
	var wanted: Dictionary = {}
	var retained: Dictionary = {}
	for id: String in room_polygons:
		var polygon: PackedVector2Array = room_polygons[id]
		if Geometry2D.is_point_in_polygon(point, polygon):
			wanted[id] = true
			retained[id] = true
		elif float(room_targets[id]) > 0.0 and _polygon_distance(point, polygon) <= ROOM_EXIT_MARGIN:
			retained[id] = true
	# A passage owns BOTH adjacent rooms, including an approach inside each
	# doorway. A wider exit zone prevents reversing the fade at its boundary.
	for zone: Dictionary in connection_zones:
		var distance := _path_distance(point, zone.path)
		var enter_radius := float(zone.width) * 0.5 + PASSAGE_APPROACH
		if distance <= enter_radius:
			wanted[zone.a] = true
			wanted[zone.b] = true
		if distance <= enter_radius + PASSAGE_EXIT_MARGIN:
			retained[zone.a] = true
			retained[zone.b] = true
	active_rooms.clear()
	var changed := false
	for id: String in room_amounts:
		var target: float = room_targets[id]
		if wanted.has(id):
			target = 1.0
			_release_remaining[id] = RELEASE_HOLD_SECONDS
		elif target > 0.0:
			if retained.has(id):
				_release_remaining[id] = RELEASE_HOLD_SECONDS
			else:
				_release_remaining[id] = maxf(0.0, float(_release_remaining[id]) - elapsed)
				if float(_release_remaining[id]) <= 0.0:
					target = 0.0
		room_targets[id] = target
		if target > 0.0:
			active_rooms.append(id)
		var duration := REVEAL_SECONDS if target > float(room_amounts[id]) else RESTORE_SECONDS
		var amount := move_toward(float(room_amounts[id]), target, elapsed / duration)
		if amount != float(room_amounts[id]):
			room_amounts[id] = amount
			changed = true
	if changed:
		_apply_render(false)


func _polygon_distance(point: Vector2, polygon: PackedVector2Array) -> float:
	var distance := INF
	for index in polygon.size():
		var closest := Geometry2D.get_closest_point_to_segment(point, polygon[index], polygon[(index + 1) % polygon.size()])
		distance = minf(distance, point.distance_to(closest))
	return distance


func _path_distance(point: Vector2, path: PackedVector2Array) -> float:
	var distance := INF
	for index in range(path.size() - 1):
		var closest := Geometry2D.get_closest_point_to_segment(point, path[index], path[index + 1])
		distance = minf(distance, point.distance_to(closest))
	return distance


func refresh_render() -> void:
	if local_window != null:
		local_window.refresh_materials()
	_apply_render(true)


func _apply_render(force: bool) -> void:
	for section: Dictionary in structural_sections:
		var amount := 0.0
		if enabled:
			amount = float(section.get("minimum_reveal", 0.0))
		if enabled and bool(section.get("is_foreground", false)):
			for owner: String in section.get("reveal_room_ids", []):
				amount = maxf(amount, float(room_amounts.get(owner, 0.0)))
		var changed := amount != float(section.get("reveal_amount", 0.0))
		section.reveal_amount = amount
		if (force or changed) and _section_renderer.is_valid():
			_section_renderer.call(section, amount, float(section.cut_height))
	if _crown_renderer.is_valid():
		_crown_renderer.call(room_amounts)


func is_point_cut(collider: CollisionObject3D, point: Vector3) -> bool:
	if local_window != null:
		return local_window.is_point_cut(collider, point)
	if not enabled or not is_instance_valid(collider) or not _body_sections.has(collider.get_instance_id()):
		return false
	var section: Dictionary = _body_sections[collider.get_instance_id()]
	return bool(section.is_foreground) and float(section.reveal_amount) >= AIM_REVEAL_THRESHOLD and point.y > float(section.cut_height)


func get_reveal_amount() -> float:
	# This controller reveals walls, not the old gallery's floor/trail layer.
	return 0.0


func set_enabled(value: bool) -> void:
	enabled = value
	if not value:
		active_rooms.clear()
		for id: String in room_amounts:
			room_amounts[id] = 0.0
			room_targets[id] = 0.0
			_release_remaining[id] = RELEASE_HOLD_SECONDS
	refresh_render()
