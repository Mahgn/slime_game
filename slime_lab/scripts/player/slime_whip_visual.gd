extends Node3D
class_name SlimeWhipVisual

const PREPARATION_SECONDS := 0.12
const ACTIVE_SECONDS := 0.08
const RECOVERY_SECONDS := 0.35
const VARIANT_RIGHT := 0
const VARIANT_LEFT := 1
const VARIANT_OVERHEAD := 2
const VARIANT_COUNT := 3
const RINGS := 18
const LAY_RINGS := 8
const LAY_MAX_LENGTH := 0.65
const LAY_SURFACE_MARGIN := 0.020
const CAP_RINGS := 4
const SIDES := 10
const CONTACT_SAMPLES := 28
const CONTACT_MASK := 1 | 4
const CONTACT_MARGIN := 0.006
const CONTACT_BULGE := 0.028
const IMPACT_SECONDS := 0.15
const ROOT_POINT := Vector3(0.20, -0.04, -0.22)
const OVERHEAD_ROOT_POINT := Vector3(-0.20, 0.0, -0.25)

var _mesh_instance: MeshInstance3D
var _impact_mesh: MeshInstance3D
var _impact_droplets: Array[MeshInstance3D] = []
var _cast_sphere := SphereShape3D.new()
var _contact: Dictionary = {}
var _latched_contact: Dictionary = {}
var _latched_pose: Dictionary = {}
var _previous_pose: Dictionary = {}
var _previous_transform := Transform3D.IDENTITY
var _previous_phase: StringName = &""
var _visible_extension := 0.0
var _impact_age := IMPACT_SECONDS
var _lay_age := 0.0
var _lay_offsets: Array[Vector3] = []
var _lay_heading := Vector3.ZERO
var _wall_marked := false


func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Tendril"
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.22, 0.77, 0.60)
	material.roughness = 0.29
	material.metallic = 0.05
	_mesh_instance.material_override = material
	add_child(_mesh_instance)
	var splash_sphere := SphereMesh.new()
	splash_sphere.radius = 1.0
	splash_sphere.height = 2.0
	splash_sphere.radial_segments = 12
	splash_sphere.rings = 6
	_impact_mesh = MeshInstance3D.new()
	_impact_mesh.name = "ImpactPad"
	_impact_mesh.mesh = splash_sphere
	_impact_mesh.material_override = material
	_impact_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_impact_mesh.top_level = true
	add_child(_impact_mesh)
	_impact_mesh.hide()
	for index in range(3):
		var droplet := MeshInstance3D.new()
		droplet.name = "ImpactDroplet%d" % index
		droplet.mesh = splash_sphere
		droplet.material_override = material
		droplet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		droplet.top_level = true
		add_child(droplet)
		droplet.hide()
		_impact_droplets.append(droplet)
	hide()


func set_tendril_material(material: Material) -> void:
	_mesh_instance.material_override = material
	_impact_mesh.material_override = material
	for droplet in _impact_droplets:
		droplet.material_override = material


static func surface_attachment(variant: int) -> Vector3:
	match variant:
		VARIANT_LEFT:
			return Vector3(-0.41, 0.18, -0.32)
		VARIANT_OVERHEAD:
			return Vector3(-0.22, 0.35, -0.32)
		_:
			return Vector3(0.41, 0.18, -0.32)


