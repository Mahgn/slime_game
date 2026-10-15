extends Node3D

const GEOMETRY = preload("res://scripts/visibility_lab/lab_geometry.gd")
const REVEAL = preload("res://scripts/visibility_lab/architectural_reveal.gd")
const PRESENTATION = preload("res://scripts/visibility_lab/lab_presentation.gd")
const PLAYER = preload("res://scenes/player/slime_player.tscn")
const LAB_PLAYER = preload("res://scripts/visibility_lab/lab_player.gd")
const ENEMY = preload("res://scenes/enemies/spitter.tscn")
const INPUT_SETUP = preload("res://scripts/input_setup.gd")
const TITLES := ["Прямой коридор","Поворот","Перекрёсток","Колонна","Арка","Мост и нижний проход"]
var player: SlimeController
var geometry: Node3D
var reveal: SlimeRoomCutaway
var enemy: Spitter
var combat: SlimeCombatRuntime
var mode := 1
var fixture_index := 0
var theme_index := 0
var combat_enabled := false
var status: Label
var pause_panel: PanelContainer
var title_label: Label
var mode_buttons: Array[Button] = []
var floor_button: Button
var combat_button: Button
var hud: CanvasLayer
var fixture_picker: OptionButton
var theme_picker: OptionButton

func _enter_tree() -> void:
	set_meta(&"camera_quarter_turns",true)
	set_meta(&"isometric_dressing_owned",true)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	INPUT_SETUP.install()
	get_tree().paused = false
	_build_lighting()
	_build_ui()
	select_fixture(0,0)
	print("VISIBILITY_LAB_READY fixtures=6 themes=2 modes=3")

func select_fixture(index: int, theme: int = 0) -> void:
	get_tree().paused = false
	if is_instance_valid(pause_panel): pause_panel.hide()
	for node in [combat,enemy,player,reveal,geometry]:
		if is_instance_valid(node):
			remove_child(node)
			node.queue_free()
	fixture_index = clampi(index,0,5)
	theme_index = clampi(theme,0,1)
	fixture_picker.select(fixture_index)
	theme_picker.select(theme_index)
	geometry = GEOMETRY.new()
	geometry.name = "PreparedArchitecture"
	geometry.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(geometry)
	geometry.build(fixture_index,theme_index)
	reveal = REVEAL.new()
	reveal.name = "ArchitecturalReveal"
	add_child(reveal)
	reveal.setup(geometry,theme_index)
	player = PLAYER.instantiate()
	player.set_script(LAB_PLAYER)
	player.name = "SlimePlayer"
	player.get_node("IsometricPresentation").set_script(PRESENTATION)
	player.position = geometry.spawn+Vector3.UP*0.05
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.presentation.room_cutaway = reveal
	player.presentation.zoom_target = 14.0
	player.presentation.camera.size = 14.0
	player.grant_ability(&"sticky_spit")
	combat = SlimeCombatRuntime.new()
	combat.name = "CombatRuntime"
	add_child(combat)
	combat.bind_player(player)
	enemy = ENEMY.instantiate()
	enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
	enemy.position = geometry.enemy_spawn+Vector3.UP*0.04
	add_child(enemy)
	combat.bind_enemy(enemy)
	set_combat(combat_enabled)
	set_mode(mode)
	reveal.support_y = geometry.spawn.y
	title_label.text = "Обзор пространства · " + TITLES[fixture_index]
	floor_button.visible = fixture_index==5

func reset_player(at: Vector3) -> void:
	player.global_position = at+Vector3.UP*0.04
	player.velocity = Vector3.ZERO
	player.clear_action_buffer()
	reveal.support_y = at.y
	player.presentation.floor_height = at.y
	player.presentation._update_camera(0.0)

func set_mode(value: int) -> void:
	mode = clampi(value,0,2)
	if is_instance_valid(reveal): reveal.set_enabled(mode==1)
	if is_instance_valid(player): player.presentation.higher_view = mode==2
	for i: int in mode_buttons.size(): mode_buttons[i].set_pressed_no_signal(i==mode)

