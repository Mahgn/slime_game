extends SlimeController
class_name SlimeIsometricController

const PRESENTATION = preload("res://scripts/isometric/isometric_presentation.gd")
const CAMERA_YAW := PI / 4.0
# Trial response for this game, not measured Hades coefficients.
const ISOMETRIC_GROUND_ACCELERATION := 65.0
const ISOMETRIC_GROUND_BRAKING := 85.0

var presentation: Node3D
var pointer := Vector2.ZERO


func _ready() -> void:
	super._ready()
	pointer = get_viewport().get_visible_rect().size * 0.5
	# Keep physical movement, actions, absorption and the animated v5 hero.
	# The separate camera no longer inherits crouching or body rotation.
	camera_yaw.set_as_top_level(true)
	camera_yaw.global_rotation = Vector3(0.0, CAMERA_YAW, 0.0)
	spring_arm.collision_mask = 0
	# The legacy arm must not move the independent camera during physics ticks.
	spring_arm.set_physics_process_internal(false)
	camera.set_as_top_level(true)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 13.0
	camera.near = 0.1
	camera.far = 140.0
	presentation = PRESENTATION.new()
	presentation.name = "IsometricPresentation"
	presentation.player = self
	add_child(presentation)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pointer = event.position
	if event is InputEventMouseButton and event.pressed and not get_tree().paused:
		var minimum := 7.0 if get_parent().has_meta(&"isometric_exploration") else 9.0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			presentation.zoom_target = clampf(presentation.zoom_target - 1.0, minimum, 22.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			presentation.zoom_target = clampf(presentation.zoom_target + 1.0, minimum, 22.0)


func _follow_camera_heading(delta: float) -> void:
	camera_yaw.global_rotation = Vector3(0.0, CAMERA_YAW, 0.0)
	var aim_direction := _get_camera_aim_point() - global_position
	aim_direction.y = 0.0
	if _action != &"":
		aim_direction = _action_direction
	if aim_direction.length_squared() > 0.01:
		var local_direction := global_basis.inverse() * aim_direction
		visual_root.rotation.y = lerp_angle(visual_root.rotation.y,
			atan2(-local_direction.x, -local_direction.z), minf(1.0, delta * 18.0))


func _update_horizontal_velocity(target: Vector3, axes: Vector2, grounded: bool, delta: float) -> void:
	var acceleration := AIR_ACCELERATION
	if grounded:
		acceleration = ISOMETRIC_GROUND_ACCELERATION if axes.length_squared() > 0.0 else ISOMETRIC_GROUND_BRAKING
	# Limit the change of the entire horizontal vector, so screen directions
	# share one response and turning cannot retain an extra diagonal speed.
	var horizontal := Vector2(velocity.x, velocity.z)
	horizontal = horizontal.move_toward(Vector2(target.x, target.z), acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y


func _get_camera_aim_point() -> Vector3:
	var origin := camera.project_ray_origin(pointer)
	var direction := camera.project_ray_normal(pointer)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 180.0, 5)
	query.exclude = [get_rid()]
	if is_instance_valid(presentation):
		var ignored: Array[RID] = [get_rid()]
		for actor in presentation.hidden_actors:
			if is_instance_valid(actor) and actor is CollisionObject3D:
				ignored.append(actor.get_rid())
		for mesh in presentation.hidden:
			if not is_instance_valid(mesh):
				continue
			var ancestor: Node = mesh.get_parent()
			while ancestor != null:
				if ancestor is CollisionObject3D:
					var rid: RID = ancestor.get_rid()
					if not ignored.has(rid):
						ignored.append(rid)
					break
				ancestor = ancestor.get_parent()
		query.exclude = ignored
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit["collider"] is CharacterBody3D:
		var target := hit["collider"] as CharacterBody3D
		return target.global_position + Vector3.UP * 0.45
	# Attack in the plane of the slime's current floor. A cursor on a
	# foreground cutaway wall must not make a horizontal spit dive into it.
	var plane := Plane(Vector3.UP, global_position.y + _combat_origin_height())
	var point: Variant = plane.intersects_ray(origin, direction)
	return point if point != null else global_position - camera_yaw.global_basis.z * 5.0
