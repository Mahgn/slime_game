extends Node

const INPUT_SETUP = preload("res://scripts/input_setup.gd")
const TEST_PATH := "res://output/level_cleanup/test_settings.cfg"
const ROOM_CASES := [
	["FIXTURE", "res://tests/helpers/combat_fixture.tscn", "_pause_panel"],
	["WORKSPACE", "res://scenes/level_workspace.tscn", "_pause_panel"],
	["OPENING", "res://scenes/opening/opening_route.tscn", "_pause_panel"],
]

var _failures := 0
var _blocked := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	INPUT_SETUP.install()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_PATH.get_base_dir()))
	get_tree().set_meta(&"checkpoint_active", false)
	_remove_test_file()
	_report("SETTINGS_DEFAULTS_BUSES", _check_defaults_and_buses())
	_report("SETTINGS_SAVE_RELOAD", _check_save_reload())
	_report("SETTINGS_INVALID_VALUES", _check_invalid_values())
	if DisplayServer.get_name() != "headless":
		_ambient_status("before_ui", GameSettings.get_node_or_null("CavernAmbience") as AudioStreamPlayer)
	_report("SETTINGS_UI_PAUSED", await _check_settings_ui())
	_report("SETTINGS_ISOMETRIC_POINTER", await _check_mouse_input())
	if DisplayServer.get_name() == "headless":
		_blocked += 2
		print("BLOCKED SETTINGS_AMBIENCE_PAUSE: headless display has no audio player")
		print("BLOCKED SETTINGS_FULLSCREEN: headless display has no window")
	else:
		_report("SETTINGS_AMBIENCE_PAUSE", await _check_ambience_pause())
		_report("SETTINGS_FULLSCREEN", await _check_fullscreen_toggle())
	for room_case in ROOM_CASES:
		_report("PAUSE_%s" % room_case[0], await _check_room_pause(room_case))
	_report("PAUSE_TIMERS", await _check_pause_timers())
	_report("PAUSE_MENU_RETURN", await _check_menu_return())
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_remove_test_file()
	GameSettings.load_settings(GameSettings.FILE_PATH)
	print("SETTINGS_SUMMARY: %d failed, %d blocked" % [_failures, _blocked])
	get_tree().quit(1 if _failures > 0 else 0)


func _check_defaults_and_buses() -> bool:
	var read_result: Error = GameSettings.load_settings(TEST_PATH)
	var effects_index := AudioServer.get_bus_index(&"Effects")
	var ambience_index := AudioServer.get_bus_index(&"Ambience")
	var defaults := (
		read_result == ERR_FILE_NOT_FOUND
		and is_equal_approx(GameSettings.master_volume, 1.0)
		and is_equal_approx(GameSettings.effects_volume, 1.0)
		and is_equal_approx(GameSettings.ambience_volume, 0.6)
		and is_equal_approx(GameSettings.mouse_sensitivity_scale, 1.0)
		and not GameSettings.invert_y
		and is_zero_approx(GameSettings.camera_shake)
		and not GameSettings.fullscreen
	)
	return (
		defaults
		and effects_index > 0
		and ambience_index > 0
		and AudioServer.get_bus_send(effects_index) == &"Master"
		and AudioServer.get_bus_send(ambience_index) == &"Master"
	)


func _check_save_reload() -> bool:
	GameSettings.set_master_volume(0.65)
	GameSettings.set_effects_volume(0.45)
	GameSettings.set_ambience_volume(0.25)
	GameSettings.set_mouse_sensitivity_scale(1.55)
	GameSettings.set_invert_y(true)
	GameSettings.set_camera_shake(0.35)
	GameSettings.set_fullscreen(false)
	var master_index := AudioServer.get_bus_index(&"Master")
	var effects_index := AudioServer.get_bus_index(&"Effects")
	var ambience_index := AudioServer.get_bus_index(&"Ambience")
	var applied := _bus_at(master_index, 0.65) and _bus_at(effects_index, 0.45) and _bus_at(ambience_index, 0.25)
	if GameSettings.save_settings() != OK:
		return false
	GameSettings.set_master_volume(1.0)
	GameSettings.set_effects_volume(1.0)
	GameSettings.set_ambience_volume(1.0)
	GameSettings.set_mouse_sensitivity_scale(0.25)
	GameSettings.set_invert_y(false)
	GameSettings.set_camera_shake(0.0)
	if GameSettings.load_settings(TEST_PATH) != OK:
		return false
	var restored := (
		is_equal_approx(GameSettings.master_volume, 0.65)
		and is_equal_approx(GameSettings.effects_volume, 0.45)
		and is_equal_approx(GameSettings.ambience_volume, 0.25)
		and is_equal_approx(GameSettings.mouse_sensitivity_scale, 1.55)
		and is_equal_approx(GameSettings.camera_shake, 0.35)
	)
	return (
		applied
		and restored
		and _bus_at(master_index, 0.65)
		and _bus_at(effects_index, 0.45)
		and _bus_at(ambience_index, 0.25)
	)


