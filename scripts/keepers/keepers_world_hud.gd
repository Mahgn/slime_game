extends SlimeKeepersRunHUD


func _build_hud() -> void:
	super._build_hud()
	# Wrapped room copy owns its height. Fixed Y offsets used to put the list
	# of exits over the second line of the room description at 720p.
	var room_copy := VBoxContainer.new()
	room_copy.name = "RoomInformation"
	room_copy.anchor_right = 0.66
	room_copy.offset_left = 24
	room_copy.offset_right = -24
	room_copy.offset_top = 13
	room_copy.add_theme_constant_override("separation",6)
	room_copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.add_child(room_copy)
	for label: Label in [_title,_objective,_navigation]:
		label.reparent(room_copy)
		label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		label.size = Vector2.ZERO
		label.size_flags_horizontal = Control.SIZE_FILL
	_navigation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_navigation.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING


func _navigation_text(room: Dictionary) -> String:
	if String(_route.get("room_id")) == "summit":
		return "К свету — по пандусу. Можно вернуться тем же путём."
	if bool(room.get("secret", false)):
		return "Тайное место · обратный путь остаётся открытым"
	var titles: PackedStringArray = []
	var world_rooms: Dictionary = _route.get("rooms")
	for destination in room.get("links", []):
		if not world_rooms[destination].get("secret", false):
			titles.append(world_rooms[destination].title)
	return "Проходы: " + " · ".join(titles)
