extends ColorRect
class_name SlimePauseMenu

signal resume_requested

var _main_box: VBoxContainer
var _settings: SlimeSettingsPanel
var _confirm: ColorRect
var _error_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	color = Color(0.02, 0.04, 0.07, 0.88)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func dismiss_submenu() -> bool:
	if _settings.visible:
		_settings.close_and_save()
		return true
	if _confirm.visible:
		_confirm.visible = false
		_main_box.visible = true
		return true
	return false


func reset_submenus() -> void:
	_settings.visible = false
	_confirm.visible = false
	_main_box.visible = true
	_error_label.text = ""


func _build_ui() -> void:
	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 14)
	_main_box.anchor_left = 0.5
	_main_box.anchor_right = 0.5
	_main_box.anchor_top = 0.5
	_main_box.anchor_bottom = 0.5
	_main_box.offset_left = -240
	_main_box.offset_right = 240
	_main_box.offset_top = -185
	_main_box.offset_bottom = 185
	add_child(_main_box)

	var title := Label.new()
	title.text = "ПАУЗА"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 31)
	_main_box.add_child(title)

	_add_button(_main_box, "Продолжить", func() -> void: resume_requested.emit())
	_add_button(_main_box, "Настройки", _open_settings)
	_add_button(_main_box, "В меню", _request_menu)

	_error_label = Label.new()
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.add_theme_font_size_override("font_size", 18)
	_main_box.add_child(_error_label)

	_settings = SlimeSettingsPanel.new()
	_settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings.visible = false
	_settings.closed.connect(_close_settings)
	add_child(_settings)

	_confirm = ColorRect.new()
	_confirm.color = Color(0.025, 0.07, 0.09, 0.98)
	_confirm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm.visible = false
	add_child(_confirm)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -300
	box.offset_right = 300
	box.offset_top = -145
	box.offset_bottom = 145
	_confirm.add_child(box)

	var warning := Label.new()
	warning.text = "Выйти в меню?\nТекущий сеанс будет завершён."
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.add_theme_font_size_override("font_size", 22)
	box.add_child(warning)
	_add_button(box, "Выйти в меню", _go_to_menu)
	_add_button(box, "Остаться", _cancel_menu)


func _add_button(parent: Control, caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 47
	button.add_theme_font_size_override("font_size", 21)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _open_settings() -> void:
	_main_box.visible = false
	_settings.visible = true


func _close_settings() -> void:
	_settings.visible = false
	_main_box.visible = true


func _request_menu() -> void:
	_main_box.visible = false
	_confirm.visible = true


func _cancel_menu() -> void:
	_confirm.visible = false
	_main_box.visible = true


func _go_to_menu() -> void:
	var tree := get_tree()
	tree.paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if tree.has_meta(&"checkpoint_active"):
		tree.remove_meta(&"checkpoint_active")
	var result := tree.change_scene_to_file("res://scenes/launch.tscn")
	if result != OK:
		tree.paused = true
		_confirm.visible = false
		_main_box.visible = true
		_error_label.text = "Не удалось открыть меню: %d" % result