func set_phase(phase: StringName, remaining: float, variant: int = VARIANT_RIGHT) -> void:
	var pose := _pose_for_phase(phase, remaining, variant)
	if pose.is_empty():
		_visible_extension = 0.0
		hide()
		return
	var draw_pose := pose
	var extension: float = pose["extension"]
	var compression := 0.0
	var lay_factor := 0.0
	if not _latched_contact.is_empty() and (phase == &"active" or phase == &"recovery"):
		draw_pose = _latched_pose
		var hit_t: float = _latched_contact["clip_t"]
		if phase == &"active":
			extension = hit_t
			compression = 1.0
			lay_factor = smoothstep(0.0, 0.055, _lay_age)
		else:
			var recovery_progress := clampf(1.0 - remaining / RECOVERY_SECONDS, 0.0, 1.0)
			# Let the portion lying on the obstacle peel back before the shaft retracts.
			lay_factor = 1.0 - smoothstep(0.0, 0.34, recovery_progress)
			extension = hit_t * (1.0 - smoothstep(0.32, 0.72, recovery_progress))
			compression = extension / maxf(hit_t, 0.01)
	elif not _contact.is_empty():
		extension = minf(extension, float(_contact["clip_t"]))
	if extension <= 0.01:
		_visible_extension = 0.0
		hide()
		return
	_visible_extension = extension
	if _mesh_instance.material_override is ShaderMaterial:
		(_mesh_instance.material_override as ShaderMaterial).set_shader_parameter("attachment_pos", surface_attachment(variant))
	_draw_tendril(draw_pose["root"], draw_pose["control_a"], draw_pose["control_b"], draw_pose["tip"], draw_pose["width"], extension, compression, lay_factor)
	show()


func get_contact() -> Dictionary:
	return _contact.duplicate()


func get_visible_extension() -> float:
	return _visible_extension


func refresh_contact(phase: StringName, remaining: float, variant: int, exclude_rid: RID) -> void:
	if phase == &"":
		_clear_contact()
		set_phase(phase, remaining, variant)
		return
	if phase == &"preparation" and _previous_phase != &"preparation":
		_clear_contact()
	var pose := _pose_for_phase(phase, remaining, variant)
	if pose.is_empty():
		_contact.clear()
		_previous_pose.clear()
		_previous_phase = phase
		set_phase(phase, remaining, variant)
		return
	if not _latched_contact.is_empty():
		_contact = _latched_contact
		# A moving hero can bring a frozen lash closer to another surface.
		if phase == &"active":
			var nearer := _scan_pose(_latched_pose, float(_latched_contact["clip_t"]), exclude_rid)
			if not nearer.is_empty() and float(nearer["clip_t"]) < float(_latched_contact["clip_t"]):
				_latched_contact = nearer
				_contact = nearer
				_impact_age = 0.0
				_place_impact(nearer)
				_try_stamp_wall(nearer)
	else:
		var candidate := _scan_pose(pose, float(pose["extension"]), exclude_rid)
		if phase == &"active" and not _previous_pose.is_empty() and (_previous_phase == &"preparation" or _previous_phase == &"active"):
			var swept := _scan_between_poses(_previous_pose, _previous_transform, pose, exclude_rid)
			if not swept.is_empty() and (candidate.is_empty() or float(swept["clip_t"]) < float(candidate["clip_t"])):
				candidate = swept
		_contact = candidate
		if phase == &"active" and not candidate.is_empty():
			_latched_contact = candidate.duplicate()
			_latched_pose = candidate.get("pose", pose)
			_activate_impact(candidate)
	if not _latched_contact.is_empty() and (phase == &"active" or phase == &"recovery"):
		_update_surface_lay(exclude_rid, pose, phase)
	else:
		_lay_offsets.clear()
	_previous_pose = pose
	_previous_transform = global_transform
	_previous_phase = phase
	set_phase(phase, remaining, variant)