func set_combat(active: bool) -> void:
	combat_enabled = active
	if is_instance_valid(enemy): enemy.set_physics_process(active)
	if is_instance_valid(combat_button): combat_button.set_pressed_no_signal(active)

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(player) or get_tree().paused: return
	if player.global_position.y < -3.0: reset_player(geometry.spawn)
	status.text = "Здоровье: %d  ·  %s" % [player.health,"Бой включён" if combat_enabled else "Враг стоит для сравнения"]
	if not player.is_alive(): status.text = "Слайм погиб · нажми «Сначала», чтобы повторить"

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		_toggle_pause()
		get_viewport().set_input_as_handled()

func _toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	pause_panel.visible = get_tree().paused
	player.cancel_absorb_for_pause()
	player.clear_action_buffer()

func _build_lighting() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("1b242b")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("b5c6cc")
	settings.ambient_light_energy = 0.35
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = settings
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-30,0)
	light.light_color = Color("ffe3bc")
	light.light_energy = 0.65
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 50
	add_child(light)

func _build_ui() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var panel := PanelContainer.new()
	panel.position = Vector2(16,12)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035,0.06,0.075,0.94)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel",style)
	hud.add_child(panel)
	var rows := VBoxContainer.new()
	panel.add_child(rows)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size",21)
	rows.add_child(title_label)
	var row := HBoxContainer.new()
	rows.add_child(row)
	var fixtures := OptionButton.new()
	fixture_picker = fixtures
	for text: String in TITLES: fixtures.add_item(text)
	fixtures.item_selected.connect(func(i: int) -> void: select_fixture(i,theme_index))
	row.add_child(fixtures)
	var themes := OptionButton.new()
	theme_picker = themes
	themes.add_item("Камень")
	themes.add_item("Дерево и металл")
	themes.item_selected.connect(func(i: int) -> void: select_fixture(fixture_index,i))
	row.add_child(themes)
	_button(row,"Сначала",func() -> void: select_fixture(fixture_index,theme_index))
	var modes := HBoxContainer.new()
	rows.add_child(modes)
	for i: int in 3:
		var button := _button(modes,["Полные стены","Цельное раскрытие","Камера выше"][i],func() -> void: set_mode(i))
		button.toggle_mode = true
		mode_buttons.append(button)
	var tools_row := HBoxContainer.new()
	rows.add_child(tools_row)
	combat_button = _button(tools_row,"Включить бой",func() -> void: set_combat(not combat_enabled))
	combat_button.toggle_mode = true
	floor_button = _button(tools_row,"Верх / низ",func() -> void: reset_player(geometry.upper_spawn if reveal.support_y<1.5 else geometry.spawn))
	_button(tools_row,"Повернуть ↶",func() -> void: player.presentation.request_quarter_turn(1))
	status = Label.new()
	rows.add_child(status)
	var footer := Label.new()
	footer.text = "WASD — движение · колёсико с жестом — поворот · прокрутка — масштаб\nЛКМ — хлыст · ПКМ — плевок · пробел удержать и отпустить — прыжок · Esc — пауза"
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	footer.position = Vector2(20,642)
	footer.add_theme_color_override("font_shadow_color",Color.BLACK)
	footer.add_theme_constant_override("shadow_offset_x",2)
	footer.add_theme_constant_override("shadow_offset_y",2)
	hud.add_child(footer)
	pause_panel = PanelContainer.new()
	pause_panel.position = Vector2(490,290)
	pause_panel.add_theme_stylebox_override("panel",style)
	hud.add_child(pause_panel)
	var pause_rows := VBoxContainer.new()
	pause_panel.add_child(pause_rows)
	var pause_title := Label.new()
	pause_title.text = "Пауза · проверка обзора"
	pause_rows.add_child(pause_title)
	_button(pause_rows,"Продолжить",_toggle_pause)
	pause_panel.hide()

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
