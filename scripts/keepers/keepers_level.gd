extends SlimeLevelWorkspace
class_name SlimeKeepersLevel

const GEOMETRY = preload("res://scripts/keepers/keepers_geometry.gd")
const LEVEL_SCENE := "res://scenes/keepers/keepers_level.tscn"
const ENTRY := Vector3(6.0, 0.045, 5.5)
const EXIT := Vector3(6.0, 0.65, -5.4)
const CAMERA_SIZE := 14.5

var geometry: Node3D
var finished := false
var camera_follow := true
var _hint: Label
var _objective: Label
var _ending: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	INPUT_SETUP.install()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_meta(&"isometric_dressing_owned", true)
	set_meta(&"isometric_exploration", true)
	geometry = GEOMETRY.new()
	geometry.name = "KeepersGeometry"
	geometry.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(geometry)
	geometry.build()
	player.presentation.room_cutaway = geometry.cutaway
	combat = SlimeCombatRuntime.new()
	combat.name = "CombatRuntime"
	add_child(combat)
	combat.bind_player(player)
	_build_ui()
	var hud := get_node("HUD")
	var title := hud.get_child(0) as Label
	title.name = "LevelTitle"
	title.text = "Котельная смотрителя"
	title.add_theme_font_override("font", preload("res://assets/ash-vault/CormorantGaramond.ttf"))
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color("f1d3a3"))
	_hint = hud.get_child(1) as Label
	_hint.name = "InteractionHint"
	_hint.add_theme_font_size_override("font_size", 17)
	_hint.add_theme_color_override("font_color", Color("dfd4bd"))
	_objective = Label.new()
	_objective.name = "LevelObjective"
	_objective.position = Vector2(25, 62)
	_objective.add_theme_font_size_override("font_size", 17)
	_objective.add_theme_color_override("font_color", Color("b9c9c5"))
	_objective.text = "Найди освещённую арку над водосбором"
	_objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_objective)
	_hud_shade(hud, false)
	_hud_shade(hud, true)
	_build_ending()
	respawn()


func _hud_shade(hud: CanvasLayer, bottom: bool) -> void:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.01, 0.015, 0.022, 0.85), Color(0.01, 0.015, 0.022, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 1) if bottom else Vector2.ZERO
	texture.fill_to = Vector2.ZERO if bottom else Vector2(0, 1)
	var shade := TextureRect.new()
	shade.name = "BottomShade" if bottom else "TitleShade"
	shade.texture = texture
	shade.anchor_right = 1.0
	shade.anchor_top = 1.0 if bottom else 0.0
	shade.anchor_bottom = shade.anchor_top
	shade.offset_top = -75 if bottom else 0
	shade.offset_bottom = 0 if bottom else 115
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(shade)
	hud.move_child(shade, 0)


func respawn() -> void:
	player.global_position = ENTRY
	player.velocity = Vector3.ZERO
	player.clear_action_buffer()
	player._ground_trail.clear_for_room_change()
	player._whip_visual._clear_contact()
	_update_room_camera()
	player.presentation.zoom_target = CAMERA_SIZE
	player.presentation.camera.size = CAMERA_SIZE
	player.presentation._update_camera(0.0)


func _update_room_camera() -> void:
	# This room has one principal floor. Jumps and the shallow basin do not
	# change camera height; clamped horizontal following keeps edges in view.
	var p := player.global_position
	var center := Vector3(clampf(p.x * 0.72, -3.5, 3.5), 0.6, clampf(p.z * 0.72, -2.8, 2.8))
	if not camera_follow:
		center = Vector3(0, 0.6, 0)
	set_meta(&"isometric_camera_center", center)


func _physics_process(_delta: float) -> void:
	if get_tree().paused or finished:
		return
	if player.global_position.y < -3.8:
		respawn()
	_update_room_camera()
	var near_exit := can_exit()
	_hint.text = "E — подняться к выходу" if near_exit else "WASD — движение · Пробел: удержать и отпустить — прыжок · ЛКМ — хлыст · Esc — пауза"
	if player.global_position.y < -0.3:
		_objective.text = "Из чаши ведёт пологий подъём между краями моста"
	elif player.global_position.z < -3.0:
		_objective.text = "Тёплый свет у арки. Выход уже рядом"
	else:
		_objective.text = "Обойди водосбор или срежь путь через разорванный мост"
	if near_exit and Input.is_action_just_pressed(&"interact"):
		_finish()


func can_exit() -> bool:
	var offset := player.global_position - EXIT
	return player.is_on_floor() and Vector2(offset.x, offset.z).length() < 1.05 and absf(offset.y) < 0.22 and player._action == &""


func _input(event: InputEvent) -> void:
	if not finished:
		super._input(event)


func _notification(what: int) -> void:
	if not finished:
		super._notification(what)


func _build_ending() -> void:
	_ending = ColorRect.new()
	_ending.name = "KeepersEnd"
	_ending.color = Color(0.018, 0.026, 0.032, 0.91)
	_ending.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ending.hide()
	get_node("HUD").add_child(_ending)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.position = Vector2(-250, -135)
	box.size = Vector2(500, 270)
	box.add_theme_constant_override("separation", 20)
	_ending.add_child(box)
	var caption := Label.new()
	caption.name = "EndingCaption"
	caption.text = "Над котельной — свежий воздух.\nЕщё немного ближе к своим."
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 27)
	caption.add_theme_color_override("font_color", Color("f1d3a3"))
	box.add_child(caption)
	var replay := Button.new()
	replay.name = "KeepersReplayButton"
	replay.text = "Пройти ещё раз"
	replay.custom_minimum_size.y = 48
	replay.pressed.connect(_restart)
	box.add_child(replay)
	var menu := Button.new()
	menu.name = "KeepersMenuButton"
	menu.text = "В меню"
	menu.custom_minimum_size.y = 48
	menu.pressed.connect(func() -> void: _pause_panel._go_to_menu())
	box.add_child(menu)


func _restart() -> void:
	get_tree().paused = false
	var error := get_tree().change_scene_to_file(LEVEL_SCENE)
	if error != OK:
		get_tree().paused = true
		(_ending.find_child("EndingCaption", true, false) as Label).text = "Не удалось повторить уровень.\nМожно вернуться в меню."
		push_error("Could not restart keepers level: %d" % error)


func _finish() -> void:
	finished = true
	player.clear_action_buffer()
	_ending.show()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