func _update_surface_lay(exclude_rid: RID, live_pose: Dictionary, phase: StringName) -> void:
	_lay_offsets.clear()
	if _latched_pose.is_empty() or _latched_contact.is_empty():
		return
	var collider: Object = _latched_contact.get("collider")
	if not is_instance_valid(collider):
		return
	var hit_t: float = _latched_contact["clip_t"]
	var world_transform := global_transform
	var base_world: Vector3 = world_transform * _point_on_pose(hit_t, _latched_pose)
	var previous_world := base_world
	var remaining_length := 0.0
	for step in range(1, 13):
		var curve_t := lerpf(hit_t, 1.0, float(step) / 12.0)
		var next_world: Vector3 = world_transform * _point_on_pose(curve_t, _latched_pose)
		remaining_length += previous_world.distance_to(next_world)
		previous_world = next_world
	var lay_length := minf(LAY_MAX_LENGTH, remaining_length * 0.8) * smoothstep(0.08, 0.43, remaining_length)
	if lay_length < 0.012:
		return
	var normal: Vector3 = (_latched_contact["normal"] as Vector3).normalized()
	var hit_point: Vector3 = _latched_contact["position"]
	var before: Vector3 = world_transform * _point_on_pose(maxf(0.0, hit_t - 0.015), _latched_pose)
	var after: Vector3 = world_transform * _point_on_pose(minf(1.0, hit_t + 0.015), _latched_pose)
	var incoming := (after - before).slide(normal)
	var upward := Vector3.UP.slide(normal)
	var swing := Vector3.ZERO
	if not _previous_pose.is_empty():
		swing = (world_transform * _point_on_pose(hit_t, live_pose) - _previous_transform * _point_on_pose(hit_t, _previous_pose)).slide(normal)
	var heading := swing.normalized() if swing.length_squared() > 0.0001 else incoming.normalized()
	if upward.length_squared() > 0.0001:
		upward = upward.normalized()
		heading = (heading * 0.85 + upward * 0.30).normalized()
	else:
		upward = heading
	if heading.length_squared() < 0.0001:
		heading = (world_transform.basis.x).slide(normal).normalized()
	if phase == &"recovery" and _lay_heading.length_squared() > 0.0001:
		heading = _lay_heading.slide(normal).normalized()
	elif phase == &"active":
		_lay_heading = heading
	if heading.length_squared() < 0.0001:
		return
	var contact_rid := RID()
	if collider is CollisionObject3D:
		contact_rid = (collider as CollisionObject3D).get_rid()
	var inverse_basis := world_transform.basis.inverse()
	var width: float = _latched_pose["width"]
	var previous_center := base_world
	var previous_radius := _lay_radius_at(0.0, width, hit_t)
	_lay_offsets.append(Vector3.ZERO)
	for step in range(1, LAY_RINGS + 1):
		var u := float(step) / float(LAY_RINGS)
		var surface_shift := heading * (lay_length * 0.68 * u) + upward * (lay_length * 0.58 * sin(PI * u))
		var candidate := base_world + surface_shift
		var radius := _lay_radius_at(u, width, hit_t)
		var center := _surface_lay_center(candidate, normal, hit_point, radius, collider)
		if step == 1:
			center = base_world.lerp(center, 0.72)
		var obstruction := _cast_segment(previous_center, center, maxf(previous_radius, radius) + 0.025, exclude_rid, contact_rid)
		if not obstruction.is_empty():
			center = previous_center.lerp(center, maxf(0.0, float(obstruction["fraction"]) - 0.02))
			_lay_offsets.append(inverse_basis * (center - base_world))
			break
		_lay_offsets.append(inverse_basis * (center - base_world))
		previous_center = center
		previous_radius = radius


func _lay_radius_at(u: float, width: float, hit_t: float) -> float:
	var start_radius := _radius_at(hit_t, width) + 0.022
	var end_radius := maxf(0.025, 0.035 * width)
	return lerpf(start_radius, end_radius, u) * (1.0 - 0.15 * u)


func _surface_lay_center(candidate: Vector3, normal: Vector3, hit_point: Vector3, radius: float, collider: Object) -> Vector3:
	# Capsules need a changing normal; a tangent plane would visibly float off a round enemy.
	if collider is Node3D:
		var shape_node := (collider as Node3D).get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape_node != null and shape_node.shape is CapsuleShape3D:
			var capsule := shape_node.shape as CapsuleShape3D
			var local := shape_node.global_transform.affine_inverse() * candidate
			var stem := maxf(0.0, capsule.height * 0.5 - capsule.radius)
			var axis := Vector3(0.0, clampf(local.y, -stem, stem), 0.0)
			var radial := local - axis
			if radial.length_squared() < 0.0001:
				radial = shape_node.global_basis.inverse() * normal
			var surface := shape_node.global_transform * (axis + radial.normalized() * capsule.radius)
			var outward := (shape_node.global_basis * radial).normalized()
			return surface + outward * (radius + LAY_SURFACE_MARGIN)
	return candidate + normal * (radius + LAY_SURFACE_MARGIN - (candidate - hit_point).dot(normal))


