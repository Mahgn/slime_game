extends SceneTree

# S5 regression: focus-loss notification pauses each route implementation.
# This is a handler test; real Windows Alt-Tab still needs a window check.

const ROOM_CASES := [
	{"id": "R01", "path": "res://scenes/r01_entrance.tscn", "menu": "_pause_panel"},
	{"id": "R02", "path": "res://scenes/main.tscn", "menu": "_pause_menu"},
	{"id": "R05", "path": "res://scenes/r05_mixed.tscn", "menu": "_pause_panel"},
	{"id": "R07", "path": "res://scenes/r07_guardian.tscn", "menu": "_pause_panel"},
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	set_meta(&"checkpoint_active", false)
	var all_passed := true
	for spec: Dictionary in ROOM_CASES:
		all_passed = (await _check_room(spec)) and all_passed
	print("PASS S5_FOCUS_LOSS" if all_passed else "FAIL S5_FOCUS_LOSS")
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _dispose_current_scene()
	quit(0 if all_passed else 1)


func _check_room(spec: Dictionary) -> bool:
	var room := await _open_room(String(spec["path"]))
	if not is_instance_valid(room):
		print("FAIL S5_FOCUS_%s scene load" % spec["id"])
		return false
	var player := room.get_node_or_null("SlimePlayer") as SlimeController
	var menu := room.get(String(spec["menu"])) as SlimePauseMenu
	if not is_instance_valid(player) or not is_instance_valid(menu):
		print("FAIL S5_FOCUS_%s player/menu missing" % spec["id"])
		return false
	for enemy: Node in get_nodes_in_group(&"enemies"):
		enemy.set("player_target", null)
	player.set("_absorb_elapsed", 0.25)
	player.set("_cooldowns", {&"sticky_spit": 1.0})
	room.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var paused_on_loss := paused and menu.is_visible_in_tree()
	var absorb_cancelled := (
		is_zero_approx(float(player.get("_absorb_elapsed")))
		and bool(player.get("_absorb_requires_release"))
	)
	var has_window := DisplayServer.get_name() != "headless"
	var cursor_released := not has_window or Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
	await create_timer(0.14, true).timeout
	var cooldown_stopped := is_equal_approx(float((player.get("_cooldowns") as Dictionary).get(&"sticky_spit", -1.0)), 1.0)
	room.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await process_frame
	var stays_paused := paused and menu.is_visible_in_tree()
	var escape := InputEventAction.new()
	escape.action = &"pause"
	escape.pressed = true
	room.call("_input", escape)
	var explicit_resume := not paused and not menu.is_visible_in_tree()
	var cursor_recaptured := not has_window or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var collection_case := true
	if spec["id"] == "R05" or spec["id"] == "R07":
		room.set("_collection_open", true)
		room.call("_update_pause_state")
		room.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		room.call("_input", escape)
		collection_case = paused and not bool(room.get("_collection_open")) and menu.is_visible_in_tree()
		room.call("_input", escape)
		collection_case = collection_case and not paused and not menu.is_visible_in_tree()
	var passed := paused_on_loss and absorb_cancelled and cursor_released and cooldown_stopped and stays_paused and explicit_resume and cursor_recaptured and collection_case
	print("S5_FOCUS_%s loss=%s absorb=%s cursor_visible=%s timer=%s focus_return=%s explicit_resume=%s cursor_capture=%s collection=%s" % [
		spec["id"], paused_on_loss, absorb_cancelled,
		str(cursor_released) if has_window else "BLOCKED_HEADLESS", cooldown_stopped,
		stays_paused, explicit_resume,
		str(cursor_recaptured) if has_window else "BLOCKED_HEADLESS", collection_case
	])
	print("PASS S5_FOCUS_%s" % spec["id"] if passed else "FAIL S5_FOCUS_%s" % spec["id"])
	return passed


func _open_room(scene_path: String) -> Node3D:
	await _dispose_current_scene()
	paused = false
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return null
	var room := scene.instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	for tick in 5:
		await physics_frame
	return room


func _dispose_current_scene() -> void:
	paused = false
	if is_instance_valid(current_scene):
		var old_scene := current_scene
		current_scene = null
		old_scene.queue_free()
	for tick in 4:
		await physics_frame
