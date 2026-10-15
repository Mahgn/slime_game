extends "res://scripts/dungeon/dungeon_player.gd"

func request_action(action_id: StringName) -> bool:
	if get_viewport().gui_get_hovered_control() != null:
		return false
	return super.request_action(action_id)
