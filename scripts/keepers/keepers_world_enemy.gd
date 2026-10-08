extends BorrowableEnemy
class_name SlimeKeepersWorldEnemy

var movement_guide: Callable

# Environmental mechanisms use the existing hit/death/source pipeline.
func receive_environment_hit(amount: int, cast_key: String) -> bool:
	return super.receive_hit(amount, cast_key, &"player")


func _move(wish: Vector3, delta: float) -> void:
	var direction := wish
	if _phase == &"approach" and direction.length_squared() < 0.001 and is_instance_valid(player_target) and player_target.is_alive() and not _has_line_of_sight():
		direction = player_target.global_position - global_position
		direction.y = 0.0
		direction = direction.normalized()
	if _phase != &"windup" and direction.length_squared() > 0.001 and movement_guide.is_valid():
		direction = movement_guide.call(self, direction)
	super._move(direction, delta)