func _push_clear_of_contact(world_center: Vector3, world_radius: float) -> Vector3:
	if _latched_contact.is_empty():
		return world_center
	var collider: Object = _latched_contact.get("collider")
	if not is_instance_valid(collider):
		return world_center
	var normal: Vector3 = (_latched_contact["normal"] as Vector3).normalized()
	var required := world_radius + LAY_SURFACE_MARGIN
	if collider is Node3D:
		var shape_node := (collider as Node3D).get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape_node != null and shape_node.shape is CapsuleShape3D:
			var capsule := shape_node.shape as CapsuleShape3D
			var local := shape_node.global_transform.affine_inverse() * world_center
			var stem := maxf(0.0, capsule.height * 0.5 - capsule.radius)
			var axis := Vector3(0.0, clampf(local.y, -stem, stem), 0.0)
			var radial := local - axis
			if radial.length_squared() < 0.0001:
				radial = shape_node.global_basis.inverse() * normal
			if radial.length_squared() < 0.0001:
				radial = Vector3.FORWARD
			var surface := shape_node.global_transform * (axis + radial.normalized() * capsule.radius)
			var outward := (shape_node.global_basis * radial).normalized()
			var clearance := (world_center - surface).dot(outward)
			if clearance < required:
				return world_center + outward * (required - clearance)
			return world_center
	# For a broad wall face the contact point and normal define its support plane.
	var hit_point: Vector3 = _latched_contact["position"]
	var clearance := (world_center - hit_point).dot(normal)
	if clearance < required:
		return world_center + normal * (required - clearance)
	return world_center

func _sample_lay_offset(progress: float) -> Vector3:
	if _lay_offsets.size() < 2:
		return Vector3.ZERO
	var position := clampf(progress, 0.0, 1.0) * float(_lay_offsets.size() - 1)
	var index := mini(int(floorf(position)), _lay_offsets.size() - 2)
	return _lay_offsets[index].lerp(_lay_offsets[index + 1], position - float(index))

func _clear_contact() -> void:
	_contact.clear()
	_latched_contact.clear()
	_latched_pose.clear()
	_previous_pose.clear()
	_previous_phase = &""
	_visible_extension = 0.0
	_impact_age = IMPACT_SECONDS
	_lay_age = 0.0
	_lay_offsets.clear()
	_lay_heading = Vector3.ZERO
	_wall_marked = false
	if is_instance_valid(_impact_mesh):
		_impact_mesh.hide()
		for droplet in _impact_droplets:
			droplet.hide()


