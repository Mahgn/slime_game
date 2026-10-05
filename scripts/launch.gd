extends Control

const STORE_SCRIPT = preload("res://scripts/progression/checkpoint_store.gd")

var _store: CheckpointStore
var _read_result: Dictionary
var _message: Label
var _continue_button: Button
var _confirm_panel: PanelContainer
var _main_panel: PanelContainer
var _settings_panel: SlimeSettingsPanel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_store = STORE_SCRIPT.new()
	_read_result = _store.read_checkpoint()
	_build_ui()
	_refresh_message()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if is_instance_valid(_settings_panel) and _settings_panel.visible:
			_settings_panel.close_and_save()
		elif is_instance_valid(_confirm_panel) and _confirm_panel.visible:
			_confirm_panel.visible = false
		get_viewport().set_input_as_handled()


func _show_settings() -> void:
	_main_panel.visible = false
	_settings_panel.visible = true


func _close_settings() -> void:
	_settings_panel.visible = false
	_main_panel.visible = true


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.045, 0.09, 0.12)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_main_panel = PanelContainer.new()
	_main_panel.anchor_left = 0.5
	_main_panel.anchor_right = 0.5
	_main_panel.anchor_top = 0.5
	_main_panel.anchor_bottom = 0.5
	_main_panel.offset_left = -270
	_main_panel.offset_right = 270
	_main_panel.offset_top = -280
	_main_panel.offset_bottom = 280
	add_child(_main_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 15)
	_main_panel.add_child(box)
	var title := Label.new()
	title.text = "СЛАЙМ: ПУТЬ НАВЕРХ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 29)
	box.add_child(title)
	_message = Label.new()
	_message.custom_minimum_size = Vector2(490, 92)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_font_size_override("font_size", 19)
	box.add_child(_message)
	_continue_button = _button(box, "Продолжить")
	_continue_button.pressed.connect(_continue_game)
	var new_button := _button(box, "Начать заново")
	new_button.pressed.connect(_request_new_game)
	var floor_button := _button(box, "Первый этаж · маршрут коллеги")
	floor_button.name = "FirstFloorButton"
	floor_button.pressed.connect(_open_first_floor)
	var workshop_button := _button(box, "Лаборатория внешности")
	workshop_button.name = "LabWorkshopButton"
	workshop_button.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/art_review/lab_workshop.tscn"))
	var settings_button := _button(box, "Настройки")
	settings_button.pressed.connect(_show_settings)
	var exit_button := _button(box, "Выход")
	exit_button.pressed.connect(func() -> void: SlimeGameSettings.current().request_quit())
	_confirm_panel = PanelContainer.new()
	_confirm_panel.visible = false
	_confirm_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_confirm_panel)
	var confirm_box := VBoxContainer.new()
	confirm_box.alignment = BoxContainer.ALIGNMENT_CENTER
	confirm_box.add_theme_constant_override("separation", 16)
	_confirm_panel.add_child(confirm_box)
	var warning := Label.new()
	warning.text = "Начать сначала? Текущий входной снимок будет заменен."
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.add_theme_font_size_override("font_size", 22)
	confirm_box.add_child(warning)
	var accept := _button(confirm_box, "Да, начать заново")
	accept.pressed.connect(_start_new_game)
	var cancel := _button(confirm_box, "Отмена")
	cancel.pressed.connect(func() -> void: _confirm_panel.visible = false)
	_settings_panel = SlimeSettingsPanel.new()
	_settings_panel.name = "SettingsPanel"
	_settings_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_panel.visible = false
	_settings_panel.closed.connect(_close_settings)
	add_child(_settings_panel)


func _button(parent: Control, label: String) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0, 48)
	button.add_theme_font_size_override("font_size", 21)
	parent.add_child(button)
	return button


func _refresh_message() -> void:
	var status: String = _read_result["status"]
	_continue_button.visible = (status == "ok" or status == "backup") and not _read_result["snapshot"]["slice_complete"]
	if status == "ok":
		_message.text = "Демо пройдено. Можно начать заново." if _read_result["snapshot"]["slice_complete"] else "Сохранён вход в %s. Продолжить начнёт комнату заново." % _read_result["snapshot"]["checkpoint_room_id"]
	elif status == "backup":
		_message.text = "Демо пройдено; запись доступна в резервной копии. Можно начать заново." if _read_result["snapshot"]["slice_complete"] else "Основной файл не удалось восстановить. Доступна резервная копия входа в %s." % _read_result["snapshot"]["checkpoint_room_id"]
	elif status == "missing":
		_message.text = "Сохранения пока нет. Прогресс записывается при переходе в следующий зал."
	else:
		_message.text = "Не удалось восстановить сохранение. Проверь файл или начни заново с подтверждением."


func _continue_game() -> void:
	if not _continue_button.visible:
		return
	var snapshot: Dictionary = _read_result["snapshot"]
	if _read_result["status"] == "backup":
		var repair := _store.write_checkpoint(snapshot, true)
		if not repair["ok"]:
			_message.text = "Не удалось восстановить сохранение: %s" % repair["error"]
			return
	_enter_room(snapshot["checkpoint_room_id"])


func _request_new_game() -> void:
	if _read_result["status"] == "missing":
		_start_new_game()
	else:
		_confirm_panel.visible = true


func _start_new_game() -> void:
	var result := _store.write_checkpoint(_store.initial_snapshot(), true)
	if not result["ok"]:
		_confirm_panel.visible = false
		_message.text = "Не удалось записать сохранение: %s" % result["error"]
		return
	_enter_room("R01")


func _enter_room(room_id: String) -> void:
	var scene_path := _store.scene_path(room_id)
	if scene_path.is_empty():
		_message.text = "Неизвестный зал в сохранении"
		return
	get_tree().set_meta(&"checkpoint_active", true)
	var result := get_tree().change_scene_to_file(scene_path)
	if result != OK:
		get_tree().remove_meta(&"checkpoint_active")
		_message.text = "Не удалось открыть зал: %d" % result


func _open_first_floor() -> void:
	if get_tree().has_meta(&"first_floor_restart_state"):
		get_tree().remove_meta(&"first_floor_restart_state")
	if get_tree().has_meta(&"checkpoint_active"):
		get_tree().remove_meta(&"checkpoint_active")
	var result := get_tree().change_scene_to_file("res://scenes/levels/first_floor.tscn")
	if result != OK:
		_message.text = "Не удалось открыть первый этаж: %d" % result
