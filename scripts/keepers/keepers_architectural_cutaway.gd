extends SlimeRoomCutaway

# The facility has one full-height shell. Preserve the camera API without
# introducing per-room, per-side or player-driven wall clipping.
var structural_sections: Array[Dictionary] = []

func configure_building(_rooms: Dictionary, _connections: Array) -> void:
	for section: Dictionary in structural_sections:
		section.node.show()
		if section.body.has_meta(&"architectural_cut_height"):
			section.body.remove_meta(&"architectural_cut_height")

func update_view(_player: SlimeController, _camera: Camera3D, _delta: float = 0.0) -> void:
	pass

func is_point_cut(_collider: Object, _point: Vector3) -> bool:
	return false
