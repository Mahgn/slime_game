extends SlimeIsometricPresentation

var higher_view := false
var pitch := atan2(13.9, sqrt(288.0))

func _update_camera(delta: float) -> void:
	var target := deg_to_rad(60.0) if higher_view else atan2(13.9, sqrt(288.0))
	pitch = target if delta == 0.0 else move_toward(pitch, target, delta * 0.8)
	super._update_camera(delta)

func _view_offset() -> Vector3:
	return Vector3(12.0, sqrt(288.0)*tan(pitch), 12.0).rotated(Vector3.UP, camera_yaw)

func back_at_yaw(yaw: float) -> Vector3:
	return Vector3(12.0, sqrt(288.0)*tan(pitch), 12.0).rotated(Vector3.UP,yaw).normalized()
