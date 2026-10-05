extends Node3D

const MENU_SCENE := "res://scenes/launch.tscn"
const SLIME_SHADER = preload("res://assets/shaders/lab_workshop.gdshader")
const DEFAULT_COLOR := Color(0.20, 0.86, 0.72)

var _slime_root: Node3D
var _eyes: Node3D
var _slime_material: ShaderMaterial
var _color_picker: ColorPickerButton
var _shape_slider: HSlider
var _gloss_slider: HSlider
var _wobble_slider: HSlider
var _eyes_toggle: CheckButton
var _spin_toggle: CheckButton


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	randomize()
	_build_world()
	_build_slime()
	_build_ui()


func _process(delta: float) -> void:
	if _spin_toggle.button_pressed:
		_slime_root.rotation.y += delta * 0.42


func _build_world() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.07, 0.11, 0.16)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.54, 0.68, 0.77)
	environment.ambient_light_energy = 0.55
	world.environment = environment
	add_child(world)

	var camera := Camera3D.new()
	camera.position = Vector3(1.7, 2.2, 5.2)
	camera.fov = 45.0
	add_child(camera)
	camera.look_at(Vector3(0.58, 0.85, 0.0))
	camera.current = true

	_add_omni_light(Vector3(-2.2, 4.0, 3.0), Color(0.74, 1.0, 0.96), 1.8)
	_add_omni_light(Vector3(2.8, 2.7, -1.8), Color(0.53, 0.70, 1.0), 1.4)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(18.0, 18.0)
	ground.mesh = plane
	ground.material_override = _material(Color(0.11, 0.19, 0.24), 0.92)
	ground.position.y = -0.05
	add_child(ground)

	var pedestal := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.48
	cylinder.bottom_radius = 1.58
	cylinder.height = 0.28
	pedestal.mesh = cylinder
	pedestal.material_override = _material(Color(0.25, 0.37, 0.44), 0.55)
	pedestal.position.y = 0.10
	add_child(pedestal)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.38
	torus.outer_radius = 1.45
	ring.mesh = torus
	ring.material_override = _emissive_material(Color(0.22, 0.84, 0.73))
	ring.position.y = 0.26
	add_child(ring)


func _build_slime() -> void:
	_slime_root = Node3D.new()
	_slime_root.name = "SlimePreview"
	_slime_root.position.y = 1.12
	add_child(_slime_root)

	var body := MeshInstance3D.new()
	body.name = "Body"
	var sphere := SphereMesh.new()
	sphere.radius = 0.8
	sphere.height = 1.6
	sphere.radial_segments = 64
	sphere.rings = 32
	body.mesh = sphere
	_slime_material = ShaderMaterial.new()
	_slime_material.shader = SLIME_SHADER
	_slime_material.set_shader_parameter("slime_color", DEFAULT_COLOR)
	body.material_override = _slime_material
	_slime_root.add_child(body)

	_eyes = Node3D.new()
	_eyes.name = "Face"
	_slime_root.add_child(_eyes)
	for side in [-1.0, 1.0]:
		_add_eye(Vector3(side * 0.23, 0.13, 0.75))
		_add_glint(Vector3(side * 0.23 - 0.024, 0.155, 0.815))


func _add_eye(at: Vector3) -> void:
	var eye := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.075
	mesh.height = 0.15
	eye.mesh = mesh
	eye.material_override = _material(Color(0.035, 0.08, 0.12), 0.07)
	eye.position = at
	_eyes.add_child(eye)


func _add_glint(at: Vector3) -> void:
	var glint := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.018
	mesh.height = 0.036
	glint.mesh = mesh
	glint.material_override = _emissive_material(Color(0.93, 1.0, 0.98))
	glint.position = at
	_eyes.add_child(glint)


func _add_omni_light(at: Vector3, color: Color, energy: float) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 9.0
	add_child(light)