func _check_invalid_values() -> bool:
	var config := ConfigFile.new()
	config.set_value("audio", "master", "invalid")
	config.set_value("audio", "effects", -3.0)
	config.set_value("audio", "ambience", 8.0)
	config.set_value("controls", "mouse_sensitivity", 99.0)
	config.set_value("controls", "invert_y", 2)
	config.set_value("controls", "camera_shake", -1.0)
	config.set_value("display", "fullscreen", "true")
	if config.save(TEST_PATH) != OK or GameSettings.load_settings(TEST_PATH) != OK:
		return false
	var values := (
		is_equal_approx(GameSettings.master_volume, 1.0)
		and is_zero_approx(GameSettings.effects_volume)
		and is_equal_approx(GameSettings.ambience_volume, 1.0)
		and is_equal_approx(GameSettings.mouse_sensitivity_scale, 2.0)
		and not GameSettings.invert_y
		and is_zero_approx(GameSettings.camera_shake)
		and not GameSettings.fullscreen
	)
	return values and AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Effects"))


func _check_settings_ui() -> bool:
	GameSettings.load_settings(TEST_PATH)
	var menu := SlimePauseMenu.new()
	get_tree().root.add_child(menu)
	await get_tree().process_frame
	get_tree().paused = true
	menu.call("_open_settings")
	var panel := menu.get("_settings") as SlimeSettingsPanel
	var slider := _find_slider(panel, "Эффекты")
	var checkbox := _find_checkbox(panel, "Полноэкранный режим")
	var opened := (
		panel != null
		and panel.visible
		and not (menu.get("_main_box") as Control).visible
		and slider != null
		and checkbox != null
	)
	if opened:
		slider.value = 0.55
	var closed := menu.dismiss_submenu()
	var saved := ConfigFile.new()
	var persisted: bool = (
		saved.load(TEST_PATH) == OK
		and is_equal_approx(float(saved.get_value("audio", "effects", -1.0)), 0.55)
	)
	var state: bool = (
		closed
		and not panel.visible
		and (menu.get("_main_box") as Control).visible
		and get_tree().paused
		and is_equal_approx(GameSettings.effects_volume, 0.55)
		and persisted
	)
	menu.queue_free()
	get_tree().paused = false
	await get_tree().process_frame
	return opened and state


func _check_room_pause(room_case: Array) -> bool:
	get_tree().set_meta(&"checkpoint_active", false)
	var room := (load(room_case[1]) as PackedScene).instantiate()
	get_tree().root.add_child(room)
	await get_tree().process_frame
	var menu := room.get(room_case[2]) as SlimePauseMenu
	if menu == null:
		room.queue_free()
		await get_tree().process_frame
		return false
	var escape := InputEventAction.new()
	escape.action = &"pause"
	escape.pressed = true
	room.call("_input", escape)
	var entered := get_tree().paused and menu.is_visible_in_tree()
	menu.call("_open_settings")
	room.call("_input", escape)
	var dismissed := (
		get_tree().paused
		and menu.is_visible_in_tree()
		and not (menu.get("_settings") as Control).visible
		and (menu.get("_main_box") as Control).visible
	)
	menu.call("_request_menu")
	room.call("_input", escape)
	var cancelled := get_tree().paused and menu.is_visible_in_tree() and not (menu.get("_confirm") as Control).visible
	room.call("_input", escape)
	var resumed := not get_tree().paused and not menu.is_visible_in_tree()
	room.queue_free()
	await get_tree().process_frame
	return entered and dismissed and cancelled and resumed





func _check_fullscreen_toggle() -> bool:
	var previous_mode := DisplayServer.window_get_mode()
	var previous_setting: bool = GameSettings.fullscreen
	GameSettings.set_fullscreen(true)
	await get_tree().process_frame
	var fullscreen_mode := DisplayServer.window_get_mode()
	GameSettings.set_fullscreen(false)
	await get_tree().process_frame
	var windowed_mode := DisplayServer.window_get_mode()
	GameSettings.set_fullscreen(previous_setting)
	DisplayServer.window_set_mode(previous_mode)
	await get_tree().process_frame
	var restored_mode := DisplayServer.window_get_mode()
	print("FULLSCREEN_MODES previous=%d fullscreen=%d windowed=%d restored=%d" % [
		previous_mode, fullscreen_mode, windowed_mode, restored_mode
	])
	return (
		fullscreen_mode == DisplayServer.WINDOW_MODE_FULLSCREEN
		and windowed_mode == DisplayServer.WINDOW_MODE_WINDOWED
		and restored_mode == previous_mode
		and GameSettings.fullscreen == previous_setting
	)




func _ambient_status(label: String, player: AudioStreamPlayer) -> void:
	if player == null:
		print("AMBIENCE_%s node=null" % label)
		return
	var wav := player.stream as AudioStreamWAV
	if wav == null:
		print("AMBIENCE_%s stream=%s" % [label, str(player.stream)])
		return
	print("AMBIENCE_%s playing=%s pos=%.4f len=%.4f loop=%d begin=%d end=%d" % [
		label, str(player.playing), player.get_playback_position(), wav.get_length(),
		wav.loop_mode, wav.loop_begin, wav.loop_end
	])


