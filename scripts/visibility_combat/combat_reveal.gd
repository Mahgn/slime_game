extends "res://scripts/keepers/keepers_architectural_cutaway.gd"

# Opt-in combat comparison. Visibility belongs to an authored wall assembly;
# the independent ghost describes its unchanged full physical volume.
const GHOST_SHADER := preload("res://shaders/visibility_combat/barrier_ghost.gdshader")
const OPEN_SECONDS := 0.28
const CLOSE_SECONDS := 0.48
const HOLD_SECONDS := 0.45
const FOCUS_IN_SECONDS := 0.18
const FOCUS_OUT_SECONDS := 0.38
const FOCUS_HOLD_SECONDS := 0.16
const FLOOR_RADIUS := 2.7
const RETAIN_RADIUS := 3.3
const ENEMY_RADIUS := 10.0
const PILOT_ROOMS: Array[String] = ["furnace", "cistern"]

var geometry: Node3D
var support_y := 0.0
var elapsed_update_time := 0.0
var protected_points: Array[Vector3] = []
var combat_points: Array[Vector3] = []
var pilot_sections: Array[Dictionary] = []
var ghost_root: Node3D
var _floor_rects: Array[Rect2] = []
var _floor_exclusions: Array[RID] = []
var _support_initialized := false
var _player_id := 0
var _aim_barrier_id := 0


func setup(source: Node3D, rooms: Dictionary, connections: Array) -> void:
	geometry = source
	enabled = false
	local_window = null
	sections.clear()
	pilot_sections.clear()
	_floor_rects.clear()
	_floor_exclusions.clear()
	_aim_barrier_id = 0
	if is_instance_valid(ghost_root):
		ghost_root.queue_free()
	ghost_root = Node3D.new()
	ghost_root.name = "TranslucentMasonry"
	# Never parent the contour to the visual assembly which disappears.
	geometry.add_child(ghost_root)
	for id: String in PILOT_ROOMS:
		var room: Dictionary = rooms[id]
		_floor_rects.append(Rect2(Vector2(room.center.x, room.center.z) - room.half, room.half * 2.0))
	for link: Dictionary in connections:
		if not PILOT_ROOMS.has(String(link.a)) or not PILOT_ROOMS.has(String(link.b)):
			continue
		var a: Vector3 = link.path[0]
		var b: Vector3 = link.path[-1]
		_floor_rects.append(Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(b.x, b.z)).grow(float(link.width) * 0.5))
	for index: int in structural_sections.size():
		var section: Dictionary = structural_sections[index]
		section.id = "wall_%03d" % index
		section.reveal_amount = 0.0
		section.wanted = false
		section.hold = 0.0
		section.focus_amount = 0.0
		section.focus_hold = 0.0
		section.pilot = false
		var body := section.get("body") as CollisionObject3D
		if is_instance_valid(body):
			_floor_exclusions.append(body.get_rid())
		var owners: Array = section.get("room_ids", [String(section.get("room_id", ""))])
		if bool(section.get("keep_full", false)) or not owners.any(func(id: String) -> bool: return PILOT_ROOMS.has(id)):
			continue
		if not is_instance_valid(body):
			continue
		var collision: CollisionShape3D
		for child: Node in body.get_children():
			if child is CollisionShape3D and child.shape is BoxShape3D:
				collision = child
				break
		if collision == null:
			continue
		var box := collision.shape as BoxShape3D
		section.pilot = true
		section.collision_shape = collision
		section.local_bounds = AABB(-box.size * 0.5, box.size)
		section.world_bounds = collision.global_transform * section.local_bounds
		section.inverse_collision = collision.global_transform.affine_inverse()
		section.ghost = _create_ghost(section)
		if section.ghost == null:
			section.pilot = false
			push_warning("Masonry reveal retains an unsupported wall: " + String(section.id))
			continue
		section.ghost_material = section.ghost.material_override
		sections[section.id] = section
		pilot_sections.append(section)
	refresh_render()


