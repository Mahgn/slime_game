extends Node
class_name SlimeIsometricInput

const MOVEMENT_BASIS := Basis(Vector3.UP, PI / 4.0)

@onready var player: SlimeController = get_parent()

var pointer := Vector2.ZERO


func _ready() -> void:
	refresh_pointer()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _notification(what: int) -> void:
	if what == NOTIFICATION_UNPAUSED and is_inside_tree():
		refresh_pointer()


func refresh_pointer() -> void:
	pointer = get_viewport().get_mouse_position()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pointer = event.position
	elif event is InputEventMouseButton:
		pointer = event.position
	if event is InputEventMouseButton and event.pressed and not get_tree().paused:
		var minimum := 7.0 if player.get_parent().has_meta(&"isometric_exploration") else 9.0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			player.presentation.zoom_target = clampf(player.presentation.zoom_target - 1.0, minimum, 22.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			player.presentation.zoom_target = clampf(player.presentation.zoom_target + 1.0, minimum, 22.0)


func screen_movement_direction(axes: Vector2) -> Vector3:
	return (MOVEMENT_BASIS.x * axes.x + MOVEMENT_BASIS.z * axes.y).normalized()


func world_direction_to_screen_axes(direction: Vector3) -> Vector2:
	return Vector2(direction.dot(MOVEMENT_BASIS.x), direction.dot(MOVEMENT_BASIS.z))


func get_aim_point() -> Vector3:
	var presentation: SlimeIsometricPresentation = player.presentation
	var camera: Camera3D = presentation.camera
	var origin := camera.project_ray_origin(pointer)
	var direction := camera.project_ray_normal(pointer)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 180.0, 5)
	var ignored: Array[RID] = [player.get_rid()]
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
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if is_instance_valid(presentation.room_cutaway):
		for surface in 24:
			if hit.is_empty() or not hit["collider"] is CollisionObject3D:
				break
			if not presentation.room_cutaway.is_point_cut(hit["collider"], hit["position"]):
				break
			query.from = hit["position"] + direction * 0.01
			hit = player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit["collider"] is CharacterBody3D:
		var target := hit["collider"] as CharacterBody3D
		return target.global_position + Vector3.UP * 0.45
	# Keep the accepted combat plane when the cursor is not on a visible actor.
	var plane := Plane(Vector3.UP, player.global_position.y + player._combat_origin_height())
	var point: Variant = plane.intersects_ray(origin, direction)
	return point if point != null else player.global_position - MOVEMENT_BASIS.z * 5.0
