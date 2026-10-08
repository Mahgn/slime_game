extends Spitter
class_name SlimeKeepersWorldSpitter

# The original enemy's retreat distance and combat timings stay unchanged.
# A connected world needs physical support, rather than bounds around (0, 0).
const RETREAT_LOOKAHEAD := 0.85
const BODY_CLEARANCE := 0.035

var movement_guide: Callable

# Environmental mechanisms use the existing hit/death/source pipeline.
func receive_environment_hit(amount: int, cast_key: String) -> bool:
	return super.receive_hit(amount, cast_key, &"player")


func _move(toward: Vector3, distance: float, delta: float) -> void:
	var direction := toward
	var movement_distance := distance
	if _phase == Phase.IDLE and _has_live_target() and not _has_line_of_sight():
		# Only select the inherited approach branch. Attack distance is still
		# computed by Spitter's physics update from the real player position.
		movement_distance = maxf(distance, ENGAGE_DISTANCE)
	if _phase != Phase.WINDUP and movement_distance > ENGAGE_DISTANCE - 0.5 and direction.length_squared() > 0.001 and movement_guide.is_valid():
		direction = movement_guide.call(self, direction)
	super._move(direction, movement_distance, delta)


func _can_retreat(direction: Vector3) -> bool:
	var horizontal := Vector3(direction.x, 0.0, direction.z)
	if horizontal.length_squared() < 0.5:
		return false
	horizontal = horizontal.normalized()
	var collider := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collider == null or not collider.shape is CapsuleShape3D:
		return false
	var capsule := collider.shape as CapsuleShape3D
	var radius := capsule.radius * maxf(collider.global_basis.x.length(), collider.global_basis.z.length())
	var start := _retreat_ground(global_position)
	if start.is_empty():
		return false
	var previous_floor: Vector3 = start.position
	var end_floor := previous_floor
	var max_slope := tan(floor_max_angle)
	# Probe the swept footprint as well as the center. A center ray alone lets
	# half of the capsule leave a narrow ledge, especially at diagonal corners.
	for step in range(1, 4):
		var at := global_position + horizontal * RETREAT_LOOKAHEAD * float(step) / 3.0
		var center := _retreat_ground(at)
		if center.is_empty():
			return false
		end_floor = center.position
		if absf(end_floor.y - previous_floor.y) > RETREAT_LOOKAHEAD / 3.0 * max_slope + BODY_CLEARANCE:
			return false
		var normal: Vector3 = center.normal
		for corner in 8:
			var angle := TAU * float(corner) / 8.0
			var offset := Vector3(cos(angle), 0, sin(angle)) * (radius + BODY_CLEARANCE)
			var support := _retreat_ground(at + offset)
			if support.is_empty():
				return false
			var expected_y := end_floor.y - (normal.x * offset.x + normal.z * offset.z) / normal.y
			# Permit normal floor-snap variation at a ramp join, not a drop to
			# another floor underneath the edge of the enemy's body.
			if absf(float(support.position.y) - expected_y) > floor_snap_length + BODY_CLEARANCE:
				return false
		previous_floor = end_floor
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = collider.global_transform
	query.transform.origin += Vector3.UP * BODY_CLEARANCE
	query.motion = horizontal * RETREAT_LOOKAHEAD + Vector3.UP * (end_floor.y - float(start.position.y))
	query.collision_mask = 1
	query.margin = 0.005
	query.exclude = [get_rid()]
	var fractions := get_world_3d().direct_space_state.cast_motion(query)
	return fractions.size() == 2 and fractions[0] >= 0.999


func _retreat_ground(at: Vector3) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.1, at + Vector3.DOWN * 1.4, 1)
	ray.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		return hit if float(hit.normal.y) >= cos(floor_max_angle) else {}
	# Same narrow tolerance as the world graph: a central ray can hit the
	# shared edge of two floor triangles. Four agreeing neighbors prove support.
	var agreed: Dictionary = {}
	var height := 0.0
	for offset: Vector3 in [Vector3(0.003,0,0), Vector3(-0.003,0,0), Vector3(0,0,0.003), Vector3(0,0,-0.003)]:
		ray.from = at + offset + Vector3.UP * 1.1
		ray.to = at + offset + Vector3.DOWN * 1.4
		var sample := get_world_3d().direct_space_state.intersect_ray(ray)
		if sample.is_empty() or float(sample.normal.y) < cos(floor_max_angle):
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
