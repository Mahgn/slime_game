extends Node
class_name SlimeIsometricInput

const MOVEMENT_BASIS := Basis(Vector3.UP, PI / 4.0)
const CAMERA_DRAG_THRESHOLD := 48.0
const FREE_DRAG_THRESHOLD := 3.0

@onready var player: SlimeController = get_parent()

var pointer := Vector2.ZERO
var _camera_dragging := false
var _camera_drag_used := false
var _camera_drag_distance := 0.0
var _camera_captured := false


func _ready() -> void:
	refresh_pointer()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _notification(what: int) -> void:
	if what in [NOTIFICATION_PAUSED, NOTIFICATION_UNPAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		_cancel_camera_drag(what != NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	if what == NOTIFICATION_UNPAUSED and is_inside_tree():
		refresh_pointer()


func _process(_delta: float) -> void:
	if _camera_dragging and not player.is_alive():
		_cancel_camera_drag()


func _exit_tree() -> void:
	_cancel_camera_drag(false)


func refresh_pointer() -> void:
	pointer = get_viewport().get_mouse_position()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not _camera_captured:
		pointer = event.position
	elif event is InputEventMouseButton and not _camera_captured:
		pointer = event.position
	if _camera_gesture(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and not get_tree().paused:
		var minimum := 7.0 if player.get_parent().has_meta(&"isometric_exploration") else 9.0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			player.presentation.zoom_target = clampf(player.presentation.zoom_target - 1.0, minimum, 22.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			player.presentation.zoom_target = clampf(player.presentation.zoom_target + 1.0, minimum, 22.0)


func _camera_gesture(event: InputEvent) -> bool:
	var view: SlimeIsometricPresentation = player.presentation
	if not is_instance_valid(view) or not view.quarter_turns_enabled:
		return false
	if get_tree().paused or not player.is_alive():
		_cancel_camera_drag()
		return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_cancel_camera_drag()
		_camera_dragging = event.pressed and not view.is_camera_turning()
		if _camera_dragging and view.free_rotation_enabled:
			# Relative motion can continue past the screen edge. Keep the aiming
			# cursor at its screen anchor and return it there on release.
			_camera_captured = true
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return true
	if event is InputEventMouseMotion and _camera_dragging:
		if not (event.button_mask & MOUSE_BUTTON_MASK_MIDDLE):
			_cancel_camera_drag()
			return false
		_camera_drag_distance += event.relative.x
		if view.free_rotation_enabled:
			var pixels: float = event.relative.x
			if not _camera_drag_used:
				if absf(_camera_drag_distance) <= FREE_DRAG_THRESHOLD:
					return true
				_camera_drag_used = true
				pixels = _camera_drag_distance - signf(_camera_drag_distance) * FREE_DRAG_THRESHOLD
			view.rotate_free(pixels)
			return true
		if not _camera_drag_used and absf(_camera_drag_distance) >= CAMERA_DRAG_THRESHOLD:
			_camera_drag_used = true
			view.request_quarter_turn(-1 if _camera_drag_distance > 0.0 else 1)
		return true
	return false


func _cancel_camera_drag(restore_pointer: bool = true) -> void:
	if _camera_captured:
		_camera_captured = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if restore_pointer and is_inside_tree():
			get_viewport().warp_mouse(pointer)
	_camera_dragging = false
	_camera_drag_used = false
	_camera_drag_distance = 0.0


func _movement_basis() -> Basis:
	return player.presentation.movement_basis() if is_instance_valid(player.presentation) else MOVEMENT_BASIS


func screen_movement_direction(axes: Vector2) -> Vector3:
	var basis := _movement_basis()
	return (basis.x * axes.x + basis.z * axes.y).normalized()


func world_direction_to_screen_axes(direction: Vector3) -> Vector2:
	var basis := _movement_basis()
	return Vector2(direction.dot(basis.x), direction.dot(basis.z))


func get_aim_point() -> Vector3:
	var presentation: SlimeIsometricPresentation = player.presentation
	var camera: Camera3D = presentation.camera
	# Camera impact is presentation only: a stationary cursor keeps its world aim.
	var origin := camera.project_ray_origin(pointer) - presentation.get_combat_camera_offset()
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
	return point if point != null else player.global_position - _movement_basis().z * 5.0
