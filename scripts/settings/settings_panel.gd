extends Control
class_name SlimeSettingsPanel

signal closed

const PANEL_WIDTH := 690.0
const PANEL_HEIGHT := 660.0

var _value_labels: Dictionary = {}
var _error_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func close_and_save() -> bool:
	var result: Error = SlimeGameSettings.current().save_settings()
	if result != OK:
		_error_label.text = "Не удалось сохранить настройки (код %d). Попробуй ещё раз." % result
		return false
	_error_label.text = ""
	closed.emit()
	return true


func _build_ui() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.035, 0.05, 0.94)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -PANEL_WIDTH * 0.5
	panel.offset_right = PANEL_WIDTH * 0.5
	panel.offset_top = -PANEL_HEIGHT * 0.5
	panel.offset_bottom = PANEL_HEIGHT * 0.5
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color(0.045, 0.115, 0.135, 0.99)
	surface.border_color = Color(0.22, 0.54, 0.51)
	surface.set_border_width_all(2)
	surface.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", surface)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	margin.add_child(content)
	_add_label(content, "НАСТРОЙКИ", 29, true)
	_add_label(content, "Изменения применяются сразу", 17, false)
	_add_section(content, "Звук")
	_add_slider(content, &"master", "Общая громкость", 0.0, 1.0, 0.05, SlimeGameSettings.current().master_volume)
	_add_slider(content, &"effects", "Эффекты", 0.0, 1.0, 0.05, SlimeGameSettings.current().effects_volume)
	_add_slider(content, &"ambience", "Музыка / фон", 0.0, 1.0, 0.05, SlimeGameSettings.current().ambience_volume)
	_add_section(content, "Управление и экран")
	_add_slider(content, &"sensitivity", "Чувствительность мыши", 0.25, 2.0, 0.05, SlimeGameSettings.current().mouse_sensitivity_scale)
	_add_slider(content, &"shake", "Тряска камеры", 0.0, 1.0, 0.05, SlimeGameSettings.current().camera_shake)
	_add_checkbox(content, &"invert_y", "Инвертировать вертикаль мыши", SlimeGameSettings.current().invert_y)
	_add_checkbox(content, &"fullscreen", "Полноэкранный режим", SlimeGameSettings.current().fullscreen)
	_error_label = _add_label(content, "", 17, false)
	_error_label.custom_minimum_size.y = 26
	_error_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.56))
	var back := Button.new()
	back.text = "Назад"
	back.custom_minimum_size.y = 46
	back.add_theme_font_size_override("font_size", 21)
	back.pressed.connect(_on_back_pressed)
	content.add_child(back)


func _add_label(parent: Control, title: String, size: int, centered: bool) -> Label:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", size)
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label


func _add_section(parent: VBoxContainer, title: String) -> void:
	var label := _add_label(parent, title, 21, false)
	label.add_theme_color_override("font_color", Color(0.66, 0.95, 0.82))
	label.custom_minimum_size.y = 30


func _add_slider(parent: VBoxContainer, key: StringName, title: String, minimum: float, maximum: float, increment: float, current: float) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 45
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	var label := _add_label(row, title, 19, false)
	label.custom_minimum_size.x = 250
	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = increment
	slider.value = current
	row.add_child(slider)
	var value_label := _add_label(row, _format_value(key, current), 18, false)
	value_label.custom_minimum_size.x = 70
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_value_labels[key] = value_label
	slider.value_changed.connect(_on_slider_changed.bind(key))


func _add_checkbox(parent: VBoxContainer, key: StringName, title: String, current: bool) -> void:
	var checkbox := CheckBox.new()
	checkbox.text = title
	checkbox.button_pressed = current
	checkbox.custom_minimum_size.y = 34
	checkbox.add_theme_font_size_override("font_size", 19)
	checkbox.add_theme_icon_override("checked", _checkbox_icon(true))
	checkbox.add_theme_icon_override("unchecked", _checkbox_icon(false))
	checkbox.toggled.connect(_on_checkbox_toggled.bind(key))
	parent.add_child(checkbox)


func _checkbox_icon(checked: bool) -> Texture2D:
	var pixels := Image.create(22, 22, false, Image.FORMAT_RGBA8)
	var border := Color(0.52, 0.94, 0.82)
	var interior := Color(0.035, 0.105, 0.12)
	var selected := Color(0.58, 0.96, 0.82)
	for y in 22:
		for x in 22:
			var edge := x < 2 or x >= 20 or y < 2 or y >= 20
			pixels.set_pixel(x, y, border if edge else (selected if checked else interior))
	if checked:
		for index in 5:
			pixels.set_pixel(5 + index, 10 + index, interior)
			pixels.set_pixel(5 + index, 11 + index, interior)
		for index in 8:
			pixels.set_pixel(9 + index, 14 - index, interior)
			pixels.set_pixel(9 + index, 15 - index, interior)
	return ImageTexture.create_from_image(pixels)

func _format_value(key: StringName, value: float) -> String:
	if key == &"sensitivity":
		return "%.2f×" % value
	return "%d%%" % roundi(value * 100.0)


func _on_slider_changed(value: float, key: StringName) -> void:
	(_value_labels[key] as Label).text = _format_value(key, value)
	match key:
		&"master":
			SlimeGameSettings.current().set_master_volume(value)
		&"effects":
			SlimeGameSettings.current().set_effects_volume(value)
		&"ambience":
			SlimeGameSettings.current().set_ambience_volume(value)
		&"sensitivity":
			SlimeGameSettings.current().set_mouse_sensitivity_scale(value)
		&"shake":
			SlimeGameSettings.current().set_camera_shake(value)


func _on_checkbox_toggled(value: bool, key: StringName) -> void:
	match key:
		&"invert_y":
			SlimeGameSettings.current().set_invert_y(value)
		&"fullscreen":
			SlimeGameSettings.current().set_fullscreen(value)


func _on_back_pressed() -> void:
	close_and_save()