func _pose_for_phase(phase: StringName, remaining: float, variant: int) -> Dictionary:
	var root_point := OVERHEAD_ROOT_POINT if variant == VARIANT_OVERHEAD else ROOT_POINT
	var control_a: Vector3
	var control_b: Vector3
	var tip: Vector3
	var width := 1.0
	var extension := 1.0
	match phase:
		&"preparation":
			var progress := clampf(1.0 - remaining / PREPARATION_SECONDS, 0.0, 1.0)
			var eased := progress * progress * (3.0 - 2.0 * progress)
			# Grow along the strike curve, so the active phase begins in the same pose.
			if variant == VARIANT_OVERHEAD:
				control_a = Vector3(-0.38, 0.56, -0.51)
				control_b = Vector3(-0.64, 0.96, -1.25)
				tip = Vector3(0.28, -0.12, -1.96)
			else:
				control_a = Vector3(0.78, 0.18, -0.53)
				control_b = Vector3(1.00, 0.38, -1.39)
				tip = Vector3(0.28, 0.07, -1.96)
			width = (0.55 + 0.45 * eased) * smoothstep(0.0, 0.45, eased)
			extension = eased
		&"active":
			var progress := clampf(1.0 - remaining / ACTIVE_SECONDS, 0.0, 1.0)
			if variant == VARIANT_OVERHEAD:
				control_a = Vector3(-0.38, 0.56, -0.51)
				control_b = Vector3(-0.64, 0.96, -1.25).lerp(Vector3(0.14, 0.51, -1.55), progress)
				tip = Vector3(0.28, -0.12, -1.96).lerp(Vector3(0.38, -0.23, -1.80), progress)
			else:
				control_a = Vector3(0.78, 0.18, -0.53)
				control_b = Vector3(1.00, 0.38, -1.39).lerp(Vector3(-0.80, 0.28, -1.38), progress)
				tip = Vector3(0.28, 0.07, -1.96).lerp(Vector3(-0.78, 0.04, -1.80), progress)
		&"recovery":
			var progress := clampf(1.0 - remaining / RECOVERY_SECONDS, 0.0, 1.0)
			if progress >= 0.72:
				return {}
			var eased := smoothstep(0.0, 0.72, progress)
			# Pull the visible tip back along the final strike curve into the buried root.
			if variant == VARIANT_OVERHEAD:
				control_a = Vector3(-0.38, 0.56, -0.51)
				control_b = Vector3(0.14, 0.51, -1.55)
				tip = Vector3(0.38, -0.23, -1.80)
			else:
				control_a = Vector3(0.78, 0.18, -0.53)
				control_b = Vector3(-0.80, 0.28, -1.38)
				tip = Vector3(-0.78, 0.04, -1.80)
			width = 1.0 - 0.55 * eased
			extension = lerpf(1.0, 0.12, eased)
		_:
			return {}
	if variant == VARIANT_LEFT:
		root_point.x = -root_point.x
		control_a.x = -control_a.x
		control_b.x = -control_b.x
		tip.x = -tip.x
	if extension <= 0.01:
		return {}
	return {
		"root": root_point,
		"control_a": control_a,
		"control_b": control_b,
		"tip": tip,
		"width": width,
		"extension": extension,
	}

func _scan_pose(pose: Dictionary, extension: float, exclude_rid: RID) -> Dictionary:
	var world_transform := global_transform
	var world_scale := _largest_basis_scale(world_transform.basis)
	for segment in range(CONTACT_SAMPLES):
		var start_t := extension * float(segment) / float(CONTACT_SAMPLES)
		var end_t := extension * float(segment + 1) / float(CONTACT_SAMPLES)
		var start_point: Vector3 = world_transform * _point_on_pose(start_t, pose)
		var end_point: Vector3 = world_transform * _point_on_pose(end_t, pose)
		var radius := maxf(_radius_at(start_t, float(pose["width"])), _radius_at(end_t, float(pose["width"]))) * world_scale
		var hit := _cast_segment(start_point, end_point, radius + CONTACT_MARGIN + CONTACT_BULGE, exclude_rid)
		if not hit.is_empty():
			var result := {
				"collider": hit["collider"],
				"position": hit["position"],
				"normal": hit["normal"],
				"clip_t": maxf(0.02, lerpf(start_t, end_t, float(hit["fraction"])) - 0.002),
			}
			return result
	return {}