func _check_ambience_pause() -> bool:
	var player := GameSettings.get_node_or_null("CavernAmbience") as AudioStreamPlayer
	_ambient_status("start", player)
	if player == null or player.bus != &"Ambience":
		return false
	var started_playing := player.playing
	await get_tree().create_timer(0.12, true).timeout
	_ambient_status("before_pause", player)
	var before := player.get_playback_position()
	get_tree().paused = true
	await get_tree().create_timer(0.18, true).timeout
	_ambient_status("during_pause", player)
	var during := player.get_playback_position()
	get_tree().paused = false
	await get_tree().create_timer(0.12, true).timeout
	_ambient_status("after_resume", player)
	var after := player.get_playback_position()
	await get_tree().create_timer(10.2, true).timeout
	_ambient_status("after_loop", player)
	var loop_position := player.get_playback_position()
	return (
		started_playing
		and before > 0.0
		and player.playing
		and absf(during - before) < 0.035
		and after > during + 0.045
		and loop_position > 0.0
		and loop_position < 1.0
	)


func _check_mouse_input() -> bool:
	var player := (load("res://scenes/player/slime_player.tscn") as PackedScene).instantiate() as SlimeIsometricController
	get_tree().root.add_child(player)
	await get_tree().process_frame
	var before := player.camera.global_basis
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(250, 175)
	motion.relative = Vector2(20, 10)
	player._input(motion)
	var correct := player.pointer == motion.position and player.camera.global_basis.is_equal_approx(before)
	correct = correct and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
	player.queue_free()
	await get_tree().process_frame
	return correct


func _check_pause_timers() -> bool:
	get_tree().set_meta(&"checkpoint_active", false)
	var room := (load("res://tests/helpers/combat_fixture.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(room)
	await get_tree().process_frame
	var player := room.get_node("SlimePlayer") as SlimeController
	player.set("_cooldowns", {&"sticky_spit": 1.0})
	player.velocity = Vector3(3.0, 0.0, 0.0)
	room.call("_pause_game")
	var position_before := player.global_position
	await get_tree().create_timer(0.22, true).timeout
	var cooldown_during := float((player.get("_cooldowns") as Dictionary).get(&"sticky_spit", -1.0))
	var distance_during := player.global_position.distance_to(position_before)
	var halted := get_tree().paused and absf(cooldown_during - 1.0) < 0.0001 and distance_during < 0.0001
	room.call("_resume_game")
	await get_tree().create_timer(0.22, true).timeout
	var cooldown_after := float((player.get("_cooldowns") as Dictionary).get(&"sticky_spit", -1.0))
	var resumed := not get_tree().paused and cooldown_after < 0.90
	print("PAUSE_TIMERS during=%.4f after=%.4f moved_during=%.6f" % [
		cooldown_during, cooldown_after, distance_during
	])
	room.queue_free()
	await get_tree().process_frame
	return halted and resumed


func _check_menu_return() -> bool:
	get_tree().set_meta(&"checkpoint_active", true)
	var room := (load("res://tests/helpers/combat_fixture.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(room)
	get_tree().current_scene = room
	await get_tree().process_frame
	var menu := room.get("_pause_panel") as SlimePauseMenu
	room.call("_pause_game")
	menu.call("_request_menu")
	menu.call("_go_to_menu")
	for tick in 10:
		await get_tree().process_frame
		if is_instance_valid(get_tree().current_scene) and get_tree().current_scene.scene_file_path == "res://scenes/launch.tscn":
			break
	var returned := (
		is_instance_valid(get_tree().current_scene)
		and get_tree().current_scene.scene_file_path == "res://scenes/launch.tscn"
		and not get_tree().paused
		and not get_tree().has_meta(&"checkpoint_active")
		and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
	)
	if is_instance_valid(get_tree().current_scene):
		var old_scene := get_tree().current_scene
		get_tree().current_scene = null
		old_scene.queue_free()
	await get_tree().process_frame
	return returned


func _find_slider(node: Node, label_text: String) -> HSlider:
	for child in node.get_children():
		if (
			child is HBoxContainer
			and child.get_child_count() >= 2
			and child.get_child(0) is Label
			and (child.get_child(0) as Label).text == label_text
		):
			return child.get_child(1) as HSlider
		var nested := _find_slider(child, label_text)
		if nested != null:
			return nested
	return null


func _find_checkbox(node: Node, label_text: String) -> CheckBox:
	for child in node.get_children():
		if child is CheckBox and child.text == label_text:
			return child
		var nested := _find_checkbox(child, label_text)
		if nested != null:
			return nested
	return null


func _bus_at(index: int, expected: float) -> bool:
	return (
		index >= 0
		and not AudioServer.is_bus_mute(index)
		and absf(db_to_linear(AudioServer.get_bus_volume_db(index)) - expected) < 0.001
	)


func _remove_test_file() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_PATH)
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(absolute_path)


func _report(case_name: String, result: bool) -> void:
	if result:
		print("PASS " + case_name)
	else:
		_failures += 1
		print("FAIL " + case_name)
