extends StaticBody3D

var mechanism: Node3D


func receive_dungeon_property(ability_id: StringName, rank: int) -> bool:
	if not is_instance_valid(mechanism):
		return false
	return bool(mechanism.call("receive_dungeon_property", ability_id, rank))
