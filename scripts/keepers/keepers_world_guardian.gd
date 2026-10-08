extends ExitGuardian
class_name SlimeKeepersWorldGuardian

var movement_guide: Callable

# Environmental mechanisms use the existing hit/death/source pipeline.
func receive_environment_hit(amount: int, cast_key: String) -> bool:
	return super.receive_hit(amount, cast_key, &"player")


func _move(wish: Vector3, delta: float) -> void:
	var direction := wish
	if _phase != &"windup" and direction.length_squared() > 0.001 and movement_guide.is_valid():
		direction = movement_guide.call(self, direction)
	super._move(direction, delta)
