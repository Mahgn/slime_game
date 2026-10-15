extends SlimeController

func request_action(action_id: StringName) -> bool:
	# Workshop buttons are mouse-operated and must not fire a weapon underneath.
	if get_viewport().gui_get_hovered_control() != null:
		return false
	return super.request_action(action_id)