func _create_ghost(section: Dictionary) -> MeshInstance3D:
	var assembly: MeshInstance3D
	var parts: Array[MeshInstance3D] = []
	var has_stone := false
	for source: MeshInstance3D in section.get("fade_meshes", []):
		if bool(source.get_meta(&"comparison_masonry",false)):
			has_stone = true
			break
	if not has_stone:
		return null
	for source: MeshInstance3D in section.get("fade_meshes", []):
		var original := source.material_override as ShaderMaterial
		var stone := bool(source.get_meta(&"comparison_masonry",false))
		var cap: bool = source == section.get("cap_mesh")
		if not stone and not cap:
			continue
		var part := MeshInstance3D.new()
		part.name = "Masonry_" + String(section.id) if assembly == null else "MasonryCap"
		# Share the authored stone/chamfer geometry, never its collision or fading
		# material. Mounted props stay with the original disappearing assembly.
		part.mesh = source.mesh
		part.set_meta(&"source_mesh", source)
		var material := ShaderMaterial.new()
		material.shader = GHOST_SHADER
		material.set_shader_parameter("stone_surface", stone)
		if cap:
			material.set_shader_parameter("base_color", original.get_shader_parameter("base_color"))
		part.material_override = material
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if assembly == null:
			assembly = part
			ghost_root.add_child(part)
		else:
			assembly.add_child(part)
		part.global_transform = source.global_transform
		parts.append(part)
	section.ghost_parts = parts
	if assembly != null:
		assembly.visible = false
	return assembly


func update_view(player: SlimeController, camera: Camera3D, delta: float = 0.0) -> void:
	if delta <= 0.0 or not is_instance_valid(geometry) or not is_instance_valid(player) or not is_instance_valid(camera) or get_tree().paused:
		return
	elapsed_update_time += delta
	if not _support_initialized or _player_id != player.get_instance_id() or player.is_on_floor():
		support_y = player.global_position.y
		_support_initialized = true
		_player_id = player.get_instance_id()
	var center := Vector3(player.global_position.x, support_y + 0.06, player.global_position.z)
	protected_points = _floor_points(center, FLOOR_RADIUS)
	protected_points.append(player.global_position + Vector3.UP * 0.65)
	var retained := _floor_points(center, RETAIN_RADIUS)
	retained.append(player.global_position + Vector3.UP * 0.65)
	combat_points = _combat_points(player)
	var directions: Array[Vector3] = [camera.global_basis.z]
	if player.presentation.is_camera_turning():
		directions.append(Vector3(12.0, 13.9, 12.0).rotated(Vector3.UP, player.presentation._turn_to).normalized())
	for section: Dictionary in pilot_sections:
		var wanted := false
		if enabled:
			var points: Array[Vector3] = retained if bool(section.wanted) else protected_points
			wanted = _occludes_any(section, points, directions) or _occludes_any(section, combat_points, directions)
		if wanted:
			section.wanted = true
			section.hold = HOLD_SECONDS
		else:
			section.hold = maxf(0.0, float(section.hold) - delta)
			if float(section.hold) == 0.0:
				section.wanted = false
		var before: float = section.reveal_amount
		var target := 1.0 if bool(section.wanted) else 0.0
		section.reveal_amount = move_toward(before, target, delta / (OPEN_SECONDS if target > before else CLOSE_SECONDS))
		var focused: bool = enabled and _aim_barrier_id != 0 and section.body.get_instance_id() == _aim_barrier_id
		section.focus_hold = FOCUS_HOLD_SECONDS if focused else maxf(0.0, float(section.focus_hold)-delta)
		var focus_target := 1.0 if enabled and float(section.focus_hold)>0.0 else 0.0
		var focus_before: float = section.focus_amount
		section.focus_amount = move_toward(focus_before, focus_target, delta / (FOCUS_IN_SECONDS if focus_target>focus_before else FOCUS_OUT_SECONDS))
		if not is_equal_approx(before, float(section.reveal_amount)) or not is_equal_approx(focus_before, float(section.focus_amount)):
			_render_section(section)


func _floor_points(center: Vector3, radius: float) -> Array[Vector3]:
	var result: Array[Vector3] = [center]
	for x: int in range(-2, 3):
		for z: int in range(-2, 3):
			var offset := Vector3(float(x), 0.0, float(z)) * radius * 0.5
			if offset.length() > radius + 0.01:
				continue
			var floor_point := _floor_point(center + offset)
			if floor_point != Vector3.INF:
				result.append(floor_point)
	return result


func _floor_point(at: Vector3) -> Vector3:
	var point := Vector2(at.x, at.z)
	if not _floor_rects.any(func(rect: Rect2) -> bool: return rect.has_point(point)):
		return Vector3.INF
	# The actual support, including the lowered cistern, is authoritative. Full
	# structural walls are excluded so their tops cannot become fictitious floor.
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.0, at + Vector3.DOWN * 3.0, 1)
	query.exclude = _floor_exclusions
	var hit := geometry.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or float(hit.normal.y) < 0.65:
		return Vector3.INF
	return (hit.position as Vector3) + Vector3.UP * 0.06