func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _emissive_material(color: Color) -> StandardMaterial3D:
	var material := _material(color, 0.18)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.4
	return material


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	panel.name = "Controls"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -390.0
	panel.add_theme_stylebox_override("panel", _panel_style())
	layer.add_child(panel)

	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	var stack := VBoxContainer.new()
	stack.custom_minimum_size.x = 330.0
	stack.add_theme_constant_override("separation", 14)
	scroll.add_child(stack)
	var back_button := _button("← В меню")
	back_button.name = "BackButton"
	back_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))
	stack.add_child(back_button)
	stack.add_child(_label("НАША ЛАБОРАТОРИЯ", 15, Color(0.40, 0.91, 0.80)))
	stack.add_child(_label("Внешний вид слайма", 28, Color.WHITE))
	var intro := _label("Пробуй варианты свободно. Это отдельная сцена без прогресса и сохранений демо.", 16, Color(0.69, 0.81, 0.84))
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(intro)
	_add_spacer(stack, 8)

	stack.add_child(_label("Цвет", 18, Color.WHITE))
	_color_picker = ColorPickerButton.new()
	_color_picker.name = "ColorPicker"
	_color_picker.custom_minimum_size.y = 43.0
	_color_picker.color = DEFAULT_COLOR
	_color_picker.color_changed.connect(func(color: Color) -> void: _slime_material.set_shader_parameter("slime_color", color))
	stack.add_child(_color_picker)

	_shape_slider = _slider(stack, "Форма: шар ↔ мягкий куб", 0.72, 0.0, 1.0, 0.01)
	_shape_slider.name = "ShapeSlider"
	_shape_slider.value_changed.connect(func(value: float) -> void: _slime_material.set_shader_parameter("cubeness", value))
	_gloss_slider = _slider(stack, "Блеск", 0.72, 0.0, 1.0, 0.01)
	_gloss_slider.name = "GlossSlider"
	_gloss_slider.value_changed.connect(func(value: float) -> void: _slime_material.set_shader_parameter("gloss", value))
	_wobble_slider = _slider(stack, "Живость формы", 0.05, 0.0, 0.20, 0.005)
	_wobble_slider.name = "WobbleSlider"
	_wobble_slider.value_changed.connect(func(value: float) -> void: _slime_material.set_shader_parameter("wobble", value))

	_eyes_toggle = CheckButton.new()
	_eyes_toggle.text = "Глаза"
	_eyes_toggle.button_pressed = true
	_eyes_toggle.toggled.connect(func(enabled: bool) -> void: _eyes.visible = enabled)
	stack.add_child(_eyes_toggle)
	_spin_toggle = CheckButton.new()
	_spin_toggle.text = "Медленно вращать"
	_spin_toggle.button_pressed = true
	stack.add_child(_spin_toggle)
	_add_spacer(stack, 5)

	var random_button := _button("Случайный вариант")
	random_button.pressed.connect(_randomize_slime)
	stack.add_child(random_button)
	var reset_button := _button("Вернуть исходный вид")
	reset_button.pressed.connect(_reset_slime)
	stack.add_child(reset_button)


func _slider(parent: VBoxContainer, title: String, initial: float, minimum: float, maximum: float, step_size: float) -> HSlider:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var title_label := _label(title, 16, Color(0.82, 0.90, 0.92))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_label)
	var value_label := _label("%.2f" % initial, 15, Color(0.41, 0.92, 0.80))
	row.add_child(value_label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step_size
	slider.value = initial
	slider.custom_minimum_size.y = 23.0
	slider.value_changed.connect(func(value: float) -> void: value_label.text = "%.2f" % value)
	parent.add_child(slider)
	return slider


func _randomize_slime() -> void:
	_color_picker.color = Color.from_hsv(randf(), randf_range(0.47, 0.82), randf_range(0.68, 0.95))
	_shape_slider.value = randf_range(0.25, 1.0)
	_gloss_slider.value = randf_range(0.35, 0.95)
	_wobble_slider.value = randf_range(0.01, 0.13)
	_slime_material.set_shader_parameter("slime_color", _color_picker.color)


func _reset_slime() -> void:
	_color_picker.color = DEFAULT_COLOR
	_shape_slider.value = 0.72
	_gloss_slider.value = 0.72
	_wobble_slider.value = 0.05
	_eyes_toggle.button_pressed = true
	_eyes.visible = true
	_spin_toggle.button_pressed = true
	_slime_root.rotation.y = 0.0
	_slime_material.set_shader_parameter("slime_color", DEFAULT_COLOR)


func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(value: String) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 46.0
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 17)
	return button


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.095, 0.14, 0.98)
	style.set_content_margin_all(22)
	return style


func _add_spacer(parent: VBoxContainer, height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	parent.add_child(spacer)
