extends RefCounted


static func install() -> void:
	_bind_key(&"move_forward", KEY_W)
	_bind_key(&"move_back", KEY_S)
	_bind_key(&"move_left", KEY_A)
	_bind_key(&"move_right", KEY_D)
	_bind_key(&"jump", KEY_SPACE)
	_bind_key(&"interact", KEY_E)
	_bind_key(&"ability_slot_2", KEY_Q)
	_bind_key(&"open_loadout", KEY_TAB)
	_bind_key(&"pause", KEY_ESCAPE)
	_bind_key(&"debug_overlay", KEY_F3)
	_bind_mouse(&"attack_primary", MOUSE_BUTTON_LEFT)
	_bind_mouse(&"ability_slot_1", MOUSE_BUTTON_RIGHT)


static func _bind_key(action: StringName, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)


static func _bind_mouse(action: StringName, button: MouseButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)