func _scan_between_poses(previous: Dictionary, previous_transform: Transform3D, current: Dictionary, exclude_rid: RID) -> Dictionary:
	var shared_extension := minf(float(previous["extension"]), float(current["extension"]))
	var world_transform := global_transform
	var world_scale := maxf(_largest_basis_scale(previous_transform.basis), _largest_basis_scale(world_transform.basis))
	for sample in range(1, CONTACT_SAMPLES + 1):
		var curve_t := shared_extension * float(sample) / float(CONTACT_SAMPLES)
		var before: Vector3 = previous_transform * _point_on_pose(curve_t, previous)
		var after: Vector3 = world_transform * _point_on_pose(curve_t, current)
		if before.distance_squared_to(after) < 0.000001:
			continue
		var radius := maxf(_radius_at(curve_t, float(previous["width"])), _radius_at(curve_t, float(current["width"]))) * world_scale
		var hit := _cast_segment(before, after, radius + CONTACT_MARGIN + CONTACT_BULGE, exclude_rid)
		if hit.is_empty():
			continue
		var interpolated_pose := current.duplicate()
		var inverse := world_transform.affine_inverse()
		var fraction: float = hit["fraction"]
		for key in ["control_a", "control_b", "tip"]:
			var old_world: Vector3 = previous_transform * (previous[key] as Vector3)
			var new_world: Vector3 = world_transform * (current[key] as Vector3)
			interpolated_pose[key] = inverse * old_world.lerp(new_world, fraction)
		interpolated_pose["width"] = lerpf(float(previous["width"]), float(current["width"]), fraction)
		var result := {
			"collider": hit["collider"],
			"position": hit["position"],
			"normal": hit["normal"],
			"clip_t": maxf(0.02, curve_t - 0.002),
			"pose": interpolated_pose,
		}
		# The interpolated pose is checked again so the rounded cap does not
		# cross a wall between the sampled rings.
		var nearer := _scan_pose(interpolated_pose, curve_t, exclude_rid)
		if not nearer.is_empty() and float(nearer["clip_t"]) < float(result["clip_t"]):
			nearer["pose"] = interpolated_pose
			return nearer
		return result
	return {}


func _cast_segment(start_point: Vector3, end_point: Vector3, radius: float, exclude_rid: RID, ignored_rid: RID = RID()) -> Dictionary:
	var motion := end_point - start_point
	if motion.length_squared() < 0.0000001:
		return {}
	_cast_sphere.radius = maxf(0.01, radius)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _cast_sphere
	query.transform = Transform3D(Basis.IDENTITY, start_point)
	query.motion = motion
	query.margin = CONTACT_MARGIN
	query.collision_mask = CONTACT_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var excluded: Array[RID] = [exclude_rid]
	if ignored_rid.is_valid():
		excluded.append(ignored_rid)
	query.exclude = excluded
	var space := get_world_3d().direct_space_state
	var fractions := space.cast_motion(query)
	if fractions.size() < 2 or fractions[0] >= 0.999:
		return {}
	var safe_fraction := clampf(fractions[0], 0.0, 1.0)
	var unsafe_fraction := clampf(fractions[1], safe_fraction, 1.0)
	var normal := -motion.normalized()
	var position := start_point + motion * safe_fraction - normal * radius
	var collider: Object = null
	var probe_fraction := minf(1.0, unsafe_fraction + 0.012 / motion.length())
	query.motion = Vector3.ZERO
	query.transform = Transform3D(Basis.IDENTITY, start_point + motion * probe_fraction)
	query.margin = CONTACT_MARGIN + 0.012
	var rest := space.get_rest_info(query)
	if not rest.is_empty():
		collider = instance_from_id(int(rest.get("collider_id", 0)))
		position = rest.get("point", rest.get("position", position))
		normal = rest.get("normal", normal)
	if collider == null:
		var overlaps := space.intersect_shape(query, 1)
		if not overlaps.is_empty():
			collider = overlaps[0].get("collider")
	if collider == null:
		# A vanished collider is not a reliable contact to freeze on.
		return {}
	return {
		"collider": collider,
		"position": position,
		"normal": normal.normalized(),
		"fraction": safe_fraction,
	}


func _point_on_pose(curve_t: float, pose: Dictionary) -> Vector3:
	return _curve_point(curve_t, pose["root"], pose["control_a"], pose["control_b"], pose["tip"])


func _radius_at(curve_t: float, width: float) -> float:
	return (lerpf(0.14, 0.055, curve_t) + 0.025 * sin(PI * curve_t)) * width


func _largest_basis_scale(world_basis: Basis) -> float:
	return maxf(world_basis.x.length(), maxf(world_basis.y.length(), world_basis.z.length()))


func _activate_impact(contact: Dictionary) -> void:
	_impact_age = 0.0
	_lay_age = 0.0
	_place_impact(contact)
	_try_stamp_wall(contact)


