extends Node3D
class_name FirstFloorRopeTarget

signal released

var _released := false
var release_permission: Callable


func _ready() -> void:
	add_to_group(&"training_targets")


func receive_hit(amount: int, cast_key: String, source_team: StringName) -> bool:
	if _released or source_team != &"player" or amount <= 0 or cast_key.is_empty():
		return false
	if release_permission.is_valid() and not release_permission.call():
		return false
	_released = true
	released.emit()
	return true
