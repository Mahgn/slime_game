extends Control

const START_SCENE := "res://scenes/opening/opening_route.tscn"

var _main_panel: PanelContainer
var _settings_panel: SlimeSettingsPanel
var _status: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE and _settings_panel.visible:
		_settings_panel.close_and_save()
		get_viewport().set_input_as_handled()


func _show_settings() -> void:
	_main_panel.visible = false
	_settings_panel.visible = true


func _close_settings() -> void:
	_settings_panel.visible = false
	_main_panel.visible = true


func _start_game() -> void:
	var tree := get_tree()
	tree.paused = false
	if tree.has_meta(&"checkpoint_active"):
		tree.remove_meta(&"checkpoint_active")
	var result := tree.change_scene_to_file(START_SCENE)
	if result != OK:
		_status.text = "Не удалось открыть игру: %d" % result


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("080a0e")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_main_panel = PanelContainer.new()
	_main_panel.anchor_left = 0.5
	_main_panel.anchor_right = 0.5
	_main_panel.anchor_top = 0.5
	_main_panel.anchor_bottom = 0.5
	_main_panel.offset_left = -280
	_main_panel.offset_right = 280
	_main_panel.offset_top = -205
	_main_panel.offset_bottom = 205
	var style := StyleBoxFlat.new()
	style.bg_color = Color("211b15")
	style.border_color = Color("8f7448")
	style.set_border_width_all(1)
	style.set_content_margin_all(24)
	_main_panel.add_theme_stylebox_override("panel", style)
	add_child(_main_panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	_main_panel.add_child(box)
	var title := Label.new()
	title.text = "Слайм: путь наверх"
	title.add_theme_font_override("font", preload("res://assets/ash-vault/CormorantGaramond.ttf"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 43)
	box.add_child(title)
	_status = Label.new()
	_status.name = "ProjectStatus"
	_status.text = "Найди путь наверх. К своим."
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 20)
	_status.add_theme_color_override("font_color", Color("dfc99d"))
	box.add_child(_status)
	var play := _button(box, "Играть")
	play.name = "PlayButton"
	play.pressed.connect(_start_game)
	var settings := _button(box, "Настройки")
	settings.name = "SettingsButton"
	settings.pressed.connect(_show_settings)
	var exit_button := _button(box, "Выход")
	exit_button.name = "ExitButton"
	exit_button.pressed.connect(func() -> void: SlimeGameSettings.current().request_quit())
	_settings_panel = SlimeSettingsPanel.new()
	_settings_panel.name = "SettingsPanel"
	_settings_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_panel.visible = false
	_settings_panel.closed.connect(_close_settings)
	add_child(_settings_panel)


func _button(parent: Control, caption: String) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 48
	button.add_theme_font_size_override("font_size", 21)
	parent.add_child(button)
	return button
