extends Node
class_name SlimeGameSettings

signal changed

const FILE_PATH := "user://settings.cfg"
const AMBIENT_STREAM := preload("res://assets/audio/cavern_ambient_loop.wav")
const EFFECTS_BUS := &"Effects"
const AMBIENCE_BUS := &"Ambience"

var master_volume := 1.0
var effects_volume := 1.0
var ambience_volume := 0.6
var mouse_sensitivity_scale := 1.0
var invert_y := false
var camera_shake := 0.0
var fullscreen := false

var _settings_path := FILE_PATH
var _ambient_player: AudioStreamPlayer
var _save_timer: Timer
var _dirty := false
var _quit_requested := false


static func current() -> SlimeGameSettings:
	var tree := Engine.get_main_loop() as SceneTree
	var active := tree.root.get_node_or_null("GameSettings") as SlimeGameSettings
	if active != null:
		return active
	# Standalone --script test runners do not instantiate project autoloads.
	active = SlimeGameSettings.new()
	active.name = "GameSettings"
	tree.root.add_child(active)
	return active


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	_ensure_audio_buses()
	load_settings()
	_save_timer = Timer.new()
	_save_timer.name = "SaveDelay"
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.4
	_save_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_save_timer.timeout.connect(save_settings)
	add_child(_save_timer)
	_start_ambience()


func _exit_tree() -> void:
	_stop_ambience()
	if _dirty:
		save_settings()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_quit()


func request_quit() -> void:
	if _quit_requested:
		return
	_quit_requested = true
	_stop_ambience()
	await get_tree().create_timer(0.25).timeout
	get_tree().quit()


func _stop_ambience() -> void:
	if is_instance_valid(_ambient_player):
		_ambient_player.stop()
		_ambient_player.stream = null


func load_settings(path: String = FILE_PATH) -> Error:
	_settings_path = path
	_set_defaults()
	var config := ConfigFile.new()
	var result := config.load(path)
	if result == OK:
		master_volume = _read_number(config, "audio", "master", master_volume, 0.0, 1.0)
		effects_volume = _read_number(config, "audio", "effects", effects_volume, 0.0, 1.0)
		ambience_volume = _read_number(config, "audio", "ambience", ambience_volume, 0.0, 1.0)
		mouse_sensitivity_scale = _read_number(config, "controls", "mouse_sensitivity", mouse_sensitivity_scale, 0.25, 2.0)
		invert_y = _read_bool(config, "controls", "invert_y", invert_y)
		camera_shake = _read_number(config, "controls", "camera_shake", camera_shake, 0.0, 1.0)
		fullscreen = _read_bool(config, "display", "fullscreen", fullscreen)
	_apply_audio()
	_apply_window()
	changed.emit()
	_dirty = false
	return result


func save_settings() -> Error:
	if is_instance_valid(_save_timer):
		_save_timer.stop()
	var config := ConfigFile.new()
	config.set_value("audio", "master", master_volume)
	config.set_value("audio", "effects", effects_volume)
	config.set_value("audio", "ambience", ambience_volume)
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity_scale)
	config.set_value("controls", "invert_y", invert_y)
	config.set_value("controls", "camera_shake", camera_shake)
	config.set_value("display", "fullscreen", fullscreen)
	var result := config.save(_settings_path)
	_dirty = result != OK
	return result


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_audio()
	_mark_changed()


func set_effects_volume(value: float) -> void:
	effects_volume = clampf(value, 0.0, 1.0)
	_apply_audio()
	_mark_changed()


func set_ambience_volume(value: float) -> void:
	ambience_volume = clampf(value, 0.0, 1.0)
	_apply_audio()
	_mark_changed()


func set_mouse_sensitivity_scale(value: float) -> void:
	mouse_sensitivity_scale = clampf(value, 0.25, 2.0)
	_mark_changed()


func set_invert_y(value: bool) -> void:
	invert_y = value
	_mark_changed()


func set_camera_shake(value: float) -> void:
	camera_shake = clampf(value, 0.0, 1.0)
	_mark_changed()


func set_fullscreen(value: bool) -> void:
	fullscreen = value
	_apply_window()
	_mark_changed()


func _start_ambience() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.name = "CavernAmbience"
	_ambient_player.bus = AMBIENCE_BUS
	_ambient_player.process_mode = Node.PROCESS_MODE_PAUSABLE
	var looped: AudioStreamWAV = AMBIENT_STREAM.duplicate()
	looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
	looped.loop_end = roundi(looped.get_length() * float(looped.mix_rate))
	_ambient_player.stream = looped
	add_child(_ambient_player)
	_ambient_player.play()

func _set_defaults() -> void:
	master_volume = 1.0
	effects_volume = 1.0
	ambience_volume = 0.6
	mouse_sensitivity_scale = 1.0
	invert_y = false
	camera_shake = 0.0
	fullscreen = false


func _read_number(config: ConfigFile, section: String, key: String, fallback: float, minimum: float, maximum: float) -> float:
	var value: Variant = config.get_value(section, key, fallback)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return fallback
	var number := float(value)
	if is_nan(number) or is_inf(number):
		return fallback
	return clampf(number, minimum, maximum)


func _read_bool(config: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	var value: Variant = config.get_value(section, key, fallback)
	return value if typeof(value) == TYPE_BOOL else fallback


func _ensure_audio_buses() -> void:
	for bus_name in [EFFECTS_BUS, AMBIENCE_BUS]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var index := AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, &"Master")


func _apply_audio() -> void:
	_set_bus_level(&"Master", master_volume)
	_set_bus_level(EFFECTS_BUS, effects_volume)
	_set_bus_level(AMBIENCE_BUS, ambience_volume)


func _set_bus_level(bus_name: StringName, level: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_mute(index, level <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(level, 0.0001)))


func _apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


func _mark_changed() -> void:
	_dirty = true
	changed.emit()
	if is_instance_valid(_save_timer):
		_save_timer.start()