func _combat_points(player: SlimeController) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for actor: Node in get_tree().get_nodes_in_group(&"enemies"):
		if not actor is Node3D or not actor.is_inside_tree() or (actor.has_method("is_alive") and not actor.is_alive()):
			continue
		var body := actor as Node3D
		if body.global_position.distance_to(player.global_position) > ENEMY_RADIUS:
			continue
		if not PILOT_ROOMS.has(String(body.get_meta(&"home_room", ""))):
			continue
		# A lower enemy and its warning stay protected: no narrow height filter.
		result.append(body.global_position + Vector3.UP * 0.65)
		for offset: Vector3 in [Vector3.ZERO, Vector3(0.7, 0, 0), Vector3(-0.7, 0, 0), Vector3(0, 0, 0.7), Vector3(0, 0, -0.7)]:
			var floor_point := _floor_point(body.global_position + offset)
			if floor_point != Vector3.INF:
				result.append(floor_point)
	for actor: Node in get_tree().get_nodes_in_group(&"projectiles"):
		if actor is Node3D and actor.is_inside_tree() and actor.global_position.distance_to(player.global_position) <= ENEMY_RADIUS:
			result.append(actor.global_position)
	return result


func _occludes_any(section: Dictionary, points: Array[Vector3], directions: Array[Vector3]) -> bool:
	for point: Vector3 in points:
		for direction: Vector3 in directions:
			if blocks_point(section, point, direction):
				return true
	return false


func blocks_point(section: Dictionary, point: Vector3, direction: Vector3) -> bool:
	var origin := point + direction * 48.0
	var bounds: AABB = section.world_bounds
	if bounds.intersects_segment(origin, point) == null:
		return false
	var inverse: Transform3D = section.inverse_collision
	var local: AABB = section.local_bounds
	return local.intersects_segment(inverse * origin, inverse * point) != null


func _render_section(section: Dictionary) -> void:
	var amount := smoothstep(0.0, 1.0, float(section.get("reveal_amount", 0.0)))
	if _section_renderer.is_valid():
		_section_renderer.call(section, amount, float(section.get("cut_height", 0.18)))
	var ghost := section.get("ghost") as MeshInstance3D
	if is_instance_valid(ghost):
		ghost.visible = amount > 0.0001
		for part: MeshInstance3D in section.ghost_parts:
			var material := part.material_override as ShaderMaterial
			material.set_shader_parameter("reveal_amount", amount)
			material.set_shader_parameter("focus_amount", smoothstep(0.0,1.0,float(section.focus_amount)))


func refresh_render() -> void:
	# Ink switches material copies. Reapply state without changing the fade,
	# and leave unrelated walls fully visible even when this mode is enabled.
	for section: Dictionary in structural_sections:
		_render_section(section)


func set_enabled(value: bool) -> void:
	enabled = value
	if not value:
		_aim_barrier_id = 0
		for section: Dictionary in pilot_sections:
			section.wanted = false
			section.hold = 0.0
			section.focus_hold = 0.0


func set_aim_barrier(collider: CollisionObject3D = null) -> void:
	if get_tree().paused:
		return
	_aim_barrier_id = collider.get_instance_id() if enabled and is_barrier(collider) else 0


func is_point_cut(collider: CollisionObject3D, point: Vector3) -> bool:
	if not is_instance_valid(collider) or not _body_sections.has(collider.get_instance_id()):
		return false
	var section: Dictionary = _body_sections[collider.get_instance_id()]
	# Only the camera aiming ray may see beyond an open visual shell. Movement,
	# jump, enemy sight, whip and projectile collision continue using the body.
	return bool(section.get("pilot", false)) and float(section.get("reveal_amount", 0.0)) > 0.98 and point.y > float(section.get("base_height", 0.0)) + 0.20


func is_barrier(collider: CollisionObject3D) -> bool:
	if not is_instance_valid(collider) or not _body_sections.has(collider.get_instance_id()):
		return false
	return bool((_body_sections[collider.get_instance_id()] as Dictionary).get("pilot", false))


func get_reveal_amount() -> float:
	return 0.0