func _try_stamp_wall(contact: Dictionary) -> void:
	if _wall_marked:
		return
	var collider: Object = contact.get("collider")
	var normal: Vector3 = contact.get("normal", Vector3.ZERO)
	if not collider is StaticBody3D or absf(normal.y) >= 0.60:
		return
	var mark_parent: Node = get_parent()
	while mark_parent != null and not mark_parent is SlimeController:
		mark_parent = mark_parent.get_parent()
	if mark_parent == null:
		return
	var player := mark_parent as SlimeController
	var tangent := Vector3.ZERO
	if not _latched_pose.is_empty():
		var hit_t: float = contact.get("clip_t", 1.0)
		var before := _point_on_pose(maxf(0.0, hit_t - 0.02), _latched_pose)
		var after := _point_on_pose(minf(1.0, hit_t + 0.02), _latched_pose)
		tangent = (global_basis * (after - before)).slide(normal)
	var mark := SlimeWallImpactMark.spawn(player, contact["position"], normal, tangent)
	_wall_marked = mark != null


func _place_impact(contact: Dictionary) -> void:
	var normal: Vector3 = contact["normal"]
	# The splash stays at the first physical contact while the loose end bends away.
	var point: Vector3 = contact["position"]
	var up := Vector3.FORWARD if absf(normal.dot(Vector3.UP)) > 0.96 else Vector3.UP
	var surface_basis := Basis.looking_at(-normal, up)
	_impact_mesh.global_transform = Transform3D(surface_basis, point + normal * 0.015)
	_impact_mesh.scale = Vector3(0.14, 0.12, 0.025)
	_impact_mesh.show()
	for index in range(_impact_droplets.size()):
		var angle := TAU * float(index) / float(_impact_droplets.size()) + 0.25
		var offset := surface_basis.x * cos(angle) * 0.13 + surface_basis.y * sin(angle) * 0.11
		var droplet := _impact_droplets[index]
		droplet.global_transform = Transform3D(surface_basis, point + offset + normal * 0.014)
		droplet.scale = Vector3(0.035, 0.029, 0.015)
		droplet.show()


func _process(delta: float) -> void:
	# The body moves in render time; keep the splash aligned with the contact.
	if _previous_phase == &"active" and not _latched_contact.is_empty():
		_place_impact(_latched_contact)
	if _previous_phase == &"active" and not _latched_contact.is_empty():
		_lay_age = minf(0.055, _lay_age + delta)
	if _impact_age >= IMPACT_SECONDS:
		return
	_impact_age = minf(IMPACT_SECONDS, _impact_age + delta)
	var pulse := 1.0 - _impact_age / IMPACT_SECONDS
	if pulse <= 0.0:
		_impact_mesh.hide()
		for droplet in _impact_droplets:
			droplet.hide()
		return
	var spread := 1.0 + 0.36 * (1.0 - pulse)
	_impact_mesh.scale = Vector3(0.14 * spread * pulse, 0.12 * spread * pulse, 0.025 * pulse)
	for index in range(_impact_droplets.size()):
		var size := (0.026 + float(index) * 0.006) * pulse
		_impact_droplets[index].scale = Vector3(size, size * 0.80, 0.015 * pulse)

