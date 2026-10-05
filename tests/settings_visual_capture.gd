extends SceneTree

# Windowed capture of the real launch screen and R01 pause menu.
# Run with --resolution WxH --script res://tests/settings_visual_capture.gd -- WxH.

const LAUNCH_SCENE = preload("res://scenes/launch.tscn")
const R01_SCENE = preload("res://scenes/r01_entrance.tscn")
const R02_SCENE = preload("res://scenes/main.tscn")
const OUTPUT := "res://output/S5/settings/visual/"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var tag := "unknown"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		tag = args[0]
	print("VISUAL tag=%s window=%s viewport=%s" % [tag, DisplayServer.window_get_size(), root.size])

	var launch := LAUNCH_SCENE.instantiate()
	root.add_child(launch)
	await _frames(15)
	_save(tag, "launch")
	launch.call("_show_settings")
	await _frames(10)
	var launch_settings := launch.get_node("SettingsPanel") as SlimeSettingsPanel
	_measure_settings(launch_settings, tag, "launch")
	_save(tag, "launch_settings")
	var checkboxes := launch_settings.find_children("*", "CheckBox", true, false)
	print("CHECKBOXES %s count=%d" % [tag, checkboxes.size()])
	if checkboxes.size() == 2:
		var invert_box := checkboxes[0] as CheckBox
		invert_box.button_pressed = true
		await _frames(3)
		_save(tag, "launch_settings_checked")
		invert_box.button_pressed = false
		await _frames(3)
	else:
		push_error("Expected two settings checkboxes")
	launch.queue_free()
	await _frames(3)

	var room := R01_SCENE.instantiate()
	root.add_child(room)
	await _frames(18)
	room.call("_pause_game")
	await _frames(8)
	_save(tag, "r01_pause")
	var pause_menu := room.get("_pause_panel") as SlimePauseMenu
	pause_menu.call("_open_settings")
	await _frames(8)
	var settings := pause_menu.get_child(1)
	_measure_settings(settings, tag, "r01_pause")
	_save(tag, "r01_pause_settings")
	if tag == "1280x720":
		room.queue_free()
		await _frames(3)
		var battle := R02_SCENE.instantiate()
		root.add_child(battle)
		await _frames(18)
		battle.call("_pause_game")
		await _frames(6)
		var battle_pause := battle.get("_pause_menu") as SlimePauseMenu
		battle_pause.call("_open_settings")
		await _frames(6)
		_measure_settings(battle_pause.get_child(1), tag, "r02_pause")
		_save(tag, "r02_pause_settings")
	quit()


func _measure_settings(settings: Control, tag: String, context: String) -> void:
	var panel := settings.get_child(1) as Control
	print("LAYOUT %s %s viewport=%s panel=%s" % [tag, context, root.size, panel.get_global_rect()])
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(root.size))
	if not viewport_rect.encloses(panel.get_global_rect()):
		push_error("Settings panel extends outside the viewport at %s %s" % [tag, context])


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _save(tag: String, name: String) -> void:
	var path := ProjectSettings.globalize_path(OUTPUT + tag + "_" + name + ".png")
	var image := root.get_texture().get_image()
	var result := image.save_png(path)
	print("CAPTURE %s size=%s code=%d" % [path, image.get_size(), result])
	if result != OK:
		push_error("Cannot save capture: %s" % path)
