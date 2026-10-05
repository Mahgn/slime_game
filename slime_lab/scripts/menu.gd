extends Control

const WORKSHOP_SCENE := "res://scenes/workshop.tscn"
const FIRST_FLOOR_SCENE := "res://scenes/first_floor.tscn"
const DEMO_DIRECTORY := "../slime_game"
const PREVIEW_SCENE := "res://scenes/art_review/slime_model_preview_v5.tscn"

static var demo_process_id: int = -1
static var preview_process_id: int = -1

var _status: Label
var _demo_button: Button
var _preview_button: Button


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	_update_process_status()


func _process(_delta: float) -> void:
	var changed := false
	if demo_process_id > 0 and not OS.is_process_running(demo_process_id):
		demo_process_id = -1
		changed = true
	if preview_process_id > 0 and not OS.is_process_running(preview_process_id):
		preview_process_id = -1
		changed = true
	if changed:
		_update_process_status()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.055, 0.09, 0.13)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var stripe := ColorRect.new()
	stripe.color = Color(0.18, 0.78, 0.68)
	stripe.anchor_right = 1.0
	stripe.offset_bottom = 7.0
	add_child(stripe)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1010, 0)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.09, 0.15, 0.20), 25, 30))
	center.add_child(panel)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 14)
	panel.add_child(stack)
	stack.add_child(_label("ПРИЁМНОЕ ОТДЕЛЕНИЕ ПОДЗЕМЕЛЬЯ", 15, Color(0.37, 0.88, 0.76)))
	stack.add_child(_label("Слизи: первый этаж", 35, Color(0.96, 0.98, 1.0)))
	stack.add_child(_label("Начни подъём или открой отдельные рабочие сцены.", 19, Color(0.68, 0.78, 0.81)))
	_add_spacer(stack, 4)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	stack.add_child(columns)
	var own_column := VBoxContainer.new()
	own_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	own_column.add_theme_constant_override("separation", 13)
	columns.add_child(own_column)
	var demo_column := VBoxContainer.new()
	demo_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	demo_column.add_theme_constant_override("separation", 13)
	columns.add_child(demo_column)

	own_column.add_child(_label("НАШ ПРОЕКТ", 15, Color(0.44, 0.83, 1.0)))
	var first_floor := _button("Играть · первый этаж", Color(0.19, 0.42, 0.62))
	first_floor.name = "FirstFloorButton"
	first_floor.pressed.connect(_open_first_floor)
	own_column.add_child(first_floor)
	own_column.add_child(_description("Подъём через девять зон: камера, хлыст, враги и поглощение навыков."))
	_add_spacer(own_column, 2)
	var workshop := _button("Внешний вид слайма", Color(0.21, 0.34, 0.52))
	workshop.name = "WorkshopButton"
	workshop.pressed.connect(_open_workshop)
	own_column.add_child(workshop)
	own_column.add_child(_description("Свободные опыты с формой, цветом и движением."))

	demo_column.add_child(_label("ПЕРВЫЙ ЧЕРНОВИК · КОЛЛЕГА", 15, Color(0.37, 0.88, 0.76)))
	var demo := _button("Демо игры", Color(0.17, 0.44, 0.41))
	demo.name = "DemoButton"
	demo.pressed.connect(_open_demo)
	demo_column.add_child(demo)
	_demo_button = demo
	demo_column.add_child(_description("Основной маршрут другого разработчика. Его файлы не меняем."))
	_add_spacer(demo_column, 2)
	var preview := _button("Новый слайм v5", Color(0.25, 0.47, 0.50))
	preview.name = "PreviewButton"
	preview.pressed.connect(_open_preview)
	demo_column.add_child(preview)
	_preview_button = preview
	demo_column.add_child(_description("Отдельная пробная сцена R02 с моделью v5."))
	_add_spacer(stack, 6)

	_status = _label("Это отдельный проект. Демо остаётся самостоятельным.", 15, Color(0.62, 0.82, 0.79))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_status)


func _open_workshop() -> void:
	var result := get_tree().change_scene_to_file(WORKSHOP_SCENE)
	if result != OK:
		_status.text = "Не удалось открыть лабораторию: %d" % result


func _open_first_floor() -> void:
	var result := get_tree().change_scene_to_file(FIRST_FLOOR_SCENE)
	if result != OK:
		_status.text = "Не удалось открыть первый этаж: %d" % result


func _open_demo() -> void:
	if demo_process_id > 0:
		return
	_start_demo_scene(false)


func _open_preview() -> void:
	if preview_process_id > 0:
		return
	_start_demo_scene(true)


func _start_demo_scene(is_preview: bool) -> void:
	var demo_path := ProjectSettings.globalize_path("res://" + DEMO_DIRECTORY).simplify_path()
	if not FileAccess.file_exists(demo_path.path_join("project.godot")):
		_status.text = "Черновик 1 не найден рядом с лабораторией."
		return
	if is_preview and not FileAccess.file_exists(demo_path.path_join("scenes/art_review/slime_model_preview_v5.tscn")):
		_status.text = "Пробная сцена с новым слаймом не найдена в черновике 1."
		return
	if OS.has_feature("template"):
		_status.text = "Открытие другого проекта доступно из Godot, не из экспортированной сборки."
		return
	var arguments := PackedStringArray(["--path", demo_path])
	if is_preview:
		arguments.append_array(PackedStringArray(["--scene", PREVIEW_SCENE]))
	var process_id := OS.create_process(OS.get_executable_path(), arguments)
	if process_id <= 0:
		_status.text = "Не удалось запустить сцену первого черновика."
		return
	if is_preview:
		preview_process_id = process_id
	else:
		demo_process_id = process_id
	_update_process_status()


func _update_process_status() -> void:
	var demo_running := demo_process_id > 0 and OS.is_process_running(demo_process_id)
	var preview_running := preview_process_id > 0 and OS.is_process_running(preview_process_id)
	_demo_button.disabled = demo_running
	_preview_button.disabled = preview_running
	if demo_running and preview_running:
		_status.text = "Основное демо и пробная сцена v5 открыты в отдельных окнах."
	elif preview_running:
		_status.text = "Пробная сцена v5 открыта отдельно. Основное демо пока со старой моделью."
	elif demo_running:
		_status.text = "Основное демо открыто отдельно. Новый слайм доступен кнопкой v5."
	else:
		_status.text = "Это отдельный проект. Демо и пробная сцена остаются самостоятельными."


func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _description(value: String) -> Label:
	var label := _label(value, 15, Color(0.68, 0.78, 0.81))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _button(value: String, color: Color) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size = Vector2(0, 68)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 21)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _panel_style(color, 14, 18))
	button.add_theme_stylebox_override("hover", _panel_style(color.lightened(0.15), 14, 18))
	button.add_theme_stylebox_override("pressed", _panel_style(color.darkened(0.15), 14, 18))
	return button


func _panel_style(color: Color, radius: int, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(padding)
	return style


func _add_spacer(parent: VBoxContainer, height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	parent.add_child(spacer)