func _draw_tendril(root_point: Vector3, control_a: Vector3, control_b: Vector3, tip: Vector3, width: float, extension: float, compression: float, lay_factor: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var use_lay := lay_factor > 0.02 and _lay_offsets.size() > 1 and absf(extension - float(_latched_contact.get("clip_t", -1.0))) < 0.002
	var body_rings := RINGS + (LAY_RINGS if use_lay else 0)
	var join := _curve_point(extension, root_point, control_a, control_b, tip)
	var join_correction := Vector3.ZERO
	var world_scale := _largest_basis_scale(global_basis)
	var inverse_transform := global_transform.affine_inverse()
	var last_center := root_point
	var last_tangent := Vector3.FORWARD
	var last_side := Vector3.RIGHT
	var last_radius := _radius_at(0.0, width)
	for ring in range(body_rings + CAP_RINGS + 1):
		var center: Vector3
		var tangent: Vector3
		var radius: float
		var cap_angle := 0.0
		if ring <= RINGS:
			var curve_t := float(ring) / float(RINGS) * extension
			center = _curve_point(curve_t, root_point, control_a, control_b, tip)
			var before := _curve_point(maxf(0.0, curve_t - 0.01), root_point, control_a, control_b, tip)
			var after := _curve_point(minf(extension, curve_t + 0.01), root_point, control_a, control_b, tip)
			tangent = (after - before).normalized()
			radius = _radius_at(curve_t, width) + 0.022 * compression * smoothstep(0.76, 1.0, float(ring) / float(RINGS))
		elif ring <= body_rings:
			var lay_t := float(ring - RINGS) / float(LAY_RINGS) * lay_factor
			var before_t := maxf(0.0, lay_t - 0.02)
			var after_t := minf(lay_factor, lay_t + 0.02)
			center = join + _sample_lay_offset(lay_t) + join_correction * (1.0 - smoothstep(0.0, 0.5, lay_t))
			var before := join + _sample_lay_offset(before_t) + join_correction * (1.0 - smoothstep(0.0, 0.5, before_t))
			var after := join + _sample_lay_offset(after_t) + join_correction * (1.0 - smoothstep(0.0, 0.5, after_t))
			tangent = (after - before).normalized()
			radius = _lay_radius_at(lay_t, width, extension)
		else:
			center = last_center
			tangent = last_tangent
			cap_angle = 0.5 * PI * float(ring - body_rings) / float(CAP_RINGS)
			center += tangent * last_radius * sin(cap_angle) * (1.0 if use_lay else 1.0 - 0.62 * compression)
			radius = maxf(0.002 * width, last_radius * cos(cap_angle))
		if ring >= RINGS - 6 and ring <= body_rings and not _latched_contact.is_empty():
			var pushed_world := _push_clear_of_contact(global_transform * center, radius * world_scale)
			center = inverse_transform * pushed_world
			if ring == RINGS:
				join_correction = center - join
		if tangent.length_squared() < 0.0001:
			tangent = last_tangent
		var side_axis := last_side - tangent * last_side.dot(tangent)
		if ring == 0 or side_axis.length_squared() < 0.0001:
			side_axis = tangent.cross(Vector3.UP)
			if side_axis.length_squared() < 0.0001:
				side_axis = tangent.cross(Vector3.RIGHT)
		side_axis = side_axis.normalized()
		var up_axis := side_axis.cross(tangent).normalized()
		for side in range(SIDES + 1):
			var angle := TAU * float(side) / float(SIDES)
			var radial := (side_axis * cos(angle) + up_axis * sin(angle)).normalized()
			var normal := (radial * cos(cap_angle) + tangent * sin(cap_angle)).normalized()
			surface.set_normal(normal)
			surface.set_uv(Vector2(minf(1.0, float(ring) / float(body_rings)), float(side) / float(SIDES)))
			surface.add_vertex(center + radial * radius)
		if ring <= body_rings:
			last_center = center
			last_radius = radius
		last_tangent = tangent
		last_side = side_axis
	var stride := SIDES + 1
	for ring in range(body_rings + CAP_RINGS):
		for side in range(SIDES):
			var a := ring * stride + side
			var b := a + stride
			surface.add_index(a)
			surface.add_index(b)
			surface.add_index(a + 1)
			surface.add_index(a + 1)
			surface.add_index(b)
			surface.add_index(b + 1)
	_mesh_instance.mesh = surface.commit()

func _curve_point(t: float, root_point: Vector3, control_a: Vector3, control_b: Vector3, tip: Vector3) -> Vector3:
	var inverse := 1.0 - t
	return root_point * inverse * inverse * inverse + control_a * 3.0 * inverse * inverse * t + control_b * 3.0 * inverse * t * t + tip * t * t * t